//go:build linux || openbsd

package platform

import (
	"os"
	"testing"
)

// withClearedEnv runs fn with HOME and XDG_*_HOME unset/forced and TMPDIR
// preserved or cleared per the caller's needs.
func withEnv(t *testing.T, env map[string]string, fn func()) {
	t.Helper()
	keys := []string{"HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "TMPDIR"}
	for _, k := range keys {
		if v, ok := env[k]; ok {
			t.Setenv(k, v)
		} else {
			os.Unsetenv(k)
		}
	}
	fn()
}

func TestXDGDefaultsFromHome(t *testing.T) {
	tmp := t.TempDir()
	withEnv(t, map[string]string{"HOME": tmp}, func() {
		x := XDGDirs()
		want := map[string]string{
			"ConfigHome": tmp + "/.config",
			"CacheHome":  tmp + "/.cache",
			"DataHome":   tmp + "/.local/share",
			"StateHome":  tmp + "/.local/state",
		}
		got := map[string]string{
			"ConfigHome": x.ConfigHome,
			"CacheHome":  x.CacheHome,
			"DataHome":   x.DataHome,
			"StateHome":  x.StateHome,
		}
		for k, w := range want {
			if got[k] != w {
				t.Errorf("%s: got %q want %q", k, got[k], w)
			}
		}
	})
}

func TestXDGOverridesAreRespected(t *testing.T) {
	tmp := t.TempDir()
	withEnv(t, map[string]string{
		"HOME":            tmp,
		"XDG_CONFIG_HOME": "/custom/cfg",
		"XDG_CACHE_HOME":  "/custom/cache",
		"XDG_DATA_HOME":   "/custom/data",
		"XDG_STATE_HOME":  "/custom/state",
	}, func() {
		x := XDGDirs()
		if x.ConfigHome != "/custom/cfg" {
			t.Errorf("ConfigHome override missed: %q", x.ConfigHome)
		}
		if x.CacheHome != "/custom/cache" {
			t.Errorf("CacheHome override missed: %q", x.CacheHome)
		}
		if x.DataHome != "/custom/data" {
			t.Errorf("DataHome override missed: %q", x.DataHome)
		}
		if x.StateHome != "/custom/state" {
			t.Errorf("StateHome override missed: %q", x.StateHome)
		}
	})
}

func TestAnteaterDirsLayoutDefault(t *testing.T) {
	tmp := t.TempDir()
	withEnv(t, map[string]string{"HOME": tmp}, func() {
		want := map[string]string{
			"config": tmp + "/.config/anteater",
			"cache":  tmp + "/.cache/anteater",
			"data":   tmp + "/.local/share/anteater",
			"state":  tmp + "/.local/state/anteater",
			"log":    tmp + "/.local/state/anteater/logs",
			"trash":  tmp + "/.local/share/Trash",
		}
		got := map[string]string{
			"config": ConfigDir(),
			"cache":  CacheDir(),
			"data":   DataDir(),
			"state":  StateDir(),
			"log":    LogDir(),
			"trash":  TrashDir(),
		}
		for k, w := range want {
			if got[k] != w {
				t.Errorf("%s: got %q want %q", k, got[k], w)
			}
		}
	})
}

func TestUserHomeReturnsHome(t *testing.T) {
	tmp := t.TempDir()
	withEnv(t, map[string]string{"HOME": tmp}, func() {
		h, err := UserHome()
		if err != nil {
			t.Fatalf("UserHome err: %v", err)
		}
		if h != tmp {
			t.Errorf("got %q want %q", h, tmp)
		}
	})
}

func TestUserHomeErrorsWhenUnset(t *testing.T) {
	withEnv(t, map[string]string{}, func() {
		if _, err := UserHome(); err == nil {
			t.Fatal("UserHome should error when HOME is unset")
		}
	})
}
