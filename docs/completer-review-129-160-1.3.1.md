# Native completer review: scripts 129–160 (1.3.1)

**Scope:** This fifth batch covers positions **129–160 of 176**, one-based, at tag `v1.3.1` and commit `04cdd463f999cba23324f6ca18907854fd2f6dc5` (also the reviewed HEAD). Each of the eight reviews below covers four consecutive paths. To reproduce the selection from the repository root:

```powershell
$base = '04cdd463f999cba23324f6ca18907854fd2f6dc5'
[string[]]$paths = @(git ls-tree -r --name-only $base | Where-Object {
    $_ -cmatch '^([^/]+_completer)/\1\.ps1$'
})
[Array]::Sort($paths, [StringComparer]::OrdinalIgnoreCase)
128..159 | ForEach-Object { '{0}. {1}' -f ($_ + 1), $paths[$_] }
```

**Baseline checks:** All 32 working-tree scripts matched their commit blobs under Git's content filters. PowerShell 7.7.0 parsed every script without errors and found one native registration site per script. Each has a matching non-trusted set entry with native targets. CompleterActions 3.0.1 `Test-CompleterScript` returned **zero findings** for this batch, including scripts with guarded literal cache initializers. These are source and strict-grammar checks, not a claim that the packaged set, installed binaries or every completion branch worked.

**Priorities:** Fix target changes first: Shred can turn part of one quoted filename into a second overwrite operand, ShellRunas drops an explicit local executable prefix, Tar offers option-shaped archive members, Tskill offers local process and session candidates for a remote server, and Tasklist inserts dynamic titles in a form PowerShell can expand. These change the proposed command; any native effect requires accepting **and executing** it. In contrast, filesystem lookups happen **on Tab**: Takeown passes an alternate UNC spelling to lookup, and Stdbuf can scan network directories on PATH even without a remote prefix. Next, fix option boundaries (especially `--` and wrapped commands), then value slots that return filenames or unparseable placeholders.

**Evidence and limits:** Line numbers refer to the script in each heading unless otherwise named. `¦` marks the cursor; the examples are completion inputs, not instructions to execute. **High** denotes target-integrity or unintended external-action risks; **Medium** denotes incorrect routing/insertion or a potentially blocking lookup; **Low** denotes narrower coverage, cache or documentation issues. Results labeled fixture or callback are observations at the stated boundary, not live native-tool behavior. Static concerns were traced in the code, not reproduced against a real target. No destructive operation, network share, credential service or live administrative inventory was exercised. This was not a full CLI-version, loader, PSReadLine or performance test.

## Review 1 · 129–132

**Coverage and limits:** Read four full scripts, their companion Markdown and root README. Static top-level inspection and captured registration: each has `Set-StrictMode` at 4, function definitions and one literal `Register-ArgumentCompleter -Native` for the stem + `.exe` (129:351; 130:225; 131:357; 132:298). No import shape defect or import-time discovery confirmed; actual importer not run by this reviewer. In fresh no-profile PowerShell, intercepted registration, then registered a forwarding wrapper passing the native `TabExpansion2` arguments to the original blocks. Stubbed tool discovery, `Test-Path`, and bounded `Get-ChildItem` results (e.g., `fixture.txt`, `fixture tool.exe`, `2.log`); on no callback output, wrapper returned a fixture sentinel to avoid provider fallback; therefore no claims about host fallback based solely on this probe. Where noted, reparsed the string after replacing the reported span. No real tools/help, operations, filesystem targets, credentials, or suggestions executed.

### 129. `sha512sum_completer/sha512sum_completer.ps1`

**Reviewed:** import/targets, help cache/fallback, cursor cut, check-manifest ranking, flag clusters, path encoding and reconstruction.

- **Medium — split path still represents two operands (native fixture + parse).** At 207–233 prior operands are joined for lookup, but only the last fragment is emitted. `sha512sum .\Program Files\fi` replaced offset 20, length 8 with `'Files\fixture tool.exe'`, leaving `.\Program 'Files\fixture tool.exe'`: two inputs, not the single chosen file. Require a prequoted/escaped path; do not offer cross-token repairs unless the whole span can be replaced as one quoted argument.
- **Medium — terminator ignored (native fixture).** At 317–347, `sha512sum -- -` yields `-b`, `--binary`, etc., rather than operand `.\-fixture.txt`. Track a completed `--` before cursor and disable option/check-mode parsing past it.
- **Medium — diagnostic cached as catalog (native help stub).** At 15–21,32–55, failure output is merged, parsed anywhere in line and accepted if any token matches. Stub reporting exit 1 and `diagnostic: --fixture-only is not supported` yielded only `--fixture-only` for `sha512sum --`, replacing the fallback catalog. Require credible option declarations, taking exit status into account; retain the fallback if output is only diagnostic. Help fixture stands in for actual process.

### 130. `shellrunas_completer/shellrunas_completer.ps1`

**Reviewed:** import/targets, register/quiet/launch grammars, opaque later arguments, cursor and quoted segments, application + filesystem enumeration. No ShellRunas invocation or registration mutation found.

