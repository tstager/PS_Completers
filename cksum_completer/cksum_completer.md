# cksum completer

## What it completes / overview

cksum_completer.ps1 registers a standalone native PowerShell completer for cksum and cksum.exe.

It is a help-driven completer with a static fallback for the checksum workflow. The script exposes a compact option catalog for common cksum flags and falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for common short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'cksum', 'cksum.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Cksum -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\cksum_completer\cksum_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. Only the indented option table is scanned, so prose such as the DIGEST bullets (`equivalent to sum -s`) can no longer contribute phantom options. A static fallback list is used when the tool is not installed. The description text of each help line (including wrapped continuation lines) becomes the completion tooltip.
- Value slots are modelled: after `-a` / `--algorithm` the digest names are offered (parsed from the `[possible values: ...]` span in the same help text, with a curated fallback), after `-l` / `--length` the sha2/sha3 lengths `224 256 384 512` are offered, and the attached `--algorithm=md` form keeps the `--algorithm=` prefix on every suggestion.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
cksum -
cksum --
cksum -a 
cksum --algorithm=sha
cksum -l 
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `-a ` / `--algorithm=` offer the digest names and `-l ` offers the digest lengths
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the cksum workflow and the option set surfaced in this repository's import-safe pattern.
- The implementation stays aligned with the repository's import-safe completer pattern.
