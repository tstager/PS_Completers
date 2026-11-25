# Completer review: first 32 at v1.3.1

**Baseline:** `master` and tag `v1.3.1` at `04cdd463f999cba23324f6ca18907854fd2f6dc5`. The working tree was clean before review. Eight groups reviewed four scripts each, including the same-stem documentation. **Result: 20 medium and 20 low findings** (IDs group related observations); no high-severity finding established. All 32 passed parsing, strict import-grammar validation and isolated cold load, but each had at least one behavioral or documentation finding. None is classified wholly clean.

**Fix first:** The same end-of-options failure appears in 15 scripts (M2); fix the dispatch order and test dash-leading operands. Next, test editing in the middle of an existing command (M1, M4, M15) and accepting completions where PowerShell replaces only part of a word (M14, M16). M8 is a separate local-only discovery issue: prevent remote filesystem access *before* probing, rather than trying to recover after a slow call.

## Selection and evidence

Run from the repository root. This selects tracked standalone scripts, not working-tree discoveries, package copies, helpers, or documentation; it sorts the **full Git paths** before slicing. There were 176 eligible paths, with no case-insensitive ties in the selected range. The last included stem is `dircolors`; the next is `dirname`. In particular, `codex_completer/` precedes `code_insiders_completer/` under this comparer.

```powershell
$sha = '04cdd463f999cba23324f6ca18907854fd2f6dc5'
[string[]]$paths = @(git ls-tree -r --name-only $sha |
    Where-Object { $_ -cmatch '^([^/]+_completer)/\1\.ps1$' })
[Array]::Sort($paths, [StringComparer]::OrdinalIgnoreCase)
$paths[0..31]
```

- **R — runtime:** registered completions via `TabExpansion2` on inert input strings in isolated **pwsh 7.7.0 on Windows** sessions. A `|` in a medium-finding example marks the cursor, not a pipe; otherwise the cursor is at the end unless stated. For example, the mid-line date probe is `(TabExpansion2 'date.exe --date to --utc' 18).CompletionMatches`. Names and path counts depend on the local directory; the relevant result is the *kind, text or replacement span* of the candidate. A filesystem result may be the engine's fallback, not output from the callback.
- **S — source:** traced code or compared the shipped documentation; explicitly marked when backed by a helper spy or an isolated regex check, rather than a registered end-to-end observation. A call that *can* block is not a measured hang. Fixtures, fallback catalogs and capture stubs exercise PowerShell routing, not the behavior of installed target versions.
- **Clean checks across the sample:** in profile-free pwsh, `Parser.ParseFile` returned **0 parse errors** and CompleterActions **3.0.1** `Test-CompleterScript -LiteralPath` returned **0 findings**. Each script was dot-sourced in its own fresh runspace: **0** entries in both the cold-load error list and the error stream for all 32. These checks do not exercise the callback.
- No live tool inventory, remote share, package operation, archive operation or build was needed. The full Pester/package gate was not run: it stages files and creates fixtures. Its path-quoting test checks the candidates actually returned, including engine fallback; it does not establish that the right candidates are present for these slots. No upstream-version parity, network timing, or exploitability is inferred here.
- **Severity:** medium means wrong argument/slot or an interactive discovery boundary that warrants a fix; low means narrower fallback, spelling, metadata or documentation defects. File labels link to the reviewed script at the first cited line; subsequent line ranges use the same file.

## Medium findings

