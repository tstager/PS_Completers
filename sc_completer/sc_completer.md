# sc completer

## What it completes / overview

`sc_completer.ps1` registers a native PowerShell argument completer for `sc` and `sc.exe`.

The completer is intentionally hybrid:

- it seeds the top-level command catalog from local `sc` help output
- it layers static per-command metadata on top for positional slots and `token=` style value handling
- and it uses a small script-scoped cache of local service names and display names for dynamic suggestions

This keeps the root command surface aligned with the locally installed `sc.exe` while still handling the subcommands whose help output is incomplete or inconsistent when probed directly.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'sc', 'sc.exe' -ScriptBlock { ... }
```

Load it into the current session with:

```powershell
. .\sc_completer.ps1
```

The file also enables:

```powershell
Set-StrictMode -Version 2.0
```

## How completion works

### Script-scoped initialization

On first use, `Initialize-ScCompletionCatalog`:

- resolves `sc.exe`
- runs bare `sc` help to capture the authoritative local top-level command list
- merges parsed command descriptions with a fallback static command catalog
- seeds metadata for:
  - `query` / `queryex` enumeration tags
  - `config` / `create` canonical `token= ` options
  - `failure` options
  - trigger templates
  - small numeric and literal hint sets

### Token-state parsing

The completer reconstructs tokens from the command line text up to the cursor so real `TabExpansion2` behavior stays aligned with runtime completion.

It tracks:

- tokens before the current slot
- the current token
- whether a leading `\\ServerName` token is present before the command name

That allows the completer to keep the optional remote-server prefix separate from the actual `sc` command and arguments.

### Dynamic local service cache

`Update-ScServiceCache` caches:

- service key names from `Get-Service | Select-Object -ExpandProperty Name`
- display names from `Get-Service | Select-Object -ExpandProperty DisplayName`

The cache is script-scoped and short-lived, so repeated completion stays cheap without attempting any remote service discovery.

## Key completion behaviors / supported values

### Top-level commands

At the root, the completer offers locally parsed `sc` commands such as:

- `query`
- `queryex`
- `start`
- `config`
- `triggerinfo`
- `GetDisplayName`
- `EnumDepend`
- `boot`
- `Lock`
- `QueryLock`

If the current token begins with `\\`, it also preserves the remote server slot with a `\\ServerName` placeholder.

### Service-name-backed commands

Commands that take an existing service name complete from local `Get-Service` names, including:

- `start`, `pause`, `interrogate`, `continue`, `stop`
- `config`, `description`, `failure`, `failureflag`, `sidtype`, `privs`, `managedaccount`
- `qc`, `qdescription`, `qfailure`, `qfailureflag`, `qsidtype`, `qprivs`, `qtriggerinfo`, `qpreferrednode`, `qmanagedaccount`, `qprotection`
- `delete`, `control`, `sdshow`, `sdset`, `triggerinfo`, `preferrednode`, `EnumDepend`

Service names and display names that contain spaces are returned as quoted completion texts so the native command receives them as a single argument.

### `query` / `queryex`

Before a service name is committed, `query` and `queryex` offer both:

- local service names
- enumeration tags:
  - `type= `
  - `state= `
  - `bufsize= `
  - `ri= `
  - `group= `

Value completion includes:

- first `type=` values like `driver`, `service`, `userservice`, `all`
- second `type=` values like `own`, `share`, `interact`, `kernel`, `filesys`, `rec`, `adapt`
- `state=` values `inactive`, `all`
- numeric hints for `bufsize=` and `ri=`

### `config` / `create`

These commands suggest canonical `token= ` forms with trailing spaces for:

- `type= `
- `start= `
- `error= `
- `binPath= `
- `group= `
- `tag= `
- `depend= `
- `obj= `
- `DisplayName= `
- `password= `

Enumerated values are provided for:

- `type=`
- `start=`
- `error=`
- `tag=`

Free-form value slots such as `binPath=`, `group=`, `depend=`, `obj=`, `DisplayName=`, and `password=` return placeholder-style completions to suppress filesystem fallback rather than inventing content.

`create` treats the first positional service name as free-form and likewise suppresses filesystem fallback there.

### Other literal and enum-aware commands

The completer also adds targeted value hints for:

- `failure`: `reset= `, `reboot= `, `command= `, `actions= `
- `failureflag`: `0`, `1`
- `sidtype`: `none`, `unrestricted`, `restricted`
- `managedaccount`: `true`, `false`
- `control`: named values like `paramchange`, `netbindadd`, `netbindremove`, `netbindenable`, `netbinddisable`
- `boot`: `bad`, `ok`
- `preferrednode`: small node-number hints
- `qc`, `qdescription`, `qfailure`, `qprivs`, `qtriggerinfo`, `GetDisplayName`, `GetKeyName`, `EnumDepend`: small buffer-size hints

### Trigger templates

For `triggerinfo`, the completer offers literal templates from local help text, including examples such as:

- `start/networkon`
- `stop/networkoff`
- `start/domainjoin`
- `stop/domainleave`
- `start/portopen/parameter`
- `start/rpcinterface/UUID`
- `start/namedpipe/pipename`
- `delete`

This stays intentionally shallow and does not attempt to parse the deeper trigger payload grammar.

## Dependencies or external command expectations

This completer expects:

- `sc.exe` to be available
- local `sc` help output to provide the authoritative root command list
- local `Get-Service` access for service-name and display-name suggestions

It does not attempt remote host discovery for `\\ServerName`.

## Usage / loading example

```powershell
. .\sc_completer.ps1

sc.exe <TAB>
sc.exe \\ServerName <TAB>
sc.exe query <TAB>
sc.exe query type= <TAB>
sc.exe config eventlog <TAB>
sc.exe create MyService <TAB>
sc.exe triggerinfo eventlog <TAB>
sc.exe GetKeyName <TAB>
```

## Limitations / notes

- `sc` subcommand help is inconsistent: some subcommands print usage when invoked bare, while others perform live actions. This implementation only treats the top-level help surface as authoritative and uses static metadata for subcommand behavior.
- Remote service enumeration is intentionally not attempted. Only the local service cache is used for dynamic values.
- Free-form slots such as descriptions, passwords, SDDL, privilege lists, and trigger payload details are intentionally placeholder-only so PowerShell does not fall back to filesystem completion in those positions.
- `showsid` accepts arbitrary names; the completer only offers local service names and display names as lightweight hints.
