package main

import (
	"fmt"
	"os"

	"autocommit/internal/cmd"
)

var (
	version   = "dev"
	commit    = "unknown"
	buildTime = "unknown"
)

func main() {
	if err := cmd.Execute(version, commit, buildTime); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
