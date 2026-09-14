# dism completer

## What it completes / overview

`dism_completer.ps1` registers a native PowerShell argument completer for `dism`.

The completer is static-first with live enrichment. DISM refuses to print its help unless the shell is elevated (`dism /?` exits 740 with "Elevated permissions are required to run DISM"), so the always-on baseline is a static catalog of the documented DISM surface (global options, the imaging, package, feature, capability, driver, edition, app-package, international and Windows PE servicing commands, each with its own switches and enumerated values). When the shell *is* elevated, `dism /?` and `dism [/Online] <command> /?` are read once per session (stdin closed, 2 s timeout) and any switch or command the static catalog does not know is added on top of it; a failed or refused help call leaves the static catalog intact.

## Registration and command names

- Registers with: `Register-ArgumentCompleter -Native`
- Command name:
  - `dism`

## How completion works

The script stores cached data in `$script:DismCompletionCatalog`:

- `Commands` - command specs (token, description, per-command switches)
- `GlobalSwitches` - the DISM global options and image specifications
- `OptionSpecs` - every known switch keyed by its lower-case token (with the trailing `:` for value-taking switches)
- `ExtraSwitchesByKey` - switches harvested from live help, per command

Every switch carries a kind:

- `Flag` - no value
- `Enum` - `/Option:` followed by one of a documented value set
- `Directory` - `/Option:` followed by a directory
- `File` - `/Option:` followed by a file (optionally filtered by extension) or a directory to descend into
- `Value` - `/Option:` followed by free text; a `<placeholder>` is offered

Tokens that end before the cursor form the context and the element under the cursor (cut at the cursor) is the word being completed, so editing an earlier token mid-line works. The first context token that matches a command (case-insensitively, including value-taking commands such as `/Set-Edition:Pro`) selects that command's switch set.

## Key completion behaviors / supported values

- At the root, it suggests every command plus the global switches, filtered by the typed prefix; an exact command such as `/Get-Features` still completes to itself.
- Once a command is on the line, it suggests that command's switches followed by the global switches.
- If the current token looks like `/Option:partialValue`, the completer:
  - suggests enumerated values (`/Format:Table|List`, `/LogLevel:1-4`, `/Compress:max|fast|none|recovery`, `/Set-ScratchSpace:32..512`, `/StubPackageOption:`, `/State:`)
  - completes directories for directory options (`/Image:`, `/WinDir:`, `/ScratchDir:`, `/MountDir:`, `/ApplyDir:`, `/CaptureDir:`, `/Source:`, ...)
  - completes files for file options, filtered by extension where documented:
    - `/PackagePath:` -> `.cab`, `.msu`, `.appx`, `.appxbundle`, `.msix`, `.msixbundle`, `.spp`
    - `/ImageFile:`, `/SourceImageFile:`, `/DestinationImageFile:` -> `.wim`, `.esd`, `.swm`, `.ffu`, `.vhd`, `.vhdx`
    - `/SWMFile:` -> `.swm`, `/SFUFile:` -> `.sfu`, `/Driver:` -> `.inf`, `/LogPath:` -> `.log`
  - offers a placeholder such as `/FeatureName:<feature-name>` for free-text values
- Path values keep exactly the prefix that was typed (`.\`, `C:\` and a trailing separator list that directory's children) and are quoted as a whole token when they contain spaces; a token that was already quoted keeps its quote style.
- Every result carries the documented description as its tooltip.

## Dependencies or external command expectations

- Works without `dism` being runnable: the static catalog covers the documented surface.
- Live enrichment only runs from an elevated shell and never blocks the prompt (stdin closed, timed out).
- Feature, capability and package names are placeholders: the read-only Dism PowerShell cmdlets also require elevation.

## Usage / loading example

```powershell
. .\dism_completer.ps1
```

Example scenarios after loading:

```powershell
dism /<Tab>
dism /Online /<Tab>
dism /Online /Cleanup-Image /<Tab>
dism /Format:<Tab>
dism /Mount-Image /ImageFile:C:\Images\<Tab>
```

## Limitations / notes

- The static catalog follows the Microsoft Learn DISM reference; a command that exists only in a newer DISM build shows up only through elevated live help.
- Mutual exclusions (for example `/Online` versus `/Image:`) are not enforced, and switches already on the line are still offered.
