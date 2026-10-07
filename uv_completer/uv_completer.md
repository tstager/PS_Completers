# uv completer

## What it completes / overview

`uv_completer.ps1` registers a native PowerShell argument completer for `uv`, `uv.exe`, `uvx`, and `uvx.exe`.

The implementation is a hybrid completer:

- it keeps a small static command tree for known high-level subcommands,
- it resolves the installed executable with `Get-Command`,
- it calls the real `uv`/`uvx` help output,
- and it caches parsed command, option, and option-value data in script scope.

This makes the completer track the installed CLI more closely than a purely hard-coded list while still providing repository-specific fallbacks for important command paths.

## Registration and command names

The script registers one native completer for all of the following command names:

- `uv`
- `uv.exe`
- `uvx`
- `uvx.exe`

Registration is done with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'uv', 'uv.exe', 'uvx', 'uvx.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Uv -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Internally, the completer distinguishes between `uv` and `uvx` with `Get-UvSourceName`.

## How completion works

### 1. Script-scoped caching

The script initializes `$script:UvCompletionCache` once and reuses it across completion requests. The cache stores:

- resolved executable paths for `uv` and `uvx`,
- per-command-path parsed help data,
- a static command tree that serves as the fallback when `uv` is not installed,
- the `uv tool dir` / `uv python dir` answers (once per binary and env override),
- the installed interpreter versions (five-minute TTL),
- parsed `pyproject.toml` files (re-read when the file's write time or size changes).

### 2. Executable discovery

`Get-UvExecutablePath` probes for the executable once per source name:

- `uv.exe` / `uv`
- `uvx.exe` / `uvx`

If the executable cannot be found, completion falls back to the static command tree.

### 3. Command-path detection

`Get-UvCommandContext` walks the already-typed tokens and builds the active command path by matching tokens against the currently known subcommands for that path.

Important details:

- tokens that start with `-` are treated as options and skipped for path building; a value-bearing option (one whose help line shows a `<METAVAR>`) also consumes the following token,
- a non-option token that is not a known subcommand switches the completer into operand mode: no further subcommands are offered, only options and positional values,
- at the root, an unknown token is probed once with `uv <token> --help` (safe because uv rejects unknown subcommands) so hidden commands such as `generate-shell-completion` still resolve,
- trailing whitespace is judged against the last element before the cursor, so editing mid-line keeps the command path (`uv pip | --no-cache`),
- `uv help ...` is treated specially through a help mode,
- `uvx` is given a synthetic root path of `tool run`, so its completion model is based on the `uv tool run` branch.

### 4. Help-driven parsing

For each command path, the completer can run:

```powershell
uv [path] --help
```

and parse the returned help text.

`Get-UvParsedHelpData` extracts:

- subcommands from `Commands:` sections,
- options from `Options:`-style sections,
- possible values from inline help such as `[possible values: ...]`,
- possible values from indented `Possible values:` lists,
- the metavariable of every option (`--cache-dir <CACHE_DIR>`), which decides whether the option is a switch, a path-typed option, or a free/enum value,
- the closed value set of the first positional in `Arguments:` (`uv generate-shell-completion <SHELL>`).

### 5. Result shaping

The completer then decides what to offer based on context:

- subcommands,
- options,
- values for the previous option when it takes one (switches such as `--frozen` fall through to the normal option/command list; path-typed options such as `--cache-dir` deliberately return nothing so PowerShell's filesystem completion applies; free values with no published set get a `<metavar>` placeholder),
- positional values such as the shell names for `uv generate-shell-completion`,
- values for `--option=value` assignments,
- help-topic subcommands when `uv help ...` is being completed,
- live operand and option values (see below).

### 6. Live values

These are read only inside the registered script block, never at load:

| Slot | Source |
| --- | --- |
| `uv tool run` / `uvx` (first operand), `uv tool upgrade`, `uv tool uninstall` | directories holding a `uv-receipt.toml` under `uv tool dir` |
| `--python` / `-p` (separate and `--python=` forms), `uv python pin` / `find` (first operand) | `uv python list --only-installed --offline --output-format json`; each minor request (`3.13`) is offered ahead of the exact versions |
| `uv python uninstall` | uv-managed installs under `uv python dir` (directory listing) |
| `--extra`, `--optional` | `[project.optional-dependencies]` of the nearest `pyproject.toml` |
| `--group`, `--no-group`, `--only-group` | `[dependency-groups]` (plus `dev` for `[tool.uv] dev-dependencies`) |
| `--package` | workspace members: the root that declares `[tool.uv.workspace]`, its `members` globs minus `exclude`, each member's `[project] name` |
| `uv remove` operands | dependency names from `[project] dependencies`, optional dependencies, dependency groups and `dev-dependencies` |
| `uv run` (first operand) | `[project.scripts]` / `[project.gui-scripts]` plus the `.exe` names in the project environment's `Scripts` folder (`.venv`, or `UV_PROJECT_ENVIRONMENT`) |

The nearest `pyproject.toml` is found by walking up from the current filesystem location, as uv does. The three processes (`uv tool dir`, `uv python dir`, `uv python list`) run under the same 5 s kill guard and ANSI strip as the help calls. Values that would need quoting in argument mode are dropped rather than emitted. When a slot's source is empty (no project, no tools) the completer falls back to its usual option list; when the source has values but none match the typed prefix it returns nothing, so PowerShell's filesystem completion applies (`uv run ma` still reaches `main.py`).

## Key completion behaviors / supported values

### Static root command tree

The script seeds completion with these top-level `uv` subcommands:

- `auth`
- `run`
- `init`
- `add`
- `remove`
- `version`
- `sync`
- `lock`
- `export`
- `tree`
- `format`
- `check`
- `audit`
- `tool`
- `python`
- `pip`
- `venv`
- `build`
- `publish`
- `workspace`
- `cache`
- `self`
- `help`

It also seeds several nested command paths:

- `auth` → `login`, `logout`, `token`, `dir`
- `tool` → `run`, `install`, `upgrade`, `list`, `audit`, `uninstall`, `update-shell`, `dir`
- `python` → `list`, `install`, `upgrade`, `find`, `pin`, `dir`, `uninstall`, `update-shell`
- `pip` → `compile`, `sync`, `install`, `uninstall`, `freeze`, `list`, `show`, `tree`, `check`
- `workspace` → `metadata`, `dir`, `list`
- `cache` → `clean`, `prune`, `dir`, `size`
- `self` → `update`, `version`

These static entries are merged with whatever the installed executable reports through `--help`.

### Option completion

When the current token starts with `-`, the completer returns option names for the active command path.

Those option lists primarily come from parsed help output, not from a large hard-coded table.

### Option value completion

The script supports both of these patterns:

```powershell
uv auth login --keyring-provider <TAB>
uv auth login --keyring-provider=<TAB>
```

Value suggestions are taken from parsed help only; there is no static value map, so the list can never disagree with the installed uv (for example `uv auth login --keyring-provider` offers exactly `disabled` and `subprocess` on 0.12.13).

### `uv help` support

If you type `uv help ...`, the completer switches into help-topic mode and offers subcommands for the current path instead of mixing in normal option completion.

### `uvx` behavior

`uvx` completion is modeled as if the command path starts at `uv tool run`.

The script also merges:

- `uvx --help`
- `uv tool run --help`

for that synthetic root, so `uvx` can reuse the `tool run` command surface.

## Dependencies or external command expectations

This completer expects one of the following to be available on `PATH`:

- `uv.exe` or `uv`
- `uvx.exe` or `uvx` for `uvx`-specific completion

Dynamic completion depends on the real CLI returning parseable `--help` text. If the executable is missing, no completions are produced.

## Usage / loading example

Dot-source the script in your PowerShell session or profile:

```powershell
. .\uv_completer.ps1
```

Example completion scenarios:

```powershell
uv <TAB>
uv tool <TAB>
uv auth login --keyring-provider <TAB>
uv auth login --keyring-provider=<TAB>
uv help python <TAB>
uvx <TAB>
```

## Limitations / notes

- Option values come from help output plus the live sources above; other free-form values get a `<metavar>` placeholder.
- `--project` / `--directory` are not honoured when locating `pyproject.toml`; the current location is used.
- The `pyproject.toml` reader is line-based and covers only the tables listed above (not their dotted-key or inline-table spellings).
- The help parser depends on the general shape of `uv --help` output. Major format changes in the CLI could reduce completion quality.
- `uvx` is intentionally mapped onto the `uv tool run` branch; this is a repository-specific design choice in the script.
- Blank completion falls back to option suggestions (typed as parameter names) when a command path exposes options but no further subcommands.

