# HTTP arbitrary raised-value cleanup

An application network security guard raising a symbol, false, or a base exn
terminated the HTTP request worker without settling its request handle. All
three cases reproduced; an ordinary exn:fail was the passing control. The test
disables deadlines, so a timeout cannot substitute for failure delivery.

The worker now catches non-break failures, retains exception identity and wraps
other values in exn:fail:http:transport with the original cause. The final five
cases also check repeated use of a progress token, synchronous false-failure
propagation and cleanup of a blocked child created by the network callback.

Focused compilation and 218 checks passed on Linux Racket 9.3. The strengthened
five ownership cases passed on 9.2 and 9.3. The broader 9.2 run hit stale compiled
CLI linkage after the HTTP export change. Rebuilding all public SDK modules
resolved that linkage error, and the same 218 checks then passed on 9.2. The
failed observation is retained separately from the passing rerun.

Installed package dependency checks and all 218 focused checks passed on 9.3.
All 14 official Go interoperability probes passed. Full 9.3 verification passed
compilation, 6,049 native checks, all 1,301 core schema cases, all 86 optional regex
cases and Scribble.

Reproduction commands, using the version-specific project environment:

```
raco make mcp/*.rkt tests/http-raised-values.rkt tests/http-lifecycle.rkt tests/http.rkt tests/http-streams.rkt tests/stdio-raised-values.rkt
raco test tests/http-raised-values.rkt tests/http-lifecycle.rkt tests/http.rkt tests/http-streams.rkt tests/stdio-raised-values.rkt
```

Trailing whitespace was trimmed from the installed setup log for Git checks.

Two consecutive `python3 scripts/package.py` runs produced identical source ZIP
hashes; `cmp` passed and SHA256SUMS records the digest. Native macOS/Windows and
remaining complete-release gates remain open.
