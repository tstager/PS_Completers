# grep completer

## What it completes / overview

`grep_completer.ps1` registers a standalone native PowerShell completer for `grep` and `grep.exe`.

It is a help-driven completer that:

- parses the local `grep --help` surface once per session and caches the result
- suggests both short and long options discovered from the installed build
- supports inline `--option=value` completion and attached short value forms such as `-m5` and `-A3`
- provides enum value hints for `--color`, `--binary-files`, `-d` / `--directories`, and `-D` / `--devices`
- provides numeric context hints for `-m` / `--max-count`, `-A` / `--after-context`, `-B` / `--before-context`, and `-C` / `--context`
- completes real filesystem paths for `-f` / `--file` (including the stdin `-` sentinel) and `--exclude-from`
- returns placeholder-only suggestions for free-form slots: `-e` / `--regexp`, `--include`, `--exclude`, `--exclude-dir`, `--label`, and `--group-separator`
- routes operands as PATTERN-then-FILE: the first bare operand is the pattern, later operands are files to search

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'grep', 'grep.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\grep_completer\grep_completer.ps1
```

The script also enables:

```powershell
Set-StrictMode -Version 2.0
```

## Import and runtime behavior

The completer keeps its top level import-safe for `Import-CompleterScript` by limiting it to:

- `Set-StrictMode -Version 2.0`
- function definitions
- one literal native `Register-ArgumentCompleter` call

All help capture, parsing, and command resolution happen lazily from helper functions during completion instead of at import time. Discovery results are cached in `$script:` scope, so `grep --help` is only invoked once per session and re-importing the script is side-effect free.

## How completion works

### Help-driven option catalog

Initialization captures `grep --help` and parses the option synopsis lines into a cached option catalog. That gives the completer a local view of the installed grep build without hard-coding the entire flag set. The parser separates each option synopsis from its inline description and understands short pairs (`-x, --long`), long-only lines (`    --long`), and short-only lines (`  -I`). It also resolves both the GNU-style `--option=PLACEHOLDER` and the clap-style `--option <PLACEHOLDER>` synopsis forms, so the same completer adapts to whichever `grep.exe` is first on `PATH`.

### Enum value overlay

A small static value overlay supplies the four enum value sets grep accepts:

- `--color` -> `always`, `never`, `auto`
- `--binary-files` -> `binary`, `text`, `without-match`
- `-d` / `--directories` -> `read`, `skip`, `recurse`
- `-D` / `--devices` -> `read`, `skip`

These sets are curated in the script rather than scraped from the `[possible values: ...]` text in `--help`, because that bracketed list is not present in every grep build (some builds spread the values across wrapped continuation lines, and others omit it). A curated overlay keeps the value hints stable and accurate regardless of the installed help wording.

### Operand routing

The completer tracks grep's main positional modes:

- normal search mode expects a first positional pattern
- `-e` / `--regexp` and `-f` / `--file` (separate, attached, or inline `--regexp=` / `--file=`) establish a pattern source, after which positionals become files to search
- once any positional has been supplied, later positionals are files
- the position right after any flag — including `-V` / `--version` and `--help` — is grammatically the pattern slot, so it offers the `<pattern>` placeholder like every other pre-operand position (note: `-h` is `--no-filename`, not help)

PowerShell native completers cannot return "nothing": an empty result array makes PowerShell fall back to its default filename completion, dumping every entry in the current directory. Returning the standard `<pattern>` placeholder there is therefore both more useful and quieter than trying to suppress output, so the completer does not special-case `--version` / `--help` / `-V` into an empty result.

### Placeholder-only slots

Free-form slots such as regex patterns (`-e` / `--regexp`), globs (`--include`, `--exclude`, `--exclude-dir`), labels (`--label`), and separators (`--group-separator`) intentionally return placeholders or the typed value instead of generic filesystem completions.

## Usage examples

```powershell
grep 
grep -
grep --color=
grep --binary-files=
grep -d 
grep -m 
grep --include 
grep -f .\
grep foo .\
grep -e pat .\
```

## Dependencies or external command expectations

- Expects `grep` or `grep.exe` to be resolvable if help data should be harvested
- Falls back to placeholder-oriented and filesystem completion when runtime discovery is unavailable
- Filesystem completion depends on local filesystem access

## Limitations / notes

- Combined short-flag clusters (for example `-rni`) are not split; an unknown leading-`-` token is treated as a consumed boolean switch.
- `--color` is an optional-value flag (`--color[=<WHEN>]`); its `WHEN` enum values are offered only via the inline `--color=` form. A bare `--color` followed by a space is a completed flag and does not consume the next token as its value.
- The four enum value sets are curated in the script rather than scraped from grep's `[possible values: ...]` help text.
- The completer does not validate glob or regular-expression syntax for pattern, glob, label, or separator slots.
- `grep` exposes no machine-readable completion schema (`--cli-schema` does not exist on these builds), so `grep --help` is the only discovery surface used and the script deliberately does not attempt to invoke a schema command.
