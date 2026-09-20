# jq completer

## What it completes / overview

`jq_completer.ps1` registers a standalone native PowerShell completer for `jq` and `jq.exe`.

The completer is help-driven with a static fallback: option names come from `jq --help` when the tool is available and are cached in script scope for the session. Option matching is case-sensitive, so `-r`/`-R`, `-s`/`-S` and `-c`/`-C` are all offered and matched exactly.

It covers:

- option-name suggestions for jq's short and long flags
- an arity table for options that take one or two arguments: `--arg NAME VALUE`, `--argjson NAME JSON`, `--rawfile NAME FILE`, `--slurpfile NAME FILE`, `-f`/`--from-file FILE`, `-L`/`--library-path DIR` (directories only), `--indent N` (the literal values `0`-`7`, since jq caps indentation at 7)
- a starter set for the filter operand: `.`, `.[]`, `keys`, `length`, `type`, `to_entries`, `map(`, `select(`, `sort_by(`, `group_by(`, `has(`, `del(`, `split(`, `join(`, `test(` and others
- path completion for input-file operands after the filter

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'jq', 'jq.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Jq -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\jq_completer\jq_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

## How completion works

- `Complete-Jq` scans the completed tokens left to right; the element under the cursor is the word being completed and is left out, so `jq ke` offers `keys`/`keys_unsorted` and `jq --arg fo` still counts `fo` as the pending NAME slot. An option from the arity table reserves the next one or two slots; other `-` tokens are flags; anything else counts as an operand.
- If a reserved slot is pending, its kind decides the answer: `path` slots use `Get-JqPathCompletions`, name and value slots offer a placeholder such as `<name>` when nothing is typed yet.
- A word starting with `-` lists the parsed options, filtered ordinally.
- With no operand seen yet, the word is the filter and the starter set is offered, filtered by the typed prefix (`jq to` offers `to_entries`, `tostring`, `tonumber`).
- After the filter, operands are input files and use path completion.

## Representative validation scenarios

```powershell
jq -r
jq -
jq
jq to
jq --rawfile
jq --rawfile name
jq . 
```

Expected behavior:

- `-r` completes only `-r`, never `-R`
- the bare command lists the filter starters
- `--rawfile ` offers `<name>`; `--rawfile name ` offers files
- `jq . ` offers files for the input operand

## Notes

- If `jq` is not available, the script falls back to a compact built-in option catalog so the completer still loads cleanly.
- The help invocation pipes `$null` into `jq` so it cannot wait on standard input.
