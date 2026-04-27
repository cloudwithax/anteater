//go:build linux || openbsd

// Command aa-analyze is the bubbletea TUI behind `aa analyze`.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/cloudwithax/anteater/internal/analyze"
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, `aa-analyze - browse disk usage by directory

Usage: aa-analyze [path]

If no path is given, scans $HOME.

Keys:
  j/k or ↑↓     move cursor
  l/→/⏎         descend into directory
  h/←/Backspace ascend
  s             toggle sort (size/name)
  d             delete selected entry (HOME-restricted, with confirmation)
  g/G           jump to top/bottom
  q             quit
`)
	}
	flag.Parse()

	target, err := resolveTarget(flag.Arg(0))
	if err != nil {
		fmt.Fprintln(os.Stderr, "aa-analyze:", err)
		os.Exit(1)
	}

	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		fmt.Fprintln(os.Stderr, "aa-analyze: cannot determine HOME")
		os.Exit(1)
	}

	model := analyze.NewModel(target, home)
	if _, err := tea.NewProgram(model, tea.WithAltScreen()).Run(); err != nil {
		fmt.Fprintln(os.Stderr, "aa-analyze:", err)
		os.Exit(1)
	}
}

func resolveTarget(arg string) (string, error) {
	if arg == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		return home, nil
	}
	abs, err := filepath.Abs(arg)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(abs); err != nil {
		return "", err
	}
	return abs, nil
}
