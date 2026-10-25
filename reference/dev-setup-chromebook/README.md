# dev-setup-chromebook

**ADHD brain + four Chromebooks: everything I wondered whether I could run on them. Kitchen sink, but tested.**

[![lint](https://github.com/dhouse109/dev-setup-chromebook/actions/workflows/lint.yml/badge.svg)](https://github.com/dhouse109/dev-setup-chromebook/actions/workflows/lint.yml)

![The end of a dev-test run: every installed component checked](docs/test-run.png)

Four bash scripts that turn the Linux environment on a Chromebook (Debian 13, inside ChromeOS) into a
development machine. A bare run installs a modest base. Everything else sits behind flags:

- Rust, Go, .NET, Java, C/C++ and assembly
- SQL Server, Oracle and Solr in Docker
- local LLMs with Ollama, and Kubernetes with kind
- Windows 3.1, 95, NT 4.0 and 2000 with Delphi 1 through 7

Yes, it's a lot. That's the point. It's what happened when I kept asking "could this laptop do *that*?"
and then made the answer repeatable. I plan to split pieces out for specific projects. This repository is
the whole lab, as it is.

| Script | What it does |
|---|---|
| `dev-setup-chromebook.sh` | Installs. Unattended, idempotent, safe to rerun. |
| `dev-init-chromebook.sh` | Logins, API keys and config, from one secrets file (`~/.config/dev-init/secrets.env`, mode 600). The scripts never contain keys. |
| `dev-test-chromebook.sh` | Checks that every installed component actually works, not just that it's on PATH, and writes a per-stack disk-usage report. |
| `dev-demo-chromebook.sh` | Optional. Installs runnable demos for each stack into `~/dev-demo`. |

All four take the same flags, so `install-web install-node` means the same thing to each of them.

> **Current version: v93.** [CHANGELOG.md](CHANGELOG.md) has the full history.

## What it is, and what it isn't

**It is** a personal lab, shared as is. Every flag exists because I wanted that thing on these machines.
The comments in the scripts explain the reasoning, including the dated notes on what broke and how it
was fixed.

**It isn't**:
- a minimal setup
- a dotfiles manager
- anything for a server

It has been run on Chromebooks only. The scripts refuse to run anywhere else unless you insist (see
[Safety](#safety)).

## Quick start

In the Chromebook's Linux terminal:

```bash
git clone https://github.com/dhouse109/dev-setup-chromebook.git
cd dev-setup-chromebook

./dev-init-chromebook.sh                          # 1. writes ~/.config/dev-init/secrets.env, then stops
nano ~/.config/dev-init/secrets.env               #    fill in what you have; empty is fine
./dev-setup-chromebook.sh install-web             # 2. install: no flags = the base only
./dev-init-chromebook.sh install-web              # 3. apply logins and config
./dev-test-chromebook.sh install-web              # 4. check it all works
```

The order is **init → setup → init → test**. Init runs twice because the first run only writes the
secrets template. The [init checklist](docs/init-checklist.md) walks through the whole sequence, and says
where each key in the secrets file comes from.

## Docs

| Doc | What's in it |
|---|---|
| [Init checklist](docs/init-checklist.md) | Run order, every flag, the secrets file, the steps to get each service's credential, and GUI first runs |
| [dev-demo](docs/dev-demo.md) | What each demo does, what it downloads, how much disk it takes, and how to reclaim the space |
| [Crostini gotchas](docs/crostini-gotchas.md) | Where ChromeOS's Linux differs from a normal Debian box, and the fix for each difference |
| [The epics](docs/dev-setup-chromebook-epics.md) | The whole history, v1 to the latest version, grouped by theme: the eras, then twelve epics with the versions that delivered each one |
| [CHANGELOG.md](CHANGELOG.md) | Every version, newest first |

Before you start, I'd back up your Linux environment or start a fresh one. ChromeOS can back up and
restore all of Linux from its Linux settings page. Then nothing here can cost you more than a restore.

## Flags

With no flags, setup installs only the base. Group flags expand into their members, and dependencies
pull in what they need. For example, `install-web` brings `install-node` with it.

**The base, always installed:**
- build tools, git, Python with pipx and uv
- ffmpeg, jq, shellcheck, direnv, sqlite3 and psql
- Docker
- Homebrew with DDEV, gh and mkcert
- Google Chrome
- an ed25519 SSH key

### In `install-all`

| Group | Members |
|---|---|
| `install-editors` | `install-vscode` `install-windsurf` `install-cursor` `install-lazarus` (Lazarus / Free Pascal) |
| `install-languages` | `install-rust` (with WASM) `install-node` (nvm, Node LTS, Claude Code, Codex, Gemini CLI, aider) `install-go` `install-pwsh` `install-ruby` (Jekyll) `install-cpp` `install-asm` `install-dotnet` (C#, VB.NET) `install-java` (JDK, Maven, Gradle) |
| `install-ecosystems` | `install-antigravity` `install-media` (Flatpak, HandBrake, KDiff3) `install-gemma` (Gemma on Ollama + Gemini) `install-mobile` (Android SDK, Tauri, React Native/Expo, Flutter) `install-android-native` (Android Studio, Kotlin) `install-godot` (standard + .NET editors) |
| `install-cloud` | `install-aws` `install-azure` `install-gcp` `install-vercel` `install-cloudflare` (wrangler) |
| `install-iac` | Terraform, tflint, Bicep and `install-ansible-full` |
| `install-cache` | `install-redis` `install-memcached` |
| `install-search` | `install-solr` `install-opensearch` `install-meilisearch` `install-typesense` |
| `install-vector` | `install-qdrant` and sqlite-vec |
| `install-testing` | `install-playwright` `install-selenium` (Grid in Docker) `install-bdd` (Gherkin runners) `install-robot` (Robot Framework) |

`install-all` also includes these single flags:

| Flag | What it installs |
|---|---|
| `install-web` | Angular CLI, corepack, Composer, PHP extensions |
| `install-tanstack` | TanStack CLI |
| `install-drupal` | Terminus, Acquia CLI, Upsun CLI, DDEV settings |
| `install-laravel` | Laravel tooling |
| `install-symfony` | Symfony tooling |
| `install-graphql` | Apollo Rover, Router and MCP Server |
| `install-k8s` | kubectl, helm, kind, k9s |
| `install-db` | ODBC, Firebird, client libraries |
| `install-db-extra` | SQLite, PostgreSQL, MariaDB and DuckDB ODBC drivers |
| `install-lakehouse` | DuckDB, dbt, DuckLake, Delta Lake |
| `install-agentic` | Temporal, LangGraph, Pydantic, Langfuse |
| `install-jev` | Jev |
| `install-mongodb` | MongoDB 8, mongosh, Compass |
| `install-gitlab` | glab, gitlab-ci-local |
| `install-vue` | Vue and Nuxt tooling |

The shared services (Redis, Solr, MongoDB and the rest) run in Docker on 127.0.0.1 behind one command,
`devsvc`. Only Redis and Memcached start with Linux. Everything else waits for `devsvc up NAME`, and the
heavy engines run one at a time, because Linux gets about 6.4 GB of an 8 GB Chromebook.

### Opt-in only (not in `install-all`)

| Flag | What it adds |
|---|---|
| `install-db-server` | SQL Server 2025, Oracle 26ai Free (both in Docker) and InterBase: `install-mssql` `install-oracle` `install-interbase` |
| `install-oracle-full` | Oracle's full image instead of Lite |
| `install-ldap` / `install-ldap-full` | lldap in Docker / OpenLDAP + lldap |
| `install-lan` / `install-lan-share` | your laptops as one network (Tailscale, an address book, shared services) |
| `install-retro` | DOS and Windows 3.1 / 95 / NT 4.0 / 2000 guests (DOSBox-X, QEMU), Open Watcom, Delphi 1–7 under Wine; pulls in `install-com` (COM development under Wine) |
| `install-models` | curated local models for Ollama (several GB) |
| `install-ollama-containers` | lets Docker containers reach Ollama |
| `install-hermes` / `install-openclaw` | personal agents |
| `install-elasticsearch` `install-milvus` `install-mongodb-atlas-local` | heavier alternatives to the shared services above |
| `install-cypress` | Cypress's system libraries |
| `install-gitlab-runner` | a GitLab Runner service |
| `install-puppet` / `install-chef` / `install-config-mgmt` | OpenVox + OpenBolt / Cinc Workstation / both |
| `install-godot-templates` | Godot export templates (~2.5 GB) |
| `install-asm-arm` | AArch64 cross toolchain + qemu-user |
| `install-cloudflared` | Cloudflare Tunnel (puts local services on the internet) |
| `install-ansible-core` | Ansible without the community collections |

## Requirements

- **Hardware:** a Chromebook with Linux turned on. Developed on four x86-64 Chromebooks with 8 GB of RAM.
- **OS:** Debian 13 (trixie), which is what ChromeOS's Linux runs on these machines. It runs both in the
  Crostini container and in the full Linux VM that newer ChromeOS releases create.
- **Disk:** three of the four machines give Linux an 80 GB disk and run several stacks together. The
  fourth has 25 GB and handles a few stacks at a time. Setup's disk guards say what they need before
  they pull big images, and dev-test's disk report shows what each stack really took.

## Safety

These scripts are made for a disposable, single-user Linux environment, and they act like it:

- They run `sudo` freely.
- They add apt sources and pipe vendor installers (`curl … | sh`) the way the vendors document.
- They change system files.

Read [what they change](#what-they-change-on-your-system) before you run them.

- **Host guard.** Each script stops at once unless it's running in ChromeOS's Linux on Debian.
  `DEV_BUNDLE_ANY_HOST=1` overrides that, at your own risk.
- **Secrets.** Secrets only live in `~/.config/dev-init/secrets.env` (mode 600). Values named `*_ONCE` are
  used once to log in and are never exported. Platform tokens are optional, and nothing forces you to get
  any.
- **Services.** Every service listens on 127.0.0.1 unless you share it with `install-lan-share`. Sharing
  goes over Tailscale, so it only reaches your own tailnet, and Redis, Qdrant and MongoDB refuse to be
  shared until they have a password.
- **Downloads.** Downloads are checked where the vendor publishes a checksum, and validated (`gzip -t`,
  `dpkg-deb`, a test run) before they replace anything.

### What they change on your system

- **apt sources and keyrings**
  - Docker, Microsoft (packages-microsoft-prod, VS Code), Windsurf, Google Cloud
  - Tailscale (`install-lan`)
  - the Flathub remote (`install-media`)
- **`/etc`**
  - a line in `/etc/gai.conf` and `/etc/apt/apt.conf.d/99force-ipv4`, only when this network's IPv6 is
    broken
  - a marked block in `/etc/hosts` (`install-lan`)
  - systemd units and drop-ins: Ollama, the LAN relay, slapd, tailscaled, gitlab-runner
  - `/etc/ld.so.conf.d/oracle-instantclient.conf` and ODBC driver registrations in `/etc/odbcinst.ini`
- **`/opt` and `/usr/local`**: Android Studio, InterBase, Oracle's SQLcl and Instant Client, the DuckDB
  ODBC driver, Antigravity, Open Watcom, PowerShell, Go, Cinc, OpenVox
- **System libraries:** one compatibility link, `libaio.so.1 → libaio.so.1t64`, for Oracle Instant
  Client on trixie.
- **Root-owned setuid helper:** Antigravity's bundled `chrome-sandbox`, which Electron needs.
- **Trust stores:** `mkcert -install` adds a local CA to the system and browser trust stores.
- **Your user:**
  - added to the `docker`, `video` and `render` groups, and `kvm` for retro
  - its password removed (`passwd -d`), on ChromeOS only, where sudo needs none
- **Your home:**
  - marked blocks in `~/.bashrc`, rewritten in place on each run
  - commands in `~/.local/bin` (`devsvc`, `mssql`, `oracle`, `ldap`, `lan`, the retro guests…)
  - settings in `~/.config/dev-*`, `devsvc`, `devldap` and `devdb`
  - downloads and logs in `./assets` next to the scripts
- **Docker:** containers and named volumes called `devdb-*`, `devsvc-*` and `devldap-*`.
- **Telemetry:** switched off wherever a tool has a switch for it.

### Licenses you accept by running a flag

The scripts accept some vendors' terms on your behalf so the install can run unattended. By running these
flags, you are agreeing to these terms. Read them first if that matters to you.

- **`install-db` / `install-mssql`**: Microsoft's EULA for ODBC Driver 18 and SQL Server Developer
  edition (`ACCEPT_EULA=Y`).
- **`install-mobile` / `install-android-native`**: the Android SDK licenses (`sdkmanager --licenses`,
  `flutter doctor --android-licenses`).
- **`install-graphql`**: the Elastic License 2.0 for Rover's composition and router plugins
  (`APOLLO_ELV2_LICENSE=accept`).
- **`install-oracle`**: Oracle's free-use terms for Database Free, SQLcl and Instant Client.
- **`install-interbase`**: Embarcadero's EULA for the Developer Edition, via a silent install of the
  download you provide.
- **`install-redis`**: Redis Insight's Server Side Public License.
- **`install-openclaw`**: OpenClaw's onboarding risk notice (`--accept-risk`).

Chrome, VS Code, Cursor, Windsurf, Android Studio and Antigravity come under their vendors' usual terms.

### Bring your own media

The repository contains no Windows, DOS, Delphi or InterBase media, and the scripts never download any.
The retro guests, Delphi and InterBase install only from files you own and put in the folders the scripts
name. The Antigravity IDE comes the same way: from a tarball you download yourself.

## Crostini gotchas

Many of these scripts' 93 versions were spent on how ChromeOS's Linux differs from a normal Debian box.
A few of the findings:

- **GPU.** Windowed OpenGL needs the `render` group. Without it, Godot and friends silently fall back to
  software rendering.
- **No Vulkan.** Godot runs on its Compatibility renderer.
- **IPv6.** A network can hand out IPv6 addresses with no route out. `wget` then hangs from one address to
  the next while the browser works fine.
- **No more port forwarding.** Newer ChromeOS releases run Linux as a full VM, and Linux port forwarding
  is gone. The laptops reach each other over Tailscale instead, and `tailscaled` must be told to leave
  userspace mode.
- **PATH shadowing.** Homebrew's dependencies (python3, sqlite3, openjdk, binutils) shadow Debian's
  unless Homebrew goes last on PATH.
- **Android Studio.** The window dims while focused under ChromeOS's Wayland. Forcing the X11 toolkit
  fixes it.

The full list, with the fix for each, is in [docs/crostini-gotchas.md](docs/crostini-gotchas.md).

## How it was built

I built this with AI pair programmers. The first versions, up to about v49, were one script written
with Gemini. From about v50 on it's Claude, and that's when the single script became the four-script
bundle. Either way, I decide what goes in and run it on the Chromebooks; the AI drafts and reviews the
bash. `dev-test` is the referee, and a version isn't done until its test run is clean.

Every change bumps all the scripts to the same version number, and [CHANGELOG.md](CHANGELOG.md) keeps
the notes. [The epics](docs/dev-setup-chromebook-epics.md) tell the same story grouped by theme, which
is the faster way to see how the bundle got here.

**Next:** I plan to split the bundle into per-project pieces, build a Windows/WSL bundle, and move the
helper commands the setup script writes out (`devsvc`, `lan`, the retro guests) into files of their own.

## Contributing

This is a personal lab: issues are welcome and PRs will be considered, but there's no support promise.
If something breaks on your Chromebook, the end of a `dev-test` run is the most useful thing to paste
into an issue.

## License

MIT, see [LICENSE](LICENSE). The tools the scripts install keep their own licenses (see
[above](#licenses-you-accept-by-running-a-flag)).
