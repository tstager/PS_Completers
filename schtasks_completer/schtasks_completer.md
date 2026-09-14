# schtasks completer

## What it completes / overview

`schtasks_completer.ps1` registers a native argument completer for `schtasks` and `schtasks.exe`.

It is primarily help-driven: the script parses `schtasks.exe /?` and subcommand help text to discover top-level subcommands and per-subcommand option tokens. It supplements that with targeted value completion for common option values, task names, and paths.

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName 'schtasks', 'schtasks.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Initialize-SchtasksCompletionCatalog

    $line = $commandAst.ToString()
    $currentWord = if ([string]::IsNullOrWhiteSpace($wordToComplete)) {
        Get-SchtasksCurrentToken -Line $line -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    } else {
        $wordToComplete
    }

    # Only elements that end before the cursor are consumed, so completing inside an
    # earlier token sees the same context as typing it fresh.
    $tokensBeforeCurrent = @(
        $commandAst.CommandElements |
            Select-Object -Skip 1 |
            Where-Object { $_.Extent.EndOffset -lt $cursorPosition } |
            ForEach-Object { $_.Extent.Text }
    )

    $activeSubcommand = Get-SchtasksActiveSubcommand -Tokens $tokensBeforeCurrent -KnownSubcommands $script:SchtasksCompletionCatalog.Subcommands
    $expectedValueOption = Get-SchtasksExpectedValueOption -TokensBeforeCurrent $tokensBeforeCurrent -KnownSubcommands $script:SchtasksCompletionCatalog.Subcommands

    if ($expectedValueOption) {
        $slot = Get-SchtasksValueSlot -Subcommand $activeSubcommand -Option $expectedValueOption
        $yieldsToSwitch = $slot -and $slot.ContainsKey('Optional') -and $slot.Optional -and $currentWord.StartsWith('/')
        if ($slot -and -not $yieldsToSwitch) {
            # A value slot is terminal: never fall through to the option-name list.
            return @(Get-SchtasksValueSlotCompletionList -Slot $slot -Option $expectedValueOption -Subcommand $activeSubcommand -CurrentWord $currentWord -TokensBeforeCurrent $tokensBeforeCurrent)
        }
    }

    if (-not $activeSubcommand) {
        $topSuggestions = @($script:SchtasksCompletionCatalog.Subcommands + '/?')
        if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('/')) {
            return $topSuggestions |
                Sort-Object -Unique |
                Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*') } |
                ForEach-Object {
                    New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
                }
        }

        return @()
    }

    if ([string]::IsNullOrWhiteSpace($currentWord) -or $currentWord.StartsWith('/')) {
        $optionKey = $activeSubcommand.ToLowerInvariant()
        $suggestions = @()

        if ($script:SchtasksCompletionCatalog.OptionTokensByKey.ContainsKey($optionKey)) {
            $suggestions = @($script:SchtasksCompletionCatalog.OptionTokensByKey[$optionKey])
        }

        return $suggestions |
            Sort-Object -Unique |
            Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($currentWord) + '*') } |
            ForEach-Object {
                New-SchtasksCompletionResult -CompletionText $_ -ResultType 'ParameterName' -ToolTip $_
            }
    }

    @()
}
```

Load it into the current session with:

```powershell
. .\schtasks_completer.ps1
```

## How completion works

### Initialization

On first use, the script initializes `$script:SchtasksCompletionCatalog` by:

- running `schtasks.exe /?`
- parsing the `Parameter List:` section to discover top-level tokens
- treating the discovered top-level tokens except `/?` as subcommands
- running `schtasks.exe <subcommand> /?` for each discovered subcommand
- parsing each subcommand help page to collect its option tokens
- loading a small static table of value hints for selected options

This initialization happens once per session.

### Subcommand-aware completion

The completer inspects command tokens to determine the active subcommand. Before any subcommand is chosen, it offers:

- discovered subcommands
- `/?`

After a subcommand is present, it offers only the option tokens collected for that subcommand.

### Value-aware completion

When the previous token is an option that expects a value, the script switches to value completion instead of more option names.

A per-subcommand value-slot table (`Get-SchtasksValueOptionTable`) decides how each value-bearing option completes, and a value slot is terminal: option names are never offered where a value is required. The table covers:

- `/TN` task names (a `<path\taskname>` placeholder under `/Create`)
- `/TR` path completion
- `/XML` path completion restricted to `.xml` files under `/Create`; the `ONE` hint under `/Query`, where the help documents `[xml_type]`
- `/I` as `<idle-minutes>` under `/Create` and as a bare switch under `/Run`
- `/MO` modifiers parsed from the `Modifiers:` block of the `/Create` help and selected by the `/SC` value already on the line (`<1-1439>` for MINUTE, `FIRST`..`LASTDAY` for MONTHLY, the union when `/SC` has not been typed, `<no-modifier>` for ONCE/ONSTART/ONLOGON/ONIDLE)
- the static enumerated value sets below
- placeholders for the free-form slots (`<system>`, `<domain\user>`, `<password>`, `<HH:mm>`, `<mm/dd/yyyy>`, `<minutes>`, `<mmmm:ss>`, `<channel-name>`)

`/P`, `/RP` and `/Query /XML` take optional values, so a `/`-prefixed word in their slot completes the next option instead.

### Quoting behavior

Path and task-name suggestions are quoted when needed for spaces, or when the current input already started with a quote.

## Key completion behaviors / supported values

### Top-level and subcommand options

Subcommands and option tokens are discovered from the installed `schtasks.exe` help text, not hardcoded command maps.

### Static value hints

The script provides explicit value suggestions for these options:

- `/SC`: `MINUTE`, `HOURLY`, `DAILY`, `WEEKLY`, `MONTHLY`, `ONCE`, `ONSTART`, `ONLOGON`, `ONIDLE`, `ONEVENT`
- `/FO`: `TABLE`, `LIST`, `CSV`
- `/RL`: `LIMITED`, `HIGHEST`
- `/D`: `MON`, `TUE`, `WED`, `THU`, `FRI`, `SAT`, `SUN`, `*`
- `/M`: `JAN`, `FEB`, `MAR`, `APR`, `MAY`, `JUN`, `JUL`, `AUG`, `SEP`, `OCT`, `NOV`, `DEC`, `*`
- `/XML`: `ONE`
- `/RU`: `SYSTEM`, `"NT AUTHORITY\SYSTEM"`, `"NT AUTHORITY\LOCALSERVICE"`, `"NT AUTHORITY\NETWORKSERVICE"`

### Task-name completion

For `/TN`, the script runs:

```powershell
schtasks.exe /Query /FO CSV
```

It extracts the first CSV column as task names, sorts them uniquely, and caches them for 60 seconds.

Task-name suggestions are only returned for `/TN` when the active subcommand is **not** `/Create`. A typed prefix matches with or without the leading `\` (`Mic` finds `\Microsoft\...`).

### Path completion

The completer uses filesystem completion for:

- `/TR` with general file or directory suggestions
- `/XML` with suggestions limited to `.xml` files and directories (under `/Create`)

Relative input stays relative, a trailing separator lists that directory, and an empty word lists the current directory.

### Token parsing behavior

The script derives the current token from the command line text so it can continue suggesting values correctly when the cursor is on a partially typed token or after trailing whitespace. Only command elements that end before the cursor count as already typed, so completing inside an earlier token (for example inside `/Query`) sees the same context as typing it fresh.

## Dependencies or external command expectations

This completer expects:

- `schtasks.exe` to be available, otherwise completion is empty
- access to `schtasks.exe /?` and `schtasks.exe <subcommand> /?` for initialization
- access to `schtasks.exe /Query /FO CSV` for task-name completion
- local filesystem access for `/TR` and `/XML` path suggestions

## Usage / loading example

```powershell
. .\schtasks_completer.ps1

schtasks <TAB>
schtasks /Create <TAB>
schtasks /Create /SC <TAB>
schtasks /Query /TN <TAB>
schtasks /Create /XML <TAB>
```

## Limitations / notes

- Free-form value slots complete as placeholders; only the options in the static hint table and the parsed `/MO` modifiers get real value lists.
- `/TN` completion is intentionally skipped for `/Create`.
- Path completion is only specialized for `/TR` and `/XML`.
- The available subcommands and option tokens depend on the help text exposed by the installed `schtasks.exe`.

