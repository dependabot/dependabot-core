// Package manifestsetparity is a Go reference reader for the manifest-set catalog bundled with
// dependabot-common (common/lib/dependabot/manifest_sets). Its tests check that Go's regexp engine and
// the Ruby implementation agree on every shared fixture, so the catalog can be consumed from Go.
package manifestsetparity

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"slices"
	"unicode/utf8"
)

const (
	SchemaVersion   = "1"
	MaxCatalogBytes = 1024 * 1024
	MaxRules        = 4096
	MaxRegexBytes   = 1024
	MaxRepeat       = 1000
	maxNesting      = 32
	directoryParent = "parent"
)

var identifier = regexp.MustCompile(`\A[a-z0-9][a-z0-9_.-]{0,63}\z`)

// InvalidCatalogError carries the same error codes as the Ruby validator.
type InvalidCatalogError struct {
	Code    string
	Message string
}

func (e *InvalidCatalogError) Error() string { return e.Code + ": " + e.Message }

func invalid(code, format string, args ...any) error {
	return &InvalidCatalogError{Code: code, Message: fmt.Sprintf(format, args...)}
}

type PathRule struct {
	ID            string
	FilenameRegex string
	Regex         *regexp.Regexp
}

type Owner struct {
	ID              string
	WhenAnyBasename []string
	Otherwise       bool
}

type Ecosystem struct {
	ID                   string
	InputsMatchedByRules bool
	PathRules            []PathRule
	Owners               []Owner
}

type Catalog struct {
	Ecosystems []Ecosystem
}

func (c *Catalog) Ecosystem(id string) *Ecosystem {
	for i := range c.Ecosystems {
		if c.Ecosystems[i].ID == id {
			return &c.Ecosystems[i]
		}
	}
	return nil
}

// MatchingRuleIDs returns the IDs of every rule whose regex matches the whole basename, in catalog order.
func (e *Ecosystem) MatchingRuleIDs(basename string) []string {
	ids := []string{}
	for _, rule := range e.PathRules {
		if rule.Regex.MatchString(basename) {
			ids = append(ids, rule.ID)
		}
	}
	return ids
}

// SelectOwner evaluates presence owners before the otherwise owner. Exactly one matching presence
// owner wins; more than one is ambiguous and returns ("", true). With none, the otherwise owner (or "")
// applies.
func (e *Ecosystem) SelectOwner(basenames []string) (id string, ambiguous bool) {
	fallback := ""
	matched := 0
	for _, owner := range e.Owners {
		if owner.Otherwise {
			fallback = owner.ID
			continue
		}
		for _, name := range owner.WhenAnyBasename {
			if slices.Contains(basenames, name) {
				id = owner.ID
				matched++
				break
			}
		}
	}
	switch matched {
	case 0:
		return fallback, false
	case 1:
		return id, false
	default:
		return "", true
	}
}

// Parse validates and loads a catalog. Any violation rejects the whole document.
func Parse(data []byte) (*Catalog, error) {
	if len(data) > MaxCatalogBytes {
		return nil, invalid("catalog_too_large", "catalog exceeds %d bytes", MaxCatalogBytes)
	}
	doc, err := decodeStrict(data)
	if err != nil {
		return nil, err
	}
	b := &builder{}
	return b.build(doc)
}

// decodeStrict decodes RFC 8259 JSON, rejecting duplicate object keys, invalid UTF-8 and trailing data.
func decodeStrict(data []byte) (any, error) {
	if !utf8.Valid(data) {
		return nil, invalid("invalid_json", "document is not valid UTF-8")
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	value, err := decodeValue(dec, 0)
	if err != nil {
		return nil, err
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return nil, invalid("invalid_json", "unexpected trailing content")
	}
	return value, nil
}

func decodeValue(dec *json.Decoder, depth int) (any, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, invalid("invalid_json", "%v", err)
	}
	delim, ok := tok.(json.Delim)
	if !ok {
		return tok, nil
	}
	if depth >= maxNesting {
		return nil, invalid("invalid_json", "maximum nesting depth exceeded")
	}
	switch delim {
	case '{':
		object := map[string]any{}
		for dec.More() {
			keyTok, err := dec.Token()
			if err != nil {
				return nil, invalid("invalid_json", "%v", err)
			}
			key, ok := keyTok.(string)
			if !ok {
				return nil, invalid("invalid_json", "expected object key")
			}
			if _, seen := object[key]; seen {
				return nil, invalid("duplicate_key", "duplicate object key %q", key)
			}
			value, err := decodeValue(dec, depth+1)
			if err != nil {
				return nil, err
			}
			object[key] = value
		}
		if _, err := dec.Token(); err != nil {
			return nil, invalid("invalid_json", "%v", err)
		}
		return object, nil
	case '[':
		array := []any{}
		for dec.More() {
			value, err := decodeValue(dec, depth+1)
			if err != nil {
				return nil, err
			}
			array = append(array, value)
		}
		if _, err := dec.Token(); err != nil {
			return nil, invalid("invalid_json", "%v", err)
		}
		return array, nil
	}
	return nil, invalid("invalid_json", "unexpected delimiter %v", delim)
}

