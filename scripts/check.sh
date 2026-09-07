#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. scripts/racket-env.sh
python3 scripts/extract-elicitation-schema.py --check
python3 scripts/extract-task-schema.py --check
raco make mcp/*.rkt examples/*.rkt tests/*.rkt dev/conformance-server.rkt dev/conformance-tasks.rkt dev/conformance-upstream-tasks.rkt dev/conformance-client.rkt dev/cancellation-server.rkt dev/cancellation-client.rkt dev/pagination-server.rkt
raco test tests
racket tests/schema-suite.rkt
raco scribble +m --htmls --dest .cache/manual mcp/scribblings/mcp.scrbl
