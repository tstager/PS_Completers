# zip completer

## Overview

`zip_completer.ps1` registers a native PowerShell argument completer for Info-ZIP `zip` / `zip.exe`.

The script is standalone and self-contained. It builds a cached option catalog from local `zip -h`, `zip -h2`, and `zip -so` output, then layers in a small amount of static metadata for value-taking options and useful long-option aliases.

## What it completes

- native options discovered from local help
- first positional archive path (`zipfile`)
- subsequent input file and directory paths
- directory values for:
  - `-b`
  - `--temp-path`
- archive output paths for:
  - `--output-file`
  - `--out`
- include/exclude pattern lists for:
  - `-i`
  - `-x`
  - `--include`
  - `--exclude`
- date hints for:
  - `-t`
  - `-tt`
- suffix-list hints for:
  - `-n`
- selected enumerated values for:
  - `-Z`
  - `-s`

## Behavior notes

- Uses `Register-ArgumentCompleter -Native` for:
  - `zip`
  - `zip.exe`
- Uses a script-scoped cache in `$script:ZipCompletionCatalog`.
- Recognizes both separate and attached short-option values such as:
  - `-t 20250101`
  - `-t20250101`
  - `-bC:\temp`
- Recognizes long-option values supplied as either:
  - `--output-file archive.zip`
  - `--output-file=archive.zip`
  - `--out archive.zip`
  - `--out=archive.zip`
- Treats `--` as an option terminator and falls back to literal path completion after it.
- Keeps `-i` / `-x` list completion active until the next option, `@`, or end of line, matching the local help grammar.

## Loading

```powershell
. .\zip_completer.ps1
```

## Example scenarios

```powershell
zip <Tab>
zip archive.zip <Tab>
zip -b <Tab>
zip -t<Tab>
zip archive.zip -x <Tab>
zip archive.zip --out=<Tab>
zip archive.zip -- -leading-dash-file<Tab>
```

## Limitations

- The option catalog is only as complete as the locally installed `zip` help output (`-h`, `-h2`, `-so`) plus the script's targeted static metadata.
- Pattern completion is path-oriented plus a few wildcard hints; it does not attempt full archive-aware pattern expansion.
- Text-valued options such as passwords or test commands are intentionally not populated with suggestions.
