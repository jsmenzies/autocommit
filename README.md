# AutoCommit

A CLI tool that analyzes Git history and generates conventional commit messages using LLM providers.

## Features

- 🤖 AI-powered commit message generation
- 📝 Follows conventional commits specification
- 🖥️ Interactive TUI for easy configuration
- ⚙️ Configurable LLM providers (starting with z.ai)
- 🔧 Git auto-add support for convenience
- ✏️ Customizable system prompts
- 🖥️ Cross-platform: Windows, macOS, Linux

## Installation

### Homebrew (macOS / Linux)

```bash
brew tap jsmenzies/autocommit
brew install autocommit
```

### Scoop (Windows)

```powershell
scoop bucket add autocommit https://github.com/jsmenzies/scoop-autocommit
scoop install autocommit
```

### From Source

```bash
go install github.com/jsmenzies/autocommit/cmd/autocommit@latest
```

### Pre-built Binaries

Download the latest release from the [releases page](https://github.com/jsmenzies/autocommit/releases).

## Quick Start

### Interactive TUI (Recommended)

Simply run `autocommit` to launch the interactive configuration TUI:

```bash
autocommit
```

This will open a menu where you can:
- Configure LLM provider and API key
- Edit the system prompt for commit generation
- Configure Git settings (auto-add)

### CLI Configuration

Alternatively, you can configure via CLI:

```bash
autocommit config init
autocommit config set providers.zai.api_key YOUR_API_KEY
```

### Generate Commit Messages

**Quick generate (bypasses TUI):**
```bash
autocommit -g
# or
autocommit --generate
```

**With auto-add enabled:**
```bash
autocommit commit
```

## Configuration

The configuration file is stored at:
- **macOS:** `~/Library/Application Support/autocommit/config.yaml`
- **Linux:** `~/.config/autocommit/config.yaml`
- **Windows:** `%APPDATA%\autocommit\config.yaml`

### Example Configuration

```yaml
default_provider: zai
auto_add: true
system_prompt: ""
providers:
  zai:
    apikey: your-api-key-here
    model: glm-4.7-Flash
```

### Configuration Options

- `default_provider` - Which LLM provider to use (currently only "zai")
- `auto_add` - Automatically run `git add .` if no staged changes (default: false)
- `system_prompt` - Custom prompt for commit message generation (empty = use default)
- `providers.zai.apikey` - Your z.ai API key
- `providers.zai.model` - Model to use: `glm-4.7-Flash`, `glm-4.7-FlashX`, or `glm-4.7`

### Models

Available z.ai models:
- **glm-4.7-Flash** - Lightweight, free tier (recommended for most users)
- **glm-4.7-FlashX** - Faster version with higher rate limits
- **glm-4.7** - Full flagship model (requires API credits)

## Usage

### Commands

- `autocommit` - Launch interactive TUI for configuration
- `autocommit -g, --generate` - Generate commit message for staged changes (bypass TUI)
- `autocommit commit` - Generate message and automatically commit
- `autocommit generate` - Generate commit message interactively
- `autocommit config init` - Create initial configuration file
- `autocommit config show` - Display current configuration
- `autocommit config set <key> <value>` - Update configuration value

### Options

- `--config <path>` - Use custom configuration file
- `-g, --generate` - Run generate directly (bypass TUI)
- `--version` - Show version information
- `--help` - Show help message

## System Prompt

The default system prompt instructs the LLM to generate conventional commit messages following best practices:

- Format: `<type>(<scope>): <subject>`
- Types: feat, fix, docs, style, refactor, test, chore
- Scope is optional - omit if not needed
- Keep subject under 72 characters
- Use present tense, imperative mood

You can customize the prompt via the TUI (Git Configuration → Edit System Prompt) or by editing the `system_prompt` field in your config file.

## Troubleshooting

### "Insufficient balance or no resource package"

Your z.ai account needs API credits. The free tier includes `glm-4.7-Flash`, but other models require a subscription. Try switching to `glm-4.7-Flash` in the TUI.

### "Unknown Model" error

Make sure you're using one of the supported model names:
- `glm-4.7-Flash`
- `glm-4.7-FlashX`
- `glm-4.7`

## Development

### Prerequisites

- Go 1.21 or later
- Git

### Building

```bash
go build ./cmd/autocommit
```

### Testing

```bash
go test ./...
```

## License

MIT License - see LICENSE file for details
