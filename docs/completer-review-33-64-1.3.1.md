# Completer review: positions 33–64 at v1.3.1

**Baseline:** `master`, HEAD and tag `v1.3.1` at `04cdd463f999cba23324f6ca18907854fd2f6dc5`. Eight groups reviewed four scripts and their same-stem documentation each. **Result: 4 high-priority, 6 medium and 2 low grouped findings.** Every script had at least one finding. All 32 passed structural validation and cold load.

**Fix first:** Do not use an unvalidated endpoint (H1), read remote ACLs for principal hints (H2), start an external Git helper for metadata (H3), or accept terms on Tab (H4). Then test the accepted argument, not just its label: handle's quoted process name and raw placeholder illustrate two different failures (M1).

## Selection and evidence

```powershell
$sha = '04cdd463f999cba23324f6ca18907854fd2f6dc5'
[string[]]$paths = @(git ls-tree -r --name-only $sha | Where-Object { $_ -cmatch '^([^/]+_completer)/\1\.ps1$' })
[Array]::Sort($paths, [StringComparer]::OrdinalIgnoreCase)
$paths[32..63]
```

176 eligible paths; sort full tracked paths before slicing. Positions 32 and 65 are `dircolors` and `markitdown`. R = observed callback, registered completion, recording spy or parser check as indicated. S = static trace, not observed effects. `^` marks the cursor. Filename output may be engine fallback. High priority denotes a consent, execution or remote-access boundary; medium denotes materially incorrect argument/routing; low denotes narrower matching or fallback defects.

Independent checks: Windows `pwsh 7.7.0 -NoProfile`, zero parse errors and zero CompleterActions 3.0.1 `Test-CompleterScript` findings for all 32. Dot-sourcing each script in a fresh runspace yielded zero cold `$Error` entries and zero error-stream records. Missing-tool `TabExpansion2` probes confirmed post-terminator option dispatch and fmt/fold mid-line width regressions. No suggested command was submitted. No live remote endpoint, EULA acceptance, ACL/adapter change or external Git helper execution tested. The full Pester/package suite stages files and was not run. Fixture results do not establish installed CLI parity.

## High-priority findings

