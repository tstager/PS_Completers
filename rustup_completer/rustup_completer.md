# rustup PowerShell completer

This standalone completer adds native PowerShell tab completion for `rustup` and `rustup.exe`.

## Approach

It uses a help-driven command model built from the installed `rustup --help` and subcommand `--help` output, with safe local discovery for:

- installed toolchains via `rustup toolchain list`
- targets via `rustup target list` and `rustup target list --installed`
- components via `rustup component list` and `rustup component list --installed`
- host triples inferred from installed toolchains and installed targets

Component and target lists follow the toolchain on the line: `--toolchain <name>`, `--toolchain=<name>`, or a leading `+<name>` adds `--toolchain <name>` to the list call, so `rustup +1.95.0 component remove <Tab>` offers what is installed on 1.95.0. Only an installed toolchain (exact name, or a short name like `stable` or `1.95.0` whose host-qualified form is installed) scopes the list; any other name keeps the default toolchain's list, so completion never queries or installs a missing toolchain. Each list is cached per toolchain for the session.

The script caches parsed help and discovery results in script scope on first use. Nothing is executed at import time besides the literal `Register-ArgumentCompleter -Native` call, which keeps it safe for `Import-CompleterScript`-style loading.

## Covered completion surfaces

- root commands and root switches
- nested commands such as `toolchain`, `target`, `component`, `override`, `self`, `set`, `show`, and `completions`
- toolchain-valued commands such as `install`, `update`, `default`, `override set`, and `run`
- target and component values for add/remove flows
- known enum-like values such as profiles, shells, auto-update modes, and auto-install modes
- `--path` path completion for override commands
- `toolchain link` path completion for the linked directory
- placeholders for non-path free-form slots like `run <command>`, `doc [TOPIC]`, and custom toolchain names

## Notes

- The completer prefers authoritative local help over hardcoded switch tables.
- It intentionally avoids destructive actions and only uses read-only `rustup` commands during completion.
- Some operand slots remain placeholder-based because live discovery would either be noisy or require guessing user intent.
