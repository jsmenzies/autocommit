# Migration Plan: Go → Zig for AutoCommit

## Overview

**Goal:** Replace the Go implementation with a minimal Zig version that maintains all core functionality but removes the TUI in favor of a simpler workflow. When `--config` is passed, open the user's default editor with an example configuration file.

**Target Platforms:** 
- macOS: `aarch64-macos` (M1/M2 only)
- Linux: `x86_64-linux-musl` (static binary)

**Key Changes:**
- Remove TUI entirely
- Config via file editor instead of interactive prompts
- Standard library only (no external dependencies initially, TOML added in Stage 10)
- Much smaller binaries (~200KB vs ~3MB)
- Full GitHub CI/CD with automated releases

**Config Format:** JSON initially (Stage 4), migrate to TOML in Stage 10

---

## Project Structure (Final)

```
autocommit/
├── build.zig                 # Build configuration
├── build.zig.zon            # Package manifest
├── .github/
│   └── workflows/
│       ├── pr-check.yml     # PR validation
│       └── release.yml      # Full release automation
├── src/
│   ├── main.zig            # Entry point
│   ├── cli.zig             # CLI argument parsing
│   ├── config.zig          # Config file handling (JSON → TOML)
│   ├── git.zig             # Git operations
│   ├── http_client.zig     # HTTP wrapper
│   ├── llm.zig             # Provider interface
│   ├── providers/          # Provider implementations
│   │   ├── zai.zig
│   │   ├── openai.zig
│   │   └── groq.zig
│   ├── prompt.zig          # System prompts
│   └── version.zig         # Version info
├── CHANGELOG.md            # Release notes
└── README.md               # Updated documentation
```

---

## Stage 0: Project Initialization

### 0.1 Create Zig Project Structure
**Verification:** `zig build` runs successfully

Create the directory structure above.

### 0.2 Configure build.zig
**Verification:** Can build for both targets

**Targets to configure:**
- Native (development)
- `aarch64-macos-none` (M1/M2)
- `x86_64-linux-musl` (Linux static)

**Build commands:**
```bash
zig build                          # Dev build
zig build -Dtarget=aarch64-macos   # macOS ARM
zig build -Dtarget=x86_64-linux-musl  # Linux x64
```

### 0.3 Configure build.zig.zon
**Verification:** `zig build` recognizes the project

Basic package manifest with name, version, and dependencies (empty initially).

---

## Stage 1: Minimal Working Binary

### 1.1 Hello World with Version
**Verification:** Binary runs and shows version

Create `src/main.zig`:
```zig
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("autocommit v0.1.0 (zig)\n", .{});
}
```

### 1.2 Cross-Compilation Test
**Verification:** Both targets build successfully

```bash
zig build-exe src/main.zig -target aarch64-macos -O ReleaseSmall -fstrip
zig build-exe src/main.zig -target x86_64-linux-musl -O ReleaseSmall -fstrip
```

**Expected output:** Two binaries, ~50-100KB each

**Test:** Run both binaries to confirm they work on their respective platforms.

---

## Stage 2: Full GitHub CI/CD Setup

### 2.1 PR Check Workflow
**Verification:** PRs trigger build checks

Create `.github/workflows/pr-check.yml`:

```yaml
name: PR Check

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  build:
    strategy:
      matrix:
        target: [aarch64-macos, x86_64-linux-musl]
        os: [macos-latest, ubuntu-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Zig
        uses: mlugg/setup-zig@v1
        with:
          version: 0.13.0
      
      - name: Build
        run: zig build -Dtarget=${{ matrix.target }} -Doptimize=ReleaseSmall
      
      - name: Test
        run: zig build test
      
      - name: Check formatting
        run: zig fmt --check src/
```

### 2.2 Full Release Workflow - Part 1
**Verification:** Tag push triggers release workflow

Create `.github/workflows/release.yml` (first part - build jobs):

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build:
    strategy:
      matrix:
        include:
          - target: aarch64-macos
            os: macos-14  # M1 runner
            name: autocommit-macos-arm64
          
          - target: x86_64-linux-musl
            os: ubuntu-latest
            name: autocommit-linux-x86_64

    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Zig
        uses: mlugg/setup-zig@v1
        with:
          version: 0.13.0
      
      - name: Build Release Binary
        run: |
          zig build -Dtarget=${{ matrix.target }} -Doptimize=ReleaseSmall -fstrip
          mv zig-out/bin/autocommit ${{ matrix.name }}
      
      - name: Generate Checksum
        run: |
          sha256sum ${{ matrix.name }} > ${{ matrix.name }}.sha256
          cat ${{ matrix.name }}.sha256
      
      - name: Upload Artifact
        uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.name }}
          path: |
            ${{ matrix.name }}
            ${{ matrix.name }}.sha256

