# reg completer

## Overview

`reg_completer.ps1` registers a native PowerShell argument completer for `reg` and `reg.exe`.

The script is self-contained and follows the repository's help-driven completer pattern. It builds a cached subcommand catalog from local `reg /?` subcommand help, then layers in targeted metadata for positional arguments, option value kinds, registry-path completion, and file-path completion.

## What it completes

- top-level `reg` subcommands:
  - `QUERY`
  - `ADD`
  - `DELETE`
  - `COPY`
  - `SAVE`
  - `LOAD`
  - `UNLOAD`
  - `RESTORE`
  - `COMPARE`
  - `EXPORT`
  - `IMPORT`
  - `FLAGS`
- subcommand-specific slash options parsed from local help
- registry key paths for:
  - query/add/delete/copy/compare/save/restore/export
  - restricted `HKLM` / `HKU` load and unload targets
  - restricted `HKLM\Software\...` targets for `reg flags`
- local registry value names for `/v` when the selected key can be resolved through the PowerShell registry provider
- registry type hints for `/t`
- separator hints for `/se` and `/s` when those slots take a separator character
- file paths for:
  - `reg import` (`.reg`)
  - `reg export` (`.reg`)
  - `reg save` / `reg load` / `reg restore` (`.hiv`)
- `reg flags` bare action tokens:
  - `QUERY`
  - `SET`
- `reg flags SET` bare flag tokens:
  - `DONT_VIRTUALIZE`
  - `DONT_SILENT_FAIL`
  - `RECURSE_FLAG`

## Behavior notes

- Uses `Register-ArgumentCompleter -Native` for `reg` and `reg.exe`.
- Uses a script-scoped cache in `$script:RegCompletionCatalog`.
- Treats subcommands and slash options case-insensitively for matching, while emitting the canonical help-style completion text.
- Accepts both short root aliases such as `HKLM\...` and long local root forms such as `HKEY_LOCAL_MACHINE\...`.
- Completes remote-machine key prefixes at the root-hive level such as `\\SERVER\HKLM\`, but does not attempt remote registry enumeration beyond the remote hive choice.
- Uses provider-backed local registry enumeration for subkeys and value names where the path is resolvable through `Registry::`.
- Returns no-op placeholder completions for free-form slots like `/d` and `/f` so PowerShell does not fall back to filesystem completion in those positions.
- `reg flags` intentionally offers `QUERY`, `SET`, and the documented set tokens, but does not suggest `/s` because the local help example mentions it without listing it in the formal syntax/parameter section.

## Loading

```powershell
. .\reg_completer.ps1
```

## Example scenarios

```powershell
reg <Tab>
reg query <Tab>
reg query HKLM\Software\<Tab>
reg query HKLM\Software\Microsoft /v <Tab>
reg add HKCU\Software\MyCo /t <Tab>
reg export HKCU\Software\MyCo <Tab>
reg import <Tab>
reg flags HKLM\Software\MyCo <Tab>
reg flags HKLM\Software\MyCo SET <Tab>
```

## Limitations

- Remote registry completion is intentionally limited to machine-prefix plus remote root-hive suggestions.
- Local value-name completion depends on the PowerShell registry provider being able to resolve the selected key.
- Free-form data/search slots intentionally avoid inventing content and only suppress filesystem fallback.
- File-path slots suggest actual filesystem entries; they do not invent a new `.reg` or `.hiv` filename until you begin typing one.
- The completer follows the locally installed `reg.exe` help surface; if a Windows build exposes different options, the help-driven descriptions will follow that local runtime.
