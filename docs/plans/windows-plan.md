# Windows Dev Setup Planning

2026-09-28 · Damien · moved into this repo 2026-10-25

> **Imported from the Claude Doc "Windows Dev Setup Planning"** (last edited 2026-09-28, written against
> Chromebook bundle v81). Everything below the next section is the doc as it stood, unchanged except that
> its architecture diagram is redrawn as text. The next section lists what has changed since, so read it
> first. The first job in this repo is to turn this doc into a build plan for the Windows bundle's first
> version (`docs/plans/v1-plan.md` or whatever numbering is chosen; see Open questions).

## What changed since 2026-09-28 (added 2026-10-25)

- **The Chromebook bundle is at v93, published** at
  [dhouse109/dev-setup-chromebook](https://github.com/dhouse109/dev-setup-chromebook) (commit `ef863ce`).
  A read-only copy of that release is in `reference/dev-setup-chromebook/`; it is what this bundle ports
  from. v94 (Lazarus as a Qt5 IDE with light/dark profiles, docked/floating layouts and a `lazmode`
  command) is planned there and not yet built.
- **The version history file** is now `CHANGELOG.md` (one section per script, newest first), not
  `dev-setup-chromebook-version-history.md`.
- **LAN sharing now runs over Tailscale.** The 2026-09-29 "home Wi-Fi only (no Tailscale)" choice was
  reversed on 2026-10-05: newer ChromeOS runs Linux as a full VM with no port forwarding, so the
  Chromebooks reach each other over Tailscale (`tailscaled` in normal tun mode, not userspace).
  `install-lan` / `install-lan-share` were rebuilt on it in v93, with `LAN_SHARE` as the single list of
  shared services. The "Laptop network" section below predates this and needs revisiting: the Windows
  laptops would join the same tailnet rather than rely on mirrored networking and LAN firewall rules alone.
- **The MCP sharing port moved from 8000 to 8770** (v89), so it no longer clashes with
  `php artisan serve` / `symfony serve`. The port table below still says 8000.
- **Flags added since the porting map below (v82–v93), not yet mapped to Windows:**
  - databases: `install-db-server` (`install-mssql`, `install-oracle`, `install-interbase`; opt-in),
    `install-oracle-full`, `install-ldap` / `install-ldap-full`
  - shared services behind `devsvc`: `install-cache` (Redis, Memcached), `install-search` (Solr,
    OpenSearch, Meilisearch, Typesense), `install-vector` (Qdrant, sqlite-vec), `install-mongodb`, and
    the opt-in `install-elasticsearch`, `install-milvus`, `install-mongodb-atlas-local`
  - web and PHP: `install-laravel`, `install-symfony`, `install-graphql` (Apollo Rover, Router, MCP
    Server), `install-vue`
  - cloud: `install-cloudflare` (wrangler), opt-in `install-cloudflared`
  - testing and CI: `install-testing` (`install-playwright`, `install-selenium`, `install-bdd`,
    `install-robot`), opt-in `install-cypress`, `install-gitlab` (glab, gitlab-ci-local), opt-in
    `install-gitlab-runner`
  - config management (opt-in): `install-puppet`, `install-chef`, `install-config-mgmt`
  - network (opt-in): `install-lan`, `install-lan-share`
  - retro and COM (opt-in): `install-retro` (DOS, Windows 3.1/95/NT 4.0/2000 guests in DOSBox-X and
    QEMU, Open Watcom, Delphi 1–7 under Wine) and `install-com`. On Windows several of these may make
    more sense natively (Delphi on the host, Hyper-V or QEMU for the guests); not yet discussed.
  - personal agents (opt-in): `install-hermes`, `install-openclaw`
  - other (opt-in): `install-godot-templates`
- **The compatibility review below** covers v76. v82–v93 have not been reviewed for WSL; the README and
  CHANGELOG in `reference/` say what each added.

## Purpose and status

Nothing is built yet: this doc collects every decision and finding about the Windows version of the dev bundle, so work can start from here instead of from chat history.

- The Chromebook bundle (setup / test / init / demo) is at v81 as of 2026-09-28; it is the reference the Windows bundle ports from. Since v81 the four scripts' version history lives in one bundle file, dev-setup-chromebook-version-history.md, instead of each script's header.
- Add to the log at the end whenever the Windows version comes up, and promote settled items into Decisions.

## Decisions so far

| Date | Decision |
| --- | --- |
| 2026-09-27 | Proposed, not yet confirmed: run Ollama natively on Windows, not inside WSL, so it can use the Intel and AMD iGPUs through Vulkan; WSL tools reach it at localhost. |
| 2026-09-27 | This doc is the central place for Windows-version planning until the build starts. |
| 2026-09-25 | Target WSL with Ubuntu or Debian on the Windows laptops. |
| 2026-09-25 | Build a separate Windows bundle rather than making the Chromebook bundle platform-aware. |

## Target machines

d3 is the strongest box and the natural home for local models; d4 has the RAM but the weakest CPU.

| Machine | Model | CPU | RAM | Disk | GPU | Likely role |
| --- | --- | --- | --- | --- | --- | --- |
| 109.hpe.d3 | HP Envy 15" | Ryzen 5 5500U (6c/12t) | 32 GB | 1 TB | Radeon iGPU (Vulkan) | Main Windows dev box; LAN model server |
| 109.hpe.d1 | HP Envy 17" | i7-1065G7 | 16 GB | 1 TB | GeForce MX330, 2 GB | Dev box; small CUDA offload |
| 109.hpp.d2 | HP Pavilion 15" | i5-10210U | 16 GB | 1 TB | Intel UHD | Dev box, CPU only |
| 109.hpr.d4 | HP 14" | Pentium Silver N5030 (no AVX/AVX2) | 32 GB | 500 GB | Intel UHD 605 | Light dev; cloud-model client |

## Architecture

The proposed split: Windows-native pieces live on the host, everything the bundle scripts install lives in WSL, and one Ollama on d3 serves both WSL and the Chromebooks.

```
Windows host · 109.hpe.d3                          Chromebooks (Crostini)
┌──────────────────────────────────────────┐        ┌─────────────────────────────┐
│ Ollama for Windows (native)              │◄───────│ ollama-remote wrapper (v77) │
│ Vulkan on Intel/AMD iGPUs; CUDA on d1    │ LAN    │ local Ollama stays CPU-only │
│ listens on 11434                         │ :11434 └─────────────────────────────┘
└──────────────────────────────────────────┘
                  ▲ localhost:11434
┌──────────────────────────────────────────┐
│ WSL 2: Ubuntu or Debian                  │
│ runs the Windows bundle's tools          │
│ aider, LangChain, gemma client → Ollama  │
└──────────────────────────────────────────┘
Proposed layout, not yet confirmed
```

WSL reaches the host's Ollama at localhost (WSL mirrored networking); the Chromebooks reach it over the LAN once d3 sets `OLLAMA_HOST=0.0.0.0:11434` and opens the Windows firewall for that port.

- On WSL, NVIDIA CUDA passes through to Linux, but Intel and AMD iGPUs have no practical Vulkan path, which is why Ollama belongs on the Windows side.
- The Windows-side counterpart of the ChromeOS launcher entries (Cursor, Godot, Antigravity) is still open: native Windows installs, or WSLg Linux apps.

### Laptop network (Chromebook v84)

The Chromebook bundle's v84 adds `install-lan` (an address book, `LAN_HOSTS`, written into /etc/hosts, and a `lan` command) and `install-lan-share` (a relay that shares a Chromebook's services). The Windows bundle should serve on the same ports, so `lan scan` on a Chromebook finds the Windows laptops' services without extra settings.

