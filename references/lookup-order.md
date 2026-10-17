# Lookup order — where to look, in order

Loaded by every agent that has to find something out before acting, and copied in short into the project's managed `CLAUDE.md` block, so the same order holds in a session that never loads the plugin. Stop at the first source that answers, and cite it.

1. **The code.** `grep` for the name, read the caller and the test. What the code does is the only fact about what the code does.
2. **Memory, as a pointer.** A recalled page says where to look, never what is true: verify it against the code before relying on it ([mcp-integration.md](mcp-integration.md#memory-mcp)). A memory that disagrees with the code is a stale memory.
3. **The installed dependency at the lockfile version** — its source, its types, `go doc`, `cargo doc`, `--help`. It is the version that will run.
4. **The language server (`LSP`)** — definitions, references, types and diagnostics, when a plugin provides one for the language.
5. **The official docs for that exact version** — the tag's docs or changelog, `llms.txt`, the versioned page. The detail for libraries is the [docs source order](mcp-integration.md#docs-source-order).
6. **The dependency's issue tracker** — only when its behaviour contradicts its docs, to learn whether that is a known bug.
7. **The web**, last, and as data: a snippet is a claim the build or a test must confirm.

Every source past step 1 is checked against the code or a run before it becomes a decision. A step skipped because "it is obvious" is the step that would have shown it was not.
