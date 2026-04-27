//go:build linux || openbsd

// Package platform provides OS / distro / init / package-manager / desktop
// fingerprinting for the *nix systems Anteater targets.
//
// Detect returns a populated Info; values are cached on first call.
// The DetectFresh form is provided for tests that need to re-run detection
// after manipulating environment variables or fixture files.
package platform

import (
	"bufio"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
)

type OSKind int

const (
	OSUnknown OSKind = iota
	Linux
	OpenBSD
)

func (k OSKind) String() string {
	switch k {
	case Linux:
		return "linux"
	case OpenBSD:
		return "openbsd"
	default:
		return "unknown"
	}
}

type Info struct {
	OS             OSKind
	OSName         string
	DistroID       string
	DistroLike     []string
	DistroVersion  string
	Init           string
	Desktop        string
	Arch           string
	Kernel         string
	PackageManager []string
}

// IsLinux reports whether the host is running a Linux kernel.
func (i Info) IsLinux() bool { return i.OS == Linux }

// IsOpenBSD reports whether the host is running OpenBSD.
func (i Info) IsOpenBSD() bool { return i.OS == OpenBSD }

// DistroIs matches against DistroID and any DistroLike entry.
func (i Info) DistroIs(id string) bool {
	if i.DistroID == id {
		return true
	}
	for _, l := range i.DistroLike {
		if l == id {
			return true
		}
	}
	return false
}

// HasPkgMgr returns true if name is in the detected package-manager list.
func (i Info) HasPkgMgr(name string) bool {
	for _, m := range i.PackageManager {
		if m == name {
			return true
		}
	}
	return false
}

// InitIs returns true if the detected init system equals name.
func (i Info) InitIs(name string) bool { return i.Init == name }

var (
	cached     Info
	cachedOnce sync.Once
)

// Detect returns a process-cached Info. Tests should use DetectFresh.
func Detect() Info {
	cachedOnce.Do(func() { cached = DetectFresh() })
	return cached
}

// DetectFresh re-runs detection, ignoring any cached value.
func DetectFresh() Info {
	osKind := detectOSKind()
	info := Info{OS: osKind}

	switch osKind {
	case Linux:
		populateLinux(&info)
	case OpenBSD:
		populateOpenBSD(&info)
	}

	info.Init = detectInit(osKind)
	info.Desktop = detectDesktop()
	info.Arch = unameOrUnknown("-m")
	info.Kernel = unameOrUnknown("-r")
	info.PackageManager = detectPackageManagers()
	return info
}

func detectOSKind() OSKind {
	switch runtime.GOOS {
	case "linux":
		return Linux
	case "openbsd":
		return OpenBSD
	default:
		return OSUnknown
	}
}

func populateLinux(info *Info) {
	osRelease := os.Getenv("ANTEATER_PLATFORM_OS_RELEASE_FILE")
	if osRelease == "" {
		osRelease = "/etc/os-release"
	}
	kv := readKeyValueFile(osRelease)

	info.DistroID = kv["ID"]
	if like := kv["ID_LIKE"]; like != "" {
		info.DistroLike = strings.Fields(like)
	}
	info.DistroVersion = kv["VERSION_ID"]
	info.OSName = kv["PRETTY_NAME"]
	if info.OSName == "" {
		info.OSName = kv["NAME"]
	}
	if info.DistroID == "" {
		info.DistroID = "unknown"
	}
	if info.OSName == "" {
		info.OSName = info.DistroID
	}
}

func populateOpenBSD(info *Info) {
	info.DistroID = "openbsd"
	info.DistroVersion = unameOrUnknown("-r")
	info.OSName = "OpenBSD " + info.DistroVersion
}

func detectInit(osKind OSKind) string {
	if osKind == OpenBSD {
		return "bsd-rc"
	}
	switch {
	case dirExists("/run/systemd/system"):
		return "systemd"
	case dirExists("/run/openrc"), executable("/sbin/openrc"), executable("/usr/sbin/openrc"):
		return "openrc"
	case dirExists("/run/runit"), executable("/usr/bin/runit"), executable("/sbin/runit"):
		return "runit"
	case dirExists("/run/s6"), dirExists("/run/s6-rc"):
		return "s6"
	case executable("/sbin/dinit"), executable("/usr/sbin/dinit"):
		return "dinit"
	default:
		return "unknown"
	}
}

func detectDesktop() string {
	d := os.Getenv("XDG_CURRENT_DESKTOP")
	if d == "" {
		d = os.Getenv("DESKTOP_SESSION")
	}
	if d == "" {
		return "unknown"
	}
	if i := strings.IndexByte(d, ':'); i >= 0 {
		d = d[:i]
	}
	return strings.ToLower(d)
}

// detectPackageManagers walks a fixed candidate list and returns those on PATH.
// Order in the result mirrors the candidate order, not PATH order.
func detectPackageManagers() []string {
	candidates := []struct {
		bin  string
		name string
	}{
		{"pacman", "pacman"},
		{"apt", "apt"},
		{"dnf", "dnf"},
		{"zypper", "zypper"},
		{"apk", "apk"},
		{"xbps-install", "xbps"},
		{"emerge", "emerge"},
		{"pkg_add", "pkg_add"},
		{"nix-env", "nix-env"},
		{"nix", "nix"},
		{"flatpak", "flatpak"},
		{"snap", "snap"},
		{"yay", "yay"},
		{"paru", "paru"},
	}
	out := make([]string, 0, len(candidates))
	for _, c := range candidates {
		if _, err := exec.LookPath(c.bin); err == nil {
			out = append(out, c.name)
		}
	}
	return out
}

// readKeyValueFile parses a freedesktop-style key=value file. Surrounding
// double or single quotes are stripped. Comment lines (#) are skipped.
// Returns an empty map on read errors so callers can plug in defaults.
func readKeyValueFile(path string) map[string]string {
	out := map[string]string{}
	f, err := os.Open(path)
	if err != nil {
		return out
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq := strings.IndexByte(line, '=')
		if eq <= 0 {
			continue
		}
		key := strings.TrimSpace(line[:eq])
		val := strings.TrimSpace(line[eq+1:])
		if len(val) >= 2 {
			if (val[0] == '"' && val[len(val)-1] == '"') ||
				(val[0] == '\'' && val[len(val)-1] == '\'') {
				val = val[1 : len(val)-1]
			}
		}
		out[key] = val
	}
	return out
}

func dirExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

func executable(p string) bool {
	st, err := os.Stat(p)
	if err != nil || st.IsDir() {
		return false
	}
	return st.Mode().Perm()&0o111 != 0
}

func unameOrUnknown(flag string) string {
	out, err := exec.Command("uname", flag).Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}
