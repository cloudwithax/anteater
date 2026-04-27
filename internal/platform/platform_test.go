//go:build linux || openbsd

package platform

import (
	"os"
	"path/filepath"
	"testing"
)

func writeFixture(t *testing.T, name, body string) string {
	t.Helper()
	dir := t.TempDir()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatalf("write %s: %v", p, err)
	}
	return p
}

func TestReadKeyValueFile(t *testing.T) {
	body := `# comment line
ID=cachyos
ID_LIKE=arch
PRETTY_NAME="CachyOS"
NAME='Cachy Linux'
VERSION_ID=
EMPTY_KEY=
=novalue

ANSI_COLOR="38;2;23;147;209"
`
	p := writeFixture(t, "os-release", body)
	got := readKeyValueFile(p)

	want := map[string]string{
		"ID":          "cachyos",
		"ID_LIKE":     "arch",
		"PRETTY_NAME": "CachyOS",
		"NAME":        "Cachy Linux",
		"VERSION_ID":  "",
		"EMPTY_KEY":   "",
		"ANSI_COLOR":  "38;2;23;147;209",
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("key %q: got %q want %q", k, got[k], v)
		}
	}
	if _, ok := got["=novalue"]; ok {
		t.Errorf("malformed line should not produce a key")
	}
}

func TestReadKeyValueFileMissing(t *testing.T) {
	got := readKeyValueFile("/nonexistent/path/os-release")
	if len(got) != 0 {
		t.Errorf("missing file should yield empty map, got %v", got)
	}
}

func TestPopulateLinuxFromFixture(t *testing.T) {
	cases := []struct {
		name        string
		body        string
		wantID      string
		wantLike    []string
		wantVersion string
		wantOSName  string
	}{
		{
			name: "cachyos",
			body: `ID=cachyos
ID_LIKE=arch
PRETTY_NAME="CachyOS"
`,
			wantID:     "cachyos",
			wantLike:   []string{"arch"},
			wantOSName: "CachyOS",
		},
		{
			name: "ubuntu",
			body: `ID=ubuntu
ID_LIKE=debian
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04 LTS"
`,
			wantID:      "ubuntu",
			wantLike:    []string{"debian"},
			wantVersion: "24.04",
			wantOSName:  "Ubuntu 24.04 LTS",
		},
		{
			name: "fedora",
			body: `ID=fedora
VERSION_ID=40
PRETTY_NAME="Fedora Linux 40 (Workstation Edition)"
`,
			wantID:      "fedora",
			wantVersion: "40",
			wantOSName:  "Fedora Linux 40 (Workstation Edition)",
		},
		{
			name: "rhel-multi-id-like",
			body: `ID=rocky
ID_LIKE="rhel centos fedora"
VERSION_ID="9.4"
PRETTY_NAME="Rocky Linux 9.4 (Blue Onyx)"
`,
			wantID:      "rocky",
			wantLike:    []string{"rhel", "centos", "fedora"},
			wantVersion: "9.4",
			wantOSName:  "Rocky Linux 9.4 (Blue Onyx)",
		},
		{
			name:       "empty falls back to unknown",
			body:       ``,
			wantID:     "unknown",
			wantOSName: "unknown",
		},
		{
			name: "name-only fallback when PRETTY_NAME absent",
			body: `ID=alpine
NAME="Alpine Linux"
`,
			wantID:     "alpine",
			wantOSName: "Alpine Linux",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			path := writeFixture(t, "os-release", tc.body)
			t.Setenv("ANTEATER_PLATFORM_OS_RELEASE_FILE", path)

			info := Info{OS: Linux}
			populateLinux(&info)

			if info.DistroID != tc.wantID {
				t.Errorf("DistroID: got %q want %q", info.DistroID, tc.wantID)
			}
			if !equalSlices(info.DistroLike, tc.wantLike) {
				t.Errorf("DistroLike: got %v want %v", info.DistroLike, tc.wantLike)
			}
			if info.DistroVersion != tc.wantVersion {
				t.Errorf("DistroVersion: got %q want %q", info.DistroVersion, tc.wantVersion)
			}
			if info.OSName != tc.wantOSName {
				t.Errorf("OSName: got %q want %q", info.OSName, tc.wantOSName)
			}
		})
	}
}

func TestPopulateOpenBSD(t *testing.T) {
	info := Info{OS: OpenBSD}
	populateOpenBSD(&info)
	if info.DistroID != "openbsd" {
		t.Errorf("DistroID: got %q want openbsd", info.DistroID)
	}
	if info.OSName == "" || info.OSName == "OpenBSD " {
		t.Errorf("OSName should include version: got %q", info.OSName)
	}
}

func TestDistroIs(t *testing.T) {
	info := Info{
		DistroID:   "cachyos",
		DistroLike: []string{"arch"},
	}
	if !info.DistroIs("cachyos") {
		t.Error("DistroIs should match exact ID")
	}
	if !info.DistroIs("arch") {
		t.Error("DistroIs should match ID_LIKE entry")
	}
	if info.DistroIs("debian") {
		t.Error("DistroIs should not match unrelated id")
	}
}

func TestHasPkgMgr(t *testing.T) {
	info := Info{PackageManager: []string{"pacman", "flatpak", "yay"}}
	if !info.HasPkgMgr("pacman") {
		t.Error("HasPkgMgr should match pacman")
	}
	if info.HasPkgMgr("apt") {
		t.Error("HasPkgMgr should not match absent manager")
	}
}

func TestInitIs(t *testing.T) {
	info := Info{Init: "systemd"}
	if !info.InitIs("systemd") {
		t.Error("InitIs systemd should match")
	}
	if info.InitIs("openrc") {
		t.Error("InitIs openrc should not match systemd")
	}
}

func TestOSKindString(t *testing.T) {
	cases := map[OSKind]string{
		Linux:     "linux",
		OpenBSD:   "openbsd",
		OSUnknown: "unknown",
	}
	for k, want := range cases {
		if got := k.String(); got != want {
			t.Errorf("OSKind(%d).String() = %q, want %q", k, got, want)
		}
	}
}

func TestDetectFreshOnHost(t *testing.T) {
	// Sanity: live detection should produce a non-empty arch/kernel.
	info := DetectFresh()
	if info.Arch == "" || info.Arch == "unknown" {
		t.Errorf("Arch should be detected on host: got %q", info.Arch)
	}
	if info.Kernel == "" || info.Kernel == "unknown" {
		t.Errorf("Kernel should be detected on host: got %q", info.Kernel)
	}
	if info.OS != Linux && info.OS != OpenBSD {
		t.Errorf("OS should resolve to a supported kind on host: got %v", info.OS)
	}
}

func equalSlices(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
