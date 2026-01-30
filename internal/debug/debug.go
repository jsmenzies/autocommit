package debug

import "fmt"

// Enabled controls whether debug output is printed
var Enabled = false

// Printf prints formatted debug output if debug mode is enabled
func Printf(format string, args ...interface{}) {
	if Enabled {
		fmt.Printf(format, args...)
	}
}

// Println prints debug output if debug mode is enabled
func Println(args ...interface{}) {
	if Enabled {
		fmt.Println(args...)
	}
}
