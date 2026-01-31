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
autocommit                    # Generate commit message interactively
autocommit config             # Open config in default editor
autocommit config show        # Display current configuration
autocommit config path        # Show configuration file path
```

### Options

- `--add` - Auto-add all unstaged files before committing
- `--push` - Auto-push after committing
- `--accept` - Auto-accept generated commit message without prompting
- `--provider <name>` - Override provider (zai, openai, groq)
- `--model <name>` - Override model
- `--debug` - Enable debug output
- `--version` - Show version information
- `--help` - Show help message

### Examples

```bash
# Generate commit message interactively (default)
autocommit

# Full automation: add all files, auto-accept commit, and push
autocommit --add --accept --push

# Auto-add all files and commit
autocommit --add

# Full automated workflow: add, commit, and push
autocommit --add --push

# Use specific provider
autocommit --provider groq

# Use specific provider and model
autocommit --provider groq --model llama-3.1-8b-instant

# Full automation with provider override
autocommit --add --accept --push --provider groq

# Note: All flags can be mixed and matched. Remove any you don't need:
#   autocommit --add              # Just add files
#   autocommit --add --push       # Add and push (review commit message)
#   autocommit --accept --push    # Accept and push (files already staged)

# Edit configuration in default editor
autocommit config

# Display current configuration
autocommit config show

# Show configuration file path
autocommit config path

# Show version
autocommit --version

# Show help
autocommit --help
```

### Shell Alias (Optional)

For a fully automated workflow, add this alias to your shell configuration:

```bash
# ~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish
alias ac='autocommit --add --accept --push'
```

With this alias, running `ac` will:
1. Auto-add all unstaged/untracked files to git
2. Generate a conventional commit message using AI
3. Auto-accept the commit message (no prompting)
4. Push the commit to the remote repository

This provides a quick "commit and push everything" workflow for rapid development.

**Note:** You can modify the flags to suit your needs:
- Remove `--accept` if you want to review/edit the commit message
- Remove `--push` if you don't want to push immediately
- Add `--provider <name>` to use a specific provider

## Configuration

Configuration is stored as JSON at `~/.config/autocommit/config.json` by default on both macOS and Linux.

If the `XDG_CONFIG_HOME` environment variable is set, the config will be stored at `$XDG_CONFIG_HOME/autocommit/config.json` instead.

### Example Configuration

Run `autocommit config` to create and edit the configuration file.

> **Note**: Groq offers a free tier for many models. Sign up at https://groq.com to get an API key.

```json
{
  "default_provider": "groq",
  "system_prompt": "<see Default Prompt section below>",
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

## Default Prompt

The default system prompt used for commit message generation:

```
You are a commit message generator. Analyze the git diff and create a conventional commit message.
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
- feat: add new feature without scope
```

## License

MIT License - see LICENSE file for details
