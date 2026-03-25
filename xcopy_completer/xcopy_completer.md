# xcopy completer

## What it completes / overview

`xcopy_completer.ps1` registers a native argument completer for `xcopy` and `xcopy.exe`.

The completer builds a cached switch catalog from local `xcopy.exe /?` output, then layers value-aware handling on top for the two inline-value switches that benefit most from it:

- `/D[:date]`
- `/EXCLUDE:file1[+file2][+file3]...`

It also completes positional source and destination paths with Windows-style quoting and trailing backslashes for directories.

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName 'xcopy', 'xcopy.exe' -ScriptBlock { ... }
```

Load it into the current session with:

```powershell
. .\xcopy_completer.ps1
```

## How completion works

### Initialization

On first use, the script creates `$script:XcopyCompletionCatalog` and:

- runs `xcopy.exe /?`
- parses option tokens and their descriptions from the local help text
- expands the documented `/[-]SPARSE` syntax into separate `/SPARSE` and `/-SPARSE` entries
- merges help-derived options with small static metadata for `/D` and `/EXCLUDE`

The resulting cache is reused on later completions in the same session.

### Positional argument handling

The completer treats the first two non-switch arguments as:

1. `source`
2. `destination`

While fewer than two positional arguments have been supplied:

- non-switch completion returns filesystem path suggestions
- a blank token also includes option suggestions, because `xcopy` switches remain valid anywhere on the command line

After both positional arguments are present, a blank token returns option suggestions only.

### Switch and inline value handling

If the current token starts with `/`, the completer first checks for inline-value forms and then falls back to switch-name completion.

Supported inline-value completions:

- `/D:` suggests a few reasonable `m-d-yyyy` and `MM-dd-yyyy` samples
- `/EXCLUDE:` completes file paths
- `/EXCLUDE:file1+...` continues completing the segment after the last `+`

Regular switch-name completion comes from the parsed local help surface, so entries such as `/A`, `/M`, `/COMPRESS`, `/NOCLONE`, `/SPARSE`, and `/-SPARSE` track the installed `xcopy.exe`.

## Dependencies or external command expectations

This completer expects:

- `xcopy.exe` to be available
- local filesystem access for path completion
- local `xcopy.exe /?` output to remain the authoritative switch source

## Usage / loading example

```powershell
. .\xcopy_completer.ps1

xcopy .\src\ .\out\ <TAB>
xcopy /D:<TAB>
xcopy /EXCLUDE:<TAB>
xcopy .\src\ .\out\ /SP<TAB>
```

## Limitations / notes

- `/D:` suggestions are sample date stubs, not validated calendar parsing.
- `/EXCLUDE:` path chaining is based on the last `+` in the token and does not try to parse nested quoting edge cases.
- Destination completion only suggests existing paths; it does not invent new file or directory names.