### H1. Docker can check one endpoint and forward another
**R, real endpoint gate / recorder.** With a synthetic Unix default pointing to an existing repository file, `docker -Htcp://example.invalid logs ` and `docker logs --host=tcp://example.invalid ` dispatched `__complete` with the original endpoint-bearing argv. The leading long-form control dispatched nothing. Resolve the exact forwarded settings; decline ambiguous forms. No client/daemon contacted. [docker:142–184,249–263,292–293,331–335,363–367](../docker_completer/docker_completer.ps1#L142).

### H2. icacls passes a remote operand to ACL discovery
**R, provider spy.** Completing `/setowner` with an inert UNC operand returned `Everyone`, but the `Get-Acl` spy recorded the UNC path. The [companion](../icacls_completer/icacls_completer.md#L328) promises local-only identity discovery. Use static identities unless the target is positively local; check before provider access. No network or ACL operation observed. [icacls:446–463,893,905–911](../icacls_completer/icacls_completer.ps1#L446).

### H3. Git requests help from external commands listed by name
**R, recording stub.** The catalog includes `others`. A listed synthetic `samplecmd` absent from the alias table reached `git samplecmd -h` on Tab. External helpers need not treat `-h` as passive metadata. Offer the name without invoking it; restrict active help to known built-ins. No external helper executed. [Git:619–621,665–690](../Git_completer/Git_completer.ps1#L619).

### H4. ListDLLs supplies consent during tooltip discovery
**S.** First Tab initializes the catalog and can request `-accepteula -nobanner /?`. Use the static catalog; do not accept terms on the user's behalf. Neither acceptance nor a persistent change was observed. [listdlls:126–135,200,503](../listdlls_completer/listdlls_completer.ps1#L126).

## Medium findings

### M1. Quote and validate the accepted argument
**R, fixture / parser.** `handle -p "Demo App" ` offered a trailing name-fragment hint; the single-quoted equivalent lost it because `App'` was counted as a separate operand. Use literal AST argument values. The hint itself is not a valid insertion: `handle <name-fragment>`, `head -n <num>`, `groff -F <directory>` and `grok --model <value>` all reparsed with `RedirectionNotSupported`. Keep guidance in display text. Similar bare hints came from `expr match abc `, `factor ` and `du --exclude `. Synthetic spaced process names in handle/ListDLLs, `IIS Express` from dotnet, `TEST NAME` after `env -u` and `hello world` after `groff -d` were inserted as multiple arguments. ipconfig's `West;Lab` parsed as two statements; `West $Desk` expanded in double quotes. icacls exhibited the same issue with synthetic identities. gh returned `repos/{owner}/{repo}` as multiple AST elements, and jq's `map(` left an unmatched parenthesis. **S + parse checks:** fsutil's `$corrupt` log name becomes a variable; gawk's `|` separator becomes pipeline syntax. Render literal data as one argument and reparse accepted lines without submitting them. Lines: handle:214–223,307–313,366–384,472,522–524; head:225–238; groff:755–769,781–786; grok:634; expr:192–195,324; factor:122; du:475–483; listdlls:371–381; dotnet:2122–2131; env:179–187,242; ipconfig:48–53,363; icacls:481–497; gh_cli:375–380,441–444; jq:348–352; fsutil:992,1469–1473,1996; gawk:18–24,1063–1068,1156–1158 (stems resolve to ledger paths).

### M2. A settled terminator or pending option does not own the next word
**R.** `-- --he` still offered `--help` for dirname, factor, fmt, fold, head, join, link and ln. Analogous fixture probes returned switches after `--` in du, fd, Git, grep, grok and jq. Go offered `-mod=vendor` after the flag boundary. Conversely, `grep -e --color=a` interpreted the pattern as an attached color switch. Consume pending values, then the terminator; gate both name and attached-value dispatch on this state. Lines: dirname:218–233; factor:146–165; fmt:374–405; fold:302–320; head:317–337; join:371–387; link:147–163; ln:304–319; du:294–337,528–536; fd:810–831; Git:1489–1497,1523–1533; grep:782–813; grok:671–682,725–744; jq:284–305,337; go:865–884,1254–1274,1335.

### M3. Later arguments change the current slot
**R.** fmt/fold returned `72` at `--width 7^` but `7z_completer` (a directory) at `--width 7^ next`. `head -n 1^ later` lost its numeric ladder, `env -u T^ tail` its fixture variable, and `ln -S ^ target` its suffixes. At `dotnet watch ^ run` the future `run` hid the expected watch commands. Use the predecessor of the active word rather than the last element of the entire AST. Lines: fmt:246–253,374–405; fold:236–243,302–320; head:211–219,317–340; env:164–170,458; ln:210–218,295–318; dotnet:362–373,2077–2085.

### M4. Quoted text is routed using shell spelling rather than argument value
**R.** `dism '/Mount-Image' /Mou`, `grok 'plugin' --` and `dsc 'config' get --out` lost the child switches offered by their unquoted controls. In `just "red^ blue"` the recorder received `"red`, opening quote included, instead of the decoded prefix. In `findstr /C:"two ` the final space belongs to the search string, but the proposed switch/file results replaced the entire `/C:` word (index 8, length 8). ListDLLs lost the matching DLL in `-d "paper a`. Decode constant AST values without evaluation and treat only unquoted, unescaped whitespace as a boundary. Lines: dism:359–362,529–546,760–780; grok:477–480,665–691; DSC:419–424; just:25–40; findstr:260–270,619–634; listdlls:505–530.

### M5. Wrong operand type or count survives dispatch
**R.** `join -a ma` offered `map.txt` where only 1 or 2 is valid; `jq --args . ma` offered a file rather than a string. `ln -t pa` admitted regular files when the directory filter had no matches. `dsc resource list Test/Alpha --out` lost the expected output flag. Repeated Docker container operands stopped completing after two names. **S:** fsutil counted the `/l` value in `8dot3name scan /l log.txt ` as the required directory; gawk offered only `inp=` in `gawk -f prog.awk inp`, excluding matching files. Track consumed option values, repeatable operands and slot ownership even on a prefix miss. Lines: join:259–265,362–386; jq:25–26,284–305,358; ln:255–262,295–318; DSC:437,518,982–995; docker:635–651,1028–1041; fsutil:1155–1161,1675–1682; gawk:1243–1251.

### M6. fd can call a session function instead of native help
**R, synthetic resolver.** A function-like command with empty `Source` was invoked by name with `--help` during initialization. Resolve applications only and use the executable path; otherwise use the static catalog. [fd:51–53,62–68](../fd_completer/fd_completer.ps1#L51).

## Low findings

- **L1 (R).** `false --he` matched `--help`; `false "--he` did not. link missed fixture `park place` with a backtick-escaped space, and still offered paths after both required operands. Decode literal prefixes and enforce arity. Lines: false:99–106,130–145; link:38–46,100–112,146–162.
- **L2 (R, empty help stubs).** DISM's empty elevated-help result caused a strict-mode `.Count` error; fd initialized its cache on empty help and did not retry. Normalize empty output; track successful initialization independently. Lines: dism:477–478,523–524; fd:345,382.

## Coverage ledger and no-findings coverage

Every selected script had at least one confirmed issue. Clean structural checks apply to every row; they do not establish full runtime coverage. Each line reference above is relative to the indicated tracked script unless specifically labeled as documentation.

| # | Group | Tracked script | Findings | Coverage / control |
|---:|---|---|---|---|
| 33 | review1 | `dirname_completer/dirname_completer.ps1` | M2 | Terminator versus filename. |
| 34 | review1 | `dism_completer/dism_completer.ps1` | M4, L2 | Quoted command and empty help; no DISM operation. |
| 35 | review1 | `docker_completer/docker_completer.ps1` | H1, M5 | Endpoint recorder and repeatable fixture operand. |
| 36 | review1 | `dotnet_completer/dotnet_completer.ps1` | M1, M3 | Watch command and synthetic SDK profile. |
| 37 | review2 | `DSC_completer/DSC_completer.ps1` | M4, M5 | Quoted config and optional list name. |
| 38 | review2 | `du_completer/du_completer.ps1` | M1, M2 | Pattern and post-terminator switch. |
| 39 | review2 | `env_completer/env_completer.ps1` | M1, M3 | Synthetic name and mid-line unset. |
| 40 | review2 | `expr_completer/expr_completer.ps1` | M1 | Keyword operand and regexp hint. |
| 41 | review3 | `factor_completer/factor_completer.ps1` | M1, M2 | Numeric placeholder and option dispatch. |
| 42 | review3 | `false_completer/false_completer.ps1` | L1 | Unquoted switch control matched. |
| 43 | review3 | `fd_completer/fd_completer.ps1` | M2, M6, L2 | Resolver fixture, option boundary and empty cache. |
| 44 | review3 | `findstr_completer/findstr_completer.ps1` | M4 | Open quoted search and replacement span. |
| 45 | review4 | `fmt_completer/fmt_completer.ps1` | M2, M3 | End-of-line width control matched. |
| 46 | review4 | `fold_completer/fold_completer.ps1` | M2, M3 | Width versus later operand. |
| 47 | review4 | `fsutil_completer/fsutil_completer.ps1` | M1, M5 | Log literals and scan operands; no administration. |
| 48 | review4 | `gawk_completer/gawk_completer.ps1` | M1, M5 | Field separator and assignment/file ambiguity. |
| 49 | review5 | `gh_cli_completer/gh_cli_completer.ps1` | M1 | Cobra fallback and API endpoint; no GitHub call. |
| 50 | review5 | `Git_completer/Git_completer.ps1` | H3, M2 | Fake external command and path/option boundary. |
| 51 | review5 | `go_completer/go_completer.ps1` | M2 | Attached build flags with synthetic help. |
| 52 | review5 | `grep_completer/grep_completer.ps1` | M2 | Pending pattern and terminator. |
| 53 | review6 | `groff_completer/groff_completer.ps1` | M1 | Quoted definition and directory placeholder. |
| 54 | review6 | `grok_completer/grok_completer.ps1` | M1, M2, M4 | Text value, terminator and child context. |
| 55 | review6 | `handle_completer/handle_completer.ps1` | M1 | Single-quoted process argument and name-fragment syntax. |
| 56 | review6 | `head_completer/head_completer.ps1` | M1, M2, M3 | Count placeholder and mid-line numeric ladder. |
| 57 | review7 | `icacls_completer/icacls_completer.ps1` | H2, M1 | ACL spy and synthetic identities; no ACL change. |
| 58 | review7 | `ipconfig_completer/ipconfig_completer.ps1` | M1 | Synthetic adapter names; no renewal. |
| 59 | review7 | `join_completer/join_completer.ps1` | M2, M5 | Restricted selector and terminator. |
| 60 | review7 | `jq_completer/jq_completer.ps1` | M1, M2, M5 | Filter starter and post-filter arguments. |
| 61 | review8 | `just_completer/just_completer.ps1` | M4 | Recorded mid-token versus end-of-word argv. |
| 62 | review8 | `link_completer/link_completer.ps1` | M2, L1 | Escaped space, arity and terminator. |
| 63 | review8 | `listdlls_completer/listdlls_completer.ps1` | H4, M1, M4 | Consent trace, process/DLL fixtures; no inventory. |
| 64 | review8 | `ln_completer/ln_completer.ps1` | M2, M3, M5 | Directory-only target, suffix and terminator. |
