package main

import (
	"fmt"
	errors "pkg-errors"
)

func main() {
	err := errors.New("kaboom")
	fmt.Println(err)
}
