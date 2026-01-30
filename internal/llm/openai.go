package llm

import (
	"autocommit/internal/prompt"
	"context"
	"fmt"
	"net/http"
)

const OpenAIAPIEndpoint = "https://api.openai.com/v1/chat/completions"

type OpenAIProvider struct {
	*BaseProvider
}

func NewOpenAIProvider(apiKey, model, systemPrompt string) *OpenAIProvider {
	return &OpenAIProvider{
		BaseProvider: NewBaseProvider(apiKey, model, OpenAIAPIEndpoint, systemPrompt, DefaultOpenAIModel),
	}
}

func (o *OpenAIProvider) Name() string {
	return ProviderOpenAI
}

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

func (o *OpenAIProvider) SetClient(client *http.Client) {
	o.client = client
}
