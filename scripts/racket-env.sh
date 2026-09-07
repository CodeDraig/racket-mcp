#!/bin/sh
# Source this from the project root; all package writes stay in this workspace.
export PLTUSERHOME="$PWD/.racket"
export PLTCOLLECTS="$PWD:"
mkdir -p "$PWD/.cache/tmp"
export TMPDIR="$PWD/.cache/tmp"