### 2.3 Full Release Workflow - Part 2 (Release Job)
**Verification:** Release created with artifacts and changelog

Add to `.github/workflows/release.yml`:

```yaml
  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Need full history for changelog
      
      - name: Download Artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts
          merge-multiple: true
      
      - name: Generate Changelog
        id: changelog
        run: |
          # Get commits since last tag
          LAST_TAG=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")
          if [ -z "$LAST_TAG" ]; then
            COMMITS=$(git log --pretty=format:"- %s" --no-merges)
          else
            COMMITS=$(git log ${LAST_TAG}..HEAD --pretty=format:"- %s" --no-merges)
          fi
          
          # Categorize commits
          FEATS=$(echo "$COMMITS" | grep -E "^- feat" || true)
          FIXES=$(echo "$COMMITS" | grep -E "^- fix" || true)
          DOCS=$(echo "$COMMITS" | grep -E "^- docs" || true)
          OTHER=$(echo "$COMMITS" | grep -vE "^- (feat|fix|docs)" || true)
          
          # Build release notes
          NOTES="## What's New\n\n"
          if [ ! -z "$FEATS" ]; then
            NOTES="${NOTES}### Features\n${FEATS}\n\n"
          fi
          if [ ! -z "$FIXES" ]; then
            NOTES="${NOTES}### Bug Fixes\n${FIXES}\n\n"
          fi
          if [ ! -z "$DOCS" ]; then
            NOTES="${NOTES}### Documentation\n${DOCS}\n\n"
          fi
          if [ ! -z "$OTHER" ]; then
            NOTES="${NOTES}### Other Changes\n${OTHER}\n\n"
          fi
          
          NOTES="${NOTES}## Installation\n\n"
          NOTES="${NOTES}### macOS (Apple Silicon)\n\`\`\`bash\ncurl -L -o autocommit https://github.com/${{ github.repository }}/releases/download/${{ github.ref_name }}/autocommit-macos-arm64\nchmod +x autocommit\nsudo mv autocommit /usr/local/bin/\n\`\`\`\n\n"
          NOTES="${NOTES}### Linux (x86_64)\n\`\`\`bash\ncurl -L -o autocommit https://github.com/${{ github.repository }}/releases/download/${{ github.ref_name }}/autocommit-linux-x86_64\nchmod +x autocommit\nsudo mv autocommit /usr/local/bin/\n\`\`\`\n\n"
          
          MACOS_SHA=$(cat artifacts/autocommit-macos-arm64.sha256 | cut -d' ' -f1)
          LINUX_SHA=$(cat artifacts/autocommit-linux-x86_64.sha256 | cut -d' ' -f1)
          
          NOTES="${NOTES}## Checksums\n\n| File | SHA256 |\n|------|--------|\n"
          NOTES="${NOTES}| autocommit-macos-arm64 | \`${MACOS_SHA}\` |\n"
          NOTES="${NOTES}| autocommit-linux-x86_64 | \`${LINUX_SHA}\` |\n"
          
          echo "notes<<EOF" >> $GITHUB_OUTPUT
          echo -e "$NOTES" >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT
      
      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          body: ${{ steps.changelog.outputs.notes }}
          files: |
            artifacts/autocommit-macos-arm64
            artifacts/autocommit-macos-arm64.sha256
            artifacts/autocommit-linux-x86_64
            artifacts/autocommit-linux-x86_64.sha256
          draft: false
          prerelease: ${{ contains(github.ref_name, 'beta') || contains(github.ref_name, 'alpha') }}
```

### 2.4 Test Release Process
**Verification:** Complete release pipeline works

```bash
# Create a test tag
git tag v0.1.0-zig-test
git push origin v0.1.0-zig-test

# Wait for GitHub Actions to complete (2-3 minutes)
# Then verify:
# 1. Release appears at https://github.com/{owner}/autocommit/releases
# 2. Two binaries attached (autocommit-macos-arm64, autocommit-linux-x86_64)
# 3. SHA256 checksum files attached
# 4. Changelog generated from commits
# 5. Installation instructions present
# 6. Checksums table present
```

