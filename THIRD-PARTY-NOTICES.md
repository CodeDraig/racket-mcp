# Third-party notices

Original racket-mcp code and documentation are licensed under the [MIT License](LICENSE).
That grant does not replace the licenses of third-party files, copied code fragments,
or generated extracts. Their authors retain their copyrights and applicable terms.
The `MIT` entry in `info.rkt` describes the original project work, not a relicensing
of everything in the source distribution.

## Bundled sources

[vendor/LOCK.json](vendor/LOCK.json) records each upstream repository, exact commit,
and the SHA-256 hashes of the selected files. The links below identify those
snapshots; directory names alone do not imply that their licenses are identical.
Existing upstream copyright and license notices are retained in the source files.

| Local material | Upstream snapshot | License and retained notice |
| --- | --- | --- |
| `vendor/protocol/` | [modelcontextprotocol/modelcontextprotocol, e76e9c5](https://github.com/modelcontextprotocol/modelcontextprotocol/tree/e76e9c572c6f2bfcb730357101acc90f2f802e02) | [Upstream license](vendor/protocol/LICENSE): Apache-2.0 for new code and specification contributions and contributions with relicensing consent; MIT for contributions whose authors have not consented. Non-specification documentation is CC-BY-4.0. These are contribution-specific terms, not a blanket choice between licenses. |
| `vendor/tasks/` | [modelcontextprotocol/ext-tasks, 9263312](https://github.com/modelcontextprotocol/ext-tasks/tree/9263312d11a682ac83f83fe84794d4627efd22f5) | [Apache-2.0](vendor/tasks/LICENSE). |
| `vendor/go-sdk/` | [modelcontextprotocol/go-sdk, a5026ea](https://github.com/modelcontextprotocol/go-sdk/tree/a5026ea7b727a59b166a06cf7ec4931a50cef427) | [Upstream license](vendor/go-sdk/LICENSE): the same contribution-specific Apache-2.0/MIT transition and CC-BY-4.0 documentation terms described above. |
| `vendor/conformance/` | [modelcontextprotocol/conformance, 7022d78](https://github.com/modelcontextprotocol/conformance/tree/7022d786071e6d868dcd5cf19a8c30db7d811537) | [Upstream license](vendor/conformance/LICENSE): the same contribution-specific Apache-2.0/MIT transition and CC-BY-4.0 documentation terms described above. |
| `vendor/json-schema/` | [json-schema-org/json-schema-spec, 4f56a99](https://github.com/json-schema-org/json-schema-spec/tree/4f56a9900674b27804f0ec32e3b7fdfa4efad695) | Copyright (c) 2022 JSON Schema Specification Authors. [BSD-3-Clause or AFL-3.0](vendor/json-schema/LICENSE), as stated in the [pinned upstream README](https://github.com/json-schema-org/json-schema-spec/blob/4f56a9900674b27804f0ec32e3b7fdfa4efad695/README.md#license). This distribution uses the BSD option and retains the complete upstream license file. |
| `vendor/metaschemas/` | [json-schema-org/json-schema-spec, 601a66c](https://github.com/json-schema-org/json-schema-spec/tree/601a66c8b0f25246bf0e1fb488c5b5f030a79b72) | The [pinned README](https://github.com/json-schema-org/json-schema-spec/blob/601a66c8b0f25246bf0e1fb488c5b5f030a79b72/README.md#license) offers AFL or BSD. This distribution uses the BSD option; [the retained JSON Schema license](vendor/json-schema/LICENSE) supplies the BSD copyright notice, conditions, and disclaimer. This older snapshot has no root LICENSE file. The XML specification sources also retain their original authorship and `trust200902` IETF publication metadata. |
| `vendor/json-schema-tests/` | [json-schema-org/JSON-Schema-Test-Suite, f6fd52a](https://github.com/json-schema-org/JSON-Schema-Test-Suite/tree/f6fd52a0a95472e079cbfc6ef7f089702b80e045) | Copyright (c) 2012 Julian Berman. [MIT](vendor/json-schema-tests/LICENSE). |
| `vendor/uri-template-tests/` | [uri-templates/uritemplate-test, 4171dac](https://github.com/uri-templates/uritemplate-test/tree/4171dac22aa67fc710b3f6df308a50bd08552986) | Copyright 2011- The Authors. [Upstream notice](vendor/uri-template-tests/LICENSE), Apache-2.0; the [full Apache license](vendor/tasks/LICENSE) is also included. |
| `vendor/syntax-spec-v3/`, except separately licensed subdirectories | [michaelballantyne/syntax-spec, 4ae3661](https://github.com/michaelballantyne/syntax-spec/tree/4ae36610804b58e8f023574bfdcba1b5ae4f7bcd) | [Apache-2.0 or MIT](vendor/syntax-spec-v3/LICENSE). This distribution uses the MIT option for these files; the [referenced Racket MIT text](LICENSES/Racket-MIT.txt) is included. Per-file authorship and copyright notices remain applicable. |
| `vendor/syntax-spec-v3/tests/dsls/tiny-hdl/` | Part of the syntax-spec snapshot above | [MPL-2.0](vendor/syntax-spec-v3/tests/dsls/tiny-hdl/LICENSE). This upstream example is included as source. Its files and modifications to them retain MPL terms; the project's MIT grant does not replace them. |

The full [CC-BY-4.0 text](LICENSES/CC-BY-4.0.txt) accompanies the upstream
documentation notices. Attribution is to the respective upstream projects and
contributors, with original source and revision links above. Upstream snapshots
are selected copies, not claims of authorship or endorsement by racket-mcp.

## Derived material and modifications

Third-party licensing also applies outside `vendor/`:

| Material | Provenance and changes |
| --- | --- |
| `mcp/private/elicitation-schema.json` | Extracted from `vendor/protocol/schema/2026-07-28/schema.json` by `scripts/extract-elicitation-schema.py`. It selects the elicitation definitions and their referenced definitions, changes the root wrapper, and adds a provenance comment. The extracted material retains the protocol snapshot's applicable licenses. |
| `mcp/private/task-schema.json` | Extracted from `vendor/tasks/schema/2026-07-28/schema.json` by `scripts/extract-task-schema.py`. It selects task result definitions and their referenced definitions and adds a provenance comment. The extracted material retains Apache-2.0. |
| `scripts/prepare-syntax-spec.py` and its prepared dependency | The script includes upstream source fragments and produces a separately patched syntax-spec copy. Changes address module temporary binding context, persistent identifier-table phases, reference-compiler defaults, and the local version. `MCP-PATCH.json` records the changed-source hashes. Upstream fragments and prepared sources retain their applicable licenses, including the tiny-hdl exception. |
| `scripts/prepare-conformance.py` and its prepared harness | The script includes an upstream registration-response fragment and produces a separate corrected fixture. It adds secret expiry, grant/response metadata, and authentication-method selection. Its manifest records the original pin and before/after hashes. The fragments and prepared harness retain the conformance snapshot's applicable licenses. |

Original orchestration and extraction code is MIT-licensed; copying or extracting
third-party content does not turn that content into original MIT-licensed work.
The preparation scripts preserve the checked-in vendor snapshots and retain
upstream notices in their prepared copies.

## Distribution boundaries

`scripts/package.py` includes the bundled source directories, this notice, the
project license, and `LICENSES/`. Retain applicable copyright notices, license
texts, and modification notices when redistributing those materials. If distributing
executables containing MPL-covered files, also provide the covered source and
the means of obtaining it as required by MPL-2.0.

Racket, externally installed Racket packages, and dependencies downloaded by Go or
npm have their own licenses. They are not licensed by this project's MIT grant.
The source packager excludes `node_modules` and compiled caches; a separately
built executable or dependency bundle needs notices for the components actually
included in that deliverable.
