package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func checkCancellation(ctx context.Context, session *mcp.ClientSession, progress <-chan *mcp.ProgressNotificationParams) {
	if _, err := session.ListTools(ctx, nil); err != nil {
		panic(err)
	}
	callCtx, cancelCall := context.WithCancel(ctx)
	defer cancelCall()
	finished := make(chan error, 1)
	go func() {
		_, err := session.CallTool(callCtx, &mcp.CallToolParams{
			Name: "wait", Meta: mcp.Meta{"progressToken": "cancel-probe"},
		})
		finished <- err
	}()
	for _, expected := range []float64{0, 0.5, 1} {
		select {
		case update := <-progress:
			if update.ProgressToken != "cancel-probe" || update.Progress != expected || update.Total != 1 {
				panic(fmt.Sprintf("unexpected progress: %+v", update))
			}
		case err := <-finished:
			panic(fmt.Sprintf("call ended before cancellation: %v", err))
		case <-ctx.Done():
			panic("timed out waiting for server progress")
		}
	}
	cancelCall()
	select {
	case err := <-finished:
		if !errors.Is(err, context.Canceled) {
			panic(fmt.Sprintf("expected context cancellation, got %v", err))
		}
	case <-ctx.Done():
		panic("call did not resolve after cancellation")
	}
	probeCtx, cancelProbe := context.WithTimeout(ctx, 3*time.Second)
	defer cancelProbe()
	tick := time.NewTicker(20 * time.Millisecond)
	defer tick.Stop()
	for {
		result, err := session.CallTool(probeCtx, &mcp.CallToolParams{Name: "worker-status"})
		if err != nil {
			panic(err)
		}
		if len(result.Content) != 1 {
			panic("unexpected worker-status result")
		}
		text, ok := result.Content[0].(*mcp.TextContent)
		if !ok {
			panic("worker-status did not return text")
		}
		if text.Text == "stopped" {
			break
		}
		if text.Text != "running" {
			panic(fmt.Sprintf("unexpected worker status: %q", text.Text))
		}
		select {
		case <-tick.C:
		case <-probeCtx.Done():
			panic("cancelled worker did not stop")
		}
	}
	listed, err := session.ListTools(ctx, nil)
	if err != nil {
		panic(err)
	}
	if len(listed.Tools) != 2 {
		panic("unexpected tool listing after cancellation")
	}
	fmt.Println("Official Go SDK: ordered progress, context cancellation, server worker cleanup, and same-connection tool listing passed (2026-07-28).")
}
