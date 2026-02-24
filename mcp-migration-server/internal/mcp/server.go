package mcp

import (
	"context"
	"fmt"
	"log"

	copilot "github.com/github/copilot-sdk/go"

	"mcp-migration-server/internal/prompts"
	"mcp-migration-server/internal/resources"
	"mcp-migration-server/internal/tools"
)

func RunServer(contextDir string) error {
	client := copilot.NewClient(&copilot.ClientOptions{
		LogLevel: "info",
	})

	if err := client.Start(context.Background()); err != nil {
		return fmt.Errorf("failed to start copilot client: %w", err)
	}
	defer client.Stop()

	// Combine tools
	myTools := []copilot.Tool{
		tools.RunGoPlatformCLI(contextDir),
	}
	myTools = append(myTools, resources.ExposeResources(contextDir)...)

	// Create a custom agent session
	session, err := client.CreateSession(context.Background(), &copilot.SessionConfig{
		Model: "gpt-5-mini", // User specified GPT-5 mini
		SystemMessage: &copilot.SystemMessageConfig{
			Mode:    "replace",
			Content: prompts.StartJavaToHelmMigrationPrompt(),
		},
		Tools: myTools,
	})

	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Destroy()

	log.Printf("MCP Migration Server successfully started for context: %s\n", contextDir)
	log.Println("Tools exposed to Copilot:")
	for _, t := range myTools {
		log.Printf(" - %s\n", t.Name)
	}

	// This blocks and keeps the local Go program running while the SDK server runs.
	// We wait until user terminates.
	// The Copilot CLI manages interaction over stdio/json-rpc.
	done := make(chan struct{})
	<-done

	return nil
}
