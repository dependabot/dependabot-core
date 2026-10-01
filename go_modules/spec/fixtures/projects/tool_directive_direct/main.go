package main

import (
	"fmt"

	"golang.org/x/tools/go/analysis/passes/printf"
	"rsc.io/quote"
)

func main() {
	fmt.Println(quote.Hello())
	// Touch a symbol from x/tools to ensure it is a direct dependency
	_ = printf.Analyzer.Name
}
