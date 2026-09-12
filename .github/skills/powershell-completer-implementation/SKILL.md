---
name: powershell-completer-implementation
description: Implement or extend standalone PowerShell argument completers for native commands in this repository. Use this when asked to create, refine, document, or validate a completer script, especially when the command surface comes from /?, --help, subcommand help, or cautious runtime discovery.
argument-hint: "[command] [executable] [help source] [expected behaviors]"
---

# PowerShell Completer Implementation

Use this skill for work in the `PS_Completers` repository when the task is to add or improve a native PowerShell completer.

This skill captures the repository's implementation patterns, the recurring runtime issues discovered while building and auditing completers, the CompleterActions strict import grammar every script must satisfy, and the clean-session validation flow that proves the work functions in real `pwsh` usage.

## Goal

Deliver a standalone completer that:

- lives in its own `<name>_completer` folder
- keeps all completer logic in a single `.ps1` file
- includes a companion `.md` document
- updates the alphabetical row in `README.md`
- is listed in `ps_completers.psd1`, the completer set that `Import-CompleterSet` loads lazily
- passes `Test-CompleterScript` with no findings, so the Pester gate in `tests/` stays green
- works through real `Register-ArgumentCompleter -Native` runtime behavior, not only direct helper invocation

## When to use which implementation style

Choose the simplest style that matches the target command:

- **Help-driven with a static fallback** (the default for coreutils-style tools)
  Parse `--help`, `/?`, `-?`, or subcommand help once per session, cache the parsed catalog in `$script:` scope, and keep a small static option list for the case where the tool is not installed. The help line's description becomes the tooltip.
  Good references:
  - `touch_completer\touch_completer.ps1` (the template shape used by about 60 coreutils completers, with an option value table)
  - `du_completer\du_completer.ps1` (static GNU catalog with value kinds, descriptions refreshed from help)
  - `OhMyPosh_completer\OhMyPosh_completer.ps1` (help parsed per command path, positional values from the `Usage:` line)
  - `dism_completer\dism_completer.ps1`
  - `schtasks_completer\schtasks_completer.ps1`

- **Static-first**
  Use explicit switch tables, subcommand maps, and placeholder values when the tool has no parsable help (GUI tools, tools that print UTF-16 help with embedded NULs such as `wsl`) or the grammar is stable and small.
  Good references:
  - `wsl_completer\wsl_completer.ps1` (mode-aware sub-option groups and enum values)
  - `wt_completer\wt_completer.ps1`
  - `psshutdown_completer\psshutdown_completer.ps1`

- **Tool-backed / dynamic**
  Use installed tool output or safe local discovery only when that keeps the completer aligned with the installed version and does not introduce risk or latency.
  Good references:
  - `Git_completer\Git_completer.ps1`
  - `gh_cli_completer\gh_cli_completer.ps1`
  - `pslist_completer\pslist_completer.ps1`
  - `xargs_completer\xargs_completer.ps1` (application names cached per `PATH` value)

## Implementation rules

### Keep the file self-contained

- Put the completer in a single shipped `.ps1` file.
- Avoid cross-file helper frameworks for one command.
- Prefer small local helper functions and script-scoped caches.

### Match repository conventions

- Use `Set-StrictMode` near the top and preserve local style (`2.0` or `Latest`) unless there is a good reason not to.
- Use `Register-ArgumentCompleter -Native`.
- Accept the standard parameters: `$wordToComplete`, `$commandAst`, `$cursorPosition`.
- Emit `System.Management.Automation.CompletionResult`.
- Use `ParameterName` for switches and `ParameterValue` for values, subcommands, process names, registry paths, file paths, and placeholders.

### Prefer safe completion behavior

- Do not make destructive or state-changing calls while completing. That includes `Set-Alias`, `$env:` writes, and anything with `-Scope Global`; completion must not mutate the session.
- Do not enumerate remote systems during completion.
- For risky verbs or sensitive slots, offer placeholders instead of live probing.
- Use local-only caches for safe data like process names, event logs, services, or directories.

### Use placeholders to beat noisy fallback

PowerShell applies its own filesystem completion whenever a native completer returns nothing. In a non-path slot, emit explicit placeholder values instead:

- `<username>`
- `<domain\user>`
- `<number>`
- `\\<computer>`
- `@file`
- `<path>`

This is the only way to suppress the fallback; there is no "return nothing and mean it".

### Route by actual command context

- Inspect `CommandAst.CommandElements` and tokenized input.
- Track tokens before the current word.
- Detect whether the user is completing a switch, switch value, operand, registry path, `@file`, executable path, or subcommand.
- When already in a path or provider-path mode, suppress unrelated root switch suggestions.

### Complete option values in all three forms