- **Medium — explicit local executable path discarded (native fixture).** At 110–123, `shellrunas .\fixture` produced `'fixture tool.exe'`, not `'.\fixture tool.exe'`. This changes an explicitly selected file into a search name. Preserve typed `.\`/`./`, regardless of normalized parent.
- **Medium — invalid placeholder inserted (native fixture + parse).** At 182–183, `shellrunas tool.exe ` inserts raw `<argument>`; reparsing the resulting line reports `RedirectionNotSupported`. Later args are intentionally opaque; do not insert syntax/placeholders to suppress fallback. Use a tested, non-inserting no-candidate policy, or deliberately allow fallback.

### 131. `shred_completer/shred_completer.ps1`

**Reviewed:** import/targets, help/cache, quoted tails, cursor, path quoting, option names, attached/separate values and operand fallback.

- **High — closing a quote changes filename text into another overwrite target (native fixture + parse).** At 157–165,348–353, `shred "fi¦ rest` yielded `"fixture.txt" rest`: native replacement spans the entire 8-character fragment; raw `rest`, originally *inside* a single unfinished filename, becomes a second, unquoted operand. No overwrite was performed. Do not append the suffix outside a closed quote; preserve it as literal filename text or decline the ambiguous completion.
- **Medium — value position inferred from end of line, not cursor (native fixture).** At 246–254,329–345, `shred -n 3¦ tail` offered fixture file `3.log`, not iteration count `3`. Determine previous option relative to cursor; keep a recognized value slot distinct from no matching suggestions.
- **Medium — optional erase mode offered as separate filename (native fixture + GNU grammar).** At 246–254,279–283, `shred --remove ` offered `unlink`, `wipe`, `wipesync`; for `--remove[=HOW]`, these are filenames in that position. Offer modes only for `--remove=`, operands otherwise. Real build not exercised.
- **Medium — ignores `--`** (329–345), same observed defect as 129 (`shred -- -` → `-f` etc., not the dash-prefixed operand); same fix. **Medium — diagnostic cached as catalog** (15–21,32–55), same fixture as 129, sole result `--fixture-only`; same fix. **Medium — invalid value placeholders** (258–277,298–302): `shred -n ` returns `3,<n>`; `<n>`/`<size>` do not form usable separate numeric values. Retain real examples and move metasyntax to tooltip.

### 132. `shuf_completer/shuf_completer.ps1`

**Reviewed:** import/targets, lazy help + fallback, cursor/quoted operand handling, generated range/count/path values, directories and attached/separate option routing.

- **Medium — right-of-cursor args affect value routing (native fixture).** At 205–213,275–295, `shuf -i ¦ tail` returned no callback output instead of the range branch; `shuf -n 2¦ tail` produced file `2.log` in count slot. Build state from left of cursor and suppress unrelated filesystem results on no-match for a recognized value type.
- **Medium — only count/range candidate invalid (native fixture + parse).** At 217–228,246–250, `shuf -n ` inserts `<count>` and reparses with `RedirectionNotSupported`; `<lo-hi>` likewise is metasyntax. Offer real examples (`1`, `1-10`) or no insertion, keep syntax in tooltip.
- **Medium — ignores `--`** (275–295), same observed defect as 129 (`shuf -- -` → `-e`, etc., not the dash-prefixed operand); same fix. **Medium — diagnostic cached as catalog** (15–21,32–55), same fixture as 129, sole result `--fixture-only`; same fix.

## Review 2 · 133–136

**Coverage and limits:** Read four scripts and companion guides at pinned HEAD; README 230–234 and set 1207–1239. All four have strict-mode, function declarations and literal native bare/.exe registrations (sigcheck:576, split:420, stat:393, stdbuf:432); sigcheck adds a guarded script catalog (6–46). No static import-shape defect. Fresh `pwsh -NoProfile` captured those registrations and exercised the blocks using parser ASTs, inert path/name fixtures, absent-command stub and stubbed discovery helpers; not native CLI or strict-import integration tests. `¦` marks cursor. No suggestions executed, no network or real local inventories queried.

**Shared completion-time I/O:** Stubbing `Test-Path`/`Get-ChildItem` recorded the UNC parent of `\\fixture.invalid\share\a` being passed to path lookup by **all four**: sigcheck 254–258 (list), split 195–208, stat 172–185, stdbuf 171–183 (test, list). No actual I/O performed. For sigcheck this conflicts with the guide's local-filesystem expectation; for coreutils this is a nonlocal Tab-time effect with explicitly entered remote paths, not evidence of scanning remote peers by default. Consider a local-only guard before provider calls; return a literal echo for nonlocal prefixes so native fallback does not retry the same path.

### 133. `sigcheck_completer/sigcheck_completer.ps1`

**Reviewed:** Static switches/slash forms, scan/catalog/offline/store modes, catalog/policy/output values, quote decoder/encoder, cursor rebasing, cached local certificate/CatRoot lookups. Does not launch Sigcheck/VirusTotal. **High · nonlocal lookup (254–258; stubbed).** See the shared UNC fixture above: the guide lists local filesystem access as a dependency, but a share path reaches enumeration.

**Medium · token boundary (160–193, 465–468, 538–542; fixture).** With `sigcheck -o 'Alpha ¦` a space inside the open quote is treated as a fresh slot and switches reappear alongside the CSV. With ``sigcheck -o Alpha` F¦`` (PowerShell backtick before the space), the callback echoes only `F` instead of completing the full filename `Alpha File.csv`. Positive control `'Alpha¦` matches the fixture CSV. Derive current and preceding arguments from AST extents/literal values rather than splitting command text.

### 134. `split_completer/split_completer.ps1`

**Reviewed:** Help/cache and absent-tool catalog, required and attached-only optional values, size candidates, unmatched-value echo, quoted paths and cursor-relative context. `split -b 1¦` returned all five documented size suggestions.

**Medium · option terminator ignored (244–256, 396–416; fixture).** `split -- --b¦` offers switch `--bytes` rather than the fixture filename beginning with that prefix; `split -- --bytes ¦` offers sizes rather than the next operand. Track a consumed standalone `--` and restrict subsequent slots to operands.

**Low · help resolution (15–21; static; also stdbuf 15–21).** Name-only `Get-Command` can resolve or auto-load a non-application. Its `Source` is not necessarily the intended executable. Restrict to Application, as stat does. No module autoload tested.

