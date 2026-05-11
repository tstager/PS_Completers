# go native argument completer for PowerShell

This standalone completer registers native tab completion for `go` and `go.exe`.

## Coverage

- Root command completion from `go help`, with a safe fallback list for importer-safe runtime use.
- `go help` completion that unions root commands and Go help topics.
- Nested command completion for:
  - `go mod`
  - `go work`
  - `go telemetry`
- Shared build-family flag completion for `build`, `clean`, `get`, `install`, `list`, `run`, and `test`, while treating root `-C` as a dedicated first-flag root option.
- Enum-aware value completion for:
  - `-buildmode`
  - `-mod`
  - `-covermode`
  - `-buildvcs`
  - `-compiler`
- Path-aware value completion for:
  - root `-C`
  - `-o`
  - `-modfile`
  - `-overlay`
  - `-pgo`
  - `-pkgdir`
- `go env` flag completion plus repeated `-w` / `-u` value-mode handling.
- `go tool` tool-name completion using lazy local discovery, with a conservative fallback list.
- `go test -args` passthrough detection so the completer stops interpreting the remainder of the command line.

## Runtime notes

- The script is import-safe at top level: it contains only `Set-StrictMode`, function definitions, and one literal `Register-ArgumentCompleter -Native` call.
- Executable discovery is lazy. It first tries `Get-Command` for `go` / `go.exe`, then falls back to `C:\Program Files\Go\bin\go.exe`.
- Command reconstruction uses `CommandAst.Extent.Text` plus `cursorPosition`; it does not rely on `CommandAst.ToString()`.
- Inline `-flag=value` forms are handled explicitly, including enum-bearing and path-bearing flags.

## Deliberate v1 limits

- No package, module, or symbol discovery.
- Free-form slots use conservative placeholder completions instead of filesystem fallback where practical.
- `go tool` completion is local-only and does not perform any networked or state-changing discovery.
