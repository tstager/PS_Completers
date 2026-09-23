# pip completer

## Overview

`pip_completer.ps1` registers a native PowerShell argument completer for `pip`, `pip.exe`, `pip3`, and `pip3.exe`.

It is help-driven with a static fallback. The surface was taken from pip 26.2.1 (`C:\Users\Trent\AppData\Local\Programs\Python\Python314\Scripts\pip.exe`, the first `pip.exe` that `Get-Command` resolves on this machine). The completer does not hard-code that version. Each session parses the help of whichever `pip` the typed name resolves to.

pip ships its own `pip completion --powershell` script. That script redefines the legacy `TabExpansion` function, which PowerShell 7 no longer calls, so it does nothing in `pwsh`. This completer replaces it.

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('pip', 'pip.exe', 'pip3', 'pip3.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Pip -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

Version-specific launchers such as `pip3.14` are not registered. `python -m pip` belongs to the `python` and `py` completers.

## How it works

### Executable resolution

`Resolve-PipExecutable` resolves the typed command name with `Get-Command -CommandType Application`. The result is cached per name and `$env:PATH` value. Activating a virtual environment changes `PATH`, so the venv's `pip` takes over, along with its own help and installed packages.

### Help parsing

`Get-PipHelp` runs `pip --help` for the root and `pip <command> --help` for a command, once per executable and command. `ConvertFrom-PipHelp` reads pip's optparse layout:

- `Commands:` rows become the command list, and their descriptions become tooltips.
- Every `... Options:` section contributes options. A `<metavar>` after the names marks an option that takes a value. The description, joined across wrapped lines, is the tooltip.
- A bracketed choice list in a description (`[auto, on, off, raw]`) becomes that option's value set.
- The `Subcommands:` list under `Description:` supplies the actions of `pip cache` and `pip config`. `pip index versions` is added explicitly, because pip documents it only in its `Usage:` line.

Each pip child process runs through `System.Diagnostics.Process` with the following settings:

- stdin is closed and output is read asynchronously.
- The process gets a 5 second timeout and is killed if it runs past it.
- ANSI escapes are stripped from the output.
- The child environment has `PIP_DISABLE_PIP_VERSION_CHECK=1` (no network), `PIP_NO_INPUT=1`, and `COLUMNS=1000`, so descriptions are not wrapped.

### Static fallback

If no `pip` resolves, the completer falls back to a small static catalog: the 18 commands, the general options, and the `cache` and `config` actions.

## What it completes

| Context | Completions |
|---|---|
| `pip <Tab>`, `pip help <Tab>` | Commands, with descriptions |
| `pip <command> -<Tab>` | The command's options plus the general options. Short flags match case-sensitively, so `-U` and `-u`, `-I` and `-i`, `-C` and `-c`, and `-V` and `-v` stay apart |
| `pip uninstall <Tab>`, `pip show <Tab>` | Installed packages, minus those already on the line |
| `--exclude <Tab>` (`list`, `freeze`) | Installed packages |
| `pip cache <Tab>`, `pip config <Tab>`, `pip index <Tab>` | Actions |
| `pip config get\|set\|unset <Tab>` | `global.` and `<command>.` sections, then `section.option` keys taken from that command's help |
| `pip config set <key> <Tab>` | The key's values: choices, `true`/`false` for switches, or a `<metavar>` placeholder |
| `pip list <Tab>` and other commands without operands | Options |
| `pip install`, `download`, `wheel`, `lock`, `hash` operands | Nothing, so PowerShell's filesystem completion lists local projects, archives and wheels |

The `[global]` config section applies to every command. For that section the completer offers the general options plus `install`'s options, which cover `index-url`, `trusted-host`, `timeout`, `progress-bar` and similar keys, without running every command's help.

### Option values

Values complete in the separate form (`--format json`) and in the attached form (`--format=json`). Attached-form suggestions keep the `--format=` prefix. Unambiguous long-option abbreviations resolve the same way optparse resolves them, so `--upgrade-str <Tab>` works.

| Option | Values | Source |
|---|---|---|
| `--progress-bar`, `--keyring-provider`, `--root-user-action` | as listed in help | parsed `[a, b, c]` |
| `--use-feature`, `--use-deprecated` | pip's current feature names | pip's own `invalid choice ... (choose from ...)` parse error. pip raises it before running anything |
| `list --format` | `columns`, `freeze`, `json` | static (help prose) |
| `cache list --format` | `human`, `abspath` | static (help prose) |
| `--exists-action` | `s`, `i`, `w`, `b`, `a` | static |
| `--upgrade-strategy` | `only-if-needed`, `eager` | static |
| `-a/--algorithm` (`hash`) | `sha256`, `sha384`, `sha512` | static |
| `--implementation` | `cp`, `pp`, `py`, `jy`, `ip` | static |
| `--no-binary`, `--only-binary`, `--all-releases`, `--only-final` | `:all:`, `:none:` | static |
| `--refresh-package` | `:all:` | static |
| `-i/--index-url` | `https://pypi.org/simple` | static |
| `<file>`, `<dir>`, `<path>`, `<path/url>`, `<python>`, `<editor>`, `-f/--find-links` | filesystem | separate form: PowerShell's own path completion. Attached form: the script's path helper, which quotes paths containing spaces |
| anything else (`--platform`, `--python-version`, `--abi`, `--proxy`, ...) | a `<metavar>` placeholder | |

### Installed packages

`Get-PipInstalledPackages` uses pip's own completion protocol. It runs the resolved `pip` with `PIP_AUTO_COMPLETE=1`, `COMP_WORDS='pip show '` and `COMP_CWORD=2`, set on the child process only. That returns the canonical names of the distributions installed in the environment that `pip` runs in, and it respects virtual environments and the user site. The list is not cached, so it is current after every install. It costs one pip start, about 230 ms, per Tab.

## Latency

The first completion in a session for the root or for a command costs one pip start, about 250-450 ms. After that, the parsed help is cached and completion takes under 15 ms.

## Placeholder-only slots

These slots are never enumerated, because the data is remote:

- `pip search <query>`
- `pip index versions <package>`
- `pip cache list|remove <pattern>`
- free-form option values such as `--platform` and `--abi`

Requirement specifiers for `install` and `download` are also not enumerated. Those operand slots use filesystem completion instead.

## Usage

```powershell
. .\pip_completer\pip_completer.ps1

pip <TAB>
pip install --upgrade-strategy <TAB>
pip install --progress-bar=<TAB>
pip uninstall cl<TAB>
pip config set global.index-url <TAB>
pip install --target=.\ven<TAB>
```
