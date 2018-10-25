package importresolver

import (
	"io/ioutil"

	"github.com/Masterminds/vcs"
)

type Args struct {
	Import string
}

func VCSRemoteForImport(args *Args) (interface{}, error) {
	remote := "https://" + args.Import
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
