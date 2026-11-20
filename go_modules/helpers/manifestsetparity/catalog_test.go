package manifestsetparity

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// dataDir locates common/lib/dependabot/manifest_sets both in a checkout and in the updater container,
// where common/ is copied next to go_modules/. MANIFEST_SETS_DIR overrides the lookup.
func dataDir(t *testing.T) string {
	t.Helper()
	if dir := os.Getenv("MANIFEST_SETS_DIR"); dir != "" {
		return dir
	}
	dir, err := filepath.Abs(filepath.Join("..", "..", "..", "common", "lib", "dependabot", "manifest_sets"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "catalog.json")); err != nil {
		t.Fatalf("manifest-set catalog not found at %s (set MANIFEST_SETS_DIR): %v", dir, err)
	}
	return dir
}

func readJSON(t *testing.T, path string, into any) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, into); err != nil {
		t.Fatalf("%s: %v", path, err)
	}
}

func bundledCatalog(t *testing.T) *Catalog {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(dataDir(t), "catalog.json"))
	if err != nil {
		t.Fatal(err)
	}
	catalog, err := Parse(data)
	if err != nil {
		t.Fatalf("bundled catalog is invalid: %v", err)
	}
	return catalog
}

func TestBundledCatalogIsValid(t *testing.T) {
	catalog := bundledCatalog(t)
	if len(catalog.Ecosystems) == 0 {
		t.Fatal("catalog has no ecosystems")
	}
}

func TestFilenameFixtures(t *testing.T) {
	bundled := bundledCatalog(t)
	var fixtures struct {
		Cases []struct {
			Catalog       *string  `json:"catalog"`
			Ecosystem     string   `json:"ecosystem"`
			Basename      string   `json:"basename"`
			MatchingRules []string `json:"matching_rules"`
		} `json:"cases"`
	}
	readJSON(t, filepath.Join(dataDir(t), "fixtures", "filenames.json"), &fixtures)
	if len(fixtures.Cases) == 0 {
		t.Fatal("no filename fixtures")
	}
	for _, c := range fixtures.Cases {
		catalog := bundled
		if c.Catalog != nil {
			parsed, err := Parse([]byte(*c.Catalog))
			if err != nil {
				t.Errorf("%q: inline catalog is invalid: %v", c.Basename, err)
				continue
			}
			catalog = parsed
		}
		eco := catalog.Ecosystem(c.Ecosystem)
		if eco == nil {
			t.Errorf("unknown ecosystem %q", c.Ecosystem)
			continue
		}
		if got := eco.MatchingRuleIDs(c.Basename); !slices.Equal(got, c.MatchingRules) {
			t.Errorf("%s %q: matched %v, fixture expects %v", c.Ecosystem, c.Basename, got, c.MatchingRules)
		}
	}
}

func TestOwnerFixtures(t *testing.T) {
	bundled := bundledCatalog(t)
	var fixtures struct {
		Cases []struct {
			Name      string   `json:"name"`
			Catalog   *string  `json:"catalog"`
			Ecosystem string   `json:"ecosystem"`
			Basenames []string `json:"basenames"`
			Owner     string   `json:"owner"`
			Ambiguous bool     `json:"ambiguous"`
		} `json:"cases"`
	}
	readJSON(t, filepath.Join(dataDir(t), "fixtures", "owners.json"), &fixtures)
	for _, c := range fixtures.Cases {
		catalog := bundled
		if c.Catalog != nil {
			parsed, err := Parse([]byte(*c.Catalog))
			if err != nil {
				t.Errorf("%s: inline catalog is invalid: %v", c.Name, err)
				continue
			}
			catalog = parsed
		}
		eco := catalog.Ecosystem(c.Ecosystem)
		if eco == nil {
			t.Errorf("unknown ecosystem %q", c.Ecosystem)
			continue
		}
		got, ambiguous := eco.SelectOwner(c.Basenames)
		if got != c.Owner || ambiguous != c.Ambiguous {
			t.Errorf("%s %v: selected (%q, ambiguous=%v), fixture expects (%q, ambiguous=%v)",
				c.Ecosystem, c.Basenames, got, ambiguous, c.Owner, c.Ambiguous)
		}
	}
}

func TestInvalidCatalogFixtures(t *testing.T) {
	var fixtures struct {
		Cases []struct {
			Name    string `json:"name"`
			Error   string `json:"error"`
			Catalog string `json:"catalog"`
		} `json:"cases"`
	}
	readJSON(t, filepath.Join(dataDir(t), "fixtures", "invalid_catalogs.json"), &fixtures)
	for _, c := range fixtures.Cases {
		_, err := Parse([]byte(c.Catalog))
		var invalidErr *InvalidCatalogError
		if !errors.As(err, &invalidErr) {
			t.Errorf("%s: expected %s, got %v", c.Name, c.Error, err)
			continue
		}
		if invalidErr.Code != c.Error {
			t.Errorf("%s: expected %s, got %v", c.Name, c.Error, err)
		}
	}
}

