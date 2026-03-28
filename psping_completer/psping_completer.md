# psping completer

## What it completes / overview

`psping_completer.ps1` registers a native PowerShell argument completer for `psping` and `psping.exe`.

The completer follows the repository's standalone pattern: a single self-contained `.ps1` script plus this companion markdown document. It uses static mode and switch metadata for the command grammar, while doing a lightweight local root-help check once per session when `psping` is installed. The grammar is still owned by static metadata because the local WindowsApps help surface is incomplete for some modes.

## Registration and command names

The script ends by calling:

```powershell
Register-ArgumentCompleter -Native -CommandName 'psping', 'psping.exe' -ScriptBlock { ... }
```

Load it into the current session with:

```powershell
. .\psping_completer.ps1
```

## How completion works

### Root help handling

At the top level, the completer offers the documented root help switch and banner switch:

- `-?`
- `-nobanner`

After `-?`, completion is intentionally restricted to the four documented help topics:

- `i`
- `t`
- `l`
- `b`

That keeps the registered runtime behavior aligned with the actual PsPing help grammar instead of falling back to unrelated file completion.

### Mode-sensitive switch completion

The completer tracks a lightweight command state from the tokens before the cursor and chooses one of these syntax surfaces:

- generic / undecided
- ICMP ping
- TCP ping
- latency client
- bandwidth client
- latency/bandwidth server

Key mode-sensitive behaviors:

- `-s` switches completion into the server surface and expects an `<address:port>` bind value
- `-b` switches completion into bandwidth mode
- `-u` is treated as a flag in latency mode
- `-u` can take an optional target-bandwidth value in bandwidth mode
- `-i` suggests interval seconds in ping modes, but outstanding I/O counts in bandwidth mode
- `-t` and `-n` are treated as mutually exclusive
- `-4` and `-6` are treated as mutually exclusive

### Value-aware placeholders

For switches that take values, the completer returns semantic suggestions instead of filesystem fallback:

- `-h` -> histogram hints such as `20`, `100`, `0.01,0.05,1,5,10`, and `<buckets|comma-separated thresholds>`
- `-i` -> `0`, `0.1`, `1`, `<seconds>` in ping modes; `1`, `4`, `8`, `16`, `<outstanding I/Os>` in bandwidth mode
- `-l` -> request sizes such as `64`, `1k`, `8k`, `64k`, `1m`, and `<requestsize[k|m]>`
- `-n` -> counts such as `10`, `100`, `1000`, `10s`, and `<count[s]>`
- `-w` -> warmup counts such as `1`, `3`, `5`, `10`, and `<count>`
- `-s` -> server bind shapes such as `<address:port>`, `0.0.0.0:5000`, and `127.0.0.1:5000`
- `-u` in bandwidth mode -> `10`, `100`, `1000`, and `<target MB/s>`

If the current token does not match one of the static hints, the completer echoes the current token back for that value slot so PowerShell does not fall through to local file completion.

### Positional destinations and endpoints

The completer uses static, non-probing placeholders for target positions:

- ICMP destination values: `<destination>`, `localhost`, `127.0.0.1`, `::1`
- TCP / latency / bandwidth endpoint values: `<destination:port>`, `localhost:80`, `127.0.0.1:443`
- Server bind values: `<address:port>`, `0.0.0.0:5000`, `127.0.0.1:5000`

The script does not attempt DNS lookups, port discovery, host discovery, or network probing during completion.

## Coverage notes

### Supported major modes

The completer is designed around the documented PsPing surfaces:

- ICMP ping
- TCP ping
- latency test (client/server)
- bandwidth test (client/server)

### Shared/common switches

The static grammar covers the documented shared/common switches:

- `-n`
- `-i`
- `-h`
- `-l`
- `-q`
- `-t`
- `-w`
- `-4`
- `-6`

### Latency/bandwidth-specific switches

The completer also covers:

- `-s`
- `-u`
- `-b`
- `-r`
- `-f`

## Why the grammar is mostly static

Local `psping.exe` is commonly available through a WindowsApps alias and its help output is not complete enough to serve as the sole source of truth. In particular, the locally observed TCP help omits `-l`, while the Microsoft Sysinternals documentation includes it in the TCP ping usage. Because of that, this completer keeps the grammar static and only uses a cached local root-help read as a lightweight validation signal.

## Usage / loading example

```powershell
. .\psping_completer.ps1

psping <TAB>
psping -?<TAB>
psping -? <TAB>
psping -n <TAB>
psping -b -u <TAB>
psping -s <TAB>
psping localhost:<TAB>
```

## Validation notes

The intended validation path is a clean PowerShell 7 session using `pwsh -NoProfile` and `TabExpansion2`, so the registered native completer behavior is tested through the real completion engine instead of by invoking helper functions directly.

## Limitations / notes

- The completer intentionally does not do any live network discovery or probing.
- Destination and endpoint suggestions are static placeholders/examples, not enumerated hosts or ports.
- The script relies on static metadata for correctness because the local help surface is incomplete.
- `-u` optional-value behavior is only surfaced after bandwidth mode is selected with `-b`.
