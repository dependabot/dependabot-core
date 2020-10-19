package updatechecker

import (
	"errors"
	"fmt"
	"io/ioutil"
	"regexp"
	"strconv"
	"strings"

	"github.com/dependabot/gomodules-extracted/cmd/go/_internal_/modfetch"
	"github.com/dependabot/gomodules-extracted/cmd/go/_internal_/modload"
	"golang.org/x/mod/modfile"
	"golang.org/x/mod/semver"
)

var (
	pseudoVersionRegexp = regexp.MustCompile(`\b\d{14}-[0-9a-f]{12}$`)
	versionRegexp       = regexp.MustCompile(`/v(\d+)$`)
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

	currentVersion := args.Dependency.Version
	currentPrerelease := semver.Prerelease(currentVersion)
	if pseudoVersionRegexp.MatchString(currentPrerelease) {
		return currentVersion, nil
	}

	modload.InitMod()

	versions := []string{}

	nextMajor := nextMajorVersion(args.Dependency.Name)
	if nextMajor != "" {
		v, _ := findVersions(nextMajor)
		versions = append(versions, v...)
	}

	if len(versions) == 0 {
		v, err := findVersions(args.Dependency.Name)
		if err != nil {
			return nil, err
		}
		versions = append(versions, v...)
	}

	excludes, err := goModExcludes(args.Dependency.Name)
	if err != nil {
		return nil, err
	}

	latestVersion := args.Dependency.Version

Outer:
	for _, v := range versions {
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

func nextMajorVersion(name string) string {
	m := versionRegexp.FindStringSubmatch(name)
	if len(m) == 0 {
		return ""
	}

	v, _ := strconv.ParseInt(m[1], 10, 32)
	return fmt.Sprintf("%s/v%d", name[:strings.LastIndex(name, "/")], v+1)
}

func findVersions(name string) ([]string, error) {
	repo, err := modfetch.Lookup("direct", name)
	if err != nil {
		return []string{}, err
	}

	return repo.Versions("")
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
