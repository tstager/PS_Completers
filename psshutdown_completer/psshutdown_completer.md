# psshutdown completer

## What it completes / overview

`psshutdown_completer.ps1` registers a native PowerShell argument completer for `psshutdown` and `psshutdown.exe`.

The completer is static-first and non-destructive. It never probes remote systems. It layers known actions, documented switches, placeholder values, and safe local `@file` path completion on top of the PsShutdown syntax surface; the only live read is the `-e` reason-code table described below.

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName 'psshutdown', 'psshutdown.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsShutdown -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
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
- `-accepteula`

Once an action or switch has already been used, it is generally hidden from later blank-position completion results so the list stays focused. Switches remain available after a remote target has been typed; only the target placeholders stop repeating. Only tokens that end before the cursor count as used, so completing inside an earlier token on the line sees the same context as typing it fresh.

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
- `-e` suggests every reason code from the "Reasons defined on this computer" table that `psshutdown -nobanner -?` prints (for example `u:2:17`, `p:7:0`), with each title as the tooltip, plus a `[u|p]:xx:yy` placeholder; it falls back to five common samples (`u:0:0`, `p:0:0`, `u:2:18`, `p:2:17`, `p:4:2`) when the tool is absent or its EULA is not yet accepted
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

The documented `\\computer[,computer[,...]]` list form is not modelled: PowerShell splits a native argument at `,` before the completer runs, so the list is never seen as one word.

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

`@file` completion is local-only and uses `Get-ChildItem` to suggest matching files and directories from the current path context. Directory candidates end in a separator, and a word that ends in a separator (`@docs\`, `"@C:\Program Files\`) lists that directory's contents, so repeated Tab descends the tree. This is purely path completion; it does not inspect the file contents.

Each candidate is inserted as one quoted argument (`'@sp ace.txt'`), because a bare `@name` is splatting syntax. The directory part you typed (`.\`, `../`, `C:`) is kept exactly as typed, and in a comma list only the item after the last comma is completed. The quote you typed is kept (`'`, `"`, or a typographic quote), single quotes are the default, and the characters that quote style treats specially are escaped. When a bare `@` is followed by a path that does not start a variable name (`@.\`), PowerShell leaves the `@` as a separate, unparseable token; the candidate is then `('@.\hosts.txt')`, which turns the line into `@('@.\hosts.txt')` and passes `@.\hosts.txt` as one argument.

### Freeform value suppression

PsShutdown accepts freeform text for values like passwords and shutdown messages. Without a native completer, PowerShell tends to fall back to filesystem completion in these slots. This script suppresses that behavior by returning placeholder or echo completions for the active value context.

## Dependencies or external command expectations

Everything except the `-e` value list is static.

It depends on:

- PowerShell's native argument completer support
- local filesystem access when completing `@file` paths
- for `-e` only: `psshutdown` on `PATH`, run once per session as `psshutdown -nobanner -?` (stdin closed, 5 s timeout, ANSI stripped, about 250 ms cold and 35 ms warm). It is started only when `HKCU:\Software\Sysinternals\PsShutdown\EulaAccepted` is 1, so completion can never raise the first-run EULA dialog; the EULA check is not cached, so accepting it later takes effect without reloading. A missing tool is cached for the session.

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