### 135. `stat_completer/stat_completer.ps1`

**Reviewed:** Application-only help/cache, fallback/format tables, file vs filesystem mode, cached values, raw/cooked path handling and quoting.

**Medium · context after the cursor (284–292, 369–390; fixture).** `stat --cached a¦ input.txt` returned `'Alpha File.csv'`; removing the trailing operand gave `always`. It checks the last AST element rather than the current one's predecessor. Bind the owner using absolute extents at the replacement slot.

**Medium · value vs operand fallthrough (271–302, 332–346, 369–390; fixture).** `stat -c fmt¦` returned `fmt.txt` instead of preserving the free format text; `stat -- --format ¦` offered format sequences after the option terminator. Distinguish unmatched but owned slots from operands and honor `--`.

### 136. `stdbuf_completer/stdbuf_completer.ps1`

**Reviewed:** Help/cache, MODE rules for input/output/error, wrapper COMMAND boundary, PATH name cache and path routing.

**Medium · wrapper/child boundary (301–336, 399–425; fixture).** `stdbuf dummy --out¦` offered wrapper `--output`; `stdbuf dummy -o ¦` offered wrapper MODEs. Those tokens belong to the child, including after explicit `--`. Use the wrapper parse state for value/option dispatch too, instead of only command-name lookup.

**Medium · MODE routing (220–228, 280–286, 399–402; fixture).** `stdbuf -o ¦ dummy` gave zero custom results vs `L, 0, <size>` at EOL. Quoted `stdbuf --output="L¦` and valid `stdbuf -o 4K¦` also emitted nothing, leaving the engine free to list files. Inspect the AST predecessor at the cursor, decode/requote typed MODEs and echo free-form sizes when there is no enumerated match.

**High · implicit remote PATH access (345–356, 408–410; static).** Even an ordinary bare COMMAND prefix triggers `Directory.Exists`/`Directory.GetFiles` on every PATH directory on cold cache, including network shares if configured. This does not require the user to type a remote path; no remote PATH was tested. Skip nonlocal directories before access or make remote scanning opt-in. See also shared name-only help lookup.

## Review 3 · 137–140

**Coverage and limits:** Read all four scripts, companion guides, root README, set entries and conformance test. CompleterActions 3.0.1 `Test-CompleterScript` reported zero findings on each; all four set entries match their literal bare and `.exe` registration names, `Trusted=False`. Behavioral examples below are direct completion callbacks with real parsed command ASTs in a profile-free PowerShell 7.7.0 process; registration, help command lookup and path I/O were stubbed. No native tool, suggestion, share or remote system was exercised; hypothetical effects are distinguished from callback observations. `¦` marks cursor.

### 137. `strings_completer/strings_completer.ps1`

**Reviewed:** Static Sysinternals switches, numeric value hints, cursor rebasing, quoted operands, environment/home expansion, filesystem fallback and registration (481–485).