### M1. Editing the middle of a line loses the preceding option (R: cached/fallback)
At the marked cursor, `date.exe --date to| --utc` offers repository directories instead of `today`/`tomorrow`; `df.exe --type nt| --total` gives no `ntfs`. Likewise `csplit --suffix-format %0| FILE` loses `%02d` and `%03d`, and `cut --bytes | README.md` offers filenames instead of `<list>`. Also `base32 -w | file.txt` returns checkout entries rather than `0`, `64`, `76` (the corresponding base64 control works). All four date/df/csplit/cut end-of-line controls work. Resolve the predecessor from command elements before the cursor, not from the end of the entire AST. **Lines:** [date:281–287](../date_completer/date_completer.ps1#L281); [df:211–217](../df_completer/df_completer.ps1#L211); [csplit:202–209](../csplit_completer/csplit_completer.ps1#L202); [cut:224–231](../cut_completer/cut_completer.ps1#L224); [base32:199–207,265–272](../base32_completer/base32_completer.ps1#L199).

### M2. A committed `--` does not end option dispatch (R: cached/fallback; curl help stubbed)
`csplit -- -f |` offers `<prefix>` instead of patterns after the FILE operand; `cut -- -f |` offers `<list>` rather than another file. `curl -- --p|` suggests `--proxy` and `--proto` for a positional URL. `comm -- --h|`, `date.exe -- --he|`, `df.exe -- --he|` and `dircolors.exe -- --he|` all suggest `--help` as an option. The same defect appears in option-name routing in `apm install -- --ta|` (`--target`), `base32 -- -|` and `base64 -- -|` (decode/wrap flags), and `basename -- --he|` and `cksum -- --he|` (`--help`). Attached values also escape the guard: `bun build -- --target=b|` offers `--target=browser`, `codex -- --sandbox=read|` offers `--sandbox=read-only`, and `code-insiders -- --sync=o|` offers `--sync=on` and `--sync=off` instead of leaving forwarded/positional text alone. Track a consumed terminator before the cursor, distinguishing it from a pending option's value; route subsequent words, including dash-prefixed ones, as operands. **Lines:** [csplit:202–209,284–294,345–360](../csplit_completer/csplit_completer.ps1#L202); [cut:224–231,312–325](../cut_completer/cut_completer.ps1#L224); [curl:924–944,990–997,1018–1026](../curl_completer/curl_completer.ps1#L924); [comm:264–283](../comm_completer/comm_completer.ps1#L264); [date:489](../date_completer/date_completer.ps1#L489); [df:372](../df_completer/df_completer.ps1#L372); [dircolors:264](../dircolors_completer/dircolors_completer.ps1#L264); [apm:1547,1879–1890,1922–1931,1948–1952](../apm_completer/apm_completer.ps1#L1547); [base32:265–283](../base32_completer/base32_completer.ps1#L265); [base64:303–331](../base64_completer/base64_completer.ps1#L303); [basename:270–289](../basename_completer/basename_completer.ps1#L270); [cksum:369–380,393–394](../cksum_completer/cksum_completer.ps1#L369); [bun:1422–1425,2067–2092](../bun_completer/bun_completer.ps1#L1422); [codex:482–498](../codex_completer/codex_completer.ps1#L482); [code_insiders:1056–1075](../code_insiders_completer/code_insiders_completer.ps1#L1056).

### M3. dd suggests operand forms it cannot use (R: missing-tool fallback)
`dd.exe --|` offers `--if=`, `--of=` and `--bs=`; the actual operands are bare `if=`, `of=` and `bs=`. `dd.exe status pr|` inserts `progress`, leaving two arguments instead of `status=progress`. Remove the dashed operand copies from the fallback and enter value mode only after an attached `key=`. **Lines:** [dd:12,59,243–251](../dd_completer/dd_completer.ps1#L12).

### M4. comm leaves a free-text delimiter slot (R: seeded option cache)
`comm --output-delimiter REA|` suggests `README.md` and directories rather than preserving the delimiter. In `comm --output-delimiter | README.md` it also returns paths where the end-of-line control gives `<string>`. Keep ownership of the value slot on a prefix miss, and locate the predecessor relative to the cursor. **Lines:** [comm:205–218,236–238,264–283](../comm_completer/comm_completer.ps1#L205).

### M5. contig shifts positional slots inside a quote or after an invocation operator (R)
With a mocked file named `new file.bin`, `contig -n "new|` offers that filename. Adding a space **inside** the open quote switches to lengths such as `65536`. Separately, `& contig -n sample 65|` gives nothing where `contig -n sample 65|` offers `65536`. Determine word boundaries from syntax at the cursor; exclude both the invocation operator and command name when counting operands. **Lines:** [contig:187–196,449–457,494](../contig_completer/contig_completer.ps1#L187).

### M6. Copilot interprets literal prefixes as wildcard patterns (R: capture stubbed)
`copilot login --host *|` offers two sample URLs, neither starting with a literal asterisk. An opening single quote followed by a left bracket gives an invalid-pattern error instead of preserving the typed prefix. Use literal prefix matching in the host, plugin and marketplace filters; the host branch was exercised. **Lines:** [copilot:1181,1192,1198](../copilot_completer/copilot_completer.ps1#L1181).

### M7. Quoting a Cursor subcommand loses its child commands (R: root/node help stubbed)
`cursor-agent mcp l|` offers `list`; `cursor-agent 'mcp' l|` instead falls back to filesystem entries, including LICENSE. Route on the decoded value of a constant string AST, not its source spelling; do not evaluate expressions. **Lines:** [cursor_agent:491,526–529](../cursor_agent_completer/cursor_agent_completer.ps1#L491).

### M8. Local-only discovery can traverse remote paths on Tab (S + helper spy; no network probe)
For `cmd /C <Tab>`, a UNC component of PATH reaches `Directory.Exists` and `EnumerateFiles` during catalog construction ([cmd:198–204](../cmd_completer/cmd_completer.ps1#L198)); bare root command completion can also reach discovery ([cmd:352](../cmd_completer/cmd_completer.ps1#L352)). For an empty offline-image directory slot, autorunsc tests `IsReady` on all drives, including mapped network drives; a typed UNC parent also reaches `Test-Path`/`Get-ChildItem` ([autorunsc:264–268,285–300](../autorunsc_completer/autorunsc_completer.ps1#L264)). AccessChk likewise passes a UNC parent to `Get-ChildItem` on its default path route ([accesschk:286–291,583–589](../accesschk_completer/accesschk_completer.ps1#L286)). A helper probe with an in-memory enumeration spy recorded the parent; it made no provider call. Expected: local discovery only, without waiting on a remote filesystem. Reject remote paths and network-backed drives before the first filesystem call; test with fake drives/enumerators. The code paths are verified, not an observed connection or measured stall.

### M9. Escaped or quoted spaces send filename completion to the wrong place (R)
In ``attrib C:\Program` Fi|`` (PowerShell-escaped space), completion in this checkout offers only `.\findstr_completer`, replacing the absolute argument; the quoted control finds `C:\Program Files`. In `autorunsc -o "Demo |` the space is inside the open filename quote, yet Tab offers switches/users instead of staying in the output-path slot (profile discovery stubbed). Use cursor-local parsed extents for both the word boundary and the whole decoded filename. **Lines:** [attrib:103–125,251–267](../attrib_completer/attrib_completer.ps1#L103); [autorunsc:190–199,441–444,504–506](../autorunsc_completer/autorunsc_completer.ps1#L190).

### M10. base64 offers a flag cluster whose argument it cannot complete (R: fallback)
`base64 -di|` offers `-diw`; after accepting it, `base64 -diw |` gives paths and stdin instead of the width hints `0`, `64`, `76` returned for `-w`. Recognize a trailing value-taking flag in a validated short cluster. **Lines:** [base64:204–224,253–275,303–312](../base64_completer/base64_completer.ps1#L204).

### M11. A discovered executable name is inserted as multiple words (R: PATH catalog stub)
With a single catalog entry named `Demo Tool.exe`, `cmd /C Demo|` inserts bare `Demo Tool.exe` instead of an appropriately quoted command word. Accepting it no longer identifies the selected filename as one word. Quote names that require it even without an opening quote; verify argument boundaries without running a program. **Lines:** [cmd:223,238–239](../cmd_completer/cmd_completer.ps1#L223).

### M12. A global option before a Codex subcommand disables its local overlay (R: two stubs)
With a fixture session `fixture42` and a generator returning `generated`, `codex resume fix|` offers the session. `codex --model=foo resume fix|` instead calls the generator and loses the session overlay. Skip recognized global options and their arguments while continuing to identify the subcommand. **Lines:** [codex:470–478,529–531](../codex_completer/codex_completer.ps1#L470).

### M13. Synchronous discovery has no deadline (S)
On first generated completion, Codex invokes its launcher synchronously ([codex:60](../codex_completer/codex_completer.ps1#L60)). On an extension-cache miss, Code Insiders calls `--list-extensions` synchronously ([code_insiders:360,512](../code_insiders_completer/code_insiders_completer.ps1#L360)). If the child waits for input or does not exit, the callback cannot return in a bounded time. Expected: an unavailable result should leave Tab usable. Close stdin, bound capture time and cache failure briefly. Neither a hung launcher nor a live extension call was tested.

### M14. AccessChk inserts the wrong argument text in two value slots (R)
`accesschk -o \RPC|` offers bare `\RPC Control`, two words instead of the one object name shown ([accesschk:51,263,575](../accesschk_completer/accesschk_completer.ps1#L51)). Use the quote renderer for static candidates too. In `accesschk -f Everyone,Us|`, PowerShell replaces just `Us` (index 22, length 2), but the completer returns `Everyone,Us`, producing `Everyone,Everyone,Us` ([accesschk:247–268,548](../accesschk_completer/accesschk_completer.ps1#L247)). Complete the final account segment only, preserving the preceding list.

### M15. apm loses the active option after a preceding statement (R: live help disabled)
`apm init --format j|` returns `json`. Both `1; apm init --format j|` and `apm init --format j| --yes` return just `j`. The cursor is absolute, but the length comparison uses command-relative text and the argument list can include elements to the right. Use element extents in a single coordinate system and exclude the active word and later elements. **Lines:** [apm:1381–1406](../apm_completer/apm_completer.ps1#L1381).

### M16. cargo-binstall duplicates previously selected strategies (R: fixture help)
In `cargo-binstall --strategies crate-meta-data,qu|`, the replacement starts at index 44 and spans only `qu`. Returning `crate-meta-data,quick-install` therefore duplicates `crate-meta-data,` in the accepted argument. The attached form can even repeat the option prefix. Use earlier segments for filtering, but emit only the substring PowerShell will replace; assert the reconstructed line, not just the candidate. **Lines:** [cargo_binstall:246,341–351,490,510–511](../cargo_binstall_completer/cargo_binstall_completer.ps1#L246).

### M17. A valid TOML comment hides Cargo features (S + isolated regex check)
Given the in-memory lines `[features] # optional toggles` and `fast = []`, the actual section regex does not recognize the header. Consequently the parser cannot supply `fast` for `cargo-clippy --features fa` from that section. Accept trailing TOML comments without treating comment characters inside quotes as delimiters. **Lines:** [cargo_clippy:529–537](../cargo_clippy_completer/cargo_clippy_completer.ps1#L529). No live manifest or Rust build was used.

### M18. cargo counts a separate option value as a positional argument (R: fixture help)
`cargo search --limit 2 |` offers options but not `<query>`; `cargo search --limit=2 |` offers the expected query hint. Consume the option value without appending it to `Positionals`. **Lines:** [cargo:1066–1070,1078–1083,1371–1375](../cargo_completer/cargo_completer.ps1#L1066).

### M19. A toolchain probe mistakes failure text for success (R: capture stub; S for I/O risk)
With rustup lookup absent and the probe returning only an unavailable-toolchain error, `cargo +sta|` still offers `+stable`. The script tests for any captured output (including stderr) from `cargo +stable --version`, without the bounded/offline controls used elsewhere. Prefer installed-toolchain data; if a probe is necessary, require successful evidence and bound the child with auto-install disabled. No download, delay or actual toolchain invocation was observed. **Lines:** [cargo:60,89–104,439–443](../cargo_completer/cargo_completer.ps1#L60).

### M20. Claude's attached-value dispatch erases options and ignores their scope (R: static catalog)
`claude --max-budget-usd=|` replaces the entire option with `<n>`; `claude --name=|` similarly becomes `<value>`. Preserve the inline prefix as for `--effort=high`. `claude --version=|` also offers a value for a boolean, and `claude plugin list --effort=h|` offers `--effort=high` outside its catalog scope. Validate that the current command accepts this exact option and that it takes a value before entering inline dispatch. **Lines:** [claude:951–961,1153–1161](../claude_completer/claude_completer.ps1#L951).

## Low findings

Runtime evidence unless labeled otherwise. Examples are completion buffers, not commands to execute.

| ID | Location | Actual → expected; suggested change |
|---|---|---|
| L1 | [date:331,405](../date_completer/date_completer.ps1#L331) | In fallback, `date.exe +%:::` appends unrelated specifiers but omits `+%:::z`. One separator space in the fallback row does not pass the two-space parser. Align row and parser and assert this specifier. |
| L2 | [date:268–271](../date_completer/date_completer.ps1#L268); [df:201–205](../df_completer/df_completer.ps1#L201) | `date.exe -I=s` offers `-I=seconds`; `df.exe -B=M` offers `-B=MB`. The equals sign is part of a short-option argument. Restrict equals routing to long options; normalize or withhold malformed short spellings (valid attached examples: `-Iseconds`, `-BMB`). |
| L3 | [dd:377](../dd_completer/dd_completer.ps1#L377) | From the repo root, `dd.exe if=dd_comp` correctly finds the directory but marks it `ProviderItem`. Forward `ProviderContainer` when prefixing a directory result. |
| L4 | [dircolors:12,59](../dircolors_completer/dircolors_completer.ps1#L12) | With help unavailable, `dircolors.exe --p` duplicates `--print-database` and `--c` misses documented `--csh` and `--c-shell`. Deduplicate and align fallback aliases with the companion surface. |
| L5 | [compact:110–112,314–321](../compact_completer/compact_completer.ps1#L110) | `compact '/?' /E` offers `/EXE` and `/EXE:`; equivalent unquoted help suppresses them. Compare decoded literal switches and keep raw extents for replacement. |
| L6 | [copilot:461,576,601,743–749](../copilot_completer/copilot_completer.ps1#L461) | `copilot PLUGINS ma` offers `marketplace` just as lowercase `plugins ma` does, despite the documented case-sensitive command tree. Use ordinal alias dictionaries as for canonical commands. |
| L7 | [curl:730–735](../curl_completer/curl_completer.ps1#L730) | Given a process-local test variable with a unique prefix, `curl --variable %REVIEW7_` echoes the prefix instead of offering `%REVIEW7_BOUNDED` (help stubbed). Test whether the typed value starts with `%`, not whether `%` starts with the typed value. |
| L8 | [cursor_agent:284–286,397–407,460–461](../cursor_agent_completer/cursor_agent_completer.ps1#L284) | From repo root, `cursor-agent --workspace README` offers `README.md` for a directory. Filter for directories in directory-only slots. |
| L9 | [autorunsc:85–96,453,483–485](../autorunsc_completer/autorunsc_completer.ps1#L85) | `autorunsc.exe -a 'ls` offers no category continuations versus 17 for the unquoted prefix. Decode either quote style before category matching. |
| L10 | [autorunsc:414,424,535–552](../autorunsc_completer/autorunsc_completer.ps1#L414) | After a supplied user, `autorunsc DemoUser D` still offers a second mocked user (`Demo User`). Gate the user catalog on the positional count. |
| L11 | [base32:12](../base32_completer/base32_completer.ps1#L12) | With discovery disabled, `base32 -` offers `--ignore-garbage` but not the documented short form `-i`. Include it in the fallback. |
| L12 | [comfy_cli:335](../comfy_cli_completer/comfy_cli_completer.ps1#L335) | With two fixture positionals (text, then an enum), `comfy-cli -- a p` offers `plain`, but `comfy-cli -- -- p` echoes `p`. Only the first terminator is special; count subsequent literal `--` as an operand. |
| L13 | [comfy_cli:68–69,78–80](../comfy_cli_completer/comfy_cli_completer.ps1#L68) | For fixture help `One of: image, video, 3d.`, `comfy-cli --kind=` omits `3d`. Parse the entire list, including choices starting with digits, rather than accepting a partial match. Synthetic help only. |
| L14 | [7z:503,545,565–570](../7z_completer/7z_completer.ps1#L503) | With fixture help, `7z 'a' <Tab>` offers only command/switch names instead of local paths offered after unquoted `a`. Quoting the `--` argument also re-enables switches. Route on decoded previous arguments; retain the current raw span for insertion. |
| L15 | [agy:219,225–228,233](../agy_completer/agy_completer.ps1#L219) | With seeded plugin metadata, `agy plugin import 7z_c` echoes `7z_c`; `.\7z_c` yields the matching local directory. Combine enum and directory matches for bare relative prefixes too. |
| L16 | [cargo_clippy:320–330,946–948,1051](../cargo_clippy_completer/cargo_clippy_completer.ps1#L320) | With a seeded lint cache, `cargo-clippy -- -d wa` gives `warnings`, like valid `-D wa`. Match lint flags with an ordinal, case-sensitive map. |
| L17 | [cargo_clippy:551–553,705–713](../cargo_clippy_completer/cargo_clippy_completer.ps1#L551) | **S + regex check:** the package regex accepts `autobenchs`, not Cargo's `autobenches`. With `autobenches = false`, inferred bench names are not suppressed. Map the canonical plural explicitly; use an in-memory manifest/target fixture for regression. |
| L18 | [choco:526–531,1189–1196](../choco_completer/choco_completer.ps1#L526) | With empty help, `choco install -sour` returns nothing, unlike `/sour` and `--sour`, though value routing accepts `-source`. Preserve the user's single-dash long-name style. |
| L19 | [claude:1286–1292](../claude_completer/claude_completer.ps1#L1286) | `claude import codex ge` still offers `gemini` after the single optional source has been consumed. Gate suggestions on positional arity. |
| L20 | [code_insiders:1095–1100](../code_insiders_completer/code_insiders_completer.ps1#L1095); [companion .md:24](../code_insiders_completer/code_insiders_completer.md#L24) | **S (documentation):** the registration example passes an obsolete `-WordToComplete` argument absent from the shipped call. Copy the actual callback invocation into the example. |

**Unranked Chocolatey compatibility note (S only):** [choco:637–640](../choco_completer/choco_completer.ps1#L637) requests `list --local-only --limit-output --no-color` and skips output that is not a package/version record. For the documented 2.x target, use `list --limit-output --no-color`, omitting the obsolete `--local-only`. If that switch is rejected, package names and versions may be absent. This is a static compatibility concern, not an observed empty inventory or a live package lookup; it is excluded from the finding counts.

## Per-script coverage

The rows are the selected paths in order, not a severity ranking. Every row also has the three clean checks above. “Clean” here is scoped to those checks or to the named control, not the entire CLI.

| # | Reviewer | Tracked script | Findings | Scope / control |
|---:|---|---|---|---|
| 1 | review1 | `7z_completer/7z_completer.ps1` | L14 | Help fixture; command/switch routing, archive paths and listfiles. `7z a -r` returned `-r`, `-r-`, `-r0`. |
| 2 | review1 | `accesschk_completer/accesschk_completer.ps1` | M8, M14 | Static modes, object names, account lists, provider routing; enumeration spy only. |
| 3 | review1 | `agy_completer/agy_completer.ps1` | L15 | Seeded root/plugin tree; reviewed help capture, path and enum dispatch. Explicit relative directory matched. |
| 4 | review1 | `apm_completer/apm_completer.ps1` | M2, M15 | Static/live merge, option and positional routing; discovery disabled. `init --format j` matched `json` at end of line. |
| 5 | review2 | `attrib_completer/attrib_completer.ps1` | M9 | Static switch and filename routing; `attrib +R` and `attrib.exe /` produced the expected flag families. |
| 6 | review2 | `autorunsc_completer/autorunsc_completer.ps1` | M8, M9, L9, L10 | Category, user and offline-path slots; mock user only. Unquoted category concatenation worked. |
| 7 | review2 | `base32_completer/base32_completer.ps1` | M1, M2, L11 | Fallback/help catalog, width and path routing; `base32.exe --wrap=6` offered `--wrap=64`. |
| 8 | review2 | `base64_completer/base64_completer.ps1` | M2, M10 | Cluster, width, stdin and path routing; mid-line standalone `-w` returned widths. |
| 9 | review3 | `basename_completer/basename_completer.ps1` | M2 | Cached catalog; suffix and path routing. `basename --suffix <Tab>` gave `<suffix>`. |
| 10 | review3 | `bun_completer/bun_completer.ps1` | M2 | Help/alias context, project caches, forwarding; no binary. `bun pm pkg g` gave `get`. |
| 11 | review3 | `cargo_binstall_completer/cargo_binstall_completer.ps1` | M16 | Fixture help, strategy lists, target and operand slots; a sole `qu` completed to `quick-install`. |
| 12 | review3 | `cargo_clippy_completer/cargo_clippy_completer.ps1` | M17, L16, L17 | Lint boundary/case, workspace/target and TOML parsing; no Rust build. Uppercase `-D` matched the seeded lint. |
| 13 | review4 | `cargo_completer/cargo_completer.ps1` | M18, M19 | Root help, toolchain selection and option state (capture stubs); attached limit retained query hint. |
| 14 | review4 | `choco_completer/choco_completer.ps1` | L18 | Fallback root/subcommands, option spelling, help/data dispatch; `choco config li` offered `list`. |
| 15 | review4 | `cksum_completer/cksum_completer.ps1` | M2 | Parsed-help-shaped cache, algorithm/value and path routing; `--he` without terminator offered `--help`. |
| 16 | review4 | `claude_completer/claude_completer.ps1` | M20, L19 | Static command scopes, option types and argument counts; `--effort=h` offered `--effort=high` at root. |
| 17 | review5 | `cmd_completer/cmd_completer.ps1` | M8, M11 | Internal commands, PATH catalog, slash switches and quoting; `/E:O` returned `/E:ON` and `/E:OFF`. |
| 18 | review5 | `codex_completer/codex_completer.ps1` | M2, M12, M13 | Generated-completion handoff and scoped overlays (stubs); `completion po` gave `powershell`. |
| 19 | review5 | `code_insiders_completer/code_insiders_completer.ps1` | M2, M13, L20 | Extension capture stub, inline/scope routing; `tunnel user login --provider g` gave `github`. |
| 20 | review5 | `comfy_cli_completer/comfy_cli_completer.ps1` | L12, L13 | In-memory help nodes; reviewed command tree, choice parsing and positional counts. First test operand advanced to the enum. |
| 21 | review6 | `comm_completer/comm_completer.ps1` | M2, M4 | Help/cache fallback, delimiter and path dispatch; empty end-of-line delimiter gave `<string>`. |
| 22 | review6 | `compact_completer/compact_completer.ps1` | L5 | Slash catalog, attached enums/paths, terminal help; unquoted `/EXE:XPRESS1` gave `/EXE:XPRESS16K`. |
| 23 | review6 | `contig_completer/contig_completer.ps1` | M5 | Three forms, manual tokenizer and cache; `contig -f X` returned the seeded `X:` drive. |
| 24 | review6 | `copilot_completer/copilot_completer.ps1` | M6, L6 | Alias/scope maps, config/paths and dynamic value filters; `--model <Tab>` gave `auto` and `<model>` with capture stubbed. |
| 25 | review7 | `csplit_completer/csplit_completer.ps1` | M1, M2 | Seeded options, FILE/PATTERN and path routing; `csplit - <Tab>` offered patterns. |
| 26 | review7 | `curl_completer/curl_completer.ps1` | M2, L7 | Fixture help, option/protocol enums, variable and file routing; `curl -x <Tab>` offered proxy values. |
| 27 | review7 | `cursor_agent_completer/cursor_agent_completer.ps1` | M7, L8 | Stub root/node help; command, directory and enum routing; `--mode=pl` gave `--mode=plan`. |
| 28 | review7 | `cut_completer/cut_completer.ps1` | M1, M2 | Seeded options, separate/attached values and files; `cut --bytes <Tab>` gave `<list>` at end of line. |
| 29 | review8 | `date_completer/date_completer.ps1` | M1, M2, L1, L2 | Fallback options, relative dates and format tokens; `--iso-8601=s` offered `--iso-8601=seconds`. |
| 30 | review8 | `dd_completer/dd_completer.ps1` | M3, L3 | Fallback operand catalog, prefixed files and lists; `conv=sync,no` offered the `nocreat`, `notrunc` and `noerror` continuations. |
| 31 | review8 | `df_completer/df_completer.ps1` | M1, M2, L2 | Fallback units, filesystem types and fields; `--output=source,fs` offered `--output=source,fstype`. |
| 32 | review8 | `dircolors_completer/dircolors_completer.ps1` | M2, L4 | Fallback switch and operand routes; `./dircol` offered the matching local directory. |