| Service | Port on the network | Windows side to plan |
| --- | --- | --- |
| Ollama | 11434 | Native Ollama with `OLLAMA_HOST=0.0.0.0:11434`, plus an inbound firewall rule on the Private profile |
| SQL Server | 1433 | Container published on 0.0.0.0, or native SQL Server with TCP/IP enabled |
| Oracle Free | 1521 | Container published on 0.0.0.0 (service FREEPDB1) |
| lldap / OpenLDAP | 3890 and 17170 / 1389 | The same ports; OpenLDAP moved off 389 as on the Chromebooks |
| DDEV sites | 8080 and 8443 | DDEV in WSL with `router_bind_all_interfaces` and router ports 8080/8443, or a relay as on the Chromebooks |
| Dev and MCP servers | 3000, 4200, 5173 / 8000 | Started with --host / 0.0.0.0, as on the Chromebooks |

WSL needs mirrored networking (`networkingMode=mirrored` in `.wslconfig`) so its services answer on the laptop's own address, and inbound rules in both Windows Defender Firewall and the Hyper-V firewall that governs WSL. The Wi-Fi network must be set to Private. Windows-native apps take laptop names from `C:\Windows\System32\drivers\etc\hosts`, the counterpart of `lan hosts apply`; the `lan` command itself runs unchanged inside WSL.