**High · nonlocal I/O on Tab (313–324).** With `strings \\fixture.invalid\share\Al¦`, the enumeration stub received `\\fixture.invalid\share\`. Against the real provider this can initiate a connection merely by completing, contrary to the local-only scanning described in the guide (56, 73). Gate the resolved parent on a local filesystem before enumeration; ensure declining does not delegate the same remote token to host fallback.

**Medium · wrong path inserted (275–281, 348–355).** With fixture `COMPLETERFIX=X:\Sandbox`, `strings %COMPLETERFIX%\Al¦` enumerated `X:\Sandbox\` but returned `%COMPLETERFIX%\Alpha.txt`. Parse-only check classified that operand as a string constant; PowerShell does not expand CMD-style `%NAME%`. Insert the literal resolved path for this prefix and retain the typed spelling only as display text.

**Medium · non-insertable hint (360–364, 472–474; parser).** An empty directory/word produces a bare `<file-or-directory>` suggestion; parsing the resulting `strings <file-or-directory>` reports `RedirectionNotSupported`. Use a valid editable argument or keep the hint out of insertion text.

### 138. `sum_completer/sum_completer.ps1`

**Reviewed:** Lazy help/fallback catalog, case-sensitive flags, current extent, literal-prefix filename filtering, quoting, default-host handoff and registration (242–246).

**Medium · explicitly typed nonlocal path (165–180; stubbed).** `sum \\fixture.invalid\share\Al¦` forwarded the UNC parent to both the existence and directory-enumeration stubs. Real path lookup can connect to the share without executing `sum`. Guard resolved parents and fallback before provider operations.

**Medium · end-of-options ignored (223–239).** `sum -- --h¦` offered `--help` even though the word is a filename. Recognize `--` among completed pre-cursor elements and route subsequent arguments to paths.

**Low · missing fallback alias (12, 59–60).** With lookup stubbed unavailable, `sum -¦` returned `-r,--sysv,--help,--version`, missing the `-s` alias documented in `sum_completer.md:18`. Add it to the static fallback.

**Medium · unbounded cold help (13–22; static, also applies to tac:13–22).** Help is synchronous, unbounded through `Out-String`; piping `$null` only closes stdin, not a hung child or excessive output. Prefer the small static catalog or bound time/output and restrict lookup to the intended application. No real child launched or latency tested.

### 139. `systeminfo_completer/systeminfo_completer.ps1`

**Reviewed:** Singleton/dependency filtering, terminal help, `/FO` enum, optional password/switch routing and placeholder suppression; static catalog; registration (359–362).

**Medium · cursor/quote state (142–145, 253–256, 302–324).** `systeminfo /FO C¦ /NH` returned no CSV: the current word was included in prior state because only the final element is removed. Separately `systeminfo /FO "LIST" /¦` returned `/NH`, which the guide excludes: state compares raw quoted extent to `LIST`. Build prior state only from extents before the replacement span and use decoded literal values.

**Medium · password copied to display (26–29, 188–191, 344–346).** With only dummy text, `systeminfo /S box /U sample /P fixture-only¦` returned `fixture-only` as completion and list text. This adds a display surface for an already-typed secret; no external disclosure was observed. Do not echo credential material to the completion menu; favor omission/interactive prompt.

**Medium · non-insertable hints (185–186, 338–345; parser).** Selecting the bare `<password>` placeholder produces `RedirectionNotSupported`; same issue with bare `<computer-name>` and `<user>`. Put explanatory placeholders in display/tooltip, not syntactically invalid insertion text.

### 140. `tac_completer/tac_completer.ps1`

**Reviewed:** Cold help/fallback flags, attached/separate separator, cursor/quote parsing, literal-prefix paths and registration (315–319). Same static unbounded-help concern as sum (13–22).

**Medium · explicitly typed nonlocal path (167–186; stubbed).** `tac \\fixture.invalid\share\¦` sent the share path to both path stubs. Real provider calls may connect before execution. Gate nonlocal/provider paths and avoid reintroducing the same lookup via fallback.

**Medium · separator context lost (232–250, 264–271, 293–312).** `tac -s Al¦` returned the fixture filename `Alpha.txt` instead of preserving the arbitrary separator; `tac -s ¦ Alpha.txt` missed the blank separator entirely because it inspected the final AST element, not the one before the cursor. Treat recognized free-text slots as handled even when no enum matches and build state only up to the cursor. The only suggestion for an empty separate slot, `<string>`, itself yields `RedirectionNotSupported` when parsed; keep example labels out of insertion text.

**Medium · end-of-options ignored (293–312).** `tac -- --h¦` offered `--help` rather than completing a filename. Honor a prior `--` before option and option-value routing.

## Review 4 · 141–144

**Coverage and limits:** Read the scripts, their companion guides and README. Used profile-free PowerShell 7.7.0 callbacks on parsed synthetic command lines with in-memory help/catalog, archive-member, filesystem and runtime stubs. No native programs, remote resources, real process data, suggestions or stress inputs executed. Each script registers both advertised names; tail/takeown have only strict mode, definitions and native registration; tar:7–32 and tasklist:7–33 also initialize guarded script caches. No strict-loader rejection inferred from AST shape.

### 141. `tail_completer/tail_completer.ps1`

**Reviewed:** Help/fallback flags, attached vs separate value and file completion, cursor-relative prefix, quoting.

**Medium · end of options (208–228, 318–337).** `tail -- --he¦` offered `--help` instead of a filename. Track a consumed `--` and route the remainder as operands.

**Medium · required numeric value leaks into paths (238–253, 284–291, 318–337).** `tail -n 1¦` offered fixture filename `1sample`, although `1` is already a count. Distinguish a handled slot with no matches from an operand slot.

**Medium · unbounded cold Tab (13–25; static).** The `--help` call reads synchronously to completion with no deadline or output cap. Piping null only closes stdin. Bound discovery and use the static fallback on failure; not timed live.

### 142. `takeown_completer/takeown_completer.ps1`

**Reviewed:** Slash-switch and optional password state, terminal help, local/remote `/F`, quoting, cursor state.

**High · unintended nonlocal lookup (428–452).** `takeown /F //host.invalid/share/1¦` passed `//host.invalid/share/` to stubbed `Get-ChildItem` and offered `//host.invalid/share/1sample`; Windows `Path.GetFullPath` normalizes that spelling to UNC. The backslash-only guard promises placeholders but would enumerate a remote parent on Tab. Classify nonlocal paths before filesystem calls. No real share contacted.

**Medium · completed inline switch loses remote context (280–319, 569–578, 592–597).** `takeown /Sfixture /F 1¦` enumerated `.` and offered `1sample` instead of documented share-relative placeholders. The inline `/S` form is recognized only while current. Normalize completed inline switches with the same grammar.

**Medium · space inside an open quote (113–149, 543–555).** `takeown /F "1sample ¦` offered `/S`, `/U`, etc. instead of continuing the quoted filename; the trailing-space test ignores quote state. Use AST extents for the active token.

### 143. `tar_completer/tar_completer.ps1`

**Reviewed:** Flavor discovery and static/GNU catalog, mode/bundle/option/operand dispatch, `-f`/`-C`, archive listing and cache, quoted paths and members. All probes used a bsdtar-flavor fixture, not a real archive/tool.

**High · option-shaped archive members (1597–1603, 1617–1633).** With member `--help`, `tar -t -f demo.tar ¦` offered bare `--help` labeled as an archive member; accepting and later running the line would pass an option, not select that member. Quoting alone does not stop native option parsing. Suppress option-shaped members until a consumed `--`, or insert a valid end-of-options boundary. Also use ordinal member deduplication: with `alpha` and `Alpha`, prefix `al` returned only `alpha` (1617–1625).

**Medium · wrong value precedence (1191–1291, 1713–1724, 1738–1743).** `tar -c -- --format=p¦` suggested `--format=pax`/`paxr` although past `--`; `tar -c --format f¦` returned `f1sample` because `f` was interpreted as a historic bundle, despite the pending format slot. Check consumed terminator and pending value before current-token option parsing, and restrict old-style bundles to their initial position.

**Medium · cursor/working-directory state (1147–1155, 1366–1369, 1683–1692).** `tar -c -f "1sample ¦` returned `-b`, `--block-size`, etc. instead of archive paths because quoted whitespace ended the word. Use the active AST extent. Independently, `tar -c -C src 1¦` asked the stub to enumerate `.` rather than `src`; retain and apply prior `-C` directories when looking up source operands, without changing the shell location.

