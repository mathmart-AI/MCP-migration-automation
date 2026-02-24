package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	copilot "github.com/github/copilot-sdk/go"
	"github.com/mathismartini/mcp-axon-proxy/internal/prompts"
	"github.com/mathismartini/mcp-axon-proxy/internal/tools"
)

// ══════════════════════════════════════════════════════════════════════════════
// 🧠 Axon CLI — Headless Agentic Runner
// Usage:
//   axon-cli --mission MISSION_K3D.md --role persona_k8s_expert
//
// Environment:
//   AXON_BACKEND_URL  (default: http://localhost:8000/mcp)
//   AXON_API_KEY      (optional)
// ══════════════════════════════════════════════════════════════════════════════

// ANSI colors for terminal output
const (
	colorReset  = "\033[0m"
	colorCyan   = "\033[36m"
	colorGreen  = "\033[32m"
	colorYellow = "\033[33m"
	colorRed    = "\033[31m"
	colorDim    = "\033[2m"
	colorBold   = "\033[1m"
)

func main() {
	// ── Parse flags ──────────────────────────────────────────────────────────
	missionPath := flag.String("mission", "", "Path to the mission Markdown file (e.g. MISSION_K3D.md)")
	roleName := flag.String("role", "", "Name of the expert persona/agent to use (e.g. persona_k8s_expert)")
	model := flag.String("model", "chatgpt-5mini", "LLM model to use for the session")
	flag.Parse()

	if *missionPath == "" || *roleName == "" {
		fmt.Fprintf(os.Stderr, "%s❌ Usage: axon-cli --mission <file.md> --role <persona_name>%s\n", colorRed, colorReset)
		fmt.Fprintf(os.Stderr, "\nAvailable roles:\n")
		for _, name := range prompts.ListAgentNames() {
			fmt.Fprintf(os.Stderr, "  • %s\n", name)
		}
		os.Exit(1)
	}

	// ── Read mission file ────────────────────────────────────────────────────
	missionBytes, err := os.ReadFile(*missionPath)
	if err != nil {
		log.Fatalf("❌ Cannot read mission file %q: %v", *missionPath, err)
	}
	missionContent := strings.TrimSpace(string(missionBytes))
	if missionContent == "" {
		log.Fatalf("❌ Mission file %q is empty", *missionPath)
	}

	// ── Resolve persona ──────────────────────────────────────────────────────
	agent := prompts.GetAgentByRole(*roleName)
	if agent == nil {
		fmt.Fprintf(os.Stderr, "%s❌ Unknown role %q%s\n", colorRed, *roleName, colorReset)
		fmt.Fprintf(os.Stderr, "Available roles:\n")
		for _, name := range prompts.ListAgentNames() {
			fmt.Fprintf(os.Stderr, "  • %s\n", name)
		}
		os.Exit(1)
	}

	// ── Banner ───────────────────────────────────────────────────────────────
	printBanner(*missionPath, agent.Name, agent.DisplayName, *model)

	// ── Initialize Copilot client ────────────────────────────────────────────
	fmt.Printf("%s[1/4]%s Initializing Copilot SDK client...\n", colorCyan, colorReset)
	client := copilot.NewClient(&copilot.ClientOptions{
		LogLevel: "debug", // Temporarily set to debug to see SDK internals
	})

	ctx := context.Background()
	if err := client.Start(ctx); err != nil {
		log.Fatalf("❌ Failed to start Copilot client: %v", err)
	}
	defer client.Stop()
	fmt.Printf("%s  ✓ Copilot client started%s\n", colorGreen, colorReset)

	// ── Register tools from Python backend ───────────────────────────────────
	fmt.Printf("%s[2/4]%s Connecting to Axon backend and registering tools...\n", colorCyan, colorReset)
	backendURL := os.Getenv("AXON_BACKEND_URL")
	if backendURL == "" {
		backendURL = "http://localhost:8000/mcp"
	}
	apiKey := os.Getenv("AXON_API_KEY")

	toolsList, err := tools.RegisterDynamicTools(backendURL, apiKey)
	if err != nil {
		log.Fatalf("❌ Failed to register tools from backend (%s): %v", backendURL, err)
	}
	fmt.Printf("%s  ✓ %d tools registered from %s%s\n", colorGreen, len(toolsList), backendURL, colorReset)

	// ── Create session ───────────────────────────────────────────────────────
	fmt.Printf("%s[3/4]%s Creating LLM session (model: %s, persona: %s)...\n",
		colorCyan, colorReset, *model, agent.Name)

	session, err := client.CreateSession(ctx, &copilot.SessionConfig{
		Model:        *model,
		Tools:        toolsList,
		CustomAgents: []copilot.CustomAgentConfig{*agent},
		Streaming:    true,
	})
	if err != nil {
		log.Fatalf("❌ Failed to create session: %v", err)
	}
	defer session.Destroy()
	fmt.Printf("%s  ✓ Session ready%s\n", colorGreen, colorReset)

	// ── Event handler — stream output to stdout ──────────────────────────────
	var totalChars int
	done := make(chan struct{})

	// Add a small helper to safely close the channel once
	closeDone := func() {
		select {
		case <-done:
			// Already closed
		default:
			close(done)
		}
	}

	session.On(func(event copilot.SessionEvent) {
		// DEBUG: Log every event type we receive
		// fmt.Fprintf(os.Stderr, "%s[DEBUG EVENT] type=%q%s\n", colorDim, event.Type, colorReset)

		switch event.Type {
		case "assistant.message.delta", "assistant.message_delta":
			if event.Data.DeltaContent != nil {
				content := *event.Data.DeltaContent
				totalChars += len(content)
				fmt.Print(content)
			}
		case "assistant.message":
			if event.Data.Content != nil {
				content := *event.Data.Content
				if len(content) >= totalChars {
					diff := content[totalChars:]
					totalChars = len(content)
					if len(diff) > 0 {
						fmt.Print(diff)
					}
				} else {
					totalChars += len(content)
					fmt.Print(content)
				}
			}
		case "tool.execution_start":
			if event.Data.ToolName != nil {
				argsStr := ""
				if event.Data.Arguments != nil {
					if b, err := json.Marshal(event.Data.Arguments); err == nil {
						var m map[string]interface{}
						if json.Unmarshal(b, &m) == nil && len(m) > 0 {
							var parts []string
							for k, v := range m {
								parts = append(parts, fmt.Sprintf("%s: %v", k, v))
							}
							argsStr = " (" + strings.Join(parts, ", ") + ")"
						} else {
							argsStr = " " + string(b)
						}
					}
				}
				fmt.Printf("\n%s[Tool Execution: %s%s]%s\n", colorYellow, *event.Data.ToolName, argsStr, colorReset)
			} else {
				fmt.Printf("\n%s[Tool Execution...]%s\n", colorYellow, colorReset)
			}
		case "assistant.message.done":
			closeDone()
		case "error":
			fmt.Printf("\n%s❌ [Error] %v%s\n", colorRed, event.Data, colorReset)
			closeDone()
		// Also close on session shutdown/idle as fallback
		case "session.shutdown", "session.idle":
			closeDone()
		default:
			// DEBUG: log unknown event types with full data (optional, can be noisy)
			// fmt.Fprintf(os.Stderr, "%s[DEBUG EVENT DATA] %+v%s\n", colorDim, event.Data, colorReset)
		}
	})

	// ── Send mission prompt ──────────────────────────────────────────────────
	fmt.Printf("\n%s[4/4]%s Sending mission to LLM (this may take a while)...\n", colorCyan, colorReset)
	fmt.Printf("%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n", colorDim, colorReset)

	go func() {
		_, err := session.Send(ctx, copilot.MessageOptions{
			Prompt: missionContent,
		})
		if err != nil {
			log.Printf("\n❌ Failed to send mission: %v\n", err)
			closeDone()
		}
		// DO NOT close the channel here! Send is async.
		// The SDK will fire "assistant.message.done" when generation finishes.
	}()

	// ── Wait for the LLM to finish ───────────────────────────────────────────
	// Wait on the done channel, but with a timeout just in case the SDK events
	// change or miss the "done" signal.
	timeout := time.After(5 * time.Minute)
	select {
	case <-done:
		// Normal exit triggered by events
	case <-timeout:
		fmt.Printf("\n%s⚠️ Timeout: LLM took too long to respond (>5min). Output might be incomplete.%s\n", colorRed, colorReset)
	}

	// ── Done ─────────────────────────────────────────────────────────────────
	fmt.Printf("\n\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n", colorGreen, colorReset)
	fmt.Printf("%s✅ Mission completed. Total response: %d characters.%s\n",
		colorGreen, totalChars, colorReset)
}

// printBanner displays a styled startup banner.
func printBanner(missionFile, agentName, agentDisplay, model string) {
	fmt.Printf("\n%s%s", colorBold, colorCyan)
	fmt.Println("╔══════════════════════════════════════════════════════════════╗")
	fmt.Println("║           🧠  AXON CLI — Headless Agentic Runner           ║")
	fmt.Println("╚══════════════════════════════════════════════════════════════╝")
	fmt.Printf("%s", colorReset)
	fmt.Printf("  Mission  : %s\n", missionFile)
	fmt.Printf("  Role     : %s %s\n", agentDisplay, agentName)
	fmt.Printf("  Model    : %s\n", model)
	fmt.Println()
}
