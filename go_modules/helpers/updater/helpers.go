package updater

import (
	"strings"

	"golang.org/x/mod/modfile"
)

// Private methods lifted from the `modfile` package

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
		// Insert at beginning of existing comment.
		com := &line.Suffix[0]
		space := " "
		if len(com.Token) > 2 && com.Token[2] == ' ' || com.Token[2] == '\t' {
			space = ""
		}
		com.Token = "// indirect;" + space + com.Token[2:]
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
	f := strings.Fields(line.Suffix[0].Token)
	return (len(f) == 2 && f[1] == "indirect" || len(f) > 2 && f[1] == "indirect;") && f[0] == "//"
}
