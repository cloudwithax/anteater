//go:build linux || openbsd

package analyze

import "fmt"

// HumanBytes renders n in IEC-ish units matching the bash bytes_to_human:
// B, KB, MB, GB, TB. Decimals expand at higher units to keep the column tidy.
func HumanBytes(n int64) string {
	const (
		kb = 1024
		mb = 1024 * 1024
		gb = 1024 * 1024 * 1024
		tb = int64(1024) * 1024 * 1024 * 1024
	)
	switch {
	case n < kb:
		return fmt.Sprintf("%dB", n)
	case n < mb:
		return fmt.Sprintf("%dKB", n/kb)
	case n < gb:
		return fmt.Sprintf("%.1fMB", float64(n)/float64(mb))
	case n < tb:
		return fmt.Sprintf("%.2fGB", float64(n)/float64(gb))
	default:
		return fmt.Sprintf("%.2fTB", float64(n)/float64(tb))
	}
}
