# AutoCommit Code Review

**Review Date:** 2026-01-30
**Project:** AutoCommit - AI-powered conventional commit message generator
**Language:** Go 1.25

---

## Executive Summary

AutoCommit is a well-structured CLI application that generates conventional commit messages using LLM providers (z.ai, OpenAI, Groq). The codebase demonstrates good separation of concerns with a clean architecture using the Cobra CLI framework and Bubble Tea for the TUI.

**Overall Rating:** 7.5/10 - Good codebase with solid architecture, but has areas for improvement in error handling, testing, and security.

---

## Architecture Overview

```
cmd/autocommit/main.go         # Entry point
internal/
├── cmd/root.go               # Cobra commands & business logic
├── config/config.go          # Configuration management (Viper)
├── git/git.go                # Git operations
├── llm/
│   ├── provider.go           # Base provider interface & HTTP client
│   ├── factory.go            # Provider factory pattern
│   ├── registry.go           # Provider metadata registry
│   ├── zai.go                # z.ai provider
│   ├── openai.go             # OpenAI provider
│   ├── groq.go               # Groq provider
│   └── constants.go          # Provider constants
├── prompt/
│   ├── prompt.go             # Interactive prompt editing
│   └── default.go            # Default system prompt
├── tui/
│   ├── app.go                # Bubble Tea app initialization
│   ├── model.go              # TUI state management
│   ├── mainmenu.go           # Main menu screen
│   ├── provider.go           # Provider selection/config screens
│   ├── gitconfig.go          # Git settings screen
│   └── prompt.go             # Prompt editor screen
└── debug/debug.go            # Debug logging utilities
```

---

## Strengths

### 1. Clean Architecture
- **Modular Design:** Clear separation between CLI commands, TUI, configuration, git operations, and LLM providers
- **Provider Pattern:** Well-implemented factory pattern for LLM providers with a clean interface
- **Dependency Injection:** HTTP clients can be injected for testing (e.g., `SetClient` methods)

### 2. Good UX Design
- **Interactive TUI:** Bubble Tea provides a polished terminal interface
- **Multiple Interfaces:** Supports both TUI and CLI workflows (`-g` flag for direct generation)
- **Configuration Management:** XDG-compliant config file locations
- **Helpful Error Messages:** Includes context and suggestions in error messages

### 3. Code Quality
- **Consistent Style:** Follows Go conventions and formatting
- **Error Wrapping:** Uses `fmt.Errorf` with `%w` verb for error chaining
- **Context Usage:** Proper context propagation for API calls
- **Constants:** Well-organized constants for providers, models, and API endpoints

### 4. CI/CD & Tooling
- **GitHub Actions:** PR validation and release workflows
- **GoReleaser:** Comprehensive cross-platform release configuration
- **mise.toml:** Tool version management
- **release-please:** Automated changelog and versioning

---

## Issues & Recommendations

### Critical Issues

#### 1. **API Keys Stored in Plaintext** (Security)
**Location:** `internal/config/config.go`

**Issue:** API keys are stored in plaintext YAML files in the user's config directory.

**Recommendation:** 
- Implement OS keyring integration (e.g., `github.com/zalando/go-keyring`)
- Support environment variable overrides for API keys
- Add warning to users about plaintext storage

```go
// Suggested approach
func (c *Config) GetAPIKey(provider string) (string, error) {
    // Check env var first
    envKey := os.Getenv(fmt.Sprintf("AUTOCOMMIT_%s_API_KEY", strings.ToUpper(provider)))
    if envKey != "" {
        return envKey, nil
    }
    // Fall back to config file (with warning)
    return c.Providers[provider].APIKey, nil
}
```

#### 2. **No Test Coverage**
**Impact:** HIGH

**Issue:** No unit tests or integration tests found in the codebase.

**Recommendation:**
- Add unit tests for `internal/git/git.go` using a mock git repository
- Add tests for LLM providers with mocked HTTP clients
- Add integration tests for the configuration system
- Set minimum coverage threshold in CI (e.g., 70%)

```go
// Example test pattern for providers
func TestZaiProvider_GenerateCommitMessage(t *testing.T) {
    mockClient := &http.Client{
        Transport: &mockTransport{},
    }
    provider := NewZaiProvider("test-key", "glm-4.7", "")
    provider.SetClient(mockClient)
    // ... test implementation
}
```

