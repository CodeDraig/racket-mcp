package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type recordingTransport struct {
	base  http.RoundTripper
	mu    sync.Mutex
	types map[string]string
}

func (r *recordingTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	res, err := r.base.RoundTrip(req)
	if err == nil {
		r.mu.Lock()
		r.types[req.Header.Get("Mcp-Name")] = res.Header.Get("Content-Type")
		r.mu.Unlock()
	}
	return res, err
}
func checkHTTPAdaptive(ctx context.Context, path string) {
	command := exec.CommandContext(ctx, "racket", path)
	command.Stderr = os.Stderr
	out, err := command.StdoutPipe()
	if err != nil {
		panic(err)
	}
	if err := command.Start(); err != nil {
		panic(err)
	}
	defer func() { _ = command.Process.Kill(); _ = command.Wait() }()
	url, err := bufio.NewReader(out).ReadString('\n')
	if err != nil {
		panic(err)
	}
	transport := &recordingTransport{base: http.DefaultTransport, types: make(map[string]string)}
	client := mcp.NewClient(&mcp.Implementation{Name: "adaptive-interop", Version: "1"}, nil)
	session, err := client.Connect(ctx, &mcp.StreamableClientTransport{
		Endpoint: strings.TrimSpace(url), HTTPClient: &http.Client{Transport: transport},
	}, &mcp.ClientSessionOptions{ProtocolVersion: "2026-07-28"})
	if err != nil {
		panic(err)
	}
	defer session.Close()
	call := func(ctx context.Context, name string) string {
		result, err := session.CallTool(ctx, &mcp.CallToolParams{Name: name})
		if err != nil {
			panic(err)
		}
		if len(result.Content) != 1 {
			panic("unexpected content count")
		}
		text, ok := result.Content[0].(*mcp.TextContent)
		if !ok {
			panic("unexpected content kind")
		}
		return text.Text
	}
	for _, name := range []string{"fast", "slow"} {
		if call(ctx, name) != name {
			panic("unexpected result")
		}
	}
	transport.mu.Lock()
	fast, slow := transport.types["fast"], transport.types["slow"]
	transport.mu.Unlock()
	if !strings.HasPrefix(fast, "application/json") || !strings.HasPrefix(slow, "text/event-stream") {
		panic(fmt.Sprintf("unexpected response types: fast=%q slow=%q", fast, slow))
	}
	if call(ctx, "invocations") != "1" {
		panic("handler was replayed")
	}
	requestCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	finished := make(chan error, 1)
	go func() { _, err := session.CallTool(requestCtx, &mcp.CallToolParams{Name: "wait"}); finished <- err }()
	await := func(expected string) {
		waitCtx, stop := context.WithTimeout(ctx, 3*time.Second)
		defer stop()
		for {
			if call(waitCtx, "worker-status") == expected {
				return
			}
			select {
			case <-time.After(20 * time.Millisecond):
			case <-waitCtx.Done():
				panic("worker state deadline exceeded")
			}
		}
	}
	await("running")
	cancel()
	select {
	case err := <-finished:
		if !errors.Is(err, context.Canceled) {
			panic(fmt.Sprintf("expected cancellation: %v", err))
		}
	case <-ctx.Done():
		panic("cancelled call did not finish")
	}
	await("stopped")
	if call(ctx, "fast") != "fast" {
		panic("server did not remain usable")
	}
	fmt.Println("Official Go SDK: HTTP JSON-to-SSE selection, single execution, cancellation, worker cleanup, and continued requests passed.")
}
