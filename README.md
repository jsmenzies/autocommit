# AutoCommit

A CLI tool that analyzes Git history and generates conventional commit messages using LLM providers.

## Features

- 🤖 AI-powered commit message generation
- 📝 Follows conventional commits specification
- ⚙️ Configurable LLM providers (z.ai, OpenAI, and Groq)
- 🖥️ Cross-platform: Windows, macOS, Linux
- 🔧 Simple configuration via YAML

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

1. **Configure the tool:**
   ```bash
   autocommit config init
   autocommit config set providers.zai.api_key YOUR_API_KEY
   ```

2. **Stage your changes:**
   ```bash
   git add .
   ```

3. **Generate commit message:**
   ```bash
   autocommit generate
   ```

## Configuration

The configuration file is stored at:
- **Linux/macOS:** `~/.config/autocommit/config.yaml`
- **Windows:** `%APPDATA%\autocommit\config.yaml`

### Example Configuration

```yaml
default_provider: zai
providers:
  zai:
    apikey: your-zai-api-key-here
    model: glm-4.7
  openai:
    apikey: your-openai-api-key-here
    model: gpt-4o-mini
  groq:
    apikey: your-groq-api-key-here
    model: llama-3.1-8b-instant
```

## Usage

### Commands

- `autocommit generate` - Generate a commit message for staged changes
- `autocommit commit` - Generate and automatically commit with the message
- `autocommit config init` - Create initial configuration file
- `autocommit config show` - Display current configuration
- `autocommit config set <key> <value>` - Update configuration value

### Options

- `--config <path>` - Use custom configuration file
- `--version` - Show version information
- `--help` - Show help message

## Development

### Prerequisites

- Go 1.21 or later
- Git

### Building

```bash
make build
```

### Testing

```bash
make test
```

## License

MIT License - see LICENSE file for details
