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

// azureDevOpsPattern matches Azure DevOps module paths:
//
//	dev.azure.com/{org}/{project}/{repo}[.git][/subpath]
//
// Repo names containing dots (e.g. "my.utils") are intentionally excluded
// to avoid ambiguity with the .git VCS qualifier suffix.
//
// NOTE: A similar pattern exists in the Ruby shared helpers at
// common/lib/dependabot/shared_helpers.rb (configure_git_url_for_azure_devops).
// Keep both in sync when changing the URL structure.
var azureDevOpsPattern = regexp.MustCompile(
	`^https://dev\.azure\.com/([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_-]+)(?:\.git)?(?:/|$)`,
)

// rewriteAzureDevOpsURL converts a flat Azure DevOps URL to the correct
// /_git/ format that Azure DevOps requires for Git operations.
// Major-version subpaths (e.g. /v2, /v3) are a Go module convention and are
// not part of the git remote URL, so they are intentionally stripped.
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

	// Azure DevOps requires /_git/ in the URL path, but Go module paths
	// use a flat structure. Rewrite before VCS lookup.
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
