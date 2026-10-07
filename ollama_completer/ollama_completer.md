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
- Installed model names for the MODEL operand of `run`, `show`, `stop`, `rm`, `pull`, `push`, `create`, the SOURCE operand of `cp`, and `launch --model` / `--model=`. Names are read passively from the manifest tree (`<root>/manifests/<host>/<namespace>/<name>/<tag>`, root = `$env:OLLAMA_MODELS` or `~/.ollama/models`) and shown the way `ollama list` prints them (`name:tag`, `namespace/name:tag`, `host/namespace/name:tag`); internal `llamacpp:<sha256>` entries are skipped. No process is started and the server is never contacted; the list is cached per models root for 5 s (about 3 ms to rescan 18 manifests). An opening quote is kept on the emitted name.
- Placeholder operand completion (also the model fallback when no installed model matches) to suppress noisy filesystem fallback for:
  - `<model>`
  - `<source-model>`
  - `<destination-model>`
  - `<prompt>`

## Runtime notes

- Validated against local `ollama` version `0.34.0`.
- Model discovery reads the manifest tree instead of running `ollama list`, which needs the server and can block or time out when it is unavailable.
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

- No integration-specific passthrough parsing after `launch --`.
- Prompt slots intentionally use placeholders; model slots never query server state (running models for `stop` are not distinguished from installed ones).
