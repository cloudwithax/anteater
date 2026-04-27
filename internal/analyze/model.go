//go:build linux || openbsd

package analyze

import (
	"context"
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// SortMode controls how a directory's children are ordered.
type SortMode int

const (
	SortSize SortMode = iota
	SortName
)

// scanDoneMsg fires when the background scan completes.
type scanDoneMsg struct {
	root *Node
	err  error
}

// progressTickMsg fires on a timer while scanning.
type progressTickMsg struct{}

// Model is the bubbletea model for `aa analyze`.
type Model struct {
	scanner   *Scanner
	rootPath  string
	home      string
	root      *Node
	current   *Node
	cursor    int
	scrollTop int
	sortMode  SortMode
	scanning  bool
	scanErr   error
	width     int
	height    int

	// confirm-delete dialog state
	deletePending *Node
	deleteErr     string
	statusMsg     string
	statusUntil   time.Time

	cancel context.CancelFunc
}

// NewModel returns a Model ready to be passed to tea.NewProgram.
func NewModel(path, home string) *Model {
	return &Model{
		scanner:  NewScanner(),
		rootPath: path,
		home:     home,
		sortMode: SortSize,
		scanning: true,
	}
}

func (m *Model) Init() tea.Cmd {
	ctx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel
	return tea.Batch(
		m.runScan(ctx),
		tickProgress(),
	)
}

func (m *Model) runScan(ctx context.Context) tea.Cmd {
	return func() tea.Msg {
		root, err := m.scanner.Scan(ctx, m.rootPath)
		return scanDoneMsg{root: root, err: err}
	}
}

func tickProgress() tea.Cmd {
	return tea.Tick(150*time.Millisecond, func(time.Time) tea.Msg {
		return progressTickMsg{}
	})
}

func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.clampCursor()
		return m, nil

	case scanDoneMsg:
		m.scanning = false
		if msg.err != nil {
			m.scanErr = msg.err
			return m, nil
		}
		m.root = msg.root
		m.current = msg.root
		m.applySort()
		return m, nil

	case progressTickMsg:
		if m.scanning {
			return m, tickProgress()
		}
		return m, nil

	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m *Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.scanning {
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			if m.cancel != nil {
				m.cancel()
			}
			return m, tea.Quit
		}
		return m, nil
	}

	if m.deletePending != nil {
		switch msg.String() {
		case "y", "Y":
			err := DeleteNode(m.deletePending, m.home)
			m.deletePending = nil
			if err != nil {
				m.deleteErr = err.Error()
				m.flashStatus("Delete failed: " + err.Error())
			} else {
				m.flashStatus("Deleted")
				m.applySort()
				m.clampCursor()
			}
			return m, nil
		case "n", "N", "esc", "q":
			m.deletePending = nil
			return m, nil
		}
		return m, nil
	}

	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "j", "down":
		if m.current != nil && m.cursor < len(m.current.Children)-1 {
			m.cursor++
			m.adjustScroll()
		}
	case "k", "up":
		if m.cursor > 0 {
			m.cursor--
			m.adjustScroll()
		}
	case "g":
		m.cursor = 0
		m.scrollTop = 0
	case "G":
		if m.current != nil {
			m.cursor = len(m.current.Children) - 1
			if m.cursor < 0 {
				m.cursor = 0
			}
			m.adjustScroll()
		}
	case "l", "right", "enter":
		m.descend()
	case "h", "left", "backspace":
		m.ascend()
	case "s":
		if m.sortMode == SortSize {
			m.sortMode = SortName
		} else {
			m.sortMode = SortSize
		}
		m.applySort()
		m.cursor = 0
		m.scrollTop = 0
	case "d":
		m.beginDelete()
	}
	return m, nil
}

func (m *Model) descend() {
	if m.current == nil || len(m.current.Children) == 0 {
		return
	}
	target := m.current.Children[m.cursor]
	if !target.IsDir {
		return
	}
	m.current = target
	m.applySort()
	m.cursor = 0
	m.scrollTop = 0
}

func (m *Model) ascend() {
	if m.current == nil || m.current.Parent == nil {
		return
	}
	prev := m.current
	m.current = m.current.Parent
	m.applySort()
	// Restore cursor onto the directory we came from.
	for i, c := range m.current.Children {
		if c == prev {
			m.cursor = i
			break
		}
	}
	m.adjustScroll()
}

