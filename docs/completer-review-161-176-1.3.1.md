# Native completer review: scripts 161–176 (1.3.1)

**Scope:** The final 16 tracked standalone completer scripts at `v1.3.1`, commit `04cdd463f999cba23324f6ca18907854fd2f6dc5`. Four reviewers each covered four scripts and their same-stem guides. Positions are one-based in the commit tree, not a sort of command names or a working-directory listing:

```powershell
$sha = '04cdd463f999cba23324f6ca18907854fd2f6dc5'
[string[]]$paths = @(git ls-tree -r --name-only $sha |
    Where-Object { $_ -cmatch '^([^/]+_completer)/\1\.ps1$' })
[Array]::Sort($paths, [StringComparer]::OrdinalIgnoreCase)
$paths[160..175]
```

There were 176 eligible full repository-relative paths, with no ties under the comparer. Position 160 was `wc_completer/wc_completer.ps1`; the last 16 run from `wecutil` through `zip`. Sorting the full paths puts `wslc_completer/` before `wsl_completer/` and `wtcli_completer/` before `wt_completer/`.

**Batch checks:** All 16 working-tree scripts matched the pinned blob IDs under Git's content filters. PowerShell 7.7.0 parsed all 16 with zero errors; each AST had one native registration site. Each had a matching non-trusted set entry for both the bare and `.exe` native names. CompleterActions 3.0.1 `Test-CompleterScript` returned zero findings for each. Dot-sourcing each script in a fresh PowerShell runspace completed with zero load errors. These checks establish neither CLI-version parity nor correct completion behavior.

**Fix first, in order:**
1. **Actions on Tab:** Xargs can launch the wrong executable to discover help. WSLC can issue an activating list against a session whose running status is stale. Where and Xargs can inspect a network directory merely because it is on PATH; Xargs, Xcopy and Zip can also inspect nonlocal argument paths.
2. **Changes to the proposed command:** Wevtutil and Where insert some discovered names as PowerShell syntax, and Xargs can split a child executable name. A native effect would require accepting **and then executing** the completion; the parser checks did not execute anything.
3. **Routing and availability:** Preserve the active word when editing mid-line, stop at child-command and option boundaries, and put deadlines on discovery. The WTCLI timing fixture shows why checking a deadline only after nested calls is insufficient.

**Evidence and limits:** Line anchors refer to the pinned script in each heading unless the companion guide is named. `¦` marks the cursor; examples are completion inputs, not commands to run. **High** denotes target-integrity or unintended external-action risks, **Medium** an incorrect completion or potentially blocking discovery, **Low** a narrower coverage, metadata or cache defect. *Observed* means reproduced at the stated fixture, callback or parser boundary; *static* means traced in source, not reproduced against a live target. No live administrative action, network probe or execution of suggested command text was needed. The Pester/package gate, packaged lazy import, interactive PSReadLine behavior and parity with installed CLI versions were not tested.

## Review 1 · 161–164

**Coverage and limits:** Registered callbacks exercised via `TabExpansion2` with fixture data and a sentinel for zero custom matches to distinguish them from host filesystem fallback. No live help, subscription, event log, publisher, PATH scan, identity or remote lookup.

### 161. `wecutil_completer/wecutil_completer.ps1`

**Reviewed:** Verb/help catalog, subscription names, XML paths and format values.

**Medium · quoted and escaped arguments (117–155, 710–714, 742–746; observed).** `wecutil.exe gs Su¦` offered the fixture subscription `'Sub One'`; quoting the same verb as `"gs"` yielded no match. A backtick-escaped space in the subscription prefix also broke matching. Compare literal command-element values, retaining the raw extent separately for replacement.

**Medium · subscription names (465–471; observed).** With synthetic enumeration output containing `東京` and `Laboratory`, only the latter survived the ASCII alphanumeric filter. Separate successful enumeration from diagnostic output without filtering out non-Latin names.

### 162. `wevtutil_completer/wevtutil_completer.ps1`

**Reviewed:** Event-log verbs, verb-specific inline values, paths and lazy log/publisher lists.

**High · path insertion (41–55, 440–442, 628–633, 666–671; observed path, static shared renderer).** For `wevtutil.exe im Te¦`, a stub directory named `Team;West` was inserted bare. The semicolon ends the command rather than remaining part of the path. Render discovered names as literal arguments; quoting only names with whitespace also leaves interpolation possible.

