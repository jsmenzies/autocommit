package config

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/viper"
)

const (
	appName = "autocommit"
)

type ProviderConfig struct {
	APIKey  string `mapstructure:"apikey"`
	Model   string `mapstructure:"model"`
	BaseURL string `mapstructure:"baseurl,omitempty"`
}

type Config struct {
	DefaultProvider string                    `mapstructure:"default_provider"`
	SystemPrompt    string                    `mapstructure:"system_prompt,omitempty"`
	AutoAdd         bool                      `mapstructure:"auto_add,omitempty"`
	AutoPush        bool                      `mapstructure:"auto_push,omitempty"`
	Providers       map[string]ProviderConfig `mapstructure:"providers"`
}

// DefaultSystemPrompt is the default prompt used for generating commit messages
const DefaultSystemPrompt = `You are a commit message generator. Analyze the git diff and create a conventional commit message.
Follow these rules:
- Use format: <type>(<scope>): <subject>
- Types: feat, fix, docs, style, refactor, test, chore
- Scope is optional - omit if not needed
- Keep subject under 72 characters
- Use present tense, imperative mood
- Be specific but concise
- Do not include any explanation, only output the commit message
- Do not use markdown code blocks

Examples:
- feat(auth): add password validation to login form
- fix(api): handle nil pointer in user service
- docs(readme): update installation instructions
- refactor(db): optimize query performance with index
- feat: add new feature without scope`

func GetConfigDir() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("failed to get config directory: %w", err)
	}
	return filepath.Join(configDir, appName), nil
}

func GetConfigPath() (string, error) {
	configDir, err := GetConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(configDir, "config.yaml"), nil
}

func Load(configPath string) (*Config, error) {
	if configPath == "" {
		var err error
		configPath, err = GetConfigPath()
		if err != nil {
			return nil, err
		}
	}

	viper.SetConfigFile(configPath)
	viper.SetConfigType("yaml")

	if err := viper.ReadInConfig(); err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("config file not found at %s, run 'autocommit config init' to create one", configPath)
		}
		return nil, fmt.Errorf("failed to read config: %w", err)
	}

	var cfg Config
	if err := viper.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	return &cfg, nil
}

func (c *Config) GetProvider(name string) (ProviderConfig, error) {
	if name == "" {
		name = c.DefaultProvider
	}

	provider, exists := c.Providers[name]
	if !exists {
		return ProviderConfig{}, fmt.Errorf("provider '%s' not found in config", name)
	}

	return provider, nil
}

func (c *Config) GetDefaultProvider() (ProviderConfig, error) {
	return c.GetProvider(c.DefaultProvider)
}

func Init() error {
	configDir, err := GetConfigDir()
	if err != nil {
		return err
	}

	if err := os.MkdirAll(configDir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	configPath := filepath.Join(configDir, "config.yaml")

	if _, err := os.Stat(configPath); err == nil {
		return fmt.Errorf("config file already exists at %s", configPath)
	}

	// Initialize with empty provider - TUI will guide user through setup
	defaultConfig := `# AutoCommit Configuration
# Run 'autocommit' to configure via TUI

system_prompt: ""
default_provider: ""

providers: {}
`

	if err := os.WriteFile(configPath, []byte(defaultConfig), 0644); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	return nil
}

func (c *Config) GetSystemPrompt() string {
	if c.SystemPrompt == "" {
		return DefaultSystemPrompt
	}
	return c.SystemPrompt
}

func Save(cfg *Config) error {
	configPath, err := GetConfigPath()
	if err != nil {
		return err
	}

	configDir, err := GetConfigDir()
	if err != nil {
		return err
	}

	if err := os.MkdirAll(configDir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	viper.Set("system_prompt", cfg.SystemPrompt)
	viper.Set("default_provider", cfg.DefaultProvider)
	viper.Set("auto_add", cfg.AutoAdd)
	viper.Set("auto_push", cfg.AutoPush)
	viper.Set("providers", cfg.Providers)
	viper.SetConfigFile(configPath)
	viper.SetConfigType("yaml")

	if err := viper.WriteConfigAs(configPath); err != nil {
		return fmt.Errorf("failed to write config: %w", err)
	}

	return nil
}

func Show() (*Config, string, error) {
	configPath, err := GetConfigPath()
	if err != nil {
		return nil, "", err
	}

	cfg, err := Load(configPath)
	if err != nil {
		return nil, "", err
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, "", fmt.Errorf("failed to read config file: %w", err)
	}

	return cfg, string(data), nil
}

func Set(key string, value string) error {
	configPath, err := GetConfigPath()
	if err != nil {
		return err
	}

	viper.SetConfigFile(configPath)
	viper.SetConfigType("yaml")

	if err := viper.ReadInConfig(); err != nil {
		return fmt.Errorf("failed to read config: %w", err)
	}

	viper.Set(key, value)

	if err := viper.WriteConfig(); err != nil {
		return fmt.Errorf("failed to write config: %w", err)
	}

	return nil
}
