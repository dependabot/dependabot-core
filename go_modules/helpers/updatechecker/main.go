package updatechecker

import (
	"errors"
	"io/ioutil"
	"regexp"

	"github.com/dependabot/gomodules-extracted/cmd/go/_internal_/modfetch"
	"github.com/dependabot/gomodules-extracted/cmd/go/_internal_/modfile"
	"github.com/dependabot/gomodules-extracted/cmd/go/_internal_/modload"
	"github.com/dependabot/gomodules-extracted/cmd/go/_internal_/semver"
)

var (
	pseudoVersionRegexp = regexp.MustCompile(`\b\d{14}-[0-9a-f]{12}$`)
)

type Dependency struct {
	Name     string `json:"name"`
	Version  string `json:"version"`
	Indirect bool   `json:"indirect"`
}

type IgnoreRange struct {
	MinVersionInclusive string `json:"min_version_inclusive"`
	MaxVersionExclusive string `json:"max_version_exclusive"`
}

type Args struct {
	Dependency   *Dependency    `json:"dependency"`
	IgnoreRanges []*IgnoreRange `json:"ignore_ranges"`
}

func GetUpdatedVersion(args *Args) (interface{}, error) {
	if args.Dependency == nil {
		return nil, errors.New("Expected args.dependency to not be nil")
	}

	modload.InitMod()

	repo, err := modfetch.Lookup(args.Dependency.Name)
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

	currentVersion := args.Dependency.Version
	currentMajor := semver.Major(currentVersion)
	currentPrerelease := semver.Prerelease(currentVersion)
	latestVersion := args.Dependency.Version

	if pseudoVersionRegexp.MatchString(currentPrerelease) {
		return latestVersion, nil
	}

Outer:
	for _, v := range versions {
		if semver.Major(v) != currentMajor {
			continue
		}

		if semver.Compare(v, latestVersion) < 1 {
			continue
		}

		if currentPrerelease == "" && semver.Prerelease(v) != "" {
			continue
		}

		for _, exclude := range excludes {
			if v == exclude {
				continue Outer
			}
		}

		latestVersion = v
	}

	return latestVersion, nil
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
