
# DSC completer

## What it completes / overview

`DSC_completer.ps1` registers a native PowerShell argument completer for the `dsc` CLI (Microsoft Desired State Configuration v3).

The command and option tree is static and was re-derived from the `--help` pages of the installed `dsc 3.2.3`. Resource, adapter, extension and function names are read live from the installed `dsc` (see [Live names](#live-names)).

## Registration and command names

- Registers with: `Register-ArgumentCompleter -Native`
- Command name:
  - `dsc`

Top-level command coverage includes:

- `completer`
- `config`
- `extension`
- `function`
- `mcp`
- `resource`
- `schema`
- `help`

Nested command coverage includes:

- `config get|set|test|validate|export|resolve|help`
- `extension list|help`
- `function list|help`
- `resource list|get|set|test|delete|schema|export|help`
- `help completer|config|extension|function|resource|schema|help`

The `help` branches mirror much of the main command tree, so help subcommands also receive completions. `config validate|resolve` and the `--as-group`, `--as-assert`, `--as-include`, `--as-get` and `--as-config` flags are hidden in `dsc --help` but accepted, so they stay in the tree.

## How completion works

The script builds a semicolon-delimited command path from the bare words left of the cursor, starting at `dsc`. It walks past options rather than stopping at them, so an option typed before a subcommand keeps its context: `dsc -l debug config get -<Tab>` and `dsc config --as-group get -<Tab>` complete the `config get` options. If an option takes a value at that level, the walk also skips the next word. This holds for root `-l`/`-t`/`-p` and for `config -p`/`-f`/`-r`. It also holds for a bundle of short flags whose last letter takes a value, such as `-wr`, since clap reads it as `-w -r`.

That command path is matched in a `switch` statement and returns a static list of `CompletionResult` objects for the matching context. Final output is then prefix-filtered against `$wordToComplete` and sorted by `ListItemText`.

## Key completion behaviors / supported values

- Root completion suggests:
  - global switches: `-l/--trace-level`, `-t/--trace-format`, `-p/--progress-format`, `-i/--ignore-settings-file`, `-h/--help`, `-V/--version`
  - top-level `dsc` subcommands
- `config` completion exposes:
  - shared configuration switches
  - verbs such as `get`, `set`, `test`, `validate`, `export`, and `resolve`
  - `config set` offers `-w/--what-if` and its aliases `--dry-run` and `--noop`
- `resource` completion exposes:
  - verbs such as `list`, `get`, `set`, `test`, `delete`, `schema`, and `export`
  - operation-specific switches, including `-r/--resource` and `-v/--version` on every operation, `-o/--output-format` on `delete`, and `-w/--what-if` (with `--dry-run`/`--noop`) on `set` and `delete`
- `extension list`, `function list`, `mcp`, and `schema` have their own small static switch sets.
- Enum-valued options complete their documented `[possible values]` in both the separate and the `--opt=value` form: `--trace-level`, `--trace-format`, `--progress-format`, every `-o/--output-format` variant (per command), `schema --type`, and the `completer <SHELL>` positional.
- Path-valued options (`-f/--file`, `config -f/--parameters-file`, `config -r/--system-root`) return nothing in the separate-word form, so PowerShell's own path completion runs. The attached `--file=` form completes the path itself and keeps the prefix. The path is quoted as one literal argument (`--file='.\sp ace.txt'`) in the quote the user typed, single by default; a typed quoted word is read as PowerShell reads it (`'it''s`), and a typed directory such as `./` is kept exactly as typed.
- Free-text options (`-i/--input`, `config -p/--parameters`, `resource -v/--version`, `resource list -d/--description` and `-t/--tags`) offer nothing of their own.
- `help` command paths are also modeled, so `dsc help ...` receives guided subcommand completion.
- Tokens to the right of the cursor are ignored, so completing mid-line still resolves the correct command path.

## Live names

| Slot | Values | Source |
| --- | --- | --- |
| `resource <op> -r/--resource`, `resource list [RESOURCE_NAME]` | resource type names | manifests on disk |
| `resource list -a/--adapter` | adapter type names (`kind: adapter`) | manifests on disk |
| `extension list [EXTENSION_NAME]` | extension type names | manifests on disk |
| `function list [FUNCTION_NAME]` | built-in function names | `dsc function list --output-format json` |

- Manifests are read passively, without starting `dsc`. The script reads the same `*.dsc.resource.*`, `*.dsc.adaptedresource.*`, `*.dsc.extension.*` and `*.dsc.manifests.json` files that `dsc` discovers:
  - the folders in `DSC_RESOURCE_PATH` (or `PATH`) plus `dsc`'s own folder
  - the top-level folder of every installed Appx package, found through the `PackageRootFolder` values under `HKCU\...\AppModel\Repository\Packages`; this mirrors the Appx discover extension
  - the manifest paths cached by the PowerShell discover extension in `%LOCALAPPDATA%\dsc\PowerShellDiscoverCache.json`
- `dsc resource list` walks the same set but runs every adapter and discover extension. It took 43 s on the reference machine. The passive scan returned the identical 54 types in about 0.3 s cold. Warm Tabs take about 15 ms, and the result is cached for 5 minutes per `PATH`/`DSC_RESOURCE_PATH`.
- Function names are compiled into `dsc.exe`, so they come from one bounded `dsc function list` run per binary. stdin is closed and both streams are drained. The run has a 5 s timeout with kill, and its output goes through ANSI stripping. A missing tool or failed run is remembered until `PATH` changes. Cold cost is about 0.5 s; warm Tabs take about 15 ms.
- A quote the user opened (`-r 'Microsoft.DSC/G`) is kept on the completed name.
- When `dsc` is not on `PATH`, no live source runs and the slots return nothing.

## Dependencies or external command expectations

- The static tree needs nothing beyond the script.
- Live names need `dsc` on `PATH`. The script resolves it with a direct `PATH` probe, not `Get-Command`.

## Usage / loading example

```powershell
. .\DSC_completer.ps1
```

Example scenarios after loading:

```powershell
dsc <Tab>
dsc config <Tab>
dsc resource get --resource Microsoft.Windows/<Tab>
dsc -l debug resource list --adapter <Tab>
dsc function list con<Tab>
dsc config get --file <Tab>
```

## Limitations / notes

- The static tree can drift from the installed `dsc` CLI over time. Re-derive it from `dsc <sub> --help` on upgrade.
- Resources an adapter reports only at run time are not offered, because they need the adapter to execute. Examples are classic PowerShell DSC resources behind `Microsoft.Adapter/PowerShell` and WMI classes.
- Settings-file `resourcePath.directories` entries are not read. Only `DSC_RESOURCE_PATH`/`PATH` and `dsc`'s folder are scanned.
- YAML `*.dsc.manifests.yaml` lists are not parsed; YAML single-resource manifests are read through their top-level `type:` line.
