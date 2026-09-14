# ollama native argument completer for PowerShell

This standalone completer registers native tab completion for `ollama` and `ollama.exe`.

## Style

- Help-driven with a small lazy static overlay.
- Built-in help is the authoritative source for root commands, root flags, subcommand flags, and `launch` integrations: once a command's help parses, flags that exist only in the overlay are dropped, so a flag the installed build no longer has is never offered.
- Root help is parsed on the first completion; each subcommand's help is parsed lazily the first time completion needs that command (one `ollama <cmd> --help` per command per session, stdin closed, 1.5 s timeout).
- The pflag type token in help decides the value model: no type means a boolean (only `--flag=false` takes a value), `string[="true"]` means the value is only legal in the attached `--flag=value` form, `int`/`duration`/`string` get a typed placeholder; the overlay only refines the value kind (enum lists, path slots).

## Coverage

- Root commands and root flags from `ollama --help`, with alias completions for:
  - `start` -> `serve`
  - `ls` -> `list`
- Subcommand flag completion for:
  - `run`
  - `create`
  - `show`
  - `pull`
  - `push`
  - `launch`
- `help` completion for root commands.
- `launch` integration completion from `ollama launch --help`.
- Inline `--flag=value` completion for:
  - `run --think=` and `run --truncate=` (the only legal form for these NoOptDefVal flags; typing the bare flag also offers its `--flag=value` forms, and a following token is treated as the prompt operand, not as the flag's value)
  - `run --format=`
  - `create --file=`
  - `launch --model=`
- Path completion for `create -f` / `create --file` (an unterminated opening quote is handled). `launch --config` is a boolean switch and takes no value.
- Enum completion for `create -q/--quantize`, `create --draft-quantize` (q4_0 ... q6_K) and `run --keepalive` (5m, 10m, 30m, 1h, 0, -1).
- Placeholder-only operand completion to suppress noisy filesystem fallback for:
  - `<model>`
  - `<source-model>`
  - `<destination-model>`
  - `<prompt>`

## Runtime notes

- Validated against local `ollama` version `0.34.0`.
- The completer deliberately does **not** depend on live model discovery, because `ollama list` can block or time out when the server is unavailable.
- `launch --` passthrough is detected before generic switch handling, so completion stops after the bare passthrough marker.
- Command reconstruction uses `CommandAst.Extent.Text` plus `cursorPosition`; it does not rely on `CommandAst.ToString()`.

## Import-CompleterScript compatibility

The top level stays importer-safe by limiting the script to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native -CommandName @('ollama', 'ollama.exe')` call

There are no top-level assignments, loops, helper invocations, or external command calls.

## Representative validation

Clean-session validation should cover:

```powershell
pwsh -NoProfile -Command '
. .\ollama_completer\ollama_completer.ps1
foreach ($s in @(
    "ollama ",
    "ollama -",
    "ollama help ",
    "ollama run ",
    "ollama run llama3 ",
    "ollama run --think ",
    "ollama run --think=",
    "ollama run --format=",
    "ollama create -f .\",
    "ollama create --file=",
    "ollama show ",
    "ollama cp ",
    "ollama rm ",
    "ollama launch ",
    "ollama launch c",
    "ollama launch claude --model ",
    "ollama launch claude --model=",
    "ollama launch claude -- ",
    "ollama ls ",
    "ollama start ",
    "ollama.exe "
)) {
    "INPUT=$s"
    (TabExpansion2 $s $s.Length).CompletionMatches |
        Select-Object -First 12 CompletionText, ResultType |
        Format-Table -AutoSize
    "---"
}
'
```

## Deliberate v1 limits

- No live model discovery.
- No integration-specific passthrough parsing after `launch --`.
- Model and prompt slots intentionally use placeholders instead of guessing from local files or server state.
