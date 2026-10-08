# markitdown completer

## What it completes / overview

`markitdown_completer.ps1` registers a native PowerShell completer for `markitdown` and `markitdown.exe`.

The completer is static-first, based on the locally installed `markitdown.exe --help` surface. It focuses on:

- documented switches
- path completion for the input filename and `-o` / `--output`
- enum-like suggestions for `--extension`, `--mime-type`, and `--charset`
- placeholder endpoint values for Azure Document Intelligence and Azure Content Understanding (`--use-cu`, `--cu-endpoint`, `--cu-analyzer`, `--cu-file-types`)
- the attached `--option=value` form for every value-bearing option
- URI scheme affordances (`https://`, `http://`, `file:///`, `data:`) for the input operand

## Registration and command names

The script registers:

- `markitdown`
- `markitdown.exe`

with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('markitdown', 'markitdown.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-MarkItDown -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

## Supported completion behavior

- `markitdown <TAB>` completes local input files (directories first, then extensions markitdown can convert, then other files, capped at 200 entries and enumerated lazily so a 30k-entry directory answers in well under a second), offers the URI schemes, and adds `<filename>` when you want to read from stdin instead. A typed word that matches nothing returns no completions so PowerShell's own filesystem fallback applies; placeholders are only offered for an empty word.
- Path candidates are emitted as exactly one PowerShell argument: a name with whitespace, `' " $ & ; , ( ) { } | < > @ #`, a backtick or a typographic quote is single-quoted (inner single-quote characters, typographic ones included, are doubled), so `markitdown it<TAB>` gives `'it''s.pdf'`. A quote you typed is kept: `markitdown "dol<TAB>` gives ``"dollar`$x.pdf"``, and a typographic opening quote is treated as the matching ASCII quote. A typed folder part such as `.\` or `./` is kept exactly as typed, separator included, and a name starting with a dash gets a `.\` prefix (`markitdown <TAB>` offers `.\-dash.txt`) so PowerShell does not read it as a parameter.
- `markitdown --extension=<TAB>` and the other `--option=value` forms complete the value with the `--option=` prefix kept. A value that needs quoting is quoted after the `=` (`--output='amp&x.md'`), and a quote typed after the `=` is kept (`--output='it<TAB>`, `--extension='pd<TAB>`); markitdown receives `--output=amp&x.md` as one argument.
- `markitdown -o <TAB>` completes output paths and suggests `output.md` when the slot is empty.
- `markitdown --extension <TAB>` suggests all 47 extensions accepted by the markitdown 0.1.7 converters (documents, text, images, audio and video).
- `markitdown --mime-type <TAB>` suggests the MIME type prefixes those converters accept, including the `image/*`, `audio/*` and `video/*` families.
- `markitdown --cu-file-types <TAB>` completes a comma-separated list segment by segment, offering only the 31 Content Understanding file types markitdown 0.1.8 accepts (for example `jpeg`, not `jpg`). The attached form `--cu-file-types=pdf,<TAB>` works the same way and skips types already in the list.
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
- MIME type and extension suggestions are copied from the converter sources of markitdown 0.1.7; charset suggestions are curated hints.
- Free-form stdin workflows are represented with placeholders rather than a custom parser for redirected input.
