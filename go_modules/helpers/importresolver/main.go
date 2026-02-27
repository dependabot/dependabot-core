package importresolver

import (
	"net/url"
	"os"
	"strings"

	"github.com/Masterminds/vcs"
)

type Args struct {
	Import string
}

func VCSRemoteForImport(args *Args) (interface{}, error) {
	remote := args.Import
	scheme := strings.Split(remote, ":")[0]
	switch scheme {
	case "http", "https":
	default:
		remote = "https://" + remote
	}

	remote = normalizeAzureDevOpsURL(remote)

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

func normalizeAzureDevOpsURL(remote string) string {
	uri, err := url.Parse(remote)
	if err != nil {
		return remote
	}

	host := strings.ToLower(uri.Host)
	if host != "dev.azure.com" {
		return remote
	}

	if strings.Contains(uri.Path, "/_git/") {
		return remote
	}

	segments := strings.Split(strings.TrimPrefix(uri.Path, "/"), "/")
	if len(segments) < 3 {
		return remote
	}

	repoSegment := segments[len(segments)-1]
	prefixSegments := segments[:len(segments)-1]
	normalizedSegments := append(prefixSegments, "_git", repoSegment)
	uri.Path = "/" + strings.Join(normalizedSegments, "/")

	return uri.String()
}
