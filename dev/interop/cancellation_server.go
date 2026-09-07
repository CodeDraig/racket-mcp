package main

import (
	"context"
	"sync/atomic"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func serveCancellation(ctx context.Context) {
	var active atomic.Bool
	var started atomic.Bool
	server := mcp.NewServer(&mcp.Implementation{Name: "go-cancellation-peer", Version: "1"}, nil)
	mcp.AddTool(server, &mcp.Tool{Name: "wait", Description: "Report progress, then wait for cancellation."},
		func(ctx context.Context, req *mcp.CallToolRequest, _ struct{}) (*mcp.CallToolResult, any, error) {
			active.Store(true)
			started.Store(true)
			defer active.Store(false)
			for _, value := range []float64{0, 0.5, 1} {
				if err := req.Session.NotifyProgress(ctx, &mcp.ProgressNotificationParams{
					ProgressToken: req.Params.GetProgressToken(), Progress: value, Total: 1,
				}); err != nil {
					return nil, nil, err
				}
			}
			<-ctx.Done()
			return nil, nil, ctx.Err()
		})
	mcp.AddTool(server, &mcp.Tool{Name: "worker-status", Description: "Inspect whether the cancelled handler stopped."},
		func(context.Context, *mcp.CallToolRequest, struct{}) (*mcp.CallToolResult, any, error) {
			status := "not-started"
			if started.Load() {
				status = "stopped"
				if active.Load() {
					status = "running"
				}
			}
			return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: status}}}, nil, nil
		})
	if err := server.Run(ctx, &mcp.StdioTransport{}); err != nil {
		panic(err)
	}
}
