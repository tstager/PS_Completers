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
- `-nobanner`, `-accepteula`
- `-?`, `/?`

`-t` is only suggested after `-c` because the delimiter only applies to CSV mode.

## Key behaviors

- Remote targets:
  - `\\<computer>`
  - `\\localhost`
  - `\\*`
  - `@file`
- `@file` completion is local-only and path-aware
- `-u` and `-p` return placeholder values for an empty word and echo a partially typed value otherwise, rather than falling back to the filesystem
- `-t` suggests the delimiters `,`, `;`, `|`, `:` and `\t`; all but `\t` are emitted double-quoted because they are PowerShell syntax when bare
- the optional `filter` slot suggests the field-label prefixes PsInfo v1.79 actually prints (`uptime`, `kernel version`, `product type`, `product version`, `service pack`, `kernel build number`, `registered organization`, `registered owner`, `ie version`, `system root`, `processors`, `processor speed`, `processor type`, `physical memory`, `video driver`); multi-word labels are quoted
- only tokens that end before the cursor count as consumed, so editing an earlier token on the line completes that token

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('psinfo', 'psinfo.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-PsInfo -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

## Limitations / notes

- Filter hints are a static list of the labels PsInfo prints; they are not discovered live.
- Remote computer discovery is intentionally not attempted.

