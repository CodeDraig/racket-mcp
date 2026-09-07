package main

import (
    "context"
    "fmt"
    "github.com/modelcontextprotocol/go-sdk/mcp"
)

func checkPagination(ctx context.Context, session *mcp.ClientSession) {
    cursor := ""
    total := 0
    for page := 0; page < 3; page++ {
        result, err := session.ListTools(ctx, &mcp.ListToolsParams{Cursor: cursor})
        if err != nil { panic(err) }
        expected := 2
        if page == 2 { expected = 1 }
        if len(result.Tools) != expected { panic("unexpected page size") }
        for _, tool := range result.Tools {
            if tool.Name != fmt.Sprintf("tool%d", total) { panic("unexpected tool ordering") }
            total++
        }
        if page < 2 && result.NextCursor == "" { panic("missing continuation cursor") }
        if page == 2 && result.NextCursor != "" { panic("unexpected continuation cursor") }
        cursor = result.NextCursor
    }
    fmt.Println("Official Go SDK: three pages, five ordered tools passed (2026-07-28).")
}