type builder struct {
	ruleCount int
}

// field lists map each allowed key to whether it is required.
var (
	rootFields      = map[string]bool{"schema_version": true, "ecosystems": true}
	ecosystemFields = map[string]bool{"id": true, "inputs_matched_by_rules": false, "path_rules": true, "owners": true}
	ruleFields      = map[string]bool{"id": true, "filename_regex": true, "directory": true}
	ownerFields     = map[string]bool{"id": true, "when_any_basename": false, "otherwise": false}
)

func (b *builder) build(doc any) (*Catalog, error) {
	root, err := object(doc, "catalog", rootFields)
	if err != nil {
		return nil, err
	}
	if n, ok := root["schema_version"].(json.Number); !ok || n.String() != SchemaVersion {
		return nil, invalid("unsupported_schema_version", "schema_version must be %s", SchemaVersion)
	}
	items, err := nonEmptyArray(root["ecosystems"], "ecosystems")
	if err != nil {
		return nil, err
	}
	catalog := &Catalog{}
	ids := []string{}
	for i, item := range items {
		eco, err := b.ecosystem(item, fmt.Sprintf("ecosystems[%d]", i))
		if err != nil {
			return nil, err
		}
		catalog.Ecosystems = append(catalog.Ecosystems, *eco)
		ids = append(ids, eco.ID)
	}
	if err := unique(ids, "duplicate_ecosystem_id"); err != nil {
		return nil, err
	}
	return catalog, nil
}

func (b *builder) ecosystem(item any, where string) (*Ecosystem, error) {
	hash, err := object(item, where, ecosystemFields)
	if err != nil {
		return nil, err
	}
	id, err := ident(hash["id"], where+".id")
	if err != nil {
		return nil, err
	}
	eco := &Ecosystem{ID: id}
	if raw, present := hash["inputs_matched_by_rules"]; present {
		matched, ok := raw.(bool)
		if !ok {
			return nil, invalid("invalid_type", "%s.inputs_matched_by_rules must be a boolean", where)
		}
		eco.InputsMatchedByRules = matched
	}

	rules, err := nonEmptyArray(hash["path_rules"], where+".path_rules")
	if err != nil {
		return nil, err
	}
	ruleIDs := []string{}
	for i, raw := range rules {
		rule, err := b.rule(raw, fmt.Sprintf("%s.path_rules[%d]", where, i))
		if err != nil {
			return nil, err
		}
		eco.PathRules = append(eco.PathRules, *rule)
		ruleIDs = append(ruleIDs, rule.ID)
	}
	if err := unique(ruleIDs, "duplicate_rule_id"); err != nil {
		return nil, err
	}

	owners, err := nonEmptyArray(hash["owners"], where+".owners")
	if err != nil {
		return nil, err
	}
	ownerIDs := []string{}
	for i, raw := range owners {
		owner, err := buildOwner(raw, fmt.Sprintf("%s.owners[%d]", where, i))
		if err != nil {
			return nil, err
		}
		eco.Owners = append(eco.Owners, *owner)
		ownerIDs = append(ownerIDs, owner.ID)
	}
	if err := unique(ownerIDs, "duplicate_owner_id"); err != nil {
		return nil, err
	}
	for i, owner := range eco.Owners {
		if owner.Otherwise && i != len(eco.Owners)-1 {
			return nil, invalid("invalid_owner_order", "%s.owners: the otherwise owner must be last and unique", where)
		}
	}
	return eco, nil
}

