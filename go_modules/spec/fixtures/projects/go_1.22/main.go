package main

// When go tidy runs it checks the import statements in the project
// to see what is actually used. Thus, for sufficient testing we must
// have a main that imports the direct dependencies.
import (
  _ "golang.org/x/text"
)

func main() {}