## Local models on Windows

d3's 32 GB makes it the one Windows laptop that runs 14B-class models comfortably; the other three stay at 8B or below. Sizes are Ollama's Q4 downloads as of 2026-09-27; nothing here has been benchmarked on these machines yet.

| Machine | Acceleration | Comfortable | Stretch |
| --- | --- | --- | --- |
| d3 | CPU + Radeon iGPU via Vulkan | `deepseek-r1:8b` / `14b` (5.2 / 9.0 GB), `qwen3.5:9b` (6.6 GB), `gemma4:12b-it-qat` (7.2 GB) | `gemma4:26b-a4b-it-qat` (16 GB, MoE, ~4B active); `deepseek-r1:32b` (20 GB) fits but crawls |
| d1 | MX330 (Pascal, driver 570+), 2 GB VRAM | Up to `deepseek-r1:8b` | `gemma4:12b-it-qat` |
| d2 | CPU only | Up to 7-8B | none |
| d4 | CPU only, no AVX/AVX2 | 1-2B | none; better as a cloud-model client |

- **DeepSeek:** only the R1 distills run locally. V4-Pro and V4.1-Flash (~760B) are Ollama `:cloud` tags, billed per token after `ollama signin`; V4.1-Flash is $0.30 in / $1.20 out per million tokens, half off-peak.
- **Vulkan check:** Ollama for Windows enables Vulkan by default; compare against CPU with `OLLAMA_VULKAN=0`, since a shared-memory iGPU doesn't always win.
- **Carry over from Chromebook v77:** the server tuning (`OLLAMA_MAX_LOADED_MODELS`, `OLLAMA_NUM_PARALLEL`, `OLLAMA_CONTEXT_LENGTH`, flash attention, q8_0 KV cache), set as Windows user environment variables instead of a systemd drop-in, with values sized per machine.
- **d3 as LAN server:** `OLLAMA_HOST=0.0.0.0:11434` plus a firewall rule scoped to the private network; the Chromebooks' `OLLAMA_REMOTE` in `secrets.env` points at it.

To fill the table with real numbers once d3 serves models: from a Chromebook, `~/dev-demo/models/run-compare.sh remote` (Chromebook bundle v77) sends one prompt to every model on `OLLAMA_REMOTE`'s server and prints load time and tokens per second per model. Run it without `remote` for the Chromebook's own figures.

