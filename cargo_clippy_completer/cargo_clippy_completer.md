# cargo-clippy completer

## Overview

`cargo_clippy_completer.ps1` registers a standalone native PowerShell completer for:

- `cargo-clippy`
- `cargo-clippy.exe`

The implementation is help-driven and stays within the repo's importer-safe top-level shape:

- `cargo-clippy --help` supplies Clippy-specific switches
- `cargo check --help` supplies the Cargo option surface that `cargo clippy` inherits
- `cargo -Z help` supplies local unstable flag values for `-Z`
- `clippy-driver -W help` supplies lint and lint-group names
- `rustup target list --installed`, falling back to `rustc --print target-list`, supplies target triples
- the nearest `Cargo.toml`, found by walking up from the current directory, supplies profile, feature, package, and target names

Option tokens are keyed ordinally, so `-V` (`--version`) and `-v` (`--verbose`) stay distinct and `-F` keeps its `--features` meaning before `--`. A value slot with no known source echoes what has been typed rather than collapsing to nothing.

## Completion behavior

Before `--`, the completer offers:

- Clippy-specific options like `--no-deps`, `--fix`, and `--explain`
- inherited Cargo check options like `--package`, `--target`, `--profile`, `--manifest-path`, and `--message-format`
- the literal `--` argument barrier

After `--`, the completer switches to Clippy lint arguments:

- `-W`, `--warn`
- `-A`, `--allow`
- `-D`, `--deny`
- `-F`, `--forbid`

Representative value behavior:

- `--color` -> `auto`, `always`, `never`
- `--message-format` -> documented Cargo formats
- `-Z` -> locally discovered unstable Cargo flags
- `-m`, `--manifest-path`, `--target-dir` -> filesystem completion
- `--config` -> filesystem completion plus `<KEY=VALUE>`
- `--profile` -> the built-in profiles plus every `[profile.<name>]` in the manifest
- `--features`, `-F` -> `[features]` keys from the manifest
- `--package`, `-p`, `--exclude` -> package names from the manifest
- `--bin`, `--example`, `--test`, `--bench` -> the matching `[[bin]]`/`[[example]]`/`[[test]]`/`[[bench]]` names
- `--target` -> installed target triples
- `--explain` and the lint flags after `--` -> lint and lint-group names from `clippy-driver -W help`

## Import-CompleterScript safety

The script keeps the top level limited to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or external command calls.

## Validation targets

Validate in clean `pwsh -NoProfile` sessions with:

- parser check
- dot-source load
- `TabExpansion2 'cargo-clippy -'`
- `TabExpansion2 'cargo-clippy --color '`
- `TabExpansion2 'cargo-clippy --manifest-path .\'`
- `TabExpansion2 'cargo-clippy -- -'`
- `TabExpansion2 'cargo-clippy -- -W '`
- `TabExpansion2 'cargo-clippy.exe -'`
