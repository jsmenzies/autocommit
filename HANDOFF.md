# AutoCommit Project Handoff

## Project Overview

AutoCommit is a CLI tool written in Go that analyzes Git history and generates conventional commit messages using LLM providers. The first supported provider is z.ai (GLM models).

## Project Structure

```
autocommit/
├── cmd/autocommit/main.go        # CLI entry point
├── internal/
│   ├── cmd/root.go              # Cobra commands (config, generate, commit)
│   ├── config/config.go         # XDG-compliant configuration management
│   ├── git/git.go               # Git operations (diff, status, commits)
│   ├── llm/zai.go               # z.ai LLM provider implementation
│   └── prompt/prompt.go         # Interactive prompt handling
├── .github/workflows/           # CI/CD workflows
│   ├── pr-check.yml             # PR validation
│   └── release.yml              # Cross-platform releases
├── mise.toml                    # Tool version management (Go 1.21)
├── go.mod                       # Go module definition
└── README.md                    # User documentation
```

## Implemented Features

### Commands
- `autocommit config init` - Create config at `$XDG_CONFIG_HOME/autocommit/config.yaml`
- `autocommit config show` - Display current config
- `autocommit config set <key> <value>` - Update config values
- `autocommit generate` (aliases: `g`, `gen`) - Generate commit message interactively
- `autocommit commit` - Generate message and commit in one step
- `autocommit version` - Show version
- `autocommit completion` - Generate shell completions

### Configuration
Config file location (XDG compliant):
- Linux/macOS: `~/.config/autocommit/config.yaml`
- Windows: `%APPDATA%\autocommit\config.yaml`

Example config:
```yaml
default_provider: zai
providers:
  zai:
    api_key: YOUR_API_KEY_HERE
    model: glm-4.7
```

### Interactive Flow
When running `autocommit generate`, the user is presented with:
1. Generated commit message
2. Options: [a]ccept, [c]ommit, [r]egenerate, [e]dit, cancel

## Technical Details

### Dependencies
- `github.com/spf13/cobra` - CLI framework
- `github.com/spf13/viper` - Configuration management
- Standard library only for Git operations (no go-git)

### LLM Integration (z.ai)
- Endpoint: `POST https://api.z.ai/api/paas/v4/chat/completions`
- Hardcoded parameters:
  - temperature: 0.7
  - max_tokens: 500
- Uses system prompt to enforce conventional commit format

### Git Operations
- `git diff --cached` - Get staged changes
- `git log -n 5` - Get recent commits for context
- `git commit -m "message"` - Create commit

## Build & Release

### Local Build
```bash
go build ./cmd/autocommit
```

### CI/CD
- **PR Validation**: Runs on PRs to main/master, checks formatting, builds, runs tests
- **Release**: Triggered on version tags (v*), builds for Linux, macOS, Windows (amd64 + arm64)

### Tool Versions (mise.toml)
- Go: 1.21
- golangci-lint: 1.55

## What's Working

✅ Git repository detection
✅ Staged changes detection
✅ Config file creation and management
✅ z.ai API integration
✅ Conventional commit message generation
✅ Interactive user prompts
✅ Cross-platform CI/CD
✅ XDG config directory support

## Next Steps / TODO

- [ ] Add more LLM providers (OpenAI, Anthropic, local models)
- [ ] Add tests (unit + integration)
- [ ] Add --dry-run flag
- [ ] Add support for multi-line commit messages
- [ ] Add git hook integration
- [ ] Improve error handling and user feedback
- [ ] Add verbose logging option
- [ ] Support for conventional commits with body/footer
- [ ] Add emoji support toggle
- [ ] Implement proper keyring integration for API keys

## Architecture Notes

### Provider Interface
```go
type Provider interface {
    GenerateCommitMessage(ctx context.Context, diff string, recentCommits []string) (string, error)
    Name() string
}
```

New providers should implement this interface and be registered in `internal/cmd/root.go`.

### Configuration System
- Uses Viper for YAML parsing
- Supports nested keys (e.g., `providers.zai.api_key`)
- Environment variable overrides not yet implemented

### Error Handling
Currently uses simple error wrapping with `fmt.Errorf()`. Consider adding:
- Custom error types for better handling
- User-friendly error messages
- Suggestions for common errors (e.g., "API key not found - run 'autocommit config init'")

## Known Issues / Limitations

1. No tests implemented yet
2. API keys stored in plaintext (security concern)
3. No support for git commit hooks
4. No batch processing for multiple commits
5. Limited to conventional commit format (no body/footer)
6. No caching of API responses

## Development Commands

```bash
# Format code
gofmt -s -w .

# Build binary
go build ./cmd/autocommit

# Run
go run ./cmd/autocommit --help

# Tidy modules
go mod tidy

# Check formatting
if [ "$(gofmt -s -l . | wc -l)" -gt 0 ]; then echo "Unformatted files found"; fi
```

## Resources

- z.ai API docs: https://docs.z.ai/api-reference/llm/chat-completion
- Cobra docs: https://github.com/spf13/cobra
- Conventional Commits: https://www.conventionalcommits.org/