Sources: [Ollama DeepSeek models](https://ollama.com/search?q=deepseek) · [deepseek-r1 tags](https://ollama.com/library/deepseek-r1/tags) · [gemma4 tags](https://ollama.com/library/gemma4/tags) · [qwen3.5 tags](https://ollama.com/library/qwen3.5/tags) · [Ollama pricing](https://ollama.com/pricing) · [Ollama hardware support](https://docs.ollama.com/gpu)

## Porting the Chromebook bundle

Most flags port to WSL almost unchanged; the work concentrates in GPU, GUI apps, Docker and Android. This map is a first pass from the v77 flag list, updated for v80 (install-interbase, install-ollama-containers, Firebird in install-db; v78, v79 and v81 added no flags). It is not a settled design.

| Chromebook flag(s) | Where on Windows | What changes |
| --- | --- | --- |
| base section (apt, pipx/uv, SSH key, Homebrew, Chrome) | WSL | Ubuntu vs Debian package names; ChromeOS-specific steps (`passwd -d`, video/render groups) drop out |
| Docker (base) | Open: Docker Desktop with WSL integration, or Docker Engine inside WSL | Decides how kind, DDEV and Langfuse compose run |
| install-languages (rust, node, go, pwsh, ruby, cpp, asm, dotnet, java) | WSL | PowerShell and .NET also exist natively on Windows; decide whether WSL copies are still wanted |
| install-editors (vscode, windsurf, cursor, lazarus) | Windows host | Native installers (winget); VS Code attaches to WSL via Remote-WSL instead of a Linux install |
| install-ollama, install-gemma, install-models | Windows host (Ollama); WSL (Python clients, gemma launcher) | Ollama tuning via user env vars; WSL clients use localhost |
| install-ollama-containers (v80) | Windows host (Ollama's listen address) | The systemd drop-in becomes OLLAMA_HOST=0.0.0.0:11434 as a Windows user env var, which d3's LAN role needs anyway. With Docker Desktop, host.docker.internal is the Windows host, so DDEV's drupal-rag demo reaches native Ollama; with Docker Engine inside WSL that name points at the WSL VM, so the route depends on the Docker decision |
| install-interbase (v80, opt-in) | Open: Windows host (native InterBase) vs WSL (the same Linux installer) | In WSL it ports as-is (/opt/interbase, ib-* wrappers, init's console registration). On the host, registration and the server move to Windows, WSL clients connect over TCP on port 3050, and the ib-* wrappers and init step drop out |
| install-agentic, install-lakehouse, install-db, install-db-extra | WSL | Little change; RAM notes relax on the 16-32 GB machines. Since v80 install-db includes Firebird 4 from Debian packages (firebird4.0-*, firebird-utils), whose Ubuntu names are unchecked (see Open questions) |
| install-cloud, install-iac, Ansible, install-k8s | WSL | Little change; kind needs the Docker decision above |
| install-web, install-tanstack, install-drupal, install-vercel, install-jev | WSL | Little change; DDEV depends on the Docker decision |
| install-mobile, install-android-native | Open: Android Studio on Windows (emulator works there) vs WSL | Crostini's `adb connect arc` path has no Windows equivalent |
| install-godot | Windows host | Native Godot gets the real GPU (Vulkan), unlike Crostini's virgl OpenGL |
| install-antigravity, install-media | Windows host | Native installers |
| install-asm-arm | WSL | Unchanged |

The four-script bundle (setup / test / init / demo), shared flags, the versioning rule, the `assets/` folder and optional-by-default tokens in `secrets.env` all carry over as conventions.

## Compatibility review of the Chromebook bundle under WSL

On Debian 13 in WSL2 most of v76 runs as-is; on Ubuntu, setup aborts early because several steps hardcode Debian repo paths and package names under `set -e`. Reviewed against v76 on 2026-09-25; v77 only added the Ollama and model flags. v78 to v81 were not re-reviewed; the likely new Ubuntu gap is v80's Firebird packages in install-db (see Open questions). All four laptops are x86-64, so the hardcoded `amd64` downloads are fine.

| Impact | Area | Problem under WSL | Fix in the Windows bundle |
| --- | --- | --- | --- |
| Breaks the run | Docker repo (Ubuntu) | Source line is `linux/debian $(lsb_release -cs)`; an Ubuntu codename under the Debian path fails `apt update` | Pick the repo path from `/etc/os-release` |
| Breaks the run | Microsoft prod repo (Ubuntu) | `config/debian/${VERSION_ID}` becomes `debian/24.04` and 404s, so install-dotnet and install-db fail; Ubuntu also packages .NET itself | Per-distro repo path; pin .NET to one source; align the test's `packages-microsoft-prod` checks |
| Breaks the run | Base apt list (Ubuntu) | `libasound2` and `libappindicator3-1` have no candidate on 24.04+; `libfuse2` may need `libfuse2t64` by name; one miss kills the whole install | Distro package map for the t64 and Ayatana names |
| Breaks the run | systemd (Debian on WSL) | Docker, kind, Langfuse and the Ollama drop-in need it; Ubuntu's WSL image enables it, Debian's likely does not | Preflight check; `[boot] systemd=true` in `/etc/wsl.conf`, then `wsl --shutdown` |
| Wrong for Windows | `sudo passwd -d $USER` | Removes the Linux account's password on a Windows laptop; the test expects `sudo -n true` | Choose a sudo policy (NOPASSWD drop-in, or keep the password) and align the test |
| Wrong for Windows | GPU | WSLg uses `/dev/dxg` and Mesa D3D12: no virgl, no `renderD128`, no sommelier, so those test checks fail even when accelerated | Skip the video/render groups; test accepts D3D12 and fails only on llvmpipe; Godot keeps `opengl3` |
| Wrong for Windows | Android | The `-cros.deb` Studio build and `adb connect arc` (setup, test, init) are ChromeOS-only; the emulator needs nested virtualization for `/dev/kvm` | Generic Linux tarball or Studio on Windows; devices via usbipd-win or the Windows adb server |
| Wrong for Windows | Browser opening | `demo_open` falls back to `xdg-open`, which opens Linux Chrome in WSLg; init's gh, codex and gcloud logins do the same | Install `wslu`; `demo_open` and `BROWSER` use `wslview` |
| Wrong for Windows | Editors and launchers | VS Code, Cursor and Windsurf install as Linux GUI apps; `.desktop` entries appear in the Windows Start menu via WSLg | Windows-side editors attached through their WSL remote extension; reword the launcher text |
| Wrong for Windows | mkcert | CA trusted in Linux only, so a Windows browser warns on DDEV sites | Windows-side trust step, printed as instructions |
| Wrong for Windows | Messages and hints | "Shut down Linux (right-click Terminal)", balloon notes, the `@chromebook` SSH key comment | `wsl --terminate <distro>` or `wsl --shutdown`; drop the Crostini notes |
| WSL hazard | Windows PATH interop | Windows `npm` and `code` shims can satisfy `command -v` checks when the Linux tool is missing | `appendWindowsPath=false` in `wsl.conf`, or a preflight warning |
| WSL hazard | Bundle location | Running from `/mnt/c` puts `assets/` on the Windows filesystem: slow, and setuid `chrome-sandbox`, exec bits, pipx and venv paths break | Preflight refuses `/mnt/*`; keep the bundle inside the Linux home |
| WSL hazard | Line endings | Scripts passed through Windows Git or an editor get CRLF: `$'\r': command not found` | Preflight check for CRLF |
| WSL hazard | Resources | WSL caps memory at 50% of host RAM; inotify watches may fall under the test's 30000 | Size memory in `.wslconfig`; `sysctl` for inotify |
| WSL hazard | Ubuntu 25.10+ | sudo-rs and Rust coreutils replace sudo and GNU coreutils; the scripts rely on `timeout -k`, `stat -c`, `readlink -f`, `setsid -w` | Confirm on a full test run |

The preflight should also stop when Docker Desktop's WSL integration is active, since it conflicts with docker-ce (see the Docker open question).

## Bundle approach: separate vs platform-aware

A separate Windows bundle is the chosen route (2026-09-25). It also gives the Windows-host half a natural home: a PowerShell script (for example `dev-host-windows.ps1`) that runs first, then hands off to the bash scripts inside WSL.

| Approach | Strengths | Costs |
| --- | --- | --- |
| Separate Windows bundle (chosen) | Chromebook bundle stays untouched after its clean run (PASS 272, FAIL 0); scripts read straight through with no platform branches; Windows choices (host-side editors, `wslview`, sudo policy, D3D12 checks) are first-class; the Crostini history in comments can go; own version numbers and docs | Drift: most code is shared (flag expansion, Homebrew PATH block, nearly every stack), so platform-neutral fixes like v59, v61 and v74 must be applied twice; versioning and companion docs double |
| Platform-aware Chromebook bundle (considered first) | One codebase: a `PLATFORM` / `DISTRO` detection layer plus a preflight, shared by all four scripts | Every change re-verifies the Chromebooks; branches in every script; no place for the Windows-host PowerShell half |

The host script covers what has no Chromebook counterpart: enabling WSL and installing the distro, `wsl.conf` and `.wslconfig`, Docker Desktop's WSL integration off, Windows-side editors with their WSL remote extensions, usbipd-win, and mkcert trust on Windows.

Keeping drift down:

- Fork from the latest Chromebook release, targeting Debian 13 on WSL, so the two bundles stay as close as possible.
- Keep the same flag names, section order and section headings, so `diff -u` between the setup scripts shows only real platform differences.
- Tag each future release note with whether it applies to the other bundle (ports to Windows: yes / no / n.a.).
- Optionally extract a shared `dev-common.sh` later for sections that never differ; only if porting becomes a chore, since it touches the Chromebook bundle.

Every fix in the compatibility review above becomes a straight edit in the fork rather than a platform branch.

## Open questions

- [ ] Ubuntu or Debian as the WSL distro? Debian matches the Chromebook container (trixie); Ubuntu is WSL's default.
- [ ] Confirm Ollama runs natively on Windows rather than in WSL.
- [ ] Docker Desktop with WSL integration, or Docker Engine inside WSL?
- [ ] How is the Windows-host half installed: winget from PowerShell, a Windows script the WSL script calls, or manual steps in the checklist?
- [ ] One bundle for all four laptops, or per-machine tiers (d3 heavier models, d4 client-only)?
- [ ] Android: Android Studio on Windows with its emulator, or keep it out of the Windows bundle?
- [ ] Should d3 serve models to the Chromebooks by default, and on which network?
- [ ] Version numbering: does the Windows bundle start at v1 or share numbers with the Chromebook bundle?
- [ ] sudo on WSL: a NOPASSWD drop-in, or keep the account password (setup's `passwd -d` stays out either way)?
- [ ] Extract a shared `dev-common.sh` later, or keep the two bundles as full forks?
- [ ] Script names for the Windows bundle, since the `-chromebook` names no longer fit?
- [ ] Does Ubuntu package Firebird 4 the way trixie does (firebird4.0-utils, firebird4.0-server-core, firebird-utils, libfbclient2)? If not, install-db needs a per-distro map for it.
- [ ] InterBase (install-interbase): Windows host or WSL?
- [ ] Version history: does the Windows bundle keep its own history file, following the Chromebook bundle's v81 layout?

## Discussion log

| Date | Topic | Outcome |
| --- | --- | --- |
| 2026-09-29 | Laptops reaching each other's services (Chromebook v84) | Home Wi-Fi only (no Tailscale); Chromebook side built in v84 (install-lan, install-lan-share); the Windows side is planned in the Laptop network section above, on the same ports |
| 2026-09-28 | Chromebook bundle v78 to v81 | Doc brought up to v81: porting map gains install-ollama-containers and install-interbase, install-db notes Firebird 4; three open questions added (Firebird on Ubuntu, InterBase placement, version-history file) |
| 2026-09-27 | Local models across all eight machines, DeepSeek options | Per-machine model table above; native Ollama on Windows proposed; d3 as LAN model server proposed; Chromebook v77 adds `OLLAMA_REMOTE` for it |
| 2026-09-27 | Central planning doc | This doc created |
| 2026-09-25 | Running the bundle on the Windows laptops | WSL with Ubuntu or Debian; a separate Windows bundle rather than a platform-aware Chromebook bundle. The v76 compatibility review and the bundle-approach comparison are in the sections above |
