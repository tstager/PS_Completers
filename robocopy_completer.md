# robocopy completer

## What it completes / overview

`robocopy_completer.ps1` registers a native argument completer for `robocopy` and `robocopy.exe`.

The completer combines data parsed from `robocopy.exe /?` with script-defined metadata for options that need value-aware completion. It also completes positional paths, file specs, directory specs, inline option values, and `.rcj` job names.

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName 'robocopy', 'robocopy.exe' -ScriptBlock { ... }
```

Load it into the current session with:

```powershell
. .\robocopy_completer.ps1
```

## How completion works

### Initialization

On first use, the script builds a script-scoped catalog:

- calls `robocopy.exe /?`
- parses help tokens that look like Robocopy options
- merges those parsed options with a static metadata table for options that need structured value completion
- stores the final option list in `$script:RobocopyCompletionCatalog`

The help-derived catalog supplies option names and descriptions, while the static metadata adds behaviors such as inline value completion, path completion, flag completion, and job-file completion.

### Positional argument handling

The completer treats the first two non-option arguments as the normal Robocopy positional directories:

1. source directory
2. destination directory

While fewer than two positional directories have been provided, completion returns directory path suggestions.

After both directories are present:

- a blank token returns both file-spec suggestions and option suggestions
- a non-empty non-option token returns file-spec suggestions

### Context-sensitive option handling

If the current token starts with `/`, the completer:

1. checks whether the token is an inline value form such as `/COPY:` or `/LOG:`
2. returns value-aware suggestions when supported
3. otherwise falls back to option-name completion

### Source-relative multi-value modes

The script tracks pending separate-value modes for:

- `/XF` for file exclusions
- `/XD` for directory exclusions

When either option has just been entered, subsequent completion uses the resolved source directory so relative file or directory suggestions are based on the Robocopy source tree.

## Key completion behaviors / supported values

### Option completion

Option names come from a merged catalog of:

- `robocopy.exe /?` output
- static metadata inside `Get-RobocopyStaticOptionMetadata`

The static metadata specifically teaches the completer about richer value completion for options such as:

- `/COPY:`
- `/DCOPY:`
- `/A+:`, `/A-:`, `/XA:`, `/IA:`
- `/LEV:`, `/MON:`, `/MOT:`, `/RH:`, `/IPG:`
- `/MT`, `/SPARSE`, `/LFSM`
- `/IOMAXSIZE:`, `/IORATE:`, `/THRESHOLD:`
- `/MAX:`, `/MIN:`, `/MAXAGE:`, `/MINAGE:`, `/MAXLAD:`, `/MINLAD:`
- `/R:`, `/W:`
- `/LOG:`, `/LOG+:`, `/UNILOG:`, `/UNILOG+:`
- `/JOB:`, `/SAVE:`
- `/XF`, `/XD`

### Path completion

Path completion is used for:

- source and destination positional directories
- inline path options such as `/LOG:` and related log-file options
- rooted paths typed inside source-relative contexts

Directory completions append a trailing `\`. Values are quoted when needed for spaces or when the input already started with a quote.

### File and directory spec completion

After the source and destination directories are present, the completer suggests:

- wildcard file patterns: `*`, `*.*`
- source-relative files and directories for general file-spec completion
- source-relative directories only for `/XD`

If the source directory cannot be resolved, source-relative suggestions are effectively unavailable.

### Inline flag and list values

For supported inline options, the completer can suggest:

- predefined list values such as counts, sizes, times, or schedule-like samples
- progressively built flag strings for attribute-style options

Examples include:

- `/COPY:` suggestions built from allowed characters `DATSOUX`
- `/DCOPY:` suggestions built from allowed characters `DATEX`
- `/A+:`, `/A-:`, `/XA:`, `/IA:` suggestions built from documented attribute letters

### Job-file completion

For `/JOB:` and `/SAVE:`, the completer looks for `*.rcj` files in the current directory and offers the file name without the `.rcj` extension.

## Dependencies or external command expectations

This completer expects:

- `robocopy.exe` to be available, otherwise it returns no completions
- local filesystem access for path, wildcard, and source-relative suggestions
- current-directory access to discover `*.rcj` files for `/JOB:` and `/SAVE:`
- a resolvable source directory if you want relative suggestions for file specs, `/XF`, or `/XD`

## Usage / loading example

```powershell
. .\robocopy_completer.ps1

robocopy C:\Source\ C:\Dest\ <TAB>
robocopy C:\Source\ C:\Dest\ /LO<TAB>
robocopy C:\Source\ C:\Dest\ /COPY:<TAB>
robocopy C:\Source\ C:\Dest\ /XF <TAB>
```

## Limitations / notes

- The script only provides structured separate-value handling for `/XF` and `/XD`.
- Optional inline-value options such as `/MT`, `/SPARSE`, and `/LFSM` are completed when you type the inline form, for example `/MT:`.
- Source-relative completion depends on the first positional argument resolving to an existing directory.
- The option catalog is initialized from the installed `robocopy.exe` help text plus the script's static metadata, so descriptions track the local tool reasonably closely.

