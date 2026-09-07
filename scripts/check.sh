#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. scripts/racket-env.sh
raco make mcp/*.rkt examples/*.rkt tests/*.rkt dev/conformance-server.rkt dev/conformance-client.rkt
raco test tests
racket tests/schema-suite.rkt
raco scribble +m --htmls --dest .cache/manual mcp/scribblings/mcp.scrbl
