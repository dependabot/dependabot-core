package updatechecker

import (
	"errors"
	"io/ioutil"

	"github.com/dependabot/gomodules-extracted/cmd/go/_internal_/modfetch"
	"github.com/dependabot/gomodules-extracted/cmd/go/_internal_/modload"
	"golang.org/x/mod/modfile"
	"golang.org/x/mod/semver"
)

type Dependency struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

type Args struct {
	Dependency *Dependency `json:"dependency"`
}

// GetVersions returns a list of versions for the given dependency that
// are within the same major version.
func GetVersions(args *Args) (interface{}, error) {
	if args.Dependency == nil {
		return nil, errors.New("Expected args.dependency to not be nil")
	}

	currentVersion := args.Dependency.Version

	modload.InitMod()

	repo, err := modfetch.Lookup("direct", args.Dependency.Name)
	if err != nil {
		return nil, err
	}

	versions, err := repo.Versions("")
	if err != nil {
		return nil, err
	}

	excludes, err := goModExcludes(args.Dependency.Name)
	if err != nil {
		return nil, err
	}

	currentMajor := semver.Major(currentVersion)

	var candidateVersions []string

Outer:
	for _, v := range versions {
		if semver.Major(v) != currentMajor {
			continue
		}

		for _, exclude := range excludes {
			if v == exclude {
				continue Outer
			}
		}

		candidateVersions = append(candidateVersions, v)
	}

	return candidateVersions, nil
}

func goModExcludes(dependency string) ([]string, error) {
	data, err := ioutil.ReadFile("go.mod")
	if err != nil {
		return nil, err
	}

	var f *modfile.File
	// TODO library detection - don't consider exclude etc for libraries
	if "library" == "true" {
		f, err = modfile.ParseLax("go.mod", data, nil)
	} else {
		f, err = modfile.Parse("go.mod", data, nil)
	}
	if err != nil {
		return nil, err
	}

	var excludes []string
	for _, e := range f.Exclude {
		if e.Mod.Path == dependency {
			excludes = append(excludes, e.Mod.Version)
		}
	}

	return excludes, nil
}
