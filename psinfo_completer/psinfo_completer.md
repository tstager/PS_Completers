# psinfo completer

## What it completes / overview

`psinfo_completer.ps1` registers a standalone native completer for `psinfo` and `psinfo.exe`.

The implementation is static-first and side-effect free. It does not query remote systems or inspect live PsInfo output during completion. Instead it focuses on the high-value syntax surface:

- remote computer placeholders
- `@file` path completion
- remote-auth placeholders
- delimiter hints for `-t`
- sample field-filter hints for the optional `filter` positional argument

## Covered syntax

The completer covers the validated help surface:

- `-u`, `-p`
- `-h`, `-s`, `-d`
- `-c`, `-t`
- `-nobanner`
- `-?`, `/?`

`-t` is only suggested after `-c` because the delimiter only applies to CSV mode.

## Key behaviors

- Remote targets:
  - `\\<computer>`
  - `\\localhost`
  - `\\*`
  - `@file`
- `@file` completion is local-only and path-aware
- `-u` and `-p` return placeholder values rather than filesystem fallback
- `-t` suggests delimiter samples including `,`, `;`, `|`, `:`, and `\t`
- the optional `filter` slot suggests representative field names such as `uptime`, `memory`, and `service pack`

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('psinfo', 'psinfo.exe') -ScriptBlock { ... }
```

## Limitations / notes

- Filter hints are samples only; they are not exhaustive field discovery.
- Remote computer discovery is intentionally not attempted.

