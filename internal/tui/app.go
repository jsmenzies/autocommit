package tui

import (
	"autocommit/internal/config"

	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

func NewModel() model {
	// Load existing config
	cfg, err := config.Load("")

	// Initialize API key input
	apiKeyInput := textinput.New()
	apiKeyInput.Placeholder = "Enter your API key..."
	apiKeyInput.EchoMode = textinput.EchoPassword
	apiKeyInput.EchoCharacter = '•'
	apiKeyInput.Focus()

	// Initialize prompt textarea
	ta := textarea.New()
	ta.SetHeight(15)
	ta.SetWidth(80)
	ta.ShowLineNumbers = true
	ta.KeyMap.InsertNewline.SetEnabled(true)

	m := model{
		screen:         screenMainMenu,
		config:         cfg,
		configErr:      err,
		apiKeyInput:    apiKeyInput,
		promptTextarea: ta,
		help:           help.New(),
		keys:           defaultKeyMap(),
		style:          newStyles(),
	}

	m.updateMenuItems()

	return m
}

func defaultKeyMap() keyMap {
	return keyMap{
		Up: key.NewBinding(
			key.WithKeys("up", "k"),
			key.WithHelp("↑/k", "up"),
		),
		Down: key.NewBinding(
			key.WithKeys("down", "j"),
			key.WithHelp("↓/j", "down"),
		),
		Left: key.NewBinding(
			key.WithKeys("left", "h"),
			key.WithHelp("←/h", "left"),
		),
		Right: key.NewBinding(
			key.WithKeys("right", "l"),
			key.WithHelp("→/l", "right"),
		),
		Enter: key.NewBinding(
			key.WithKeys("enter"),
			key.WithHelp("enter", "select"),
		),
		Back: key.NewBinding(
			key.WithKeys("esc"),
			key.WithHelp("esc", "back"),
		),
		Quit: key.NewBinding(
			key.WithKeys("q", "ctrl+c"),
			key.WithHelp("q", "quit"),
		),
		Save: key.NewBinding(
			key.WithKeys("ctrl+s"),
			key.WithHelp("ctrl+s", "save"),
		),
	}
}

func (m *model) updateMenuItems() {
	items := []menuItem{
		{
			title:       "Configure Provider",
			description: "Select and configure LLM provider",
			action:      func() tea.Cmd { return nil },
		},
		{
			title:       "Edit System Prompt",
			description: "Customize the prompt used for commit message generation",
			action:      func() tea.Cmd { return nil },
		},
		{
			title:       "Exit",
			description: "Save and exit configuration",
			action:      func() tea.Cmd { return tea.Quit },
		},
	}
	m.menuItems = items
}

func (m model) Init() tea.Cmd {
	return tea.Batch(
		textinput.Blink,
	)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd
	var cmd tea.Cmd

	// Always update text input components first so they receive all input
	m.apiKeyInput, cmd = m.apiKeyInput.Update(msg)
	cmds = append(cmds, cmd)

	m.promptTextarea, cmd = m.promptTextarea.Update(msg)
	cmds = append(cmds, cmd)

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch m.screen {
		case screenMainMenu:
			return m.updateMainMenu(msg)
		case screenProviderList:
			return m.updateProviderList(msg)
		case screenProviderConfig:
			return m.updateProviderConfig(msg)
		case screenPromptEditor:
			return m.updatePromptEditor(msg)
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.promptTextarea.SetWidth(msg.Width - 4)
		m.promptTextarea.SetHeight(m.height - 10)
	}

	return m, tea.Batch(cmds...)
}

func (m model) View() string {
	if m.width == 0 {
		return "Loading..."
	}

	var content string

	switch m.screen {
	case screenMainMenu:
		content = m.viewMainMenu()
	case screenProviderList:
		content = m.viewProviderList()
	case screenProviderConfig:
		content = m.viewProviderConfig()
	case screenPromptEditor:
		content = m.viewPromptEditor()
	}

	helpView := m.help.View(m.keys)
	return content + "\n" + helpView
}

func Run() error {
	m := NewModel()
	p := tea.NewProgram(m, tea.WithAltScreen())
	_, err := p.Run()
	return err
}

func (m *model) saveConfig() error {
	if m.config == nil {
		m.config = &config.Config{
			Providers: make(map[string]config.ProviderConfig),
		}
	}
	return config.Save(m.config)
}
