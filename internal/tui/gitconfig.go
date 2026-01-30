package tui

import (
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
		// Toggle the selected option
		m.ensureConfig()

		switch m.menuCursor {
		case 0:
			m.config.AutoAdd = !m.config.AutoAdd
		case 1:
			m.config.AutoPush = !m.config.AutoPush
		}

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

	// Auto-add item
	var autoAddStatus string
	if m.config != nil && m.config.AutoAdd {
		autoAddStatus = s.success.Render("enabled")
	} else {
		autoAddStatus = s.value.Render("disabled")
	}

	cursor0 := "  "
	if m.menuCursor == 0 {
		cursor0 = s.menuCursor.Render("> ")
	}
	autoAddItem := fmt.Sprintf("%s%s %s", cursor0, s.menuItem.Render("Auto-add changes"), autoAddStatus)

	// Auto-push item
	var autoPushStatus string
	if m.config != nil && m.config.AutoPush {
		autoPushStatus = s.success.Render("enabled")
	} else {
		autoPushStatus = s.value.Render("disabled")
	}

	cursor1 := "  "
	if m.menuCursor == 1 {
		cursor1 = s.menuCursor.Render("> ")
	}
	autoPushItem := fmt.Sprintf("%s%s %s", cursor1, s.menuItem.Render("Auto-push commits"), autoPushStatus)

	return title + "\n" + subtitle + "\n\n" +
		autoAddItem + "\n" +
		autoPushItem + "\n\n" +
		s.instruction.Render("↑↓: navigate • enter: toggle • esc: back • q: quit") + "\n\n" +
		s.label.Render("Auto-add: automatically stage all changes if none are staged\n") +
		s.label.Render("Auto-push: automatically push commits after committing")
}
