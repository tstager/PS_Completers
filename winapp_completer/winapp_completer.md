# winapp_completer

PowerShell argument completer for the **winapp CLI** (`winapp` / `winapp.exe`) —
Microsoft's tool for Windows app development (package identity, MSIX packaging,
`Package.appxmanifest` management, test certificates, Windows App SDK
projections, and UI Automation).

## Installation

Dot-source the script from your PowerShell profile:

```powershell
. 'C:\path\to\Completers\winapp_completer\winapp_completer.ps1'
```

Or load it for the current session only:

```powershell
. .\winapp_completer\winapp_completer.ps1
```

## Registration

The completer registers a **native** `Register-ArgumentCompleter` for both
invocation forms that winapp resolves to on Windows:

| Registered name | Rationale |
| --- | --- |
| `winapp`     | Bare command; resolves through the Windows app-execution alias (`%LOCALAPPDATA%\Microsoft\WindowsApps\winapp.exe`) |
| `winapp.exe` | Explicit executable name used by some launchers and shells |

Both names share the same completer scriptblock.

## Design: schema-driven, lazy, probe-once

Unlike static completers, this one derives its entire command surface from winapp
itself, so it stays correct as the (public-preview) CLI evolves:

- On the **first** completion request the completer invokes `winapp --cli-schema`
  once, parses the JSON command tree, and caches it in script scope for the rest
  of the session.
- Completion then walks the **live tree** generically: subcommands, options,
  aliases, value types, and positional arguments all come from the schema.
- The schema invocation is **probe-once**: it runs at most a single time per
  session. A failed or missing winapp is never retried.
- A small **static enum overlay** supplies the choice sets the schema does not
  carry (the schema reports enum option types but not their values).
- If winapp is missing or the schema cannot be parsed, completion is a **graceful
  no-op** — it returns no results and never throws. (PowerShell then falls back
  to its default filesystem completion, as it does for any native command without
  a completer.)

Because the surface is fetched live, no command tree is baked into the script and
there is no stale static fallback to maintain.

## Coverage

### Top-level commands

`cert` · `create-debug-identity` · `create-external-catalog` · `get-winapp-path`
· `init` · `manifest` · `package` (alias `pack`) · `restore` · `run` · `sign` ·
`store` · `tool` (alias `run-buildtool`) · `ui` · `unregister` · `update`

The command tree is exactly three levels deep. Only `cert`, `manifest`, and `ui`
are **containers** (they have subcommands and no own options); every other
top-level command is a **leaf** with its own options and/or positional arguments.

### Subcommand trees

| Container | Subcommands |
| --- | --- |
| `cert` | `generate` · `info` · `install` |
| `manifest` | `add-alias` · `generate` · `update-assets` |
| `ui` | `click` · `focus` · `get-focused` · `get-property` · `get-value` · `inspect` · `invoke` · `list-windows` · `screenshot` · `scroll` · `scroll-into-view` · `search` · `set-value` · `status` · `wait-for` |

### Global recursive options

These apply at **every** depth and are unioned into every option list. All are
switches (they never consume the next token):

| Option | Type | Aliases |
| --- | --- | --- |
| `--cli-schema` | switch | — |
| `--help`       | switch | `-?` · `-h` · `/?` · `/h` |
| `--version`    | switch | — |

### Options and aliases

Options are read generically from the schema for the current command node, so
both short and long aliases complete without any hand-maintained maps:

- Short aliases such as `-q` (`--quiet`), `-v` (`--verbose`), `-o` (`--output`),
  `-r` (`--recursive`), `-a` (`--app`), `-w` (`--window`), `-p` (`--property`),
  `-d` (`--depth`), `-i` (`--interactive`), `-t` (`--timeout`).
- Long aliases such as `--no-config` (`init --ignore-config`), `--no-prompt`
  (`init --use-defaults`), `--entrypoint` (`manifest generate --executable`), and
  `--exe` (`package`/`run --executable`).

Typing a single dash offers any matching alias (short or long); typing two
dashes offers the canonical long option names, with aliases noted in the
tooltip.

### Enum value choices (static overlay)

The schema reports enum option types but not their members, so the completer
layers a small static overlay (matched by a substring of the value type, which
also handles the `System.Nullable<...>` wrapper):

| Value type token | Choices | Options |
| --- | --- | --- |
| `IfExists` | `Error` · `Overwrite` · `Skip` | `cert generate --if-exists` · `create-external-catalog --if-exists` · `manifest generate --if-exists` |
| `SdkInstallMode` | `stable` · `preview` · `experimental` · `none` | `init --setup-sdks` · `update --setup-sdks` |
| `ManifestTemplates` | `Packaged` · `Sparse` | `manifest generate --template` |

### Value slot completion (by value type)

