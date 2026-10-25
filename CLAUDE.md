# CLAUDE.md — dev-setup-windows

Guidance for Claude Code sessions working in this repository. Read this first, then
`docs/plans/windows-plan.md`.

## What this repo is

The Windows counterpart of [dev-setup-chromebook](https://github.com/dhouse109/dev-setup-chromebook): a
bundle that turns the owner's Windows laptops into the same development environment the Chromebooks get,
with the same flags and features, plus the Windows-specific code, config and exceptions. It is a personal
lab, like the Chromebook bundle. The owner decides what goes in and runs every version on the laptops;
Claude drafts, reviews and fixes the scripts.

**Status: nothing is built yet.** The repo holds:

| Path | What it is |
|---|---|
| `docs/plans/windows-plan.md` | Every decision, finding and open question so far. Start here. |
| `reference/dev-setup-chromebook/` | Read-only copy of the Chromebook bundle's published v93 (commit `ef863ce`): the four scripts, CHANGELOG, README and docs. The source this bundle ports from. |

## The first job

Turn `docs/plans/windows-plan.md` into a build plan for the first version, **with the owner**. The plan
doc's "Open questions" list must be settled before code is written, and several answers shape everything
else. Ask; don't pick defaults silently:

- WSL distro: Debian 13 (matches the Chromebooks) or Ubuntu (WSL's default)
- Docker: Docker Desktop with WSL integration, or Docker Engine inside WSL
- how the Windows-host half is installed (a PowerShell script that runs first, winget, manual steps)
- script names (the `-chromebook` names don't fit) and version numbering (start at v1, or share numbers)
- one bundle for all four laptops, or per-machine tiers
- Ollama native on Windows (proposed) vs in WSL; whether d3 serves models to the Chromebooks
- sudo policy in WSL; Android; InterBase placement; the retro/COM flags on Windows

Present choices with a recommended default and the trade-off, the way the plan doc does, and record the
answers in the plan (Decisions table, plus a line in the Discussion log).

## Architecture (proposed in the plan, not final)

- **Windows host:** a PowerShell script (e.g. `dev-host-windows.ps1`) for what has no Chromebook
  counterpart: enabling WSL and installing the distro, `wsl.conf` / `.wslconfig`, native apps (editors,
  Godot, Ollama), Windows firewall rules, mkcert trust, usbipd-win.
- **WSL 2:** the bash setup / test / init / demo scripts, forked from `reference/` with the fixes from
  the plan's compatibility review applied as straight edits.
- **Network:** the Chromebooks now share services over Tailscale (see the plan's "What changed" section);
  the Windows laptops should be reachable the same way and on the same ports.

## Conventions carried over from the Chromebook bundle

These carry over as settled conventions. Read `reference/dev-setup-chromebook/README.md` and its `CHANGELOG.md` intro for the
originals.

1. **Four scripts, one set of flags.** setup / test / init / demo all take the same flags with the same
   expansion logic, and **flag names match the Chromebook bundle**, so a flag means the same thing on
   both platforms.
2. **One version number for the bundle.** Any change to any script bumps every script to the same
   version, including scripts with no code change ("version bump only" in the changelog). Where the
   numbering starts is an open question.
3. **CHANGELOG.md**, one section per script, newest first.
4. **Nothing loose in the home directory.** Logs, downloads, reports and generated helpers go in
   `./assets` next to the scripts.
5. **Secrets only in `~/.config/dev-init/secrets.env`** (mode 600) inside WSL, never in the scripts or
   the repo. Every hosting-platform or cloud token is optional; init reports a missing one as a skip.
6. **Setup is unattended and idempotent.** No prompts; every step guarded so reruns are safe and a
   hand-configured machine is brought into line, not clobbered.
7. **Downloads are verified** (vendor checksums, `gzip -t`, `dpkg-deb --info`, a test run) before they
   replace anything.
8. **Scope:** CLIs and system-level tools belong in the bundle behind flags; SDKs and frameworks for one
   project stay per-project.
9. **Bring your own media.** Never download Windows, DOS, Delphi, InterBase or other licensed media; the
   scripts install only from files the owner supplies.
10. **A version isn't done until its test run on a laptop is clean** (FAIL 0, WARNs only for optional
    credentials). Until then it is "built, not yet confirmed run on a laptop".

Proposed in the plan, not yet confirmed (check with the owner before relying on them):

- **Keep the fork diffable:** same section order and headings as the reference scripts, so `diff -u`
  between a Windows script and its Chromebook original shows only real platform differences.
- **Tag each changelog entry** with whether it ports to the other bundle (yes / no / n.a.).
- **A shared `dev-common.sh`** only later, and only if porting fixes twice becomes a chore.

## Rules for `reference/`

- **Never edit it.** It is a snapshot of a published Chromebook release, not working code.
- To refresh it, replace the whole folder with a newer tagged Chromebook release and update the commit in
  `reference/README.md` and this file, in a commit of its own.
- Don't run the reference scripts: their host guard stops them anywhere but ChromeOS anyway.

## Target machines

| Machine | Model | CPU | RAM | Notes |
|---|---|---|---|---|
| 109.hpe.d3 | HP Envy 15" | Ryzen 5 5500U | 32 GB | Main Windows dev box; proposed LAN model server; first test target |
| 109.hpe.d1 | HP Envy 17" | i7-1065G7 | 16 GB | GeForce MX330 (2 GB) |
| 109.hpp.d2 | HP Pavilion 15" | i5-10210U | 16 GB | CPU only |
| 109.hpr.d4 | HP 14" | Pentium Silver N5030 | 32 GB | No AVX/AVX2; 500 GB disk |

All x86-64, 1 TB disks except d4.

## What a cloud session can and can't check

The cloud VM is Linux, not Windows or WSL. Real runs happen on the laptops; the owner pastes the end of a
test run back into the session.

- **Bash:** `bash -n` and `shellcheck -S error` on every script.
- **PowerShell:** install `pwsh` if missing, then parse-check each `.ps1` with
  `[System.Management.Automation.Language.Parser]::ParseFile(...)` and run PSScriptAnalyzer at Error
  severity.
- **Secrets:** gitleaks runs in CI (`.gitleaks.toml` allowlists the Chromebook bundle's two known false
  positives, which `reference/` contains).
- **Line endings:** `.gitattributes` keeps `.sh` files LF; CRLF breaks bash in WSL.

## Workflow

- Plans first: each version is planned in `docs/plans/` and approved by the owner before it is built.
- One branch per version, PR into `main`; large versions in stages, one commit per stage.
- The scripts will be large; make targeted edits rather than regenerating whole files.
- After a clean run on a laptop: merge, tag, and publish a GitHub Release with the changelog entry.
