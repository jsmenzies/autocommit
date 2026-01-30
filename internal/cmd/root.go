package cmd

import (
	"autocommit/internal/config"
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
	rootCmd      = &cobra.Command{
		Use:   "autocommit",
		Short: "AI-powered conventional commit message generator",
		Long: `AutoCommit analyzes your staged Git changes and generates conventional commit messages
using LLM providers. Currently supports z.ai (GLM models).`,
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
	if !git.IsGitRepo() {
		return fmt.Errorf("not a git repository")
	}
	cfg, err := config.Load(cfgFile)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}
	if !git.HasStagedChanges() {
		if cfg.AutoAdd {
			fmt.Println("Auto-adding all changes...")
			if err := git.AddAll(); err != nil {
				return fmt.Errorf("failed to auto-add changes: %w", err)
			}
		} else {
			return fmt.Errorf("no staged changes found. Run 'git add' first or enable auto_add in config")
		}
	}
	providerCfg, err := cfg.GetDefaultProvider()
	if err != nil {
		return err
	}
	diff, err := git.GetStagedDiff()
	if err != nil {
		return err
	}
	recentCommits, err := git.GetRecentCommitMessages(5)
	if err != nil {
		recentCommits = []string{}
	}
	var provider llm.Provider
	switch cfg.DefaultProvider {
	case "zai":
		provider = llm.NewZaiProvider(providerCfg.APIKey, providerCfg.Model, cfg.GetSystemPrompt())
	default:
		return fmt.Errorf("unsupported provider: %s", cfg.DefaultProvider)
	}
	ctx := context.Background()
	message, err := provider.GenerateCommitMessage(ctx, diff, recentCommits)
	if err != nil {
		return fmt.Errorf("failed to generate message: %w", err)
	}
	fmt.Printf("\nSuggested commit message:\n%s\n\n", message)
	action, err := promptUserAction()
	if err != nil {
		return err
	}
	switch action {
	case "accept":
		fmt.Println("Use 'autocommit commit' to commit with this message")
	case "commit":
		if err := git.DoCommit(message); err != nil {
			return err
		}
		fmt.Println("Changes committed successfully!")
	case "regenerate":
		fmt.Println("Regenerating...")
		return runGenerate(cmd, args)
	case "edit":
		edited, err := prompt.EditMessage(message)
		if err != nil {
			return err
		}
		fmt.Printf("Edited message:\n%s\n", edited)
		return nil
	case "cancel":
		fmt.Println("Cancelled")
	}
	return nil
}

var generateCmd = &cobra.Command{
	Use:     "generate",
	Short:   "Generate a commit message for staged changes",
	Aliases: []string{"g", "gen"},
	RunE:    runGenerate,
}

func runCommit(cmd *cobra.Command, args []string) error {
	if !git.IsGitRepo() {
		return fmt.Errorf("not a git repository")
	}
	cfg, err := config.Load(cfgFile)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}
	if !git.HasStagedChanges() {
		if cfg.AutoAdd {
			fmt.Println("Auto-adding all changes...")
			if err := git.AddAll(); err != nil {
				return fmt.Errorf("failed to auto-add changes: %w", err)
			}
		} else {
			return fmt.Errorf("no staged changes found. Run 'git add' first or enable auto_add in config")
		}
	}
	providerCfg, err := cfg.GetDefaultProvider()
	if err != nil {
		return err
	}
	diff, err := git.GetStagedDiff()
	if err != nil {
		return err
	}
	recentCommits, err := git.GetRecentCommitMessages(5)
	if err != nil {
		recentCommits = []string{}
	}
	var provider llm.Provider
	switch cfg.DefaultProvider {
	case "zai":
		provider = llm.NewZaiProvider(providerCfg.APIKey, providerCfg.Model, cfg.GetSystemPrompt())
	default:
		return fmt.Errorf("unsupported provider: %s", cfg.DefaultProvider)
	}
	ctx := context.Background()
	message, err := provider.GenerateCommitMessage(ctx, diff, recentCommits)
	if err != nil {
		return fmt.Errorf("failed to generate message: %w", err)
	}
	fmt.Printf("Committing with message: %s\n", message)
	if err := git.DoCommit(message); err != nil {
		return err
	}
	fmt.Println("Changes committed successfully!")
	return nil
}

var commitCmd = &cobra.Command{
	Use:   "commit",
	Short: "Generate message and commit changes",
	RunE:  runCommit,
}

func promptUserAction() (string, error) {
	fmt.Println("Options:")
	fmt.Println("  [a] Accept and show (use 'autocommit commit' to commit)")
	fmt.Println("  [c] Accept and commit immediately")
	fmt.Println("  [r] Regenerate message")
	fmt.Println("  [e] Edit message")
	fmt.Println("  [x] Cancel")
	fmt.Print("\nChoice (a/c/r/e/x): ")
	reader := bufio.NewReader(os.Stdin)
	input, err := reader.ReadString('\n')
	if err != nil {
		return "", err
	}
	input = strings.TrimSpace(strings.ToLower(input))
	switch input {
	case "a", "accept":
		return "accept", nil
	case "c", "commit":
		return "commit", nil
	case "r", "regenerate":
		return "regenerate", nil
	case "e", "edit":
		return "edit", nil
	case "x", "cancel":
		return "cancel", nil
	default:
		fmt.Println("Invalid choice, defaulting to cancel")
		return "cancel", nil
	}
}
