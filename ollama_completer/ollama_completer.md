# ollama native argument completer for PowerShell

This standalone completer registers native tab completion for `ollama` and `ollama.exe`.

## Style

- Help-driven with a small lazy static overlay.
- Built-in help is the primary authoritative source for root commands, root flags, subcommand flags, and `launch` integrations.
- The overlay only supplies alias normalization, placeholder-only operands, enum values, and path/value-kind hints that help output does not model directly.

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
  - `run --think=`
  - `run --format=`
  - `create --file=`
  - `launch --config=`
  - `launch --model=`
- Path completion for:
  - `create -f` / `create --file`
  - `launch --config`
- Placeholder-only operand completion to suppress noisy filesystem fallback for:
  - `<model>`
  - `<source-model>`
  - `<destination-model>`
  - `<prompt>`
  - `<quantization>`
  - `<duration>`
  - `<negative-prompt>`

## Runtime notes

- Validated against local `ollama` version `0.23.3`.
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
- Model, prompt, quantization, and duration slots intentionally use placeholders instead of guessing from local files or server state.
