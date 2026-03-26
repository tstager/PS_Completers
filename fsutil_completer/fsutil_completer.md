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
3. lazily runs `fsutil <path> /?` for deeper nodes when a path appears to have nested verbs

This keeps top-level and family verb completion aligned with the installed `fsutil` binary while still allowing deeper command trees such as `resource setLog ...` to expand when needed.

## Value-aware coverage
The completer adds focused value suggestions for commonly useful grammars, including:
- `fsutil 8dot3name set`
- `fsutil behavior query`
- `fsutil behavior set`
- `fsutil file queryAllocRanges`
- `fsutil file queryFileNameById`
- `fsutil fsInfo driveType`
- `fsutil objectID set`
- `fsutil repair enumerate`
- `fsutil repair set`
- `fsutil repair wait`
- `fsutil storageReserve findByID`
- `fsutil transaction query`
- `fsutil usn createJournal`
- `fsutil usn deleteJournal`
- `fsutil usn enableRangeTracking`
- `fsutil volume allocationReport`
- `fsutil volume findShrinkBlocker`
- `fsutil volume queryCluster`
- `fsutil wim enumFiles`

The value layer favors:
- drive / volume path suggestions such as `C:` and `C:\`
- file and directory path completion for true path slots
- literal enums such as `0|1`, `0-3`, `NTFS|ReFS`, `/D`, `/N`, `$corrupt`, `$verify`
- safe placeholders or examples for IDs, GUIDs, offsets, lengths, clusters, and similar numeric values

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
- Many `fsutil` leaf help pages are inconsistent; some return a `Usage:` page, while others reject `/?` and only expose nested verb lists. The completer handles both patterns.
- Free-form non-path values are intentionally hint-oriented rather than exhaustive. It avoids risky or expensive live discovery for things like file IDs, object IDs, and transaction IDs.
- For free-form non-path slots, the completer echoes the current token when needed so PowerShell does not fall back to unrelated filesystem suggestions.
- Filesystem fallback is only used for slots that are actually paths.
