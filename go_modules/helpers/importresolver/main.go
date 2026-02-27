package importresolver

import (
	"os"
	"regexp"
	"strings"

	"github.com/Masterminds/vcs"
)

type Args struct {
	Import string
}

// azureDevOpsPattern matches Azure DevOps URLs:
//
//	https://dev.azure.com/{org}/{project}/{repo}[.git][/subpath]
//
// Repo names containing dots are excluded to avoid ambiguity with .git.
// Keep in sync with common/lib/dependabot/shared_helpers.rb
// (AZURE_DEVOPS_MODULE_PATTERN), which matches bare module paths (no scheme).
var azureDevOpsPattern = regexp.MustCompile(
	`^https://dev\.azure\.com/([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_-]+)(?:\.git)?(?:/|$)`,
)

func rewriteAzureDevOpsURL(remote string) string {
	m := azureDevOpsPattern.FindStringSubmatch(remote)
	if m == nil {
		return remote
	}
	return "https://dev.azure.com/" + m[1] + "/" + m[2] + "/_git/" + m[3]
}

func VCSRemoteForImport(args *Args) (interface{}, error) {
	remote := args.Import
	scheme := strings.Split(remote, ":")[0]
	switch scheme {
	case "http", "https":
	default:
		remote = "https://" + remote
	}

	rewritten := rewriteAzureDevOpsURL(remote)
	if rewritten != remote {
		return rewritten, nil
	}

	local, err := os.MkdirTemp("", "unused-vcs-local-dir")
	if err != nil {
		return nil, err
	}

	repo, err := vcs.NewRepo(remote, local)
	if err != nil {
		return nil, err
	}
	defer func() {
		os.RemoveAll(repo.LocalPath())
	}()
	return repo.Remote(), nil
}
