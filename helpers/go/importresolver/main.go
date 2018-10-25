package importresolver

import (
	"io/ioutil"
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

	local, err := ioutil.TempDir("", "unused-vcs-local-dir")
	if err != nil {
		return nil, err
	}

	repo, err := vcs.NewRepo(remote, local)
	if err != nil {
		return nil, err
	}

	return repo.Remote(), nil
}
