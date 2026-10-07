# env completer

## What it completes / overview

env_completer.ps1 registers a standalone native PowerShell completer for env and env.exe.

It is a help-driven completer with a static fallback for the environment utility workflow. The script exposes the command's option catalog from the installed build and models env's operand list (`[-] [NAME=VALUE]... [COMMAND [ARG]...]`).

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion: the bare `-`, `NAME=` assignments from the live environment, and programs on `PATH`
- path completion for path-like operands and for the words after `COMMAND`
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-i`
- `--ignore-environment`
- `-0`
- `--null`
- `-u`
- `--unset`
- `-C`
- `--chdir`
- `-S`
- `--split-string`
- `--block-signal`
- `--default-signal`
- `--ignore-signal`
- `--list-signal-handling`
- `-v`
- `--debug`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'env', 'env.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Env -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\env_completer\env_completer.ps1
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
- Value-bearing options complete their documented values in the separate form (`--opt value`), the attached form (`--opt=value`) and for a partially typed value. Path-valued options use the script's own path completion. See the table below.
- The words before the cursor are walked the way env's own option parser does: options (including bundled short flags such as `-iu NAME` and unique long-option abbreviations) until the first non-option word or `--`, then an optional bare `-`, then `NAME=VALUE` assignments; the first word without `=` is `COMMAND`.
- In the operand slot an empty word offers `-` ("a mere - implies -i", only before any operand) and `NAME=` for every variable in the current session; names only, values are never read into completions. After an assignment or `-`, or once a prefix is typed, programs env can start from `PATH` (`.exe`, `.com`, `.bat`, `.cmd`, first match in `PATH` order) are offered as well. Names are matched case-insensitively, as Windows treats them.
- The `PATH` program list comes from a direct directory scan (no process is started), cached per `PATH` value for 60 seconds.
- A candidate containing whitespace or a PowerShell argument-mode metacharacter (for example `ProgramFiles(x86)=`) is single-quoted; a typed opening quote is honoured. A typed path (`.\`, `./`, `~`, a drive or a separator) and a prefix with no variable or program match use filesystem path completion, with wildcard characters in the typed text escaped.
- Words after `COMMAND` belong to that command: env's own options and values are no longer offered there; a non-option word gets path completion.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `-u`, `--unset`: environment variable names from the current session
- `-C`, `--chdir`: filesystem paths
- `-S`, `--split-string`: `<string>`
- `--block-signal`, `--default-signal`, `--ignore-signal`: `HUP`, `INT`, `QUIT`, `KILL`, `TERM`, `USR1`, `USR2`, `PIPE`, `ALRM`, `CHLD`

## Representative validation scenarios

```powershell
env -
env --
env --split-string 
env --split-string=
env 
env PA
env FOO=1 no
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--split-string` shows its documented values in both the separate and the attached form
- `env ` offers `-` and `NAME=` assignments; `env PA` offers the matching assignments (`Path=`, `PATHEXT=`, spelled as the session spells them) and programs such as `paste.exe`; `env FOO=1 no` offers `notepad.exe`
- path-like operands and the words after `COMMAND` offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the environment utility workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
