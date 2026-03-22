# icacls completer

## What it completes / overview
`icacls_completer.ps1` registers a native completer for `icacls` and `icacls.exe`. It builds most of its completion catalog by parsing `icacls.exe /?` and then layers command-context logic on top of that parsed data.

The script covers:
- target path completion
- main `icacls` command switches such as `/save`, `/restore`, `/setowner`, `/findsid`, `/verify`, and `/reset`
- ACL modification operations such as `/grant`, `/grant:r`, `/deny`, `/remove`, `/remove:g`, `/remove:d`, `/setintegritylevel`, and `/inheritance:*`
- value completion for selected options, including file paths, integrity levels, and permission expressions

## Registration and command names
- Registers with `Register-ArgumentCompleter -Native`
- Command names: `icacls`, `icacls.exe`
- Completion scriptblock is registered inline at the end of the file

```powershell
Register-ArgumentCompleter -Native -CommandName 'icacls', 'icacls.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    ...
}
```

The file also enables `Set-StrictMode -Version 2.0`.

## How completion works
### Script-scoped catalog
The script keeps a script-scoped hashtable named `$script:IcaclsCompletionCatalog` with these buckets:
- `Initialized`
- `Commands`
- `CommandOptionsByKey`
- `CommonOptions`
- `ModifyOptions`
- `IntegrityLevels`
- `SimplePermissions`
- `SpecificPermissions`
- `InheritanceFlags`

`Initialize-IcaclsCompletionCatalog` populates that catalog once per session.

### Help parsing
The catalog is sourced from `icacls.exe /?`.

Key parser helpers:
- `Invoke-IcaclsHelpText` runs `icacls.exe '/?'` and returns the help text lines.
- `Get-IcaclsSyntaxBlocks` groups syntax blocks that start with `ICACLS`.
- `Get-IcaclsTokensFromText` extracts `/option`-style tokens from text.
- `Expand-IcaclsHelpToken` expands abbreviated help forms into concrete tokens, including:
  - `/grant[...]` -> `/grant`, `/grant:r`
  - `/remove[...]` -> `/remove`, `/remove:g`, `/remove:d`
  - `/inheritance:e|d|r` -> `/inheritance:e`, `/inheritance:d`, `/inheritance:r`
- `Get-IcaclsCommonOptionsFromLines` extracts common switches described with `indicates`.
- `Get-IcaclsIntegrityLevelsFromLines` extracts integrity level values such as short and long forms.
- `Get-IcaclsSimplePermissionsFromLines` extracts simple rights.
- `Get-IcaclsSpecificPermissionsFromLines` extracts specific rights used inside parenthesized ACL expressions.
- `Get-IcaclsInheritanceFlagsFromLines` extracts inheritance flag tokens such as `(OI)` and `(CI)`.

If help text cannot be retrieved, the script marks the catalog initialized and returns without populating those lists.

### Command-line context detection
The registered completer scriptblock:
- collects command tokens from `$commandAst.CommandElements`
- reconstructs the current token with `Get-IcaclsCurrentToken`
- determines whether the cursor is after a trailing space
- finds tokens before the current one with `Get-IcaclsTokensBeforeCurrent`
- identifies the active main command with `Get-IcaclsActiveCommand`
- detects whether a modification option has already appeared with `Test-IcaclsHasModifyOperation`
- determines whether the previous token expects a value with `Get-IcaclsExpectedValueOption`

### Specialized value completion
- `Get-IcaclsPathCompletions` uses `Get-ChildItem` and automatically quotes paths that contain spaces.
- `Get-IcaclsInlineOptionCompletions` supports inline forms for:
  - `/inheritance:e|d|r`
  - `/remove:g|d`
  - `/grant:r`
- `Get-IcaclsExpandedOptionValueCompletions` currently expands `/setintegritylevel` into combined forms.
- `Get-IcaclsIntegrityLevelCompletions` offers plain or prefixed integrity levels, including inheritance prefixes like `(OI)` and `(CI)`.
- `Get-IcaclsPermissionCompletions` handles `<identity>:<permission>` patterns.
- `Get-IcaclsParenthesizedPermissionCompletions` understands parenthesized permission syntax, tracks already-used inheritance flags and specific rights, and avoids duplicate suggestions.

## Key completion behaviors / supported values
### Initial completion behavior
Before a target path is present, the completer prefers path completion unless the current word starts with `/`. It also exposes `/?`.

After a target path is present, it suggests:
- active-command-specific options when a main command like `/save` or `/restore` has been selected
- modification options plus common options when a modify operation is already in play
- otherwise the combined set of main commands, modify options, common options, and `/?`

### Main commands
The file has an explicit helper for these primary commands:
- `/save`
- `/restore`
- `/setowner`
- `/findsid`
- `/verify`
- `/reset`

These are also used by `Get-IcaclsMainCommandFromTokens` to determine which syntax block is active.

### Common and modification options
Common and modification options are mostly parsed from help text. The implementation specifically expands and handles:
- `/grant`
- `/grant:r`
- `/deny`
- `/remove`
- `/remove:g`
- `/remove:d`
- `/setintegritylevel`
- `/inheritance:e`
- `/inheritance:d`
- `/inheritance:r`

### Value completions
- `/save` and `/restore` complete file system paths.
- `/grant`, `/grant:r`, and `/deny` complete permission expressions.
- `/setintegritylevel` completes integrity level values.
- Non-option arguments are completed as file system paths.

### Integrity levels and permissions
Integrity-level completions are built from parsed help data and combined with prefixes:
- empty prefix
- `(OI)`
- `(CI)`
- `(OI)(CI)`
- `(CI)(OI)`

Permission completion supports:
- simple rights after an identity prefix such as `User:F`
- parenthesized rights and inheritance flags such as `User:(OI)(CI)(M)`-style input
- comma-separated specific-right lists inside parentheses

The exact permission and flag sets come from the current machine's `icacls /?` output and are cached after first use.

## Dependencies or external command expectations
- Requires `icacls.exe`
- Relies on the format of `icacls.exe /?` output
- Uses `Get-ChildItem` for path completion

Because the completion catalog is generated from help text, availability and wording can vary with the host Windows version.

## Usage / loading example
```powershell
. "$PSScriptRoot\icacls_completer.ps1"

# Example completions
# icacls <TAB>
# icacls C:\Temp /grant <TAB>
# icacls C:\Temp /setintegritylevel <TAB>
```

## Limitations / notes
- The parser is intentionally tied to `icacls /?` formatting, so help text changes can change or break discovered tokens.
- Catalog initialization is one-time per session; the script does not refresh the cached data automatically.
- If `icacls.exe` cannot be found or returns no help text, the catalog stays effectively empty and completion results will be limited.
- Permission completion is specialized for `/grant`, `/grant:r`, and `/deny`; other options listed in `Get-IcaclsExpectedValueOption` may not have dedicated result generation.
- Path completion uses `Get-ChildItem` and returns fully qualified paths, quoting them when they contain spaces.