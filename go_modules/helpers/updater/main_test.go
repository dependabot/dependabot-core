package updater

import (
	"io/ioutil"
	"os"
	"path"
	"strings"
	"testing"
)

func TestUpdateImportPaths(t *testing.T) {
	dir, err := buildTmpRepo("fixtures/major")
	defer os.RemoveAll(dir)
	if err != nil {
		t.Fatal(err)
	}

	if err = os.Chdir(dir); err != nil {
		t.Fatal(err)
	}

	args := &Args{
		Dependencies: []Dependency{
			{
				Name:            "github.com/Masterminds/semver/v3",
				Version:         "v3.0.1",
				PreviousVersion: "v1.5.0",
				Indirect:        false,
			},
		},
	}

	res, err := UpdateDependencyFile(args)
	if err != nil {
		t.Fatal(err)
	}

	b, err := ioutil.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}

	main := string(b)
	if !strings.Contains(main, "github.com/Masterminds/semver/v3") {
		t.Fatal("Import path was not updated")
	}

	b, err = ioutil.ReadFile("go.mod")
	if err != nil {
		t.Fatal(err)
	}
	mod := string(b)
	if !strings.Contains(mod, "github.com/Masterminds/semver/v3 v3.0.1") {
		t.Fatal("Package not updated in go.mod")
	}

	if files, ok := res.([]string); ok {
		if len([]string(files)) != 1 {
			t.Fatalf("Expected 2 files to change, but got %d", len(files))
		}

		if files[0] != "main.go" {
			t.Fatalf("Expected main.go, got %s", files[0])
		}
	} else {
		t.Fatal("Error converting result to slice")
	}
}

func buildTmpRepo(fixtures string) (dir string, err error) {
	dir, err = ioutil.TempDir("", "test")
	if err != nil {
		return "", err
	}

	files, err := ioutil.ReadDir(fixtures)
	if err != nil {
		return "", err
	}

	for _, f := range files {
		b, err := ioutil.ReadFile(path.Join(fixtures, f.Name()))
		if err != nil {
			return "", err
		}

		if err = ioutil.WriteFile(path.Join(dir, f.Name()), b, f.Mode()); err != nil {
			return "", err
		}
	}

	return dir, err
}
