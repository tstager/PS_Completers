# autorunsc completer

## What it completes / overview

`autorunsc_completer.ps1` registers a native PowerShell completer for `autorunsc` and `autorunsc.exe`.

The implementation is intentionally side-effect free:

- it covers the validated help switches, including `-?` and `/?`
- it treats `-a`, `-o`, and `-z` as value-aware slots
- it adds safe local profile-name hints for the trailing `user` positional
- it keeps offline-scan path positions path-aware

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `autorunsc`, `autorunsc.exe`
- The script enables `Set-StrictMode -Version 2.0`

Load it with:

```powershell
. .\autorunsc_completer.ps1
```

## How completion works

### Switch completion

The script completes the locally validated Autorunsc switches:

- `-a`
- `-c`
- `-ct`
- `-h`
- `-m`
- `-o`
- `-s`
- `-t`
- `-u`
- `-x`
- `-v`
- `-vr`
- `-vs`
- `-vrs`
- `-vt`
- `-z`
- `-nobanner`
- `-accepteula`
- `-?`
- `/?`

It also handles the mutual-output variants cleanly:

- `-c` versus `-ct`
- VirusTotal forms `-v`, `-vr`, `-vs`, and `-vrs`

### Value-aware switches

The completer adds targeted values for the main parameterized switches:

- `-a` -> `*` and the validated category letters (`b`, `c`, `d`, `e`, `g`, `h`, `i`, `k`, `l`, `m`, `n`, `o`, `p`, `r`, `s`, `t`, `w`, `x`)
- `-o` -> output-file path completion
- `-z` -> two directory-only values:
  - offline Windows system root
  - offline user-profile path

#### Concatenated `-a` categories

Help's usage line is `-a <*|bcdeghi klmnoprstw>`, so category letters may be concatenated. A typed run of letters is therefore treated as a prefix to extend rather than a token to match: `autorunsc -a ls<TAB>` offers `ls` first and then `lsb`, `lsc`, `lsd` and every other category not already in the run. A run containing a letter that is not a category returns nothing rather than guessing.

#### Offline `-z` operands

Both `-z` operands name directories inside an offline image, so they are completed with directories only (including hidden ones) and an empty slot is seeded with the local volume roots (`C:\`, `D:\`, ...) rather than a listing of the working directory. Once both operands are supplied the completer emits a `<no-more-arguments>` placeholder instead of constructing a completion from an empty string.

### Positional `user` completion

When `-z` is not active, the trailing positional argument is treated as the documented `user` slot.

The completer suggests:

- `*`
- the current `$env:USERNAME`
- local profile directory names from `C:\Users`
- a `<user>` placeholder

## Dependencies or external command expectations

This completer is static and does not invoke `autorunsc` during completion.

It only depends on:

- PowerShell native argument completer support
- local filesystem access for `-o` and `-z`, plus `[System.IO.DriveInfo]::GetDrives()` for the `-z` volume roots
- cheap local inspection of `C:\Users` for profile-name hints

## Usage / loading example

```powershell
. .\autorunsc_completer.ps1

autorunsc -<TAB>
autorunsc -a <TAB>
autorunsc -o .\<TAB>
autorunsc -z C:\<TAB>
autorunsc <TAB>
```

## Limitations / notes

- The completer does not query Autoruns or VirusTotal during completion.
- The `user` positional is completed from local profile folders, not from domain or remote account discovery.
- Offline path positions stay local-only and directory-aware.
