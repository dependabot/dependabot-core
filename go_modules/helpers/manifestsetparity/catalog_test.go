package manifestsetparity

import (
	"encoding/json"
	"errors"
	"fmt"
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
