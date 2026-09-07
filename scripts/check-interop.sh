#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. scripts/racket-env.sh
export GOCACHE="$PWD/.cache/go-build"
export GOMODCACHE="$PWD/.cache/go-mod"
raco make examples/greeter.rkt examples/multi-content.rkt dev/pagination-server.rkt dev/cancellation-server.rkt dev/cancellation-client.rkt
go -C dev/interop build -o "$PWD/.cache/mcp-interop" .
.cache/mcp-interop "$PWD/examples/greeter.rkt"
.cache/mcp-interop "$PWD/dev/pagination-server.rkt" pagination
.cache/mcp-interop "$PWD/dev/cancellation-server.rkt" cancellation
racket dev/cancellation-client.rkt "$PWD/.cache/mcp-interop"

.cache/mcp-interop "$PWD/examples/multi-content.rkt" multi-content
