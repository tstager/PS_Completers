# cargo completer

## What it completes / overview

`cargo_completer.ps1` registers a standalone native PowerShell completer for:

- `cargo`
- `cargo.exe`

The implementation is **help-driven with safe local discovery**:

- root options come from `cargo --help`
- installed commands come from `cargo --list`
- command-specific switches come from `cargo <command> --help`
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

After a command is chosen, the completer lazily parses `cargo <command> --help` and caches the discovered switches in script scope. clap help lists both forms of every short/long pair and marks value-bearing options with a metavar, so only options that really take a value consume the following token; bare flags such as `--timings` do not.

### Value completion

The completer provides explicit value completion for representative non-path slots such as:

- `--color` -> `auto`, `always`, `never`
- `--message-format` -> documented Cargo message formats
- `--target` -> `rustc --print target-list`
- `-Z` -> `cargo -Z help`
- `new/init --vcs` -> `git`, `hg`, `pijul`, `fossil`, `none`

Attached forms complete too and keep their prefix: `--color=al` -> `--color=always`, `-Zbind` -> `-Zbindeps`, `-Ffa` -> `-Ffast`. A word such as `--features=x` or `-pfoo` earlier on the line is read as an option with its value, not as an operand.

### Project-aware values

When a `Cargo.toml` is underfoot (nearest one walking up from the current directory, or the one named by root `-C` or `--manifest-path`/`-m`), the completer reads the project from `cargo metadata --no-deps --format-version 1 --offline`:

- `--profile` -> `dev`, `release`, `test`, `bench` plus every `[profile.NAME]` in the workspace root manifest (built-ins only outside a project and for `install`)
- `-F`/`--features` -> features of the selected package (`-p`/`--package`, else the package of the nearest manifest, else every member of a virtual workspace), including the implicit features of optional dependencies; after a comma only the last segment is completed
- `-p`/`--package`/`--exclude` -> workspace member names
- `--bin`/`--example`/`--test`/`--bench` -> target names of that kind in the selected package, including auto-discovered ones
- `remove <DEP_ID>` -> the selected package's dependency names
- `update [SPEC]` -> package names in the workspace `Cargo.lock`

`uninstall` operands, `-p`/`--package` and `--bin` come from the install registry `.crates2.json` under `--root`, `CARGO_INSTALL_ROOT` or `CARGO_HOME` (default `~/.cargo`), read passively without starting cargo.

Without a manifest, or when `cargo metadata` fails, the static placeholders stay.

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
- `cargo <command> --help` is treated as authoritative. It is used in preference to `cargo help <command>`, whose manpage output omits the long form of every short/long option pair.
- Options are keyed and matched ordinally, so `-V` (`--version`) and `-v` (`--verbose`) stay distinct.
- Subcommands that `cargo --list` prints without a description, such as third-party `binstall` and `miri`, are recognized and get their own switch surface.
- After `--` the completer returns nothing, leaving the arguments of the program cargo runs to PowerShell's filesystem fallback.
- The implementation never probes package registries or remote sources during completion. `cargo metadata` runs with `--offline --no-deps` (it reads manifests and writes nothing), stdin closed, a 5 s timeout, and `RUSTUP_AUTO_INSTALL=0` so a `rust-toolchain.toml` that names a missing toolchain cannot trigger a download. Results are cached per manifest path and write time for 30 seconds; failures are cached too. Measured: about 450 ms for the first Tab in a project, about 50 ms after that.

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
