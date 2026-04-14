# scoop completer

## What it completes / overview

`scoop_completer.ps1` registers a standalone native PowerShell completer for `scoop`, `scoop.ps1`, and `scoop.cmd`.

It uses a hybrid, static-first model:

- static command-family routing for Scoop's stable command surface
- cached local discovery for installed apps, buckets, aliases, shims, cache entries, and config keys
- local bucket-manifest name completion when the user has typed a prefix
- path-aware completion for import, manifest, and shim target paths
- placeholder-oriented suggestions for free-form query, URL, repo, command, and passthrough slots

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('scoop', 'scoop.ps1', 'scoop.cmd') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\scoop_completer\scoop_completer.ps1
```

## Import and runtime behavior

The top level stays compatible with `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter` call

All runtime probing is lazy and happens from helper functions during completion.

## How completion works

### Static command routing

The completer hard-codes Scoop's stable top-level commands and nested verb families such as:

- `alias add|rm|list`
- `bucket add|list|known|rm`
- `cache show|rm`
- `shim add|rm|list|info|alter`
- `config rm`

### Cached local value sources

When a slot benefits from real local state, the completer uses cached local-only discovery:

- `scoop list` for installed apps
- `scoop bucket list` and `scoop bucket known` for bucket names
- `scoop shim list` for shim names
- `scoop alias list` for alias names
- `scoop cache show` for cache entries
- the active Scoop root's `buckets\*\bucket\*.json` tree for locally available manifest names

### Enum and config value hints

The completer suggests documented enums such as:

- `--arch` -> `32bit`, `64bit`, `arm64`
- config booleans -> `$true`, `$false`
- `scoop_branch` -> `master`, `develop`
- `default_architecture` -> `64bit`, `32bit`, `arm64`
- `shim` -> `kiennq`, `scoopcs`, `71`

### Path and placeholder handling

Real path completion is used only when the current slot is path-bearing and the user is entering a path-like token, for example:

- `scoop import .\`
- `scoop install .\`
- `scoop shim add myshim .\`

Free-form slots intentionally use placeholders to suppress noisy filesystem fallback, for example:

- `scoop search `
- `scoop create `
- `scoop bucket add <name> `
- `scoop shim add myshim target.exe -- `

## Usage examples

```powershell
scoop
scoop install -
scoop install --arch=
scoop uninstall
scoop bucket add
scoop config default_architecture
scoop import .\
scoop shim add myshim .\
```

## Dependencies or external command expectations

- Expects Scoop to be installed and resolvable as `scoop`, `scoop.ps1`, or `scoop.cmd` for dynamic local discovery
- Falls back to placeholder-oriented suggestions when runtime discovery returns nothing
- Uses only local filesystem and local Scoop metadata sources

## Limitations / notes

- The completer does not call `scoop search` during completion, so remote or very broad app discovery is not attempted on every keypress.
- Local bucket manifest names are only offered after the user has started typing a prefix, to avoid dumping a very large list on empty input.
- Version suffixes like `app@version` are treated conservatively; the completer preserves the typed suffix but does not try to enumerate versions.
