# `py` completer

This completer provides a standalone native PowerShell argument completer for the Windows Python launcher `py` / `py.exe`.

## Covered launcher surface

- Launcher flags: `-2`, `-3`, `-32`, `-64`, `-0`, `--list`, `-0p`, `--list-paths`, `-h`, `-?`, `--help`
- Launcher selector forms: `-V:TAG`, `-V:COMPANY/TAG`
- Version-selector grammar: `-3.14`, `-3.14-32`, `-3.14-64`
- First positional script/file operand: filesystem path completion

## Behavior notes

- The completer is launcher-specific and intentionally does **not** surface embedded Python interpreter options just because `py -h` / `py --help` prints Python help after the launcher section.
- It reconstructs command text from `CommandAst.Extent.Text` plus `cursorPosition`, so trailing-space and attached-token handling follow the real native completion path.
- `-V:` completion is value-aware. When available, installed runtime tags are discovered lazily from local `py -0p` output and cached briefly.
- `-V:prefix` and `-V:COMPANY/` remain in selector mode and use placeholders when no installed-tag match is available, rather than falling back to filesystem completion.
- After the first script/file operand is present, launcher switch completion stops. Subsequent completion is limited to path-like arguments or placeholder sentinels.

## Import-safe top-level shape

The script keeps its top level import-safe for `Import-CompleterScript` usage:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

All runtime discovery and caching happens lazily inside helper functions.
