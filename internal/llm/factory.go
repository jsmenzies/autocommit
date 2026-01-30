package llm

import "fmt"

// ProviderFactory is a function that creates a Provider instance
type ProviderFactory func(apiKey, model, systemPrompt string) Provider

// factories maps provider names to their factory functions
var factories = map[string]ProviderFactory{
	ProviderZai: func(apiKey, model, systemPrompt string) Provider {
		return NewZaiProvider(apiKey, model, systemPrompt)
	},
	ProviderOpenAI: func(apiKey, model, systemPrompt string) Provider {
		return NewOpenAIProvider(apiKey, model, systemPrompt)
	},
	ProviderGroq: func(apiKey, model, systemPrompt string) Provider {
		return NewGroqProvider(apiKey, model, systemPrompt)
	},
}

// CreateProvider creates a provider instance by name
func CreateProvider(name, apiKey, model, systemPrompt string) (Provider, error) {
	factory, exists := factories[name]
	if !exists {
		return nil, fmt.Errorf("unsupported provider: %s", name)
	}
	return factory(apiKey, model, systemPrompt), nil
}

// RegisterProvider registers a new provider factory (useful for extensions)
func RegisterProvider(name string, factory ProviderFactory) {
	factories[name] = factory
}
