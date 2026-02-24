package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"sync"

	copilot "github.com/github/copilot-sdk/go"
)

func main() {
	client := copilot.NewClient(&copilot.ClientOptions{
		LogLevel: "debug",
	})
	ctx := context.Background()

	if err := client.Start(ctx); err != nil {
		log.Fatal(err)
	}
	defer client.Stop()

	session, err := client.CreateSession(ctx, &copilot.SessionConfig{
		Model: "chatgpt-5mini",
	})
	if err != nil {
		log.Fatalf("Failed to create session: %v", err)
	}
	defer session.Destroy()

	var wg sync.WaitGroup
	wg.Add(1)

	session.On(func(event copilot.SessionEvent) {
		fmt.Printf("[EVENT] %s\n", event.Type)
		switch event.Type {
		case "assistant.message":
			if event.Data.Content != nil {
				fmt.Print(*event.Data.Content)
			}
		case "assistant.message.done", "error":
			wg.Done()
		}
	})

	// Use scanner behavior exactly like server
	fmt.Println("Axon Proxy Test Agent ready.")

	// Just send one blocking message.
	_, err = session.Send(ctx, copilot.MessageOptions{
		Prompt: "Hello Copilot, reply with exactly one word: PING.",
	})
	if err != nil {
		log.Printf("Send error: %v", err)
	}

	fmt.Println("\nDone with send block. Waiting on STDIN...")

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		text := scanner.Text()
		fmt.Printf("Read: %s\n", text)
	}
}
