package tui

import (
	"autocommit/internal/config"
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

func (m model) updateProviderList(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "up", "k":
		if m.providerCursor > 0 {
			m.providerCursor--
		}
	case "down", "j":
		if m.providerCursor < len(availableProviders)-1 {
			m.providerCursor++
		}
	case "enter":
		selectedProvider := availableProviders[m.providerCursor]
		m.providerConfigProvider = selectedProvider.name

		// Check if provider is already configured
		if m.config != nil && m.config.Providers != nil {
			if providerCfg, exists := m.config.Providers[selectedProvider.name]; exists {
				// Pre-fill existing values
				m.apiKeyInput.SetValue(providerCfg.APIKey)
				// Find model index
				for i, model := range selectedProvider.models {
					if model == providerCfg.Model {
						m.modelCursor = i
						break
					}
				}
			} else {
				// Reset inputs for new provider
				m.apiKeyInput.SetValue("")
				m.modelCursor = 0
			}
		} else {
			// Reset inputs for new provider
			m.apiKeyInput.SetValue("")
			m.modelCursor = 0
		}
		m.apiKeyInput.Focus()
		m.screen = screenProviderConfig
	case "esc":
		m.screen = screenMainMenu
	case "q", "ctrl+c":
		return m, tea.Quit
	}
	return m, nil
}

func (m model) viewProviderList() string {
	s := m.style

	title := s.title.Render("Select Provider")
	subtitle := s.subtitle.Render("Choose an LLM provider to configure")

	var items string
	for i, provider := range availableProviders {
		cursor := "  "
		if m.providerCursor == i {
			cursor = s.menuCursor.Render("> ")
		}

		// Check if configured
		status := "not configured"
		if m.config != nil && m.config.Providers != nil {
			if _, exists := m.config.Providers[provider.name]; exists {
				if m.config.DefaultProvider == provider.name {
					status = s.success.Render("active")
				} else {
					status = s.value.Render("configured")
				}
			}
		}

		items += fmt.Sprintf("%s%s %s\n", cursor, s.menuItem.Render(provider.displayName), status)
	}

	return title + "\n" + subtitle + "\n\n" + items + "\n" + s.instruction.Render("esc: back • enter: select • q: quit")
}

func (m model) updateProviderConfig(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	providerInfo := availableProviders[m.providerCursor]

	switch msg.String() {
	case "ctrl+v":
		// Allow paste operation to pass through to textinput
		return m, nil
	case "up", "k":
		// Move between fields
		if m.apiKeyInput.Focused() {
			m.apiKeyInput.Blur()
		} else {
			m.apiKeyInput.Focus()
		}
	case "down", "j":
		// Move between fields
		if m.apiKeyInput.Focused() {
			m.apiKeyInput.Blur()
		} else {
			m.apiKeyInput.Focus()
		}
	case "left", "h":
		if !m.apiKeyInput.Focused() && m.modelCursor > 0 {
			m.modelCursor--
		}
	case "right", "l":
		if !m.apiKeyInput.Focused() && m.modelCursor < len(providerInfo.models)-1 {
			m.modelCursor++
		}
	case "enter":
		// Save the configuration
		if m.config == nil {
			m.config = &config.Config{
				Providers: make(map[string]config.ProviderConfig),
			}
		}

		m.config.Providers[m.providerConfigProvider] = config.ProviderConfig{
			APIKey: m.apiKeyInput.Value(),
			Model:  providerInfo.models[m.modelCursor],
		}
		m.config.DefaultProvider = m.providerConfigProvider

		if err := m.saveConfig(); err != nil {
			// Error will be displayed in a future enhancement
			return m, nil
		}
		m.screen = screenProviderList
	case "esc":
		m.screen = screenProviderList
	case "q", "ctrl+c":
		return m, tea.Quit
	}
	return m, nil
}

func (m model) viewProviderConfig() string {
	s := m.style
	providerInfo := availableProviders[m.providerCursor]

	title := s.title.Render(fmt.Sprintf("Configure %s", providerInfo.displayName))

	// API Key field
	apiKeyLabel := s.label.Render("API Key:")
	apiKeyValue := m.apiKeyInput.View()

	// Model selection
	var modelOptions []string
	for i, model := range providerInfo.models {
		if i == m.modelCursor {
			modelOptions = append(modelOptions, s.menuCursor.Render("["+model+"]"))
		} else {
			modelOptions = append(modelOptions, s.value.Render(" "+model+" "))
		}
	}
	modelLabel := s.label.Render("Model:")
	modelValue := strings.Join(modelOptions, " ")

	return title + "\n\n" +
		apiKeyLabel + "\n" + apiKeyValue + "\n\n" +
		modelLabel + "\n" + modelValue + "\n\n" +
		s.instruction.Render("tab/↑↓: switch fields • ←→: change model • enter: save • esc: back")
}
