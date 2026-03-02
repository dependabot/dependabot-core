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

	segments := strings.Split(strings.TrimPrefix(uri.Path, "/"), "/")
	if len(segments) < 3 {
		return remote
	}

	normalizedSegments := segments
	if !strings.Contains(uri.Path, "/_git/") {
		if len(segments) < 3 {
			return remote
		}

		// Azure DevOps paths are /{org}/{project}/_git/{repo}[/{subdir}...].
		// Insert "_git" after the first two segments and preserve the rest.
		normalizedSegments = make([]string, 0, len(segments)+1)
		normalizedSegments = append(normalizedSegments, segments[:2]...)
		normalizedSegments = append(normalizedSegments, "_git")
		normalizedSegments = append(normalizedSegments, segments[2:]...)

		for i := range normalizedSegments {
			if normalizedSegments[i] != "_git" {
				continue
			}

			repoIndex := i + 1
			if repoIndex >= len(normalizedSegments) {
				return remote
			}

			normalizedSegments[repoIndex] = strings.TrimSuffix(normalizedSegments[repoIndex], ".git")
			break
		}
	}

	uri.Path = "/" + strings.Join(normalizedSegments, "/")

	return uri.String()
}
