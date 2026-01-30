package llm

import "fmt"

type ProviderFactory func(apiKey, model, systemPrompt string) Provider

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

func CreateProvider(name, apiKey, model, systemPrompt string) (Provider, error) {
	factory, exists := factories[name]
	if !exists {
		return nil, fmt.Errorf("unsupported provider: %s", name)
	}
	return factory(apiKey, model, systemPrompt), nil
}
