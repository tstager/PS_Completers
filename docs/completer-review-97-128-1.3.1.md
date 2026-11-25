# Native completer review: scripts 97–128 (1.3.1)

**Scope:** 32 tracked standalone scripts at `04cdd463f999cba23324f6ca18907854fd2f6dc5`. All eight four-script reviewer reports are represented below. The ordinals are **one-based positions**, not a filename range: enumerate the commit tree, keep `<name>_completer/<name>_completer.ps1`, sort the full paths with `StringComparer.OrdinalIgnoreCase`, and take positions 97 through 128 of 176. All 32 working-tree scripts matched their commit blob IDs under Git’s content filters. PowerShell 7.7.0 parsed all 32 with zero syntax errors; each AST contained a native completer registration site. This does not establish that lazy import or completion works.

**Priorities:** Address actions performed on Tab first: PsShutdown and Robocopy can reach nonlocal path providers, and rustup can pass a toolchain outside the installed set to discovery. Separately, RegDelNull, SC and rustfmt can insert dynamic names as PowerShell syntax rather than literal data. The latter risks require the user to accept and then execute the resulting command. RTK has a separate load-time contract issue that a syntax check does not detect.

**How to read the evidence:** Line ranges refer to the script in the heading unless another file is named. `¦` marks the cursor, not a character to type. Examples describe completion input, not commands to run. **High** means a target-integrity, unintended external-action or whole-script availability risk; **Medium** means a wrong or missing result in an applicable completion state, or a potential interactive hang; **Low** means limited coverage, metadata or cold-path inefficiency. Severity is distinct from confidence: static consequences are labeled, and no destructive command, native target, network endpoint or live administrative inventory was exercised. The review is not an exhaustive CLI-version, interactive menu, performance or end-to-end test.

## Review 1 · 97–100

**Coverage and limits:** Sysinternals: source and companion guides; stubbed help, parse-only fixtures and non-discovery callbacks. No live service, process, driver, registry or remote enumeration.

### 97. `psping_completer/psping_completer.ps1`

**Reviewed:** ICMP/TCP modes, client/server switches, help topics.

**Medium · cursor state (738–759).** With help stubbed, `psping -i¦ 1 -b` produced no `-i` match. State consumes the whole AST and removes only a matching *last* token; later switches affect mode and the current switch looks used. Build state from extents before the replacement span.

**Low · latency (126–148, 216–222).** The root-help probe can wait five seconds, yet its validation flag does not govern the candidates. Remove it from the Tab path.

### 98. `psservice_completer/psservice_completer.ps1`

**Reviewed:** Remote target/credentials, verbs, filters, service and driver names.

**Medium · wrong host (589–615, 684, 802, 821; static).** After a remote server and `query`, verb dispatch still suggests local service/driver names. Use remote placeholders rather than querying either host.

**Medium · literal insertion (375–387).** A helper fixture returned `Example$Tier` bare; PowerShell expands `$Tier` rather than passing the service name. Serialize names as literal arguments, not just strings containing spaces.

### 99. `psshutdown_completer/psshutdown_completer.ps1`

**Reviewed:** Actions, target lists, value slots, reason codes.

**High · unintended network I/O (286–297; static).** The `@file` completer passes its typed parent directly to `Test-Path` and `Get-ChildItem`. A UNC parent can contact a share on Tab despite the local-only contract. Reject nonlocal/provider paths before either call; test with a stub, not a live share.

**Medium · target syntax (328, 369).** Placeholder insertion is bare `@file`, which the parser marks as splatting. Use the same literal quoting as real file results.

### 100. `pssuspend_completer/pssuspend_completer.ps1`

**Reviewed:** Static switches, local process cache, remote placeholders.

**Medium · target replacement (307–311).** For the synthetic target `\\example.invalid`, the callback inserted `\\computer` instead. Offer a generic host only for an empty/matching prefix; otherwise preserve the supplied host. No processes or remote hosts were queried.

## Review 2 · 101–104

