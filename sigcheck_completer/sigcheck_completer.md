# sigcheck completer

## What it completes / overview

`sigcheck_completer.ps1` registers a native PowerShell completer for `sigcheck` and `sigcheck.exe`.

The completer is mode-aware and static-first:

- it covers the validated local help surface, including `-?` and `/?`
- it distinguishes the main Sigcheck modes:
  - normal file scan
  - `-d` catalog dump
  - `-o` offline VirusTotal CSV lookup
  - `-t`, `-tu`, `-tv`, `-tuv` certificate-store dump modes
- it keeps file and directory operands path-aware
- it adds safe local certificate-store-name hints

## Registration and command names

- Registers with `Register-ArgumentCompleter -Native`
- Command names: `sigcheck`, `sigcheck.exe`
- The script enables `Set-StrictMode -Version 2.0`

Load it with:

```powershell
. .\sigcheck_completer.ps1
```

## How completion works

### Switch completion

The script completes the validated switches:

- `-a`
- `-accepteula`
- `-c`
- `-ct`
- `-d`
- `-e`
- `-f`
- `-h`
- `-i`
- `-l`
- `-m`
- `-n`
- `-o`
- `-p`
- `-q`
- `-r`
- `-s`
- `-t`
- `-tu`
- `-tv`
- `-tuv`
- `-u`
- `-v`
- `-vr`
- `-vs`
- `-vrs`
- `-vt`
- `-w`
- `-nobanner`
- `-?`

Sysinternals accepts `/x` for every `-x` switch, so a word starting with `/`
completes the whole catalog in its slash spelling (`/a`, `/nobanner`, `/?`, ...)
and a `/x` already on the line is normalised to `-x` for mode detection. The
slash forms are offered only once the typed word starts with `/`.

### Value-aware slots

The completer handles the main separate-value switches:

- `-f` -> catalog-file path completion, restricted to `.cat` / `.cab` files, with
  the two `%SystemRoot%\System32\CatRoot` store folders seeded in
- `-p` -> policy GUID or policy-file hints
- `-w` -> output-file path completion

### Mode-aware positional completion

The trailing positional slot changes by mode:

- default mode -> file or directory to inspect
- `-d` -> catalog file or directory, restricted to `.cat` / `.cab` files
- `-o` -> previously captured Sigcheck CSV file, restricted to `.csv`
- `-t*` -> certificate store name or `*`

Directories are always kept so the tree stays navigable; only the file kinds the
option accepts are listed. Store names that contain spaces (`AAD Token Issuer`,
`Local NonRemovable Certificates`) are emitted quoted, so accepting one produces
a single operand.

For certificate-store modes, the completer reads store names from:

- `Cert:\LocalMachine` for `-t` and `-tv`
- `Cert:\CurrentUser` for `-tu` and `-tuv`

If provider access fails, the completer falls back to a small built-in store list.

## Dependencies or external command expectations

This completer does not invoke `sigcheck` during completion.

It only depends on:

- PowerShell native argument completer support
- local filesystem access for file/path positions
- local certificate provider access for store-name hints

## Usage / loading example

```powershell
. .\sigcheck_completer.ps1

sigcheck -<TAB>
sigcheck -f .\<TAB>
sigcheck -t <TAB>
sigcheck -tu <TAB>
sigcheck -o .\<TAB>
sigcheck .\<TAB>
```

## Limitations / notes

- The completer does not perform any VirusTotal queries.
- Policy completion uses a placeholder/sample GUID plus local path hints rather than live policy discovery.
- Store-name hints are local-only.
- The cursor is rebased on the command's start offset before tokenizing, so a mid-line cursor is classified from the text to its left.