**Medium · cursor state (683–705; observed).** `wevtutil.exe gl Te¦ /f:Text` lost the matching log `Team One`. The callback counts the active operand as already supplied when another element follows it. Build state only from elements preceding the replacement span.

**Medium · options on the wrong verb (126–140, 344–356, 400–405, 707–731; observed).** `im /a:¦` offered four authentication values and `im /r:¦` a computer placeholder. Neither option belongs to the script’s manifest-install catalog. Check verb membership before dispatching inline values.

**Low · empty discovery cache (598–620, 636–658; observed with availability stub).** An empty log or publisher list bypasses its 120-second TTL and triggers discovery on the next Tab. Two updates for each list made four availability checks rather than two. Cache completed empty results by timestamp.

### 163. `where_completer/where_completer.ps1`

**Reviewed:** `where.exe` versus the PowerShell alias, recursive directory operands and PATH executable names.

**High · literal insertion (115–125, 155–157, 225–229; observed).** `where.exe /R Te¦` returned bare `Team;West\` from a directory fixture; `where.exe To¦` returned bare `Tool Box.exe` from the PATH-name fixture. The first splits the command, the second splits the search pattern. Match raw names but insert one literal argument.

**Medium · PATH lookup can reach a share (175–201; static).** An ordinary name prefix can scan every PATH directory, including UNC entries, without a locality check or deadline. Skip nonlocal roots before filesystem calls and cache empty results. No share was contacted or delay measured.

**Medium · cursor state (287–305; observed).** Adding a later pattern, as in `where.exe /R Te¦ *.exe`, removed the directory match. Locate the active word by extent instead of dropping the final element.

### 164. `whoami_completer/whoami_completer.ps1`

**Reviewed:** Windows/GNU catalog selection, terminal identity switches, summary flags and format values.

**Medium · terminal echo truncates input (100–121, 231, 245–251, 321–326, 342–350; observed).** On the Windows fixture, `whoami.exe /UPN abc¦def` returned `abc` for a replacement span covering all six letters. Accepting the purported unchanged echo drops `def`. Use the full element when preserving user text.

**Medium · quoted terminal switch (125–136, 150–158, 187–191; observed).** `whoami.exe '/UPN' /¦` offered all eleven switches, including `/ALL`, instead of recognizing the terminal identity mode. Match parsed literal values rather than stripping only double quotes.

**Medium · explicitly selected executable (67–76, 335–337; observed).** With bare `whoami` resolving to a GNU fixture, completion on an explicitly qualified System32 `whoami.exe` offered GNU-only `--help` and `--version`. Select the catalog using the application named in the invocation, not a session-wide lookup of the bare name.

## Review 2 · 165–168

**Coverage and limits:** Registered completions with an in-memory WinApp schema and fixture profile, directory, process and distribution names. Empty custom output was distinguished from filesystem fallback. No schema probe, recording session, sandbox or WSL administrative operation was run.

### 165. `winapp_completer/winapp_completer.ps1`

**Reviewed:** Cached CLI schema, command tree, flag aliases, enums and path overlays.

**Medium · cursor state (783, 814–835, 847–877; observed).** `winapp r¦` returned `run`; adding text to the right (`winapp r¦ new`) removed that match because `new` selected a different schema node. Commit only elements before the active word.

**Low · flag versus value (826–835, 854–860, 915–928; observed).** At `winapp run --arch¦` there was no match: the current flag was already treated as a value prefix. After a space, the architecture values appeared. Keep the exact flag eligible until the separator.

**Low · slash aliases (502, 518–540, 925–928; observed).** `winapp /¦` offered neither `/?` nor `/h` despite those aliases in the fixture schema. Match schema-declared slash aliases without treating arbitrary paths as options.

**Low · guide (89, 604–610; static).** The directory overlay for the `create-external-catalog` operand agrees with the companion guide at line 53, not the placeholder listed at line 161. Correct the table.

### 166. `wpr_completer/wpr_completer.ps1`

**Reviewed:** Static actions, profile discovery, plus-delimited profile lists, process names and flags.

**Medium · discovery has no deadline (372–383, 398–404; static).** Tab can invoke `wpr.exe -profiles` synchronously, without closing stdin or bounding the wait. The cache cannot help while the first call is blocked. Close stdin, bound the read and wait, and cache the outcome. No hang was observed.

**Medium · profile list arity (782–787; observed).** `wpr -profiledetails Example ¦` offered bare profile names again rather than `-filemode`. The list is one plus-delimited operand (guide line 14); `Example+Ex¦` correctly extended that operand. Return to option completion once the list is committed.

**Medium · custom profile source (383, 410–429; observed callback).** For `Demo.wprp!`, the callback appended the fixture’s built-in profile `BuiltInOnly` and detail suffixes. It queried only unqualified `-profiles`, never the named profile definition. Use names verified for the specified local file, or preserve the prefix without inventing file-specific profiles.

### 167. `wsb_completer/wsb_completer.ps1`

**Reviewed:** Sandbox commands, cached ID lookup, separate and attached values, host directories and guest placeholders.

**Medium · quote boundaries (166–198, 367–376, 607–625; observed).** `wsb share --host-path "Test ¦` returned share flags rather than continuing the matching directory: the trailing space was still inside an open quote. Quoting a completed verb (`wsb "exec" --ru¦`) also lost `--run-as`. Use literal AST values for completed words and the active extent for unfinished ones.

