# markitdown completer

## What it completes / overview

`markitdown_completer.ps1` registers a native PowerShell completer for `markitdown` and `markitdown.exe`.

The completer is static-first, based on the locally installed `markitdown.exe --help` surface. It focuses on:

- documented switches
- path completion for the input filename and `-o` / `--output`
- enum-like suggestions for `--extension`, `--mime-type`, and `--charset`
- a placeholder endpoint value for Azure Document Intelligence

## Registration and command names

The script registers:

- `markitdown`
- `markitdown.exe`

with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('markitdown', 'markitdown.exe') -ScriptBlock { ... }
```

## Supported completion behavior

- `markitdown <TAB>` completes local input files and also offers `<filename>` when you want to read from stdin instead.
- `markitdown -o <TAB>` completes output paths and suggests `output.md` when the slot is empty.
- `markitdown --extension <TAB>` suggests common extensions such as `pdf`, `docx`, `pptx`, `xlsx`, `html`, `csv`, `json`, and `txt`.
- `markitdown --mime-type <TAB>` suggests common MIME types for the supported input formats.
- `markitdown --charset <TAB>` suggests common text encodings.
- `markitdown --endpoint <TAB>` suggests an Azure Document Intelligence endpoint placeholder.

## Dependencies or external command expectations

The completer was authored from the local `markitdown.exe --help` output. It does not call `markitdown` during completion, and it does not perform network operations.

## Usage / loading example

```powershell
. .\markitdown_completer\markitdown_completer.ps1
```

Example scenarios:

```powershell
markitdown <TAB>
markitdown report.pdf -o <TAB>
markitdown --extension <TAB>
markitdown --mime-type <TAB>
markitdown --endpoint <TAB>
```

## Limitations / notes

- The completer does not enumerate installed plugins; `--list-plugins` remains a normal flag.
- MIME type, extension, and charset suggestions are curated hints rather than values discovered from the runtime.
- Free-form stdin workflows are represented with placeholders rather than a custom parser for redirected input.