func (m *Model) beginDelete() {
	if m.current == nil || len(m.current.Children) == 0 {
		return
	}
	target := m.current.Children[m.cursor]
	m.deletePending = target
	m.deleteErr = ""
}

func (m *Model) applySort() {
	if m.current == nil {
		return
	}
	if m.sortMode == SortSize {
		SortBySize(m.current)
	} else {
		SortByName(m.current)
	}
}

func (m *Model) clampCursor() {
	if m.current == nil {
		return
	}
	if m.cursor >= len(m.current.Children) {
		m.cursor = len(m.current.Children) - 1
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
	m.adjustScroll()
}

func (m *Model) adjustScroll() {
	visible := m.visibleRows()
	if visible <= 0 {
		return
	}
	if m.cursor < m.scrollTop {
		m.scrollTop = m.cursor
	}
	if m.cursor >= m.scrollTop+visible {
		m.scrollTop = m.cursor - visible + 1
	}
	if m.scrollTop < 0 {
		m.scrollTop = 0
	}
}

func (m *Model) visibleRows() int {
	// header(1) + breadcrumb(1) + footer(2) = 4 reserved
	rows := m.height - 4
	if rows < 1 {
		return 1
	}
	return rows
}

func (m *Model) flashStatus(s string) {
	m.statusMsg = s
	m.statusUntil = time.Now().Add(2 * time.Second)
}

var (
	headerStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("12"))
	pathStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
	cursorStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("13"))
	dirStyle       = lipgloss.NewStyle().Foreground(lipgloss.Color("12"))
	sizeStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("10"))
	smallSizeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
	errStyle       = lipgloss.NewStyle().Foreground(lipgloss.Color("9"))
	helpStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
	confirmStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("11"))
)

func (m *Model) View() string {
	if m.scanErr != nil {
		return errStyle.Render("Scan failed: "+m.scanErr.Error()) + "\n"
	}
	if m.scanning {
		p := m.scanner.Progress()
		return headerStyle.Render("Scanning "+m.rootPath) + "\n" +
			fmt.Sprintf("  files: %d  dirs: %d  bytes: %s\n", p.Files, p.Dirs, HumanBytes(p.Bytes)) +
			helpStyle.Render("  press q to abort") + "\n"
	}

	var b strings.Builder
	b.WriteString(headerStyle.Render("aa analyze"))
	b.WriteString("  ")
	b.WriteString(sizeStyle.Render(HumanBytes(m.current.Size)))
	b.WriteString("\n")
	b.WriteString(pathStyle.Render(m.current.Path))
	b.WriteString("\n")

	visible := m.visibleRows()
	end := m.scrollTop + visible
	if end > len(m.current.Children) {
		end = len(m.current.Children)
	}

	if len(m.current.Children) == 0 {
		b.WriteString(helpStyle.Render("  (empty)\n"))
	}

	for i := m.scrollTop; i < end; i++ {
		c := m.current.Children[i]
		marker := "  "
		nameStyle := lipgloss.NewStyle()
		if c.IsDir {
			nameStyle = dirStyle
		}
		if i == m.cursor {
			marker = "▶ "
			nameStyle = cursorStyle
		}
		sizeText := HumanBytes(c.Size)
		sizePadded := fmt.Sprintf("%10s", sizeText)
		styledSize := sizeStyle.Render(sizePadded)
		if c.Size == 0 {
			styledSize = smallSizeStyle.Render(sizePadded)
		}
		name := c.Name
		if c.IsDir {
			name += "/"
		}
		line := fmt.Sprintf("%s%s  %s", marker, styledSize, nameStyle.Render(name))
		if c.Err != "" {
			line += "  " + errStyle.Render("("+c.Err+")")
		}
		b.WriteString(line + "\n")
	}

	// Status / footer
	footer := "↑↓ jk move  l/⏎ enter  h/← back  s sort  d delete  q quit"
	if m.deletePending != nil {
		dp := m.deletePending
		footer = fmt.Sprintf("Delete %s (%s)? [y/N]", dp.Path, HumanBytes(dp.Size))
		b.WriteString(confirmStyle.Render(footer) + "\n")
	} else if !m.statusUntil.IsZero() && time.Now().Before(m.statusUntil) {
		b.WriteString(helpStyle.Render(m.statusMsg) + "\n")
	} else {
		b.WriteString(helpStyle.Render(footer) + "\n")
	}
	return b.String()
}
