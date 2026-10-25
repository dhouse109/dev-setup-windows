# Init checklist

*Working notes kept alongside the scripts, copied at the v93 release. The "since vNN" remarks date each behaviour; [CHANGELOG.md](../CHANGELOG.md) has the full story.*

## Run order

Run init once before setup to get the secrets template, fill it while setup downloads, then run init again after setup. Only the first init run is safe before setup; the second needs the tools setup installs (`gh`, `hf`, `adb`, `eas`, `claude`, `codex`, `gemini`, `aws`, `az`, `gcloud`, `ng`, `dotnet`, `vercel`, `terminus`, `acli`). All three scripts take the same flags and are versioned as one bundle (v93 as of this doc).

1. `./dev-init-chromebook.sh install-all` — writes `~/.config/dev-init/secrets.env` and exits.
2. Fill in the keys (sections below). Filling in the file logs nothing in by itself; step 5 applies it.
3. `./dev-setup-chromebook.sh install-all` — 30–60 minutes of downloads, fully unattended since v68; see Running setup.
4. `source ~/.bashrc`
5. `./dev-init-chromebook.sh install-all` — applies the keys, logs in (GitHub, Hugging Face, cloud CLIs, Vercel), uploads the SSH key, runs `adb connect arc`.
6. `./dev-test-chromebook.sh install-all` — verifies every component and every login. Run before step 5 it still works, but reports each login as a WARN and says init is pending.
7. Work through the GUI first-run list that init prints at the end.

Running init early by mistake does no damage: steps fail or skip, and rerunning after setup applies them, since every step is idempotent. Add `noninteractive` to skip any login prompt you did not supply a token for. An existing `secrets.env` is upgraded in place: init appends the sections a newer version added when they are missing (AWS / Azure / Google Cloud in v57, Vercel and Jev in v67, the machine label and Drupal hosting tokens in v68), so don't delete the file; run init once after updating the scripts to get them.

## Running setup

Setup installs and asks for nothing. Run it from the Linux terminal, in the directory holding the scripts.

### Before the first run

- ChromeOS Settings → About ChromeOS → Linux development environment → turn on Linux (Debian 13 on current builds); set the disk size while you're there (see ChromeOS settings).
- Clone the repository into a folder of its own under Linux files (the scripts create an `assets` folder next to themselves). The version history is CHANGELOG.md, beside the scripts.
- Since v65 the scripts keep what they generate in an `assets` folder next to themselves, not loose in the home directory: test logs in `assets/logs`, installer downloads in `assets/downloads` (emptied after install), and `assets/gemma_client.py`. Drop the Antigravity `.tar.gz` bundle in `assets` too. The test script moves older `~/dev-test-*.log` and `.output` files into `assets/logs` on start, and setup with install-gemma adds a gemma command to \~/.bashrc that runs the client with its venv (open a new terminal, then type gemma) and clears the old `~/gemma_client.py`. Tool dot-directories and the `~/lakehouse` and `~/agentic` workspaces stay where they are.
- On ChromeOS, setup runs `sudo passwd -d $USER` near its start, so you are never prompted for a password again (the scripts stop on any other machine unless `DEV_BUNDLE_ANY_HOST=1`, and even then skip this step). `set -e` means any failure aborts; rerunning is safe, every block is idempotent.

### Flags

The same expansion is used by all three scripts, so a flag set that installs is the flag set that tests and initializes.

