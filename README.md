# AutoCommit (Zig Rewrite)

A CLI tool that analyzes Git history and generates conventional commit messages using LLM providers.

> **Status**: Work in progress - Zig rewrite at Stage 4 of migration

## Current Implementation Status

### ✅ Implemented
- CLI argument parsing with help, version, and config commands
- Configuration management (JSON-based)
- Cross-platform config file paths (macOS/Linux)
- GitHub CI/CD workflows (PR checks, releases)
- Debug mode support

### 🚧 Not Yet Implemented
- Git operations (diff, commit, push)
- HTTP client for API calls
- LLM provider implementations (z.ai, OpenAI, Groq)
- Commit message generation
- Interactive prompts

## Installation

### Homebrew (macOS/Linux)

```bash
brew tap jsmenzies/tap
brew install autocommit
```

### From Source

Requires Zig 0.13.0 or later:

```bash
git clone https://github.com/jsmenzies/autocommit.git
cd autocommit
zig build
```

The binary will be at `zig-out/bin/autocommit`.

### Pre-built Binaries

Download from [releases page](https://github.com/jsmenzies/autocommit/releases) (coming soon).

## Usage

### Commands

```bash
autocommit                    # Default: generate commit message (placeholder)
autocommit help               # Show help
autocommit --help             # Show help
autocommit -h                 # Show help
autocommit version            # Show version
autocommit --version          # Show version
autocommit -v                 # Show version
autocommit config             # Open config in default editor
autocommit config print       # Display current configuration
```

### Options

- `-p, --provider <name>` - Override provider (zai, openai, groq)
- `-m, --model <name>` - Override model
- `-d, --debug` - Enable debug output

### Examples

```bash
# Generate commit message using default provider and model from config
autocommit

# Generate with specific provider and model overrides
autocommit -p groq -m llama-3.1-8b-instant

# Edit configuration in default editor
autocommit config

# Show current configuration
autocommit config print

# Show help
autocommit help
```

## Configuration

Configuration is stored as JSON at `~/.config/autocommit/config.json` by default on both macOS and Linux.

If the `XDG_CONFIG_HOME` environment variable is set, the config will be stored at `$XDG_CONFIG_HOME/autocommit/config.json` instead.

### Example Configuration

Run `autocommit config` to create and edit the configuration file.

> **Note**: Groq offers a free tier for many models. Sign up at https://groq.com to get an API key.

```json
{
  "default_provider": "groq",
  "auto_add": false,
  "auto_push": false,
  "system_prompt": "You are a commit message generator. Analyze the git diff and create a conventional commit message following best practices.",
  "providers": {
    "groq": {
      "api_key": "your-groq-api-key-here",
      "model": "llama-3.1-8b-instant",
      "endpoint": "https://api.groq.com/openai/v1/chat/completions"
    }
  }
}
```

### Configuration Options

- `default_provider` - Which LLM provider to use (zai, openai, groq)
- `auto_add` - Automatically run `git add .` if no staged changes
- `auto_push` - Automatically push after committing
- `system_prompt` - Custom prompt for commit message generation
- `providers.{name}.api_key` - API key for the provider
- `providers.{name}.model` - Model to use
- `providers.{name}.endpoint` - API endpoint URL

## Build Commands

For development and testing:

```bash
zig build              # Development build
zig build test         # Run tests
zig build run          # Build and run
zig build -Doptimize=ReleaseSmall  # Optimized build
```

## Development

### Running Tests

```bash
zig build test
```

### Cross Compilation

```bash
# macOS ARM64
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSmall

# Linux x86_64 (static)
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSmall
```

## Migration from Go

This is a ground-up rewrite from Go to Zig with the following goals:
- Smaller binaries (~200KB vs ~3MB)
- Faster startup times
- Simpler architecture (no TUI, file-based config)
- Standard library only (minimal dependencies)

See [MIGRATION_PLAN.md](./MIGRATION_PLAN.md) for detailed migration stages.

## License

MIT License - see LICENSE file for details
