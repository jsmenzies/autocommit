package llm

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"autocommit/internal/debug"
)

// ZaiAPIEndpoint is the z.ai API endpoint for chat completions
const ZaiAPIEndpoint = "https://api.z.ai/api/paas/v4/chat/completions"

// ZaiProvider implements the Provider interface for z.ai
type ZaiProvider struct {
	*BaseProvider
}

// NewZaiProvider creates a new z.ai provider instance
func NewZaiProvider(apiKey, model, systemPrompt string) *ZaiProvider {
	if model == "" {
		model = "glm-4.7"
	}

	return &ZaiProvider{
		BaseProvider: NewBaseProvider(apiKey, model, ZaiAPIEndpoint, systemPrompt, "glm-4.7"),
	}
}

// Name returns the provider name
func (z *ZaiProvider) Name() string {
	return "zai"
}

// GenerateCommitMessage generates a commit message using the z.ai API
func (z *ZaiProvider) GenerateCommitMessage(ctx context.Context, diff string, recentCommits []string) (string, error) {
	debug.Println("[DEBUG] zai.GenerateCommitMessage called")

	if z.APIKey == "" {
		return "", fmt.Errorf("zai API key is not configured")
	}

	debug.Printf("[DEBUG] API Key length: %d\n", len(z.APIKey))
	debug.Printf("[DEBUG] Model: %s\n", z.Model)
	debug.Printf("[DEBUG] Diff length: %d chars\n", len(diff))
	debug.Printf("[DEBUG] Recent commits count: %d\n", len(recentCommits))

	// Use custom system prompt if provided, otherwise use default
	systemPrompt := z.SystemPrompt
	if systemPrompt == "" {
		systemPrompt = GetDefaultSystemPrompt()
	}
	debug.Printf("[DEBUG] System prompt length: %d chars\n", len(systemPrompt))

	userContent := BuildUserContent(diff, recentCommits)
	req := BuildChatRequest(z.Model, systemPrompt, userContent, 0.7, 1500)

	chatResp, err := z.SendChatRequest(ctx, req)
	if err != nil {
		// Check for specific z.ai error conditions
		if strings.Contains(err.Error(), "429") {
			return "", fmt.Errorf("z.ai API rate limit exceeded or insufficient balance. Please check your account at https://z.ai")
		}
		return "", err
	}

	debug.Printf("[DEBUG] Response received with %d choices\n", len(chatResp.Choices))

	return ExtractMessage(chatResp)
}

// SetClient allows setting a custom HTTP client (useful for testing)
func (z *ZaiProvider) SetClient(client *http.Client) {
	z.client = client
}