### 168. `wslconfig_completer/wslconfig_completer.ps1`

**Reviewed:** Legacy WSL root modes, list modifiers, cached distributions and terminal states.

**Medium · cursor offsets (54–55, 263; observed).** `wslconfig /s Te¦zz` offered the two matching fixture distributions. Prefixing the same input with `0; ` made it echo `Tezz`: an absolute cursor was used to slice command-relative text. Rebase the offset or compare absolute element extents.

**Medium · distribution insertion (231–241; observed).** `wslconfig.exe /s Te¦` inserted `Test Distro` bare, making two arguments; an open quoted prefix only echoed the prefix. Decode for lookup and render each distribution as one literal.

**Medium · unbounded lookup (166–196; static).** The synchronous `wslconfig.exe /l` has neither a stdin guard nor a deadline. The 15-second result cache only takes effect after return. Bound the subprocess as for WPR.

**Low · list modifiers (137–140, 160, 207–214, 289–319; observed).** Root `/¦` offered `/all` and `/running`, and `/l /all ¦` reopened root commands. Restrict modifiers to list mode and do not restart root dispatch after one is consumed.

## Review 3 · 169–172

**Coverage and limits:** Parsed command lines and invoked captured registration callbacks with fixture help, settings, windows, tabs, sessions and distributions. These are callback results, not host menu tests. No terminal was launched, no real COM discovery ran, and no container, session or distribution was accessed.

### 169. `wslc_completer/wslc_completer.ps1`

**Reviewed:** Help-derived command tree and aliases, static fallback, short options, cache lifetimes, scoped image and container lookup, and passthrough tails.

**High · stale running-session check (767–771, 793–798, 837–839, 874; recorded calls, conditional impact).** After the fixture session stopped, the first image lookup reused its cached running status and sent `--session fixture images --format json` without rechecking. The guide (line 41) explains why discovery avoids stopped sessions: the CLI can activate them. No activation was observed. Prefer a non-activating query or a placeholder where no such query exists; refreshing the status only narrows the race.

**Medium · session insertion (1078–1088, 1110–1112; observed).** `wslc --session Bu¦` inserted fixture `Build Lab` as two words. Match the decoded name and quote it as one literal, preserving the option prefix for attached values.

**Medium · qualified image names (942–949, 1331–1333, 1346; observed).** The fixture image `registry.example/team/demo:latest` matched `wslc run registry.example¦` but disappeared when the prefix grew to `registry.example/team¦`. The slash sends it to path lookup before the image slot is considered. Select the operand kind before applying filesystem heuristics.

**Medium · passthrough grammar (349–362, 715, 1271–1277; synthetic help).** With a leaf usage ending in `<container> [<command>]`, `wslc exec demo --us¦` offered the host’s `--user`. The parser skips the optional command as if it were a subcommand selector. Distinguish dispatch groups from child-command tails; the fixture establishes the parser behavior, not the spelling of installed help.