---

## Stage 3: CLI Argument Parsing

### 3.1 Define CLI Structure
**Verification:** Can parse all expected arguments

Create `src/cli.zig` with argument definitions:

**Arguments to support:**
- `--config` / `-c` → Open config in editor and exit
- `--generate` / `-g` → Generate commit message directly (skip TUI)
- `--provider` → Override provider from config
- `--model` → Override model from config
- `--debug` / `-d` → Enable debug output
- `--help` / `-h` → Show help text
- `--version` / `-v` → Show version

### 3.2 Implement Argument Parser
**Verification:** All flags work correctly

Using `std.process.args` and manual parsing (no external deps):

```zig
const CliArgs = struct {
    config: bool = false,
    generate: bool = false,
    provider: ?[]const u8 = null,
    model: ?[]const u8 = null,
    debug: bool = false,
    help: bool = false,
    version: bool = false,
};

fn parseArgs(allocator: std.mem.Allocator) !CliArgs {
    // Parse process arguments
    // Return filled CliArgs struct
}
```

### 3.3 Help Text
**Verification:** `./autocommit --help` shows comprehensive help

```
autocommit - AI-powered conventional commit message generator

Usage:
  autocommit [options]
  autocommit -g                    # Generate commit message directly
  autocommit --config              # Edit configuration file

Options:
  -c, --config          Open configuration file in editor
  -g, --generate        Generate commit message directly (bypass TUI)
  --provider <name>     Override provider (zai, openai, groq)
  --model <name>        Override model
  -d, --debug           Enable debug output
  -h, --help            Show this help message
  -v, --version         Show version information

Configuration:
  Config file location:
    macOS:  ~/Library/Application Support/autocommit/config.json
    Linux:  ~/.config/autocommit/config.json

  Run with --config to create and edit the configuration file.

Examples:
  autocommit --config              # Setup configuration
  autocommit -g                    # Generate message for staged changes
  autocommit -g --provider groq    # Use groq provider for this run
```

### 3.4 Version Output
**Verification:** `./autocommit --version` shows version

Format: `autocommit v0.1.0 (zig)`

---

## Stage 4: Configuration System (JSON)

### 4.1 Config File Paths
**Verification:** Correct paths for each OS

Create `src/config.zig`:

**macOS:** `~/Library/Application Support/autocommit/config.json`
**Linux:** `~/.config/autocommit/config.json`

Use `std.process.getEnvVarOwned` to get HOME, then construct path.

### 4.2 Config Structure
**Verification:** JSON serialization/deserialization works

```zig
const Config = struct {
    default_provider: []const u8,
    auto_add: bool,
    auto_push: bool,
    system_prompt: []const u8,
    providers: Providers,
};

const Providers = struct {
    zai: ProviderConfig,
    openai: ProviderConfig,
    groq: ProviderConfig,
};

const ProviderConfig = struct {
    api_key: []const u8,
    model: []const u8,
    endpoint: []const u8,
};
```

### 4.3 --config Flag Implementation
**Verification:** Opens editor with example config

