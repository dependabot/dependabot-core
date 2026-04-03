package main

import (
	"fmt"
	"github.com/dependabot/vgotest"
	"rsc.io/quote"
)

func main() {
	fmt.Println(quote.Hello())
	fmt.Println(vgotest.Version)
}