| Value type | Behaviour |
| --- | --- |
| Enum types (above) | Offers the known choices |
| `System.IO.FileInfo` | `CompleteFilename` (files **and** directories) |
| `System.IO.DirectoryInfo` / `DirectoryInfo[]` | Directory-only completion |
| `System.Int32` / `System.Nullable<System.Int64>` | `<n>` placeholder (suppresses filesystem fallback) |
| `System.String` / `System.String[]` | `<helpName>` or `<value>` placeholder |
| `System.Boolean` / `System.Void` | Switch — never consumes a value |

### Positional argument completion

Positional slots are resolved from the schema's `order` field and completed by
value type. Trailing array arguments repeat for additional slots.

| Command | Positional(s) |
| --- | --- |
| `cert info` / `cert install <cert-path>` | file |
| `create-debug-identity [entrypoint]` | file |
| `create-external-catalog <input-folder>` | `<input-folder>` placeholder (typed `String`, semicolon-separated list) |
| `init` / `restore [base-directory]` | directory |
| `manifest generate [directory]` | directory |
| `manifest update-assets <image-path>` | file |
| `package <input-folder...>` | directory (repeating — `DirectoryInfo[]` for MSIX bundles) |
| `run <input-folder> [app-args...]` | directory, then `<app-args>` |
| `sign <file-path> <cert-path>` | file, file |
| `ui <subcommand> [selector]` | `<selector>` placeholder |
| `ui set-value <selector> <value>` | `<selector>`, `<value>` placeholders |

When the word being completed is empty inside a leaf command, the completer
offers the positional placeholder **and** the full option list, so
`winapp run <Tab>` shows both the directory slot and the available flags.

## Inline `--flag=value` syntax

Value-taking options support the `--flag=value` inline form. For example,
`winapp init --setup-sdks=` followed by Tab offers `stable`, `preview`,
`experimental`, `none`. Switch options that are typed inline emit nothing (no
crash).

## Passthrough commands

`store` (Microsoft Store Developer CLI) and `tool` (Windows SDK build tools) pass
their remaining arguments through to the wrapped tool. `store` carries no options
of its own and `tool` carries only `--quiet`/`--verbose`; in both cases the
completer offers the global options on `--` and otherwise returns nothing
gracefully (no crash).

## Implementation style

- **Self-contained** single `.ps1` file; no external dependencies beyond winapp.
- **`Set-StrictMode -Version Latest`** throughout, with PSObject property guards
  on every schema access (container nodes lack `options`/`arguments`; leaves lack
  `subcommands`; `store` lacks all three).
- **Import-CompleterScript-safe**: the top level contains only the help block,
  `Set-StrictMode`, function definitions, and the single idempotent registration
  block. All schema fetch, parse, cache, and enum-overlay setup live inside lazy
  helper functions invoked from the completion function — there are no top-level
  assignments, loops, external calls, or helper invocations.
- **Idempotent** via a script-scoped `WinAppCompleterRegistered` guard; safe to
  dot-source multiple times.
- **Native convention detection** preserves compatibility with both the ReadLine
  `CompleteInput` path and the `TabExpansion2` path, so real runtime tab
  completion engages — not just direct scriptblock invocation.
- **Public-preview aware**: because the surface comes from the live schema, the
  completer self-updates as winapp changes; only the enum overlay and the
  registered command names are maintained by hand.

## Validation

```powershell
. .\winapp_completer\winapp_completer.ps1

# Top-level subcommands
(TabExpansion2 'winapp ' 7).CompletionMatches.CompletionText

# SdkInstallMode enum
(TabExpansion2 'winapp init --setup-sdks ' 25).CompletionMatches.CompletionText

# ui subcommands (15)
(TabExpansion2 'winapp ui ' 10).CompletionMatches.CompletionText

# cert / manifest containers
(TabExpansion2 'winapp cert ' 12).CompletionMatches.CompletionText
(TabExpansion2 'winapp manifest ' 16).CompletionMatches.CompletionText

# Enum slots
(TabExpansion2 'winapp cert generate --if-exists ' 33).CompletionMatches.CompletionText
(TabExpansion2 'winapp manifest generate --template ' 36).CompletionMatches.CompletionText

# Inline enum
(TabExpansion2 'winapp init --setup-sdks=pre' 27).CompletionMatches.CompletionText

# Option list (globals unioned with node-local)
(TabExpansion2 'winapp update --' 16).CompletionMatches.CompletionText

# Short aliases
(TabExpansion2 'winapp ui click -' 17).CompletionMatches.CompletionText

# File / directory value slots
(TabExpansion2 'winapp sign ' 12).CompletionMatches | Select-Object CompletionText, ResultType
(TabExpansion2 'winapp run ' 11).CompletionMatches  | Select-Object CompletionText, ResultType

# winapp.exe registration
(TabExpansion2 'winapp.exe ' 11).CompletionMatches.CompletionText
```
