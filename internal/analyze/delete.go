//go:build linux || openbsd

package analyze

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

// ErrPathOutsideHome is returned when the caller tries to delete a node whose
// path is not under the user's HOME directory. analyze restricts deletions to
// HOME so it cannot be used to rm -rf system files.
var ErrPathOutsideHome = errors.New("refusing to delete path outside HOME")

// ErrPathProtected is returned when the path itself is HOME, /, or another
// path on the protected list.
var ErrPathProtected = errors.New("refusing to delete protected path")

// ProtectedPaths is the set of absolute paths that DeleteNode always refuses
// to remove regardless of HOME containment.
var ProtectedPaths = map[string]struct{}{
	"/":     {},
	"/etc":  {},
	"/usr":  {},
	"/var":  {},
	"/boot": {},
	"/home": {},
	"/root": {},
}

// DeleteNode removes the path backing n after safety checks. It refuses any
// path that is not strictly inside the user's HOME, and refuses HOME itself
// and a small list of protected paths. On success the node is detached from
// its parent's Children slice.
func DeleteNode(n *Node, home string) error {
	if n == nil {
		return errors.New("nil node")
	}
	if home == "" {
		return errors.New("empty HOME")
	}

	abs, err := filepath.Abs(n.Path)
	if err != nil {
		return err
	}
	homeAbs, err := filepath.Abs(home)
	if err != nil {
		return err
	}

	if _, protected := ProtectedPaths[abs]; protected {
		return ErrPathProtected
	}
	if abs == homeAbs {
		return ErrPathProtected
	}

	rel, err := filepath.Rel(homeAbs, abs)
	if err != nil || rel == "." || rel == "" || strings.HasPrefix(rel, "..") {
		return ErrPathOutsideHome
	}

	if err := os.RemoveAll(abs); err != nil {
		return err
	}

	if n.Parent != nil {
		out := n.Parent.Children[:0]
		for _, c := range n.Parent.Children {
			if c != n {
				out = append(out, c)
			}
		}
		n.Parent.Children = out

		// Propagate freed bytes up to ancestors.
		freed := n.Size
		for p := n.Parent; p != nil; p = p.Parent {
			p.Size -= freed
		}
	}
	return nil
}