**Coverage and limits:** ptx and interpreters: source and guides; parsed synthetic command lines, callback/helper checks and a seeded launcher catalog. The Python invocation case returned local repo paths. No interpreters, native help or runtime inventory executed.

### 101. `ptx_completer/ptx_completer.ps1`

**Reviewed:** Help/fallback flags, option values, file operands.

**Medium · cursor state (130–143, 203–211, 310–314).** For `ptx --width 8¦0 tail`, the helper extracted `8` but reported no value slot or values: it consulted the last AST elements instead of the cursor’s predecessor. Select the option by extent.

**Low · fallback coverage (12–21, 59).** Without help, documented `--gap-size` and `-W` are missing.

### 102. `pwsh_completer/pwsh_completer.ps1`

**Reviewed:** Host flags and aliases, enum/path values, script and command tails.

**Medium · script arguments (502–528).** `pwsh demo.ps1 -OutputFormat X¦` yielded host enum `XML`, although the script owns these arguments. Attached/pending host values are handled before the tail check. Establish the script boundary before dispatching host values.

### 103. `python_completer/python_completer.ps1`

**Reviewed:** Interpreter flags, warning/hash/-X values, module lookup and script tails.

**Medium · interpreter boundary (288–301, 868–882).** `python -mhttp.server --he¦` returned four interpreter help flags after control had passed to the module. Recognize attached `-m`/`-c` operands.

**Medium · invocation syntax (146–175, 226–233).** `& python --check-hash-based-pycs n¦` returned filesystem names instead of `never`: the tokenizer drops `&` and treats `python` as the script. Use command-element extents to skip the actual command.

### 104. `py_completer/py_completer.ps1`

**Reviewed:** Manager/legacy modes, selectors, command values, tails.

**Medium · invented runtime (700–723).** With only `One\3.12` and `Two\3.14` in a fixture, `py -V:One\3¦` offered nonexistent `One\3.14`. Match existing publisher/tag pairs, not every tag.

**Medium · repeated selector (958–974).** The same fixture offered selectors after `py -3 -V:One\3¦`; check whether a runtime was already selected first.

## Review 3 · 105–108

**Coverage and limits:** Qwen, path utilities and RegDelNull: source, repo-relative paths, in-memory option data and parser-only key-name fixture. No symlink operations, native help or registry reads.

### 105. `qwen_completer/qwen_completer.ps1`

**Reviewed:** Three-level command tree, flags, enums and path values.

**Medium · invalid placeholder (1104–1116).** On `qwen --model ¦`, the callback inserted `<value>`; the resulting text produced parser error `RedirectionNotSupported`. Keep the hint in the label, not in command text.

**Low · directories (157–160, 601–602, 782–801, 1073–1078, 1097–1101).** `qwen --add-dir ./READM¦` returned `./README.md` as a `ProviderItem`. Preserve the directory-only constraint in both attached and separate value branches. The companion guide acknowledges this directory limitation.

### 106. `readlink_completer/readlink_completer.ps1`

**Reviewed:** Help/fallback catalog, options and quoted operands.

**Medium · terminator (235–250).** With seeded options, `readlink -- --q¦` returned `--quiet` as `ParameterName`. After a committed `--`, match the dash-leading operand against paths instead.

### 107. `realpath_completer/realpath_completer.ps1`

**Reviewed:** Help/fallback options, operands, attached and separate relative paths.

**Low · result type (204–213, 248–253).** For `realpath --relative-to=./qwen_comp¦`, the callback returned the repo directory as `ProviderItem`, losing `ProviderContainer`. Preserve the inner result type.

**Low · escaped paths (89–105, 161–188).** The bare-word helper retains the backtick in a backtick-escaped space; lookup then searches for a different name. Decode the literal token without evaluation.

### 108. `RegDelNull_completer/RegDelNull_completer.ps1`

**Reviewed:** Registry hives, cached child keys, switches and terminal help.

