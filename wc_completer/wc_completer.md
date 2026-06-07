# wc completer

## What it completes / overview

`wc_completer.ps1` registers a standalone native PowerShell completer for `wc` and `wc.exe`.

It is a help-driven completer that:

- parses the local `wc --help` surface once per session and caches the result
- suggests both short and long options discovered from the installed build
- supports inline `--option=value` completion for the two value-bearing options
- provides enum value hints for `--total` (`auto`, `always`, `only`, `never`)
- completes real filesystem paths for `--files0-from`, including the stdin `-` sentinel
- completes real filesystem paths for file operands, including the stdin `-` sentinel

`wc` is a small command: every short flag is a boolean count selector (`-c`, `-m`, `-l`, `-L`, `-w`) and only two long options consume a value (`--total` and `--files0-from`). The completer reflects that simplicity directly.

## Command and build

The completer targets the `wc` byte/word/line counter from the coreutils family. It works with either of the common Windows builds:

- uutils coreutils (Rust, clap-based help): `wc [OPTION]... [FILE]...` with separate-token placeholders such as `--files0-from <F>` and `--total <WHEN>`
- GNU coreutils: the same option surface but attached-form placeholders such as `--files0-from=F` and `--total=WHEN`

Whichever `wc.exe` resolves first on `PATH` is used for help discovery, and the parser adapts to its help format automatically.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'wc', 'wc.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\wc_completer\wc_completer.ps1
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

All help capture, parsing, and command resolution happen lazily from helper functions during completion instead of at import time. Discovery results are cached in `$script:` scope, so `wc --help` is only invoked once per session and re-importing the script is side-effect free.

## How completion works

### Help-driven option catalog

Initialization captures `wc --help` and parses the option synopsis lines into a cached option catalog. That gives the completer a local view of the installed `wc` build without hard-coding the entire flag set. The parser separates each option synopsis from its inline description and understands short pairs (`-c, --bytes`), long-only lines (`    --total <WHEN>`), and short-only lines. It resolves both the GNU-style `--option=PLACEHOLDER` and the clap-style `--option <PLACEHOLDER>` synopsis forms, so the same completer adapts to whichever `wc.exe` is first on `PATH`.

### Option coverage

| Option | Form | Value | Notes |
| --- | --- | --- | --- |
| `-c`, `--bytes` | boolean | none | print the byte counts |
| `-m`, `--chars` | boolean | none | print the character counts |
| `-l`, `--lines` | boolean | none | print the newline counts |
| `-L`, `--max-line-length` | boolean | none | print the length of the longest line |
| `-w`, `--words` | boolean | none | print the word counts |
| `--total` | value-bearing | `WHEN` enum | when to print total counts |
| `--files0-from` | value-bearing | `F` file/stdin | read NUL-terminated names from file `F` |
| `-h`, `--help` | boolean | none | print help (terminal) |
| `-V`, `--version` | boolean | none | print version (terminal) |

The exact set and descriptions come from the installed build's help text; the table above reflects the standard coreutils surface.

### Value-bearing options

Only two options consume a value, and both always do (neither is optional-value), so a separate-token form (`--total auto`) and the attached form (`--total=auto`) are both handled:

- `--total` -> enum value completion over the curated set `auto`, `always`, `only`, `never`. The enum set is curated in the script rather than scraped from the wrapped `WHEN can be: ...` continuation line in `--help`, which keeps the value hints stable and accurate regardless of help wording. A typed value that does not match the enum is echoed back as a literal so typos are not silently dropped.
- `--files0-from` -> real filesystem path completion plus the stdin `-` sentinel, because `wc` reads NUL-terminated file names either from a named file or from standard input when the argument is `-`.

### Operand file completion

`wc` operands are uniformly file paths (unlike `grep`, there is no pattern-first operand), so every positional slot offers real filesystem path completion plus the stdin `-` sentinel. This holds at the first operand and at every later operand, and after an explicit `--` end-of-options marker.

### Placeholder and anti-fallback behavior

PowerShell native completers cannot return "nothing": an empty result array makes PowerShell fall back to its default filename completion, dumping every entry in the current directory. To avoid that, value and operand slots always return at least a placeholder result:

- a value slot with no filesystem matches returns its placeholder (`<when>`, `<F>`, `<file>`) or the typed value
- the operand slot returns the `-` sentinel plus path matches, falling back to the `<file>` placeholder when nothing matches

The terminal flags `-h` / `--help` and `-V` / `--version` are grammatically followed by the file operand slot, so the position right after them offers file completion and the `<file>` placeholder rather than an empty array.

## Usage examples

```powershell
wc 
wc -
wc --total 
wc --total=
wc --files0-from 
wc --files0-from=
wc file.txt 
wc -l .\
```

## Dependencies or external command expectations

- Expects `wc` or `wc.exe` to be resolvable if help data should be harvested
- Falls back to placeholder-oriented and filesystem completion when runtime discovery is unavailable
- Filesystem completion depends on local filesystem access

## Limitations / notes

- Combined short-flag clusters (for example `-lw`) are not split; an unknown leading-`-` token is treated as a consumed boolean switch.
- The `--total` enum value set is curated in the script rather than scraped from `wc`'s wrapped `WHEN can be: ...` help text.
- The completer does not validate the `--files0-from` file's NUL-terminated contents.
- `wc` exposes no machine-readable completion schema, so `wc --help` is the only discovery surface used and the script deliberately does not attempt to invoke a schema command.