### High Priority Issues

#### 3. **No Input Validation for API Keys**
**Location:** `internal/llm/*.go`

**Issue:** Empty API keys are only checked at API call time, not at configuration time.

**Recommendation:**
- Validate API key format during configuration
- Check for empty keys before attempting API calls with clearer error messages

```go
func (z *ZaiProvider) GenerateCommitMessage(ctx context.Context, diff string, recentCommits []string) (string, error) {
    if strings.TrimSpace(z.APIKey) == "" {
        return "", fmt.Errorf("zai API key not configured. Run 'autocommit' to configure or set ZAI_API_KEY environment variable")
    }
    // ...
}
```

#### 4. **Unbounded Diff Size**
**Location:** `internal/git/git.go:31-43`

**Issue:** No limit on the size of git diffs sent to LLM APIs, which could:
- Exceed API token limits
- Cause performance issues
- Increase API costs unexpectedly

**Recommendation:**
```go
const MaxDiffSize = 100000 // ~100KB

func GetStagedDiff() (string, error) {
    diff, err := getRawDiff()
    if err != nil {
        return "", err
    }
    if len(diff) > MaxDiffSize {
        return diff[:MaxDiffSize] + "\n... (truncated)", nil
    }
    return diff, nil
}
```

#### 5. **Missing Context Cancellation**
**Location:** `internal/llm/provider.go:89-137`

**Issue:** HTTP client timeout is hardcoded to 15 seconds, but no context cancellation handling for user interrupts.

**Recommendation:**
```go
func (bp *BaseProvider) SendChatRequest(ctx context.Context, req ChatRequest) (*ChatResponse, error) {
    httpReq, err := http.NewRequestWithContext(ctx, "POST", bp.BaseURL, bytes.NewBuffer(reqBody))
    // ... rest of implementation
}
```

### Medium Priority Issues

#### 6. **Duplicate Provider Selection Logic**
**Location:** `internal/tui/provider.go:40-63`

**Issue:** Code duplication when resetting provider configuration form.

**Recommendation:** Extract into a helper method:
```go
func (m *model) resetProviderForm() {
    m.apiKeyAlreadySet = false
    m.apiKeyOriginalValue = ""
    m.apiKeyInput.SetValue("")
    m.apiKeyInput.Placeholder = "Enter your API key..."
    m.modelCursor = 0
}
```

#### 7. **Magic Numbers in UI**
**Location:** `internal/tui/app.go:25-28`

**Issue:** Hardcoded dimensions without explanation.

**Recommendation:**
```go
const (
    TextAreaDefaultHeight = 15
    TextAreaDefaultWidth  = 80
    TextAreaMinHeight     = 10
)
```

#### 8. **Inconsistent Error Handling in TUI**
**Location:** `internal/tui/*.go`

**Issue:** Some screens show error messages inline, others don't handle errors visibly.

**Recommendation:** Standardize error handling across all TUI screens with a consistent error display pattern.

#### 9. **No Retry Logic for API Calls**
**Location:** `internal/llm/provider.go`

**Issue:** API failures immediately return error without retry for transient failures.

**Recommendation:** Add exponential backoff retry for 5xx errors and rate limits (429).

### Low Priority Issues

#### 10. **Debug Output Formatting**
**Location:** `internal/debug/debug.go`

**Issue:** Debug output includes hardcoded `[DEBUG]` prefix in every call.

**Recommendation:**
```go
func Printf(format string, args ...interface{}) {
    if Enabled {
        fmt.Printf("[DEBUG] "+format, args...)
    }
}
```

#### 11. **Unused Import in main.go**
**Location:** `cmd/autocommit/main.go:11-14`

**Issue:** `commit` and `buildTime` variables are set but never used.

**Recommendation:** Either use them in version output or remove:
```go
func main() {
    if err := cmd.Execute(version, commit, buildTime); err != nil {
        // ...
    }
}
// And in root.go:
versionCmd = &cobra.Command{
    Run: func(cmd *cobra.Command, args []string) {
        fmt.Printf("autocommit version %s (commit: %s, built: %s)\n", version, commit, buildTime)
    },
}
```