func TestLimits(t *testing.T) {
	rules := make([]string, MaxRules+1)
	for i := range rules {
		rules[i] = fmt.Sprintf(`{"id":"r%d","filename_regex":"\\Aa\\z","directory":"parent"}`, i)
	}
	doc := `{"schema_version":1,"ecosystems":[{"id":"e","path_rules":[` + strings.Join(rules, ",") +
		`],"owners":[{"id":"o","otherwise":true}]}]}`
	assertCode(t, doc, "too_many_rules")
	assertCode(t, `{"schema_version":1,"ecosystems":[]}`+strings.Repeat(" ", MaxCatalogBytes), "catalog_too_large")
	assertCode(t, "{\"schema_version\":1,\"ecosystems\":\"\xff\"}", "invalid_json")
	assertCode(t, strings.Repeat("[", 33)+strings.Repeat("]", 33), "invalid_json")
}

func assertCode(t *testing.T, doc, code string) {
	t.Helper()
	_, err := Parse([]byte(doc))
	var invalidErr *InvalidCatalogError
	if !errors.As(err, &invalidErr) || invalidErr.Code != code {
		t.Errorf("expected %s, got %v", code, err)
	}
}

// TestDigestManifest verifies digests.json the way a vendoring consumer would: every listed file hashes to
// its recorded sha256, and every published file is listed.
func TestDigestManifest(t *testing.T) {
	dir := dataDir(t)
	var manifest struct {
		SchemaVersion int    `json:"schema_version"`
		Algorithm     string `json:"algorithm"`
		Files         []struct {
			Path   string `json:"path"`
			SHA256 string `json:"sha256"`
		} `json:"files"`
	}
	readJSON(t, filepath.Join(dir, "digests.json"), &manifest)
	if manifest.SchemaVersion != 1 || manifest.Algorithm != "sha256" {
		t.Fatalf("unexpected digest manifest header: %d %q", manifest.SchemaVersion, manifest.Algorithm)
	}

	listed := map[string]bool{}
	for _, file := range manifest.Files {
		data, err := os.ReadFile(filepath.Join(dir, filepath.FromSlash(file.Path)))
		if err != nil {
			t.Fatal(err)
		}
		if got := fmt.Sprintf("%x", sha256.Sum256(data)); got != file.SHA256 {
			t.Errorf("%s: sha256 %s, manifest says %s", file.Path, got, file.SHA256)
		}
		listed[file.Path] = true
	}

	published, err := publishedFiles(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, rel := range published {
		if !listed[rel] {
			t.Errorf("%s is published but missing from digests.json", rel)
		}
	}
}

// publishedFiles mirrors the Ruby generator's globs: *.json at the top level (except digests.json itself)
// and fixtures/**/*.json at any depth. Paths are slash-separated and relative to dir.
func publishedFiles(dir string) ([]string, error) {
	top, err := filepath.Glob(filepath.Join(dir, "*.json"))
	if err != nil {
		return nil, err
	}
	var files []string
	for _, path := range top {
		if filepath.Base(path) != "digests.json" {
			files = append(files, filepath.Base(path))
		}
	}
	fixtures := filepath.Join(dir, "fixtures")
	err = filepath.WalkDir(fixtures, func(path string, entry fs.DirEntry, err error) error {
		if err != nil || entry.IsDir() || filepath.Ext(path) != ".json" {
			return err
		}
		rel, err := filepath.Rel(dir, path)
		if err == nil {
			files = append(files, filepath.ToSlash(rel))
		}
		return err
	})
	if errors.Is(err, fs.ErrNotExist) {
		err = nil
	}
	return files, err
}

func TestPublishedFilesIncludesNestedFixtures(t *testing.T) {
	dir := t.TempDir()
	for _, rel := range []string{"catalog.json", "digests.json", "fixtures/owners.json", "fixtures/extra/nested.json", "fixtures/notes.txt"} {
		path := filepath.Join(dir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("{}"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got, err := publishedFiles(dir)
	if err != nil {
		t.Fatal(err)
	}
	slices.Sort(got)
	want := []string{"catalog.json", "fixtures/extra/nested.json", "fixtures/owners.json"}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Errorf("published files = %v, want %v", got, want)
	}
}
