# sdelete completer

## What it completes / overview

`sdelete_completer.ps1` registers a standalone native PowerShell completer for `sdelete` and `sdelete.exe`.

The implementation is intentionally risk-bounded:

- it is static-first
- it never invokes destructive actions
- it distinguishes delete mode from free-space-cleaning mode
- it returns numeric hints for `-p`
- it offers the suite-wide `-accepteula` switch alongside the eight switches SDelete prints in its own help
- and it warns about ambiguous bare-letter path operands that could be interpreted as disk targets

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'sdelete', 'sdelete.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-SDelete -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\sdelete_completer\sdelete_completer.ps1
```

The script also enables:

```powershell
Set-StrictMode -Version 2.0
```

## How completion works

### Mode-aware behavior

The completer scans tokens and selects:

- delete mode by default
- free-space mode when `-c` or `-z` is present

Delete mode offers path completion plus delete-oriented switches such as `-r`, `-s`, and `-f`.

Switch names are only added to an operand slot when the word under the cursor is empty. Once the user has typed any non-empty operand text the completer returns operand matches alone, so `sdelete no<TAB>` completes `notes.md` instead of replacing it with `-c`.

Tokenization is quote-state aware, so an unterminated quote is handled: `sdelete "Program Files\<TAB>` completes inside that directory rather than losing the path context.

Free-space mode offers:

- drive-letter targets like `D:`, taken from single-letter filesystem drives and cached for the session
- sample physical disk numbers like `0`
- placeholders such as `<drive:>` and `<physical-disk-number>`
- mode-compatible switches only

### Value handling

`-p` is modeled as a value-taking switch with sample pass counts such as:

- `1`
- `3`
- `7`
- `10`

If the user already typed a custom number, the completer echoes that token back instead of falling through to filesystem suggestions. The consumed pass count is not treated as a positional operand, so `-c` and `-z` stay available after `sdelete -p 3`.

### Ambiguous bare-letter safety

In delete mode, a single bare letter can be confused with disk targeting. When the user types an ambiguous bare-letter token without `-f`, the completer returns an explanatory result first and then the real path matches for that letter, so the warning is visible without blocking Tab from reaching an unambiguous path such as `ab.txt`.

## Usage examples

```powershell
sdelete <TAB>
sdelete -p <TAB>
sdelete -z <TAB>
sdelete -c D<TAB>
sdelete -f A<TAB>
```

## Dependencies or external command expectations

- No SDelete execution is required during completion
- Path completion depends on local filesystem access
- Drive suggestions come from local single-letter PowerShell filesystem drives; named PSDrives such as `Temp:` are excluded because SDelete cannot accept them

## Limitations / notes

- Physical disk numbers are intentionally conservative sample hints rather than live disk enumeration.
- The completer does not attempt to validate whether a typed drive or disk target is safe to clean.
- `/?` is treated as terminal for completion.
