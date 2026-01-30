package cmd

import (
	"autocommit/internal/config"
	"autocommit/internal/debug"
	"autocommit/internal/git"
	"autocommit/internal/llm"
	"autocommit/internal/prompt"
	"autocommit/internal/tui"
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
)

var (
	cfgFile      string
	generateFlag bool
	debugFlag    bool
	rootCmd      = &cobra.Command{
		Use:   "autocommit",
		Short: "AI-powered conventional commit message generator",
		Long: `AutoCommit analyzes your staged Git changes and generates conventional commit messages
using LLM providers. Supports z.ai (GLM models), OpenAI (GPT models), and Groq (ultra-fast inference).`,
		RunE: func(cmd *cobra.Command, args []string) error {
			// If -g flag is set, run generate directly
			if generateFlag {
				return runGenerate(cmd, args)
			}
			// Otherwise, launch the TUI for configuration
			return tui.Run()
		},
	}
)

func Execute(version, commit, buildTime string) error {
	rootCmd.Version = version
	return rootCmd.Execute()
}

func init() {
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $XDG_CONFIG_HOME/autocommit/config.yaml)")
	rootCmd.PersistentFlags().BoolVarP(&generateFlag, "generate", "g", false, "Run generate directly (bypass TUI)")
	rootCmd.PersistentFlags().BoolVarP(&debugFlag, "debug", "d", false, "Enable debug mode (verbose output)")

	rootCmd.PersistentPreRun = func(cmd *cobra.Command, args []string) {
		debug.Enabled = debugFlag
	}

	rootCmd.AddCommand(configCmd)
	rootCmd.AddCommand(generateCmd)
	rootCmd.AddCommand(commitCmd)
	rootCmd.AddCommand(versionCmd)
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print version information",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("autocommit version %s\n", rootCmd.Version)
	},
}
var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Manage autocommit configuration",
}
var configInitCmd = &cobra.Command{
	Use:   "init",
	Short: "Create initial configuration file",
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := config.Init(); err != nil {
			return err
		}
		cfgPath, _ := config.GetConfigPath()
		fmt.Printf("Configuration file created at: %s\n", cfgPath)
		fmt.Println("Please edit the file and add your API key.")
		return nil
	},
}
var configShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Display current configuration",
	RunE: func(cmd *cobra.Command, args []string) error {
		_, content, err := config.Show()
		if err != nil {
			return err
		}
		fmt.Println(content)
		return nil
	},
}
var configSetCmd = &cobra.Command{
	Use:   "set [key] [value]",
	Short: "Update a configuration value",
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		return config.Set(args[0], args[1])
	},
}

func init() {
	configCmd.AddCommand(configInitCmd)
	configCmd.AddCommand(configShowCmd)
	configCmd.AddCommand(configSetCmd)
}

func runGenerate(cmd *cobra.Command, args []string) error {
	const maxRegenerations = 10

	for attempt := 0; attempt < maxRegenerations; attempt++ {
		message, cfg, err := generateWorkflow(cfgFile, true)
		if err != nil {
			return err
		}

		fmt.Printf("\nSuggested commit message:\n%s\n\n", message)
		action, err := promptUserAction(cfg)
		if err != nil {
			return err
		}
		switch action {
		case "commit":
			if err := git.DoCommit(message); err != nil {
				return err
			}
			fmt.Println("Changes committed successfully!")
			// Auto-push if enabled
			if cfg.AutoPush {
				fmt.Println("Auto-pushing to remote...")
				if err := git.Push(); err != nil {
					return fmt.Errorf("commit succeeded but push failed: %w", err)
				}
				fmt.Println("Changes pushed successfully!")
			}
			return nil
		case "regenerate":
			fmt.Println("Regenerating...")
			continue
		case "edit":
			edited, err := prompt.EditMessage(message)
			if err != nil {
				return err
			}
			fmt.Printf("Edited message:\n%s\n", edited)
			return nil
		case "cancel":
			fmt.Println("Cancelled")
			return nil
		}
	}
	return fmt.Errorf("maximum regeneration attempts (%d) reached", maxRegenerations)
}

