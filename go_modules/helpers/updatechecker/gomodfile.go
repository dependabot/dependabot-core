package updatechecker

import (
	"io/ioutil"

	"github.com/dependabot/gomodules-extracted/cmd/go/_internal_/modfile"
)

type goModFile struct {
	excludes           map[string][]string
	pinnedDependencies []string
}

func parseModFile() (goModFile, error) {
	fileInfo := goModFile{excludes: map[string][]string{}}

	data, err := ioutil.ReadFile("go.mod")
	if err != nil {
		return fileInfo, err
	}

	var f *modfile.File
	// TODO library detection - don't consider exclude etc for libraries
	if "library" == "true" {
		f, err = modfile.ParseLax("go.mod", data, nil)
	} else {
		f, err = modfile.Parse("go.mod", data, nil)
	}
	if err != nil {
		return fileInfo, err
	}

	for _, e := range f.Exclude {
		fileInfo.excludes[e.Mod.Path] = append(fileInfo.excludes[e.Mod.Path], e.Mod.Version)
	}

	for _, r := range f.Replace {
		if r.Old.Path == r.New.Path {
			fileInfo.pinnedDependencies = append(fileInfo.pinnedDependencies, r.New.Path)
		}
	}

	return fileInfo, nil
}
