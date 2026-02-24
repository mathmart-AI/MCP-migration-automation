package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	copilot "github.com/github/copilot-sdk/go"
	"github.com/mathismartini/mcp-axon-proxy/internal/prompts"
	"github.com/mathismartini/mcp-axon-proxy/internal/tools"
)

func main() {
	// Initialize the Copilot client
	client := copilot.NewClient(&copilot.ClientOptions{
		LogLevel: "error",
	})

	ctx := context.Background()

	// Start the client
	log.Println("Starting Copilot Client (Axon Proxy)...")
	if err := client.Start(ctx); err != nil {
		log.Fatal(err)
	}
	defer client.Stop()

	// Get backend configuration
	backendURL := os.Getenv("AXON_BACKEND_URL")
	if backendURL == "" {
		backendURL = "http://localhost:8000/mcp"
	}
	apiKey := os.Getenv("AXON_API_KEY")

	// Define tools that proxy to Python backend
	toolsList, err := tools.RegisterDynamicTools(backendURL, apiKey)
	if err != nil {
		log.Fatalf("Failed to register dynamic tools: %v", err)
	}

	log.Printf("Successfully registered %d tools from Python backend!", len(toolsList))

	// Load expert personas (CustomAgents)
	expertAgents := prompts.GetExpertAgents()
	log.Printf("Loaded %d expert personas (CustomAgents).", len(expertAgents))

	// Create a session
	session, err := client.CreateSession(ctx, &copilot.SessionConfig{
		Model:        "chatgpt-5mini", // Adjust model as needed
		Tools:        toolsList,
		CustomAgents: expertAgents,
	})
	if err != nil {
		log.Fatalf("Failed to create session: %v", err)
	}
	defer session.Destroy()

	// Handle events
	session.On(func(event copilot.SessionEvent) {
		if event.Type == "assistant.message" {
			if event.Data.Content != nil {
				fmt.Printf("\n🤖 Copilot: %s\n> ", *event.Data.Content)
			}
		} else if event.Type == "error" {
			log.Printf("Session error: %v", event.Data)
		}
	})

	fmt.Println("Axon Proxy Agent ready. Type your prompt (or 'exit' to quit):")
	fmt.Print("> ")

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		text := strings.TrimSpace(scanner.Text())
		if text == "exit" || text == "quit" {
			break
		}
		if text == "" {
			fmt.Print("> ")
			continue
		}

		_, err := session.Send(ctx, copilot.MessageOptions{
			Prompt: text,
		})
		if err != nil {
			log.Printf("Error sending message: %v\n", err)
		}
	}

	if err := scanner.Err(); err != nil {
		log.Fatal(err)
	}

	fmt.Println("Goodbye!")
}
