package main

import (
    "context"
    "fmt"
    "os"
    "os/exec"
    "time"
    "github.com/modelcontextprotocol/go-sdk/mcp"
)

func main() {
    ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
    defer cancel()
    client := mcp.NewClient(&mcp.Implementation{Name: "racket-interop", Version: "1"}, nil)
    command := exec.Command("racket", os.Args[1])
    command.Stderr = os.Stderr
    session, err := client.Connect(ctx, &mcp.CommandTransport{Command: command}, &mcp.ClientSessionOptions{ProtocolVersion: "2026-07-28"})
    if err != nil { panic(err) }
    defer session.Close()
    tools, err := session.ListTools(ctx, nil)
    if err != nil { panic(err) }
    if len(tools.Tools) != 1 || tools.Tools[0].Name != "greet" { panic("unexpected tool listing") }
    result, err := session.CallTool(ctx, &mcp.CallToolParams{Name: "greet", Arguments: map[string]any{"name": "Go"}})
    if err != nil { panic(err) }
    text, ok := result.Content[0].(*mcp.TextContent)
    if !ok || text.Text != "Hello, Go" { panic("unexpected tool result") }
    fmt.Println("Official Go SDK: discovery, tool listing, and tool call passed (2026-07-28).")
}