func (b *builder) rule(item any, where string) (*PathRule, error) {
	b.ruleCount++
	if b.ruleCount > MaxRules {
		return nil, invalid("too_many_rules", "catalog exceeds %d rules", MaxRules)
	}
	hash, err := object(item, where, ruleFields)
	if err != nil {
		return nil, err
	}
	id, err := ident(hash["id"], where+".id")
	if err != nil {
		return nil, err
	}
	source, ok := hash["filename_regex"].(string)
	if !ok {
		return nil, invalid("invalid_type", "%s.filename_regex must be a string", where)
	}
	directory, ok := hash["directory"].(string)
	if !ok {
		return nil, invalid("invalid_type", "%s.directory must be a string", where)
	}
	if directory != directoryParent {
		return nil, invalid("invalid_directory", "%s.directory must be %q", where, directoryParent)
	}
	re, err := CompilePortable(id, source)
	if err != nil {
		return nil, err
	}
	return &PathRule{ID: id, FilenameRegex: source, Regex: re}, nil
}

func buildOwner(item any, where string) (*Owner, error) {
	hash, err := object(item, where, ownerFields)
	if err != nil {
		return nil, err
	}
	id, err := ident(hash["id"], where+".id")
	if err != nil {
		return nil, err
	}
	rawNames, hasNames := hash["when_any_basename"]
	rawOtherwise, hasOtherwise := hash["otherwise"]
	if hasNames == hasOtherwise {
		return nil, invalid("invalid_type", "%s needs exactly one of when_any_basename or otherwise", where)
	}
	if hasOtherwise {
		if v, ok := rawOtherwise.(bool); !ok || !v {
			return nil, invalid("invalid_type", "%s.otherwise must be true", where)
		}
		return &Owner{ID: id, Otherwise: true}, nil
	}
	items, err := nonEmptyArray(rawNames, where+".when_any_basename")
	if err != nil {
		return nil, err
	}
	names := []string{}
	for _, raw := range items {
		name, ok := raw.(string)
		if !ok {
			return nil, invalid("invalid_type", "%s.when_any_basename must be a string", where)
		}
		if name == "" || bytes.ContainsAny([]byte(name), "/\x00") {
			return nil, invalid("invalid_type", "%s.when_any_basename entries must be basenames", where)
		}
		if slices.Contains(names, name) {
			return nil, invalid("invalid_type", "%s.when_any_basename has duplicates", where)
		}
		names = append(names, name)
	}
	return &Owner{ID: id, WhenAnyBasename: names}, nil
}

func object(value any, where string, fields map[string]bool) (map[string]any, error) {
	hash, ok := value.(map[string]any)
	if !ok {
		return nil, invalid("invalid_type", "%s must be an object", where)
	}
	unknown := []string{}
	for key := range hash {
		if _, known := fields[key]; !known {
			unknown = append(unknown, key)
		}
	}
	if len(unknown) > 0 {
		slices.Sort(unknown)
		return nil, invalid("unknown_field", "%s has unknown field(s) %v", where, unknown)
	}
	names := make([]string, 0, len(fields))
	for name := range fields {
		names = append(names, name)
	}
	slices.Sort(names)
	for _, name := range names {
		if _, present := hash[name]; fields[name] && !present {
			return nil, invalid("missing_field", "%s.%s is required", where, name)
		}
	}
	return hash, nil
}

func nonEmptyArray(value any, where string) ([]any, error) {
	array, ok := value.([]any)
	if !ok || len(array) == 0 {
		return nil, invalid("invalid_type", "%s must be a non-empty array", where)
	}
	return array, nil
}

func ident(value any, where string) (string, error) {
	id, ok := value.(string)
	if !ok {
		return "", invalid("invalid_type", "%s must be a string", where)
	}
	if !identifier.MatchString(id) {
		return "", invalid("invalid_identifier", "%s %q is not a valid identifier", where, id)
	}
	return id, nil
}

func unique(ids []string, code string) error {
	seen := map[string]bool{}
	for _, id := range ids {
		if seen[id] {
			return invalid(code, "%q appears more than once", id)
		}
		seen[id] = true
	}
	return nil
}
