package llm

// Default LLM generation parameters
const (
	DefaultTemperature = 0.7
	DefaultMaxTokens   = 500
	ZaiMaxTokens       = 1500
)

// Provider names
const (
	ProviderZai    = "zai"
	ProviderOpenAI = "openai"
	ProviderGroq   = "groq"
)

// Default models for each provider
const (
	DefaultZaiModel    = "glm-4.7"
	DefaultOpenAIModel = "gpt-4o-mini"
	DefaultGroqModel   = "llama-3.1-8b-instant"
)
