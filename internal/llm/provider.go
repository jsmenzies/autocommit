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

	"autocommit/internal/debug"
)

// Provider defines the interface for LLM providers
type Provider interface {
	GenerateCommitMessage(ctx context.Context, diff string, recentCommits []string) (string, error)
	Name() string
}

// Message represents a chat message
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// ChatRequest represents a chat completion request
type ChatRequest struct {
	Model       string    `json:"model"`
	Messages    []Message `json:"messages"`
	Temperature float64   `json:"temperature"`
	MaxTokens   int       `json:"max_tokens"`
}

// Choice represents a completion choice
type Choice struct {
	Message Message `json:"message"`
}

// ChatResponse represents a chat completion response
type ChatResponse struct {
	Choices []Choice `json:"choices"`
}

// BaseProvider contains shared functionality for HTTP-based LLM providers
type BaseProvider struct {
	APIKey       string
	Model        string
	BaseURL      string
	SystemPrompt string
	client       *http.Client
}

// NewBaseProvider creates a new base provider with common configuration
func NewBaseProvider(apiKey, model, baseURL, systemPrompt string, defaultModel string) *BaseProvider {
	if model == "" {
		model = defaultModel
	}

	return &BaseProvider{
		APIKey:       apiKey,
		Model:        model,
		BaseURL:      baseURL,
		SystemPrompt: systemPrompt,
		client: &http.Client{
			Timeout: 60 * time.Second,
		},
	}
}

// BuildChatRequest creates a chat request with the given parameters
func BuildChatRequest(model, systemPrompt, userContent string, temperature float64, maxTokens int) ChatRequest {
	return ChatRequest{
		Model: model,
		Messages: []Message{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userContent},
		},
		Temperature: temperature,
		MaxTokens:   maxTokens,
	}
}

// BuildUserContent creates the user content from diff and recent commits
func BuildUserContent(diff string, recentCommits []string) string {
	recentContext := ""
	if len(recentCommits) > 0 {
		recentContext = "\n\nRecent commits for context:\n"
		for _, msg := range recentCommits {
			recentContext += "- " + msg + "\n"
		}
	}

	return fmt.Sprintf("Git diff:\n%s%s", diff, recentContext)
}

// SendChatRequest sends a chat request and returns the response
func (bp *BaseProvider) SendChatRequest(ctx context.Context, req ChatRequest) (*ChatResponse, error) {
	reqBody, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	debug.Printf("[DEBUG] Request URL: %s\n", bp.BaseURL)
	debug.Printf("[DEBUG] Request Model: %s\n", req.Model)
	debug.Printf("[DEBUG] Request Body Size: %d bytes\n", len(reqBody))
	debug.Println("[DEBUG] Sending request...")

	httpReq, err := http.NewRequestWithContext(ctx, "POST", bp.BaseURL, bytes.NewBuffer(reqBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+bp.APIKey)
	httpReq.Header.Set("User-Agent", "autocommit/1.0")

	start := time.Now()
	resp, err := bp.client.Do(httpReq)
	elapsed := time.Since(start)
	debug.Printf("[DEBUG] Request took %v\n", elapsed)

	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API request failed with status %d: %s", resp.StatusCode, string(body))
	}

	debug.Printf("[DEBUG] Response Status: %d\n", resp.StatusCode)
	debug.Printf("[DEBUG] Response Body:\n%s\n", string(body))

	var chatResp ChatResponse
	if err := json.Unmarshal(body, &chatResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return &chatResp, nil
}

// ExtractMessage extracts the message content from a chat response
func ExtractMessage(chatResp *ChatResponse) (string, error) {
	if len(chatResp.Choices) == 0 {
		return "", fmt.Errorf("no response from LLM (empty choices)")
	}

	content := strings.TrimSpace(chatResp.Choices[0].Message.Content)
	if content == "" {
		return "", fmt.Errorf("LLM returned empty message content - model may need more tokens or the diff is too complex")
	}

	return content, nil
}
