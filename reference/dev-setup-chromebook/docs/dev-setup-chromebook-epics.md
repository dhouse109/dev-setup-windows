# dev-setup-chromebook: the epics, v1 to v93

The bundle's history grouped by theme rather than by version: what each epic set out to do, and the
versions that did it. The version-by-version notes are in [CHANGELOG.md](../CHANGELOG.md).
Versions before v53 were reconstructed afterwards from notes on the Gemini-era conversations and from
comments in the scripts, so their details are coarser.

## The two eras

1. **Gemini era (v1 to about v49): one script**
    - v1-v12: an ad-hoc collection of terminal commands becomes an automated provisioning script.
    - v13-v22: `setup.sh` grows into `dev-setup-chromebook` (v17), with flag expansion (v18).
    - v25-v35: Debian trixie and PEP 668 fixes, Crostini workarounds, regressions found and fixed.
    - v36-v49: no notes survive.
2. **Claude era (about v50 to v93): a four-script bundle**
    - v50-v56: setup gains its companions (test by v52, init in v53), all on one version number.
    - v57-v74: cloud, infrastructure, web and language stacks; the Crostini hardening runs.
    - v75-v84: dev-demo, local models, database servers, LDAP and the laptop network.
    - v85-v93: COM and retro computing, personal agents, frameworks, shared services, GraphQL, test
      tools, then three engines and Delphi 1-7 for the retro guests.

## Epics

