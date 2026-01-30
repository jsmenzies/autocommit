package tui

import (
	"autocommit/internal/config"

	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type screen int

const (
	screenMainMenu screen = iota
	screenProviderList
	screenProviderConfig
	screenPromptEditor
	screenGitConfig
)

type providerInfo struct {
	name        string
	displayName string
	models      []string
}

var availableProviders = []providerInfo{
	{
		name:        "zai",
		displayName: "z.ai (GLM models)",
		models:      []string{"glm-4.7-Flash", "glm-4.7-FlashX", "glm-4.7"},
	},
	{
		name:        "openai",
		displayName: "OpenAI (GPT models)",
		models:      []string{"gpt-4o-mini", "gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo"},
	},
	{
		name:        "groq",
		displayName: "Groq (Ultra-fast inference)",
		models:      []string{"llama-3.1-8b-instant", "llama-3.3-70b-versatile", "llama-4-scout-17b-16e-instruct", "mixtral-8x7b-32768", "gemma2-9b-it"},
	},
}

type model struct {
	screen    screen
	config    *config.Config
	configErr error
	// Main menu
	menuCursor int
	menuItems  []menuItem
	// Provider list
	providerCursor int
	// Provider config form
	providerConfigProvider string
	apiKeyInput            textinput.Model
	apiKeyAlreadySet       bool
	apiKeyOriginalValue    string
	modelCursor            int
	// Prompt editor
	promptTextarea textarea.Model
	// Help
	help help.Model
	keys keyMap
	// Styling
	style *styles
	// Dimensions
	width  int
	height int
}
type menuItem struct {
	title       string
	description string
	action      func() tea.Cmd
}
type keyMap struct {
	Up    key.Binding
	Down  key.Binding
	Left  key.Binding
	Right key.Binding
	Enter key.Binding
	Back  key.Binding
	Quit  key.Binding
	Save  key.Binding
}

func (k keyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.Up, k.Down, k.Enter, k.Back, k.Quit}
}
func (k keyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.Left, k.Right},
		{k.Enter, k.Back, k.Save, k.Quit},
	}
}

type styles struct {
	title       lipgloss.Style
	subtitle    lipgloss.Style
	menuItem    lipgloss.Style
	menuCursor  lipgloss.Style
	label       lipgloss.Style
	value       lipgloss.Style
	error       lipgloss.Style
	success     lipgloss.Style
	instruction lipgloss.Style
}

func newStyles() *styles {
	return &styles{
		title:       lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#7D56F4")).MarginBottom(1),
		subtitle:    lipgloss.NewStyle().Foreground(lipgloss.Color("#999999")).MarginBottom(1),
		menuItem:    lipgloss.NewStyle().PaddingLeft(2),
		menuCursor:  lipgloss.NewStyle().Foreground(lipgloss.Color("#7D56F4")).Bold(true),
		label:       lipgloss.NewStyle().Foreground(lipgloss.Color("#999999")),
		value:       lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF")),
		error:       lipgloss.NewStyle().Foreground(lipgloss.Color("#FF5555")),
		success:     lipgloss.NewStyle().Foreground(lipgloss.Color("#55FF55")),
		instruction: lipgloss.NewStyle().Foreground(lipgloss.Color("#666666")).MarginTop(1),
	}
}