var generateCmd = &cobra.Command{
	Use:     "generate",
	Short:   "Generate a commit message for staged changes",
	Aliases: []string{"g", "gen"},
	RunE:    runGenerate,
}

func runCommit(cmd *cobra.Command, args []string) error {
	message, cfg, err := generateWorkflow(cfgFile, true)
	if err != nil {
		return err
	}

	fmt.Printf("Committing with message: %s\n", message)
	if err := git.DoCommit(message); err != nil {
		return err
	}
	fmt.Println("Changes committed successfully!")

	if cfg.AutoPush {
		fmt.Println("Auto-pushing to remote...")
		if err := git.Push(); err != nil {
			return fmt.Errorf("commit succeeded but push failed: %w", err)
		}
		fmt.Println("Changes pushed successfully!")
	}
	return nil
}

var commitCmd = &cobra.Command{
	Use:   "commit",
	Short: "Generate message and commit changes",
	RunE:  runCommit,
}

// generateWorkflow encapsulates the shared workflow for generating commit messages
// Returns the generated message, the config used, and any error
func generateWorkflow(cfgFile string, autoAdd bool) (string, *config.Config, error) {
	if !git.IsGitRepo() {
		return "", nil, fmt.Errorf("not a git repository")
	}

	cfg, err := config.Load(cfgFile)
	if err != nil {
		return "", nil, fmt.Errorf("failed to load config: %w", err)
	}

	// Handle auto_add: if enabled, always stage all changes unconditionally
	if cfg.AutoAdd {
		fmt.Println("Auto-adding all changes...")
		if err := git.AddAll(); err != nil {
			return "", nil, fmt.Errorf("failed to auto-add changes: %w", err)
		}
	}

	// Check if we have staged changes to generate a message from
	if !git.HasStagedChanges() {
		return "", nil, fmt.Errorf("no staged changes found. Run 'git add' first or enable auto_add in config")
	}

	providerCfg, err := cfg.GetDefaultProvider()
	if err != nil {
		return "", nil, err
	}

	diff, err := git.GetStagedDiff()
	if err != nil {
		return "", nil, err
	}

	recentCommits, err := git.GetRecentCommitMessages(5)
	if err != nil {
		recentCommits = []string{}
	}

	provider, err := createProvider(cfg.DefaultProvider, providerCfg, cfg.GetSystemPrompt())
	if err != nil {
		return "", nil, err
	}

	ctx := context.Background()
	message, err := provider.GenerateCommitMessage(ctx, diff, recentCommits)
	if err != nil {
		return "", nil, fmt.Errorf("failed to generate message: %w", err)
	}

	if strings.TrimSpace(message) == "" {
		return "", nil, fmt.Errorf("generated message is empty - please try again or check your API key and model settings")
	}

	return message, cfg, nil
}

func createProvider(providerName string, providerCfg config.ProviderConfig, systemPrompt string) (llm.Provider, error) {
	return llm.CreateProvider(providerName, providerCfg.APIKey, providerCfg.Model, systemPrompt)
}

func promptUserAction(cfg *config.Config) (string, error) {
	fmt.Println("Options:")
	if cfg.AutoPush {
		fmt.Println("  [enter] Commit and push")
	} else {
		fmt.Println("  [enter] Commit")
	}
	fmt.Println("  [r] Regenerate message")
	fmt.Println("  [e] Edit message")
	fmt.Println("  [q] Quit")
	fmt.Print("\nChoice (enter/r/e/q): ")
	reader := bufio.NewReader(os.Stdin)
	input, err := reader.ReadString('\n')
	if err != nil {
		return "", err
	}
	input = strings.TrimSpace(strings.ToLower(input))
	switch input {
	case "", "enter":
		return "commit", nil
	case "r", "regenerate":
		return "regenerate", nil
	case "e", "edit":
		return "edit", nil
	case "q", "quit", "cancel":
		return "cancel", nil
	default:
		fmt.Println("Invalid choice, defaulting to quit")
		return "cancel", nil
	}
}
