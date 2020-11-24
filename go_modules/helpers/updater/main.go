package updater

import (
	"io/ioutil"

	"golang.org/x/mod/modfile"
)

type Dependency struct {
	Name     string `json:"name"`
	Version  string `json:"version"`
	Indirect bool   `json:"indirect"`
}

type Args struct {
	Dependencies []Dependency `json:"dependencies"`
}

func UpdateDependencyFile(args *Args) (interface{}, error) {
	data, err := ioutil.ReadFile("go.mod")
	if err != nil {
		return nil, err
	}

	f, err := modfile.Parse("go.mod", data, nil)
	if err != nil {
		return nil, err
	}

	for _, dep := range args.Dependencies {
		f.AddRequire(dep.Name, dep.Version)
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

	newModFile, _ := f.Format()

	return string(newModFile), nil
}
