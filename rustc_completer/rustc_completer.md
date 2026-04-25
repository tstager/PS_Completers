# rustc completer

## What it completes / overview

`rustc_completer.ps1` registers a standalone native PowerShell completer for `rustc` and `rustc.exe`.

It is a **help-driven** completer with a small amount of safe local discovery:

- parses the installed `rustc -h` surface for documented switches
- reads local `rustc -W help` output for lint names
- reads local `rustc -C help` output for codegen option names
- reads local `rustc --print target-list` output for target triples
- reads local `rustc --print target-cpus` output for CPU names
- completes local files and directories for input/output path slots

The completion path does not compile code or probe remote state.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('rustc', 'rustc.exe') -ScriptBlock { ... }
```

Load it with:

```powershell
. .\rustc_completer\rustc_completer.ps1
```

The script also enables:

```powershell
Set-StrictMode -Version 2.0
```

## Import-CompleterScript compatibility

The file keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, `try` blocks, helper invocations, or external command calls.

## How completion works

### Switch surface

The completer suggests the documented option surface for common `rustc` flags, including:

- `-h`, `--help`
- `--cfg`
- `--check-cfg`
- `-L`
- `-l`
- `--crate-type`
- `--crate-name`
- `--edition`
- `--emit`
- `--print`
- `-g`
- `-O`
- `-o`
- `--out-dir`
- `--explain`
- `--test`
- `--target`
- `-A`, `--allow`
- `-W`, `--warn`
- `--force-warn`
- `-D`, `--deny`
- `-F`, `--forbid`
- `--cap-lints`
- `-C`, `--codegen`
- `-V`, `--version`
- `-v`, `--verbose`

### Representative value slots

The completer gives value suggestions for several non-path slots:

- `--edition` → `2015`, `2018`, `2021`, `2024`, `future`
- `--crate-type` → standard crate kinds
- `--emit` → documented emit kinds
- `--print` → documented `rustc --print` topics
- `--target` → installed target triples from `rustc --print target-list`
- `-A`, `-W`, `-D`, `-F`, `--force-warn` → lint names from `rustc -W help`
- `--cap-lints` → `allow`, `warn`, `deny`, `forbid`
- `-C`, `--codegen` → option names from `rustc -C help`

For `-C` / `--codegen`, the completer also recognizes `name=value` forms and suggests values for common options such as:

- `opt-level`
- `target-cpu`
- `target-feature`
- `code-model`
- `lto`
- `panic`
- `strip`
- `split-debuginfo`
- `symbol-mangling-version`
- common boolean switches

### Path completion

The completer uses local-only filesystem enumeration for:

- the primary input source file operand
- `-L` library search paths
- `-o` output file paths
- `--out-dir` output directories

### Placeholder-only slots

Some `rustc` value grammars are free-form or too noisy for reliable live enumeration. For those, the completer intentionally returns placeholder-style hints instead of trying to discover data:

- `--cfg`
- `--check-cfg`
- `-l`
- `--crate-name`
- `--explain`

That avoids falling back to unrelated filesystem completions in non-path slots.

## Usage examples

```powershell
rustc -<TAB>
rustc --edition <TAB>
rustc --target <TAB>
rustc -W <TAB>
rustc -C <TAB>
rustc -C target-cpu=<TAB>
rustc -L <TAB>
rustc .\<TAB>
rustc.exe --print <TAB>
```

## Runtime notes

- The completer registers both `rustc` and `rustc.exe` because both names resolve locally on this machine.
- Help/output harvesting is lazy and cached in script scope.
- Help text is treated as authoritative even though native tools do not always use conventional exit codes for help paths.

## Limitations

- The completer does not parse every possible nested `rustc` value grammar.
- `-L` and `-l` support richer syntaxes than simple directory/library-name hints; the completer keeps those slots conservative.
- Path completion is local-only and prefix-based.
