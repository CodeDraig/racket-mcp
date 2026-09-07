#!/bin/sh
# Source from the project root; optionally select another project-local package home.
export PLTUSERHOME="${MCP_RACKET_USER_HOME:-$PWD/.racket}"
export PLTCOLLECTS="$PWD:"
mkdir -p "$PWD/.cache/tmp"
export TMPDIR="$PWD/.cache/tmp"
