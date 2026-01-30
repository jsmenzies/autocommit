package debug

import "fmt"

var Enabled = false

func Printf(format string, args ...interface{}) {
	if Enabled {
		fmt.Printf(format, args...)
	}
}

func Println(args ...interface{}) {
	if Enabled {
		fmt.Println(args...)
	}
}
