package main

import (
	"fmt"

	"go.testcompany.local/shared/logger"
)

func main() {
	logger.Info("Hello world")
	fmt.Println("Using vanity import with SSH URL")
}
