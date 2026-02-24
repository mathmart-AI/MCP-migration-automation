//go:build integration

package tools

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
)

// backendURL returns the test MCP backend URL.
// Override with AXON_BACKEND_URL env var if needed.
func backendURL() string {
	if u := os.Getenv("AXON_BACKEND_URL"); u != "" {
		return u
	}
	return "http://localhost:8000/mcp"
}

// sendMCPRequest is a helper that sends a JSON-RPC request to the Python backend
// and returns the raw response body as a map. It mimics exactly what the Go proxy
// handler closures do in tools.go.
func sendMCPRequest(t *testing.T, payload MCPRequest) map[string]any {
	t.Helper()

	body, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("Failed to marshal request payload: %v", err)
	}

	req, err := http.NewRequest("POST", backendURL(), bytes.NewBuffer(body))
	if err != nil {
		t.Fatalf("Failed to create HTTP request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("HTTP request failed (is the Python backend running on %s?): %v", backendURL(), err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected HTTP 200 OK, got %d %s", resp.StatusCode, resp.Status)
	}

	var result map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		t.Fatalf("Failed to decode JSON response: %v", err)
	}

	return result
}

// ---------------------------------------------------------------------------
// TEST 1: tools/list relay
// ---------------------------------------------------------------------------
// Proves: The Go proxy can reach the Python backend and retrieve the full
// list of available MCP tools via JSON-RPC.
func TestToolsListRelay(t *testing.T) {
	result := sendMCPRequest(t, MCPRequest{
		JSONRPC: "2.0",
		ID:      1,
		Method:  "tools/list",
	})

	// Verify response structure
	resultField, ok := result["result"].(map[string]any)
	if !ok {
		t.Fatalf("Response missing 'result' field or wrong type: %v", result)
	}

	toolsField, ok := resultField["tools"].([]any)
	if !ok {
		t.Fatalf("Result missing 'tools' array: %v", resultField)
	}

	// Verify we got a reasonable number of tools (the backend has 28 defined)
	if len(toolsField) < 10 {
		t.Fatalf("Expected at least 10 tools, got %d", len(toolsField))
	}

	t.Logf("✅ tools/list returned %d tools from Python backend", len(toolsField))

	// Verify at least one known tool exists (list_repositories is the simplest)
	found := false
	for _, tool := range toolsField {
		toolMap, ok := tool.(map[string]any)
		if !ok {
			continue
		}
		if toolMap["name"] == "list_repositories" {
			found = true
			break
		}
	}
	if !found {
		t.Fatal("Expected to find tool 'list_repositories' in tools list")
	}

	t.Log("✅ Found 'list_repositories' tool in the listing")
}

// ---------------------------------------------------------------------------
// TEST 2: tools/call relay with list_repositories
// ---------------------------------------------------------------------------
// Proves: The relay can dispatch a tools/call JSON-RPC command and receive
// a structured response. list_repositories has no required args.
func TestExecuteToolRelay_ListRepositories(t *testing.T) {
	result := sendMCPRequest(t, MCPRequest{
		JSONRPC: "2.0",
		ID:      2,
		Method:  "tools/call",
		Params: map[string]any{
			"name":      "list_repositories",
			"arguments": map[string]any{},
		},
	})

	// The response must contain a "result" field (even if the DB is not
	// connected, the handler will return a TextContent with an error message
	// rather than an HTTP-level error).
	resultField, ok := result["result"].(map[string]any)
	if !ok {
		// Check if there's an error field at the JSON-RPC level
		errField, hasErr := result["error"]
		if hasErr {
			t.Logf("⚠️  JSON-RPC error (expected without DB): %v", errField)
			// This is still a valid relay — the backend processed the request
			// and returned a proper JSON-RPC error. PASS.
			t.Log("✅ tools/call relay works (JSON-RPC error response received)")
			return
		}
		t.Fatalf("Response missing both 'result' and 'error' fields: %v", result)
	}

	// If we got a result, check for content
	content, ok := resultField["content"].([]any)
	if ok && len(content) > 0 {
		t.Logf("✅ tools/call list_repositories returned %d content items", len(content))
	} else {
		t.Log("✅ tools/call list_repositories returned a valid result structure")
	}
}

// ---------------------------------------------------------------------------
// TEST 3: tools/call relay with list_symbols_in_file (spring-petclinic)
// ---------------------------------------------------------------------------
// Proves: The Go proxy can relay a file-analysis tool call pointing to a real
// Java file from the cloned spring-petclinic repo. We don't expect the DB-
// backed tool to succeed, but we prove the HTTP relay handles the request
// end-to-end with a structured JSON response.
func TestExecuteToolRelay_GetFileSymbols(t *testing.T) {
	// Build path to a real Java file from the cloned test context
	petClinicFile := "/tmp/axon-test-context/spring-petclinic/src/main/java/org/springframework/samples/petclinic/PetClinicApplication.java"
	if _, err := os.Stat(petClinicFile); os.IsNotExist(err) {
		t.Skipf("Spring PetClinic not cloned at %s — skipping", petClinicFile)
	}

	result := sendMCPRequest(t, MCPRequest{
		JSONRPC: "2.0",
		ID:      3,
		Method:  "tools/call",
		Params: map[string]any{
			"name": "list_symbols_in_file",
			"arguments": map[string]any{
				"repository_id": 1,
				"file_path":     petClinicFile,
			},
		},
	})

	// Verify we got a valid JSON-RPC response (result or error)
	_, hasResult := result["result"]
	_, hasError := result["error"]

	if !hasResult && !hasError {
		t.Fatalf("Response missing both 'result' and 'error': %v", result)
	}

	// If we got a result, inspect the content for text
	if hasResult {
		resultField := result["result"].(map[string]any)
		content, ok := resultField["content"].([]any)
		if ok && len(content) > 0 {
			// Extract text from first content item
			firstItem := content[0].(map[string]any)
			text, _ := firstItem["text"].(string)
			if text != "" {
				t.Logf("✅ Got text response (%d chars): %s", len(text), truncate(text, 200))
			}
		}
	}

	// Convert to JSON to prove it's valid structured data
	responseJSON, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		t.Fatalf("Response is not valid JSON: %v", err)
	}

	t.Logf("✅ E2E relay for list_symbols_in_file completed. Response size: %d bytes", len(responseJSON))
	t.Logf("📁 Java file used: %s", petClinicFile)

	// Final assertion: the JSON response must contain the jsonrpc field
	if _, ok := result["jsonrpc"]; !ok {
		t.Fatal("Response missing 'jsonrpc' field — not a valid JSON-RPC response")
	}
}

// truncate shortens a string for display
func truncate(s string, maxLen int) string {
	s = strings.ReplaceAll(s, "\n", " ")
	if len(s) <= maxLen {
		return s
	}
	return fmt.Sprintf("%s...", s[:maxLen])
}
