package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ZaiAPIEndpoint is the z.ai API endpoint for chat completions
const ZaiAPIEndpoint = "https://api.z.ai/api/paas/v4/chat/completions"

type Provider interface {
	GenerateCommitMessage(ctx context.Context, diff string, recentCommits []string) (string, error)
	Name() string
}

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ChatRequest struct {
	Model       string    `json:"model"`
	Messages    []Message `json:"messages"`
	Temperature float64   `json:"temperature"`
	MaxTokens   int       `json:"max_tokens"`
}

type Choice struct {
	Message Message `json:"message"`
}

type ChatResponse struct {
	Choices []Choice `json:"choices"`
}

type ZaiProvider struct {
	APIKey       string
	Model        string
	BaseURL      string
	SystemPrompt string
	client       *http.Client
}

func NewZaiProvider(apiKey, model, systemPrompt string) *ZaiProvider {
	if model == "" {
		model = "glm-4.7"
	}

	return &ZaiProvider{
		APIKey:       apiKey,
		Model:        model,
		BaseURL:      ZaiAPIEndpoint,
		SystemPrompt: systemPrompt,
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

func (z *ZaiProvider) Name() string {
	return "zai"
}

func (z *ZaiProvider) GenerateCommitMessage(ctx context.Context, diff string, recentCommits []string) (string, error) {
	if z.APIKey == "" {
		return "", fmt.Errorf("zai API key is not configured")
	}

	// Use custom system prompt if provided, otherwise use default
	systemPrompt := z.SystemPrompt
	if systemPrompt == "" {
		systemPrompt = `You are a commit message generator. Analyze the git diff and create a conventional commit message.
Follow these rules:
- Use format: <type>(<scope>): <subject>
- Types: feat, fix, docs, style, refactor, test, chore
- Keep subject under 72 characters
- Use present tense, imperative mood
- Be specific but concise
- Do not include any explanation, only output the commit message
- Do not use markdown code blocks

Examples:
- feat(auth): add password validation to login form
- fix(api): handle nil pointer in user service
- docs(readme): update installation instructions
- refactor(db): optimize query performance with index`
	}

	recentContext := ""
	if len(recentCommits) > 0 {
		recentContext = "\n\nRecent commits for context:\n"
		for _, msg := range recentCommits {
			recentContext += "- " + msg + "\n"
		}
	}

	userContent := fmt.Sprintf("Git diff:\n%s%s", diff, recentContext)

	req := ChatRequest{
		Model: z.Model,
		Messages: []Message{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userContent},
		},
		Temperature: 0.7,
		MaxTokens:   500,
	}

	reqBody, err := json.Marshal(req)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", z.BaseURL, bytes.NewBuffer(reqBody))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+z.APIKey)

	resp, err := z.client.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("API request failed with status %d: %s", resp.StatusCode, string(body))
	}

	var chatResp ChatResponse
	if err := json.Unmarshal(body, &chatResp); err != nil {
		return "", fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(chatResp.Choices) == 0 {
		return "", fmt.Errorf("no response from LLM")
	}

	return strings.TrimSpace(chatResp.Choices[0].Message.Content), nil
}
