package main

import (
	"encoding/json"
	"errors"
	"io/ioutil"
	"log"
	"os"

	"modfile"
)

type Dependency struct {
	Name     string `json:"name"`
	Version  string `json:"version"`
	Indirect bool   `json:"indirect"`
}

type HelperParams struct {
	Function string `json:"function"`
	Args     struct {
		Dependencies []Dependency `json:"dependencies"`
	} `json:"args"`
}

type Output struct {
	Error  string `json:"error,omitempty"`
	Result string `json:"result,omitempty"`
}

func main() {
	d := json.NewDecoder(os.Stdin)
	helperParams := &HelperParams{}
	if err := d.Decode(helperParams); err != nil {
		abort(err)
	}

	if helperParams.Function != "updateDependencyFile" {
		abort(errors.New("Expected function to be 'updateDependencyFile'"))
	}

	data, err := ioutil.ReadFile("go.mod")
	if err != nil {
		abort(err)
	}

	f, err := modfile.ParseLax("go.mod", data, nil)
	if err != nil {
		abort(err)
	}

	for _, dep := range helperParams.Args.Dependencies {
		f.AddRequire(dep.Name, dep.Version)
	}

	for _, r := range f.Require {
		for _, dep := range helperParams.Args.Dependencies {
			if r.Mod.Path == dep.Name {
				setIndirect(r.Syntax, dep.Indirect)
			}
		}
	}

	f.Cleanup()

	newModFile, _ := f.Format()
	output(&Output{Result: string(newModFile)})
}

func output(o *Output) {
	bytes, jsonErr := json.Marshal(o)
	if jsonErr != nil {
		log.Fatal(jsonErr)
	}

	os.Stdout.Write(bytes)
}

func abort(err error) {
	output(&Output{Error: err.Error()})
	os.Exit(1)
}
