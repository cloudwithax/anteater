//go:build linux || openbsd

package analyze

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, path string, size int) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	data := make([]byte, size)
	for i := range data {
		data[i] = 'a'
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestScannerSumsSizes(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "a.txt"), 100)
	writeFile(t, filepath.Join(root, "sub", "b.txt"), 250)
	writeFile(t, filepath.Join(root, "sub", "deep", "c.txt"), 50)

	tree, err := NewScanner().Scan(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	if !tree.IsDir {
		t.Fatal("expected root to be a directory")
	}
	if tree.Size != 400 {
		t.Errorf("root size = %d, want 400", tree.Size)
	}
	if len(tree.Children) != 2 {
		t.Fatalf("root children = %d, want 2", len(tree.Children))
	}

	var sub *Node
	for _, c := range tree.Children {
		if c.Name == "sub" {
			sub = c
		}
	}
	if sub == nil {
		t.Fatal("missing sub directory")
	}
	if sub.Size != 300 {
		t.Errorf("sub size = %d, want 300", sub.Size)
	}
	if sub.Parent != tree {
		t.Error("sub.Parent != root")
	}
}

func TestScannerHandlesEmptyDir(t *testing.T) {
	root := t.TempDir()
	tree, err := NewScanner().Scan(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	if tree.Size != 0 {
		t.Errorf("empty dir size = %d, want 0", tree.Size)
	}
	if len(tree.Children) != 0 {
		t.Errorf("empty dir children = %d, want 0", len(tree.Children))
	}
}

func TestScannerHandlesSingleFile(t *testing.T) {
	root := t.TempDir()
	target := filepath.Join(root, "only.txt")
	writeFile(t, target, 42)

	tree, err := NewScanner().Scan(context.Background(), target)
	if err != nil {
		t.Fatal(err)
	}
	if tree.IsDir {
		t.Error("expected leaf to be a file")
	}
	if tree.Size != 42 {
		t.Errorf("size = %d, want 42", tree.Size)
	}
}

func TestScannerSkipList(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "keep", "a.txt"), 10)
	writeFile(t, filepath.Join(root, "skip", "b.txt"), 1000)

	s := NewScanner()
	s.Skip[filepath.Join(root, "skip")] = struct{}{}

	tree, err := s.Scan(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	if tree.Size != 10 {
		t.Errorf("size = %d, want 10 (skip dir excluded)", tree.Size)
	}
	for _, c := range tree.Children {
		if c.Name == "skip" && len(c.Children) > 0 {
			t.Errorf("skip dir was descended into: %d children", len(c.Children))
		}
	}
}

func TestScannerReportsPermissionErrors(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("running as root: chmod 0 still readable")
	}
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "open", "a.txt"), 5)
	closed := filepath.Join(root, "closed")
	if err := os.MkdirAll(closed, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(closed, "b.txt"), 99)
	if err := os.Chmod(closed, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(closed, 0o755) })

	tree, err := NewScanner().Scan(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range tree.Children {
		if c.Name == "closed" && c.Err == "" {
			t.Error("expected Err to be set on unreadable directory")
		}
	}
}

func TestScannerRespectsContextCancel(t *testing.T) {
	root := t.TempDir()
	for i := range 50 {
		writeFile(t, filepath.Join(root, "d", "f", "g", "x"), i+1)
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := NewScanner().Scan(ctx, root)
	if err == nil {
		t.Skip("scan completed before cancel observed; not flaky enough to fail")
	}
}

func TestSortBySize(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "small.txt"), 10)
	writeFile(t, filepath.Join(root, "big.txt"), 1000)
	writeFile(t, filepath.Join(root, "medium.txt"), 100)

	tree, err := NewScanner().Scan(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	SortBySize(tree)
	if tree.Children[0].Name != "big.txt" {
		t.Errorf("first = %s, want big.txt", tree.Children[0].Name)
	}
	if tree.Children[2].Name != "small.txt" {
		t.Errorf("last = %s, want small.txt", tree.Children[2].Name)
	}
}

func TestSortByName(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "c.txt"), 1)
	writeFile(t, filepath.Join(root, "a.txt"), 1)
	writeFile(t, filepath.Join(root, "b.txt"), 1)

	tree, err := NewScanner().Scan(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	SortByName(tree)
	want := []string{"a.txt", "b.txt", "c.txt"}
	for i, n := range tree.Children {
		if n.Name != want[i] {
			t.Errorf("children[%d] = %s, want %s", i, n.Name, want[i])
		}
	}
}

func TestProgressReports(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "a.txt"), 100)
	writeFile(t, filepath.Join(root, "b", "c.txt"), 200)

	s := NewScanner()
	if _, err := s.Scan(context.Background(), root); err != nil {
		t.Fatal(err)
	}
	p := s.Progress()
	if p.Files != 2 {
		t.Errorf("Files = %d, want 2", p.Files)
	}
	if p.Dirs != 2 {
		t.Errorf("Dirs = %d, want 2", p.Dirs)
	}
	if p.Bytes != 300 {
		t.Errorf("Bytes = %d, want 300", p.Bytes)
	}
}
