package tools

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	copilot "github.com/github/copilot-sdk/go"
)

type RunGoPlatformParams struct {
	Args []string `json:"args" jsonschema:"Arguments to pass to the go-platform cli, e.g. ['template', 'helm-platform', '-f', 'values.yaml']"`
}

func RunGoPlatformCLI(contextDir string) copilot.Tool {
	return copilot.DefineTool(
		"run_go_platform_cli",
		"Executes commands via the go-platform binary located in the context directory. Use this to validate helm templates and execute custom platform rules.",
		func(params RunGoPlatformParams, inv copilot.ToolInvocation) (any, error) {
			cliPath := filepath.Join(contextDir, "go-platform")

			// Check if binary exists
			if _, err := os.Stat(cliPath); os.IsNotExist(err) {
				return nil, fmt.Errorf("go-platform binary not found at %s", cliPath)
			}

			cmd := exec.Command(cliPath, params.Args...)
			cmd.Dir = contextDir

			var stdout bytes.Buffer
			var stderr bytes.Buffer
			cmd.Stdout = &stdout
			cmd.Stderr = &stderr

			err := cmd.Run()

			result := map[string]string{
				"stdout": stdout.String(),
				"stderr": stderr.String(),
			}

			if err != nil {
				result["error"] = err.Error()
			}

			return result, nil
		},
	)
}
