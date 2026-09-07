package main

import (
	"context"
	"fmt"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"os"
	"os/exec"
	"time"
)

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if len(os.Args) > 1 && os.Args[1] == "serve-cancellation" {
		serveCancellation(ctx)
		return
	}
	if len(os.Args) > 2 && os.Args[2] == "http-adaptive" {
		checkHTTPAdaptive(ctx, os.Args[1])
		return
	}
	progress := make(chan *mcp.ProgressNotificationParams, 16)
	options := &mcp.ClientOptions{}
	if len(os.Args) > 2 && os.Args[2] == "cancellation" {
		options.ProgressNotificationHandler = func(_ context.Context, req *mcp.ProgressNotificationClientRequest) {
			progress <- req.Params
		}
	}
	client := mcp.NewClient(&mcp.Implementation{Name: "racket-interop", Version: "1"}, options)
	command := exec.Command("racket", os.Args[1])
	command.Stderr = os.Stderr
	session, err := client.Connect(ctx, &mcp.CommandTransport{Command: command}, &mcp.ClientSessionOptions{ProtocolVersion: "2026-07-28"})
	if err != nil {
		panic(err)
	}
	defer session.Close()
	if len(os.Args) > 2 && os.Args[2] == "pagination" {
		checkPagination(ctx, session)
		return
	}
	if len(os.Args) > 2 && os.Args[2] == "cancellation" {
		checkCancellation(ctx, session, progress)
		return
	}
	if len(os.Args) > 2 && os.Args[2] == "multi-content" {
		checkMultiContent(ctx, session)
		return
	}
	tools, err := session.ListTools(ctx, nil)
	if err != nil {
		panic(err)
	}
	if len(tools.Tools) != 1 || tools.Tools[0].Name != "greet" {
		panic("unexpected tool listing")
	}
	result, err := session.CallTool(ctx, &mcp.CallToolParams{Name: "greet", Arguments: map[string]any{"name": "Go"}})
	if err != nil {
		panic(err)
	}
	text, ok := result.Content[0].(*mcp.TextContent)
	if !ok || text.Text != "Hello, Go" {
		panic("unexpected tool result")
	}
	fmt.Println("Official Go SDK: discovery, tool listing, and tool call passed (2026-07-28).")
}