**Medium · advertised archive bound is post hoc (1559–1574; static).** Entire stdout and stderr are buffered, and all stdout is split before selecting 5,000 members. The time limit does not enforce an output/memory limit. Read incrementally with byte and entry limits, stop the child once reached. No large archive or stress test used.

### 144. `tasklist_completer/tasklist_completer.ps1`

**Reviewed:** Help/static switch and filter catalog, trailing/cursor state, `/FO`/`/FI`, runtime snapshot/identity/service/module/title caches, filter serialization.

**High · dynamic filter values become PowerShell syntax (445–451, 592–603, 728–736, 855–865).** A fixture window title `Quarterly $draft` produced `"WINDOWTITLE eq Quarterly $draft"`. Parser-only inspection found a `VariableExpressionAst`, not a literal title; real titles can also contain quotes and other metacharacters. This changes argument meaning on subsequent execution, not on Tab. Serialize the entire completed expression as one PowerShell literal (including quote escaping); preserve progressive completion. No expression or suggestion executed.

**Medium · wrong host for filter inventory (364, 627–744, 952–965).** `tasklist /S fixture.invalid /FI "PID eq 7¦` invoked the stub with only `/FO CSV /NH` and suggested fixture-local PID `77`. After `/S`, local runtime values are not evidence about the selected host. Disable local inventory for remote slots and offer neutral hints; do not introduce a remote query.

## Review 5 · 145–148

**Coverage and limits:** Read four scripts, companions and README rows. Inspected initialization before probing: literal native registration, local helper definitions, StrictMode; Testlimit also has the allowed guarded literal catalog (10–74). No target invocation during import; no import-shape defect confirmed. All four dot-sourced successfully in isolated `pwsh -NoProfile -NonInteractive` 7.7.0. Registered `.exe` probes used `TabExpansion2` with `Get-Command`, `Test-Path`, `Get-ChildItem` stubbed *before* sourcing; a second run resolved help only to an inert function returning one fixture line. No target binaries, accepted suggestions, stress actions, network or administrative discovery ran. Results apply to completion, not native CLI behavior. `¦` marks the cursor; no text below was submitted as a native command.

### 145. `testlimit_completer/testlimit_completer.ps1`

**Reviewed:** Static mode/modifier, optional numerics, terminal count/help, cursor/quote handling; literal registration 364–368.

- **Medium — quoted switches lose their meaning (149–150, 314–322).** `testlimit.exe '-c' ¦` returned primary switches including `-a` and `-c`, rather than count candidates only. The quotes delimit the argument; they are not part of its native value; raw regex text bypasses last-option enforcement. Read constant argument values from AST elements before the cursor; do not evaluate expressions. **Registered fixture.**
- **Medium — cursor suffix filters alternatives (325–329, 349–350).** `testlimit.exe -¦accepteula` returned only `-accepteula`; the same `-` prefix at end returned the full legal dash set. Slice the active element through the cursor instead of using the engine's full `wordToComplete`. **Registered fixture.**
- **Low — repeats help unconditionally (342–346).** After `testlimit.exe /? -x¦`, returned `-?` despite neither matching the prefix nor being a valid continuation under companion line 76. Treat consumed help as terminal; avoid inserting a duplicate flag. **Registered fixture.**

### 146. `test_completer/test_completer.ps1`

**Reviewed:** Static case-sensitive operator table and typed operands, absolute cursor extents, literal path filtering and rendered quotes, native registration 308–312. README.md:242 calls this help-driven; companion:7 and script:12–60 correctly identify it as static (**Low/doc-only**: correct index).

- **Medium — tests the spelling of the previous word rather than its role/value (155–156, 263–282, 305).** `test.exe '-t' ¦` gave engine filesystem fallback instead of 0/1/2, while unquoted `-t` offered them. Conversely `test.exe -n -t ¦` offered descriptors though `-t` was the string already consumed by `-n`. `test.exe -e -¦` offered `-b`, `-c`, etc., not the fixture file `-flag` in the FILE slot. Track expression/operand position, decode constant quoted operators, and route file slots directly to path completion. **Registered fixture.**

### 147. `touch_completer/touch_completer.ps1`

**Reviewed:** Lazy help + fallback, date/time/stamp/reference, current-token and path quoting, literal registration 335–339.

- **Medium — value routing looks after the cursor and leaks into files (229–237, 283–287, 313–332).** `touch.exe --date to¦ file` offered fixture files `todayfile`, `tomato`; same prefix at end offered `today`, `tomorrow`. `touch.exe --time 'mod¦` offered `'modify-file'` rather than `'modify'`; `--date tomat¦` offered `tomato` when no sample matched. Establish value ownership from preceding extents, decode/requote typed enum prefixes and distinguish a recognized slot with zero matches from a positional file. **Registered fixture.**
- **Medium — `--` does not terminate option parsing (225–237, 313–332).** `touch.exe -- -¦` offered `-a`, `-t`, etc., instead of fixture filename `-flag` as a path. Track a consumed delimiter and bypass option/value dispatch thereafter. **Registered fixture.**
- **Medium — diagnostics replace fallback catalog (13–21, 32–54).** Help fixture emitted only `error: cannot interpret --fixture-only`; `touch.exe --¦` offered only `--fixture-only`, hiding the entire fallback. The unscoped resolution and synchronous help call also lack a wall-clock timeout (static, no hang induced). Resolve applications only; bound capture/time and accept credible option-definition rows rather than any dashed token in merged output. **Registered fixture for catalog; static for latency.**

### 148. `truncate_completer/truncate_completer.ps1`

**Reviewed:** Lazy catalog/cache, size modifiers, quoted size/path rendering, cursor-bounded previous tokens, reference routing and literal registration 341–345.

