# contig completer

## What it completes / overview

`contig_completer.ps1` registers a standalone native PowerShell completer for `contig` and `contig.exe`.

The implementation is static-first and mode-aware:

- normal mode completes switches plus existing file and path targets
- `-f` mode pivots to free-space analysis and suggests drive-letter operands
- `-n` (or `-l`) mode pivots to new-file creation and suggests a file path followed by sample numeric lengths
- NTFS metadata names such as `$Mft` and `$LogFile` are offered in existing-file mode
- switch names are offered only when the word under the cursor is empty or starts with `-` or `/`, so a typed operand is never displaced by a switch

The completer is side-effect free and does not invoke Contig while completing.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'contig', 'contig.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Contig -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it into the current session with:

```powershell
. .\contig_completer\contig_completer.ps1
```

It also enables:

```powershell
Set-StrictMode -Version 2.0
```

## How completion works

### Mode detection

Contig documents three mutually exclusive usage forms:

```text
1  contig [-a] [-s] [-q] [-v] <existing file>
2  contig -f [-v] [drive:]
3  contig [-v] [-l] -n <new file> <new file length>
```

Every switch in the catalog carries the set of forms it belongs to. The completer starts with all three forms viable and intersects that set with each switch already on the line, so choosing `-a` drops `-f`, `-l` and `-n` from the offered switches, and choosing `-l` drops `-a`, `-f`, `-q` and `-s`. A bare operand with no form-selecting switch narrows the set to form 1. `-v`, `-nobanner`, `-accepteula`, `-?` and `/?` belong to all three forms and stay available throughout.

The operand slot is picked from the same state:

- existing-file mode (default)
- free-space mode when `-f` is present
- new-file mode when `-n` or `-l` is present

### Existing-file mode

Existing-file mode offers:

- `-a`, `-q`, `-s`, `-v`, `-nobanner`, `-accepteula`, `-?`, and `/?`
- local filesystem path completion for existing files and directories
- NTFS metadata names:
  - `$Mft`
  - `$LogFile`
  - `$Volume`
  - `$AttrDef`
  - `$Bitmap`
  - `$Boot`
  - `$BadClus`
  - `$Secure`
  - `$UpCase`
  - `$Extend`

### Free-space mode

When `-f` is present, the completer stops offering normal file operands and instead suggests:

- NTFS volume letters such as `C:`, taken from `[System.IO.DriveInfo]::GetDrives()` and cached for the session; non-NTFS volumes and named PSDrives are excluded because `-f` drives the NTFS free-space APIs
- a `<drive:>` placeholder
- compatible switches such as `-v` and `-nobanner`

### New-file mode

When `-n` is present, the completer suggests:

1. a file path for the new file target
2. sample numeric length values such as:
   - `65536`
   - `1048576`
   - `10485760`
   - `1073741824`

`-l` is offered before `-n` as well, because live help puts it there: `contig [-v] [-l] -n <new file> <new file length>`.

## Key completion behaviors / supported values

### Root examples

```powershell
contig <TAB>
contig -<TAB>
contig $<TAB>
```

### Free-space examples

```powershell
contig -f <TAB>
contig -f C<TAB>
```

### New-file examples

```powershell
contig -n <TAB>
contig -n .\sample.bin <TAB>
```

## Dependencies or external command expectations

- No Contig execution is required during completion
- File and directory suggestions depend on local filesystem access
- Drive suggestions come from local NTFS volumes reported by .NET, enumerated once per session

## Limitations / notes

- The completer intentionally uses sample numeric lengths rather than trying to infer a preferred size.
- Existing-file mode is modeled as a single primary operand slot even though users can still type additional free-form arguments manually.
- `-?` and `/?` are both offered and both treated as terminal for completion so PowerShell does not fall back to generic filesystem suggestions after help is requested.
- NTFS metadata names are inserted single-quoted (`'$Mft'`) so they survive as a literal argument; the list item still shows the bare name. A bare `$name` prefix is intercepted by PowerShell's own variable completion before the native completer runs, so typing an opening quote first is the only way to reach these names.
- Tokenization is quote-state aware, so a path with an unterminated opening quote still completes inside the intended directory instead of losing the path context.
