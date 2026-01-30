package tui

import (
	"autocommit/internal/config"
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
)

func (m model) updateGitConfig(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "up", "k":
		if m.menuCursor > 0 {
			m.menuCursor--
		}
	case "down", "j":
		if m.menuCursor < 1 {
			m.menuCursor++
		}
	case "enter":
		// Toggle auto_add
		if m.config == nil {
			m.config = &config.Config{
				Providers: make(map[string]config.ProviderConfig),
			}
		}
		m.config.AutoAdd = !m.config.AutoAdd
		if err := m.saveConfig(); err != nil {
			// Error will be displayed in a future enhancement
			return m, nil
		}
	case "esc":
		m.screen = screenMainMenu
		m.menuCursor = 0
	case "q", "ctrl+c":
		return m, tea.Quit
	}
	return m, nil
}

func (m model) viewGitConfig() string {
	s := m.style

	title := s.title.Render("Git Configuration")
	subtitle := s.subtitle.Render("Configure git behavior settings")

	var autoAddStatus string
	if m.config != nil && m.config.AutoAdd {
		autoAddStatus = s.success.Render("enabled")
	} else {
		autoAddStatus = s.value.Render("disabled")
	}

	cursor := "  "
	if m.menuCursor == 0 {
		cursor = s.menuCursor.Render("> ")
	}

	autoAddItem := fmt.Sprintf("%s%s %s", cursor, s.menuItem.Render("Auto-add changes"), autoAddStatus)

	return title + "\n" + subtitle + "\n\n" +
		autoAddItem + "\n\n" +
		s.instruction.Render("enter: toggle • esc: back • q: quit") + "\n\n" +
		s.label.Render("When enabled, autocommit will automatically run 'git add .' if no changes are staged.")
}
