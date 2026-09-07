#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. scripts/racket-env.sh
python3 scripts/extract-elicitation-schema.py --check
python3 scripts/extract-task-schema.py --check
raco make mcp/*.rkt examples/*.rkt tests/*.rkt dev/*.rkt
raco test tests
racket tests/schema-suite.rkt
raco scribble +m --htmls --dest .cache/manual mcp/scribblings/mcp.scrbl
