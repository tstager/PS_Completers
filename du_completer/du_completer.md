# du completer

## What it completes / overview

`du_completer.ps1` registers a standalone native PowerShell completer for `du` and `du.exe`.

It models GNU coreutils `du`, which is the build that resolves on `PATH` when Git for Windows is installed. The option catalog is static and complete for that surface; descriptions are refreshed from `du --help` on first use when the tool is available. Sysinternals `du` is not modelled.

The completer covers:

- every short and long option of GNU `du`, offered case-sensitively so `-B`/`-b`, `-D`/`-d`, `-H`/`-h`, `-L`/`-l`, `-S`/`-s` and `-X`/`-x` stay distinct
- values for `-d`/`--max-depth`, `-B`/`--block-size`, `-t`/`--threshold`, `--time`, `--time-style` and `--exclude`, in the separate and the attached `--opt=value` form
- directory completion for the operand slots
- quoted paths, including an unterminated opening quote

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'du', 'du.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Du -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\du_completer\du_completer.ps1
```

The script also enables `Set-StrictMode -Version 2.0`.

## Import-CompleterScript compatibility

The top level contains `Set-StrictMode`, one `Get-Variable`-guarded catalog initialisation, function definitions and the literal registration call, which the CompleterActions strict import grammar accepts.

## How completion works

- `Initialize-DuCompletionCatalog` builds the option catalog from a static table of GNU options with their value kinds, then overlays descriptions parsed from `du --help` (run with stdin closed). Lookups use an ordinal comparer.
- `Get-DuState` scans the completed tokens, records which options were used, and notes when the previous option still expects a value. An attached `--opt=value` token counts as a complete option.
- `Complete-Du` answers, in order: values for an attached `--opt=` word, values for a pending option, options for a word starting with `-`, and directory completion for everything else. An empty operand slot also lists the unused options.
- Value kinds: `Levels` offers `0 1 2 3 5 10`; `Size` offers `1 1K 1M 1G K M G`; `TimeWord` offers `atime access use ctime status`; `TimeStyle` offers `full-iso long-iso iso +%Y-%m-%d`; `File` returns nothing so PowerShell's file completion applies.

## Representative validation scenarios

```powershell
du -
du --m
du -d
du --max-depth=
du --time=
du -h
```

Expected behavior:

- `-` lists all 44 short and long options with their help descriptions
- `--m` completes `--max-depth`; `-d ` and `--max-depth=` list the depth hints
- `--time=` lists the time words with the `--time=` prefix kept
- `-h ` lists the directories of the current location

## Dependencies or external command expectations

- `du` or `du.exe` on `PATH` to refresh descriptions; the static catalog is used as-is otherwise
- filesystem access for directory completion

## Limitations / notes

- File-valued options (`--files0-from`, `-X`/`--exclude-from`) defer to PowerShell's file completion.
- Operand completion lists directories only; `du` also accepts files, which PowerShell's fallback does not add because the completer returns results.
