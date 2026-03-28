# psservice completer

## What it completes / overview

`psservice_completer.ps1` registers a native PowerShell argument completer for `psservice` and `psservice.exe`.

The completer is intentionally standalone and lightweight:

- it uses a static top-level command catalog derived from the local PsService help surface confirmed during implementation
- it models the optional `\\Computer [-u Username [-p Password]]` preamble separately from command arguments
- and it uses a small script-scoped cache of local service names and display names from `Get-Service`

This keeps completion safe and cheap while avoiding any remote probing or command execution in the completion path.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'psservice', 'psservice.exe' -ScriptBlock { ... }
```

Load it into the current session with:

```powershell
. .\psservice_completer.ps1
```

The file also enables:

```powershell
Set-StrictMode -Version 2.0
```

## How completion works

### Script-scoped command metadata

The script keeps a small script-scoped catalog for:

- safe top-level verbs:
  - `query`
  - `config`
  - `setconfig`
  - `start`
  - `stop`
  - `restart`
  - `pause`
  - `cont`
  - `depend`
  - `find`
  - `security`
- root switches:
  - `-?`
  - `/?`
  - `-nobanner`
  - `-u`
  - `-p`
- `query` enums:
  - `-t`: `driver`, `service`, `interactive`, `all`
  - `-s`: `active`, `inactive`, `all`
- `setconfig` start-type values:
  - `auto`
  - `demand`
  - `disabled`

The completer does not call `psservice -? <verb>` or any live service-control command during completion.

### Token-state parsing

The completer reconstructs tokens from the command line text up to the cursor so registered `TabExpansion2` behavior matches actual runtime completion.

It tracks:

- tokens before the current slot
- the current token
- quoting state for display names containing spaces
- the optional remote/auth preamble before the command name

That allows the script to keep `\\Computer`, `-u`, and `-p` separate from the actual PsService verb and arguments.

### Dynamic local service cache

`Update-PsServiceServiceCache` caches:

- service key names from `Get-Service | Select-Object -ExpandProperty Name`
- display names from `Get-Service | Select-Object -ExpandProperty DisplayName`

Display names with spaces are emitted as quoted completion texts. The cache is script-scoped and short-lived so repeated completion stays cheap.

Remote service enumeration is intentionally not attempted.

## Key completion behaviors / supported values

### Root / preamble

At the root, the completer offers:

- top-level verbs
- `-?`, `/?`, and `-nobanner`
- `-u` and `-p` as remote-auth preamble switches
- a `\\Computer` placeholder for the optional remote target

If `-u` or `-p` is waiting for a value, the completer returns placeholder-style results such as `<username>` or `<password>` to suppress filesystem fallback without inventing data.

### `query`

`query` offers:

- local service names and display names
- `-g`, `-t`, and `-s`
- `-?` and `/?`

Value completion includes:

- `-t`: `driver`, `service`, `interactive`, `all`
- `-s`: `active`, `inactive`, `all`
- `-g`: placeholder `<group>`

The group slot is intentionally placeholder-only rather than probing load-order groups dynamically.

### Service-name commands

These commands complete from the local service cache:

- `start`
- `stop`
- `restart`
- `pause`
- `cont`
- `depend`

The completer offers both service key names and display names as lightweight hints.

### Optional-service commands

`config` and `security` accept an optional service name, so the completer offers local service hints in the first positional slot and then stops.

### `setconfig`

`setconfig` completes:

1. a local service name or display name
2. one of:
   - `auto`
   - `demand`
   - `disabled`

### `find`

`find` completes:

1. a local service name or display name
2. the literal trailing value `all`

The completer does not attempt any network scanning or discovery for this verb.

## Dependencies or external command expectations

This completer expects:

- `psservice.exe` to be available on the machine
- local `Get-Service` access for service-name and display-name suggestions

It does not depend on remote host discovery and does not query PsService subcommands during completion.

## Usage / loading example

```powershell
. .\psservice_completer.ps1

psservice.exe <TAB>
psservice.exe \\Computer <TAB>
psservice.exe \\Computer -u <TAB>
psservice.exe query <TAB>
psservice.exe query -t <TAB>
psservice.exe setconfig Spooler <TAB>
psservice.exe find Spooler <TAB>
psservice.exe security <TAB>
```

## Limitations / notes

- Dynamic hints are local only. The completer does not enumerate services on remote computers.
- `find` is intentionally non-probing because it can trigger network scanning.
- `-u` and `-p` return placeholders only; the completer does not attempt account discovery.
- `config` and `security` treat the service name as optional and do not force a placeholder when the user wants bare command help or runtime behavior instead.
- Without a completer, PowerShell typically falls back to filesystem completion in many of these positions; placeholder returns are used selectively to suppress that fallback in value slots.
