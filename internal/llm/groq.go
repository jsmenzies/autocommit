package llm

import (
	"autocommit/internal/prompt"
	"context"
	"fmt"
	"net/http"
)

const GroqAPIEndpoint = "https://api.groq.com/openai/v1/chat/completions"

type GroqProvider struct {
	*BaseProvider
}

func NewGroqProvider(apiKey, model, systemPrompt string) *GroqProvider {
	return &GroqProvider{
		BaseProvider: NewBaseProvider(apiKey, model, GroqAPIEndpoint, systemPrompt, DefaultGroqModel),
	}
}

func (g *GroqProvider) Name() string {
	return ProviderGroq
}

func (g *GroqProvider) GenerateCommitMessage(ctx context.Context, diff string, recentCommits []string) (string, error) {
	if g.APIKey == "" {
		return "", fmt.Errorf("groq API key is not configured")
	}

	systemPrompt := g.SystemPrompt
	if systemPrompt == "" {
		systemPrompt = prompt.GetDefaultSystemPrompt()
	}

	userContent := BuildUserContent(diff, recentCommits)
	req := BuildChatRequest(g.Model, systemPrompt, userContent, DefaultTemperature, DefaultMaxTokens)

	chatResp, err := g.SendChatRequest(ctx, req)
	if err != nil {
		return "", err
	}

	return ExtractMessage(chatResp)
}

func (g *GroqProvider) SetClient(client *http.Client) {
	g.client = client
}
