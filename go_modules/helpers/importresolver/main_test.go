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

func TestRewriteAzureDevOpsURL(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "Azure DevOps module path with .git suffix",
			input:    "https://dev.azure.com/VaronisIO/da-cloud/be-protobuf.git",
			expected: "https://dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf",
		},
		{
			name:     "Azure DevOps module path without .git suffix",
			input:    "https://dev.azure.com/MyOrg/MyProject/myrepo",
			expected: "https://dev.azure.com/MyOrg/MyProject/_git/myrepo",
		},
		{
			name:     "non-Azure DevOps URL is unchanged",
			input:    "https://github.com/some/repo",
			expected: "https://github.com/some/repo",
		},
		{
			name:     "Azure DevOps URL with too few segments",
			input:    "https://dev.azure.com/MyOrg/MyProject",
			expected: "https://dev.azure.com/MyOrg/MyProject",
		},
		{
			name:     "Azure DevOps URL with major version subpath",
			input:    "https://dev.azure.com/MyOrg/MyProject/myrepo/v2",
			expected: "https://dev.azure.com/MyOrg/MyProject/_git/myrepo",
		},
		{
			name:     "Azure DevOps URL with .git and subpath",
			input:    "https://dev.azure.com/MyOrg/MyProject/myrepo.git/v3",
			expected: "https://dev.azure.com/MyOrg/MyProject/_git/myrepo",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := rewriteAzureDevOpsURL(tt.input)
			if result != tt.expected {
				t.Errorf("rewriteAzureDevOpsURL(%q) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestVCSRemoteForImportAzureDevOps(t *testing.T) {
	args := &Args{
		Import: "dev.azure.com/MyOrg/MyProject/myrepo.git",
	}
	result, err := VCSRemoteForImport(args)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	expected := "https://dev.azure.com/MyOrg/MyProject/_git/myrepo"
	if result != expected {
		t.Errorf("VCSRemoteForImport(%q) = %q, want %q", args.Import, result, expected)
	}
}
