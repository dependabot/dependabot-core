package main

import (
	"time"

	"github.com/theupdateframework/go-tuf/pkg/keys"
	"github.com/theupdateframework/go-tuf/sign"
	"github.com/theupdateframework/go-tuf/verify"
)

type signedMeta struct {
	Type    string    `json:"_type"`
	Expires time.Time `json:"expires"`
	Version int64     `json:"version"`
}

func main() {
	ver := int64(10)
	exp := time.Now().Add(-time.Hour)
	k, _ := keys.GenerateEd25519Key()
	s, _ := sign.Marshal(&signedMeta{Type: "", Version: ver, Expires: exp}, k)

	db := verify.NewDB()
	db.Verify(s, "root", ver)
}
