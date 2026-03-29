# psexec completer

## What it completes / overview

`psexec_completer.ps1` registers a standalone native PowerShell completer for `psexec` and `psexec.exe`.

The implementation is intentionally static-first and side-effect free:

- it completes the documented remote-target preamble with `\\computer` and `@file` placeholders
- it offers placeholder values for remote-auth, timeout, service-name, session, processor-group, and affinity slots
- it keeps command-tail completion conservative so remote execution is never probed during completion
- when `-c` is present, it allows local executable and path completion for the command slot because that value names the local file PsExec copies before execution

## Registration and command names

The script registers:

```powershell
Register-ArgumentCompleter -Native -CommandName @('psexec', 'psexec.exe') -ScriptBlock { ... }
```

Load it into the session with:

```powershell
. .\psexec_completer.ps1
```

## How completion works

### Remote preamble

Before the command slot is chosen, the completer suggests safe remote-target forms:

- `\\<computer>`
- `\\localhost`
- `\\*`
- `@file`

When the current token starts with `@`, completion switches to local path completion for the file portion while preserving the `@` prefix.

### Switches and value slots

The completer covers the locally validated help surface, including:

- `-u`, `-p`, `-n`, `-r`
- `-h`, `-l`, `-s`, `-e`, `-x`, `-i`
- `-c`, `-f`, `-v`, `-w`, `-d`
- `-g`, `-a`, `-arm`, `-verbose`
- `-accepteula`, `-nobanner`
- priority switches: `-low`, `-belownormal`, `-abovenormal`, `-high`, `-realtime`, `-background`
- help aliases: `-?`, `/?`

Value-aware slots return placeholders or sample values instead of falling back to filesystem completion:

- `-u` -> `<username>`, `<domain\user>`
- `-p` -> `<password>`
- `-n` -> timeout samples
- `-r` -> `PSEXESVC`, `<service-name>`
- `-i` -> session samples
- `-w` -> `<remote-directory>`
- `-g` -> processor-group samples
- `-a` -> CPU-affinity samples

### Command slot handling

Without `-c`, the command and later arguments are treated conservatively:

- the first command slot returns placeholder/echo results such as `<command>`
- later arguments return placeholder/echo results such as `<argument>`

That suppresses generic filesystem fallback without pretending the local machine knows the remote command environment.

With `-c`, the first command slot uses local executable/path completion because the argument names the local program or script PsExec copies to the target system.

## Dependencies or external command expectations

The completer is non-enumerating and does not call `psexec` at completion time.

It only uses:

- local filesystem access for `@file` and `-c` path completion
- `Get-Command` to suggest local applications when `-c` is active

## Limitations / notes

- Remote targets are placeholders only; there is no host discovery.
- Remote directories, commands, and argument tails are intentionally not enumerated.
- `-f` and `-v` are only suggested after `-c`, matching their documented relationship to copy mode.

