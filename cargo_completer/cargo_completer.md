# cargo completer

## What it completes / overview

`cargo_completer.ps1` registers a standalone native PowerShell completer for:

- `cargo`
- `cargo.exe`

The implementation is **help-driven with safe local discovery**:

- root options come from `cargo --help`
- installed commands come from `cargo --list`
- command-specific switches come from `cargo help <command>`
- `+toolchain` suggestions come from local `rustup toolchain list` when available
- `--target` values come from local `rustc --print target-list`
- `-Z` values come from local `cargo -Z help`

It stays conservative in free-form slots and uses placeholders instead of noisy filesystem fallback for non-path operands like:

- `cargo install <crate>`
- `cargo uninstall <crate>`
- `cargo search <query>`
- `cargo test <test-filter>`

## Registration and command names

The script uses one importer-safe native registration:

```powershell
Register-ArgumentCompleter -Native -CommandName @('cargo', 'cargo.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Cargo -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or external command calls.

## Completion behavior

### Root surface

At the root, the completer offers:

- global options from `cargo --help`
- installed commands and aliases from `cargo --list`
- `+toolchain` overrides from local rustup state

### Command-specific switches

After a command is chosen, the completer lazily parses `cargo help <command>` and caches the discovered switches in script scope.

### Value completion

The completer provides explicit value completion for representative non-path slots such as:

- `--color` -> `auto`, `always`, `never`
- `--message-format` -> documented Cargo message formats
- `--target` -> `rustc --print target-list`
- `-Z` -> `cargo -Z help`
- `new/init --vcs` -> `git`, `hg`, `pijul`, `fossil`, `none`

### Path completion

Local path completion is used only for path-bearing slots such as:

- root `-C`
- root and command `--config`
- `--manifest-path`
- `--target-dir`
- `--artifact-dir`
- `install --path`
- `install --root`
- positional paths for `cargo new` and `cargo init`

## Runtime notes

- `cargo --list` was used to include installed Cargo subcommands like `clippy`, `fmt`, and other locally available commands.
- `cargo help <command>` is treated as authoritative even though Cargo help surfaces are long-form manpage-style output.
- The implementation avoids probing package registries, workspaces, or remote sources during completion.

## Validation performed

Representative local validation in clean `pwsh -NoProfile` sessions:

- parser check for `cargo_completer\cargo_completer.ps1`
- clean dot-source load
- `TabExpansion2 'cargo -'`
- `TabExpansion2 'cargo '`
- `TabExpansion2 'cargo help '`
- `TabExpansion2 'cargo build --color '`
- `TabExpansion2 'cargo build --target '`
- `TabExpansion2 'cargo -Z '`
- `TabExpansion2 'cargo.exe -'`

A repo-local `CompleterActions` / `Import-CompleterScript` module was not present in this checkout during implementation, so importer validation could not be run here.
