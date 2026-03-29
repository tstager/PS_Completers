# contig completer

## What it completes / overview

`contig_completer.ps1` registers a standalone native PowerShell completer for `contig` and `contig.exe`.

The implementation is static-first and mode-aware:

- normal mode completes switches plus existing file and path targets
- `-f` mode pivots to free-space analysis and suggests drive-letter operands
- `-n` mode pivots to new-file creation and suggests a file path followed by sample numeric lengths
- NTFS metadata names such as `$Mft` and `$LogFile` are offered in existing-file mode

The completer is side-effect free and does not invoke Contig while completing.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'contig', 'contig.exe' -ScriptBlock { ... }
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

The completer scans earlier tokens and selects one of three modes:

- existing-file mode (default)
- free-space mode when `-f` is present
- new-file mode when `-n` is present

That keeps suggestions aligned with the distinct syntax forms in `Contig.exe /?`.

### Existing-file mode

Existing-file mode offers:

- `-a`, `-q`, `-s`, `-v`, `-nobanner`, and `/?`
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

- local filesystem drive letters such as `C:`
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

`-l` is modeled only in `-n` mode.

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
- Drive suggestions come from local PowerShell filesystem drives

## Limitations / notes

- The completer intentionally uses sample numeric lengths rather than trying to infer a preferred size.
- Existing-file mode is modeled as a single primary operand slot even though users can still type additional free-form arguments manually.
- `/?` is treated as terminal for completion so PowerShell does not fall back to generic filesystem suggestions after help is requested.
- NTFS metadata names that start with `$` may complete most reliably when quoted or escaped because bare `$name` text can be intercepted by normal PowerShell variable completion before native completion runs.
