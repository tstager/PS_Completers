# stdbuf completer

## What it completes / overview

stdbuf_completer.ps1 registers a standalone native PowerShell completer for stdbuf and stdbuf.exe.

It is a help-driven completer with a static fallback for standard buffering control. The script exposes the command's option catalog, completes the COMMAND operand from the executables on `PATH`, and falls back to filesystem path completion for the remaining operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- MODE values for `-i`/`-o`/`-e` and their long forms
- executable names for the COMMAND operand
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-i`
- `--input`
- `-o`
- `--output`
- `-e`
- `--error`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'stdbuf', 'stdbuf.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Stdbuf -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\stdbuf_completer\stdbuf_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. A static fallback list is used when the tool is not installed. The description text of each help line becomes the completion tooltip.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Value-bearing options complete their documented values in the separate form (`--opt value`), the attached form (`--opt=value`) and for a partially typed value. See the table below. A MODE slot whose typed prefix matches no value returns nothing from the completer instead of offering file paths.
- The COMMAND operand (the first word that is neither an option nor a MODE, or the word after `--`) completes executable names from the `PATH` directories, matched case-insensitively. `.exe` files are offered without the extension, because the exec stdbuf uses finds `NAME.exe` from `NAME`; `.com`, `.bat` and `.cmd` files keep their extension, which stdbuf needs. The directories are read directly (no process is started) and the list is cached per session, keyed by `$env:PATH`. A name with whitespace or an argument-mode metacharacter is single-quoted, and a quote the user already typed is kept. An empty COMMAND slot (`stdbuf `, `stdbuf -o L `, `stdbuf -o L -- `) returns nothing, so PowerShell lists the current directory in `.\name` form and a local script stays reachable; the executables appear once a name prefix is typed (stdbuf looks a bare name up on `PATH` only). A path-like prefix (containing `\`, `/` or `:`, or starting with `.` or `~`) uses path completion, and a typed `.\` or `./` is kept in the result (`.\r` -> `.\run.sh`).
- Other operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `-o`, `-e`, `--output`, `--error`: `L`, `0`, `<size>`
- `-i`, `--input`: `0`, `<size>` (stdbuf rejects `L` for standard input: "line buffering stdin is meaningless")

## Representative validation scenarios

```powershell
stdbuf -
stdbuf --
stdbuf --input 
stdbuf --input=
stdbuf -o L gre
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--input` shows its documented values (`0`, `<size>`) in both the separate and the attached form
- `-o L gre` offers `grep` and the other executables on `PATH` that start with `gre`
- an empty COMMAND slot falls back to PowerShell's current-directory listing (`.\name`)
- operand slots after COMMAND offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the buffered-command workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
