#!/bin/sh
# Run from the repository root with PATH and package home selecting Racket.
set -eu
. scripts/racket-env.sh
python3 scripts/extract-elicitation-schema.py --check
python3 scripts/extract-task-schema.py --check
raco make mcp/*.rkt examples/*.rkt tests/*.rkt dev/*.rkt
raco test --jobs 4 tests
racket tests/schema-suite.rkt
racket tests/schema-regex-suite.rkt
raco scribble +m --htmls --dest ".cache/manual-final-$MCP_RELEASE_VERSION" mcp/scribblings/mcp.scrbl
