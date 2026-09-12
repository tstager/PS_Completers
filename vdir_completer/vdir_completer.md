# vdir completer

## What it completes / overview

vdir_completer.ps1 registers a standalone native PowerShell completer for vdir and vdir.exe.

It is a help-driven completer with a static fallback for the vdir command surface. The script exposes the supported option catalog and falls back to filesystem path completion for operand slots.

The completer covers:

- option-name suggestions for the supported short and long flags
- operand completion for file or path-like arguments
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-cftuvSUX`
- `--sort`
- `-a`
- `--all`
- `-A`
- `--almost-all`
- `--author`
- `-l`
- `-b`
- `--escape`
- `--block-size`
- `-B`
- `--ignore-backups`
- `-c`
- `-C`
- `--color`
- `-d`
- `--directory`
- `-D`
- `--dired`
- `-f`
- `-aU`
- `-ls`
- `-F`
- `--classify`
- `--file-type`
- `--format`
- `-x`
- `-m`
- `-1`
- `--full-time`
- `--time-style`
- `-g`
- `--group-directories-first`
- `-G`
- `--no-group`
- `-h`
- `--human-readable`
- `-s`
- `--si`
- `-H`
- `--dereference-command-line`
- `--dereference-command-line-symlink-to-dir`
- `--hide`
- `--hyperlink`
- `--indicator-style`
- `-i`
- `--inode`
- `-I`
- `--ignore`
- `-k`
- `--kibibytes`
- `-L`
- `--dereference`
- `-n`
- `--numeric-uid-gid`
- `-N`
- `--literal`
- `-o`
- `-p`
- `-q`
- `--hide-control-chars`
- `--show-control-chars`
- `-Q`
- `--quote-name`
- `--quoting-style`
- `-r`
- `--reverse`
- `-R`
- `--recursive`
- `--size`
- `-S`
- `--time`
- `-t`
- `-T`
- `--tabsize`
- `-u`
- `-U`
- `-v`
- `-w`
- `--width`
- `-X`
- `-Z`
- `--context`
- `--append-exe`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'vdir', 'vdir.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Vdir -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\vdir_completer\vdir_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Option names come from the installed tool's `--help` output, parsed once per session and cached in script scope. A static fallback list is used when the tool is not installed. The description text of each help line becomes the completion tooltip.
- Option matching is case-sensitive, so case-distinct short options such as `-d` and `-D` are both offered.
- Value-bearing options complete their documented values in the separate form (`--opt value`), the attached form (`--opt=value`) and for a partially typed value. Path-valued options use the script's own path completion. See the table below.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Option values

- `--block-size`: `K`, `M`, `G`, `KB`, `MB`, `GB`
- `--color`, `--hyperlink`: `always`, `auto`, `never`
- `--format`: `across`, `commas`, `horizontal`, `long`, `single-column`, `verbose`, `vertical`
- `--hide`, `-I`, `--ignore`: `<pattern>`
- `--indicator-style`: `none`, `slash`, `file-type`, `classify`
- `--quoting-style`: `literal`, `locale`, `shell`, `shell-always`, `shell-escape`, `shell-escape-always`, `c`, `escape`
- `--sort`: `none`, `size`, `time`, `version`, `extension`, `width`
- `--time`: `atime`, `access`, `use`, `ctime`, `status`, `birth`, `creation`
- `--time-style`: `full-iso`, `long-iso`, `iso`, `locale`
- `-T`, `--tabsize`, `-w`, `--width`: `<cols>`

## Representative validation scenarios

```powershell
vdir -
vdir --
vdir --block-size 
vdir --block-size=
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `--block-size` shows its documented values in both the separate and the attached form
- operand slots offer filesystem completion
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the core vdir option surface and the standard operand fallback.
- The implementation stays aligned with the repository's import-safe completer pattern.
