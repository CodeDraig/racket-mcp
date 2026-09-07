package main

import (
	"context"
	"fmt"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func checkMultiContent(ctx context.Context, session *mcp.ClientSession) {
	read, err := session.ReadResource(ctx, &mcp.ReadResourceParams{URI: "docs:///pages"})
	if err != nil {
		panic(err)
	}
	if len(read.Contents) != 2 {
		panic("resource read lost content")
	}
	tool, err := session.CallTool(ctx, &mcp.CallToolParams{Name: "show-pages"})
	if err != nil {
		panic(err)
	}
	if len(tool.Content) != 2 {
		panic("tool embedding lost content")
	}
	prompt, err := session.GetPrompt(ctx, &mcp.GetPromptParams{Name: "read-pages"})
	if err != nil {
		panic(err)
	}
	if len(prompt.Messages) != 2 {
		panic("prompt embedding lost content")
	}
	for i, text := range []string{"First page", "Second page"} {
		if read.Contents[i].URI != "docs:///pages" || read.Contents[i].Text != text {
			panic("incorrect resource content")
		}
		embedded, ok := tool.Content[i].(*mcp.EmbeddedResource)
		if !ok || embedded.Resource.URI != "docs:///pages" || embedded.Resource.Text != text {
			panic("incorrect tool embedding")
		}
		embedded, ok = prompt.Messages[i].Content.(*mcp.EmbeddedResource)
		if !ok || prompt.Messages[i].Role != "user" || embedded.Resource.URI != "docs:///pages" || embedded.Resource.Text != text {
			panic("incorrect prompt embedding")
		}
	}
	fmt.Println("Official Go SDK: multi-content resource read, tool embedding, and prompt message lowering passed (2026-07-28).")
}