- **Medium — size slot falls through on a sample miss (271–285, 319–338).** `truncate.exe -s 1f¦` offered the fixture filename `1file` rather than remaining in SIZE context. Represent ownership independently of result count; offer an editable size hint or preserve input, not a path. **Registered fixture.**
- **Medium — post-delimiter filenames misrouted (237–246, 311–338).** `truncate.exe -- -¦` returned `-c`, `--no-create`, etc., not fixture file `-flag`. Track the option terminator, then route to path completion. **Registered fixture.**
- **Medium — diagnostic output displaces fallback (13–21, 32–54).** With the same inert help-error text as touch, `truncate.exe --¦` offered only `--fixture-only`. Validate help definition rows, constrain command resolution to applications and bound time/output; no real process timing/exit behavior tested. **Registered fixture/static.**

**Shared low-severity insertion issue (static + selected observed outputs):** symbolic hints are passed as bare `CompletionText`: Testlimit 285–293 (`-c x¦` → `<count>`), test 234–248 (`-n ¦` → `<string>`), touch 259–261, 283–287 (`<stamp>`), truncate 218, 277–285 (`<size>`). These are documentation notation, not usable values; a separate argument starting with `<` is also PowerShell syntax, not a literal. Keep the notation in ListItemText/ToolTip and use a safe editable or valid completion, preserving typed numeric input; no placeholder was executed.

## Review 6 · 149–152

**Coverage and limits:** Read the four scripts, companion docs, README and registration and test contract. Parsed native command lines and captured registrations in profile-free pwsh 7.7.0. Fixture help, command lookup, process/session and path-provider functions supplied inert data; registry branch inspected only. No native tool, process/session inventory, real share, destructive command or suggestion executed. The three coreutils scripts have strict-mode/functions/literal native registration only (tr:4,325–329; tsort:4,235–239; tty:4,151–155); Tskill additionally has a guarded in-memory catalog (7–20), with no target discovery on import; no loader rejection observed or inferred solely from that guard.

### 149. `tr_completer/tr_completer.ps1`

**Reviewed:** Help/fallback, SET1/SET2 arity and vocabulary, quoted prefixes, path fallback, registration under both names.

**High · nonlocal I/O on Tab (149–171, 311–322; stubbed).** `tr //fixture.invalid/share/Fi¦` passed `//fixture.invalid/share/` to the recording `Test-Path` and enumeration branch. `tr` takes character sets, not files. A UNC-looking set can therefore initiate network I/O on Tab. Keep vocabulary completion local and do not resolve nonlocal paths in the optional file fallback. No share was contacted; when suppressing unsafe paths also account for engine fallback.

**Medium · wrong option state (246–272, 296–309; stubbed).** `tr -- -d¦` and `tr a -d¦` returned option `-d` although documented option parsing has stopped. State computes only whether a SET slot exists, then unconditional dash dispatch ignores option termination. Carry an options-allowed flag from completed AST elements to dispatch. Also emit repetition notation only in SET2: `tr [x*¦` offered `[x*]` in SET1 despite its own SET2-only tooltip (229–230, 311–315).

**Medium · escaped bare paths (90–99, 148–163; stubbed; also tsort:89–98,149–165).** For the synthetic file `Fixture Worker`, ``Fixture` W`` returned zero results in both scripts while the open quoted prefix `"Fixture W` returned `"Fixture Worker"` with the same stub: the unquoted decoder leaves the backtick in the search key. Decode the literal token prefix without evaluating it. Quoted path inputs follow a separate tokenizer branch.

### 150. `tskill_completer/tskill_completer.ps1`

**Reviewed:** Guarded catalog, availability, process/ID/host caches, switch/inline routing, first target, registration (320–324). Direct dot-source worked with a recording registration function.

**High · local IDs offered for a remote destructive target (96–123, 139–154, 285–291, 305–315; stubbed).** `tskill /SERVER:FixtureHost Fi¦` offered local `Fixture Worker`; `tskill /SERVER:FixtureHost /ID:¦` returned `/ID:7` from the *local* session fixture. Numeric process/session IDs are host-specific and may identify an unrelated task on the selected server if a suggestion is accepted and later run. Inspect the selected server and suppress local dynamic process/session candidates for nonlocal hosts; do not query remote hosts on Tab.

**High · process names inserted as syntax (96–112, 181–185; stubbed).** `tskill Fi¦` offered `Fixture Worker` bare, not one quoted target argument. Names containing shell metacharacters also leave data in command syntax. Serialize discovered names as one literal argument; match on decoded text and keep raw names for display only. No suggestion was executed.

**Medium · invocation operator and cursor state (261–283, 305–315; fixtures).** `& tskill Fi¦` returned zero instead of fixture process `Fixture Worker`: regex splitting skips `&`, then treats `tskill` as an existing process target. For `tskill /I¦junk`, callback prefers the full `/Ijunk` over `/I` and misses `/ID:`; a separate inert native TabExpansion2 recorder confirmed the engine passes the full word. Use CommandElements excluding the actual command, and take only the active extent through the cursor.

### 151. `tsort_completer/tsort_completer.ps1`

**Reviewed:** Help and fallback, typed path prefix/quote handling, option versus input routing, import shape.

**Medium · explicitly typed nonlocal path (149–172, 232; stubbed).** `tsort //fixture.invalid/share/Fi¦` passed the normalized UNC parent to `Test-Path` and the enumeration branch. Do not contact a network share merely to edit an argument; guard nonlocal parents before provider operations and consider engine fallback. No live path probe.

**Medium · end-of-options ignored (216–232; stubbed).** `tsort -- --h¦` returned `--help`: a filename position is sent to the option catalog. Track `--` and pass the prefix to literal path completion instead. Also see escaped bare paths under 149.

