# sha1sum completer

## What it completes / overview

sha1sum_completer.ps1 registers a standalone native PowerShell completer for sha1sum and sha1sum.exe.

It is a help-driven completer with a static fallback for the sha1sum workflow. The script exposes the command's option catalog from the installed build, then falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-b`
- `--binary`
- `-c`
- `--check`
- `--tag`
- `-t`
- `--text`
- `-z`
- `--zero`
- `--ignore-missing`
- `--quiet`
- `--status`
- `--strict`
- `-w`
- `--warn`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'sha1sum', 'sha1sum.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Sha1sum -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\sha1sum_completer\sha1sum_completer.ps1
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
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
sha1sum -
sha1sum --
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the sha1sum workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
