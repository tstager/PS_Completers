# mktemp completer

## What it completes / overview

mktemp_completer.ps1 registers a standalone native PowerShell completer for mktemp and mktemp.exe.

It is a help-driven completer with a static fallback for the temporary file or directory creator workflow. The script exposes the command's option catalog from the installed build, completes the DIR of `-p`/`--tmpdir` with directories and describes the TEMPLATE operand with template shapes.

The completer covers:

- option-name suggestions for the supported short and long flags
- TEMPLATE operand suggestions: `tmp.XXXXXXXXXX`, `XXXXXXXXXX`, `<prefix>XXXXXX`, a typed prefix extended with `XXXXXX` (`tmp.` -> `tmp.XXXXXX`) and directory completion for a template that carries a path part
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `--tmpdir`
- `-d`
- `--directory`
- `-u`
- `--dry-run`
- `-q`
- `--quiet`
- `--suffix`
- `-p`
- `-t`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'mktemp', 'mktemp.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Mktemp -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\mktemp_completer\mktemp_completer.ps1
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
- TEMPLATE names a file that does not exist yet and must end in at least three X's, so the operand slot offers template shapes instead of existing files; only a path part inside the template (`subdir\log.`) is completed against the filesystem, directories only.
- `-p DIR` and `--tmpdir[=DIR]` are directory-only slots: files are filtered out and the results keep their `ProviderContainer` type. The attached short form `-pC:\Temp` is recognised too; because PowerShell splits that token at the colon and only replaces the text after `-pC:`, the completer trims that unreplaced head from its results.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `--suffix`: `<suffix>`
- `-p`, `--tmpdir`: directories (separate form `-p DIR`, attached forms `--tmpdir=DIR` and `-pDIR`)

## Representative validation scenarios

```powershell
mktemp -
mktemp --
mktemp --suffix 
mktemp --suffix=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--suffix` shows its documented values in both the separate and the attached form
- `mktemp ` offers the template shapes and `mktemp tmp.` offers `tmp.XXXXXX`; `mktemp -p ` lists directories only
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the temporary file or directory creator workflow and the option set surfaced by the installed build.
- The implementation stays aligned with the repository's import-safe completer pattern.
