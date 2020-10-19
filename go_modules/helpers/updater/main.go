package updater

import (
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/mod/modfile"
	"golang.org/x/mod/semver"
	"golang.org/x/tools/go/packages"
)

// Dependency holds information for a package that requires updating.
type Dependency struct {
	Name            string `json:"name"`
	Version         string `json:"version"`
	PreviousVersion string `json:"previous_version"`
	Indirect        bool   `json:"indirect"`
}

func (d *Dependency) majorUpgrade() bool {
	if d.PreviousVersion == "" {
		return false
	}
	return semver.Major(d.PreviousVersion) != semver.Major(d.Version)
}

func (d *Dependency) oldName() string {
	m := semver.Major(d.PreviousVersion)
	parts := strings.Split(d.Name, "/")
	root := strings.Join(parts[:len(parts)-1], "/")
	if m == "v0" || m == "v1" || m == "" {
		return root
	}
	return root + "/" + m
}

// Args are arguments
type Args struct {
	Dependencies []Dependency `json:"dependencies"`
}

// UpdateDependencyFile checks the current directory for a go.mod file and
// updates it based on the args.Dependencies that are passed in, and write the
// results back to disk.
// If any of the dependencies is a major version upgrade, it will find any
// import statements in the code, and update them to the new version.
// Returns a list of updated files
func UpdateDependencyFile(args *Args) (interface{}, error) {
	data, err := ioutil.ReadFile("go.mod")
	if err != nil {
		return nil, err
	}

	f, err := modfile.Parse("go.mod", data, nil)
	if err != nil {
		return nil, err
	}

	paths := []string{}

	for _, dep := range args.Dependencies {
		if dep.majorUpgrade() {
			f.DropRequire(dep.oldName())
		}

		f.AddRequire(dep.Name, dep.Version)
		u, err := updateImportPaths(dep)
		if err != nil {
			return paths, err
		}

		paths = append(paths, u...)
	}

	for _, r := range f.Require {
		for _, dep := range args.Dependencies {
			if r.Mod.Path == dep.Name {
				setIndirect(r.Syntax, dep.Indirect)
			}
		}
	}

	f.SortBlocks()
	f.Cleanup()

	newModFile, err := f.Format()
	if err != nil {
		return nil, err
	}

	ioutil.WriteFile("go.mod", newModFile, 0644)

	updated := []string{}
	wd, err := os.Getwd()
	if err != nil {
		return updated, err
	}

	for _, path := range paths {
		rel, err := filepath.Rel(wd, path)
		if err != nil {
			return updated, err
		}
		updated = append(updated, rel)
	}

	return updated, nil
}

// updateImportPaths traverses the packages in the current directory, and for
// each one parses the go syntax and swaps out import paths from the old to the
// new path.
func updateImportPaths(dep Dependency) ([]string, error) {
	updated := []string{}

	if dep.majorUpgrade() {
		c := &packages.Config{Mode: packages.LoadSyntax, Tests: true, Dir: "./"}
		pkgs, err := packages.Load(c, "./...")
		if err != nil {
			return updated, err
		}

		ids := map[string]struct{}{}
		files := map[string]struct{}{}

		for _, p := range pkgs {
			if _, ok := ids[p.ID]; ok {
				continue
			}
			ids[p.ID] = struct{}{}
			u, err := updateImportPath(p, dep.oldName(), dep.Name, files)
			if err != nil {
				return updated, err
			}

			updated = append(updated, u...)
		}
	}

	return updated, nil
}
