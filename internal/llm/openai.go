package llm

import (
	"autocommit/internal/prompt"
	"context"
	"fmt"
	"net/http"
)

// OpenAIAPIEndpoint is the OpenAI API endpoint for chat completions
const OpenAIAPIEndpoint = "https://api.openai.com/v1/chat/completions"

// OpenAIProvider implements the Provider interface for OpenAI
type OpenAIProvider struct {
	*BaseProvider
}

// NewOpenAIProvider creates a new OpenAI provider instance
func NewOpenAIProvider(apiKey, model, systemPrompt string) *OpenAIProvider {
	return &OpenAIProvider{
		BaseProvider: NewBaseProvider(apiKey, model, OpenAIAPIEndpoint, systemPrompt, DefaultOpenAIModel),
	}
}

// Name returns the provider name
func (o *OpenAIProvider) Name() string {
	return ProviderOpenAI
}

// GenerateCommitMessage generates a commit message using the OpenAI API
func (o *OpenAIProvider) GenerateCommitMessage(ctx context.Context, diff string, recentCommits []string) (string, error) {
	if o.APIKey == "" {
		return "", fmt.Errorf("openai API key is not configured")
	}

	// Use custom system prompt if provided, otherwise use default
	systemPrompt := o.SystemPrompt
	if systemPrompt == "" {
		systemPrompt = prompt.GetDefaultSystemPrompt()
	}

	userContent := BuildUserContent(diff, recentCommits)
	req := BuildChatRequest(o.Model, systemPrompt, userContent, DefaultTemperature, DefaultMaxTokens)

	chatResp, err := o.SendChatRequest(ctx, req)
	if err != nil {
		return "", err
	}

	return ExtractMessage(chatResp)
}

// SetClient allows setting a custom HTTP client (useful for testing)
func (o *OpenAIProvider) SetClient(client *http.Client) {
	o.client = client
}
