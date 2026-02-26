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
var azureDevOpsPattern = regexp.MustCompile(
	`^https://dev\.azure\.com/([^/]+)/([^/]+)/([^/.]+?)(?:\.git)?(?:/|$)`,
)

// rewriteAzureDevOpsURL converts a flat Azure DevOps URL to the correct
// /_git/ format that Azure DevOps requires for Git operations.
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
