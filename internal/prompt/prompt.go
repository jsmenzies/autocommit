package prompt

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func EditMessage(original string) (string, error) {
	fmt.Printf("\nCurrent message: %s\n", original)
	fmt.Println("Enter new message (press Enter twice to finish):")

	reader := bufio.NewReader(os.Stdin)
	var lines []string

	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			return "", err
		}

		line = strings.TrimSpace(line)
		if line == "" {
			break
		}
		lines = append(lines, line)
	}

	if len(lines) == 0 {
		return original, nil
	}

	return strings.Join(lines, "\n"), nil
}
