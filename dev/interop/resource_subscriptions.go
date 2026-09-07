package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func checkResourceSubscriptions(ctx context.Context, path string, httpMode bool) {
	type event struct{ kind, id, uri string }
	events := make(chan event, 16)
	client := mcp.NewClient(&mcp.Implementation{Name: "resource-subscription-interop", Version: "1"}, &mcp.ClientOptions{
		ResourceUpdatedHandler: func(_ context.Context, req *mcp.ResourceUpdatedNotificationRequest) {
			events <- event{"update", fmt.Sprint(req.Params.Meta[mcp.MetaKeySubscriptionID]), req.Params.URI}
		},
	})
	client.AddReceivingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
		return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
			if method == "notifications/subscriptions/acknowledged" {
				ack, ok := req.(*mcp.ClientRequest[*mcp.SubscriptionsAcknowledgedParams])
				if !ok || ack.Params == nil {
					panic("invalid acknowledgement")
				}
				uris := ack.Params.Notifications.ResourceSubscriptions
				if len(uris) != 1 {
					panic(fmt.Sprintf("unexpected accepted URIs: %v", uris))
				}
				events <- event{"ack", fmt.Sprint(ack.Params.Meta[mcp.MetaKeySubscriptionID]), uris[0]}
			}
			return next(ctx, method, req)
		}
	})
	cmd := exec.CommandContext(ctx, "racket", path)
	cmd.Stderr = os.Stderr
	var transport mcp.Transport
	if httpMode {
		cmd.Args = append(cmd.Args, "http")
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
		transport = &mcp.StreamableClientTransport{Endpoint: strings.TrimSpace(line)}
	} else {
		transport = &mcp.CommandTransport{Command: cmd}
	}
	session, err := client.Connect(ctx, transport, &mcp.ClientSessionOptions{ProtocolVersion: "2026-07-28"})
	if err != nil {
		panic(err)
	}
	defer session.Close()
	await := func() event {
		select {
		case e := <-events:
			return e
		case <-time.After(3 * time.Second):
			panic("resource subscription event timed out")
		}
	}
	read := func(want string) {
		result, err := session.ReadResource(ctx, &mcp.ReadResourceParams{URI: "local:///doc"})
		if err != nil {
			panic(err)
		}
		if len(result.Contents) != 1 || result.Contents[0].URI != "local:///doc" || result.Contents[0].Text != want {
			panic(fmt.Sprintf("unexpected resource result: %+v", result))
		}
	}
	read("0")
	previousID := ""
	for round := 1; round <= 2; round++ {
		if err := session.Subscribe(ctx, &mcp.SubscribeParams{URI: "local:///doc"}); err != nil {
			panic(err)
		}
		ack := await()
		if ack.kind != "ack" || ack.uri != "local:///doc" || ack.id == "" || ack.id == "<nil>" || ack.id == previousID {
			panic(fmt.Sprintf("invalid resource acknowledgement: %+v", ack))
		}
		previousID = ack.id
		result, err := session.CallTool(ctx, &mcp.CallToolParams{Name: "publish"})
		if err != nil {
			panic(err)
		}
		if len(result.Content) != 1 {
			panic("unexpected publish result")
		}
		text, ok := result.Content[0].(*mcp.TextContent)
		if !ok || text.Text != fmt.Sprint(round) {
			panic("unexpected publish value")
		}
		changed := await()
		if changed.kind != "update" || changed.id != ack.id || changed.uri != "local:///doc" {
			panic(fmt.Sprintf("incorrect forwarded update: %+v", changed))
		}
		read(fmt.Sprint(round))
		if err := session.Unsubscribe(ctx, &mcp.UnsubscribeParams{URI: "local:///doc"}); err != nil {
			panic(err)
		}
	}
	fmt.Printf("Official Go SDK: resource subscription acceptance, upstream forwarding, URI mapping, updated reads and re-subscription passed (HTTP=%v).\n", httpMode)
}
