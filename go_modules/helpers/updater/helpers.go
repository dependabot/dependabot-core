package updater

import (
	"strings"

	"golang.org/x/mod/modfile"
)

// Private methods lifted from the `modfile` package.
// Last synced: 4/28/2021 from:
// https://github.com/golang/mod/blob/858fdbee9c245c8109c359106e89c6b8d321f19c/modfile/rule.go

var slashSlash = []byte("//")

// setIndirect sets line to have (or not have) a "// indirect" comment.
func setIndirect(line *modfile.Line, indirect bool) {
	if isIndirect(line) == indirect {
		return
	}
	if indirect {
		// Adding comment.
		if len(line.Suffix) == 0 {
			// New comment.
			line.Suffix = []modfile.Comment{{Token: "// indirect", Suffix: true}}
			return
		}

		com := &line.Suffix[0]
		text := strings.TrimSpace(strings.TrimPrefix(com.Token, string(slashSlash)))
		if text == "" {
			// Empty comment.
			com.Token = "// indirect"
			return
		}

		// Insert at beginning of existing comment.
		com.Token = "// indirect; " + text
		return
	}

	// Removing comment.
	f := strings.Fields(line.Suffix[0].Token)
	if len(f) == 2 {
		// Remove whole comment.
		line.Suffix = nil
		return
	}

	// Remove comment prefix.
	com := &line.Suffix[0]
	i := strings.Index(com.Token, "indirect;")
	com.Token = "//" + com.Token[i+len("indirect;"):]
}

// isIndirect reports whether line has a "// indirect" comment,
// meaning it is in go.mod only for its effect on indirect dependencies,
// so that it can be dropped entirely once the effective version of the
// indirect dependency reaches the given minimum version.
func isIndirect(line *modfile.Line) bool {
	if len(line.Suffix) == 0 {
		return false
	}
	f := strings.Fields(strings.TrimPrefix(line.Suffix[0].Token, string(slashSlash)))
	return (len(f) == 1 && f[0] == "indirect" || len(f) > 1 && f[0] == "indirect;")
}
