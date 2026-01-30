package llm

import (
	"context"
	"fmt"
	"net/http"
)

// GroqAPIEndpoint is the Groq API endpoint for chat completions
const GroqAPIEndpoint = "https://api.groq.com/openai/v1/chat/completions"

// GroqProvider implements the Provider interface for Groq
type GroqProvider struct {
	*BaseProvider
}

// NewGroqProvider creates a new Groq provider instance
func NewGroqProvider(apiKey, model, systemPrompt string) *GroqProvider {
	return &GroqProvider{
		BaseProvider: NewBaseProvider(apiKey, model, GroqAPIEndpoint, systemPrompt, "llama-3.1-8b-instant"),
	}
}

// Name returns the provider name
func (g *GroqProvider) Name() string {
	return "groq"
}

// GenerateCommitMessage generates a commit message using the Groq API
func (g *GroqProvider) GenerateCommitMessage(ctx context.Context, diff string, recentCommits []string) (string, error) {
	if g.APIKey == "" {
		return "", fmt.Errorf("groq API key is not configured")
	}

	// Use custom system prompt if provided, otherwise use default
	systemPrompt := g.SystemPrompt
	if systemPrompt == "" {
		systemPrompt = GetDefaultSystemPrompt()
	}

	userContent := BuildUserContent(diff, recentCommits)
	req := BuildChatRequest(g.Model, systemPrompt, userContent, 0.7, 500)

	chatResp, err := g.SendChatRequest(ctx, req)
	if err != nil {
		return "", err
	}

	return ExtractMessage(chatResp)
}

// SetClient allows setting a custom HTTP client (useful for testing)
func (g *GroqProvider) SetClient(client *http.Client) {
	g.client = client
}
