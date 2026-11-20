package manifest

import (
	"fmt"
	"sort"
	"strings"

	"golang.org/x/mod/module"
)

type RestoreChecksumsArgs struct {
	OriginalContent string `json:"original_content"`
	UpdatedContent  string `json:"updated_content"`
}

// RestoreChecksums retains the incomplete graph's entries in Go's checksum order.
func RestoreChecksums(args RestoreChecksumsArgs) (string, error) {
	sums := make(map[module.Version]map[string]bool)
	for _, content := range []string{args.OriginalContent, args.UpdatedContent} {
		for _, line := range strings.Split(content, "\n") {
			fields := strings.Fields(line)
			if len(fields) == 0 {
				continue
			}
			if len(fields) != 3 {
				return "", fmt.Errorf("malformed checksum entry: %q", line)
			}
			mod := module.Version{Path: fields[0], Version: fields[1]}
			if sums[mod] == nil {
				sums[mod] = make(map[string]bool)
			}
			sums[mod][fields[2]] = true
		}
	}
	mods := make([]module.Version, 0, len(sums))
	for mod := range sums {
		mods = append(mods, mod)
	}
	module.Sort(mods)
	var result strings.Builder
	for _, mod := range mods {
		hashes := make([]string, 0, len(sums[mod]))
		for hash := range sums[mod] {
			hashes = append(hashes, hash)
		}
		sort.Strings(hashes)
		for _, hash := range hashes {
			fmt.Fprintf(&result, "%s %s %s\n", mod.Path, mod.Version, hash)
		}
	}
	return result.String(), nil
}
