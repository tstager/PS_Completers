# go native argument completer for PowerShell

This standalone completer registers native tab completion for `go` and `go.exe`.

The surface is **discovered** from the installed toolchain rather than filtered
against a hardcoded whitelist. Every node of the command tree is read from the
`go help` page that describes it, so a command the completer has never heard of
still gets its real flags.

## Where the surface comes from

`go help [command [subcommand]]` prints the same shape everywhere, and the parser
reads all four parts of it:

- the `usage:` line, for the command's own bracketed flags (`[-o output]`,
  `[-exec xprog]`, `[-go=version]`), for whether the command accepts
  `[build flags]` or `[build/test flags]`, for its operands (`[packages]`,
  `[moddirs]`, `[var ...]`), and for literal alternations such as
  `go telemetry [off|local|on]`
- the indented flag definitions in the body (`\t-p n`, `\t-covermode set,count,atomic`,
  `  -c int`), which is where `go help build` documents the shared build-flag
  block and where `go help doc` and `go help vet` document their own
- the prose flag sentences go uses elsewhere (`The -n flag prints commands ...`)
- the `The commands are:` and `Additional help topics:` tables, for root
  commands, help topics and nested commands

`go help test` is read together with `go help testflag`, because that is where
`-run`, `-bench`, `-timeout`, `-fuzz` and the rest actually live.

## Coverage

- Root command completion, plus the `help` entry that `go help` does not list
  about itself.
- `go help` completion that unions root commands and Go help topics.
- Every command gets its own flags, including the ones that previously had none:
  `doc`, `fmt`, `generate`, `fix`, `version`, `vet`, and the command-specific
  flags of `clean`, `get`, `list` and `test` that the shared build-flag block
  does not contain.
- Second-level subcommands get their own flags too: `go mod tidy -`,
  `go work use -`, `go mod edit -`.
- Nested command completion for any command whose help lists subcommands
  (`go mod`, `go work`, ...), and literal choices for `go telemetry`.
- `-flag` and `--flag` are the same flag, as they are to go's own flag package,
  and a typed `--` keeps the `--` spelling on the way back.
- Enum-aware value completion for `-buildmode`, `-mod`, `-covermode`,
  `-buildvcs` and `-compiler`.
- Path-aware value completion for root `-C`, `-o`, `-exec`, `-modfile`,
  `-overlay`, `-pgo`, `-pkgdir`, `-outputdir`, `-coverprofile`, `-vettool` and
  `-fixtool`.
- Operand completion: the reserved package patterns from `go help packages`
  (`./...`, `.`, `all`, `std`, `cmd`, `tool`) alongside the directory tree,
  module version queries after an `@` (`example.com/x@latest`, `@upgrade`,
  `@patch`, `@none`), and Go environment variable names for `go env`.
- `go env` flag completion plus repeated `-w` / `-u` value-mode handling, with
  the variable names read from the installed `go env` output.
- `go tool` tool-name completion using lazy local discovery, with a conservative
  fallback list.
- `go test -args` passthrough detection so the completer stops interpreting the
  remainder of the command line.

## Runtime notes

- The script is import-safe at top level: it contains only `Set-StrictMode`, function definitions, and one literal `Register-ArgumentCompleter -Native` call.
- Executable discovery is lazy. It first tries `Get-Command` for `go` / `go.exe`, then falls back to `C:\Program Files\Go\bin\go.exe`.
- Command reconstruction uses `CommandAst.Extent.Text` with `$cursorPosition`
  rebased by `$commandAst.Extent.StartOffset`; it does not rely on
  `CommandAst.ToString()`.
- The tokenizer is quote-aware and lets an unterminated quote run to the end of
  the input, which is what happens while a quoted path containing a space is
  still being typed. A regex that only matched balanced quotes split
  `go -C "C:\Program Fi` into two tokens and completed the wrong slot.
- Path completions strip the quoting `CompleteFilename` applies before applying
  the quoting style the user actually typed, so a directory with a space comes
  back quoted once, not twice.
- Every `go` invocation runs with standard input closed.
- Parsed help is cached per command path for the session, and the whole cache is
  dropped when the working directory changes, because go's output is
  module-scoped.
- Inline `-flag=value` forms are handled explicitly, including enum-bearing and path-bearing flags, and keep the flag prefix on the inserted text.

## Representative validation

Clean `pwsh -NoProfile` `TabExpansion2` runs against go1.27.0:

- `go doc -`, `go fmt -`, `go version -`, `go generate -`, `go fix -`,
  `go vet -`: 0 results each -> 8, 3, 3, 34, 35 and 36
- `go mod tidy -` 0 -> 6; `go work use -` 0 -> `-r`
- `go clean -` 31 -> 38 (`-i -r -cache -testcache -modcache -fuzzcache`)
- `go list -` 31 -> 44 (`-f -m -deps -e -export -find -test -u -versions ...`)
- `go test -` 50 -> 64 (`-fuzz -shuffle -cpuprofile -memprofile -trace ...`)
- `go get -` 31 -> 35 (`-t -u -tool`)
- `go build --buildmode=p` -> `--buildmode=pie`, `--buildmode=plugin`
- `go --` 0 -> `--C`
- `go run -exec ` 31 flag names -> path completion
- `go install example.com/x@` 0 -> the four version queries
- `go env GO` 1 -> 36 environment variable names
- `go env ` 4 -> 51 (the flags plus the variable names)
- `go build ` 32 -> 218 (package patterns and the tree as well as the flags)
- `go -C "C:\Program Fi` -> `"C:\Program Files"`, `"C:\Program Files (x86)"`
- `go `, `go help `, `go mod `, `go work `, `go tool `, `go telemetry ` and
  `go build -buildmode ` unchanged
- `$x = 1; go bui` identical to the same input at the start of a line
- `$Error` did not grow across the probe set

## Deliberate limits

- No package, module, or symbol discovery over the network; operand completion
  stays on the reserved patterns and the local tree.
- Comma-separated inline value lists (`-tags=dev,`) are not split.
- `go tool` completion is local-only and does not perform any networked or state-changing discovery.
