# Crostini gotchas

These are things that went wrong while building this bundle on ChromeOS's Linux (Debian 13, 8 GB
Chromebooks), and what fixed each one. Every fix is in the scripts. Search them for the flag in brackets
to see it in context; the comment above each fix usually tells the story.

## Graphics

- **Windowed OpenGL falls back to software rendering** (setup base). Crostini hands Linux a virgl GPU as
  `/dev/dri/renderD128`, which belongs to the `render` group. The default user is only in `video`, so Godot,
  Flutter desktop, Android Studio's previews and Chrome's WebGL silently use llvmpipe.
  **Fix:** `usermod -aG video,render $USER`, then shut Linux down and reopen it.
- **There is no Vulkan** (`install-godot`). Only OpenGL comes through. Godot's Forward+ and Mobile renderers
  need Vulkan, so the `godot` launchers default to `--rendering-driver opengl3`.
  **Fix:** pick the Compatibility renderer for new projects.
- **Android Studio's window dims while it has focus** (`install-android-native`). This happens under
  ChromeOS's Wayland, with the IDE's JetBrains runtime.
  **Fix:** `-Dawt.toolkit.name=XToolkit` in its VM options.

## Network

- **Downloads hang on IPv6** (setup base). A Linux VM can get IPv6 addresses with no route out. `wget` then
  waits on one IPv6 address after another, while the ChromeOS browser works because it races IPv4 against
  IPv6. **Fix:** setup detects this and adds `precedence ::ffff:0:0/96 100` to `/etc/gai.conf`, plus
  `Acquire::ForceIPv4` for apt. Every wget and curl also gets a 20-second connect timeout.
- **Linux port forwarding is gone** (`install-lan`). On these Chromebooks, new Linux installs since ChromeOS
  147 run as a full VM, with no port forwarding from ChromeOS. Other laptops can't reach a service in
  Linux. **Fix:** Tailscale.
- **Tailscale starts in userspace mode** (`install-lan`). In this VM `tailscaled` picked userspace
  networking by itself, so there was no `tailscale0` interface and Linux tools couldn't reach the 100.x
  addresses. **Fix:** `FLAGS="--tun=tailscale0"` in `/etc/default/tailscaled`.
- **Ollama answers 403 to a plain hostname** (`install-lan`). Ollama refuses a `Host:` it doesn't
  recognise. **Fix:** the address book also writes `NAME.internal` names, which it accepts.
- **The GitHub API rate-limits anonymous calls** (many flags). It allows 60 calls an hour per IP, then
  returns 403 in the middle of a run. **Fix:** release tags come from the `releases/latest` redirect, which
  isn't rate-limited.

## Memory and disk

- **Linux sees about 6.4 GB of an 8 GB Chromebook.** SQL Server and Oracle hold about 2 GB each while
  running, and Solr, OpenSearch, Elasticsearch, Milvus and Atlas Local hold 1–3 GB. **Fix:** setup creates
  them stopped. `mssql up`, `oracle up` and `devsvc up` stop the other heavy engines first and check a
  memory budget (`DEVSVC_RAM_MB`).
- **`vm.max_map_count` can't be raised from inside the container** (`install-search`). OpenSearch and
  Elasticsearch normally insist on it. **Fix:** `node.store.allow_mmap=false`, so they don't need it, and
  their disk watermarks are off, so a nearly full disk doesn't turn an index read-only.
- **`/tmp` is RAM-backed.** Large downloads and the test script's scratch space live on disk instead
  (`./assets`, and the test's own work folder).
- **kind works in Crostini's Docker** (`install-k8s`). A cluster takes about 2 GB, so the test unloads
  Ollama's models first.

## Packages and PATH

- **Homebrew shadows Debian** (setup base). Formula dependencies bring their own python3, sqlite3, `as`,
  `ld` and openjdk, and Homebrew's `shellenv` puts them ahead of Debian's. **Fix:** a marked `~/.bashrc`
  block moves Homebrew's directories to the end of PATH. `brew unlink openjdk` keeps `java` on Debian's JDK.
- **A PATH block moved below the lines that need it** (v74). Rewriting a `~/.bashrc` block by deleting it
  and appending it again put it below a `kubectl` completion line, and every new terminal said
  `kubectl: command not found`. **Fix:** marked blocks are rewritten in place.
- **aider needs Python ≤ 3.12, trixie has 3.13** (`install-node`).
  **Fix:** `uv tool install --python 3.12 aider-chat`, which fetches a managed 3.12.
- **npm 12 blocks dependency install scripts** (`install-node` and others). Global CLIs with native
  modules then install broken. **Fix:** `npm install -g --allow-scripts=<names>`, with the names listed per
  package.
- **Debian trixie renamed `libaio.so.1` to `libaio.so.1t64`** (`install-oracle`). Oracle Instant Client
  links against the old name. **Fix:** one compatibility link in the system library directory.
- **Firebird's embedded lock directory** (`install-db`). If another user created `/tmp/firebird` first,
  every embedded open fails. **Fix:** setup probes once and, only if needed, sets a private
  `FIREBIRD_LOCK`.
- **The docker group isn't active in the run that adds you to it.** Group changes apply to new logins, so
  setup's own Docker calls go through `sudo`, and the helper commands fall back to `sudo -n docker`.

## Android

- **The Android emulator doesn't run in Crostini** (`install-android-native`).
  **Fix:** deploy to the Chromebook's own Android runtime. Turn on ADB debugging in ChromeOS's Linux
  settings, then `adb connect arc`.

## Databases

- **Oracle Free's Lite image ignored `ORACLE_PWD`** (`install-oracle`). Every login failed with ORA-01017.
  **Fix:** the first `oracle up` of a new data volume runs the image's own `setPassword.sh`.
- **InterBase's installer leaves `ibmgr` root-only** (`install-interbase`). Checks run as the user then see
  no server manager. **Fix:** setup gives `bin/` tools the execute bit for everyone. A related trap: the
  unregistered Developer Edition server spins at 100% CPU without ever listening, so setup no longer
  starts it before registration.
- **InterBase's `isql -q` exits 1 even when `CREATE DATABASE` worked** (`install-interbase`).
  **Fix:** the test drops `-q`.

## Retro

- **Delphi 1's IDE crashes in a shared Wine prefix** (`install-retro`). It fails with a `winevdm.exe` page
  fault. **Fix:** give it its own 32-bit prefix inside a Wine virtual desktop, with integrated debugging
  turned off.
- **Some Chromebooks have no `/dev/kvm`.** Windows NT 4.0 and 2000 under QEMU then run in software
  emulation, which works but is slow. Windows 3.1 and 95 run in DOSBox-X, which doesn't need KVM.