For every value-bearing option, handle the separate form (`--time mod`), the attached form (`--time=mod`, keeping the `--time=` prefix on every suggestion), and a partially typed value. The template family does this with a `Get-<X>OptionValueCompletions` helper holding a per-option table; path-valued options route to the script's own path helper, and dynamic slots (environment variable names, process ids) use a scriptblock in the table. Tools with `key=value` operands (`dd`) use the same helper with a bare-word attached regex.

### Cache expensive discovery carefully

- Cache parsed help output in `$script:` scope, initialised lazily from a function or in a top-level `Get-Variable` guard (see the grammar below).
- Probe caches with `Get-Variable ... -ErrorAction Ignore`, not `SilentlyContinue`, so a cold load adds nothing to `$Error`.
- Cache local discovery with short-lived or lazy initialization if it is moderately expensive.
- Do not recompute heavy discovery on every keystroke.

### Keep the top level inside the CompleterActions strict import grammar

Every script must import under the CompleterActions strict tier (`Import-CompleterScript`, and `Import-CompleterSet` for the whole repository). The grammar is documented in `about_Import_Completers` (CompleterActions 2.0.0 or later) and enforced by `Test-CompleterScript`. Script scope may contain only:

- `Set-StrictMode`
- function definitions
- `if` statements whose conditions and bodies stay inside the grammar; the blessed shape is a cache guard:

  ```powershell
  if (-not (Get-Variable -Name ToolCompletionCatalog -Scope Script -ErrorAction Ignore)) {
      $script:ToolCompletionCatalog = @{ Initialized = $false; Switches = @() }
  }
  ```

- script-scope `Register-ArgumentCompleter` calls with literal arguments: a single literal string or a literal `@('name', 'name.exe')` array for `-CommandName`, and a literal `-ScriptBlock { ... }`

Everything else is rejected at script scope and must live inside a function body or the registration scriptblock: bare assignments, loops, `try`/`catch`, helper invocations, `Invoke-Expression`, external command calls, and anything that computes registration metadata. Inside functions there are no restrictions.

Check a script with:

```powershell
Import-Module CompleterActions -MinimumVersion 2.0.0
Test-CompleterScript -LiteralPath .\<name>_completer\<name>_completer.ps1
```

A conforming script returns nothing. Each finding carries `Line`, `Column`, `Construct`, `Message` and `Hint`; every strict-grammar finding has severity `Error`, and a script that does not parse yields one finding per parse error. The repository gate `tests/Completers.Tests.ps1` runs this over every script and then imports `ps_completers.psd1` lazily, so regenerate the set file after adding, renaming, or removing a completer:

```powershell
pwsh -NoProfile -File ./tools/Export-CompleterSetFile.ps1
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
```

## Shared idioms and the defects they prevent

These came out of the 2026-09 audit of all 169 completers. Apply them proactively; most of the family already uses them.

