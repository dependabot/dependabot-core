package manifest

import (
	"strings"
	"testing"

	"golang.org/x/mod/modfile"
	"golang.org/x/mod/module"
)

func TestRestoreReplacedRequirements(t *testing.T) {
	const original = `module example.com/root

go 1.21

require (
	// Kept for the unavailable sibling.
	example.com/direct v1.2.3 // sibling API
	example.com/indirect v1.4.0 // indirect
	example.com/public v1.0.0
	example.com/unmatched v1.0.0
	example.com/transitive v1.2.0 // indirect
)

replace example.com/direct => ../direct
`
	const updated = `module example.com/root

go 1.21

require (
	example.com/indirect v1.5.0
	example.com/public v1.1.0
	example.com/unmatched v1.1.0
)

replace example.com/direct => ../direct
`
	content, err := RestoreReplacedRequirements(RestoreRequirementsArgs{
		OriginalContent: original,
		UpdatedContent:  updated,
		ReplacedModules: []module.Version{
			{Path: "example.com/direct"},
			{Path: "example.com/indirect", Version: "v1.4.0"},
			{Path: "example.com/unmatched", Version: "v1.1.0"},
			{Path: "example.com/absent"},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := modfile.Parse("go.mod", []byte(content), nil)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]struct {
		version  string
		indirect bool
	}{
		"example.com/direct":     {"v1.2.3", false},
		"example.com/indirect":   {"v1.4.0", true},
		"example.com/public":     {"v1.1.0", false},
		"example.com/unmatched":  {"v1.1.0", false},
		"example.com/transitive": {"v1.2.0", true},
	}
	for _, requirement := range parsed.Require {
		expected, exists := want[requirement.Mod.Path]
		if !exists || requirement.Mod.Version != expected.version || requirement.Indirect != expected.indirect {
			t.Fatalf("unexpected requirement: %+v", requirement)
		}
		delete(want, requirement.Mod.Path)
	}
	if len(want) != 0 {
		t.Fatalf("missing requirements: %v", want)
	}
	for _, comment := range []string{"// Kept for the unavailable sibling.", "// sibling API", "// indirect"} {
		if !strings.Contains(content, comment) {
			t.Errorf("lost comment %q in %s", comment, content)
		}
	}
	if len(parsed.Replace) != 1 || parsed.Replace[0].New.Path != "../direct" {
		t.Fatalf("replacement changed: %+v", parsed.Replace)
	}
}

func TestRestoreReplacedRequirementsUnmatched(t *testing.T) {
	const content = "module example.com/root\n\nrequire example.com/public v1.1.0\n"
	result, err := RestoreReplacedRequirements(RestoreRequirementsArgs{
		OriginalContent: "module example.com/root\n",
		UpdatedContent:  content,
		ReplacedModules: []module.Version{{Path: "example.com/absent"}},
	})
	if err != nil || result != content {
		t.Fatalf("unmatched module changed: %q, %v", result, err)
	}
}

func TestRestoreReplacedRequirementsInvalid(t *testing.T) {
	for _, args := range []RestoreRequirementsArgs{
		{OriginalContent: "require", UpdatedContent: "module example.com/root\n"},
		{OriginalContent: "module example.com/root\n", UpdatedContent: "require"},
	} {
		if _, err := RestoreReplacedRequirements(args); err == nil {
			t.Fatal("invalid manifest accepted")
		}
	}
}