#### 12. **Missing Documentation on Provider Models**
**Location:** `internal/llm/registry.go`

**Issue:** No documentation about model capabilities or pricing tiers.

**Recommendation:** Add model metadata:
```go
type ModelInfo struct {
    Name        string
    Description string
    IsFreeTier  bool
}
```

---

## Code Style Observations

### Positive
- ✅ Consistent use of `internal/` package structure
- ✅ Clear naming conventions (e.g., `GenerateCommitMessage` not `GenMsg`)
- ✅ Proper use of interfaces for testability
- ✅ Good comment coverage for exported functions
- ✅ XDG Base Directory specification compliance

### Areas for Improvement
- ⚠️ Some long functions could be broken down (e.g., `updateProviderList`)
- ⚠️ Mixed use of pointer and value receivers in TUI model methods
- ⚠️ Some string concatenation could use `strings.Builder` for performance

---

## Security Assessment

| Aspect | Status | Notes |
|--------|--------|-------|
| API Key Storage | ⚠️ WARNING | Plaintext in config file |
| Input Sanitization | ✅ OK | Git diff is passed directly to API |
| HTTPS Only | ✅ OK | All providers use HTTPS |
| User Agent | ✅ OK | Custom User-Agent set |
| Debug Logging | ⚠️ WARNING | Could leak API keys in debug mode |

**Recommendation:** Add warning when debug mode is enabled that API keys may be logged.

---

## Performance Considerations

1. **Memory Usage:** Large diffs are held entirely in memory before sending to API
2. **HTTP Client:** Single client reused (good), but no connection pooling configuration
3. **String Building:** `BuildUserContent` uses string concatenation in a loop

**Optimization Suggestion:**
```go
func BuildUserContent(diff string, recentCommits []string) string {
    var sb strings.Builder
    sb.WriteString("Git diff:\n")
    sb.WriteString(diff)
    if len(recentCommits) > 0 {
        sb.WriteString("\n\nRecent commits for context:\n")
        for _, msg := range recentCommits {
            sb.WriteString("- ")
            sb.WriteString(msg)
            sb.WriteString("\n")
        }
    }
    return sb.String()
}
```

---

## Testing Strategy Recommendations

### Unit Tests Priority
1. `internal/git/git.go` - Mock git commands
2. `internal/config/config.go` - Temporary config files
3. `internal/llm/*.go` - Mock HTTP responses
4. `internal/prompt/prompt.go` - Mock stdin

### Integration Tests
1. End-to-end workflow with mocked LLM provider
2. Configuration file roundtrip
3. TUI screen navigation

### Test Example
```go
func TestGenerateWorkflow_Success(t *testing.T) {
    // Setup temp git repo
    // Stage some changes
    // Mock provider
    // Run generateWorkflow
    // Assert message format
}
```

---

## Documentation Status

| Component | README | Code Comments | HANDOFF.md |
|-----------|--------|---------------|------------|
| Installation | ✅ | N/A | ✅ |
| Configuration | ✅ | ✅ | ✅ |
| API Usage | ✅ | ✅ | ⚠️ |
| Provider Setup | ✅ | ⚠️ | ⚠️ |
| Development | ✅ | N/A | ✅ |

---

## Suggested Next Steps

### Immediate (High Priority)
1. Add unit tests with 70%+ coverage
2. Implement environment variable support for API keys
3. Add diff size limiting
4. Add retry logic with exponential backoff

### Short-term (Medium Priority)
1. Implement OS keyring integration
2. Add context cancellation support
3. Refactor duplicate code in TUI
4. Add input validation for API keys

### Long-term (Low Priority)
1. Add caching for API responses
2. Implement batch processing for multiple commits
3. Add git hook integration
4. Support multi-line commit messages with body/footer

---

## Conclusion

AutoCommit is a solid, well-architected CLI tool with good UX and clean code structure. The main areas needing attention are **security (API key storage)**, **testing coverage**, and **error handling robustness**. The codebase is maintainable and follows Go best practices, making it a good foundation for future enhancements.

**Recommended Actions:**
1. Address critical security issue (API key storage)
2. Add comprehensive test suite
3. Implement input validation and error handling improvements
4. Consider the performance optimizations suggested

---

*Review generated by automated code review process*
