package main

import (
	"log"
	"os"
	"path/filepath"

	"mcp-migration-server/internal/mcp"
)

func main() {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("Could not get home dir: %v", err)
	}

	contextDir := filepath.Join(homeDir, "CONTEXT")
	envContext := os.Getenv("MCP_CONTEXT_DIR")
	if envContext != "" {
		contextDir = envContext
	}

	log.Printf("Starting MCP Migration Server on target context: %s\n", contextDir)
	if err := mcp.RunServer(contextDir); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
