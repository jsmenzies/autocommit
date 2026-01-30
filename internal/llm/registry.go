package llm

// ProviderInfo contains metadata about an LLM provider
type ProviderInfo struct {
	Name        string
	DisplayName string
	Models      []string
}

// Registry contains metadata for all available providers
var Registry = []ProviderInfo{
	{
		Name:        ProviderZai,
		DisplayName: "z.ai (GLM models)",
		Models:      []string{"glm-4.7-Flash", "glm-4.7-FlashX", "glm-4.7"},
	},
	{
		Name:        ProviderOpenAI,
		DisplayName: "OpenAI (GPT models)",
		Models:      []string{"gpt-4o-mini", "gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo"},
	},
	{
		Name:        ProviderGroq,
		DisplayName: "Groq (Ultra-fast inference)",
		Models:      []string{"llama-3.1-8b-instant", "llama-3.3-70b-versatile", "llama-4-scout-17b-16e-instruct", "mixtral-8x7b-32768", "gemma2-9b-it"},
	},
}

// GetProviderInfo returns the provider info for a given provider name
func GetProviderInfo(name string) (ProviderInfo, bool) {
	for _, info := range Registry {
		if info.Name == name {
			return info, true
		}
	}
	return ProviderInfo{}, false
}

// GetProviderNames returns a list of all registered provider names
func GetProviderNames() []string {
	names := make([]string, len(Registry))
	for i, info := range Registry {
		names[i] = info.Name
	}
	return names
}
