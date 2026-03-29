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
- `-?`
- `/?`

It also handles the mutual-output variants cleanly:

- `-c` versus `-ct`
- VirusTotal forms `-v`, `-vr`, `-vs`, and `-vrs`

### Value-aware switches

The completer adds targeted values for the main parameterized switches:

- `-a` -> `*` and the validated category letters (`b`, `c`, `d`, `e`, `g`, `h`, `i`, `k`, `l`, `m`, `n`, `o`, `p`, `r`, `s`, `t`, `w`)
- `-o` -> output-file path completion
- `-z` -> two path-aware values:
  - offline Windows system root
  - offline user-profile path

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
- local filesystem access for `-o` and `-z`
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
- Offline path positions stay local-only and path-aware.