### 170. `wsl_completer/wsl_completer.ps1`

**Reviewed:** Host flags, distributions, list/version/shell-type values and child-command boundaries.

**Medium · discovery on Tab (8–14; static).** Each distribution lookup invokes unqualified `wsl -l -q` without a timeout, closed stdin or cache. Resolve the native application and bound and cache the lookup; no live invocation or delay was tested.

**Medium · cursor and quoted state (70–80, 155–157; observed).** `wsl --shell-type lo¦ --list --quiet` lost `login`; `wsl --set-version "Build Lab" ¦` returned root switches instead of versions 1 and 2. The regex tokenizes the whole command and splits quoted words. Read settled AST elements before the active word.

**Medium · child arguments (92–97, 125–132, 192; observed).** `wsl --exec tool --us¦` returned host flag `--user` after the child boundary. Stop host completion at `-e`, `--exec` or the committed terminator before looking up values.

**Medium · distribution insertion (50–58; observed).** `wsl -d Bu¦` inserted fixture `Build Lab` as two words. Serialize the selected name as one literal argument.

**Low · literal prefix (50; observed).** `wsl --list --[¦` raised an invalid-wildcard error. Compare by literal prefix rather than interpolating the typed word into a wildcard.

### 171. `wtcli_completer/wtcli_completer.ps1`

**Reviewed:** Aliases, case-sensitive flags, profile settings, help cache and optional window/tab/pane discovery.

**Medium · discovery budget (529, 550–555, 571–578; fixture and static).** Four fixture windows resulted in four tab-list and four pane-list calls. The advertised 2.5-second walk budget is checked only after the tab list is materialized; separate 1.5-second waits can therefore exceed it. Pass a shared deadline through nested lookups and cap each wait by the remaining time. With five simulated 800 ms tab-list calls, the helper took 4.23 seconds and returned no panes. That measures the fixture, not real server latency.

**Medium · profile insertion (714–715, 785–789; observed).** `wtcli new-tab -p Lab¦` inserted the fixture profile `Lab <dev>` bare. A real name containing angle-bracketed text is mistaken for an authored placeholder, bypassing quoting. Mark actual placeholders explicitly and serialize profile names as literals.

### 172. `wt_completer/wt_completer.ps1`

**Reviewed:** Terminal subcommands, root and subcommand options, window selectors and named settings.

**Medium · global value dispatch (358, 373–379, 413–419; observed).** `wt -w l¦` returned `last`, but `wt.exe nt -w l¦` and `wt nt --window=l¦` returned no value. The walker recognizes global options after the subcommand; the value dispatcher only checks that subcommand’s table. Use the same option set for both.

**Medium · profile quoting (99–106, 427, 443–444; observed and reparsed).** For the profile `Team’s Lab` (U+2019), the suggested `'Team’s Lab'` failed to parse with `TerminatorExpectedAtEndOfString`. PowerShell recognizes the typographic apostrophe as a delimiter. Test literal serialization by reparsing names containing both ASCII and typographic quotes.

**Low · profile prefix (429; observed).** With fixture profile `Lab[1]`, `wt -p Lab[¦` threw an invalid-wildcard error. Use a literal prefix comparison.

## Review 4 · 173–176

**Coverage and limits:** Static source and guide review plus captured registration callbacks with inert option/name/path fixtures and parser checks (not end-to-end menu tests). No child command, copy, archive action, unbounded output producer, remote path or discovered executable was run. Filesystem locality and timeout findings describe reachable code, not observed traffic or measured hangs.

### 173. `xargs_completer/xargs_completer.ps1`

**Reviewed:** PATH/PATHEXT help selection, option grammar, argument-file paths, child executable names and handoff.

**High · wrong executable launched for help (62–72, 158–171, 183–185; static, name predicate checked).** The cold lookup enumerates `xargs.*` and compares only the last extension with PATHEXT. A sibling named `xargs.preview.exe` qualifies even if there is no `xargs.exe`. The selected path is passed to the help subprocess on Tab. Resolve the exact executable basename and extension before starting a process.

**High · nonlocal filesystem access (154–164, 327–337; static).** A UNC PATH entry can reach directory enumeration during option discovery; a typed remote argument-file parent can reach path probing. Reject nonlocal roots before either lookup.