1. **The installer and its flag system**
    - v1-v13: from ad-hoc commands to one provisioning script, `setup.sh` (v13: system, Python, Rust,
      SSH key, Docker, Homebrew, VS Code, Chrome, PowerShell, Node.js, Cursor, Windsurf, Flatpak,
      Lazarus, Antigravity).
    - v17: renamed `dev-setup-chromebook`.
    - v18: stack switches: group flags expand at the top of the script, with `install-all` as the
      master switch.
    - v20-v26: the active-flags readout, lost in v25 and restored in v26.
    - v62: fully unattended runs (Homebrew's ask mode off, no overwrite prompts).
    - v65: everything the scripts write lives in `./assets`, not loose in the home directory.
    - v68: Homebrew moved to the end of PATH; v74: marked `~/.bashrc` blocks rewritten in place.
    - v81: the version history moved out of the script headers into one file.
    - v93: the Chrome, Go and PowerShell downloads checked before use, so a bad one skips that tool
      instead of stopping the run; IPv4 preferred where IPv6 is broken.

2. **One bundle: test, init and demo**
    - by v52: dev-test, which checks that each component works, not only that it is installed.
    - v53: dev-init, which applies logins, keys and config from `secrets.env`, never from the scripts.
    - v54-v55: the three scripts kept on one version number.
    - v57 onward: each new stack gets its own init section and test section.
    - v68: run order init → setup → init → test; platform tokens optional throughout.
    - v75: dev-demo, the optional fourth script: hands-on demos for each stack in `~/dev-demo`.
    - v77: dev-test measures disk use per stack.

3. **Debian trixie and Crostini hardening**
    - v28-v33: the trixie fix (`software-properties-common` out), PEP 668 virtual environments for
      the Gemma and Antigravity SDKs, Cursor downloaded around a Crostini DNS bug, and the regressions
      those changes caused, fixed.
    - v52: Debian's t64 library renames accepted.
    - v59: aider on a managed Python 3.12, since trixie ships 3.13.
    - v64, v68: Homebrew's openjdk, python3, sqlite3 and binutils no longer shadow Debian's.
    - v69: the `render` group for GPU rendering through virgl.
    - v70: Android Studio's dimming window under Wayland; Ollama's model-load timeout raised.
    - v72: test scratch moved off the RAM-backed `/tmp`.
    - v93: downloads no longer hang on a broken IPv6 route.

4. **Languages and editors**
    - v13: Python, Rust, Node.js, PowerShell; Cursor, Windsurf, VS Code; Lazarus.
    - v16: WebAssembly targets and wasm-pack.
    - v18: Go.
    - v29: Ruby and Jekyll.
    - v51: Claude Code from its native installer; v58: Gemini CLI and aider.
    - v63: C/C++, assembly (x86-64 and AArch64), .NET (C# and VB.NET) and Java.
    - v66: Godot, the standard and .NET editors side by side.
    - v73: the graphical Antigravity installed from its tarball.

5. **Mobile and Android**
    - v17: the mobile switch (Tauri, React Native, Flutter).
    - v28-v32: Android SDK PATH fixes, then the SDK tools downloaded automatically.
    - v50-v52: Android platform-name fix, Tauri via npm with NDK_HOME, Android Studio link scraping,
      the Flutter Linux toolchain.
    - v56: deploying to the Chromebook's own Android runtime with `adb connect arc`.
    - v70: Android Studio pinned to the X11 toolkit.

6. **AI and local models**
    - v14: the Gemma 4 hybrid setup on Ollama, with `gemma_client.py`.
    - v33-v35: RAM warnings for the 8 GB machines; Hugging Face login with `HF_TOKEN`; Gemini 2.5
      Flash for the cloud route.
    - v50: `install-agentic`: Temporal, LangGraph, Pydantic and Langfuse.
    - v67: Jev (TypeSafe AI) and the Vercel CLI.
    - v77: Ollama as its own flag, and `install-models` (DeepSeek-R1, Qwen 3.5, an embedding model).
    - v80: Ollama reachable from Docker containers, for a Drupal RAG site.
    - v86: personal agents: Hermes Agent and OpenClaw.

7. **Data and databases**
    - v22: `install-db`: ODBC, the SQL Server driver, Access and Paradox.
    - v79: Delta Lake in `install-lakehouse` (DuckDB, dbt, DuckLake).
    - v80: Firebird 4 embedded, and InterBase.
    - v82: `install-db-server`: SQL Server 2025 and Oracle 26ai Free in Docker, with InterBase.
    - v83: Oracle's full image as an option.
    - v89: shared services behind `devsvc`: Redis, Memcached, Solr, OpenSearch, Meilisearch,
      Typesense, Qdrant, sqlite-vec, MongoDB, and opt-in Elasticsearch, Milvus and Atlas Local.
    - v93: five database fixes, found on a v92 `install-db-server` run.

8. **Cloud, infrastructure and DevOps**
    - v57: AWS, Azure and Google Cloud CLIs; Terraform, tflint and Bicep. v61: tflint from its release
      zip after it left homebrew-core.
    - v58: Kubernetes (kubectl, helm, kind, k9s); v60: kind verified in Crostini's Docker.
    - v67: Vercel; v89: Cloudflare's wrangler and cloudflared.
    - v76: Ansible, full and core.
    - v91: GitLab (glab, gitlab-ci-local, an opt-in runner); Puppet (OpenVox) and Chef (Cinc).

9. **Web, PHP and Drupal**
    - v58-v59: `install-web` (Angular CLI, corepack, Composer, Drupal's PHP extensions).
    - v65: TanStack.
    - v68: `install-drupal`: Terminus, Acquia CLI, Upsun and DDEV settings.
    - v83: LDAP directories (lldap, OpenLDAP) for Drupal logins.
    - v87: Laravel; v88: Symfony.
    - v90: GraphQL with Apollo (Rover, Router, MCP Server), with a Drupal demo.
    - v91: Vue and Nuxt.

10. **Testing tools**
    - v91: `install-testing`: Playwright, a Selenium Grid, Gherkin runners and Robot Framework; Cypress
      as an opt-in.

11. **The laptop network**
    - v84: `install-lan` (an address book for all the laptops) and `install-lan-share` (sharing
      Ollama, databases, LDAP, DDEV and dev servers).
    - v89: the `devsvc` services join what can be shared (Redis, Qdrant and MongoDB once they have a
      password).
    - v93: over Tailscale, after Linux port forwarding disappeared from newer ChromeOS releases.

12. **Retro computing**
    - v85: COM development under Wine; DOS and Windows 3.x with DOSBox-X and Open Watcom; Delphi 1.
    - v92: QEMU joins as the third engine, for Windows NT 4.0 and 2000; Windows 95 in DOSBox-X;
      Delphi 1 under Wine; one `retro` command over all three.
    - v93: Delphi 3 to 7, app CDs in every guest, configurable disk sizes.
