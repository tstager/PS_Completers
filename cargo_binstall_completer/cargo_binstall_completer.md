# cargo-binstall completer

## What it completes / overview

`cargo_binstall_completer.ps1` registers a native PowerShell argument completer for `cargo-binstall` and `cargo-binstall.exe`.

The completer is help-driven for the root option surface: it lazily reads local `cargo-binstall.exe --help`, parses the published switches, and adds a small set of safe value completions for documented enumerations and path-bearing options.

## Command surface source

- Primary source: local `cargo-binstall.exe --help`
- Subcommand help: not used, because this executable exposes a root-only option surface in local help and `cargo-binstall.exe help` behaved like an install attempt rather than a safe help command in this environment
- Additional safe local discovery:
  - `rustc --print target-list` for `--targets` values when `rustc` is available

## Registration and command names

- Registers with: `Register-ArgumentCompleter -Native`
- Command names:
  - `cargo-binstall`
  - `cargo-binstall.exe`

The top level is `Import-CompleterScript`-safe:

- `Set-StrictMode`
- function declarations only
- one literal `Register-ArgumentCompleter -Native -CommandName @('cargo-binstall', 'cargo-binstall.exe')`

## How completion works

The script:

1. Resolves `cargo-binstall.exe` or `cargo-binstall` with `Get-Command`.
2. Runs `cargo-binstall.exe --help` lazily during completion.
3. Parses the option specifications published in the local help output.
4. Completes:
   - root switches from local help
   - documented path-valued switches with filesystem completion
   - documented enumerated values with explicit `ParameterValue` results
   - a placeholder positional operand for `crate[@version]`

## Key completion behaviors

- Switch completion:
  - All switches published by local `--help` are offered as `ParameterName` results.
- Path completion:
  - `--manifest-path`
  - `--bin-dir`
  - `--install-path`
  - `--root`
  - `--root-certificates`
  - `--settings`
- Enumerated value completion:
  - `--pkg-fmt`
  - `--strategies`
  - `--disable-strategies`
  - `--min-tls-version`
  - `--log-level`
- Safe local value discovery:
  - `--targets` uses `rustc --print target-list` when available and completes comma-separated target triples
- Placeholder-only slots:
  - free-form values such as `--version`, `--git`, `--registry`, `--github-token`, and the positional `crate[@version]` operand use placeholders instead of filesystem fallback

## Usage / loading example

```powershell
. .\cargo_binstall_completer.ps1
```

Example scenarios after loading:

```powershell
cargo-binstall -<Tab>
cargo-binstall --pkg-fmt <Tab>
cargo-binstall --manifest-path .\<Tab>
cargo-binstall.exe --targets x86_64-unknown-linux-gnu,<Tab>
```

## Limitations / notes

- The completer only targets the root command surface documented by local `cargo-binstall.exe --help`.
- It does not attempt network lookups, crate index discovery, or registry enumeration while completing.
- If `cargo-binstall` is not on `PATH`, the completer returns no results.
- If `rustc` is unavailable, `--targets` falls back to the documented placeholder style rather than live target discovery.
