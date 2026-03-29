# strings completer

## What it completes / overview

`strings_completer.ps1` registers a native PowerShell completer for `strings` and `strings.exe`.

The completer is intentionally small and static:

- it covers the locally validated Strings help switches, including `-?` and `/?`
- it treats `-b`, `-f`, and `-n` as numeric value-taking slots
- it keeps the trailing `<file or directory>` operand path-aware
- it suppresses generic filesystem fallback in non-path value positions

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `strings`, `strings.exe`
- The script enables `Set-StrictMode -Version 2.0`

Load it with:

```powershell
. .\strings_completer.ps1
```

## How completion works

### Switch completion

The script completes the locally validated switches:

- `-a`
- `-b`
- `-f`
- `-n`
- `-o`
- `-s`
- `-u`
- `-nobanner`
- `-?`
- `/?`

### Value-aware numeric hints

The completer recognizes the three separate-value switches:

- `-b` -> sample byte counts such as `256`, `512`, `1024`, `4096`, `65536`
- `-f` -> sample offsets such as `0`, `512`, `4096`, `65536`, `0x1000`
- `-n` -> sample minimum lengths such as `3`, `4`, `8`, `16`, `32`

These suggestions keep PowerShell from falling back to unrelated file completion while you are entering numeric values.

### Path-aware operand completion

For the final `<file or directory>` operand, the completer uses local filesystem inspection so that:

- blank path positions still return command-relevant completions
- partial and quoted paths continue to complete cleanly
- directory suggestions keep a trailing `\` for continued navigation

## Dependencies or external command expectations

This completer is static and does not invoke `strings` during completion.

It only depends on:

- PowerShell native argument completer support
- local filesystem access for operand completion

## Usage / loading example

```powershell
. .\strings_completer.ps1

strings -<TAB>
strings -b <TAB>
strings -f <TAB>
strings -n <TAB>
strings .\<TAB>
```

## Limitations / notes

- The completer follows the validated local `/?` help surface; it does not treat `--help` as a supported switch.
- Numeric hints are examples, not validation rules.
