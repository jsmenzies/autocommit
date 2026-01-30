package tui

import (
	"autocommit/internal/config"

	tea "github.com/charmbracelet/bubbletea"
)

func (m model) updatePromptEditor(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+s":
		// Save the prompt
		if m.config == nil {
			m.config = &config.Config{
				Providers: make(map[string]config.ProviderConfig),
			}
		}
		m.config.SystemPrompt = m.promptTextarea.Value()
		if err := m.saveConfig(); err != nil {
			return m, nil
		}
		m.screen = screenMainMenu
	case "esc":
		m.screen = screenMainMenu
	case "q", "ctrl+c":
		return m, tea.Quit
	}
	return m, nil
}

func (m model) viewPromptEditor() string {
	s := m.style

	title := s.title.Render("Edit System Prompt")
	subtitle := s.subtitle.Render("Customize the prompt used for generating commit messages")

	textareaView := m.promptTextarea.View()

	help := s.instruction.Render("ctrl+s: save • esc: back without saving • q: quit")

	return title + "\n" + subtitle + "\n\n" + textareaView + "\n\n" + help
}
