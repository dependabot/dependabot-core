package importresolver

import (
	"testing"
)

func TestVCSRemoteForImport(t *testing.T) {
	args := &Args{
		Import: "https://github.com/dependabot/dependabot-core",
	}
	_, err := VCSRemoteForImport(args)
	if err != nil {
		t.Fatalf("failed to get VCS remote for import %s: %v", args.Import, err)
	}
}