**Logic:**
1. Determine config file path based on OS
2. Check if directory exists, create if not (`std.fs.makeDirRecursive`)
3. If config file doesn't exist, write example config
4. Get `$EDITOR` environment variable (fallback: `vi` on Unix, `notepad` on Windows)
5. Spawn editor process and wait for it to close
6. Validate JSON is parseable
7. Exit with success code (don't continue to generation)

**Example config template:**
```json
{
  "default_provider": "groq",
  "auto_add": false,
  "auto_push": false,
  "system_prompt": "You are a commit message generator. Analyze the git diff and create a conventional commit message following best practices.",
  "providers": {
    "zai": {
      "api_key": "your-zai-api-key-here",
      "model": "glm-4.7-Flash",
      "endpoint": "https://api.z.ai/api/paas/v4/chat/completions"
    },
    "openai": {
      "api_key": "your-openai-api-key-here",
      "model": "gpt-4o-mini",
      "endpoint": "https://api.openai.com/v1/chat/completions"
    },
    "groq": {
      "api_key": "your-groq-api-key-here",
      "model": "llama-3.1-8b-instant",
      "endpoint": "https://api.groq.com/openai/v1/chat/completions"
    }
  }
}
```

### 4.4 Config Validation
**Verification:** Detects and reports config issues clearly

**Checks:**
- File exists and is readable
- Valid JSON syntax
- Required fields present (default_provider, providers)
- Provider exists in config
- API key not empty for selected provider
- Model specified for selected provider

**Error messages:**
- "Config file not found at {path}. Run with --config to create one."
- "Invalid JSON in config file: {error}"
- "Provider '{name}' not found in config"
- "API key not set for provider '{name}'. Edit your config file."

---

## Stage 5: Git Operations

### 5.1 Git Command Functions
**Verification:** Each git command works correctly

Create `src/git.zig` with shell command wrappers:

```zig
const Git = struct {
    fn isRepo() bool;
    fn hasStagedChanges() bool;
    fn getStagedDiff() ![]const u8;
    fn getRecentCommits(n: usize) ![][]const u8;
    fn addAll() !void;
    fn commit(message: []const u8) !void;
    fn push() !void;
};
```

### 5.2 Implementation Details
**Verification:** All operations handle errors properly

**Use `std.process.Child` to spawn git commands:**

```zig
fn runGitCommand(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    // Spawn git process
    // Capture stdout/stderr
    // Return stdout on success
    // Include stderr in error on failure
}
```

**Specific commands:**
- `isRepo()`: `git rev-parse --git-dir` (check exit code)
- `hasStagedChanges()`: `git diff --cached --quiet` (non-zero exit = has changes)
- `getStagedDiff()`: `git diff --cached` (capture stdout)
- `getRecentCommits(n)`: `git log -n {n} --format=%s` (parse each line)
- `addAll()`: `git add -A`
- `commit(msg)`: `git commit -m "{msg}"`
- `push()`: `git push`

### 5.3 Error Handling
**Verification:** Clear error messages for git failures

**Error cases:**
- Not a git repository: "Not a git repository. Run 'git init' first."
- No staged changes: "No staged changes. Run 'git add' or enable auto_add in config."
- Git command fails: Include stderr in error message

---

## Stage 6: HTTP Client & JSON

### 6.1 HTTP Client Wrapper
**Verification:** Can make HTTPS POST requests to APIs

Create `src/http_client.zig`:

```zig
const HttpClient = struct {
    client: std.http.Client,
    
    fn init(allocator: std.mem.Allocator) HttpClient;
    fn deinit(self: *HttpClient);
    fn post(
        self: *HttpClient,
        url: []const u8,
        headers: []const std.http.Header,
        body: []const u8,
    ) ![]const u8;  // Returns response body
};
```

**Configuration:**
- Timeout: 15 seconds
- HTTPS only
- User-Agent: "autocommit/1.0"

### 6.2 JSON Request Building
**Verification:** Correct JSON structure for LLM APIs

**Request structure:**
```json
{
  "model": "glm-4.7-Flash",
  "messages": [
    {
      "role": "system",
      "content": "You are a commit message generator..."
    },
    {
      "role": "user",
      "content": "Git diff:\n{diff}\n\nRecent commits:\n- {commit1}\n- {commit2}"
    }
  ],
  "temperature": 0.7,
  "max_tokens": 1500
}
```

### 6.3 JSON Response Parsing
**Verification:** Can extract commit message from API response

**Parse path:** `choices[0].message.content`

**Response structure:**
```json
{
  "choices": [
    {
      "message": {
        "content": "feat(auth): add password validation"
      }
    }
  ]
}
```

### 6.4 Error Handling
**Verification:** Handle API errors gracefully

**HTTP errors:**
- 401: "Invalid API key. Check your config file."
- 429: "Rate limit exceeded. Please try again later."
- 500+: "API server error. Please try again later."

**Other errors:**
- Timeout: "Request timed out. Check your internet connection."
- Invalid JSON: "Invalid response from API."
- Empty content: "API returned empty message."

---

## Stage 7: LLM Provider Interface

### 7.1 Provider Interface Definition
**Verification:** Can instantiate and use different providers

Create `src/llm.zig`:

```zig
const Provider = struct {
    name: []const u8,
    api_key: []const u8,
    model: []const u8,
    endpoint: []const u8,
    system_prompt: []const u8,
    http_client: *HttpClient,
    
    fn generateCommitMessage(
        self: Provider,
        diff: []const u8,
        recent_commits: []const []const u8,
    ) ![]const u8;
};

fn createProvider(
    name: []const u8,
    config: Config,
    http_client: *HttpClient,
) !Provider;
```

### 7.2 Provider Implementations
**Verification:** All three providers work correctly

Create `src/providers/` directory with:

**zai.zig:**
- Endpoint: `https://api.z.ai/api/paas/v4/chat/completions`
- Default model: `glm-4.7-Flash`
- Special error handling for rate limits

**openai.zig:**
- Endpoint: `https://api.openai.com/v1/chat/completions`
- Default model: `gpt-4o-mini`

**groq.zig:**
- Endpoint: `https://api.groq.com/openai/v1/chat/completions`
- Default model: `llama-3.1-8b-instant`

### 7.3 Provider Selection
**Verification:** Uses correct provider based on config or CLI override

**Priority:**
1. CLI `--provider` flag (highest)
2. Config `default_provider`
3. Error if neither specified

### 7.4 System Prompts
**Verification:** Default prompt generates good commit messages

Create `src/prompt.zig` with default system prompt:

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


---

## Stage 8: Main Workflow

### 8.1 Generate Workflow
**Verification:** End-to-end commit message generation works

Update `src/main.zig` to implement the main workflow:

**Steps:**
1. Parse CLI arguments
2. If `--version`, print version and exit
3. If `--help`, print help and exit
4. If `--config`, open editor and exit
5. Check if in git repository
6. Load configuration
7. If `--provider` or `--model` flags set, override config
8. Handle auto_add if enabled and no staged changes
9. Check for staged changes
10. Get staged diff
11. Get recent commits (last 5)
12. Initialize HTTP client
13. Create provider
14. Generate commit message via API
15. Display generated message
16. Interactive prompt for action
17. Execute chosen action (commit/regenerate/edit/quit)

### 8.2 Interactive Prompt
**Verification:** User can choose all options

**Display:**
```
Suggested commit message:
feat(auth): add password validation

Options:
  [enter] Commit
  [r]     Regenerate
  [e]     Edit message
  [q]     Quit

Choice:
```

**Actions:**
- `enter` or empty: Run `git commit` with message
- `r`: Regenerate message (new API call)
- `e`: Edit mode (read lines from stdin until empty line)
- `q` or `ctrl+c`: Quit without committing

### 8.3 Edit Mode
**Verification:** Can edit generated message

**Implementation:**
1. Print current message
2. Print "Enter new message (press Enter twice to finish):"
3. Read lines from stdin
4. Stop reading when empty line encountered
5. Use edited message for commit

### 8.4 Commit and Push
**Verification:** Can commit and optionally push

**Commit:**
- Run `git commit -m "message"`
- Print "Committed successfully"

**Auto-push (if enabled):**
- If config.auto_push is true
- Run `git push`
- Print "Pushed successfully"
- Handle push errors (commit succeeded but push failed)

---

## Stage 9: Polish & Edge Cases

### 9.1 Debug Mode
**Verification:** --debug shows useful diagnostic info

When `--debug` flag is set, print:
- Config file path being used
- Selected provider and model
- API endpoint being called
- Request timing (start/end/duration)
- Response status code
- Response size

**Example:**
```
[DEBUG] Config path: /Users/user/.config/autocommit/config.json
[DEBUG] Provider: zai, Model: glm-4.7-Flash
[DEBUG] API endpoint: https://api.z.ai/api/paas/v4/chat/completions
[DEBUG] Request started
[DEBUG] Request completed in 1.234s
[DEBUG] Response status: 200
[DEBUG] Response size: 523 bytes
```

### 9.2 Large Diff Handling
**Verification:** Large diffs don't break API

**Problem:** Very large diffs can exceed API token limits

**Solution:**
- If diff > 100KB, truncate and add notice
- Include first 100KB + "\n... (truncated)"

### 9.3 Empty or Invalid Responses
**Verification:** Handle API edge cases

**Cases:**
- Empty choices array: "No response from LLM"
- Empty content: "LLM returned empty message"
- Whitespace-only content: Trim and check if empty

### 9.4 Rate Limiting & Retries
**Verification:** Handle 429 errors gracefully

**Current:** Return error immediately
**Future enhancement:** Exponential backoff retry

### 9.5 Error Message Quality
**Verification:** All errors are actionable

**Before:** "API error"
**After:** "z.ai API rate limit exceeded (429). Please wait a moment and try again, or check your account at https://z.ai"

### 9.6 Memory Management
**Verification:** No memory leaks (use GPA in debug)

**Pattern:**
```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();
```

---

## Stage 10: Migrate Config to TOML (Optional)

### 10.1 Add ztoml Dependency
**Verification:** Can build with external dependency

Update `build.zig.zon`:
```json
{
    "name": "autocommit",
    "version": "0.2.0",
    "dependencies": {
        "ztoml": {
            "url": "https://github.com/edyu/ztoml/archive/refs/tags/v0.2.0.tar.gz",
            "hash": "<hash_here>"
        }
    }
}
```

### 10.2 Update build.zig
**Verification:** Dependency properly linked

Add to `build.zig`:
```zig
const ztoml = b.dependency("ztoml", .{});
exe.root_module.addImport("ztoml", ztoml.module("ztoml"));
```

### 10.3 Convert Config Format
**Verification:** Config reads/writes TOML instead of JSON

Update `src/config.zig`:
- Import `ztoml`
- Replace `std.json` with TOML parsing
- Keep same Config struct

### 10.4 Example TOML Config
**Verification:** TOML config works

```toml
# AutoCommit Configuration

default_provider = "zai"
auto_add = false
auto_push = false

system_prompt = """
You are a commit message generator. 
Analyze the git diff and create a conventional commit message.
"""

[providers.zai]
api_key = "your-zai-api-key-here"
model = "glm-4.7-Flash"
endpoint = "https://api.z.ai/api/paas/v4/chat/completions"

[providers.openai]
api_key = "your-openai-api-key-here"
model = "gpt-4o-mini"
endpoint = "https://api.openai.com/v1/chat/completions"

[providers.groq]
api_key = "your-groq-api-key-here"
model = "llama-3.1-8b-instant"
endpoint = "https://api.groq.com/openai/v1/chat/completions"
```

### 10.5 Config Migration (Optional)
**Verification:** Can auto-convert JSON to TOML

On load:
1. Try TOML config first (new location: config.toml)
2. If not found, try JSON config (old location: config.json)
3. If JSON found, offer to convert to TOML
4. Save as TOML, remove old JSON

---

## Complete Verification Checklist

| Stage | Component | Verification Test | Status |
|-------|-----------|------------------|--------|
| 0 | Project setup | `zig build` succeeds | [ ] |
| 1 | Hello world | Binary runs | [ ] |
| 1 | Cross-compile | Two targets build | [ ] |
| 2 | PR workflow | PR triggers build | [ ] |
| 2 | Release workflow | Tag creates release | [ ] |
| 2 | Artifacts | 2 binaries + checksums | [ ] |
| 2 | Changelog | Generated from commits | [ ] |
| 3 | --help | Shows comprehensive help | [ ] |
| 3 | --version | Shows version | [ ] |
| 3 | --config | Opens editor | [ ] |
| 4 | Config save/load | JSON persists correctly | [ ] |
| 4 | Config validation | Detects invalid config | [ ] |
| 5 | Git operations | All git commands work | [ ] |
| 6 | HTTP client | HTTPS requests succeed | [ ] |
| 6 | JSON parsing | Correct API response parsing | [ ] |
| 7 | zai provider | Generates commits | [ ] |
| 7 | openai provider | Generates commits | [ ] |
| 7 | groq provider | Generates commits | [ ] |
| 8 | Full workflow | End-to-end commit | [ ] |
| 8 | Interactive prompt | All options work | [ ] |
| 9 | Debug mode | Shows diagnostic info | [ ] |
| 9 | Error handling | Clear error messages | [ ] |
| 10 | TOML config | Reads/writes TOML | [ ] |

---

## Binary Size Targets

| Target | Expected Size | Compressed |
|--------|--------------|------------|
| aarch64-macos | 200-300KB | 100-150KB |
| x86_64-linux-musl | 250-350KB | 120-180KB |

---

## Performance Targets

| Metric | Target |
|--------|--------|
| Cold start | < 50ms |
| Config load | < 10ms |
| Git operations | < 100ms |
| API response | < 5s (depends on provider) |
| Total workflow | < 10s |

---

## Migration Complete!

Once all stages are verified:
1. Go implementation can be archived/removed
2. Update README with new installation instructions
3. Update CHANGELOG with migration notes
4. Tag v1.0.0-zig or similar to mark completion

