# wslc completer

`wslc_completer.ps1` registers a standalone native PowerShell completer for `wslc` and `wslc.exe`, the Windows Subsystem for Linux container CLI.

Completion follows the installed binary. Command and option lists are parsed from `--help` / `-?` and cached per command path. Container, image, network, and volume names come from read-only `--format json` queries. There is no `wslc completion` command and no `--cli-schema`.

## Registration

```powershell
Register-ArgumentCompleter -Native -CommandName @('wslc', 'wslc.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Wslc -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

## How completion works

- Resolves `wslc` or `wslc.exe`, then `C:\Program Files\WSL\wslc.exe` if those names are not on `PATH`.
- Runs help with stdin closed, a 4 second timeout, and ANSI stripping. A failed help call is retried after 30 seconds rather than on every keystroke.
- Walks settled tokens with absolute `Extent.EndOffset` values, so completion still works when `wslc` is not the first statement on the line.
- Completes nested commands from the `Commands:` section of the current help page.
- Parent help lists canonical names only. Aliases (`ls`, `ps`, `rm`, `delete`) are probed per command group, and one is offered only when `wslc <group> <alias> --help` lists it under `Aliases:`. So `wslc rm`, `wslc container rm` and `wslc image ls` complete like their targets, and `system session` gets no `ls`.
- Completes options from `Options:` and `Global Options`, including `-?`. `-p` / `--publish` and `-P` / `--publish-all` stay distinct.
- Value options support both `wslc run --pull missing` and `wslc run --pull=missing`. Enums such as `always|missing|never`, `json` / `table`, `auto|tty|plain|quiet`, and `--gpus all` are read from the help description.
- Short alias chains such as `-dp` and `-qn` are read letter by letter. wslc lets only the last alias in a chain take a value, so `wslc run -dp ` completes the `-p` value, `-dp 8080:80` uses up the next word, and `-dp=` completes as `-dp=<host:container>`. wslc rejects `-n1` (a value glued to the alias), so that form is not completed.
- TakesValue is inferred from each command's own description, so `build --pull` stays a flag while `run --pull` takes a policy. `--since`, `--until`, `--password`, `--username`, `--type`, `--gateway` and `--label` always take a value, because some of their descriptions read like flags.
- Operand kinds come from the `Usage:` names, refined by `Arguments:` descriptions: `container cp <source> <target>` is described as a path and gets filesystem completion, while `tag <source> <target>` stays an image.
- `run`, `create`, `exec` and `system session run` stop parsing options at the first operand. After the image or container, everything belongs to the container command, so no wslc options are offered there.

## Dynamic names

Read-only queries, cached for 8 seconds, with a 3 second timeout:

- `wslc system session list` for `--session`. It has no `--format`, so the `Display Name` column is parsed; `--session` takes that name, not the numeric ID.
- `wslc list --all --format json`
- `wslc images --format json`
- `wslc network list --format json`
- `wslc volume list --format json`

The object lists start the default session when none is running, which takes about 2 seconds. `system session list` does not. So object names are queried only when a session is running, and only when the `--session` named on the line, if any, is one of them. That session is passed on to the query. Otherwise the slot gets its placeholder and no session is started.

Object list output is newline-delimited JSON. If a query is empty or fails, the slot gets a placeholder (`<container>`, `<image>`, `<network>`, `<volume>`, `<session>`) instead of unrelated file names.

## Placeholders and paths

- `--password` is `<password>`. The completer never reads credentials.
- `--name` on create/run is `<name>` (a new name, not an existing container).
- `-p` / `--publish` is `<host:container>`.
- `-e` / `--env`, `--build-arg`, and `--label` are `<key=value>`.
- `build --secret` is `<secret>`; its value is a spec (`id=NAME,src=PATH`), not a path.
- `--file`, `--cidfile`, `--iidfile`, `--env-file`, `export -o` / `save -o`, and path operands use filesystem completion. `build -o` takes a buildx output spec and gets `<output>`.
- A volume value that already looks like a path (`.\`, `C:\`, `/`, `~`) is left to filesystem completion. Otherwise volume names are offered.

## Version

On this machine `wslc version` printed `wslc 3.0.1.0`. The file version resource was `5.0.1.1`. The completer does not freeze either number; it follows live help.

## Safety

Completion does not run mutating commands. It does not call `run`, `create`, `build`, `pull`, `push`, `login`, `logout`, `kill`, `remove`, `start`, `stop`, `prune`, `tag`, `import`, `export`, `load`, `save`, `exec`, or `attach` to discover values.

If `wslc` is not installed, only the root command and option fallback is offered.
