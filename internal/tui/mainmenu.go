package tui

import (
	"autocommit/internal/prompt"
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
)

func (m model) updateMainMenu(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "up", "k":
		if m.menuCursor > 0 {
			m.menuCursor--
		}
	case "down", "j":
		if m.menuCursor < len(m.menuItems)-1 {
			m.menuCursor++
		}
	case "enter":
		switch m.menuCursor {
		case 0: // Configure Provider
			m.screen = screenProviderList
		case 1: // Edit System Prompt
			// Set current prompt in textarea
			if m.config != nil {
				m.promptTextarea.SetValue(m.config.GetSystemPrompt())
			} else {
				m.promptTextarea.SetValue(prompt.GetDefaultSystemPrompt())
			}
			m.screen = screenPromptEditor
		case 2: // Git Configuration
			m.screen = screenGitConfig
		case 3: // Exit
			return m, tea.Quit
		}
	case "q", "ctrl+c":
		return m, tea.Quit
	}
	return m, nil
}

func (m model) viewMainMenu() string {
	s := m.style

	title := s.title.Render("AutoCommit Configuration")
	subtitle := s.subtitle.Render("Select an option to configure")

	var menuItems string
	for i, item := range m.menuItems {
		cursor := "  "
		if m.menuCursor == i {
			cursor = s.menuCursor.Render("> ")
		}
		menuItems += fmt.Sprintf("%s%s\n%s\n\n", cursor, s.menuItem.Render(item.title), s.label.Render("   "+item.description))
	}

	return title + "\n" + subtitle + "\n\n" + menuItems
}
