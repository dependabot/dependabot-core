package updater

import (
	"fmt"
	"go/format"
	"os"
	"strings"

	"golang.org/x/mod/modfile"
	"golang.org/x/tools/go/ast/astutil"
	"golang.org/x/tools/go/packages"
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

func updateImportPath(p *packages.Package, old, new string, files map[string]struct{}) ([]string, error) {
	updated := []string{}

	for _, syn := range p.Syntax {
		goFileName := p.Fset.File(syn.Pos()).Name()
		if _, ok := files[goFileName]; ok {
			continue
		}
		files[goFileName] = struct{}{}
		var rewritten bool
		for _, i := range syn.Imports {
			imp := strings.Replace(i.Path.Value, `"`, ``, 2)
			if strings.HasPrefix(imp, fmt.Sprintf("%s/", old)) || imp == old {
				newImp := strings.Replace(imp, old, new, 1)
				rewrote := astutil.RewriteImport(p.Fset, syn, imp, newImp)
				if rewrote {
					updated = append(updated, goFileName)
					rewritten = true
				}
			}
		}
		if !rewritten {
			continue
		}

		f, err := os.Create(goFileName)
		if err != nil {
			return updated, err
		}
		err = format.Node(f, p.Fset, syn)
		f.Close()
		if err != nil {
			return updated, err
		}
	}

	return updated, nil
}
