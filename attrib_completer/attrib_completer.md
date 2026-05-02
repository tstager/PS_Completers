# attrib completer

## What it completes / overview

`attrib_completer.ps1` registers a standalone native PowerShell completer for `attrib` and `attrib.exe`.

It is a **static-first** completer because `attrib.exe` has a small, stable surface and the local help text on this machine was slightly inconsistent about the full attribute-toggle set.

The completer covers:

- whole-token attribute toggles:
  - `+R`, `-R`
  - `+A`, `-A`
  - `+S`, `-S`
  - `+H`, `-H`
- additional whole-token attribute toggles:
  - `+O`, `-O`
  - `+I`, `-I`
  - `+X`, `-X`
  - `+P`, `-P`
  - `+U`, `-U`
  - `+B`, `-B`
  - `+V`, `-V`
- slash switches:
  - `/S`
  - `/D`
  - `/L`
  - `/?`
- filesystem path and wildcard operand completion for `[drive:][path][filename]`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('attrib', 'attrib.exe') -ScriptBlock { ... }
```

That covers both the bare command name and the explicit `.exe` form.

Load it with:

```powershell
. .\attrib_completer\attrib_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, `try`/`catch` blocks, helper invocations, or external command calls.

## How completion works

### 1. Static-first routing

Completion is routed only by the current token prefix:

- `+` or `-` => attribute-toggle completion only
- `/` => slash-switch completion only
- anything else => path / wildcard operand completion

That keeps `+`, `-`, and `/` slots from falling back into noisy filesystem completion.

### 2. Attribute-toggle surface

The attribute-toggle table is intentionally static and includes the union needed for this machine:

- local `attrib.exe /?` output listed `R`, `A`, `S`, `H`, `O`, `I`, `X`, `P`, and `U` in the main usage line
- the same local help text also described `V` (integrity) and `B` (SMR blob) in the detail section

Because of that inconsistency, the completer intentionally includes:

- `+B`, `-B`
- `+V`, `-V`

even though those tokens were not all surfaced consistently in the same help line.

### 3. Slash switches

The slash-switch table is static:

- `/S`
- `/D`
- `/L`
- `/?`

`/?` is included explicitly even though it acts as the help trigger rather than a normal processing switch.

### 4. Operand completion

For non-switch tokens, the completer delegates to PowerShell filename completion so that:

- relative paths such as `.\`
- wildcard-bearing operands
- normal file and directory paths

all use the shell's native filesystem completion behavior.

## Representative validation scenarios

```powershell
attrib /
attrib.exe /
attrib +
attrib -
attrib +R .\
attrib .\
```

Expected behavior:

- `attrib /` and `attrib.exe /` show only slash switches
- `attrib +` and `attrib -` show only whole-token attribute toggles with the matching sign
- `attrib +R .\` and `attrib .\` stay in filesystem completion mode for the operand slot

## Notes

- The completer is intentionally non-enumerating beyond local filesystem completion.
- Toggle completions are emitted as `ParameterName`.
- Path operands are emitted as `ParameterValue`.
- `README.md` was intentionally not updated in this task, per the requested scope.
