//go:build linux || openbsd

package platform

import (
	"errors"
	"os"
	"path/filepath"
)

// XDG returns resolved XDG base directories with default fallbacks.
type XDG struct {
	ConfigHome string // $XDG_CONFIG_HOME or $HOME/.config
	CacheHome  string // $XDG_CACHE_HOME  or $HOME/.cache
	DataHome   string // $XDG_DATA_HOME   or $HOME/.local/share
	StateHome  string // $XDG_STATE_HOME  or $HOME/.local/state
}

// XDGDirs resolves the XDG base directory chain. If $HOME is unset and
// XDG_*_HOME env vars are also unset, the corresponding fields are empty.
func XDGDirs() XDG {
	home, _ := UserHome()
	return XDG{
		ConfigHome: envOrJoin("XDG_CONFIG_HOME", home, ".config"),
		CacheHome:  envOrJoin("XDG_CACHE_HOME", home, ".cache"),
		DataHome:   envOrJoin("XDG_DATA_HOME", home, ".local", "share"),
		StateHome:  envOrJoin("XDG_STATE_HOME", home, ".local", "state"),
	}
}

// ConfigDir returns Anteater's per-user config directory.
func ConfigDir() string { return filepath.Join(XDGDirs().ConfigHome, "anteater") }

// CacheDir returns Anteater's per-user cache directory.
func CacheDir() string { return filepath.Join(XDGDirs().CacheHome, "anteater") }

// DataDir returns Anteater's per-user data directory.
func DataDir() string { return filepath.Join(XDGDirs().DataHome, "anteater") }

// StateDir returns Anteater's per-user state directory (logs, deletion
// records, recoverable runtime state).
func StateDir() string { return filepath.Join(XDGDirs().StateHome, "anteater") }

// LogDir returns Anteater's per-user log directory.
func LogDir() string { return filepath.Join(StateDir(), "logs") }

// TrashDir returns the FreeDesktop trash root.
func TrashDir() string { return filepath.Join(XDGDirs().DataHome, "Trash") }

// UserHome returns $HOME, or an error if unset. Mirrors os.UserHomeDir but
// uses anteater-specific error wording for clearer log lines.
func UserHome() (string, error) {
	if h := os.Getenv("HOME"); h != "" {
		return h, nil
	}
	return "", errors.New("anteater: $HOME is not set")
}

func envOrJoin(envKey, base string, parts ...string) string {
	if v := os.Getenv(envKey); v != "" {
		return v
	}
	if base == "" {
		return ""
	}
	return filepath.Join(append([]string{base}, parts...)...)
}
