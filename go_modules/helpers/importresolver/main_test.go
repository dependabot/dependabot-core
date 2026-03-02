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

func TestNormalizeAzureDevOpsURL(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{
			name:  "adds _git segment when missing and removes .git suffix",
			input: "https://dev.azure.com/VaronisIO/da-cloud/be-protobuf.git",
			want:  "https://dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf",
		},
		{
			name:  "preserves existing _git segment",
			input: "https://dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf",
			want:  "https://dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf",
		},
		{
			name:  "removes .git suffix when _git already exists",
			input: "https://dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.git",
			want:  "https://dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf",
		},
		{
			name:  "preserves subdirectory while removing .git suffix",
			input: "https://dev.azure.com/VaronisIO/da-cloud/be-protobuf.git/submodule",
			want:  "https://dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf/submodule",
		},
		{
			name:  "ignores non azure hosts",
			input: "https://github.com/dependabot/dependabot-core",
			want:  "https://github.com/dependabot/dependabot-core",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got := normalizeAzureDevOpsURL(test.input)
			if got != test.want {
				t.Fatalf("normalizeAzureDevOpsURL(%q) = %q, want %q", test.input, got, test.want)
			}
		})
	}
}
