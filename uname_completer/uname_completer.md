# uname completer

## What it completes / overview

uname_completer.ps1 registers a standalone native PowerShell completer for uname and uname.exe.

It is a help-driven completer with a static fallback for the uname command surface. The script exposes the supported option catalog; uname accepts no operands, so the completer never offers filesystem paths.

The completer covers:

- option-name suggestions for the supported short and long flags
- the option catalog in the empty slot after `uname ` or a flag, since the tool has no operands
- clustered short flags: `uname -sn` extends to `-sna`, `-snr`, `-snm`, ... for each flag not yet in the cluster
- a simple import-safe registration shape that can be loaded directly in PowerShell

Representative options include (parsed from the installed build's `--help`):

- `-a`
- `--all`
- `-p`
- `-i`
- `-s`
- `--kernel-name`
- `-n`
- `--nodename`
- `-r`
- `--kernel-release`
- `-v`
- `--kernel-version`
- `-m`
- `--machine`
- `--processor`
- `--hardware-platform`
- `-o`
- `--operating-system`
- `--help`
- `--version`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'uname', 'uname.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Uname -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\uname_completer\uname_completer.ps1
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
- `Usage: uname [OPTION]...` has no operand, so an empty word returns the whole option catalog (which also keeps PowerShell's filename fallback away) and a typed non-option word returns nothing.
- A single-dash word made only of known short flags (`-sn`) is treated as a getopt cluster and completed by appending each remaining short flag.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The help invocation pipes `$null` into the tool so it cannot wait on standard input, and the cache probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
uname -
uname --
```

Expected behavior:

- `-` and `--` prefixes show matching option suggestions with descriptions taken from the tool's help
- `uname ` and `uname -a ` list the option catalog instead of files; `uname -sn` offers cluster extensions
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the core uname option surface; there is no operand slot to complete.
- The implementation stays aligned with the repository's import-safe completer pattern.
