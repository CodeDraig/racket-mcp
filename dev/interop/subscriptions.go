package main

import (
	"bufio"
	"context"
	"fmt"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"os"
	"os/exec"
	"strings"
	"time"
)

type subscriptionEvent struct {
	kind, id string
	accepted bool
}

func checkSubscriptions(ctx context.Context, path string, httpMode bool) {
	var endpoint string
	if httpMode {
		cmd := exec.CommandContext(ctx, "racket", path, "http")
		cmd.Stderr = os.Stderr
		out, err := cmd.StdoutPipe()
		if err != nil {
			panic(err)
		}
		if err := cmd.Start(); err != nil {
			panic(err)
		}
		defer func() { _ = cmd.Process.Kill(); _ = cmd.Wait() }()
		line, err := bufio.NewReader(out).ReadString('\n')
		if err != nil {
			panic(err)
		}
		endpoint = strings.TrimSpace(line)
	}
	// A second connection must establish its own listener after graceful closure.
	for round := 0; round < 2; round++ {
		events := make(chan subscriptionEvent, 16)
		client := mcp.NewClient(&mcp.Implementation{Name: "subscription-interop", Version: "1"}, &mcp.ClientOptions{
			ToolListChangedHandler: func(_ context.Context, req *mcp.ToolListChangedRequest) {
				events <- subscriptionEvent{kind: "change", id: fmt.Sprint(req.Params.Meta[mcp.MetaKeySubscriptionID])}
			},
		})
		client.AddReceivingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
			return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
				if method == "notifications/subscriptions/acknowledged" {
					ack, ok := req.(*mcp.ClientRequest[*mcp.SubscriptionsAcknowledgedParams])
					if !ok || ack.Params == nil {
						panic("invalid acknowledgement type")
					}
					events <- subscriptionEvent{kind: "ack", id: fmt.Sprint(ack.Params.Meta[mcp.MetaKeySubscriptionID]), accepted: ack.Params.Notifications.ToolsListChanged}
				}
				return next(ctx, method, req)
			}
		})
		var transport mcp.Transport
		if httpMode {
			transport = &mcp.StreamableClientTransport{Endpoint: endpoint}
		} else {
			cmd := exec.CommandContext(ctx, "racket", path)
			cmd.Stderr = os.Stderr
			transport = &mcp.CommandTransport{Command: cmd}
		}
		session, err := client.Connect(ctx, transport, &mcp.ClientSessionOptions{ProtocolVersion: "2026-07-28"})
		if err != nil {
			panic(err)
		}
		await := func() subscriptionEvent {
			select {
			case e := <-events:
				return e
			case <-time.After(3 * time.Second):
				panic("subscription event timed out")
			}
		}
		ack := await()
		if ack.kind != "ack" || !ack.accepted || ack.id == "<nil>" || ack.id == "" {
			panic(fmt.Sprintf("invalid first event: %+v", ack))
		}
		call := func(name, want string) {
			result, err := session.CallTool(ctx, &mcp.CallToolParams{Name: name})
			if err != nil {
				panic(err)
			}
			if len(result.Content) != 1 {
				panic("unexpected result content")
			}
			text, ok := result.Content[0].(*mcp.TextContent)
			if !ok || text.Text != want {
				panic("unexpected tool result")
			}
		}
		call("publish", "published")
		changed := await()
		if changed.kind != "change" || changed.id != ack.id {
			panic(fmt.Sprintf("unrelated change: %+v", changed))
		}
		call("close-listeners", "closed")
		call("echo", "alive")
		if err := session.Close(); err != nil {
			panic(err)
		}
	}
	fmt.Printf("Official Go SDK: subscription acknowledgement, accepted filter, tagged changes, graceful closure and fresh connection passed (HTTP=%v).\n", httpMode)
}