**High · child selection (407–410, 423–425; observed).** With fixture executable `tool name`, `xargs to¦` inserted the bare name; reparsing yielded two operands and changed the child executable to `tool`. Render each name as a single literal argument.

**Medium · child boundary (441–462, 511–522; observed).** `xargs echo --he¦` still offered xargs’s `--help`, while `xargs -- to¦` missed a matching fixture executable because the terminator counted as the child. Consume xargs options and the terminator first, then distinguish the child slot from its arguments.

**Medium · cursor prefix (296–301, 511–518; observed).** `xargs --arg-file=alpha¦BAD` lost the matching file `alpha file.txt` by matching the whole element. Use only the prefix for lookup even when replacing the full token.

**Medium · invalid value hint (381–398; static).** The separate value slot after `-n` inserts bare `<max>`, which is shell syntax rather than a numeric argument. Put the hint in the label, not in the command line.

### 174. `xcopy_completer/xcopy_completer.ps1`

**Reviewed:** Help-seeded switches, dates, source and destination paths, and chained `/EXCLUDE:` values. The fixture `/EXCLUDE:al¦` correctly returned `'/EXCLUDE:alpha file.txt'`.

**High · nonlocal path access (429–440, 548, 608–613; static).** Positional and exclusion-file completion pass the supplied parent to `Get-ChildItem`. `-LiteralPath` prevents wildcard expansion, not UNC or provider access on Tab. Require a local filesystem parent before enumeration; leave other paths opaque.

**Medium · help command resolution (15–25; static).** Testing whether `xcopy.exe` exists and then invoking it by name admits a same-named function or alias. Require an Application and invoke its resolved path with bounded input and wait semantics.

### 175. `yes_completer/yes_completer.ps1`

**Reviewed:** Help and fallback options, option terminator, literal strings, quoted input and value hints.

**Medium · unbounded help output (13–22; static).** The first flag completion collects all output from `yes --help` into a string. An implementation that treats `--help` as text to repeat need never finish. Closing stdin does not stop an output producer. Use the static flags or bound both runtime and captured output.

**Medium · unfinished quoted text (98–107, 156–168; observed).** At `yes "abc ¦`, the callback offered `<string>`, `y` and `n`, treating the space inside the quote as an empty operand. Accepting a candidate would discard the typed text. Use the active element’s extent.

**Medium · end of options (171–179; observed).** `yes -- --he¦` offered `--help` instead of treating the prefix as text. Honor a committed `--` before flag matching.

**Medium · invalid string hint (122–125; parser check).** The empty slot inserts bare `<string>`; reparsing `yes <string>` produced `RedirectionNotSupported`. Keep the placeholder in the menu label, not as raw command text.

### 176. `zip_completer/zip_completer.ps1`

**Reviewed:** Help-derived option catalog, archive and input paths, attached values, short clusters, pattern lists and option termination.

**High · nonlocal path access (962–975; static).** Archive, input, directory and pattern completions enumerate the typed parent without checking filesystem provider or locality. A remote parent can trigger I/O on Tab. Gate enumeration before calling the provider.

**Medium · attached quoted path (85–97, 767–805, 1231–1240; observed).** With fixture file `alpha file.txt`, `zip --out="al¦` returned `'--out="al.zip'`. The opening quote became part of the proposed filename. Decode the value portion before lookup and serialize the resulting option and value once.

**Medium · pattern-list clusters (904–916; observed).** With fixture help for `-d` and `-r`, `zip -drxalpha ¦` returned generic archive/options rather than continuing the `-x` pattern list. Keep list mode active when its first pattern is attached to the cluster.

**Medium · pending value precedence (1237–1241, 1260–1262; observed).** At `zip -Z -s¦`, the callback offered split sizes such as `-s1g` even though the compression-method slot was pending. Resolve the required value before interpreting a new inline option.

**Medium · invalid password hint (1165–1167; observed and reparsed).** The candidate after `zip -P ¦` was bare `<password>`, which produces `RedirectionNotSupported`. Show the hint as a label rather than inserting parser syntax.

**Medium · help identity and latency (22–25, 42–44; static).** Unrestricted command resolution can select a session function for three synchronous help probes, none with a stdin or time bound. Require a native Application, invoke its resolved path and bound the probes.
