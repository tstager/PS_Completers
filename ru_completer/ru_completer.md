# ru completer

## What it completes / overview

`ru_completer.ps1` registers a standalone native PowerShell completer for `ru` and `ru.exe`.

It is a help-driven, registry-aware, mode-aware completer that supports both documented forms:

- normal mode: `ru <absolute registry path>`
- hive mode: `ru -h <hive file> [relative path]`

The implementation is careful not to load hive files during completion.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'ru', 'ru.exe' -ScriptBlock { ... }
```

Load it with:

```powershell
. .\ru_completer\ru_completer.ps1
```

It also enables:

```powershell
Set-StrictMode -Version 2.0
```

## How completion works

### Help-driven switch catalog

Initialization starts from a static model and overlays descriptions from local `ru.exe /?`.

Modeled switches include:

- `-c`
- `-ct`
- `-h`
- `-l`
- `-n`
- `-q`
- `-v`
- `-nobanner`
- `/?`

### Normal registry-path mode

Without `-h`, the completer offers absolute local registry paths rooted at:

- `HKLM\`
- `HKCU\`
- `HKCR\`
- `HKU\`
- `HKCC\`

and preserves long-form roots such as `HKEY_LOCAL_MACHINE\` when typed.

### Hive mode

When `-h` is present:

1. the next slot completes as a local hive-file path
2. the following optional slot returns a `<relative-path>` placeholder or the user’s current token

That suppresses generic filesystem fallback without loading or mounting the hive file just to discover keys.

### Value-aware handling

- `-l` returns numeric depth hints
- `-l`, `-n`, and `-v` are treated as mutually exclusive recursion-depth modes
- `-c` and `-ct` are treated as sibling forms

## Usage examples

```powershell
ru <TAB>
ru HKLM\Soft<TAB>
ru -h <TAB>
ru -h .\ntuser.dat <TAB>
ru -l <TAB>
```

## Dependencies or external command expectations

- Expects `ru.exe` or `ru` to be available if help text should be harvested
- Falls back to the static catalog if help capture is unavailable
- Registry completion depends on the local PowerShell registry provider
- Hive-file completion depends on local filesystem access

## Limitations / notes

- Hive-relative paths are placeholder-based only because the completer intentionally does not load hives.
- Remote registry syntax is not modeled.
- `/?` is treated as terminal for completion.