### 152. `tty_completer/tty_completer.ps1`

**Reviewed:** No-operand behavior, empty/current slot, option catalog and fallback, import shape. No file enumeration inside the script.

**Medium · options after terminator (130–148; stubbed).** `tty -- ¦` offered the entire static catalog; no options or operands are valid after the terminator. Track completed `--` before dispatch and distinguish an intentional no-match from delegating to PowerShell's path fallback. The root README:249 also describes filesystem operand completion, contrary to the no-operand guide and script.

**Low · cold fallback omits documented alias (12, 59–60; static + stubbed callback).** With no tool available `tty --q¦` returned no candidate, although tty_completer.md lists `--quiet`. Add it to the fallback catalog.

**Shared Medium · options parsed out of help prose (tr/tsort/tty:21, 32–53; stubbed).** Fixture help declaring `--help` and containing ordinary prose about another tool's `--other-tool-option` made all three catalogs include the latter as supported. Parse option declaration columns and explicitly marked alias fields (important for tr's `-C`) instead of every line-wide option-shaped word. No live CLI version was tested.

## Review 7 · 153–156

**Coverage and limits:** Read the four scripts, companion docs, relevant README import instructions and manifest entries (1387, 1396, 1405, 1414). Parser found zero errors; each script has only `Set-StrictMode` (line 4), function definitions and one native registration for both base and `.exe` names (153:186; 154:324; 155:328; 156:249). No import-shape defect or import-time external call confirmed. Direct dot-sourcing does apply StrictMode to that scope. In disposable PowerShell 7.7.0 `-NoProfile -NonInteractive` processes, dot-sourced registrations and called `CommandCompletion.CompleteInput` on strings; `Get-Command` absent or returning inert help fixture, provider enumeration mocked with synthetic item objects. Shell's own filename fallback may see the repo. No native tool, native help or completed line ran; no mutations, real build catalog or end-to-end importer validation. `¦` marks cursor only.

**Shared, Medium — committed `--` ignored (all four):** `uname`:159–182; `unexpand`:299–321; `uniq`:304–325; `unlink`:226–246. Runtime: `CMD -- --h` still returns `--help` for every command (`uname` also gives `--hardware-platform`). Expected no options: operands for the file tools, no candidates for `uname`. Track committed option terminator using elements strictly left of cursor; in operand mode allow dash-prefixed filenames.

**Shared, Low — prose promoted to flags (all four):** uname/uniq/unlink:32–55, unexpand:50–72. Inert help containing an option row plus ` Note: --old is no longer accepted.` made each register `--old` as a selectable option. Match only declaration columns of supported help layouts, not option-like words anywhere in text. Mocked boundary; does not assert particular installed builds have this wording.

**Shared, Low — escaped bare path prefixes (154–156):** unexpand:106–118, uniq:88–100, unlink:87–100 return unquoted text unchanged. In all three `CMD a` followed by a backtick, space and `b` produced no match for synthetic `a b.txt`; quoted prefix worked (e.g. `unlink 'a b` → `'a b.txt'`). Decode literal escapes in bare path words via tokenizer/AST without evaluating expressions; preserve output quoting. Shell filename fallback can mask this for real paths.

### 153. `uname_completer/uname_completer.ps1`

**Reviewed:** lazy help/static fallback, case-sensitive flag matching, short-flag clusters, offset/token routing, unsupported operands, native registration. Positive control: `uname -sn` correctly gave `-sna`, `-snr`, etc.

**Medium — unsupported operands trigger filename fallback**, 165–182; companion `.md`:7 says no paths. Runtime `uname readme` → `.\README.md`; current function emits an empty pipeline rather than a handled-no-result. Return an explicit native no-match sentinel for invalid operands; control registration emitting `$null` suppressed engine fallback.

**Low — quoted option prefix not recognized**, 98–106,168–182: `uname "--ke` returned no options, expected e.g. `--kernel-name` as quoted native argument. Use AST prefix and decode quote/escape syntax.

### 154. `unexpand_completer/unexpand_completer.ps1`

**Reviewed:** binary lookup/cache identity, fallback, tab lists, attached/separate value routing, path rendering and fallback.

**Medium — value routing reads past cursor and falls through to paths**, 235–244,269–274,299–321. `unexpand --tabs 4¦ input` returned synthetic `4-file`, not the documented value `4`. Bound predecessor to cursor, separate 'recognized value context' from 'matches' and suppress file fallback for unmatched tab lists.

**Medium — invalid literal placeholder**, 247–255,269–274: `unexpand -t ` offers `4,8,<list>`; parsing the insertion `unexpand -t <list>` produced `RedirectionNotSupported`. Offer e.g. `4,8` or put syntax hints in tooltip only.

**Low — negative cache never recovers after same-PATH install**, 9–16,25–34 vs companion `.md`:55: missing tool caused two candidate lookups; making stub available without changing PATH still left lookup count at two and fallback unchanged. Re-resolve a missing source on subsequent/bounded refresh; test unchanged PATH.

### 155. `uniq_completer/uniq_completer.ps1`

**Reviewed:** attached-only optional group method (`uniq --group=b` → `--group=both`), required numeric options, operand routing/quoting, help cache/fallback.

**Medium — numeric slots emit invalid PowerShell and then filenames**, 211–221,244–261,276–281,304–325: `uniq --skip-fields ` inserts `<number>` (parse-only `uniq -f <number>` → `RedirectionNotSupported`); `uniq -f 123` and `uniq -f 1¦23 input` return synthetic `123.txt`. Recognize numeric slot by cursor-bounded predecessor; emit legal numeric examples or handled-no-result; keep syntax hints in tooltip rather than insertable text.

