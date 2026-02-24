package tools

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	copilot "github.com/github/copilot-sdk/go"
)

type MCPRequest struct {
	JSONRPC string `json:"jsonrpc"`
	ID      int    `json:"id"`
	Method  string `json:"method"`
	Params  any    `json:"params,omitempty"`
}

type MCPResponse struct {
	Result MCPResult `json:"result"`
	Error  *MCPError `json:"error,omitempty"`
}

type MCPResult struct {
	Tools   []MCPTool    `json:"tools"`
	Content []MCPContent `json:"content,omitempty"`
}

type MCPError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    string `json:"data"`
}

type MCPTool struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	InputSchema map[string]any `json:"inputSchema"`
}

type MCPContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

func RegisterDynamicTools(backendURL, apiKey string) ([]copilot.Tool, error) {
	reqBody, _ := json.Marshal(MCPRequest{JSONRPC: "2.0", ID: 1, Method: "tools/list"})
	req, err := http.NewRequest("POST", backendURL, bytes.NewBuffer(reqBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch tools from %s: %w", backendURL, err)
	}
	defer resp.Body.Close()

	var mcpResp MCPResponse
	if err := json.NewDecoder(resp.Body).Decode(&mcpResp); err != nil {
		return nil, fmt.Errorf("failed to parse tools JSON: %w", err)
	}

	if mcpResp.Error != nil {
		return nil, fmt.Errorf("error from backend: %s - %s", mcpResp.Error.Message, mcpResp.Error.Data)
	}

	var copilotTools []copilot.Tool

	for _, t := range mcpResp.Result.Tools {
		toolName := t.Name // Capture variable for closure

		cTool := copilot.Tool{
			Name:        t.Name,
			Description: t.Description,
			Parameters:  t.InputSchema,
			Handler: func(inv copilot.ToolInvocation) (copilot.ToolResult, error) {
				callBody, _ := json.Marshal(MCPRequest{
					JSONRPC: "2.0",
					ID:      1,
					Method:  "tools/call",
					Params: map[string]any{
						"name":      toolName,
						"arguments": inv.Arguments,
					},
				})

				creq, _ := http.NewRequest("POST", backendURL, bytes.NewBuffer(callBody))
				creq.Header.Set("Content-Type", "application/json")
				if apiKey != "" {
					creq.Header.Set("X-API-Key", apiKey)
				}

				// The user requested a strict 15-second timeout for Copilot fallback/self-correction.
				cclient := &http.Client{Timeout: 15 * time.Second}
				cresp, cerr := cclient.Do(creq)
				if cerr != nil {
					return copilot.ToolResult{}, fmt.Errorf("tool call %s failed (timeout/conn): %w", toolName, cerr)
				}
				defer cresp.Body.Close()

				var callResp MCPResponse
				if err := json.NewDecoder(cresp.Body).Decode(&callResp); err != nil {
					return copilot.ToolResult{}, fmt.Errorf("failed to parse tool response: %w", err)
				}

				if callResp.Error != nil {
					return copilot.ToolResult{
						TextResultForLLM: fmt.Sprintf("Error from tool: %s - %s", callResp.Error.Message, callResp.Error.Data),
						ResultType:       "error",
						SessionLog:       fmt.Sprintf("Tool %s failed: %s", toolName, callResp.Error.Message),
					}, fmt.Errorf("tool execution failed: %s", callResp.Error.Message)
				}

				var resultText string
				for _, c := range callResp.Result.Content {
					resultText += c.Text + "\n"
				}

				return copilot.ToolResult{
					TextResultForLLM: resultText,
					ResultType:       "success",
					SessionLog:       fmt.Sprintf("Called tool %s successfully", toolName),
				}, nil
			},
		}
		copilotTools = append(copilotTools, cTool)
	}

	return copilotTools, nil
}