**High · target integrity (81–97, 284–293).** A synthetic key containing a space and literal `$Example` was rendered in double quotes with the dollar unescaped. Parsing the suggested text produced a nested expression, so subsequent execution could address a different key. Serialize dynamic key names as literal PowerShell arguments; test the parser round trip. No registry data or native command was used.

## Review 4 · 109–112

**Coverage and limits:** Windows utilities and ripgrep: source and guides; isolated token/hint helpers, parser and case-comparison checks, and a recording path-enumeration stub. No clipboard, registry, remote share or native process access.

### 109. `regjump_completer/regjump_completer.ps1`

**Reviewed:** Clipboard switch, registry roots and immediate child names.

**Medium · quoted prefix (94–104, 287–293).** A space at the end of an unfinished quoted registry key is treated as a new argument, resetting suggestions to roots and `-c` instead of continuing the key. Slice the active AST extent at the cursor.

### 110. `reg_completer/reg_completer.ps1`

**Reviewed:** Twelve subcommands, local keys/values, remote roots, files and value kinds.

**Medium · nonliteral separators (49, 666–677, 1097–1104).** At `reg query HKCU /se ¦`, separator hints are emitted as raw shell text. Selecting `#` starts a comment; `;` and the pipe character are also syntax. Return a quoted literal in `CompletionText`, retaining the raw label.

### 111. `rg_completer/rg_completer.ps1`

**Reviewed:** Options, clusters, file types, pattern/file modes and option terminator.

**Medium · valid flags end completion (918, 955–956, 1010–1011).** Case-insensitive `-in` equates `-v`/`-H` with terminal `-V`/`-h`, suppressing the pattern slot. Compare short switches case-sensitively.

**Medium · terminator (1041–1049).** Inline long-option dispatch still handles `rg -- --engine=a¦` as an option; guard it with `EndOfOptions`.

### 112. `robocopy_completer/robocopy_completer.ps1`

**Reviewed:** Source/destination directories, file specs, /XF and /XD, inline paths and job names.

**High · unintended network I/O (541–546, 650–675, 945–946; stubbed).** The local-only path guard recognizes a double backslash but not the alternate `//` UNC spelling. A `/LOG:` path with a `//server/share/` parent was passed unchanged to a recording `Get-ChildItem` stub. Detect both spellings before resolution or enumeration; no share was contacted.

## Review 5 · 113–116

**Coverage and limits:** RTK and Rust utilities: AST inspection, pure token/quote helpers and seeded toolchain lists with a discovery recorder. No strict loader import, compiler, formatter, rustup invocation or timing test.

### 113. `rtk_completer/rtk_completer.ps1`

**Reviewed:** Cached help and static fallback, nested commands, enums, paths, variadics and attached options.

**High · strict import contract (3–9, 322–333, 606–626; static).** An executable cache initializer is a top-level `IfStatementAst`. This contradicts the permitted shape described in `rtk_completer.md:19` and the repository’s strict lazy-import requirement (`README.md:71–75`). A valid PowerShell parse is not a strict-import pass; registration through that loader is at risk. Initialize the cache in a getter. No loader rejection was observed or dot-source failure inferred.

### 114. `rustc_completer/rustc_completer.ps1`

**Reviewed:** Help/static flags, lint groups, codegen, targets, attached/list values and source paths.

**Medium · open quote (49–85, 907–911, 965–975).** For `rustc --out-dir "demo ¦`, token state reported an empty current word and put the unfinished path among completed arguments. Retain whitespace inside the active quoted operand.

**Low · cold latency (298–300, 370, 392, 415, 422–424; static).** Even a flag prefix can initialize help, lints, codegen, targets and CPU lists sequentially, with five-second per-probe waits. Defer each list to its value slot; latency was not measured.

### 115. `rustfmt_completer/rustfmt_completer.ps1`

**Reviewed:** Option catalog, config enums, two-stage print-config, Rust files and attached values.

**High · target integrity (124–145, 209–215).** The renderer turned the synthetic filename `draft $notes.rs` into `"draft $notes.rs"`; reparsing found a nested expression instead of a literal filename. Formatting could act on another file if the suggestion is accepted and run. Quote all metacharacters as literal argument data.