**Low — extra positional operand completed**, 304–325: `uniq one two read` returns synthetic `readme-other` after INPUT and OUTPUT are filled. Count consumed operands separately from option values, suppress filenames once arity 2 reached.

### 156. `unlink_completer/unlink_completer.ps1`

**Reviewed:** help/fallback, positional cursor/quoted literals, path matching/quoting/dash anchoring, native option and path dispatch.

**Medium — completer offers a second filename after the sole FILE operand**, 226–246: `unlink first read` returned synthetic `readme-other`, rather than no candidates. Track prior operands to the cursor and suppress filename fallback for impossible slots; this is a bad suggestion, not evidence of deletion. No unlink invocation. See shared terminator, help-prose and escaped-word findings.

## Review 8 · 157–160

**Coverage and limits:** Read scripts and companion docs at the pinned SHA. PowerShell 7.7.0 -NoProfile child process, intercepted Register-ArgumentCompleter, invoked registered script blocks on parsed fixture command lines; mocked help, file listings and catalogs. `¦` marks cursor. No target programs, child commands, suggested text, network, or real tool/project discovery executed. Parser checks do not execute completion text. All registered names captured. Native whole-word cursor cases model callback inputs rather than PSReadLine acceptance.

### 157. `uptime_completer/uptime_completer.ps1`

**Reviewed:** Strict mode, helper definitions, literal two-name registration (4,225–229); help lookup/fallback/cache (6–60); word slicing, quoting, filenames (88–186); blank slot delegates to shell. No discovered native call on import.

- **Medium · terminator ignored (206–222; fixture).** `uptime -- --h¦` returns `--help`; this is now an operand, not an option. Scan completed arguments for `--` before option dispatch and complete literal filenames, anchoring dash-leading names.
- **Medium · cold help (13–22,52–60; static):** first option lookup invokes help synchronously with no timeout/output cap, so fallback cannot help until capture returns. Resolve Application and bound child capture; no delayed executable was run.

### 158. `uv_completer/uv_completer.ps1`

**Reviewed:** Guarded literal cache initialization and one literal registration (1–25,1278–1282); root/uvx tree, help parser, subprocess 5 s kill, file and project lookups, enums, free/path/fallback routing. No native call observed during import. No real uv/uvx, Python/tool inventory or pyproject exercised.

- **Medium · child arguments routed to uv (984–993,1255–56,1275; fixture).** `uv run child --off¦` returns uv `--offline` after the child executable. Mark the pass-through boundary for run/tool run/uvx and stop routing child argv through the parent option parser.
- **Medium · cursor prefix ignored (1124–45,1245–56; callback fixture).** With `uv --off¦bad` and native word `--offbad`, no `--offline` is returned; text right of cursor should not veto it. Cut the AST extent at the cursor and use that prefix throughout.
- **Medium · alias loses enum and produces non-insertable metavar (331–346,1043–66,1239–45; fixture/parser).** Help fixture `-m, --mode <MODE>  [possible values: one, two]`: `uv --mode ¦` returns `one,two`; `uv -m ¦` returns `<mode>`. Independently `--label <LABEL>` generates `<label>` for an open value slot; bare leading `<` causes parser error. Share enums across aliases while preserving case-sensitive option identity, leave instructions in tooltip, avoid inserting example grammar as argv.

### 159. `vdir_completer/vdir_completer.ps1`

**Reviewed:** Strict/literal two-name registration (4,399–403), help/fallback cache, attached and detached enums, optional attached-only flags, path quoting/separators, blank fallback. Help capture (13–22) has same static no-deadline caveat as uptime.

- **Medium · wrong predecessor mid-line (225–241,347–351; fixture).** `vdir --sort si¦ze tail` yields no `size`, while `vdir --sort si¦` yields `size`. Looks at the last elements of the full AST, not the predecessor at cursor. Restrict state to the left of the active extent, and decode quoted enum prefixes before matching.
- **Medium · terminator ignored (375–397; fixture).** `vdir -- --h¦` returns `--help` instead of treating it as a filename prefix. Honor `--` before both value and option dispatch.
- **Medium · invalid insertion (273–281,321–331,349–350; callback/parser).** `vdir --width ¦` inserts `<cols>` and `vdir --width <cols>` gives `RedirectionNotSupported`. Same emission for `<pattern>`. Keep placeholders display-only; offer valid examples or decline.

### 160. `wc_completer/wc_completer.ps1`

**Reviewed:** Strict/literal native registration, GNU/clap help parser, terminal/positional fallback, files0-from, stdin sentinel, cursor/quote handling. No discovery at import. Attached spaced filename fixture `--files0-from='name with space.txt'` parses as one argument (no defect there).

- **Medium · option branches override operand state (558–560,594,648–667; fixture).** `wc -- --h¦` gives `--help`; `wc -- --total=a¦` gives `--total=auto, --total=always`. Both are operand prefixes after `--`. Honor computed EndOfOptions before assignment/option dispatch; prioritize pending values before new assignments.
- **Medium · cursor prefix discarded (644,663–664; fixture).** `wc --he¦bad` yields no `--help` when supplied whole native word `--hebad`. Use the already-sliced `$currentToken`.
- **Medium · quoting lost in enum miss fallback (422–436,456–465,505–508; callback/parser).** `wc --total 'two words'` returns unquoted `two words`, splitting one typed argument into two. Match enums against decoded text, but never return decoded user text as bare PowerShell source: keep raw quoted spelling or decline invalid enum candidates.
- **Medium · cold help (60–77,326,367; static):** synchronous help has no deadline or explicit stdin closure; an empty/unparseable response marks catalog initialized, permanently removing option suggestions until cache reset. Bound capture and support retry or a conservative fallback. No hung/failing native binary run.
