package manifest

import (
	"fmt"

	"golang.org/x/mod/modfile"
	"golang.org/x/mod/module"
)

type RestoreRequirementsArgs struct {
	OriginalContent string           `json:"original_content"`
	UpdatedContent  string           `json:"updated_content"`
	ReplacedModules []module.Version `json:"replaced_modules"`
}

// RestoreReplacedRequirements retains requirements when the source graph is
// incomplete. Empty replacements cannot prove that a requirement is unused.
func RestoreReplacedRequirements(args RestoreRequirementsArgs) (string, error) {
	original, err := modfile.Parse("original go.mod", []byte(args.OriginalContent), nil)
	if err != nil {
		return "", fmt.Errorf("parse original requirements: %w", err)
	}
	updated, err := modfile.Parse("updated go.mod", []byte(args.UpdatedContent), nil)
	if err != nil {
		return "", fmt.Errorf("parse updated requirements: %w", err)
	}
	protected := make(map[string]*modfile.Require)
	for _, requirement := range original.Require {
		for _, replacement := range args.ReplacedModules {
			if replacement.Path == requirement.Mod.Path &&
				(replacement.Version == "" || replacement.Version == requirement.Mod.Version) {
				protected[requirement.Mod.Path] = requirement
				break
			}
		}
	}
	if len(args.ReplacedModules) == 0 || len(original.Require) == 0 {
		return args.UpdatedContent, nil
	}

	requirements := make([]*modfile.Require, 0, len(updated.Require)+len(protected))
	present := make(map[string]bool)
	for _, requirement := range updated.Require {
		if saved := protected[requirement.Mod.Path]; saved != nil {
			requirements = append(requirements, saved)
		} else {
			requirements = append(requirements, requirement)
		}
		present[requirement.Mod.Path] = true
	}
	for _, requirement := range original.Require {
		if !present[requirement.Mod.Path] {
			requirements = append(requirements, requirement)
			protected[requirement.Mod.Path] = requirement
		}
	}
	updated.SetRequire(requirements)
	for _, requirement := range updated.Require {
		if saved := protected[requirement.Mod.Path]; saved != nil {
			requirement.Syntax.Comments = saved.Syntax.Comments
		}
	}
	updated.Cleanup()
	content, err := updated.Format()
	if err != nil {
		return "", fmt.Errorf("format restored requirements: %w", err)
	}
	return string(content), nil
}
