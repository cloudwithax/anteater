//go:build linux || openbsd

// Package analyze provides the disk-usage scanner and bubbletea TUI behind
// `aa analyze`. The scanner walks a directory tree concurrently, building an
// in-memory node tree with per-directory totals (apparent size).
package analyze

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"sync/atomic"

	"golang.org/x/sync/errgroup"
)

// Node is one entry in the scanned tree.
type Node struct {
	Name      string
	Path      string
	Size      int64 // sum of self + descendants (apparent bytes)
	SelfSize  int64 // 0 for directories
	IsDir     bool
	IsSymlink bool
	Parent    *Node
	Children  []*Node
	Err       string // permission denied, etc.
}

// Progress is a snapshot of scanner state, safe to read concurrently.
type Progress struct {
	Files int64
	Dirs  int64
	Bytes int64
}

// Scanner walks a directory tree and produces a Node tree.
type Scanner struct {
	// Skip is the set of absolute paths to skip entirely. Defaults via NewScanner.
	Skip map[string]struct{}
	// Concurrency caps simultaneous directory reads. Defaults to 32.
	Concurrency int

	files atomic.Int64
	dirs  atomic.Int64
	bytes atomic.Int64
}

// DefaultSkip is the set of absolute paths the scanner refuses to descend
// into by default. These are pseudo or device filesystems where du-style
// accounting is meaningless or actively dangerous (e.g. /proc files reporting
// huge sparse sizes).
var DefaultSkip = []string{
	"/proc",
	"/sys",
	"/dev",
	"/run",
}

// NewScanner returns a Scanner with default skip set and concurrency.
func NewScanner() *Scanner {
	skip := make(map[string]struct{}, len(DefaultSkip))
	for _, p := range DefaultSkip {
		skip[p] = struct{}{}
	}
	return &Scanner{Skip: skip, Concurrency: 32}
}

// Progress returns a snapshot of scan progress so far.
func (s *Scanner) Progress() Progress {
	return Progress{
		Files: s.files.Load(),
		Dirs:  s.dirs.Load(),
		Bytes: s.bytes.Load(),
	}
}

// Scan walks root and returns the resulting tree. Returns an error only if
// root cannot be stat'd or the context is cancelled. Per-entry errors are
// recorded on the offending Node.
func (s *Scanner) Scan(ctx context.Context, root string) (*Node, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	info, err := os.Lstat(abs)
	if err != nil {
		return nil, err
	}

	rootNode := &Node{
		Name:      filepath.Base(abs),
		Path:      abs,
		IsDir:     info.IsDir(),
		IsSymlink: info.Mode()&os.ModeSymlink != 0,
	}

	if !rootNode.IsDir {
		rootNode.SelfSize = info.Size()
		rootNode.Size = info.Size()
		s.files.Add(1)
		s.bytes.Add(info.Size())
		return rootNode, nil
	}

	s.dirs.Add(1)

	concurrency := s.Concurrency
	if concurrency <= 0 {
		concurrency = 32
	}
	g, gctx := errgroup.WithContext(ctx)
	g.SetLimit(concurrency)

	s.walk(gctx, g, rootNode)

	if err := g.Wait(); err != nil && !errors.Is(err, context.Canceled) {
		return nil, err
	}

	computeSize(rootNode)
	return rootNode, nil
}

// walk builds the tree under dir. File sizes are recorded on each leaf;
// directory sizes are computed in a separate bottom-up pass after g.Wait.
func (s *Scanner) walk(ctx context.Context, g *errgroup.Group, dir *Node) {
	if ctx.Err() != nil {
		return
	}
	if _, skipped := s.Skip[dir.Path]; skipped {
		return
	}

	entries, err := os.ReadDir(dir.Path)
	if err != nil {
		dir.Err = err.Error()
		return
	}

	children := make([]*Node, 0, len(entries))
	for _, entry := range entries {
		full := filepath.Join(dir.Path, entry.Name())
		if _, skipped := s.Skip[full]; skipped {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			children = append(children, &Node{
				Name: entry.Name(), Path: full, Parent: dir, Err: err.Error(),
			})
			continue
		}
		isDir := entry.IsDir()
		isSymlink := info.Mode()&os.ModeSymlink != 0
		n := &Node{
			Name:      entry.Name(),
			Path:      full,
			IsDir:     isDir,
			IsSymlink: isSymlink,
			Parent:    dir,
		}
		if !isDir {
			if !isSymlink {
				n.SelfSize = info.Size()
				s.files.Add(1)
				s.bytes.Add(info.Size())
			}
			children = append(children, n)
			continue
		}
		s.dirs.Add(1)
		children = append(children, n)
		g.Go(func() error {
			s.walk(ctx, g, n)
			return nil
		})
	}
	dir.Children = children
}

// computeSize fills in Size for every directory node by recursing depth-first.
func computeSize(n *Node) int64 {
	if n == nil {
		return 0
	}
	if !n.IsDir {
		n.Size = n.SelfSize
		return n.SelfSize
	}
	var total int64
	for _, c := range n.Children {
		total += computeSize(c)
	}
	n.Size = total
	return total
}

// SortBySize sorts a node's immediate children largest-first (in place).
func SortBySize(n *Node) {
	if n == nil {
		return
	}
	sort.SliceStable(n.Children, func(i, j int) bool {
		return n.Children[i].Size > n.Children[j].Size
	})
}

// SortByName sorts a node's immediate children alphabetically (in place).
func SortByName(n *Node) {
	if n == nil {
		return
	}
	sort.SliceStable(n.Children, func(i, j int) bool {
		return n.Children[i].Name < n.Children[j].Name
	})
}
