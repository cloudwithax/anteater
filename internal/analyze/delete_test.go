//go:build linux || openbsd

package analyze

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestDeleteNodeRemovesAndUpdatesParents(t *testing.T) {
	home := t.TempDir()
	writeFile(t, filepath.Join(home, "keep.txt"), 100)
	writeFile(t, filepath.Join(home, "junk", "big.bin"), 5000)

	tree, err := NewScanner().Scan(context.Background(), home)
	if err != nil {
		t.Fatal(err)
	}
	originalSize := tree.Size

	var junk *Node
	for _, c := range tree.Children {
		if c.Name == "junk" {
			junk = c
		}
	}
	if junk == nil {
		t.Fatal("junk not found")
	}
	freed := junk.Size

	if err := DeleteNode(junk, home); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(filepath.Join(home, "junk")); !os.IsNotExist(err) {
		t.Errorf("junk still exists: %v", err)
	}
	for _, c := range tree.Children {
		if c.Name == "junk" {
			t.Error("junk still in tree.Children")
		}
	}
	if tree.Size != originalSize-freed {
		t.Errorf("tree.Size = %d, want %d", tree.Size, originalSize-freed)
	}
}

func TestDeleteNodeRefusesPathOutsideHome(t *testing.T) {
	home := t.TempDir()
	other := t.TempDir()
	writeFile(t, filepath.Join(other, "x.txt"), 10)

	n := &Node{Path: filepath.Join(other, "x.txt")}
	err := DeleteNode(n, home)
	if !errors.Is(err, ErrPathOutsideHome) {
		t.Errorf("err = %v, want ErrPathOutsideHome", err)
	}
	if _, err := os.Stat(filepath.Join(other, "x.txt")); err != nil {
		t.Errorf("file should still exist: %v", err)
	}
}

func TestDeleteNodeRefusesHome(t *testing.T) {
	home := t.TempDir()
	n := &Node{Path: home}
	err := DeleteNode(n, home)
	if !errors.Is(err, ErrPathProtected) {
		t.Errorf("err = %v, want ErrPathProtected", err)
	}
	if _, err := os.Stat(home); err != nil {
		t.Errorf("HOME should still exist: %v", err)
	}
}

func TestDeleteNodeRefusesProtected(t *testing.T) {
	for path := range ProtectedPaths {
		err := DeleteNode(&Node{Path: path}, "/tmp")
		if err == nil {
			t.Errorf("%s: err = nil, want non-nil", path)
		}
	}
}
