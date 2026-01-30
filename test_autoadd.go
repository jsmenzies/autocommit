package main

import (
	"autocommit/internal/config"
	"fmt"
	"os"
)

func main() {
	// Test loading the config with auto_add
	cfg, err := config.Load("")
	if err != nil {
		fmt.Printf("Error loading config: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Config loaded successfully!\n")
	fmt.Printf("Default Provider: %s\n", cfg.DefaultProvider)
	fmt.Printf("Auto Add: %v\n", cfg.AutoAdd)
	fmt.Printf("System Prompt: %s\n", cfg.SystemPrompt)

	provider, err := cfg.GetDefaultProvider()
	if err != nil {
		fmt.Printf("Error getting provider: %v\n", err)
		return
	}

	fmt.Printf("Provider API Key: %s...\n", provider.APIKey[:10])
	fmt.Printf("Provider Model: %s\n", provider.Model)
}
