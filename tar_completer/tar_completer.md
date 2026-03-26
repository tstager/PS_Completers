# tar completer

## What it completes / overview

`tar_completer.ps1` registers a native PowerShell completer for `tar` and `tar.exe`.

It is tailored to the local Windows `bsdtar` implementation and combines:

- mode-first completion for `-c`, `-r`, `-t`, `-u`, and `-x`
- common and mode-specific short/long options
- archive and directory path completion for `-f` and `-C`
- file/directory operand completion in create/append/update modes
- pattern hints for list/extract modes
- value hints for `--format` and `--mtime`

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName 'tar', 'tar.exe' -ScriptBlock { ... }
```

Load it into the current session with:

```powershell
. .\tar_completer.ps1
```

## How completion works

### Initialization

On first use, the script creates `$script:TarCompletionCatalog` and:

- verifies `tar.exe` is available
- seeds a static catalog aligned with the local `bsdtar --help` output and relevant `bsdtar` documentation
- loads `--help` once to confirm format/value hints such as `--format`
- prepares small hint sets for `--mtime` and archive-entry patterns

### Mode-aware parsing

`bsdtar` requires the first option to be a mode specifier, so the completer treats:

- `-c` / `--create`
- `-r` / `--append`
- `-t` / `--list`
- `-u` / `--update`
- `-x` / `--extract`

as the root of the command grammar. It also understands the historical bundled short form without a leading dash for common cases such as `tar cf archive.tar`.

Before a mode is chosen, completion focuses on mode tokens and `--help`.

After a mode is chosen, the completer offers:

- common options such as `-f`, `-b`, `-v`, `-w`
- create/update options such as `--format`, `--exclude`, `--mtime`, `-C`, `-z`, `-j`, `-J`
- extract options such as `-k`, `-m`, `-O`, `-p`

### Value-aware completion

The completer routes to specific value completion for:

- `-f` / `--file` → archive path
- `-C` / `--directory` → directory path
- `--format` → `ustar`, `pax`, `cpio`, `shar`
- `--mtime` → date/timestamp hints
- `--exclude` / `--include` → pattern hints plus path suggestions

It also understands compact forms such as `-cf`, `-xf`, and attached-value prefixes well enough to complete the value after the short option.

### Operand completion

In create/append/update modes, non-option operands complete as filesystem paths.

If the current operand starts with `@`, the completer treats it as the documented `@<archive>` form and completes the archive path after the `@`.

In list/extract modes, trailing operands are archive-entry patterns rather than filesystem paths, so the completer switches to wildcard-friendly pattern hints instead of normal path completion.

## Dependencies or external command expectations

This completer expects:

- `tar.exe` to be available
- the local `bsdtar --help` surface to stay broadly consistent
- local filesystem access for archive/file/directory completion

## Usage / loading example

```powershell
. .\tar_completer.ps1

tar <TAB>
tar -c <TAB>
tar -cf <TAB>
tar -c --format <TAB>
tar -c @<TAB>
tar -x -f archive.tar <TAB>
```

## Limitations / notes

- The completer targets the local Windows `bsdtar` help surface, not GNU tar.
- List/extract pattern completion uses generic wildcard hints rather than enumerating archive contents.
- The script includes useful long-option aliases from `bsdtar` documentation, but it does not attempt to expose the entire upstream manpage surface.
