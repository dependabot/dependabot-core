package main

import (
	"github.com/theupdateframework/go-tuf/verify"
)

func main() {
	// the vulnerable package is imported an used, but the vulnerable function not
	// called
	verify.NewDB()
}
