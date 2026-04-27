//go:build linux || openbsd

package analyze

import "testing"

func TestHumanBytes(t *testing.T) {
	cases := []struct {
		in   int64
		want string
	}{
		{0, "0B"},
		{512, "512B"},
		{1024, "1KB"},
		{2048, "2KB"},
		{5 * 1024 * 1024, "5.0MB"},
		{int64(3) * 1024 * 1024 * 1024, "3.00GB"},
		{int64(2) * 1024 * 1024 * 1024 * 1024, "2.00TB"},
	}
	for _, c := range cases {
		if got := HumanBytes(c.in); got != c.want {
			t.Errorf("HumanBytes(%d) = %s, want %s", c.in, got, c.want)
		}
	}
}
