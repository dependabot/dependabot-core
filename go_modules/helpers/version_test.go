package main

import (
	"encoding/json"
	"golang.org/x/mod/semver"
	"os"
	"reflect"
	"testing"
)

// TestVersionComparison verifies that the ordered version fixture is sorted correctly.
func TestVersionComparison(t *testing.T) {
	data, err := os.ReadFile("../spec/fixtures/ordered_versions.json")
	if err != nil {
		t.Fatalf("failed to read file: %v", err)
	}
	var expected []string
	if err = json.Unmarshal(data, &expected); err != nil {
		t.Fatalf("failed to unmarshal json: %v", err)
	}

	actual := make([]string, len(expected))
	copy(actual, expected)
	semver.Sort(actual)

	// The sorted order should equal the original order in the file.
	if !reflect.DeepEqual(actual, expected) {
		t.Fatalf("got %v", actual)
	}
}