| Flag | Installs |
| --- | --- |
| *(none)* | Base: apt packages, pipx and uv, SSH key, Docker, Homebrew with ddev/gh/mkcert, Chrome |
| `install-all` | Every category below |
| `install-editors` | vscode, windsurf, cursor, lazarus |
| `install-languages` | rust, node, go, pwsh, ruby, cpp, asm, dotnet, java |
| `install-ecosystems` | antigravity, media, gemma (pulls in install-ollama), mobile, android-native, godot |
| `install-godot` | Godot standard (GDScript) and .NET (C#) editors side by side, godot and godot-mono launchers, app-drawer entries; pulls in install-dotnet (v66, part of install-ecosystems) |
| `install-godot-templates` | Godot export templates for both editors, about 2.5 GB to download; opt-in only, not part of install-all (v66) |
| `install-ollama` | The Ollama server (moved out of install-gemma; install-gemma, install-models and install-ollama-containers pull it in) with a systemd drop-in: 15-minute load timeout, at most two models loaded (Ollama adds the second only when both fit), one request per model, 8K context with flash attention and a q8\_0 KV cache; OLLAMA\_API\_BASE for aider and the ollama-remote wrapper in \~/.bashrc. Ollama's installer, which downloads the whole bundle, is skipped when the latest release is already installed (OLLAMA\_REINSTALL=1 forces it). CPU-only in Crostini (v77, part of install-all through install-gemma) |
| `install-models` | deepseek-r1:1.5b, qwen3.5:4b and qwen3-embedding:0.6b, about 5 GB; OLLAMA\_EXTRA\_MODELS adds more (pass it on every run, or the recorded list drops them). Skips a pull that would leave under DEV\_MODELS\_MIN\_FREE\_GB (default 10 GB, or 15% of the Linux disk when that is less, since v92) free; never pulls :cloud tags. Pulls in install-ollama; opt-in only, not part of install-all (v77) |
| `install-ollama-containers` | A second Ollama drop-in with OLLAMA\_HOST=0.0.0.0:11434, so Docker containers (DDEV's web container, for a Drupal AI site) reach Ollama at http://host.docker.internal:11434. Local clients are unaffected and ChromeOS does not expose the port to the network. Later runs without the flag keep it; undo by deleting dev-setup-containers.conf and restarting Ollama. Pulls in install-ollama; opt-in only, not part of install-all (v80) |
| `install-mobile` | tauri, rn, flutter; pulls in rust and node automatically |
| `install-db`, `install-db-extra` | MSSQL, Paradox and Lazarus client libs, Firebird 4 with its embedded engine (isql-fb, gbak; v80); SQLite, PostgreSQL, MariaDB, DuckDB ODBC |
| `install-interbase` | Embarcadero InterBase from the download you put in assets: silent install into /opt/interbase, instance gds\_db on port 3050. Its tools stay off PATH (ib-isql, ib-gbak, ib-mgr in \~/.bashrc) and libgds.so off the library path, so a Lazarus program picks InterBase or Firebird with a TSQLDBLibraryLoader. The Developer Edition needs registering before its server starts: init does that. Opt-in only, not part of install-all (v80); part of install-db-server since v82. A zip is unpacked into assets/downloads/interbase, kept if the install fails (setup prints the console-mode command for it) and removed once InterBase is installed (v81) |
| `install-db-server` | The database servers: install-mssql, install-oracle and install-interbase. Opt-in only, not part of install-all: the two container images are about 3 GB each, and a pull is skipped when it would leave under DEV\_DB\_MIN\_FREE\_GB (default 10 GB, or 15% of the Linux disk when that is less, since v92) free; the reason is kept in \~/.config/devdb/\<engine>.skipped, and setup's summary, init and test quote it. Each engine holds about 2 GB while it runs, so the containers are created stopped and the mssql and oracle commands start one at a time (v82) |
| `install-mssql` | SQL Server 2025 Developer in Docker: container devdb-mssql on 127.0.0.1:1433, login sa, data in the volume devdb-mssql-data, capped at MSSQL\_MEMORY\_MB (default and minimum 2048). Plus the Go sqlcmd and ODBC Driver 18. A rerun recreates the container on a newer image (DB\_SERVER\_RECREATE=1 forces it) and keeps the volume (v82, part of install-db-server) |
| `install-oracle` | Oracle AI Database 26ai Free (Lite image) in Docker: container devdb-oracle on 127.0.0.1:1521, service FREEPDB1, login system, data in the volume devdb-oracle-data. Plus SQLcl as sql (with the JDK install-java uses) and Instant Client with its ODBC driver, registered as Oracle ODBC. A newer image is not applied on its own, since that upgrades the database: setup says how, and DB\_SERVER\_RECREATE=1 does it (v82, part of install-db-server) |
| `install-oracle-full` | install-oracle on Oracle's full image (about 3.6 GB to download, 9.5 GB on disk, against 1.8 GB for Lite), for the optional database components Lite leaves out. Its data lives in its own volume, devdb-oracle-full-data: moving from Lite starts an empty database with the same password and leaves the Lite one in devdb-oracle-data. Remembered: later runs with plain install-oracle or install-db-server keep it on full. Back to Lite: docker rm -f devdb-oracle, then setup with install-oracle. Opt-in, in no group (v83) |
| `install-ldap` | LDAP, the lite directory: lldap in Docker, container devldap-lldap on 127.0.0.1:3890 with a web UI on 127.0.0.1:17170, data in the volume devldap-lldap-data. It runs all the time (about 20 MB of RAM) and joins DDEV's network as lldap, so Drupal in DDEV reaches ldap://lldap:3890. Base DN dc=example,dc=com unless LDAP\_BASE\_DN says otherwise; people alice, bob, carol, groups drupal\_editors and drupal\_admins, and the read-only service account uid=drupal-bind. Plus ldap-utils, php-ldap and the ldap command (status, up, down, search, login, passwords, drupal, ui, logs). Opt-in, in no group (v83) |
| `install-ldap-full` | OpenLDAP itself, Debian's slapd, a systemd service on port 389 with the whole protocol (ldapadd/ldapmodify, schemas, overlays, cn=config), admin cn=admin,\<base DN>, the same people and groups; reached from DDEV as ldap://host.docker.internal:389. Includes install-ldap, so lldap runs next to it. A slapd serving another suffix is reconfigured (Debian moves the old database to /var/backups). Opt-in, in no group (v83) |
| `install-lan` | Using the other laptops: the address book LAN\_HOSTS from secrets.env goes into /etc/hosts (this machine's own name maps to 127.0.0.1), so every tool takes the laptop names, plus the lan command (status, hosts, ip, scan, url, ollama, mcp, site, share; 'lan help'). Since v93 also Tailscale, installed in normal mode (tailscale0; dev-init joins the laptop), NAME.internal beside each name in /etc/hosts, and 'lan probe' / 'lan path'. Opt-in, in no group (v84) |
| `install-lan-share` | Serving the other laptops; includes install-lan. LAN\_SHARE picks what is shared (ollama mssql oracle ldap ddev dev mcp, and since v89 redis solr opensearch elasticsearch meilisearch typesense qdrant mongodb; empty = nothing; redis, qdrant and mongodb only with their login set, Memcached, Milvus, Atlas Local and (v91) the Selenium Grid never). A relay, dev-lan-relay.service, listens on this Linux's network address and passes connections to 127.0.0.1, so no service changes and 'lan share off' closes every port at once. Network ports: Ollama 11434, SQL Server 1433, Oracle 1521, lldap 3890 and 17170, OpenLDAP 1389, DDEV 8080 and 8443. Dev and MCP servers listen on the network themselves (--host, host="0.0.0.0"). Since v93, over Tailscale: 'tailscale serve' publishes the LAN\_SHARE ports to your tailnet only, and the relay stays off; LAN\_TAILSCALE=0 keeps the relay, where each port needs a ChromeOS port forward ('lan share ports'). Opt-in, in no group (v84) |
| `install-cache` | The caches, install-redis and install-memcached, as shared Docker containers run by the devsvc command (status, up, down, info, cli, password, logs, ddev, fits; 'devsvc help'). Every devsvc service listens on 127.0.0.1 only, joins DDEV's network under its DDEV name while it runs, and is checked against a memory budget (DEVSVC\_RAM\_MB) before it starts. In install-all (v89) |
| `install-redis` | Redis 8 (search, JSON, time series and Bloom built in) in Docker: container devsvc-redis on 127.0.0.1:6379, DDEV name devredis, data in the volume devsvc-redis-data, maxmemory 256mb. Starts with Linux (DEVSVC\_AUTOSTART); REDIS\_PASSWORD sets a login. Plus redis-tools (redis-cli) and Redis Insight (REDIS\_INSIGHT=0 skips it). Part of install-cache (v89) |
| `install-memcached` | Memcached 1.6 in Docker on 127.0.0.1:11211, DDEV name devmemcached, 64 MB, no login and no volume. Starts with Linux. Part of install-cache (v89) |
| `install-search` | The search engines: install-solr, install-opensearch, install-meilisearch and install-typesense, created stopped ('devsvc up NAME' starts one). The heavy engines (Solr, OpenSearch, Elasticsearch, Milvus, Atlas Local; since v91 the Selenium Grid) run one at a time and stop SQL Server or Oracle when they start. Logins are generated on the first run and kept ('devsvc password NAME'). In install-all (v89) |
| `install-solr`, `install-opensearch`, `install-meilisearch`, `install-typesense` | Solr 9.10 in SolrCloud mode on 127.0.0.1:8983 (devsolr, user solr, 512 MB heap); OpenSearch 3 on 127.0.0.1:9200 (devopensearch, user admin, 512 MB heap, plain HTTP); Meilisearch v1 on 127.0.0.1:7700 (devmeili, master key); Typesense 30 on 127.0.0.1:8108 (devtypesense, API key). Part of install-search (v89) |
| `install-elasticsearch` | Elasticsearch 9 on 127.0.0.1:9201 (9200 is OpenSearch's), DDEV name develastic, user elastic, plain HTTP, machine learning off; a heavy engine. Opt-in, in no group (v89) |
| `install-vector` | install-qdrant plus sqlite-vec, the vector extension for Debian's sqlite3 and Python, in \~/.local/lib/sqlite-vec (SQLITE\_VEC in \~/.bashrc). In install-all (v89) |
| `install-qdrant` | Qdrant v1 on 127.0.0.1:6333 (REST) and 6334 (gRPC), DDEV name devqdrant, telemetry off; QDRANT\_API\_KEY sets a login. Part of install-vector (v89) |
| `install-milvus` | Milvus v3 standalone (embedded etcd, local storage) on 127.0.0.1:19530 with its WebUI on 9091, DDEV name devmilvus, no login; a heavy engine. Opt-in, in no group (v89) |
| `install-mongodb` | MongoDB 8 on 127.0.0.1:27017, DDEV name devmongo, WiredTiger cache 0.5 GB; MONGO\_ROOT\_PASSWORD turns on auth. Plus mongosh, the Database Tools (mongoimport, mongoexport, mongodump) and Compass (MONGODB\_COMPASS=0 skips it); install-web adds php-mongodb. In install-all (v89) |
| `install-mongodb-atlas-local` | MongoDB Atlas Local (Atlas Search and Vector Search; about 2.5 GB of RAM) on 127.0.0.1:27018, DDEV name devmongo-atlas, plus the Atlas CLI; a heavy engine. Pulls in install-mongodb. Opt-in, in no group (v89) |
| `install-lakehouse` | DuckDB CLI with the Iceberg, DuckLake and Delta Lake extensions; delta-rs (deltalake); dbt Fusion, dbt Core |
| `install-agentic` | Temporal, LangGraph, Langfuse compose; FastMCP's CLI and the MCP Inspector (v89) |
| `install-cloud` | aws, azure, gcp CLIs (v57), vercel CLI (v67), Cloudflare's wrangler (v89) |
| `install-vercel` | Vercel CLI with telemetry off; pulls in install-node (v67, part of install-cloud) |
| `install-cloudflare` | Cloudflare's wrangler (Workers, D1, KV, R2, Pages) as a global npm package, telemetry off; 'wrangler dev' needs no account. Pulls in install-node (v89, part of install-cloud) |
| `install-cloudflared` | cloudflared from Cloudflare's apt repository, for tunnels; setup creates none. Opt-in, in no group (v89) |
| `install-graphql` | Apollo's GraphQL tools as three binaries in \~/.local/bin from their GitHub releases (checksum-checked where the release has one): Rover, the Apollo Router (v2 only) and the Apollo MCP Server, plus Rover's composition and router plugins in \~/.rover. A \~/.bashrc block turns Apollo telemetry off and accepts the plugins' Elastic License v2. Local federation needs no account; APOLLO\_KEY is never exported. In install-all, no dependencies (v90) |
| `install-testing` | The test tools: install-playwright, install-selenium, install-bdd and install-robot. Test libraries (@playwright/test, cucumber-js, Behat, behave, Reqnroll's packages) stay per project. In install-all (v91) |
| `install-playwright` | Playwright's Chromium, Firefox and WebKit in \~/.cache/ms-playwright with their system libraries (playwright install --with-deps), and Playwright MCP warmed in npx's cache. Pulls in install-node. Part of install-testing (v91) |
| `install-selenium` | A Selenium Grid (selenium/standalone-chrome) as the devsvc service selenium: WebDriver on 127.0.0.1:4444, noVNC on 127.0.0.1:7900 to watch it, DDEV name devselenium, created stopped, a heavy engine (\~1.6 GB), no login and never LAN-shared. Plus Selenium Manager's chromedriver for the installed Chrome in \~/.cache/selenium (no chromedriver on PATH) and SE\_AVOID\_STATS in \~/.bashrc. Part of install-testing (v91) |
| `install-bdd` | The Gherkin runners' machine-level part: Reqnroll's dotnet new templates (SpecFlow's successor) when .NET is installed. Cucumber, Behat (4.x for Symfony 8, 3.x with Drupal's Drupal Extension) and behave are per project. No dependencies. Part of install-testing (v91) |
| `install-robot` | Robot Framework as a uv tool on Debian's Python with the Browser (Playwright), SeleniumLibrary and RequestsLibrary libraries; robot, rebot, libdoc and rfbrowser in \~/.local/bin; the Browser library's Node side without browsers (it uses the system Chrome). Pulls in install-node. Part of install-testing (v91) |
| `install-cypress` | Cypress's system libraries (Debian 13's t64 names, Xvfb) and a \~/.bashrc block turning crash reports off; Cypress itself is per project (npm 12 needs "allowScripts": {"cypress": true}). Pulls in install-node. Opt-in, in no group (v91) |
| `install-gitlab` | glab, GitLab's CLI, from Homebrew (like gh; Debian's own glab is years behind) with bash completion, and gitlab-ci-local (npm) to run a project's .gitlab-ci.yml here, jobs with an image in Docker; plus rsync and git. Logins come from init. Pulls in install-node. In install-all (v91) |
| `install-gitlab-runner` | GitLab Runner from GitLab's apt repository as the gitlab-runner service, its user in the docker group for the Docker executor; left unregistered until init registers it with GITLAB\_RUNNER\_TOKEN\_ONCE. Pulls in install-gitlab. Opt-in, in no group (v91) |
| `install-vue` | Vue.js scaffolding warmed for offline use: create-vue and create-nuxt in npx's cache and Nuxt's minimal template in \~/.cache/giget. Nothing global: Vue, Pinia, Vue Router and Nuxt stay per project. Pulls in install-node. In install-all (v91) |
| `install-puppet` | OpenVox, Vox Pupuli's free fork of Puppet: openvox-agent (puppet, facter) and OpenBolt (bolt) from apt.voxpupuli.org, in /opt/puppetlabs/bin at the end of PATH. OpenVox 8; OPENVOX\_MAJOR=9 picks the next line. Masterless: the agent service is disabled. Opt-in, in no group, not in install-all (v91) |
| `install-chef` | Cinc Workstation, the free build of Chef Workstation (cinc-client, knife, Test Kitchen with Dokken, Cookstyle, ChefSpec, Berkshelf, cinc-auditor), its .deb checked against Cinc's SHA-256, in /opt/cinc-workstation/bin at the end of PATH. No license key. Opt-in, in no group, not in install-all (v91) |
| `install-config-mgmt` | Group: install-puppet + install-chef. Ansible stays in install-iac. Opt-in, not in install-all (v91) |
| `install-jev` | Jev (TypeSafe AI) readiness: TypeSafe's agent skill for Claude Code, key slots in secrets.env, SDK and live-call tests. Nothing else is installed: the model is hosted and its SDKs are per project (v67, part of install-all) |
| `install-iac` | Terraform, tflint, Bicep when azure is present (v57); Ansible, full package via install-ansible-full (v76) |
| `install-ansible-full` | Ansible in one pipx venv named ansible-core on Debian's Python: ansible-core, the ansible community package (about 90 collections, ansible-community), ansible-lint, Molecule and the Docker SDK; about 520 MB (v76, part of install-iac) |
| `install-ansible-core` | The lean Ansible: the same venv without the community package, plus community.docker from Galaxy; about 85 MB. Standalone, in no group; when full is also asked for or already installed, full is kept (v76) |
| `install-web` | Angular CLI, corepack (pnpm/yarn shims), Composer; pulls in node automatically (v58); php-redis, php-memcached and php-mongodb (v89) |
| `install-tanstack` | TanStack CLI (@tanstack/cli) and corepack for pnpm; pulls in install-node (v65, part of install-all) |
| `install-drupal` | Terminus (Pantheon), acli (Acquia) and the Upsun CLI, the Terminus rsync plugin, bash completion, rsync and a MariaDB client, DDEV telemetry off; pulls in install-web (v68, part of install-all) |
| `install-laravel` | Laravel 13: the Laravel installer (laravel new) as a global Composer package, with Composer's global bin added to PATH, and php-bcmath. Pulls in install-web (Composer and the PHP extensions Laravel needs) and install-node (Vite). Pest, Pint, Sail and Boost stay per project; DDEV's laravel project type works as is. In install-all (v87) |
| `install-symfony` | Symfony 8: the Symfony CLI (symfony new, symfony serve, check:requirements, check:security) as the .deb from its GitHub releases, checked against the release's checksums, with no extra apt source. Pulls in install-web (Composer and the PHP extensions Symfony needs; PHP 8.4 is trixie's own). Doctrine, MakerBundle and PHPUnit stay per project; DDEV's symfony project type works as is. In install-all (v88) |
| `install-k8s` | kubectl, helm, kind, k9s (v58) |
| `install-cpp` | gdb, valgrind, cmake, ninja, pkg-config, clang/clangd/clang-format/clang-tidy, lldb, ccache, meson; gcc and g++ are already in base (v63, part of install-languages) |
| `install-asm` | nasm, yasm; GNU as and ld are already in base (v63, part of install-languages) |
| `install-dotnet` | .NET 10 SDK from Microsoft's Debian feed: C# and VB.NET (v63, part of install-languages) |
| `install-java` | default-jdk (21 on trixie, the same JDK the Android stacks use) and JAVA\_HOME, Maven from apt, Gradle from Homebrew (v63, part of install-languages) |
| `install-asm-arm` | AArch64 cross toolchain and qemu-user; opt-in only, not part of install-all (v63) |
| `install-com` | COM / DCOM / ActiveX development under Wine: wine (64 + 32-bit, i386 multiarch), mingw-w64 with widl, libwine-dev (the system .idl files) and stdole2.tlb, winetricks. A WoW64 Wine prefix at \~/.local/share/wine/com (the wine-com wrapper runs programs in it) and DEV\_COM\_\* in \~/.bashrc. Build a server with widl + mingw, register it with regsvr32, create it with CoCreateInstance, in-process or out-of-process. ATL/MFC (MSVC only) and a cross-machine DCOM server (that side belongs on a Windows laptop) are not covered. Opt-in, in no group (v85) |
| `install-retro` | DOS and old Windows: Open Watcom v2 in /opt/watcom (wcl for 16-bit DOS, wcl386 for DOS/4GW 32-bit and, with -bt=nt, Win32; -bt=windows for Win16), and five guests from your own media, each with a command and a launcher icon: win31 (Windows 3.1x) and win95 (Windows 95, FAT32 on OSR2) on DOSBox-X, winnt40 (NT 4.0) and win2000 on QEMU (KVM where /dev/kvm exists; setup adds you to the group that owns it), delphi1 (Delphi 1 alone, in its own 32-bit Wine prefix). Media goes in \~/\<guest>/install (Delphi 1: \~/win31/install/apps); '\<cmd> setup' creates the guest's disk after a free-space check. 'retro run FILE' runs one program on the engine its header calls for. Adds qemu-system-x86, qemu-system-gui, qemu-utils, mtools, dosfstools and (v93) libarchive-tools. Pulls in install-com. Opt-in, in no group (v85; QEMU, win95, winnt40, win2000, delphi1 and retro since v92; program CDs as F:, the disk-size settings, win95 snapshots and the delphi command for Delphi 3, 4, 5, 6 and 7 since v93) |
| `install-hermes` | Hermes Agent (Nous Research), a personal agent with memory, skills and a messaging gateway: its own installer from GitHub, code in \~/.hermes/hermes-agent, the hermes command in \~/.local/bin, data in \~/.hermes. No setup wizard, gateway service, desktop-control driver or browser tools (HERMES\_BROWSER=1 adds the browser). It keeps to its own logins, so it never borrows Claude Code's. Needs a model with a 64K-token context: init sets one from secrets.env. Opt-in, in no group (v86) |
| `install-openclaw` | OpenClaw, a personal agent with a gateway and Control UI: the npm package openclaw (about 900 MB) on nvm's Node 24.16+ or 26.1+, so it pulls in install-node. No gateway service; the gateway stays on loopback with a token; anonymous feature statistics recorded off (the daily update check stays on). No ClawHub skills. OpenClaw runs shell commands without asking by default; init sets tools.exec.mode=ask. Needs a model with a 64K-token context: init sets one from secrets.env. Opt-in, in no group (v86) |

### Have in the assets folder (optional fallbacks)

- `Cursor*.AppImage` — used if the cursor.com download endpoint fails. Since v67 setup looks in assets first, then the current directory.
- `*antigravity*.tar.gz` — the Linux x64 tarball of Antigravity IDE, the Antigravity 2.0 desktop app, or both, from antigravity.google/download. Google publishes no stable download link for these, so they stay a manual download; the CLI and SDK install regardless. Since v73 setup installs each tarball it finds under /opt (antigravity-ide or antigravity), links the command into \~/.local/bin, sets up the Chromium sandbox helper and adds a ChromeOS launcher entry. Leave the file in assets: rerunning with the same tarball changes nothing, and a newer one replaces the install. Looked for in assets first, then the current directory.
- `*InterBase*.zip` (or the ib\_install\_linux\_x86\_64.bin inside it) and any license slip file — only for install-interbase or install-db-server. The free Developer Edition is a registered download from Embarcadero, so it cannot be fetched unattended; keep the serial number from the download email for init. Without it, install-db-server still sets up SQL Server and Oracle, and the test reports InterBase as a single WARN rather than failures. Since v80.
- Nothing else: Lazarus, Android Studio, the Android SDK and Godot download themselves.

### No setup-time prompts

Through v67, `install-gemma` stopped at an interactive `hf auth login` unless `HF_TOKEN` was already in the environment, even with the token sitting in `secrets.env`, because setup never read that file. Since v68 setup takes `HF_TOKEN` from the environment or from `secrets.env`, and with no token it skips the login and leaves it to init. Setup reads nothing else from the secrets file; every other login belongs to init.

### After it finishes

- `source ~/.bashrc` and `newgrp docker`, or open a new terminal.
- Shut Linux down once (right-click the Terminal icon, Shut down Linux) and reopen it, so the docker, video and render groups take effect; without the render group every graphical app renders in software. Then run init with the same flags to apply secrets.env, then the test script. Tested before init, every login shows as a WARN and the test says init is pending.

Since v93 setup checks the network first: if IPv6 doesn't get out (the Oct 4 hang on Chrome's download), it makes Linux prefer IPv4 with the same two lines that fixed it by hand (`/etc/gai.conf` and `/etc/apt/apt.conf.d/99force-ipv4`; `DEV_PREFER_IPV4=0` skips the check). Every download gets a 20-second connection timeout, and a bad Go or PowerShell download now skips just that tool; the summary at the end names it and the flag to rerun.

The test script ends with a disk report (v77): the measured size of every installed stack, then totals for apt, Homebrew (with its eight biggest formulae), Docker data, caches, `~/dev-demo`, the home directory and the Linux disk. It prints them as INFO lines and saves a copy to `assets/logs/disk-<timestamp>.tsv`, labelled with `MACHINE_LABEL` from `secrets.env` so reports from different Chromebooks can be compared. The totals overlap the per-stack lines on purpose, because apt and Homebrew each hold several stacks. Add `nodisk` to skip it; it takes a minute or two.

## The secrets file

All keys live in `~/.config/dev-init/secrets.env` (mode 600, sourced by `~/.bashrc`); the script itself never contains a key. Empty values are skipped, `export`ed values reach every new shell, and `*_ONCE` values are consumed by init for a one-time login and never exported. Keep this file out of every repo.

| Variable | Used by | Required? | Where it comes from |
| --- | --- | --- | --- |
| `GIT_NAME`, `GIT_EMAIL` | base | Yes | You |
| `GH_TOKEN_ONCE` | base (`gh`, SSH key upload) | Yes, or interactive login | GitHub |
| `GEMINI_API_KEY` | install-node (Gemini CLI, aider), install-gemma, install-agentic | Yes | Google AI Studio |
| `HF_TOKEN` | install-gemma (Transformers path) | Yes for gated weights | Hugging Face |
| `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_BASE_URL` | install-agentic | Yes | Langfuse Cloud |
| `ANTHROPIC_API_KEY` | install-node, install-agentic | Optional | Anthropic Console |
| `OPENAI_API_KEY` | install-node (Codex, aider) | Optional | OpenAI Platform |
| `EXPO_TOKEN` | install-rn (via install-mobile) | Optional | Expo |
| `AWS_DEFAULT_REGION` | install-aws | Preset to `us-east-1` | You |
| `AWS_PROFILE` | install-aws | Uncomment after `aws configure sso` | Profile name you chose |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | install-aws | Fallback only | IAM console |
| `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` | install-azure | Optional (service principal) | Azure portal, Entra ID |
| `AZURE_SUBSCRIPTION_ONCE` | install-azure | Optional | Subscription name or id |
| `GOOGLE_APPLICATION_CREDENTIALS` | install-gcp | Optional (headless only) | Service-account JSON key path |
| `GCP_PROJECT_ONCE` | install-gcp | Optional | Project id |
| `VERCEL_TOKEN` | install-vercel | Optional, commented out | vercel.com/account/tokens. Overrides a saved vercel login in every shell, so leave it commented unless you want that |
| `TYPESAFE_API_KEY` | install-jev | One of the two Jev keys | console.typesafe.ai, Settings, Keys (early access is waitlisted) |
| `AI_GATEWAY_API_KEY` | install-jev | One of the two Jev keys | Vercel dashboard, AI Gateway tab. Reaches Jev as model typesafe-ai/jev through the AI SDK |
| `MACHINE_LABEL` | base, install-drupal | Optional, recommended | You: a short name for this Chromebook. Labels the SSH key uploaded to GitHub, Pantheon and Acquia, since every Linux container is otherwise called penguin |
| `TERMINUS_MACHINE_TOKEN_ONCE` | install-drupal | Optional; needed for Pantheon, which has no browser login | Pantheon dashboard, Account, Machine tokens |
| `ACQUIA_API_KEY_ONCE`, `ACQUIA_API_SECRET_ONCE` | install-drupal | Optional; needed for Acquia | cloud.acquia.com, profile menu, Account settings, API Tokens |
| `UPSUN_CLI_TOKEN` | install-drupal | Optional, commented out | console.upsun.com, My profile, API tokens. Only if you have projects on Upsun |
| `ANSIBLE_VAULT_PASSWORD_FILE` | install-ansible-full, install-ansible-core | Optional, commented out | You: path to a one-line vault password file (mode 600). Uncomment only once the file exists: Ansible refuses to run at all when it is missing |
| `OLLAMA_REMOTE` | install-ollama (the ollama-remote command, dev-demo's compare remote) | Optional, commented out | You: another machine's Ollama, e.g. http://192.168.1.50:11434, or with install-lan a laptop name such as winlaptop (port 11434 is assumed). A Chromebook serves it with LAN\_SHARE=ollama (since v93 over Tailscale: use NAME.internal or its 100.x address, since Ollama answers a plain laptop name with 403); a Windows laptop needs OLLAMA\_HOST=0.0.0.0:11434 and a firewall rule. Plain ollama stays local |
| `OLLAMA_API_KEY` | install-ollama (direct calls to ollama.com's API) | Optional, commented out | ollama.com/settings/keys. The local CLI does not need it: :cloud models go through 'ollama signin' |
| `DEEPSEEK_API_KEY` | install-ollama (aider, langchain-deepseek) | Optional, commented out | platform.deepseek.com, API keys. Init checks it against api.deepseek.com |
| `INTERBASE_SYSDBA_PASSWORD` | install-interbase (test, demo) | Optional, commented out | You: set it only after changing SYSDBA's password from the default masterkey (init prints the gsec command). The serial number is never stored here |
| `MSSQL_SA_PASSWORD`, `ORACLE_PWD` | install-mssql, install-oracle (the mssql and oracle commands, test, demo) | Optional, commented out | You, only to pick your own before the first setup run with the flag; otherwise setup generates one and 'mssql password' / 'oracle password' print it. Letters, digits and \_ are safe for both. Update it here if you change it inside the database: init reports a skip when the two differ |
| `LDAP_BASE_DN, LLDAP_ADMIN_PASSWORD, OPENLDAP_ADMIN_PASSWORD, LDAP_BIND_PASSWORD, LDAP_SAMPLE_PASSWORD` | install-ldap, install-ldap-full (setup only; not exported) | Optional, commented out | You, only to pick your own before the first setup run with the flag; otherwise setup generates them. Either way they are kept in \~/.config/devldap/ldap.env (mode 600), which wins from then on and which the ldap command, test and demo read; 'ldap passwords' prints them. Init reports a skip when secrets.env and ldap.env differ |
| `LAN_HOSTS, LAN_SELF, LAN_SHARE, LAN_DEV_PORTS, LAN_MCP_PORTS, LAN_EXTRA` | install-lan, install-lan-share (the lan command, init, test, demo; not exported) | Optional | You. LAN\_HOSTS: every laptop as name=address, the same list on each (reserve each address on the router first). LAN\_SELF: this machine's name in it, when not MACHINE\_LABEL. LAN\_SHARE: what this machine serves. The last three stay commented unless you change the dev-server (3000 4200 5173) or MCP (8000) ports or add more relayed ports |
| `AGENT_PROVIDER, AGENT_MODEL, AGENT_ANTHROPIC_API_KEY, OPENROUTER_API_KEY` | install-hermes, install-openclaw (init) | Optional | You. AGENT\_PROVIDER: auto (the first of AGENT\_ANTHROPIC\_API\_KEY or ANTHROPIC\_API\_KEY, OPENROUTER\_API\_KEY, OLLAMA\_REMOTE with AGENT\_MODEL), anthropic, openrouter, ollama-remote or skip. AGENT\_MODEL: empty means Sonnet (claude-sonnet-5-5; anthropic/claude-sonnet-5.5 on OpenRouter); required for a remote Ollama, which must serve a 64K context (OLLAMA\_CONTEXT\_LENGTH=65536 there). AGENT\_ANTHROPIC\_API\_KEY: an Anthropic key for the agents only, not exported, so Claude Code keeps using your subscription. OPENROUTER\_API\_KEY stays commented until used |
| `DEVSVC_AUTOSTART, DEVSVC_RAM_MB` | the shared services (setup, the devsvc command; not exported) | Optional, commented out | You. DEVSVC\_AUTOSTART: the services that start with Linux (default "redis memcached", "none" for none); the rest start on 'devsvc up'. DEVSVC\_RAM\_MB: the memory budget 'devsvc up' checks first (default 3000); DEVSVC\_FORCE=1 on one command overrides it |
| `REDIS_PASSWORD, QDRANT_API_KEY, MONGO_ROOT_PASSWORD` | install-redis, install-qdrant, install-mongodb (setup, devsvc, lan, test, demo; not exported) | Optional, commented out; needed to share that service with install-lan-share | You. Empty means no login, which is fine on 127.0.0.1. Setup applies a change on every run (MongoDB's is written into the existing data); init reports a skip until it has |
| `SOLR_PASSWORD, OPENSEARCH_ADMIN_PASSWORD, ELASTIC_PASSWORD, MEILI_MASTER_KEY, TYPESENSE_API_KEY` | install-search, install-elasticsearch (setup only; not exported) | Optional, commented out | You, only to pick your own before the first setup run with the flag; otherwise setup generates them. Either way they are kept in \~/.config/devsvc/devsvc.env (mode 600), which wins from then on, since the engines store them; 'devsvc password NAME' prints one. Init reports a skip when secrets.env and devsvc.env differ |
| `MONGODB_ATLAS_PUBLIC_API_KEY, MONGODB_ATLAS_PRIVATE_API_KEY` | install-mongodb-atlas-local (the Atlas CLI) | Optional, commented out | cloud.mongodb.com, Organization Access Manager, API Keys. Only for hosted Atlas; Atlas Local needs no account. 'atlas auth login' in a browser works instead |
| `CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID` | install-cloudflare (wrangler, dev-demo's cloud/cloudflare deploy) | Optional, commented out | dash.cloudflare.com, My Profile, API Tokens, template 'Edit Cloudflare Workers'; the account id is on the dashboard's Workers page. Or 'wrangler login' in a browser instead. 'wrangler dev' needs neither |
| `APOLLO_KEY, APOLLO_GRAPH_REF` | install-graphql (init writes the key into Rover's profile; dev-demo's drupal-graphql connectors item; not exported) | Optional, commented out | GraphOS Studio: your user settings, API keys (or a graph API key); the graph ref is graph-id@variant. Never export APOLLO\_KEY: exported, every local router and MCP server reports to GraphOS, where the Free plan allows self-hosted routers 60 requests a minute |
| `CYPRESS_RECORD_KEY` | install-cypress (only 'cypress run --record' uses it; exported) | Optional, commented out | Cypress Cloud: the project's settings, Record Keys; the projectId goes in the project's cypress.config. Local Cypress runs need no account (v91) |
| `GITLAB_TOKEN_ONCE, DRUPALCODE_TOKEN_ONCE` | install-gitlab (init logs glab in to gitlab.com and git.drupalcode.org and uploads the SSH key to gitlab.com; not exported) | Optional, commented out | gitlab.com: Preferences > Access tokens, scopes api and write\_repository. git.drupalcode.org: a personal access token from your preferences there, if your account can create one; drupal.org's git SSH keys stay on your drupal.org profile (v91) |
| `GITLAB_RUNNER_TOKEN_ONCE` | install-gitlab-runner (init registers the runner once, Docker executor, named after MACHINE\_LABEL) | Optional, commented out | A glrt- runner authentication token: a project's (or group's) Settings > CI/CD > Runners > New runner (v91) |
| `GITLAB_MCP` | install-gitlab ("1": init adds GitLab's MCP server to Claude Code at user scope) | Optional, commented out | No key: the server's first use opens GitLab's OAuth login. It is in beta and on the Free tier; the top-level group must allow MCP access (v91) |
| `KNIFE_CHEF_SERVER_URL` | install-chef (an existing Chef or Cinc server, with the organization: https://chef.example.com/organizations/myorg) | Optional, commented out | Only for a server you already use; local mode, Test Kitchen and InSpec need nothing (v91) |
| `KNIFE_NODE_NAME` | install-chef (your user name on that server) | Optional, commented out | Your user (client) name on the server (v91) |
| `KNIFE_CLIENT_KEY` | install-chef (the path to your user's .pem key) | Optional, commented out | Downloaded from the server when the user or key was made. With all three set, init writes knife's default profile once (v91) |
| LAN\_TAILSCALE | install-lan, install-lan-share (v93) | Optional, commented out | You: 0 keeps the v84 relay and ChromeOS port forwards and installs no Tailscale; default 1 |
| TAILSCALE\_AUTHKEY | install-lan (init joins the tailnet with it, v93) | Optional, commented out | You: an auth key from the Tailscale admin console (Settings > Keys), to join without a browser; not needed once joined |
| RETRO\_EXCHANGE\_MB | install-retro (read when an exchange disk is made, v93) | Optional, commented out | You: 64-2047, default 1024; 512 for less disk. The same name on the command line wins for one run |
| RETRO\_WIN95\_DISK\_MB | install-retro (read when win95's hdd.img is made, v93) | Optional, commented out | You: 512-8192, default 2048 |

Init derives `GOOGLE_API_KEY` from `GEMINI_API_KEY`, so one Google key serves both `gemma_client.py` and `langchain-google-genai`. `LANGFUSE_BASE_URL` stays at `https://cloud.langfuse.com` unless you self-host on a 16 GB+ machine.

The cloud key lines (v57) ship commented out and must stay that way until you set a value. botocore treats an exported empty `AWS_PROFILE` as a profile named `""` and fails, and google-auth errors on an empty `GOOGLE_APPLICATION_CREDENTIALS`. Uncomment only the lines you fill in.

## Running init with an empty secrets file

With no secrets filled in and no `noninteractive` flag, init walks through every login that has a CLI flow, so you can authenticate live when it reaches each one. In order:

1. `gh auth login` — GitHub, browser.
2. `codex login` — browser link.
3. `hf auth login` — paste a Hugging Face token at the prompt.
4. `eas login` — Expo.
5. `aws configure sso` — start URL and region, then browser.
6. `az login --use-device-code` — code entered on any device.
7. `gcloud auth login`, then `gcloud auth application-default login` — browser, twice.
8. `vercel login` — browser (v67).

Two kinds of item cannot be prompted for and land in the todo list at the end instead:

- API keys with no login command: `GEMINI_API_KEY`, the Langfuse pair, the Pantheon and Acquia tokens, the Jev keys (`TYPESAFE_API_KEY` or `AI_GATEWAY_API_KEY`), and `GIT_NAME` / `GIT_EMAIL`. These only ever come from `secrets.env`.
- Claude Code: init never calls `claude`; run it once yourself, since that login is a full terminal session.

The practical minimum to type into `secrets.env` is therefore name, email, the Gemini key and the two Langfuse keys; everything else can be done at the prompt.

## Credentials by service

The minimum trip for `install-all` is GitHub, Google AI Studio, Hugging Face and Langfuse; Anthropic, OpenAI, Expo, the three cloud CLIs and Vercel each have an interactive fallback.

### GitHub (base)

1. [github.com](https://github.com) → profile menu → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token.
2. Scopes: `repo`, `read:org`, `admin:public_key`. The last one lets init upload (since v92 init first asks GitHub itself with ssh -T, on port 22 and then on ssh.github.com port 443, so a key you added in the web UI counts as done, and a token without the scope gets 'gh auth refresh -h github.com -s admin:public\_key' as its todo) `~/.ssh/id_ed25519.pub` to your account.
3. Pick an expiry, copy the token once, paste into `GH_TOKEN_ONCE`.
4. Alternative: leave it empty and answer the interactive `gh auth login` in the browser.

### Google AI Studio (install-gemma, install-agentic)

1. [aistudio.google.com/apikey](https://aistudio.google.com/apikey) → Create API key.
2. Pick or create a Google Cloud project when asked; the default project is fine.
3. Paste into `GEMINI_API_KEY`.

### Hugging Face (install-gemma)

1. [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) → Create new token → type *Read* → copy.
2. Open the Gemma 4 model page (search `google/gemma-4`) and click *Agree and access repository* on the gated-model banner. The token alone does not unlock gated weights; without this step the Transformers path returns 403.
3. Paste into `HF_TOKEN`. Ollama needs none of this.

### Langfuse (install-agentic)

1. [cloud.langfuse.com](https://cloud.langfuse.com) → sign up (GitHub login is quickest) → New organization → New project. The free Hobby tier is enough.
2. Project → Settings → API Keys → Create new API key. Copy both `pk-lf-…` and `sk-lf-…` now; the secret is shown once.
3. Paste into `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY`; leave `LANGFUSE_BASE_URL` as is.

### Anthropic (install-node, install-agentic) — optional

- Leave `ANTHROPIC_API_KEY` empty to use the Claude subscription in Claude Code; run `claude` once after init and finish the browser login.
- Set it only for API billing or `langchain-anthropic`: [console.anthropic.com](https://console.anthropic.com) → API Keys → Create Key.

### OpenAI (install-node) — optional

- Leave `OPENAI_API_KEY` empty and run `codex login` for the ChatGPT-account flow.
- Or create a key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys).

### Gemini CLI and aider (install-node)

- Gemini CLI: run `gemini` once and sign in with a Google account (credentials land in `~/.gemini`), or let it use the `GEMINI_API_KEY` above. Init reports whichever it finds.
- aider has no login of its own: it uses `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` or `GEMINI_API_KEY`, whichever is set. With none, run it against local Ollama: `aider --model ollama_chat/gemma4:e2b-it-qat`.

### Expo / EAS (install-rn via install-mobile) — optional

- [expo.dev](https://expo.dev) → sign in → Account settings → Access tokens → Create token → paste into `EXPO_TOKEN`.
- Or leave it empty and `eas login` prompts.

### AWS (install-aws)

1. Preferred path is IAM Identity Center, with no keys to copy. Have your Identity Center start URL and region ready (from your AWS access portal).
2. Init runs `aws configure sso`, which asks for those two values and opens a browser.
3. Afterwards put the profile name you chose in `AWS_PROFILE` and uncomment it, so every shell and boto3 use it. Expired SSO sessions are refreshed by rerunning init.
4. Static keys are a fallback only: IAM console → Users → Security credentials → Create access key → paste into the two `AWS_ACCESS_*` lines and uncomment them.

### Azure (install-azure)

1. Interactive: init runs `az login --use-device-code`; open the URL it prints on any device and enter the code.
2. Set `AZURE_SUBSCRIPTION_ONCE` to a subscription name or id to make it the default.
3. Service principal, for headless use only: Azure portal → Microsoft Entra ID → App registrations → New registration → Certificates & secrets → New client secret. Copy the tenant id, the application (client) id and the secret value into the three `AZURE_*` lines and uncomment them.

### Google Cloud (install-gcp)

1. Interactive: init runs `gcloud auth login` and then `gcloud auth application-default login`; both open a browser. The second one is what the google-cloud-\* SDKs and Terraform's google provider use.
2. Set `GCP_PROJECT_ONCE` to the project id shown on the Cloud Console dashboard.
3. Service-account key, for headless use only: Console → IAM & Admin → Service Accounts → Keys → Add key → JSON. Save it under `~/.config` and set `GOOGLE_APPLICATION_CREDENTIALS` to the path, uncommented.

### Vercel (install-vercel)

1. Interactive: init runs `vercel login`, which opens a browser. That is all most machines need.
2. Token, for unattended use only: vercel.com/account/tokens → Create. Uncomment `VERCEL_TOKEN` and paste it. An exported token overrides the saved login in every shell, so leave the line commented otherwise.

### Jev / TypeSafe AI (install-jev)

One key is enough; the two routes reach the same model.

1. Direct: console.typesafe.ai → Settings → Keys → paste into `TYPESAFE_API_KEY`. Early access is waitlisted, so this may take a while to open up.
2. Through Vercel: dashboard → AI Gateway → API keys → create → paste into `AI_GATEWAY_API_KEY`. Available as soon as you have a Vercel account, and the same key reaches every other model behind the gateway.
3. Rerun init, then the test script with install-jev: it makes a live call on each route that has a key.

### Pantheon, Acquia, Upsun (install-drupal)

All three platforms are optional. Setup installs the CLIs without any credential, and init reports an unconfigured platform as a skip rather than a todo, so nothing here blocks a clean install; add a token whenever you are ready and rerun init. These tokens reach every site your account can, client production included. Name each one after the machine (the same name as `MACHINE_LABEL`) so one Chromebook's access can be revoked alone.

1. Pantheon: dashboard.pantheon.io → Account → Machine tokens → Create token → paste into `TERMINUS_MACHINE_TOKEN_ONCE`. Terminus has no browser login, so this is the only route.
2. Acquia: cloud.acquia.com → profile menu → Account settings → API Tokens → Create token → paste the key and the secret into `ACQUIA_API_KEY_ONCE` and `ACQUIA_API_SECRET_ONCE`. The secret is shown once.
3. Upsun, only if you have projects there: console.upsun.com → My profile → API tokens → uncomment `UPSUN_CLI_TOKEN` and paste. Or skip the token and run `upsun login`.
4. Run init with install-drupal. It logs Terminus and acli in, uploads `~/.ssh/id_ed25519.pub` to Pantheon and Acquia (git and remote Drush use SSH on both), and copies the working tokens into DDEV's global config so `ddev pull pantheon` and `ddev pull acquia` can authenticate. That file is then set to mode 600, since DDEV writes it world-readable.

### Local and cloud models (install-ollama, v77)

All optional; init reports each as a skip until you set it.

1. Another machine's Ollama: on that machine set `OLLAMA_HOST=0.0.0.0:11434`, allow port 11434 on its private network, then put its address with the port in `OLLAMA_REMOTE`. Init checks that it answers; `ollama-remote list` uses it.
2. Cloud models through the local CLI (for example `deepseek-v4.1-flash:cloud`, billed per token): run `ollama signin` once. It prints a link to open in the browser, so init cannot do it for you.
3. Direct calls to ollama.com's API: a key from ollama.com/settings/keys in `OLLAMA_API_KEY`.
4. DeepSeek's own API: a key from platform.deepseek.com in `DEEPSEEK_API_KEY`.

### InterBase (install-interbase)

The Developer Edition server refuses to start until it is registered. Init does it when port 3050 is not answering.

1. Download InterBase for Linux (free Developer Edition) from Embarcadero and keep the serial number from the email.
2. Put the zip in the assets folder and run setup with `install-interbase`.
3. Run init with `install-interbase` interactively: it opens InterBase's console License Manager (serial number, then your Embarcadero login) (it prints the keystrokes first: 2 Direct register, the serial, Y, your login, then 4 Save and 5 Exit) and starts the server once with ib-server (since v92: it stops a stuck server first, waits up to 20 s, shows the log when the start fails and leaves nothing spinning; setup no longer starts an unregistered server), which runs `ibmgr -start -forever`. With `noninteractive` this is a todo.
4. Optional: change SYSDBA's password with `gsec` and put the new one in `INTERBASE_SYSDBA_PASSWORD`.

Since v93 setup runs `ldconfig` right after the InterBase install and gives the installer's root-only `ibmgr` the execute bit, and ib-server and init check it through sudo too: v92 read that mode as "not installed" and asked to register an InterBase that was already registered.

The server does not start with Linux by itself; rerun init, or `ib-mgr -start -forever`, after a restart.

### SQL Server and Oracle (install-db-server)

Nothing to register: setup generates a password for each container, and `~/.local/bin` gets the `mssql` and `oracle` commands.

1. Optional, before the first setup run with the flag: uncomment `MSSQL_SA_PASSWORD` or `ORACLE_PWD` in `secrets.env` to pick your own. A password only takes effect when the database is first created.
2. Run setup with `install-db-server` (or `install-mssql` / `install-oracle` alone). The containers are created but left stopped.
3. `mssql up` or `oracle up` starts one and waits until it answers; Oracle's first start takes a few minutes (since v93 the first 'oracle up' of a new data volume also sets the database's passwords with the image's setPassword.sh, because the Lite image never applied ORACLE\_PWD), and `DEVDB_WAIT` (default 900 seconds) bounds the wait. Then `mssql sql` / `oracle sql` open sqlcmd / SQLcl, `status`, `logs` and `password` report, and `down` stops it.
4. Changed a password inside the database (`ALTER LOGIN sa` / `ALTER USER system`)? Put the new one in `secrets.env` so the commands, test and demo still log in.

### LDAP (install-ldap, install-ldap-full)

Nothing to log in to: setup creates the directories with their own passwords and keeps them in `~/.config/devldap/ldap.env`.

1. To choose the base DN or any password yourself, uncomment its line in the LDAP section of `secrets.env` before the first setup run with the flag. For OpenLDAP the base DN must be dc=... parts only.
2. After setup, `ldap status` shows both directories and `ldap passwords` the passwords.
3. `ldap login alice` checks a sample password; `ldap ui` opens lldap's web UI (admin, for people and groups).
4. `ldap drupal` prints the values for Drupal's LDAP server form; dev-demo's drupal/drupal-ldap site sets them up in DDEV.

### Laptop network (install-lan, install-lan-share)

Nothing to log in to. Init writes the address book into /etc/hosts and applies LAN\_SHARE to the relay; the one manual step is outside Linux.

1. Since v93: let init join each laptop to your tailnet (the browser login, or TAILSCALE\_AUTHKEY) and turn off key expiry for it in the Tailscale admin console; then fill in `LAN_HOSTS` with the same list on every laptop (the 100.x addresses 'tailscale status' lists; a laptop not on Tailscale keeps its home address, reserved on the router), and `MACHINE_LABEL` (or `LAN_SELF`) with this laptop's name in it.
2. On a laptop that serves, set `LAN_SHARE` and rerun init (or `lan share apply`).
3. Only with LAN\_TAILSCALE=0 (the v84 relay): add each port `lan share ports` lists in ChromeOS: Settings > Advanced > Developers > Linux > Port forwarding > Add, type TCP (search Settings for "port forwarding" if your ChromeOS files it elsewhere).
4. Run `lan scan` on another laptop, or (v93) 'lan probe NAME', which checks each shared service there in its own protocol. In relay mode init keeps each relayed port on its to-do list until a connection from another laptop has come through it; dev and MCP ports stay skips, since init cannot see those.

Anyone on the same Wi-Fi reaches a forwarded port, and Ollama has no login: run `lan share off` on any network that is not yours. A guest network or a router with client isolation keeps laptops apart whatever the scripts do.

### Personal agents (install-hermes, install-openclaw)

Nothing to log in to: init gives each agent a model from secrets.env. Both need a 64K-token context, more than an 8 GB Chromebook holds, so use a cloud key or a bigger machine's Ollama.

1. Fill in `AGENT_ANTHROPIC_API_KEY` (the agents' own key: `ANTHROPIC_API_KEY` works too, but it is exported to every shell, where Claude Code then bills the API instead of your subscription) or `OPENROUTER_API_KEY`, or `OLLAMA_REMOTE` plus `AGENT_MODEL`, and rerun init. Hermes gets the key in `~/.hermes/.env`; OpenClaw is onboarded without prompts and set to ask before running a shell command.
2. Init changes only a model it set itself. A model you pick with `hermes model` or `openclaw models set` stays; `hermes config set model.provider auto` hands Hermes back to init.
3. Manual, when you want them: Nous Portal (`hermes portal`), messaging (`hermes gateway setup`, `openclaw channels add`) with bot accounts made for it, and the always-on services (`hermes gateway install`, `openclaw gateway install`).

An agent runs as you and can read your files, secrets.env included, and the Crostini user has passwordless sudo: Hermes asks before a risky command, and init makes OpenClaw ask before any command not on its allowlist. Read a ClawHub skill before `openclaw skills install`: malicious ones have been found there.

### Shared services (install-cache, install-search, install-vector, install-mongodb, v89)

Nothing to log in to: every service runs on this machine, on 127.0.0.1. Logins and keys live in `~/.config/devsvc/devsvc.env` (mode 600); `devsvc password NAME` prints one and `devsvc info NAME` the connection values for DDEV, Drupal, Laravel, Symfony, Python and Node.

1. Before the first setup run, optionally set `REDIS_PASSWORD`, `QDRANT_API_KEY` and `MONGO_ROOT_PASSWORD` (applied on every run) and any of the five search logins (used only when an engine is first created; generated otherwise).
2. Redis and Memcached start with Linux; start the others when needed: `devsvc up solr`, then `devsvc down solr`. `devsvc fits NAME` says whether one fits the memory budget right now.
3. With install-lan-share, add the service to `LAN_SHARE` only once its login is set: init lists a service it left out as a to-do naming the key.

### Cloudflare (install-cloudflare, v89)

`wrangler dev` runs Workers and D1 locally with no account. To deploy, set `CLOUDFLARE_API_TOKEN` (and `CLOUDFLARE_ACCOUNT_ID` when the token covers several accounts) and rerun init, or run `wrangler login`. A rejected token is a to-do; no account is a skip. cloudflared (install-cloudflared) needs no login for a quick tunnel; `cloudflared tunnel login` is only for named tunnels.

### Apollo GraphOS (install-graphql, v90)

Optional: `rover dev`, `rover supergraph compose`, the router and `apollo-mcp-server` work locally with no account, and an empty `APOLLO_KEY` is a skip. With a key in `secrets.env`, init writes it into Rover's default profile (`~/.config/rover/profiles/default`, mode 600) and checks it with `rover config whoami`: a rejected key is a to-do, GraphOS out of reach is a skip. Keep `APOLLO_KEY` unexported; init reports a to-do if the environment, `secrets.env` or `~/.bashrc` exports it. `APOLLO_GRAPH_REF` matters only for Apollo Connectors in `rover dev` (dev-demo's drupal-graphql `connectors` item).

### Test tools (install-testing, install-cypress)

Nothing to log in to: Playwright, Selenium, the Gherkin runners, Robot Framework and Cypress all run locally. Init reports what setup left: Playwright's three browsers (missing ones are a to-do), Selenium Manager's chromedriver for the current Chrome (missing is a skip; the next run fetches it), Reqnroll's templates when .NET is installed, and `robot` and `rfbrowser` in `~/.local/bin`. The Selenium Grid shows in the shared-services report (`devsvc up selenium` starts it). `CYPRESS_RECORD_KEY` is optional and only matters for Cypress Cloud recording; empty is a skip. Playwright MCP is added to Claude Code per folder, not by init: dev-demo's e2e-bakeoff `mcp` item does it.

### GitLab (install-gitlab, install-gitlab-runner)

Optional: glab and gitlab-ci-local work without an account, and a missing token is a skip. With `GITLAB_TOKEN_ONCE`, init logs glab in to gitlab.com (`glab auth login --stdin`, SSH as the git protocol) and uploads `~/.ssh/id_ed25519.pub`; with `DRUPALCODE_TOKEN_ONCE`, it adds git.drupalcode.org as a second host. An existing login is kept; a rejected token is a to-do. `GITLAB_RUNNER_TOKEN_ONCE` registers the runner once (`gitlab-runner register --non-interactive`, Docker executor), after which init reports it as registered. `GITLAB_MCP=1` adds GitLab's MCP server (`https://gitlab.com/api/v4/mcp`) to Claude Code; its OAuth login comes on first use. GitLab itself is not installed: it needs 8 GB of RAM, more than the Linux container gets.

### Puppet and Chef (install-puppet, install-chef)

Nothing to log in to: both run masterless here (`puppet apply`, Bolt, `cinc-client -z`). Init reports the OpenVox, facter, OpenBolt and Cinc versions; a missing command is a to-do, and so is an enabled `puppet` service. With `KNIFE_CHEF_SERVER_URL`, `KNIFE_NODE_NAME` and `KNIFE_CLIENT_KEY` all set, init writes knife's `[default]` profile to the `credentials` file in Cinc's knife folder (mode 600), never over an existing `[default]`, then tries `knife node list`; for a self-signed server certificate run `knife ssl fetch` first.

## ChromeOS settings

Two settings outside the Linux container are needed for the Android stacks (install-mobile, install-android-native); both are under Settings → About ChromeOS → Linux development environment.

- [ ] Develop Android apps → toggle *Enable ADB debugging* → confirm → restart the Chromebook. The toggle alone is not enough on ChromeOS; init then runs `adb connect arc` (falling back to `100.115.92.2:5555`), after which `adb devices` shows the Chromebook as `emulator-5554`. Crostini cannot run the Android emulator, so this is how apps get deployed.
- [ ] Disk size → give the container about 30 GB or more. Android Studio, the SDK, the NDK and Gradle caches need roughly 10 GB on their own, and the Gemma model adds 4.3 GB. Memory behaves differently from disk: `free` inside Linux can show several GB "used" with no process holding it. That is ChromeOS's balloon keeping VM memory for the host and returning it only under pressure, slowly. Closing Chrome tabs and Android apps is what frees it. It is why a cold Gemma load can take minutes, and why v70 raises Ollama's load timeout to 15 minutes. Measured on eldrid: with about 1.8 GB available the first load ran past 15 minutes, and once memory had been returned the next one took 34 seconds. Also measured on eldrid with only the Terminal open: of 6.4 GB, Linux processes, tmpfs and kernel structures together held about 0.55 GB, yet only 2.3 GB was available, so roughly 3.5 GB sat in no Linux category. That is memory ChromeOS itself had taken back for the host, not anything running in the container. It returns under pressure, and on eldrid a load that had to force it back took over 15 minutes. The first gemma call after the Chromebook has been idle is the slow one; the ChromeOS Task Manager (Search + Esc) shows what the host side is holding. Note also that `/tmp` is a RAM-backed tmpfs on Debian 13: anything large written there costs memory, which is why the test script keeps its scratch projects in `~/.cache/dev-test` since v72. Clang/LLVM with the .NET SDK is about 1 GB, the two Godot editors about 0.4 GB, and install-godot-templates several GB more, which matters on the 64 GB machine.

Docker group membership is handled by setup; run `newgrp docker` or open a new terminal for it to take effect.

## GUI first-runs

None of these can be scripted; do them once, in any order. Init's still-manual list at the end names the ones it can check (Claude Code, Codex, Android Studio, the Langfuse keys, and the cloud logins under noninteractive). Antigravity (reported as a skip since v81, as sign-in happens in the app), drupal.org (a skip), the editors and Godot never appear there.

- [ ] Claude Code: run `claude` in a terminal and finish the browser login (subscription) — skip if you set `ANTHROPIC_API_KEY`.
- [ ] Codex: run `codex login` for the ChatGPT-account flow — skip if you set `OPENAI_API_KEY`.
- [ ] Android Studio: launch from the app drawer, accept the wizard defaults, point it at the existing SDK at `~/.android/sdk` if asked, skip the emulator. With ADB debugging enabled, the Chromebook appears as a connected device. Since v70 setup pins it to the X11 toolkit (`-Dawt.toolkit.name=XToolkit` in its VM options): its bundled runtime defaults to native Wayland, which on ChromeOS dims the IDE window whenever it has focus. If the window ever dims again after an Android Studio update, check Help → Edit Custom VM Options for that line.
- [ ] Antigravity: launch Antigravity IDE (or Antigravity) from the app drawer, or run antigravity-ide, and sign in with your Google account. The CLI is `agy` at `~/.local/bin/agy`; the Python SDK venv is activated with `source ~/.antigravity-env/bin/activate`.
- [ ] Cursor, Windsurf, VS Code: sign in only if you want their AI features; nothing else depends on it. Since v66 Cursor has its own ChromeOS launcher entry (it ships as a bare AppImage, so it had none); rerun setup with install-cursor on machines set up earlier, and give the app drawer a minute to pick it up.
- [ ] Godot: launch Godot Engine or Godot Engine (.NET) from the app drawer. When creating a project choose the Compatibility renderer; Forward+ and Mobile need Vulkan, which the Linux container does not expose.
- [ ] drupal.org: add `~/.ssh/id_ed25519.pub` at git.drupalcode.org → user settings → SSH keys. Issue forks and merge requests push over SSH, and there is no API for it, so init can only check. The test script warns until `ssh -T git@git.drupal.org` greets you.
- [ ] Langfuse: `cp ~/agentic/.env.example ~/agentic/.env` and fill in the same Langfuse keys there for the agentic project (init sets them in the shell; the project reads its own `.env`).
- [ ] Cloud logins run inside init itself (browser or device code); with `noninteractive` they land in this todo list instead: `aws configure sso`, `az login --use-device-code`, `gcloud auth login`, `gcloud auth application-default login`, `vercel login`.

## Nothing to configure

These install and work with no account, key or setting: Docker, Homebrew, ddev, gh (binary only), mkcert, Google Chrome, Rust and wasm-pack, Go, PowerShell, Ruby and Jekyll, Lazarus, Flatpak with HandBrake and KDiff3, all database and ODBC drivers (msodbcsql18, pxlib, SQLite, PostgreSQL, MariaDB, DuckDB with the `CSV` DSN), the lakehouse stack (DuckDB CLI with Iceberg, DuckLake and Delta Lake, delta-rs, dbt Fusion, dbt Core via `dbt1`), Temporal (`tsdb` alias), and Ollama with `gemma4:e2b-it-qat`.

Terraform, tflint and Bicep (install-iac, v57): init writes `plugin_cache_dir` into `~/.terraformrc` so providers download once instead of per project. State backends and provider credentials are per project and use the cloud logins above. Bicep is installed via `az bicep` only when install-azure is also present.

Ansible (`install-ansible-full` via install-iac, or `install-ansible-core`, v76) has no account to log in to. Init only checks the optional `ANSIBLE_VAULT_PASSWORD_FILE`, tightens it to mode 600, and reports skip when it is unset. Docker containers need nothing as targets; for an SSH host run `ssh-copy-id -i ~/.ssh/id_ed25519.pub user@host` once. Collections a project needs beyond the installed set go in its `requirements.yml` (`ansible-galaxy collection install -r requirements.yml`); a copy in `~/.ansible/collections` takes precedence over the bundled one.

Update Ansible by rerunning setup with the same flags, not with `pipx upgrade-all`: that upgrades ansible-core alone, past the version the community package pins, and the test's `pip check` then fails. Once `ANSIBLE_VAULT_PASSWORD_FILE` is uncommented, the file must exist and must not be executable unless it is a script: Ansible runs an executable password file. Init and the test both check this.

Ollama (`install-ollama`, v77) needs no account for local models. Init only makes sure the service starts with Linux. To change a server setting, use `sudo systemctl edit ollama`; don't edit setup's `dev-setup.conf`, which is rewritten on every run. The override wins, and the test reports a changed value as a pass with a note. The curated models (`install-models`) are listed in `assets/ollama-models.txt`, which the test and demo scripts read. Set `OLLAMA_TEST_CLOUD=1` before the test to also make one live `:cloud` call (after `ollama signin`; a fraction of a cent).

The test reports four INFO lines for the models: where the model ran, its speed, its context length, and the KV-cache line from Ollama's log (q8\_0 applies only with flash attention; a model that falls back to f16 shows it there). Up to two models stay loaded, so a RAG loop keeps its embedding and chat models side by side when memory allows; Ollama unloads an idle one first when it does not. Loaded models hold RAM for five minutes, so run 'ollama stop \<model>' before kind or a Gradle build. For strictly one at a time, set `OLLAMA_MAX_LOADED_MODELS` to 1 with `sudo systemctl edit ollama`.

Firebird (part of `install-db` since v80) needs no account: embedded access has no server and checks no password, so `ISC_USER=SYSDBA isql-fb /path/file.fdb` opens any file you can write. If Firebird's shared lock directory is not writable for you, setup adds `FIREBIRD_LOCK=~/.cache/firebird-lock` to `~/.bashrc`; every program opening the same file must use it.

SQL Server and Oracle (`install-db-server`, v82) each hold about 2 GB while running and Linux gets about 6.4 GB, so `mssql up` stops Oracle first and the reverse (`DEVDB_BOTH=1` runs both). Both listen on 127.0.0.1 only, and Oracle Free allows one instance per machine. Data lives in the volumes `devdb-mssql-data` and `devdb-oracle-data` (devdb-oracle-full-data on the full image), which survive reruns and image updates; to start over, `docker rm -f devdb-mssql && docker volume rm devdb-mssql-data` and rerun setup (the same for oracle). On dragonair's 64 GB disk, watch the roughly 3 GB images: `demo-clean` does not remove them.

The full Oracle image (`install-oracle-full`, v83) needs about 13 GB free (the image plus the copy of its built-in database that goes into the new volume) on top of `DEV_DB_MIN_FREE_GB`; setup keeps the Lite container when it can't pull it, and init lists that as a todo. After the move, `docker volume rm devdb-oracle-data && docker rmi container-registry.oracle.com/database/free:latest-lite` reclaims the Lite database and image once you no longer need them. `oracle sql` then `SELECT comp_id, comp_name FROM dba_registry;` shows which components a database has.

LDAP (`install-ldap`, `install-ldap-full`, v83) needs no account. lldap restarts with Linux until `ldap down`; slapd is a service that starts with Linux. After `ddev poweroff`, `ldap up` puts lldap back on DDEV's network. Start over (deletes the directories): `docker rm -f devldap-lldap && docker volume rm devldap-lldap-data`, for full also `sudo apt purge -y slapd && sudo rm -rf /var/lib/ldap /etc/ldap/slapd.d`, then remove `~/.config/devldap/ldap.env` and rerun setup.

The laptop network (`install-lan`, `install-lan-share`, v84) is off until you fill in secrets.env: an empty `LAN_SHARE` shares nothing. The relay passes connections from this Linux's network address to 127.0.0.1, so the services keep their own settings and nothing is recreated; `lan share` shows each port, whether its service runs, and whether another laptop has reached it yet. DDEV sites on another laptop: `lan site <laptop> <site>`, then https://\<site>.ddev.site:8443 (that laptop's mkcert certificate, so the browser warns). Vite and Angular accept an address rather than a name unless their allowedHosts says otherwise.

Since v93 the laptops talk over Tailscale: Linux on these Chromebooks now runs as a full VM with no ChromeOS port forwarding. Setup installs Tailscale in normal mode, init joins the laptop, `lan share apply` publishes LAN\_SHARE with `tailscale serve`, and `lan probe NAME` / `lan path NAME` check another laptop's services and route. Ollama on another laptop: `http://NAME.internal:11434`. `LAN_TAILSCALE=0` in `secrets.env` keeps the v84 relay.

COM and retro (`install-com`, `install-retro`, v85) need no accounts. COM registers into a local Wine prefix (`~/.local/share/wine/com`); `wine-com` runs programs in it, and widl + mingw build a server that `regsvr32` registers and `CoCreateInstance` activates, in-process or out-of-process — the same activation path DCOM uses across machines, whose server side belongs on a Windows laptop. Retro builds DOS 16/32-bit (run in DOSBox-X) and Win16/Win32/Win64 (run under Wine) from Open Watcom and mingw; put Windows 3.1x media in `~/win31/install/windows` and installers like Delphi 1 in `~/win31/install/apps`, then `win31 setup`.

Since v92 the retro guests need no account either, only your media and keys. Init reports each one as a skip (you may want only some): `win31` media in `~/win31/install/windows`, the Windows 95 CD's `.iso` in `~/win95/install` (OSR2 asks for the OEM key, `xxxxx-OEM-xxxxxxx-xxxxx`), the NT 4.0 and 2000 CD `.iso` files in `~/winnt40/install` and `~/win2000/install` (service-pack `.iso` files there become a second CD), then `<cmd> setup`. A setup refused for disk space says so in init and in `retro`. KVM is a todo only when `/dev/kvm` exists and the group that owns it (kvm on Debian) is not active yet (shut Linux down and reopen it); without `/dev/kvm` (dragonair) NT 4.0 and 2000 run in software emulation. At the NT login, `winnt40 keys ctrl-alt-del` (ChromeOS keeps the real keys). Delphi 1 under Wine: `delphi1 setup` (its SETUP.EXE in `~/win31/install/apps`), then `delphi1` or its launcher icon; it turns Integrated debugging off and sets the editor font (Courier New 10) in `DELPHI.INI`, which lives in `C:\WINDOWS`, by itself, and `delphi1 ini save` keeps any other options you change. Fonts for the other guests: `<guest> fonts` puts the core fonts and Tahoma in `C:\FONTS` (win31) or `D:\FONTS`, with a README on installing them and on font smoothing (grayscale at most: ClearType began with Windows XP). The Wine route has no integrated debugger, no Database Desktop and no BDE table access: those stay in `win31`. The steps are in `~/dev-demo/retro/matrix/STEPS-delphi1.md` and `STEPS-winnt.md`.

Since v93: program CDs (`.iso`) go in `~/<guest>/install/apps` and are F: in every guest (`<guest> cd list`, `<guest> cd NAME`; winnt40 and win2000 swap it while running, `cd --windows` swaps their Windows CD). The exchange disk is 1 GB and win95's disk 2 GB by default; set `RETRO_EXCHANGE_MB` (64-2047, 512 for less disk) and `RETRO_WIN95_DISK_MB` (512-8192) in `secrets.env` before the disk exists, or on the command line for one run (`RETRO_EXCHANGE_MB=512 win2000 setup`); `retro sizes` shows them, and `<guest> exchange recreate` rebuilds an exchange disk at a new size. `win95 snapshot save|restore|list|delete` keeps undo points. Delphi 3, 4, 5, 6 and 7 under Wine (Delphi 5 reports Windows 2000, and its real guest is win2000, as for 6 and 7): the CD in `~/delphi/install/N`, then `delphi N setup` and `delphi N`; init lists each as a skip. Which Delphi goes in which guest: `STEPS-delphi.md` in the same folder.

The personal agents (`install-hermes`, `install-openclaw`, v86) run as `hermes` and `openclaw chat` once init has given them a model. The test needs no key: each agent answers one prompt from a stand-in model on this machine, and OpenClaw's gateway is checked to stay on loopback and refuse a wrong token. `AGENT_TEST_LIVE=1` adds one real prompt per agent. The Linux container sleeps with the Chromebook, so a messaging bot here is not reachable around the clock.

Docker containers reach Ollama only after setup runs with `install-ollama-containers` (v80); init reports which way it is. DDEV's Drupal AI demo (`drupal-rag`) needs that and the `install-models` models.

Angular, corepack and Composer need no accounts either: init only turns Angular CLI analytics off, and `corepack use pnpm@latest` pins a package manager per project. kubectl, helm, kind and k9s have no login of their own — kind writes `~/.kube/config` when you create a cluster, and cloud clusters come from `aws eks update-kubeconfig`, `az aks get-credentials` or `gcloud container clusters get-credentials`. A kind cluster takes about 2 GB, so stop Ollama models before starting one.

The native toolchains (install-cpp, install-asm, install-asm-arm, v63) need no accounts. The .NET SDK (install-dotnet, v63) needs none either: NuGet.org restores anonymously and private feeds are per project in `nuget.config`. Init makes sure `DOTNET_CLI_TELEMETRY_OPTOUT=1` is in `~/.bashrc` and creates the ASP.NET Core HTTPS development certificate; `dotnet dev-certs https --trust` is optional and left to you, since it edits the CA stores. New projects: `dotnet new console -o app` for C#, `dotnet new console -lang VB -o app` for VB.NET. WinForms and WPF are Windows-only in both languages; console, library, ASP.NET Core and Avalonia projects build and run. In Cursor and Windsurf use the clangd extension and an open C# extension, since Microsoft's C/C++ and C# Dev Kit extensions are licensed for VS Code only. Clang/LLVM and the .NET SDK together add roughly 1 GB to the container.

Java (install-java, v63) needs no accounts: Maven Central and the Gradle plugin portal are anonymous, and private repositories go in `~/.m2/settings.xml` or `~/.gradle/gradle.properties` per project. Init only confirms `JAVA_HOME` is in `~/.bashrc`. There is one JDK, Debian's `default-jdk`; a project pinned to another release would need SDKMAN or the Adoptium repo, which the bundle does not install. Gradle comes from Homebrew because Debian's package is too old; it runs on the Debian JDK as long as `JAVA_HOME` is exported, so open a new terminal after setup. Homebrew's openjdk comes along as a dependency of gradle and kotlin and links its own java ahead of Debian's; since v64 setup unlinks it (brew unlink openjdk) so PATH and JAVA\_HOME name the same JDK, and the test fails if they drift apart. First Maven and Gradle builds download a few hundred MB into `~/.m2` and `~/.gradle`. Use `--no-daemon` on the 8 GB machines, or `gradle --stop` afterwards, since an idle Gradle daemon holds about 500 MB.

TanStack (install-tanstack, v65) needs no account. Start, Router, Query and the rest are per-project npm libraries; the flag installs only the scaffolding CLI. `tanstack create my-app` makes a Start app with SSR, `--router-only` a client-side SPA, and `tanstack add tanstack-query` adds to an existing project (pass `--forced` when running it without a terminal). Add-on keys such as Clerk or Sentry go in each project's `.env`, and other deploy logins (`wrangler login`) are per project; since v67 init handles `vercel login` once per machine. Leave TanStack Intent on when you scaffold by hand: it wires `AGENTS.md` and `CLAUDE.md` so Claude Code, Codex and Gemini CLI can load the libraries' skills. For E2E, set `use: { channel: 'chrome' }` in `playwright.config.ts` so Playwright drives the installed Chrome and downloads no browser. `pnpm dev` serves `http://localhost:3000`, which ChromeOS forwards to the browser. If hot reload stops firing in a large project, the container's inotify watch limit is the usual cause; the test script warns when it is below 65536. The first scaffold fills the pnpm store with about 200 MB under `~/.local/share/pnpm`, shared by later projects.

Godot (install-godot, v66) needs no account. Crostini exposes OpenGL through virgl and not Vulkan, so Godot runs here with its Compatibility renderer: pick Compatibility in the project manager when you create a project. The `godot` and `godot-mono` launchers already pass `--rendering-driver opengl3`; set `GODOT_RENDERING_DRIVER=vulkan` to override. Both editors live under `~/.local/opt/godot/current` and are replaced together when setup finds a newer release; pin one with `GODOT_VERSION=4.7.2-stable`. C# projects build with the .NET SDK from install-dotnet. Exporting a game needs install-godot-templates. Android export settings (SDK path, debug keystore) are per machine under Editor Settings, Export, Android, and Godot's docs ask for JDK 17 while the bundle installs 21, so expect to sort that out before the first Android export. The test script opens a small Godot window for a second to prove rendering works; if it reports the adapter as llvmpipe, rendering is in software. On eldrid this was group membership, not the GPU, confirmed in v69's run once Linux had been restarted (virgl on X11, Wayland and in Godot): `/dev/dri/renderD128` belongs to group `render`, the default user is only in `video`, and windowed OpenGL needs the render node. Since v69 setup adds both groups. Follow-up checks in the test say which case you are in: whether the VM exposes `/dev/dri` at all (if not, enable `chrome://flags/#crostini-gpu-support` and shut Linux down fully, not just the terminal), what `glxinfo` reports for X11 apps, and whether Godot on native Wayland gets a hardware renderer. If only Wayland is accelerated, start the editors with `GODOT_DISPLAY_DRIVER=wayland`, which the launchers honour.

Vercel (install-vercel, v67): init runs `vercel login`, or checks `VERCEL_TOKEN` if you set one. Per project, run `vercel link` once and then `vercel env pull` to write that project's variables to `.env.local`. The AI SDK and the AI Gateway client stay per project.

Jev (install-jev, v67) is TypeSafe AI's hosted decision model: state and typed questions go in, Choice, Score and yes/no probabilities come out, and it generates no text. Nothing is installed for it beyond TypeSafe's skill for Claude Code, invoked as `/typesafe:typesafe-ai`. Add the SDK per project with `uv add typesafe-sdk` or `pnpm add @typesafe-ai/sdk`; both read `TYPESAFE_API_KEY`. Through Vercel AI Gateway it is `pnpm add ai@latest`, the experimental `evaluate` API and model `typesafe-ai/jev`. The test script makes a live call on each route that has a key and skips the ones that do not. Pin the model version once you tune confidence thresholds, since `jev-latest` moves, and treat the published speed and accuracy figures as TypeSafe's own until you have measured on your traffic.

Homebrew and PATH (v68): `brew shellenv` puts Homebrew first on PATH, and on Linux every formula links its own copies of common tools, so Homebrew's `java`, `python3`, `sqlite3`, `as` and `ld` were shadowing Debian's. Setup now writes a marked block in `~/.bashrc` that moves Homebrew's directories to the end of PATH. Tools that exist only in Homebrew (`gh`, `ddev`, `aws`, `az`, `terraform`, `kubectl`, `gradle` and the rest) are unaffected; to prefer a Homebrew copy of anything else, call it by full path. `brew doctor` will remark that `/usr/bin` comes first, which is the intent. Since v74 the block is rewritten where it stands in `~/.bashrc`; v68 to v73 moved it to the end on every run, below the kubectl completion line, so each new terminal printed `kubectl: command not found`. kubectl completion now lives in `~/.local/share/bash-completion/completions` (loaded on demand, like terminus and acli), and `k` still works as an alias with completion. The four Python venvs are built from `/usr/bin/python3`, and one that was built on Homebrew's Python is rebuilt once, which re-downloads its packages (torch included) on that run.

Drupal tooling (install-drupal, v68): one machine-level CLI per host, and everything else per project. DDEV's web container already carries `terminus`, `acli` and the Upsun CLI for `ddev pull`; the host copies are for work outside a project. Per project, not installed by the bundle: Drush, PHPStan with phpstan-drupal, PHPCS with Drupal Coder, Drupal Rector and Upgrade Status as Composer dev dependencies (host PHP 8.4 runs `vendor/bin/phpcs` for the editor), and for contrib module work `ddev add-on get ddev/ddev-drupal-contrib`, which runs the same checks as drupal.org's CI. Xdebug is already in DDEV (`ddev xdebug on`, editor listens on 9003). PHP Intelephense is on Open VSX, so it works in Cursor and Windsurf too. Terminus plugin installed: rsync. Pantheon Secrets need no plugin: Terminus 4 has `terminus secret:site:set`, `secret:site:list` and the `secret:org:*` commands built in, and the old secrets-manager plugin is deprecated. Both CLIs self-update with `terminus self:update` and `acli self:update`.

Laravel (`install-laravel`, v87) needs no account: each app keeps its settings in its own `.env`. Start one with `laravel new <app>` in a new terminal, then `composer run dev` (server, queue worker, logs and Vite together). Per project: Laravel Boost gives Claude Code the app's docs and tools (`composer require laravel/boost --dev`, then `php artisan boost:install`). The front-end build fetches the welcome page's font from fonts.bunny.net, so it needs the network.

Symfony (`install-symfony`, v88) needs no account either: each app keeps its settings in `.env` and `.env.local`. Start one with `symfony new <app> --webapp`, then `symfony serve` in it. `symfony new` makes a first git commit, so set `GIT_NAME` and `GIT_EMAIL` in secrets.env first (or pass `--no-git`). For https from `symfony serve`, run `symfony server:ca:install` yourself: it adds the CLI's own CA to the system and browser trust stores, so init only mentions it.

The shared services (v89) cost memory only while they run: Redis and Memcached together about 25 MB idle, Solr or OpenSearch about 1 to 1.3 GB, Atlas Local about 2.5 GB. `devsvc up` refuses a start that would push past `DEVSVC_RAM_MB` (counting loaded Ollama models) and names what to stop; the heavy engines stop one another, and SQL Server or Oracle, as they start. OpenSearch and Elasticsearch need `vm.max_map_count` only with mmap on, which setup turns off. FastMCP's CLI (`fastmcp`, from the fastmcp-slim package) and the MCP Inspector (`mcp-inspector`) come with install-agentic; FastMCP itself is added per project (`uv add fastmcp`).

RAM reminder for the 8 GB machines: Ollama holds about 3.5 GB while a model is loaded, so run `ollama stop gemma4:e2b-it-qat` before Android builds, large DuckDB loads, or the Temporal worker.