### 116. `rustup_completer/rustup_completer.ps1`

**Reviewed:** Nested commands/flags, toolchain overrides, target/component lists, enums and paths.

**High · unverified toolchain discovery (306–325, 344–347, 380–383).** With only a dated nightly installed in the fixture, `+nightly` matched its prefix and the recorder received `component list --installed --toolchain nightly`. The rolling channel is not the installed dated nightly. This defeats the installed-only guard; remote activity or auto-installation depends on rustup and was not observed. Resolve legitimate aliases to their full installed identifier; skip scoped discovery for unknowns.

## Review 6 · 117–120

**Coverage and limits:** RU, SBX, scheduled tasks and Scoop: source and guides; stubbed RU help, isolated enum checks, synthetic task help, and stubbed app/manifest/shim names. No registry, child process, real task or package discovery.

### 117. `ru_completer/ru_completer.ps1`

**Reviewed:** Help/static switches, registry keys, hive files and depth values.

**Low · help spelling (159, 599–607).** With help stubbed empty, both `ru /¦` and `ru /?¦` returned zero matches before an operand: only dash prefixes route to switches. Route slash-help prefixes to the same matcher.

### 118. `sbx_completer/sbx_completer.ps1`

**Reviewed:** Literal argument extraction, Cobra adapter/directives, local enums.

**Medium · timeout (154–163; static).** The five-second budget ends when the child exits, but reading stdout via `.Result` can still block if another process holds the pipe open. Bound the read by the same deadline.

**Low · enum quotes (270–284, 302–304).** An attached, fully quoted `--platform="linux/amd64"` produced zero matches; a partial open quote produced two. Remove a matching closing delimiter before comparing enum values.

### 119. `schtasks_completer/schtasks_completer.ps1`

**Reviewed:** Subcommand options, modifiers, local task names and paths.

**Medium · wrong host (403–419, 506–510; static).** `/Query /S example.invalid /TN` routes to local task names. Preserve user input or offer a placeholder when `/S` selects another host; do not query it on Tab.

**Low · empty cache (403–413).** A zero-result query sets the timestamp but cannot hit the cache, causing repeat discovery before expiry. Cache emptiness as a result.

**Medium · help language (36–43, 278–295).** In a canned help fixture, replacing just the English `Parameter List:` heading reduced the recognized command count from one to zero; the empty table is cached. Seed core commands or parse rows independent of heading language. Actual localized output was not tested.

### 120. `scoop_completer/scoop_completer.ps1`

**Reviewed:** Command/flag routing, local metadata sources, versions and positional slots.

**Medium · catalog merge (1125–1126).** With one installed app `demo` and two manifests `alpha`, `beta`, `scoop info demo¦` offered `demoalpha beta`; `al¦` had no result. Coerce both outputs to arrays before adding.

**Low · fixed arity (1237–1247).** `scoop help list ¦` offered all topics again: clamping to the last slot makes it repeat. Repeat only explicitly variadic slots.

**Medium · literal shim names (357, 918–931, 1169).** `scoop which dem¦` with stubbed shim `demo tool` inserted two operands on reparsing. Quote dynamic names while retaining the raw menu label.

## Review 7 · 121–124

**Coverage and limits:** SC, SDelete, sed and seq: static inspection of source and guides. Scenarios are code traces, not live reproductions; no service, disk, destructive operation or installed help was exercised.

### 121. `sc_completer/sc_completer.ps1`

**Reviewed:** Help-seeded verbs, server prefix, service/display names, tagged values and paths.

**High · nonliteral service names (556–572, 580–592; static).** A name such as `Fixture;Example` is inserted bare, splitting the command if accepted and subsequently run. Within double quotes, dollar signs and backticks also remain active. Use the existing literal renderer (614–640) for every dynamic name; test with inert parser fixtures.

### 122. `sdelete_completer/sdelete_completer.ps1`

