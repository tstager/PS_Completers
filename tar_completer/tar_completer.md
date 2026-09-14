# tar completer

## What it completes / overview

`tar_completer.ps1` registers a native PowerShell completer for `tar` and `tar.exe`.

It models whichever `tar` `Get-Command` resolves first. Two builds usually coexist on Windows: the libarchive `bsdtar` in `System32` and Git for Windows' GNU tar. The completer runs `tar --version` once per session and picks the flavor:

- `bsdtar`: the static catalog below, verified against `bsdtar 3.8.8`
- `GNU tar`: a catalog parsed live from `tar --help` (modes, every option with its description, `--format` values, `--quoting-style` styles), because GNU tar rejects roughly a third of the bsdtar spellings (`--cd`, `--norecurse`, `--fast-read`, `--newer-than`, ...) and adds modes of its own

It combines:

- mode-first completion for `-c`, `-r`, `-t`, `-u`, and `-x` (plus `-A`/`--catenate`, `--delete`, `-d`/`--diff`, `--test-label` under GNU tar)
- common and mode-specific short/long options
- archive and directory path completion for `-f` and `-C`
- file/directory operand completion in create/append/update modes
- pattern hints for list/extract modes
- value hints for `--format` and `--mtime`

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName 'tar', 'tar.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Tar -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it into the current session with:

```powershell
. .\tar_completer.ps1
```

## How completion works

### Initialization

On first use, the script creates `$script:TarCompletionCatalog` and:

- verifies `tar.exe` is available and remembers its resolved path
- runs `tar --version` once to decide between the `bsdtar` and `GNU tar` flavors
- for `bsdtar`, seeds a static catalog aligned with the local `bsdtar --help` output and relevant `bsdtar` documentation
- for `GNU tar`, parses `tar --help` into the same spec shape: value kinds are inferred from the placeholders (`FILE`, `DIR`, `DATE-OR-FILE`, `NUMBER`, `FORMAT`, `PATTERN`, `PROG`, ...), `[=VALUE]` options are marked optional so they never swallow the next token, and enum placeholders (`ORDER`, `METHOD`, `STYLE`, `CONTROL`, `TYPE`) get their documented value sets
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

- common options such as `-f`, `-b`, `-v`, `-w`, `-C`, `--exclude`, `--include`, `-T`, `-X`, `--strip-components`, `--newer*`/`--older*`, `--uid`/`--gid`/`--uname`/`--gname`, `--options`, `--passphrase`
- create/update options such as `--format`, `--posix`, `--mtime`, `--clamp-mtime`, `-L`, `--one-file-system`, `--owner`/`--group`
- compression options (`-z`, `-j`, `-J`, `--lzma`, `--zstd`, `--lz4`, `--lzop`, `-Z`, `-I`) in create, list, and extract mode, where `bsdtar` accepts them
- extract options such as `-k`, `-m`, `-O`, `-p`, `-U`, `--acls`/`--xattrs`/`--fflags`

Every option's mode set was verified against the live `bsdtar 3.8.8` binary (`tar -<mode> <option> -f nonexist.tar` fails on the archive, not on the option), so options appear only in the modes that accept them. `--help` and `--version` are offered in every slot.

### Value-aware completion

The completer routes to specific value completion for:

- `-f` / `--file`, `-T`, `-X`, `--newer-than`, `--older-than` → file path
- `-C` / `--directory` → directory path
- `--format` → the 18 formats this libarchive build accepts (`ustar`, `pax`, `paxr`, `cpio`, `odc`, `newc`, `shar`, `shardump`, `gnutar`, `v7tar`, `bsdtar`, `mtree`, `zip`, `7zip`, `iso9660`, `xar`, `raw`, `warc`)
- `--mtime`, `--newer`, `--older`, `--newer-mtime`, `--older-mtime` → date hints in the forms `bsdtar` parses (`yyyy-MM-dd`, `"yyyy-MM-dd HH:mm:ss"`, `@<unix-epoch>`), computed at completion time
- `--strip-components` → `1`, `2`, `3`; `-I` → common compression program names
- `--exclude` / `--include` → pattern hints plus path suggestions

A quoted path that is still open (`tar -c -f "C:\Program Fi<Tab>`) is tokenized as one value and completes inside the quoted directory.

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

- Under GNU tar the option surface is only as complete as `tar --help`; options are not mode-gated there, and GNU's `-L` is the numeric `--tape-length`, not bsdtar's `--dereference`.
- List/extract pattern completion uses generic wildcard hints rather than enumerating archive contents.
- The catalog covers the options verified against the installed `bsdtar 3.8.8`; macOS-only options (`--mac-metadata`, `--hfsCompression`, `--nodump`) and `-s` (rejected by this build) are deliberately left out.
