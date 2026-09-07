package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"sync/atomic"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func serveResources(ctx context.Context, httpMode bool) {
	var version atomic.Int64
	server := mcp.NewServer(&mcp.Implementation{Name: "go-resource-peer", Version: "1"}, &mcp.ServerOptions{
		Capabilities: &mcp.ServerCapabilities{},
		SubscribeHandler: func(_ context.Context, req *mcp.SubscribeRequest) error {
			if req.Params.URI != "go:///doc" {
				return fmt.Errorf("unknown URI")
			}
			return nil
		},
		UnsubscribeHandler: func(context.Context, *mcp.UnsubscribeRequest) error { return nil },
	})
	server.AddResource(&mcp.Resource{Name: "document", URI: "go:///doc", MIMEType: "text/plain"},
		func(context.Context, *mcp.ReadResourceRequest) (*mcp.ReadResourceResult, error) {
			return &mcp.ReadResourceResult{Contents: []*mcp.ResourceContents{{
				URI: "go:///doc", MIMEType: "text/plain", Text: fmt.Sprint(version.Load()),
			}}}, nil
		})
	mcp.AddTool(server, &mcp.Tool{Name: "publish", Description: "Change the resource and notify subscribers."},
		func(ctx context.Context, _ *mcp.CallToolRequest, _ struct{}) (*mcp.CallToolResult, any, error) {
			value := version.Add(1)
			if err := server.ResourceUpdated(ctx, &mcp.ResourceUpdatedNotificationParams{URI: "go:///doc"}); err != nil {
				return nil, nil, err
			}
			return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: fmt.Sprint(value)}}}, nil, nil
		})
	if httpMode {
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			panic(err)
		}
		httpServer := &http.Server{Handler: mcp.NewStreamableHTTPHandler(
			func(*http.Request) *mcp.Server { return server }, &mcp.StreamableHTTPOptions{Stateless: true})}
		go func() { <-ctx.Done(); _ = httpServer.Close() }()
		fmt.Printf("http://%s/mcp\n", listener.Addr())
		if err := httpServer.Serve(listener); err != nil && err != http.ErrServerClosed {
			panic(err)
		}
		return
	}
	if err := server.Run(ctx, &mcp.StdioTransport{}); err != nil {
		panic(err)
	}
}