- **Help-harvest regex.** When scraping option tokens from help text use `(?<!\S)(--?[A-Za-z0-9][A-Za-z0-9-]*)(?=(\s|,|=|\[|$))`. Without `=` and `[` in the lookahead every `--opt=VALUE` and `--opt[=WHEN]` line is silently dropped. Keep the rest of the line as the option's description and use it as the tooltip.
- **Case-sensitive option matching.** Use `[System.StringComparer]::Ordinal` for option sets and `[System.StringComparison]::Ordinal` for prefix matching. Case-insensitive comparers delete `-D`/`-d`, `-F`/`-f`, `-T`/`-t` pairs. PowerShell hashtable literals (`@{}` and `[ordered]@{}`) are case-insensitive and fail to parse with "Duplicate keys" when both `-W` and `-w` appear; build option tables with `[System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)`.
- **Cursor rebasing.** `$cursorPosition` is an offset into the whole input line, while `$commandAst.ToString()` and `$commandAst.Extent.Text` are command-relative. Before slicing, padding, or comparing against that string, subtract `$commandAst.Extent.StartOffset`. Otherwise completion breaks whenever the command is not the first statement on the line. Comparisons against `$element.Extent.EndOffset` stay absolute.
- **Stdin guard on external calls.** Pipe `$null` into every help invocation (`$null | & $exe --help 2>&1 | Out-String`) so a tool that waits on standard input cannot hang the prompt. For tools that are slow or spawn shells (`pi`), use `System.Diagnostics.Process` with `RedirectStandardInput`, close stdin after start, read output asynchronously, and `WaitForExit(<ms>)` with a kill on timeout.
- **StrictMode and `.Count`.** Wrap function results in `@()` before reading `.Count`; a single returned object has no `Count` under `Set-StrictMode` and the exception is swallowed by `TabExpansion2`, which then falls back to filenames.
- **Wildcard escaping.** Never interpolate typed text into `-like` directly; use `-like ([System.Management.Automation.WildcardPattern]::Escape($leaf) + '*')`. A `[` in the input throws otherwise.
- **`Split-Path` on empty input.** Guard with `[string]::IsNullOrWhiteSpace` first; `Split-Path ''` throws.
- **Trailing-separator paths.** `Split-Path -Leaf` on `dir\` returns `dir`; treat a trailing separator as "list the children of this directory".
- **Single-element slices.** `$tokens[0..($tokens.Count - 2)]` duplicates the element when the count is 1; use `@($tokens | Select-Object -First ($tokens.Count - 1))`.
- **Which binary resolves.** Several tools exist twice on Windows (Git for Windows GNU builds versus uutils coreutils, Sysinternals `du` versus GNU `du`). Model the build that `Get-Command` resolves first and say so in the doc.
- **Engine quirk.** `TabExpansion2` does not call a native completer for an empty word directly after a `{}` script-block token (`xargs -I {} <Tab>`); this is not a completer bug.

## Runtime edge cases learned from this repo

Apply these checks proactively:

- **Native registration should usually cover both bare and `.exe` names.**
  This matters for commands that resolve through Windows app execution aliases. Register both in one literal array; do not create aliases to compensate.

- **Do not assume help exits `0`.**
  Many native tools print valid help and exit nonzero. Treat useful help output as authoritative even when the exit code is not.

- **Do not assume `--help` is real help.**
  Some tools treat it as an operand or behave differently from `/?`, and some (`wsl`) print UTF-16 help that a text parser cannot read.

- **Test `@file` with a bare `@`.**
  Empty path portions must not throw from `Split-Path`.

- **Test slash-prefixed apps separately.**
  Commands like `shellrunas` may use `/reg`, `/unreg`, `/quiet`, and can accidentally leak a literal `/` completion if path completion is not gated.

- **Provider paths need dedicated handling.**
  Registry-aware completers should preserve provider completion for values like `HKLM:\` or `HKCU\Software\`.

## Recommended workflow

1. Inspect the target command locally with `Get-Command` and help output; note which binary resolves.
2. If local help is incomplete or graphical, use authoritative vendor or product docs.
3. Choose help-driven, static, or tool-backed completion based on the real command surface.
4. Design the script so its top-level shape stays inside the strict import grammar from the start.
5. Create:
   - `<name>_completer\<name>_completer.ps1`
   - `<name>_completer\<name>_completer.md`
6. Implement the completer with repository-consistent helper naming, the shared idioms above, and value completion in all three forms.
7. Update the alphabetical row in `README.md` and regenerate `ps_completers.psd1`.
8. Run `Test-CompleterScript` on the script, then the Pester gate, then clean `pwsh -NoProfile` runtime probes with `TabExpansion2`, including one probe with the command mid-line.
9. If runtime behavior differs from direct helper invocation, fix the registered/runtime path.

## Validation requirements

Use the checklist in [validation-checklist.md](./validation-checklist.md).

Minimum validation for a new or changed completer:

- `Test-CompleterScript` returns no findings
- the Pester gate under `tests/` passes (it also checks `ps_completers.psd1` lists exactly the scripts in the repository)
- dot-source the script in a clean session and confirm `$Error` stays empty
- confirm representative `TabExpansion2` results
- verify one or more switch surfaces, including a case-distinct short option pair when the tool has one
- verify value completions for at least one non-path slot in the separate and the attached form
- verify path or provider-path completion when the completer supports it
- verify completion with the command preceded by another statement on the line
- validate both bare and `.exe` invocation names when relevant

Prefer representative real-world checks over calling helper functions directly.

## Repository integration

For repository work, finish with all of the following:

- standalone folder added
- `.ps1` script added
- `.md` doc added, with the literal registration snippet copied from the script
- `README.md` row added in alphabetical order
- `ps_completers.psd1` regenerated
- `Test-CompleterScript` clean and the Pester gate green
- clean-session validation performed
- if requested by the user, add the completer to the profile's `#region Argument Completers`

## Reference files

- `README.md`
- `.github/copilot-instructions.md`
- `tests/Completers.Tests.ps1`
- `tools/Export-CompleterSetFile.ps1`
- `touch_completer\touch_completer.ps1`
- `du_completer\du_completer.ps1`
- `OhMyPosh_completer\OhMyPosh_completer.ps1`
- `Git_completer\Git_completer.ps1`
- `dism_completer\dism_completer.ps1`
- `schtasks_completer\schtasks_completer.ps1`
- `wsl_completer\wsl_completer.ps1`
- `xargs_completer\xargs_completer.ps1`
- `pslist_completer\pslist_completer.ps1`

## Output expectations

When using this skill:

- explain which completer style you chose and why, and which installed binary the surface was taken from
- mention any special runtime quirks discovered
- call out how the script satisfies the strict import grammar and that `Test-CompleterScript` returned nothing
- validate with clean-session `pwsh -NoProfile` commands
- call out whether registration needed both bare and `.exe` names
- mention any deliberately placeholder-only or non-enumerating slots
- confirm the Pester gate passed and `ps_completers.psd1` was regenerated when the script set changed
