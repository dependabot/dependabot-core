package manifest

import "testing"

func TestRestoreChecksums(t *testing.T) {
	const original = `example.com/z v1.0.0 h1:z
example.com/a v1.9.0/go.mod h1:mod
example.com/a v1.9.0 h1:b
example.com/a v1.9.0 h1:a
`
	const updated = `example.com/a v1.10.0/go.mod h1:newmod
example.com/a v1.10.0 h1:new
example.com/a v1.9.0 h1:a

`
	const want = `example.com/a v1.9.0 h1:a
example.com/a v1.9.0 h1:b
example.com/a v1.9.0/go.mod h1:mod
example.com/a v1.10.0 h1:new
example.com/a v1.10.0/go.mod h1:newmod
example.com/z v1.0.0 h1:z
`
	result, err := RestoreChecksums(RestoreChecksumsArgs{OriginalContent: original, UpdatedContent: updated})
	if err != nil {
		t.Fatal(err)
	}
	if result != want {
		t.Fatalf("restored checksums:\n%s\nwant:\n%s", result, want)
	}
}

func TestRestoreChecksumsMalformed(t *testing.T) {
	for _, args := range []RestoreChecksumsArgs{
		{OriginalContent: "missing hash"},
		{UpdatedContent: "missing hash"},
	} {
		if _, err := RestoreChecksums(args); err == nil {
			t.Fatal("malformed checksum accepted")
		}
	}
}
