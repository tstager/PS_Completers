# wsl completer

## What it completes / overview

`wsl_completer.ps1` registers a native PowerShell completer for `wsl`.

This is a lightweight, mostly static completer. It offers:

- a fixed set of common top-level `wsl` subcommands,
- a fixed set of common options,
- runtime distro-name completion for a few distro-related arguments,
- and a single hard-coded user suggestion for `root`.

## Registration and command names

The script registers a native completer for:

- `wsl`

Registration is done with:

```powershell
Register-ArgumentCompleter -Native -CommandName wsl -ScriptBlock $WslCompleter
```

The script checks `Get-Command wsl` before returning completions. It does not separately register `wsl.exe`.

## How completion works

### 1. Command availability check

At the start of each completion request, the script verifies that `wsl` is available:

```powershell
Get-Command wsl -ErrorAction SilentlyContinue
```

If the command is missing, the completer returns nothing.

### 2. Simple token parsing

The script tokenizes the current command line with a regular expression and inspects the immediately previous token.

Completion decisions are based on that previous token rather than on a deeper command tree.

### 3. Static suggestion lists

The script keeps two static lists.

#### Subcommands

- `--list`
- `--set-default`
- `--set-version`
- `--install`
- `--update`
- `--shutdown`
- `--help`
- `--version`

#### Options

- `-d`, `--distribution`
- `-e`, `--exec`
- `-u`, `--user`
- `-c`, `--command`
- `--cd`, `--workingdir`

### 4. Contextual value completion

The script has special cases for a few previous tokens.

#### Distribution completion

After any of these tokens, the completer runs `wsl -l -q` and returns the discovered distro names:

- `-d`
- `--distribution`
- `--set-default`
- `--set-version`

#### User completion

After either of these tokens, the completer returns only `root`:

- `-u`
- `--user`

### 5. Default completion behavior

If no special case applies, the completer returns the combined static subcommand and option list.

## Key completion behaviors / supported values

### Top-level suggestions

By default, the completer offers the combined list of subcommands and options shown above.

### Distro suggestions from the installed WSL configuration

For distro-related arguments, suggestions come from the current output of:

```powershell
wsl -l -q
```

That keeps distro-name completion aligned with the distributions installed on the machine.

### Hard-coded `root` user suggestion

The script does not enumerate users inside a distribution. It only suggests `root` for `-u` and `--user`.

## Dependencies or external command expectations

This completer expects `wsl` to be available.

Runtime distro completion depends on:

```powershell
wsl -l -q
```

If that command fails or returns nothing, distro suggestions will also be empty.

## Usage / loading example

Dot-source the script:

```powershell
. .\wsl_completer.ps1
```

Example completion scenarios:

```powershell
wsl <TAB>
wsl --set-default <TAB>
wsl -d <TAB>
wsl --user <TAB>
```

## Limitations / notes

- The script only covers a small set of common subcommands and options.
- It does not complete version numbers for `--set-version`.
- It does not complete paths for `--cd` or `--workingdir`.
- It does not complete command text for `-c`, `--command`, `-e`, or `--exec`.
- It is registered for `wsl`, not `wsl.exe`.
- All returned suggestions are emitted through a simple filter against `$wordToComplete`; there is no deeper parsing of nested command structure.

