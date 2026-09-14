# fsutil completer

## What it does
`fsutil_completer.ps1` registers a standalone native completer for `fsutil` and `fsutil.exe`.

It combines:
- a cached command tree parsed from local `fsutil` help
- cached family help for the top-level subcommand catalog
- targeted static metadata for high-value value completion where the grammar is stable

## Registration
- Uses `Register-ArgumentCompleter -Native`
- Targets `fsutil` and `fsutil.exe`
- Enables `Set-StrictMode -Version 2.0`

```powershell
. "$PSScriptRoot\fsutil_completer.ps1"
```

## Command tree behavior
On first use, the script:
1. runs bare `fsutil` to collect the top-level command families
2. runs bare `fsutil <family>` once per family to collect leaf verbs
3. runs bare `fsutil resource setLog` (the only two-token node with sub-verbs) to collect its listing
4. runs bare `fsutil behavior query` and `fsutil behavior set`, which print their option tables, for the behavior metadata

Nothing else is ever executed: pressing Tab after any other two-token path never runs `fsutil <family> <verb>` or `fsutil <family> <verb> /?`, because several verbs treat `/?` as an operand (`fsutil tiering queryFlags /?` tries to open a volume named `/?`) and set-style verbs would perform their operation. Every invocation goes through a `System.Diagnostics.Process` with stdin closed and a 5-second timeout, so a verb that blocks cannot stall the prompt. Help-entry parsing accepts a single space between verb and description, so a verb that fills the column (`file queryExtentsAndRefCounts`) is not dropped.

The cursor is rebased on `CommandAst.Extent.StartOffset`, so completion works when `fsutil` is not the first statement on the line, and only elements that end before the cursor count as completed tokens, so a cursor inside an earlier token completes that token's prefix.

## Value-aware coverage
Every leaf whose usage line was captured from the installed binary (10.0.26100) has an argument model: positionals, `/x` options, `name=value` tags (`startUsn=`, `format=`, `Action=`, `q=`) and bare keywords (`csv`, `wait`, `tail`). Handlers cover the irregular grammars, including:
- `fsutil 8dot3name set`
- `fsutil behavior query`
- `fsutil behavior set` (value shapes such as `<0-3> | <0|1>`, `<1|2>` and `<0-15>` are expanded from the live option table; `symlinkEvaluation` offers `L2L:0`/`L2L:1`/`L2R:...`/`R2L:...`/`R2R:...`)
- `fsutil file queryAllocRanges` and `fsutil file setZeroData`
- `fsutil file queryFileNameById`
- `fsutil fsInfo driveType`
- `fsutil objectID set`
- `fsutil repair enumerate`, `fsutil repair set`, `fsutil repair wait`
- `fsutil storageReserve findByID`
- `fsutil transaction query`
- `fsutil usn createJournal`, `fsutil usn deleteJournal`, `fsutil usn enableRangeTracking`
- `fsutil usn enumData` (`<file ref#> <lowUsn> <highUsn> <volume pathname>`) and `fsutil usn readJournal` (`csv`, `wait`, `tail`, `minVer=`, `maxVer=`, `startUsn=`)
- `fsutil volume allocationReport`, `fsutil volume findShrinkBlocker`, `fsutil volume queryCluster`
- `fsutil wim enumFiles`

The value layer favors:
- drive / volume path suggestions such as `C:` and `C:\`
- file and directory path completion for true path slots
- literal enums such as `0|1`, `0-3`, `NTFS|ReFS`, `/D`, `/N`, `$corrupt`, `$verify`, `/TrNH`, `CSV|XML|EVTX|TXT|No`
- safe placeholders or examples for IDs, GUIDs, USNs, offsets, lengths, clusters, and similar numeric values

## Examples
```powershell
. "$PSScriptRoot\fsutil_completer.ps1"

# Root families
# fsutil <TAB>
# fsutil.exe <TAB>

# Family leaf verbs
# fsutil file <TAB>
# fsutil volume <TAB>
# fsutil usn <TAB>

# Value-aware examples
# fsutil behavior query <TAB>
# fsutil file queryAllocRanges <TAB>
# fsutil objectID set <TAB>
# fsutil usn deleteJournal <TAB>
# fsutil volume queryCluster <TAB>
```

## Notes and limitations
- `fsutil /?` is not used for root discovery because bare `fsutil` is the authoritative top-level help entry point on this machine.
- Leaf usage is never probed live (`/?` is an operand for several verbs); the per-leaf grammar is a static table transcribed from the usage lines the binary prints when a verb is invoked without its required arguments.
- Zero-argument verbs (`fsInfo drives`, `volume list`, `transaction list`) have no argument model and fall through to PowerShell's filesystem completion.
- Free-form non-path values are intentionally hint-oriented rather than exhaustive. It avoids risky or expensive live discovery for things like file IDs, object IDs, and transaction IDs.
- For free-form non-path slots, the completer echoes the current token when needed so PowerShell does not fall back to unrelated filesystem suggestions.
- Filesystem fallback is only used for slots that are actually paths.