**Reviewed:** Delete/free-space modes, pass counts, paths, physical targets and bare-letter warnings.

**Medium · quoted target (115–155, 379–384, 396–419; static).** Whitespace inside an open quoted path is treated as an argument boundary; `sdelete "Fixture ¦` can offer switches and unrelated current-directory targets. Keep the active argument extent.

**Medium · guessed disk targets (333–336; static).** The menu inserts real disk indices `0`, `1`, `2` as examples unrelated to the intended target. Avoid guessing operational values for a destructive command; use a non-inserting hint.

**Medium · ambiguous letter (269–276, 350–362, 412–420; static).** The warning for `A` inserts `A`, and an exact one-letter file match remains bare. For a verified file use `.\A`; do not offer the ambiguous spelling as the fix.

### 123. `sed_completer/sed_completer.ps1`

**Reviewed:** Help/static options, clusters, script vs. input files, value hints and terminator.

**Low · dropped aliases (510–518, 545–570; static).** If a parsed help group contains one known token, the entire group is skipped. A help line pairing `-n` with a new long alias therefore loses the alias. Merge missing tokens into the known definition.

### 124. `seq_completer/seq_completer.ps1`

**Reviewed:** Help/fallback options, separator/format/terminator hints and numeric operands.

**Medium · separator syntax (216–222, 241–251).** The suggestion for a semicolon after `-s` is bare `;`, ending the command instead of supplying its value. Emit a quoted separator literal.

## Review 8 · 125–128

**Coverage and limits:** SHA utilities: source and guides; direct callbacks with seeded option caches, plus pure cluster/quote checks. No checksum utility, native help, filesystem fixture or host fallback exercised.

### 125. `sha1sum_completer/sha1sum_completer.ps1`

**Reviewed:** Help/fallback flags, cursor slicing, quoting, local paths; check-mode filtering and short clusters.

**Medium · terminator (316–333).** With the option cache seeded, `-- --ch¦` yielded `--check` as a parameter rather than completing a filename. Honor a committed `--` before dispatching by prefix.

**Low · invalid clusters (245–246, 257–265, 278–297).** A fixture extended `-bc` to `-bcw` even though `-b` is excluded by the script’s own verify-mode rules. Validate existing flags before suggesting another.

### 126. `sha224sum_completer/sha224sum_completer.ps1`

**Reviewed:** Help/fallback flags, cursor slicing, quoting, local paths; empty word yields no custom matches.

**Medium · terminator (228–238).** With the option cache seeded, `-- --ch¦` yielded `--check` as a parameter rather than completing a filename. Honor a committed `--` before dispatching by prefix.

**Low · mode (228–235).** With seeded options, `--check --ta¦` suggested output-format flag `--tag`; filter output-only candidates in check mode.

### 127. `sha256sum_completer/sha256sum_completer.ps1`

**Reviewed:** Help/fallback flags, cursor slicing, quoting, local paths; explicit empty-word paths.

**Medium · terminator (222–232).** With the option cache seeded, `-- --ch¦` yielded `--check` as a parameter rather than completing a filename. Honor a committed `--` before dispatching by prefix.

**Low · fallback (12).** Documented `-b`/`--binary` are absent when help is unavailable.

**Low · mode (222–229).** The seeded `--check --ta¦` case offered output-format flag `--tag`.

### 128. `sha384sum_completer/sha384sum_completer.ps1`

**Reviewed:** Help/fallback flags, cursor slicing, quoting, local paths; empty word yields no custom matches.

**Medium · terminator (242–252).** With the option cache seeded, `-- --ch¦` yielded `--check` as a parameter rather than completing a filename. Honor a committed `--` before dispatching by prefix.

**Low · smart quotes (87–103, 157–162).** Parsing the synthetic prefix `‘README` left the opening quote in the filename and produced no quote marker. Decode PowerShell quote delimiters before lookup.

**Low · mode (242–249).** The seeded `--check --ta¦` case offered output-format flag `--tag`.
