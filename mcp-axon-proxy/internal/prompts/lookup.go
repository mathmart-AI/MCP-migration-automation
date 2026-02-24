package prompts

import (
	"strings"

	copilot "github.com/github/copilot-sdk/go"
)

// GetAgentByRole searches for a CustomAgentConfig by name.
// It matches exact name first, then falls back to substring/contains matching.
// Returns nil if no match is found.
func GetAgentByRole(roleName string) *copilot.CustomAgentConfig {
	agents := GetExpertAgents()
	lower := strings.ToLower(roleName)

	// Pass 1: exact match on Name field
	for i, a := range agents {
		if strings.ToLower(a.Name) == lower {
			return &agents[i]
		}
	}

	// Pass 2: substring match (e.g. "k8s" matches "persona_k8s_expert")
	for i, a := range agents {
		if strings.Contains(strings.ToLower(a.Name), lower) {
			return &agents[i]
		}
	}

	return nil
}

// ListAgentNames returns all available persona names for help/error messages.
func ListAgentNames() []string {
	agents := GetExpertAgents()
	names := make([]string, len(agents))
	for i, a := range agents {
		names[i] = a.Name
	}
	return names
}
