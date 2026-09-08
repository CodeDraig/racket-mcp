# Native schema regex compatibility, 2026-09-07

The new optional runner executes the pinned `ecmascript-regex.json` and
`non-bmp-regex.json` files: 86 cases, counted separately from the 1,301 core cases.
The initial run passed 64 and failed or rejected 22: control/tab escapes,
Unicode whitespace and its complement, and the `digit` property alias.

The native frontend now tokenizes escapes and character classes, translates
control/hex/Unicode escapes and supported property aliases, preserves escaped
literal text, and uses ECMAScript line/whitespace behavior. Character-class unions
and negation are emitted explicitly. Invalid escapes, Racket-only group forms,
backreferences and malformed brace syntax do not silently use native meanings.
Supported category properties work inside classes. Unsupported named groups,
script/binary properties, non-scalar escapes and some lookbehind forms remain
outside this compatibility profile; this is not full ECMAScript conformance.

The first passing optional run was insufficient. An exhaustive Unicode scan
found that generated complement intervals excluded U+FF40. Standalone probes
reproduced a native range defect on Linux Racket 9.2 and 9.3: `[U+FF00-U+FFFF]`
incorrectly rejects U+FF40. Negation now uses a negative lookahead and native
any-character matching. Positive intervals are split at UTF-8 suffix boundaries
and individually wrapped atomically; without those wrappers, Racket merges them
back into the defective wide interval. Each interval consumes one character, so
protecting it introduces no loss of useful internal backtracking.

The first full run was deliberately terminated after discovering that defect;
`interrupted-full.log` is not a passing result. The initial split-range attempt
also failed, and its log is retained. A second full run was stopped after a
probe found that quantified empty classes had lost their consuming width. The
empty-set expression now preserves that width; regressions cover `*`, `+`, `?`
and `{0}`. Neither stopped run is a passing result. The final focused selection passed 172
checks on both Racket versions, including whitespace/complement agreement across
all 1,112,064 Unicode scalar values and interval boundary regressions. The final
focused run also passed all 86 optional and all 1,301 core schema cases.

The next completed full run found one failure among 5,301 native checks:
a schema `$id` containing a fragment was incorrectly accepted. A translated
negated class placed its assertion outside the following quantifier, checking
only the first character. Complement expressions now remain a single grouped
atom. Added regressions cover repeated negation, dot and non-whitespace, plus
zero repetitions. The construction test now reports the failing schema value.
The corrected focused run passed 225 native checks, all 86 optional cases and
all 1,301 core cases on Racket 9.3. `ungrouped-complement-full.log` retains the
failed full run; it is not a pass.

Both `scripts/check.sh` and `scripts/ci.py` now run the optional suite. All 14 Go
probes and installed package dependency checks passed on Racket 9.3. The installed package also passed 225 focused checks and all 86 optional cases.
The corrected full run passed 5,323 native checks, 1,301 core schema cases,
86 optional regex cases and the Scribble build on Linux/Racket 9.3. Its complete
log is `full.log`. These results do not imply a fresh full Racket 9.2 run. Saved logs
have trailing whitespace trimmed. This does not close the SDK release gates.

The rule reference is the [ECMAScript patterns specification](https://tc39.es/ecma262/multipage/text-processing.html#sec-patterns),
particularly control escapes, WhiteSpace/LineTerminator, and Unicode property
aliases. The test inputs retain their existing upstream pins; compilation does
not fetch any network resources. Native macOS/Windows remain unverified.
