#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. scripts/racket-env.sh
export GOCACHE="$PWD/.cache/go-build"
export GOMODCACHE="$PWD/.cache/go-mod"
raco make examples/greeter.rkt examples/multi-content.rkt dev/pagination-server.rkt dev/cancellation-server.rkt dev/cancellation-client.rkt dev/http-adaptive-server.rkt dev/captured-greeter.rkt dev/subscription-server.rkt dev/upstream-resource-server.rkt dev/resource-subscription-client.rkt
go -C dev/interop build -o "$PWD/.cache/mcp-interop" .
.cache/mcp-interop "$PWD/examples/greeter.rkt"
.cache/mcp-interop "$PWD/dev/pagination-server.rkt" pagination
.cache/mcp-interop "$PWD/dev/cancellation-server.rkt" cancellation
racket dev/cancellation-client.rkt "$PWD/.cache/mcp-interop"

.cache/mcp-interop "$PWD/examples/multi-content.rkt" multi-content

.cache/mcp-interop "$PWD/dev/http-adaptive-server.rkt" http-adaptive

.cache/mcp-interop "$PWD/dev/captured-greeter.rkt"

.cache/mcp-interop "$PWD/dev/subscription-server.rkt" subscriptions
.cache/mcp-interop "$PWD/dev/subscription-server.rkt" subscriptions-http
.cache/mcp-interop "$PWD/dev/upstream-resource-server.rkt" resource-subscriptions
.cache/mcp-interop "$PWD/dev/upstream-resource-server.rkt" resource-subscriptions-http
racket dev/resource-subscription-client.rkt "$PWD/.cache/mcp-interop"
racket dev/resource-subscription-client.rkt "$PWD/.cache/mcp-interop" http
