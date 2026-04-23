package main

import (
	"fmt"
	"github.com/dependabot/vgotest"
	"rsc.io/quote"
)

func main() {
	fmt.Println("API:", quote.Hello(), vgotest.Version)
}
