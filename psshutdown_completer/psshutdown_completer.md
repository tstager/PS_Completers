# psshutdown completer

## What it completes / overview

`psshutdown_completer.ps1` registers a native PowerShell argument completer for `psshutdown` and `psshutdown.exe`.

The completer is intentionally static and non-destructive. It does not probe remote systems or call `psshutdown` at completion time. Instead, it layers known actions, documented switches, placeholder values, and safe local `@file` path completion on top of the PsShutdown syntax surface.

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName 'psshutdown', 'psshutdown.exe' -ScriptBlock { ... }
```

Load it into the current session with:

```powershell
. .\psshutdown_completer.ps1
```

## How completion works

### Top-level option and action completion

At the start of the command, and whenever the current token starts with `-`, the completer offers the PsShutdown action switches:

- `-s`
- `-r`
- `-h`
- `-d`
- `-k`
- `-a`
- `-l`
- `-o`
- `-x`

It also offers the other documented switches:

- `-f`
- `-c`
- `-t`
- `-v`
- `-e`
- `-m`
- `-u`
- `-p`
- `-n`
- `-nobanner`

Once an action or switch has already been used, it is generally hidden from later blank-position completion results so the list stays focused.

### Value-aware option handling

The completer tracks the options that take a separate value:

- `-t`
- `-v`
- `-e`
- `-m`
- `-u`
- `-p`
- `-n`

When one of those options is the active value slot, completion returns value-specific suggestions instead of falling back to unrelated filesystem entries.

Examples:

- `-t` suggests countdown/time samples such as `20`, `30`, `60`, `300`, `1:00`, and `23:00`, plus a `<seconds-or-h:mm>` placeholder
- `-v` suggests numeric display durations such as `0`, `5`, `10`, and `30`
- `-e` suggests common reason-code samples such as `u:0:0` and `p:0:0`, plus a `[u|p]:xx:yy` placeholder
- `-m` returns a message placeholder: `"<message>"`
- `-u` returns username-oriented placeholders/examples such as `<username>` and `<domain\user>`
- `-p` returns a `<password>` placeholder
- `-n` suggests common connection timeout values such as `5`, `10`, `30`, and `60`

For freeform slots like `-m` and `-p`, if you already typed a custom value the completer echoes that current token back as the completion result so PowerShell does not fall back to local file completion.

### Remote target completion

When the current token is in the remote target position, the completer offers safe static target shapes instead of attempting live enumeration:

- `\\computer`
- `\\*`
- `@file`

It also handles comma-separated target lists in the documented form:

```text
\\computer[,computer[,...]]
```

When the current token starts with `@`, the completer switches to local path completion for the file portion while preserving the `@` prefix.
In interactive PowerShell, you will usually want to type the token as `"@...` so PowerShell does not interpret bare `@` as splatting syntax before the native completer runs.

## Key completion behaviors / supported values

### Actions

The completer covers the locally confirmed PsShutdown actions:

- `-s` shutdown without poweroff
- `-r` reboot
- `-h` hibernate
- `-d` suspend
- `-k` power off
- `-a` abort
- `-l` lock
- `-o` log off
- `-x` turn monitor off

### Other switches

The completer covers the locally confirmed switches:

- `-f`
- `-c`
- `-t`
- `-v`
- `-e`
- `-m`
- `-u`
- `-p`
- `-n`
- `-nobanner`

### Path-aware `@file` handling

`@file` completion is local-only and uses `Get-ChildItem` to suggest matching files and directories from the current path context. This is purely path completion; it does not inspect the file contents.

### Freeform value suppression

PsShutdown accepts freeform text for values like passwords and shutdown messages. Without a native completer, PowerShell tends to fall back to filesystem completion in these slots. This script suppresses that behavior by returning placeholder or echo completions for the active value context.

## Dependencies or external command expectations

This completer is static and does not require invoking `psshutdown` at completion time.

It only depends on:

- PowerShell's native argument completer support
- local filesystem access when completing `@file` paths

## Usage / loading example

```powershell
. .\psshutdown_completer.ps1

psshutdown <TAB>
psshutdown -<TAB>
psshutdown -t <TAB>
psshutdown -e <TAB>
psshutdown -u Administrator -p <TAB>
psshutdown \\<TAB>
psshutdown "@<TAB>
```

## Validation notes

The intended validation path is a clean PowerShell 7 session using `pwsh -NoProfile` and `TabExpansion2`, so the registered native completer behavior is tested the same way users hit it interactively.

## Limitations / notes

- The completer intentionally avoids live remote computer discovery.
- `\\computer` and `\\*` are placeholders, not enumerated network results.
- The script assumes the documented syntax shape where the remote target is a single positional target argument or `@file`.
- `@file` completion is path-aware, but the completer does not validate file readability or contents.
- In PowerShell syntax, bare `@file` text can be parsed as splatting-related input before native completion runs, so quoting the argument (for example `"@servers.txt"`) gives the most reliable completion experience.
