#!/bin/bash
# dev-test-chromebook - Version 93
# Version history: CHANGELOG.md, next to this script in the bundle
# (one section per script, newest version first).
#
# Companion to dev-setup-chromebook.sh. Takes the SAME flags, expands them with the
# SAME logic, and then verifies that what those flags installed actually works. Installs
# nothing (the only side effects are scratch files under a temp dir that is removed on exit,
# a log file in ./assets/logs next to this script, the Docker images the slow tests pull, and
# package caches the slow tests warm: ~/.npm and ~/.cache/node/corepack for install-web,
# ~/.cache/puppeteer for install-node, ~/.nuget and ~/.dotnet for install-dotnet, ~/.m2 and
# ~/.gradle for install-java, ~/.cache/composer for install-laravel and install-symfony, ~/.local/share/pnpm for install-tanstack, ~/.cache/uv for install-jev,
# ~/.ansible and ~/.cache/molecule for the Ansible flags; with OLLAMA_TEST_CLOUD=1, the small
# manifest of the :cloud model it calls, which 'ollama list' then shows).
# With install-godot a small Godot window opens for about a second. With install-mssql /
# install-oracle the database containers are started for their round-trip and stopped again
# afterwards (unless they were already running); the test table is dropped again.
# With install-ldap-full a throwaway entry is added to OpenLDAP and deleted again; with install-ldap
# the slow checks start a small alpine:3 container to reach the directories the way DDEV would.
# With install-lan-share a throwaway relay and two small web servers run for a few seconds on free high
# ports; nothing is shared, and the installed relay and its settings are left as they are (v93: only in
# relay mode, LAN_TAILSCALE=0; over Tailscale the test reads 'tailscale serve status' and changes nothing).
# v93: with install-lan over Tailscale, each other laptop's shared services get one short exchange in their
# own protocol ('lan probe': HTTP, TDS pre-login, TNS connect, LDAP bind, Redis PING, MongoDB hello; no logins)
# and one 'tailscale ping'.
# With install-com a small COM server is built under the temp dir and registered in the COM Wine prefix
# (~/.local/share/wine/com) for its calls, then unregistered again. With install-retro DOSBox-X runs
# headless for a few seconds per DOS program (no window); v93: the win95 checks run the helper in a scratch
# home under the temp dir (a stand-in Windows CD and app CD made with genisoimage or xorriso, a 512 MB
# hdd.img), so ~/win95 is never touched.
# With install-hermes / install-openclaw a stand-in model (a small Python server) runs on a free port
# for the offline checks, a scratch Hermes home is made in ~/.hermes/.dev-test-PID and removed, and
# OpenClaw's gateway runs for a few seconds from a scratch state dir; nothing is sent to a real model
# unless AGENT_TEST_LIVE=1.
# With install-graphql a stand-in subgraph (a small Python server), the Apollo Router and apollo-mcp-server
# run for a few seconds on free high ports from the temp dir; nothing reaches GraphOS (APOLLO_KEY is unset).
# v91: with the test tools (install-testing, install-cypress) a small links app (Python) runs on a free port
# for the browser checks, and the slow checks build scratch projects under the temp dir, warming ~/.npm,
# ~/.cache/uv, ~/.cache/composer, ~/.nuget, ~/.m2 and, for install-cypress, ~/.cache/Cypress (Cypress's
# ~250 MB Electron build). With install-selenium the Grid (devsvc-selenium) is started for its round trip
# and stopped again unless it was running. With install-gitlab a small pipeline runs through gitlab-ci-local in a
# scratch git repository (its Docker job pulls redis:8-alpine); with install-vue create-vue and Nuxt projects are
# scaffolded, built and served for a moment from the temp dir. With install-puppet / install-chef small
# configurations converge into the temp dir, and Bolt and Test Kitchen use scratch containers (debian:trixie-slim,
# cincproject/cinc, dokken/debian-13), removed afterwards.
#
#   ./dev-test-chromebook.sh install-all
#   ./dev-test-chromebook.sh install-node install-lakehouse quick
#
# Test-only flags:
#   quick     skip the slow functional tests (docker hello-world, cargo/go/kotlin builds,
#             puppeteer install, jekyll build, flutter first run, ollama generation,
#             dbt run, temporal round-trip, terraform init/apply,
#             ng new + build, kind cluster, dotnet new + run for C# / VB, maven + gradle builds,
#             tanstack create + build + Playwright, Godot import/render/C# build and exports,
#             Jev SDK installs and live calls, Ansible against a container + molecule test,
#             deepseek-r1:1.5b generation + qwen3-embedding call, a container reaching Ollama,
#             the SQL Server and Oracle round-trips, a container reaching lldap / slapd,
#             the COM server builds and calls under Wine, the Open Watcom builds and the
#             Wine <-> DOSBox-X matrix, the Hermes / OpenClaw offline turns and the
#             OpenClaw gateway check, the Laravel skeleton build, serve and Vite build, the Symfony
#             webapp build, migration, PHPUnit and server checks, the Apollo router and MCP
#             round trips, the browser runs of Playwright, Selenium (local and Grid), the Gherkin
#             runners, Robot Framework and Cypress, gitlab-ci-local's Docker job, the create-vue and
#             Nuxt scaffolds, the Bolt plan and Test Kitchen in containers, ChefSpec)
#   OLLAMA_TEST_CLOUD=1 (environment variable, not a flag): also make one live call to an Ollama
#             :cloud model (OLLAMA_CLOUD_TEST_MODEL, default deepseek-v4.1-flash:cloud); needs
#             'ollama signin' and costs a fraction of a cent
#   AGENT_TEST_LIVE=1 (environment variable, not a flag): Hermes and OpenClaw each answer one prompt
#             with the model dev-init gave them (a fraction of a cent on a cloud key)
#   verbose   print every command's output inline (everything is always written to the log)
#   nodisk    skip the disk-usage report at the end (v77; it takes a minute or two)
#
# Result levels:
#   PASS  works
#   FAIL  something the installer promised is missing or broken   -> exit status 1
#   WARN  not needed to get started (logins, API keys, optional CLIs, unverified names)
#   SKIP  a slow test skipped because of 'quick'
#   INFO  a fact worth knowing, not a result (v77: where an Ollama model ran)
#
# Keep the FLAG EXPANSION block identical to the installer's when you bump versions.

# >>> dev-bundle host guard >>>
# These scripts are written for the Linux environment of a Chromebook (ChromeOS's Crostini container, or
# the Linux VM newer ChromeOS releases create) running Debian 13. They use sudo freely, add apt sources and
# change system files, so on any other machine they stop here. DEV_BUNDLE_ANY_HOST=1 runs them anyway, at
# your own risk; steps that only make sense on ChromeOS (removing the Linux user's password) still skip.
DEV_ON_CHROMEOS=0
if [ -e /dev/.cros_milestone ] || [ -d /opt/google/cros-containers ] \
    || dpkg-query -W -f='${Status}' cros-guest-tools cros-garcon 2> /dev/null | grep -q 'ok installed'; then
    DEV_ON_CHROMEOS=1
fi
if [ "$DEV_ON_CHROMEOS" != 1 ] && [ "${DEV_BUNDLE_ANY_HOST:-0}" != 1 ]; then
    echo "$(basename "$0"): this is not ChromeOS's Linux, so nothing was changed." >&2
    echo "  These scripts are made for a Chromebook's Linux (Debian 13) and assume it throughout." >&2
    echo "  To run them anyway, at your own risk:  DEV_BUNDLE_ANY_HOST=1 $0 $*" >&2
    exit 1
fi
if ! grep -Eqs '^ID="?debian"?$' /etc/os-release && [ "${DEV_BUNDLE_ANY_HOST:-0}" != 1 ]; then
    echo "$(basename "$0"): this Linux is not Debian; the scripts expect ChromeOS's default, Debian 13." >&2
    echo "  To run them anyway, at your own risk:  DEV_BUNDLE_ANY_HOST=1 $0 $*" >&2
    exit 1
fi
# <<< dev-bundle host guard <<<

# Deliberately NO 'set -e': a failing check must be recorded, not abort the run.

# =================================================================
# FLAG EXPANSION (STACK SWITCHES)  -- copied verbatim from the installer
# =================================================================
FLAGS=" $* "

echo "Active Test Flags: $FLAGS"

# 1. The "Install All" Master Switch
if [[ "$FLAGS" =~ " install-all " ]]; then
    FLAGS+=" install-editors install-languages install-ecosystems install-db install-db-extra install-lakehouse install-agentic install-cloud install-iac install-web install-tanstack install-k8s install-jev install-drupal install-laravel install-symfony install-graphql install-cache install-search install-vector install-mongodb install-testing install-gitlab install-vue "
fi

# 2. Category Stack Switches
if [[ "$FLAGS" =~ " install-editors " ]]; then
    FLAGS+=" install-vscode install-windsurf install-cursor install-lazarus "
fi

if [[ "$FLAGS" =~ " install-languages " ]]; then
    FLAGS+=" install-rust install-node install-go install-pwsh install-ruby install-cpp install-asm install-dotnet install-java "
fi

if [[ "$FLAGS" =~ " install-ecosystems " ]]; then
    FLAGS+=" install-antigravity install-media install-gemma install-mobile install-android-native install-godot "
fi

if [[ "$FLAGS" =~ " install-cloud " ]]; then
    FLAGS+=" install-aws install-azure install-gcp install-vercel install-cloudflare "
fi

# v76: install-iac covers configuration management too: the full Ansible community package.
# install-ansible-core (the lean install) belongs to no group; with both, full wins (see setup).
if [[ "$FLAGS" =~ " install-iac " ]]; then
    FLAGS+=" install-ansible-full "
fi

# v82: install-db-server = the database servers: SQL Server and Oracle in Docker, plus InterBase
# (install-interbase, v80, in no group until now). Opt-in, NOT in install-all: several GB of images,
# and each engine holds about 2 GB of RAM while it runs. Each of the three flags also works alone.
if [[ "$FLAGS" =~ " install-db-server " ]]; then
    FLAGS+=" install-mssql install-oracle install-interbase "
fi

# v83: install-oracle-full = install-oracle on Oracle's full image instead of the Lite one (about
# 9.5 GB on disk against 1.8 GB), for the optional database components the Lite image leaves out.
# In no group: install-db-server stays on Lite. Once devdb-oracle runs the full image, later runs
# with plain install-oracle (or install-db-server) keep it on full.
if [[ "$FLAGS" =~ " install-oracle-full " ]]; then
    FLAGS+=" install-oracle "
fi

# v83: LDAP directories to authenticate apps (Drupal) against. install-ldap = the lite one, lldap in
# Docker; install-ldap-full = the full OpenLDAP server (slapd) AND lldap, so full includes lite.
# Both opt-in, in no group, NOT in install-all.
if [[ "$FLAGS" =~ " install-ldap-full " ]]; then
    FLAGS+=" install-ldap "
fi

# v84: your laptops on the home network. install-lan = the address book (LAN_HOSTS in secrets.env,
# written into /etc/hosts) and the 'lan' command; install-lan-share = this machine shares services
# with the others through a relay, and includes install-lan. Both opt-in, in no group, NOT in install-all.
if [[ "$FLAGS" =~ " install-lan-share " ]]; then
    FLAGS+=" install-lan "
fi

# v85: install-retro's Win16 tests run on Wine, so it pulls in install-com (matches the installer).
if [[ "$FLAGS" =~ " install-retro " ]]; then
    FLAGS+=" install-com "
fi
# v86: personal agents, install-hermes (Nous Research's Hermes Agent) and install-openclaw: both
# opt-in, in no group, NOT in install-all. OpenClaw is an npm package on nvm's Node, so it pulls in
# install-node (matches the installer).
if [[ "$FLAGS" =~ " install-openclaw " ]]; then
    FLAGS+=" install-node "
fi

# v89: shared development services behind one 'devsvc' command, in Docker, published on 127.0.0.1 only.
# install-cache = install-redis (Redis 8 container, redis-tools, Redis Insight) + install-memcached
# (Memcached 1.6 container). In install-all; both start with Linux (DEVSVC_AUTOSTART) and cost ~25 MB.
# Each flag also works alone. PHP's redis and memcached extensions come with install-web.
if [[ "$FLAGS" =~ " install-cache " ]]; then
    FLAGS+=" install-redis install-memcached "
fi
# install-search = install-solr (Solr 9.10 in SolrCloud mode, basic auth) + install-opensearch (OpenSearch 3)
# + install-meilisearch + install-typesense. In install-all; all four are created stopped ('devsvc up').
# install-elasticsearch (Elasticsearch 9) is opt-in, in no group, NOT in install-all: the same job as
# OpenSearch, and the three Java engines run one at a time.
if [[ "$FLAGS" =~ " install-search " ]]; then
    FLAGS+=" install-solr install-opensearch install-meilisearch install-typesense "
fi
# install-vector = install-qdrant (Qdrant in Docker) + sqlite-vec (the loadable extension for Debian's
# sqlite3), in install-all. install-milvus (Milvus standalone, which asks for 8 GB of RAM) is opt-in, in no
# group. install-mongodb (MongoDB 8 in Docker, mongosh, the Database Tools, Compass) is in install-all;
# install-mongodb-atlas-local (Atlas Local: Search and Vector Search, plus the Atlas CLI) is opt-in and
# pulls in install-mongodb for the clients.
if [[ "$FLAGS" =~ " install-vector " ]]; then
    FLAGS+=" install-qdrant "
fi
if [[ "$FLAGS" =~ " install-mongodb-atlas-local " ]]; then
    FLAGS+=" install-mongodb "
fi

# v90: install-graphql = Apollo's GraphQL tooling: Rover (the CLI), the Apollo Router (v2) and the Apollo
# MCP Server, three standalone binaries in ~/.local/bin, plus Rover's composition and router plugins. In
# install-all; no dependency guard (the demos use install-node and install-web, both in install-all).

# v91: install-testing = the test tools: install-playwright (Playwright's Chromium, Firefox and WebKit with
# their system libraries, Playwright MCP warmed), install-selenium (a Selenium Grid in Docker as the devsvc
# service 'selenium', and Selenium Manager's driver cache), install-bdd (the Gherkin runners' machine-level
# parts: Reqnroll's dotnet templates when .NET is here) and install-robot (Robot Framework with the Browser,
# SeleniumLibrary and Requests libraries). In install-all. install-cypress (Cypress's system libraries) is
# opt-in, in no group, NOT in install-all: the same job as Playwright, with an Electron download per project.
if [[ "$FLAGS" =~ " install-testing " ]]; then
    FLAGS+=" install-playwright install-selenium install-bdd install-robot "
fi
# v91: GitLab and Vue.js. install-gitlab = glab (GitLab's CLI, from Homebrew, like gh) and gitlab-ci-local (runs
# a .gitlab-ci.yml here, in Docker or the shell); in install-all. install-gitlab-runner (opt-in, in no group, NOT
# in install-all: a system service that takes CI jobs from gitlab.com) pulls in install-gitlab. install-vue =
# create-vue and create-nuxt warmed in npx's cache (Vue, Pinia, Router and Nuxt are per project); in install-all.
if [[ "$FLAGS" =~ " install-gitlab-runner " ]]; then
    FLAGS+=" install-gitlab "
fi
# v91: Puppet and Chef, as their community builds: install-puppet = OpenVox (Vox Pupuli's fork of Puppet: puppet,
# facter) + OpenBolt; install-chef = Cinc Workstation (the free build of Chef Workstation). Both opt-in, in no group,
# NOT in install-all (Ansible, in install-iac, is the bundle's everyday configuration management).
# install-config-mgmt (opt-in) = both.
if [[ "$FLAGS" =~ " install-config-mgmt " ]]; then
    FLAGS+=" install-puppet install-chef "
fi

# 3. Dependency Guards
# Mobile frameworks require Rust and Node to be present
if [[ "$FLAGS" =~ " install-mobile " ]] || [[ "$FLAGS" =~ " install-tauri " ]] || [[ "$FLAGS" =~ " install-rn " ]]; then
    FLAGS+=" install-rust install-node "
fi
# v88: Symfony builds on Composer and the PHP extensions too (install-web). In install-all. Placed before
# the install-web guard so that guard sees the flag.
if [[ "$FLAGS" =~ " install-symfony " ]]; then
    FLAGS+=" install-web "
fi
# v87: Laravel builds on Composer and the PHP extensions (install-web, which needs Node for Vite). In
# install-all. Placed before the install-web guard so that guard sees the flag.
if [[ "$FLAGS" =~ " install-laravel " ]]; then
    FLAGS+=" install-web "
fi
# The Drupal hosting CLIs lean on Composer (Terminus plugins) and Drupal's PHP extensions: install-web,
# which needs Node. Placed before the install-web guard so that guard sees the flag.
if [[ "$FLAGS" =~ " install-drupal " ]]; then
    FLAGS+=" install-web "
fi
# Angular CLI and corepack (install-web) need Node
if [[ "$FLAGS" =~ " install-web " ]]; then
    FLAGS+=" install-node "
fi
# The TanStack CLI is an npm package and scaffolds with pnpm (corepack), so it needs Node too
if [[ "$FLAGS" =~ " install-tanstack " ]]; then
    FLAGS+=" install-node "
fi
# Godot's .NET editor builds C# projects with the .NET SDK. The templates flag implies the editors.
if [[ "$FLAGS" =~ " install-godot-templates " ]]; then
    FLAGS+=" install-godot "
fi
if [[ "$FLAGS" =~ " install-godot " ]]; then
    FLAGS+=" install-dotnet "
fi
# The Vercel CLI is an npm package; the Jev flag installs a Claude Code plugin (claude comes with Node)
# v89: wrangler (install-cloudflare, part of install-cloud) is an npm package too. install-cloudflared (opt-in,
# in no group, not in install-all: a tunnel puts local services on the public internet) needs nothing else.
if [[ "$FLAGS" =~ " install-vercel " ]] || [[ "$FLAGS" =~ " install-jev " ]] || [[ "$FLAGS" =~ " install-cloudflare " ]]; then
    FLAGS+=" install-node "
fi
# v91: Playwright and Cypress are npm packages, and Robot Framework's Browser library runs a Node side:
# all three need Node. install-bdd and install-selenium need nothing else (install-bdd adds a language's
# piece only where that language is installed).
if [[ "$FLAGS" =~ " install-playwright " ]] || [[ "$FLAGS" =~ " install-cypress " ]] || [[ "$FLAGS" =~ " install-robot " ]]; then
    FLAGS+=" install-node "
fi
# v91: gitlab-ci-local is an npm package, and the Vue scaffolders run through npx: both need Node.
if [[ "$FLAGS" =~ " install-gitlab " ]] || [[ "$FLAGS" =~ " install-vue " ]]; then
    FLAGS+=" install-node "
fi
# v77: the Ollama server is its own flag. install-gemma (so install-ecosystems and install-all) and the
# opt-in install-models (NOT in install-all: several GB of downloads) both need it.
# v80: so does install-ollama-containers (opt-in, in no group: Ollama reachable from Docker containers).
if [[ "$FLAGS" =~ " install-gemma " ]] || [[ "$FLAGS" =~ " install-models " ]] || [[ "$FLAGS" =~ " install-ollama-containers " ]]; then
    FLAGS+=" install-ollama "
fi
# =================================================================

has() { [[ "$FLAGS" =~ " $1 " ]]; }

QUICK=0; VERBOSE=0
has quick   && QUICK=1
has verbose && VERBOSE=1

# =================================================================
# ENVIRONMENT: reproduce what 'source ~/.bashrc' would give a fresh shell, without
# sourcing ~/.bashrc itself (it usually bails out in non-interactive shells).
# =================================================================
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.gems/bin:$HOME/.flutter/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew_after_system() {   # v68: move Homebrew's bin/sbin to the END of PATH (see the note in dev-setup)
    local p parts out=""
    IFS=: read -ra parts <<< "$PATH"
    for p in "${parts[@]}"; do
        case "$p" in /home/linuxbrew/.linuxbrew/bin|/home/linuxbrew/.linuxbrew/sbin|"") ;; *) out="${out:+$out:}$p" ;; esac
    done
    PATH="$out:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin"
}
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && brew_after_system
if [ -d "$HOME/.config/nvm" ]; then export NVM_DIR="$HOME/.config/nvm"; else export NVM_DIR="$HOME/.nvm"; fi
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" > /dev/null 2>&1
export GEM_HOME="$HOME/.gems"
export ANDROID_HOME="$HOME/.android/sdk"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"
# The installer wrote these two as literal paths; read them back the same way.
export JAVA_HOME="${JAVA_HOME:-$(grep -m1 '^export JAVA_HOME=' ~/.bashrc 2>/dev/null | cut -d'"' -f2)}"
export NDK_HOME="${NDK_HOME:-$(grep -m1 '^export NDK_HOME=' ~/.bashrc 2>/dev/null | cut -d'"' -f2)}"
export PUPPETEER_SKIP_DOWNLOAD=true
export PUPPETEER_EXECUTABLE_PATH="/usr/bin/google-chrome-stable"
export GEMMA_MODEL="gemma4:e2b-it-qat"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0   # v58: pnpm/yarn shims fetch without a prompt
export NG_CLI_ANALYTICS=false              # v58: no analytics prompt from ng new
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1   # v63: same as the installer's ~/.bashrc lines
export PATH="$PATH:$HOME/.dotnet/tools"
# v87: Composer's global bin (install-laravel's laravel command), at the end of PATH like setup's block.
for _cb in "$HOME/.config/composer/vendor/bin" "$HOME/.composer/vendor/bin"; do [ -d "$_cb" ] && export PATH="$PATH:$_cb"; done; unset _cb
# v91: OpenVox (install-puppet) and Cinc Workstation (install-chef), at the end of PATH like setup's blocks.
for _cb in /opt/puppetlabs/bin /opt/cinc-workstation/bin; do [ -d "$_cb" ] && export PATH="$PATH:$_cb"; done; unset _cb
SELF=$(readlink -f "$0")                   # v58: for the shellcheck self-check

# =================================================================
# TEST HARNESS
# =================================================================
PASS=0; FAIL=0; WARN=0; SKIP=0
FAILED=(); WARNED=()
LAST=pass
# v65: logs live in ./assets/logs next to the scripts, not in the home directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd || true)"
[ -n "$SCRIPT_DIR" ] || SCRIPT_DIR="$PWD"
export ASSETS="$SCRIPT_DIR/assets"
mkdir -p "$ASSETS/logs" "$ASSETS/downloads"
for old_log in "$HOME"/dev-test-*.log "$HOME"/dev-test-*.output; do
    [ -e "$old_log" ] && mv "$old_log" "$ASSETS/logs/" && echo "moved $(basename "$old_log") from ~ to $ASSETS/logs/"
done
LOG="$ASSETS/logs/dev-test-$(date +%Y%m%d-%H%M%S).log"
# v72: on disk, not in /tmp: Debian 13 mounts /tmp as tmpfs, so scratch there is held in RAM. Not
# under ./assets either: that folder has a '#' in its path, which Vite and other tools mishandle.
mkdir -p "$HOME/.cache/dev-test"
rm -rf "$HOME"/.cache/dev-test/run.* 2> /dev/null   # leftovers from a run that was killed (no EXIT trap)
rm -rf "$HOME"/.hermes/.dev-test-* 2> /dev/null      # v86: the same for the Hermes offline check's scratch home
export WORK; WORK=$(mktemp -d "$HOME/.cache/dev-test/run.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

if [ -t 1 ]; then GRN=$'\e[32m' RED=$'\e[31m' YEL=$'\e[33m' DIM=$'\e[2m' RST=$'\e[0m'; else GRN=; RED=; YEL=; DIM=; RST=; fi

section() { echo; echo "== $* =="; echo; echo "== $* ==" >> "$LOG"; }

show_tail() {  # last few lines of a failed/warned command, unless verbose already printed all of it
    [ "$VERBOSE" = 1 ] && return
    [ -n "$1" ] && printf '%s\n' "$1" | tail -n 3 | sed "s/^/      ${DIM}| /;s/\$/${RST}/"
}

# _run LABEL TIMEOUT_SECS KIND(check|warn) COMMAND
_run() {
    local label="$1" secs="$2" kind="$3" cmd="$4" out rc t0
    printf '  %-62s ' "$label"
    { echo "--- $label"; echo "\$ $cmd"; } >> "$LOG"
    t0=$SECONDS
    out=$(cd "$WORK" && timeout -k 5 "$secs" bash -c "$cmd" 2>&1 < /dev/null); rc=$?
    printf '%s\n--- exit %s (%ss)\n' "$out" "$rc" "$((SECONDS - t0))" >> "$LOG"
    [ "$VERBOSE" = 1 ] && [ -n "$out" ] && { echo; printf '%s\n' "$out" | sed 's/^/      | /'; printf '  %-62s ' ""; }
    local took=""; [ $((SECONDS - t0)) -ge 5 ] && took=" ${DIM}($((SECONDS - t0))s)${RST}"
    if [ $rc -eq 0 ]; then
        echo "${GRN}PASS${RST}$took"; PASS=$((PASS + 1)); LAST=pass
    elif [ "$kind" = warn ]; then
        echo "${YEL}WARN${RST}$took"; WARN=$((WARN + 1)); WARNED+=("$label"); LAST=warn
        show_tail "$out"
    else
        if [ $rc -eq 124 ]; then echo "${RED}FAIL${RST} (timed out after ${secs}s)"; else echo "${RED}FAIL${RST} (exit $rc)$took"; fi
        FAIL=$((FAIL + 1)); FAILED+=("$label"); LAST=fail
        show_tail "$out"
    fi
}

check() { _run "$1" "${3:-120}" check "$2"; }            # check LABEL CMD [TIMEOUT]
warn()  { _run "$1" "${3:-120}" warn  "$2"; }            # same, but a failure is only a WARN
slow()  {                                                # same as check, skipped under 'quick'
    if [ "$QUICK" = 1 ]; then
        printf '  %-62s %s\n' "$1" "${DIM}SKIP (quick)${RST}"; SKIP=$((SKIP + 1)); LAST=skip
    else
        _run "$1" "${3:-900}" check "$2"
    fi
}
slowwarn() { if [ "$QUICK" = 1 ]; then printf '  %-62s %s\n' "$1" "${DIM}SKIP (quick)${RST}"; SKIP=$((SKIP + 1)); LAST=skip; else _run "$1" "${3:-900}" warn "$2"; fi; }
hint()  { [ "$LAST" = fail ] || [ "$LAST" = warn ] && echo "      ${YEL}hint:${RST} $*"; }
# v92: is a package installed? Asked for the amd64 package first, then the plain name, then each further
# name given (an old name before a t64 rename). With Wine's 32-bit side (install-com) many libraries are
# installed for amd64 AND i386, and a plain 'dpkg -s NAME' then fails with "ambiguous package name",
# which v91 read as "missing". Exported, so the bash -c of every check can call it.
dpkg_has() {
    local p
    for p in "$@"; do
        dpkg-query -W -f='${Status}\n' "$p:amd64" 2> /dev/null | grep -q 'install ok installed' && return 0
        dpkg-query -W -f='${Status}\n' "$p" 2> /dev/null | grep -q 'install ok installed' && return 0
    done
    return 1
}
export -f dpkg_has
# v77: a fact worth seeing that is neither good nor bad (not counted): info LABEL TEXT
info()  { printf '  %-62s %s\n' "$1" "${DIM}INFO${RST} $2"; echo "--- $1: INFO $2" >> "$LOG"; }
# v92: a check that cannot run because an earlier one already failed for the same cause (counted as SKIP).
skipped() { printf '  %-62s %s\n' "$1" "${DIM}SKIP${RST} $2"; SKIP=$((SKIP + 1)); LAST=skip; echo "--- $1: SKIP $2" >> "$LOG"; }

echo "Testing Chromebook Linux provisioning (Version 93)... log: $LOG"
[ "$QUICK" = 1 ] && echo "(quick mode: slow functional tests will be skipped)"

# v68: say so when dev-init has not applied the secrets file yet. Filling in secrets.env logs
# nothing in by itself: dev-init is what feeds the tokens to gh / hf / the cloud CLIs and makes
# ~/.bashrc source the file. Until it has run, every login check below is an expected WARN.
INIT_PENDING=0
if [ -f "$HOME/.config/dev-init/secrets.env" ] && ! grep -qF 'dev-init/secrets.env' ~/.bashrc 2> /dev/null; then
    INIT_PENDING=1
elif [ ! -f "$HOME/.config/dev-init/secrets.env" ]; then
    INIT_PENDING=2
fi
init_pending_note() {
    case "$INIT_PENDING" in
        1) echo "${YEL}NOTE:${RST} secrets.env exists but dev-init has not applied it yet, so login and key checks show as WARN."
           echo "      Run ./dev-init-chromebook.sh with the same flags, then rerun this test." ;;
        2) echo "${YEL}NOTE:${RST} no ~/.config/dev-init/secrets.env yet: run ./dev-init-chromebook.sh once to create it,"
           echo "      fill it in, run it again to apply it. Until then login and key checks show as WARN." ;;
    esac
}
init_pending_note

# =================================================================
# BASE (always installed)
# =================================================================
section "Base system, Python tooling, SSH, Docker, Homebrew, Chrome (always)"

check "passwordless sudo (installer ran 'passwd -d')"      'sudo -n true'
check "apt is healthy"                                     'sudo -n apt-get check'
check "key apt packages present"                           'for p in build-essential git curl wget nano php-cli pipx python3-venv python3-pip ffmpeg x11-utils libgtk-3-dev libwebkit2gtk-4.1-dev librsvg2-dev; do dpkg_has "$p" || { echo "missing: $p"; exit 1; }; done'
# v93: a network whose IPv6 does not get out made downloads hang (Oct 4 2026); setup v93 then prefers IPv4.
cat > "$WORK/ipv6_check.sh" << 'IPV6_EOF'
f=/etc/gai.conf
if grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' "$f" 2> /dev/null; then
    echo "IPv4 is preferred ($f$( [ -f /etc/apt/apt.conf.d/99force-ipv4 ] && echo ", apt too"))"; exit 0
fi
v6=$(getent ahostsv6 dl.google.com 2> /dev/null | awk '$1 ~ /:/ && $1 !~ /^::ffff:/ { print $1; exit }')
v4=$(getent ahostsv4 dl.google.com 2> /dev/null | awk '{ print $1; exit }')
tcp() { timeout 6 bash -c 'exec 3<> "/dev/tcp/$0/443"' "$1" 2> /dev/null; }
[ -n "$v6" ] || { echo "no IPv6 address resolved for dl.google.com: nothing to wait on"; exit 0; }
if tcp "$v6"; then echo "IPv6 reaches dl.google.com ($v6)"; exit 0; fi
[ -n "$v4" ] && tcp "$v4" || { echo "SKIPPED: dl.google.com answers over neither IPv6 nor IPv4 (offline?)"; exit 0; }
echo "IPv6 does not get out ($v6 does not answer, IPv4 does) and IPv4 is not preferred: downloads can hang"; exit 1
IPV6_EOF
warn  "network: downloads do not wait on a broken IPv6 route"  'bash ipv6_check.sh' 30
hint  "rerun setup (v93 prefers IPv4 when IPv6 does not get out), or by hand: echo 'precedence ::ffff:0:0/96  100' | sudo tee -a /etc/gai.conf; echo 'Acquire::ForceIPv4 \"true\";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4"
# v52: Debian 13 renamed several runtime libs with a t64 suffix (the time_t transition); apt resolves the
# installer's old names to them via Provides, but dpkg -s only knows the real name. Accept either.
# v92: through dpkg_has (amd64 first), every missing one listed, and for libasound2 the shared library
# itself (ldconfig), which is what Chrome and the rest link against, whatever the package is called.
check "t64-renamed libs (libfuse2, libmagic1, libasound2, ...)" 'm=""; for p in libfuse2 libmagic1 libasound2 libcups2 libatk1.0-0 libatk-bridge2.0-0; do dpkg_has "${p}t64" "$p" || m="$m $p/${p}t64"; done; /sbin/ldconfig -p | grep -q "libasound.so.2 (libc6,x86-64)" || m="$m libasound.so.2(x86-64)"; [ -z "$m" ] || { echo "missing:$m"; exit 1; }; echo "all there (amd64)"'
# v65: nothing these scripts generate should sit loose in the home directory any more.
warn  "no script-generated files loose in ~"           '! ls ~/gemma_client.py ~/dev-test-*.log ~/google-chrome-stable_current_amd64.deb ~/packages.microsoft.gpg ~/windsurf-stable.gpg ~/fpc-laz_*.deb ~/fpc-src_*.deb ~/lazarus-project_*.deb 2> /dev/null | grep .'
hint  "~/gemma_client.py goes away when setup (v65 or later) runs with install-gemma; the rest can simply be deleted"
check "gcc compiles and runs a C program"                  'printf "#include <stdio.h>\nint main(){puts(\"hello from gcc\");return 0;}\n" > hello.c && gcc hello.c -o hello_c && ./hello_c | grep -q "hello from gcc"'
check "php-cli runs"                                       'php -r "echo PHP_VERSION;"'
check "python3 venv + pip work"                            'python3 -m venv venv-test && venv-test/bin/pip --version && venv-test/bin/python -c "import sys; print(sys.version)"'
# v68: venvs must sit on Debian's interpreter, not on a Homebrew keg that a later 'brew upgrade' removes.
check "existing venvs were built from /usr/bin/python3"    'bad=0; for d in ~/.antigravity-env ~/.lakehouse-env ~/.gemma-env ~/.agentic-env; do [ -f "$d/pyvenv.cfg" ] || continue; h=$(sed -n "s/^home = //p" "$d/pyvenv.cfg"); echo "$d: home = $h"; [ "$h" = /usr/bin ] || bad=1; done; exit $bad'
hint  "rerun the installer with the flag that owns that venv (install-antigravity / -lakehouse / -gemma / -agentic): v68 rebuilds it on Debian's Python"
check "pipx on PATH"                                       'pipx --version'
check "uv (installed via pipx)"                            'uv --version'
# v58: base CLI utilities
check "jq, shellcheck, direnv, htop, sqlite3, psql on PATH" 'jq --version && shellcheck --version && direnv version && htop --version && sqlite3 --version && psql --version'
check "jq evaluates a filter"                              'echo "{\"a\":1}" | jq -e ".a == 1"'
check "direnv hook line in ~/.bashrc"                      'grep -q "direnv hook bash" ~/.bashrc'
warn  "shellcheck finds no error-level issues in this script" "shellcheck -S error '$SELF'"
hint  "informational: only error-level findings are checked; run 'shellcheck' by hand for warnings"
check "SSH key ~/.ssh/id_ed25519 exists and is valid"      'ssh-keygen -l -f ~/.ssh/id_ed25519'
check "docker CLI"                                         'docker --version'
check "docker daemon reachable as ${USER:-$(id -un)}"                   'docker info > /dev/null'
hint  "run 'newgrp docker' or log out and back in; the installer added you to the docker group"
check "docker compose plugin"                              'docker compose version'
check "docker buildx plugin"                               'docker buildx version'
slow  "docker run hello-world"                             'docker run --rm hello-world | grep -q "Hello from Docker"' 300
check "Homebrew"                                           'brew --version'
# v68: Homebrew after the system directories (see dev-setup's header).
check ".bashrc has the v68 Homebrew block (brew last on PATH)"   'grep -q "^# >>> dev-setup homebrew >>>$" ~/.bashrc && ! grep -q "^eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\"$" ~/.bashrc'
hint  "rerun the installer (any flags): v68 replaces the bare brew shellenv line with a block that moves Homebrew to the end of PATH"
# v69: 'bash -i' under the harness was stopped by job control (it is not the terminal's foreground
# process group, so taking the tty raises SIGTTOU) and sat there until the 120 s timeout. setsid
# gives it a session with no controlling terminal; the inner timeout keeps a stuck ~/.bashrc short.
# v74: a new terminal must start silently. v68-v73 left "kubectl: command not found" on every one.
# env -i: start like a real new terminal (system PATH only), not with this script's PATH, which
# already contains Homebrew and would hide exactly this kind of ordering problem.
check "a new interactive shell starts without errors"      'e=$(timeout 30 setsid -w env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" SHELL=/bin/bash TERM=xterm-256color PATH=/usr/local/bin:/usr/bin:/bin bash -ic true < /dev/null 2>&1 > /dev/null | grep -v -e "cannot set terminal process group" -e "no job control in this shell"); [ -z "$e" ] || { echo "$e" | head -n 5; exit 1; }' 60
hint  "these lines come from ~/.bashrc; 'command not found' there usually means a line needs a tool whose PATH entry comes later in the file"
check "an interactive shell has /usr/bin ahead of Homebrew" 'p=$(timeout 30 setsid -w bash -ic "echo \"\$PATH\"" < /dev/null 2> /dev/null | tail -n 1); [ -n "$p" ] || { echo "could not read PATH from an interactive shell"; exit 1; }; echo "$p" | tr ":" "\n" | grep -n -x -e /usr/bin -e /home/linuxbrew/.linuxbrew/bin; u=$(echo "$p" | tr ":" "\n" | grep -n -x /usr/bin | head -n 1 | cut -d: -f1); b=$(echo "$p" | tr ":" "\n" | grep -n -x /home/linuxbrew/.linuxbrew/bin | head -n 1 | cut -d: -f1); [ -n "$u" ] && [ -n "$b" ] && [ "$u" -lt "$b" ]' 60
hint  "something later in ~/.bashrc puts Homebrew back in front; look for a second brew shellenv line"
check "python3 on PATH is Debian's"                        'p=$(command -v python3); echo "$p -> $(python3 --version)"; [ "$p" = /usr/bin/python3 ]'
warn  "no Homebrew command shadows a system one"           'n=0; for f in /home/linuxbrew/.linuxbrew/bin/*; do c=${f##*/}; [ -x "/usr/bin/$c" ] || continue; w=$(command -v "$c" 2> /dev/null); case "$w" in /home/linuxbrew/*) echo "$c -> $w"; n=$((n+1));; esac; done; echo "$n shadowed"; [ "$n" -eq 0 ]'
hint  "PATH order got undone for this run; compare with: bash -ic \"echo \\$PATH\""
check "brew shellenv line in ~/.bashrc"                    'grep -q "linuxbrew/bin/brew shellenv" ~/.bashrc'
check "brew gcc formula"                                   'brew list --formula gcc > /dev/null'
check "ddev"                                               'ddev --version'
check "gh (GitHub CLI)"                                    'gh --version'
warn  "gh is logged in"                                    'gh auth status'
hint  "run dev-init: it logs gh in with GH_TOKEN_ONCE from secrets.env (or interactively). Filling in secrets.env alone does not log anything in"
# v92: asked of GitHub itself, so a key added in the web UI counts (gh's token may lack the public_key scope).
warn  "GitHub accepts ~/.ssh/id_ed25519 (ssh -T git@github.com)" 'o=$(timeout 25 ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes git@github.com 2>&1); echo "$o" | grep -qi -e "successfully authenticated" -e "permission denied" || o=$(timeout 25 ssh -T -p 443 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes git@ssh.github.com 2>&1); echo "$o" | grep -v "^Warning: Permanently added" | head -n 2; echo "$o" | grep -qi "successfully authenticated"'
hint  "add ~/.ssh/id_ed25519.pub at https://github.com/settings/keys, or 'gh auth refresh -h github.com -s admin:public_key' and rerun dev-init (it uploads it)"
check "mkcert installed and local CA present"              'mkcert -CAROOT && [ -f "$(mkcert -CAROOT)/rootCA.pem" ]'
check "mkcert issues a localhost cert"                     'mkcert -cert-file t.pem -key-file t-key.pem localhost 2>&1 && [ -s t.pem ]'
check "Google Chrome"                                      'google-chrome-stable --version'
slow  "Chrome headless renders a page"                     'google-chrome-stable --headless=new --disable-gpu --no-sandbox --dump-dom "data:text/html,<title>ok</title>" | grep -q "<title>ok</title>"' 90

# =================================================================
# CONDITIONAL SECTIONS (same order as the installer)
# =================================================================

# Rust
if has install-rust; then
    section "Rust (install-rust)"
    check "rustc"                                          'rustc --version'
    check "cargo"                                          'cargo --version'
    check "cargo PATH line in ~/.bashrc"                   'grep -q ".cargo/bin" ~/.bashrc'
    check "wasm32-unknown-unknown target installed"        'rustup target list --installed | grep -qx wasm32-unknown-unknown'
    check "wasm-pack"                                      'wasm-pack --version'
    slow  "cargo new + build + run a binary"               'cargo new --quiet hello_rs && cd hello_rs && cargo run --quiet | grep -q "Hello, world!"' 600
    slow  "cargo build a lib for wasm32-unknown-unknown"   'cargo new --quiet --lib hello_wasm && cd hello_wasm && cargo build --quiet --target wasm32-unknown-unknown && ls target/wasm32-unknown-unknown/debug/*.rlib' 600
fi

# Go
if has install-go; then
    section "Go (install-go)"
    check "go"                                             'go version'
    check "go PATH line in ~/.bashrc"                      'grep -q "/usr/local/go/bin" ~/.bashrc'
    slow  "go run hello.go (first run compiles the runtime)" 'printf "package main\nimport \"fmt\"\nfunc main(){fmt.Println(\"hello from go\")}\n" > hello.go && go run hello.go | grep -q "hello from go"' 300
fi

# Node.js & AI coding agents
if has install-node; then
    section "Node.js, Claude Code, Codex, Gemini CLI, aider, Puppeteer (install-node)"
    # v65: setup points nvm's default alias at lts/* so new terminals get the Node (and its global
    # npm packages) that the installer just used. This script sources nvm the same way, so it compares the default alias
    # with the newest installed LTS: a mismatch means setup installed globals into one Node while
    # your terminals run another.
    warn  "nvm default alias is the newest installed LTS"   '. "$NVM_DIR/nvm.sh" && echo "default $(nvm version default), newest installed LTS $(nvm version "lts/*")" && [ "$(nvm version default)" = "$(nvm version "lts/*")" ]'
    hint  "nvm alias default \"lts/*\"; then 'nvm reinstall-packages <old version>' if tools went missing"
    check "nvm installed"                                  '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm --version'
    check "node LTS (>= 22)"                               'node --version && node --version | grep -qE "^v(2[2-9]|[3-9][0-9])\."'
    check "npm"                                            'npm --version'
    check "node runs JavaScript"                           'node -e "console.log(2+2)" | grep -qx 4'
    check "codex CLI"                                      'codex --version'
    check "gemini CLI"                                     'gemini --version'
    check "aider (uv tool, ~/.local/bin)"                  '[ -x ~/.local/bin/aider ] && aider --version'
    hint  "rerun the installer with install-node; v59 installs aider with 'uv tool install --python 3.12' (its pipx route needs Python <= 3.12)"
    # v59: the secrets template writes  export GEMINI_API_KEY=""  and '.+' matched those two quotes; require a non-empty value.
    warn  "gemini CLI signed in or GEMINI_API_KEY set"     '[ -s ~/.gemini/oauth_creds.json ] || [ -n "$GEMINI_API_KEY" ] || grep -qE "^export GEMINI_API_KEY=\"[^\"]+\"" ~/.config/dev-init/secrets.env 2> /dev/null'
    hint  "run 'gemini' once and sign in with Google, or set GEMINI_API_KEY in secrets.env"
    check "claude is the native install in ~/.local/bin"   '[ -x ~/.local/bin/claude ] && ~/.local/bin/claude --version'
    check "no stale npm-global @anthropic-ai/claude-code"  '! npm ls -g --depth=0 2>/dev/null | grep -q "@anthropic-ai/claude-code"'
    hint  "npm uninstall -g @anthropic-ai/claude-code"
    warn  "claude has been configured (~/.claude.json)"    '[ -s ~/.claude.json ]'
    hint  "run 'claude' once to log in"
    check "Puppeteer env vars in ~/.bashrc"                'grep -q PUPPETEER_EXECUTABLE_PATH ~/.bashrc && grep -q PUPPETEER_SKIP_DOWNLOAD ~/.bashrc'
    slow  "puppeteer installs w/o Chromium and drives system Chrome" 'mkdir pptr && cd pptr && npm init -y > /dev/null && npm install --silent --no-audit --no-fund puppeteer && [ ! -d ~/.cache/puppeteer/chrome ] ; node -e "const p=require(\"puppeteer\");(async()=>{const b=await p.launch({args:[\"--no-sandbox\"]});const pg=await b.newPage();await pg.setContent(\"<title>pptr-ok</title>\");console.log(await pg.title());await b.close();})().catch(e=>{console.error(e);process.exit(1)})" | grep -q pptr-ok' 600
fi

# Web tooling
if has install-web; then
    section "Web tooling: Angular CLI, corepack, Composer (install-web)"
    check "ng (Angular CLI)"                               'ng version 2>&1 | grep -q "Angular CLI"'
    check "corepack enabled (pnpm/yarn shims on PATH)"     'corepack --version && command -v pnpm && command -v yarn'
    check "COREPACK_ENABLE_DOWNLOAD_PROMPT in ~/.bashrc"   'grep -q COREPACK_ENABLE_DOWNLOAD_PROMPT ~/.bashrc'
    slow  "corepack shim fetches and runs pnpm"            'pnpm --version' 300
    check "composer (Debian package, system php-cli)"      'composer --version'
    # v59: what drupal/core's composer.json requires from the host PHP, plus the extras the installer adds.
    check "PHP extensions for Drupal (gd, dom, mbstring, pdo, intl, curl, zip)" 'for e in gd dom mbstring pdo pdo_sqlite pdo_mysql pdo_pgsql intl curl zip; do php -m | grep -qix "$e" || { echo "missing: $e"; exit 1; }; done'
    # v89: the clients of the shared cache services (install-cache): Drupal, Laravel and Symfony use these.
    check "PHP extensions for Redis and Memcached (redis, memcached)" 'for e in redis memcached; do php -m | grep -qix "$e" || { echo "missing: $e (php-$e)"; exit 1; }; echo "$e $(php -r "echo phpversion(\"$e\");")"; done'
    hint  "rerun setup with install-web: v89 adds php-redis and php-memcached"
    # ng new + npm install is the slow part (a few hundred MB of node_modules); the build itself is quick.
    slow  "ng new + npm install + ng build"                'ng new ngtest --defaults --skip-git --skip-install > /dev/null && cd ngtest && npm install --silent --no-audit --no-fund && ng build --configuration development > /dev/null && [ -f dist/ngtest/browser/index.html ]' 900
fi

# TanStack (CLI, Start, Router, Query) + Vitest + Playwright on the system Chrome
if has install-tanstack; then
    section "TanStack: CLI, Start, Router, Query; Vitest; Playwright (install-tanstack)"
    # The CLI is pre-1.0 (0.71 when this was written) and its flags move. Every create below passes
    # --no-intent: TanStack Intent's agent-skill setup wants an interactive terminal to confirm
    # permissions and otherwise reports an error (the create still exits 0). In your own projects
    # leave it on; it wires AGENTS.md / CLAUDE.md for Claude Code, Codex and Gemini CLI.
    check "tanstack CLI on PATH"                           'tanstack --version'
    hint  "rerun the installer with install-tanstack (npm install -g @tanstack/cli)"
    check "pnpm shim present (corepack)"                   'command -v pnpm && grep -q COREPACK_ENABLE_DOWNLOAD_PROMPT ~/.bashrc'
    check "add-on catalogue lists tanstack-query (local, JSON)" 'tanstack create --list-add-ons --framework React --json | jq -e "map(.id) | index(\"tanstack-query\") != null" > /dev/null'
    warn  "tanstack libraries --json (fetches from tanstack.com)" 'tanstack libraries --json | jq -e "length > 0" > /dev/null' 60
    hint  "network only: 'tanstack libraries', 'doc' and 'search-docs' call tanstack.com; scaffolding does not"
    # Vite watches the whole project tree. When the limit is too low hot reload silently stops firing.
    warn  "inotify watch limit is enough for Vite (>= 30000)" 'n=$(cat /proc/sys/fs/inotify/max_user_watches); echo "fs.inotify.max_user_watches = $n"; [ "$n" -ge 30000 ]'
    hint  "try 'sudo sysctl fs.inotify.max_user_watches=524288'; if the container refuses, set server.watch.usePolling in vite.config.ts for large projects"
    # Fixtures for the Playwright test, written here so the command below stays readable.
    mkdir -p "$WORK/ts-fixtures/e2e"
    cat > "$WORK/ts-fixtures/playwright.config.ts" <<'EOF'
import { defineConfig } from '@playwright/test'

// channel: 'chrome' drives the google-chrome-stable the base installer put on the machine, so
// Playwright never downloads its own Chromium into ~/.cache/ms-playwright.
export default defineConfig({
  testDir: './e2e',
  reporter: 'line',
  use: { channel: 'chrome', baseURL: 'http://localhost:3188' },
  webServer: {
    command: 'node_modules/.bin/vite dev --port 3188 --strictPort',
    url: 'http://localhost:3188',
    reuseExistingServer: false,
    timeout: 120000,
  },
})
EOF
    cat > "$WORK/ts-fixtures/e2e/smoke.spec.ts" <<'EOF'
import { test, expect } from '@playwright/test'

test('SSR page loads, hydrates, and the client router navigates', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('body')).toBeVisible()
  await page.locator('a[href="/about"]').first().click()
  await expect(page).toHaveURL(/\/about$/)
})
EOF
    # First run fills the pnpm store (~200 MB under ~/.local/share/pnpm); later scaffolds reuse it.
    slow  "tanstack create: Start app (SSR) with pnpm"     'tanstack create tsstart --package-manager pnpm --no-git --no-intent -y > create.log 2>&1 || { tail -n 20 create.log; exit 1; }; [ -f tsstart/src/routeTree.gen.ts ] && [ -d tsstart/node_modules ] && jq -e ".dependencies[\"@tanstack/react-start\"]" tsstart/package.json' 900
    hint  "'tanstack create --help' shows the current flags; --no-intent and --package-manager are the likeliest to have changed"
    slow  "Start app: vite build (client + server bundles)" 'cd tsstart && pnpm build > build.log 2>&1 || { tail -n 20 build.log; exit 1; }; ls dist/client > /dev/null && ls dist/server/server.js' 600
    slow  "Start app: dev server answers with server-rendered HTML" 'cd tsstart || exit 1; node_modules/.bin/vite dev --port 3187 --strictPort > dev.log 2>&1 & pid=$!; trap "kill $pid 2>/dev/null" EXIT; ok=1; for i in $(seq 1 90); do curl -fsS http://localhost:3187/ -o page.html 2>/dev/null && { ok=0; break; }; sleep 1; done; [ $ok = 0 ] && grep -qi "<html" page.html || { tail -n 20 dev.log; exit 1; }' 180
    hint  "port 3187 busy (a dev server left over from an interrupted run)? 'ss -ltnp | grep 3187', then kill that pid. In daily use 'pnpm dev' serves http://localhost:3000, which ChromeOS forwards to the browser"
    slow  "tanstack add tanstack-query, then rebuild"      'cd tsstart && tanstack add tanstack-query --forced > add.log 2>&1 < /dev/null; jq -e ".dependencies[\"@tanstack/react-query\"]" package.json || { tail -n 20 add.log; exit 1; }; pnpm build > build2.log 2>&1 || { tail -n 20 build2.log; exit 1; }' 600
    hint  "--forced skips the 'uncommitted changes, continue?' prompt, which exits 0 without doing anything when stdin is not a terminal"
    slow  "Vitest runs a unit test in the project"         'cd tsstart && pnpm add -D vitest > vitest.log 2>&1 || { tail -n 20 vitest.log; exit 1; }; printf "import { expect, test } from \"vitest\"\ntest(\"vitest runs in the scaffolded project\", () => { expect([1, 2, 3].map((n) => n * 2)).toEqual([2, 4, 6]) })\n" > src/smoke.test.ts && node_modules/.bin/vitest run --dir src' 600
    slow  "Playwright E2E on the system Chrome (no browser download)" 'cd tsstart && cp -r ../ts-fixtures/. . && pnpm add -D @playwright/test > pw.log 2>&1 || { tail -n 20 pw.log; exit 1; }; node_modules/.bin/playwright test' 600
    hint  "needs google-chrome-stable from the base section; Playwright passes --no-sandbox itself. Port 3188 busy? 'ss -ltnp | grep 3188'"
    slow  "tanstack create --router-only: SPA builds to dist/index.html" 'tanstack create tsspa --router-only --package-manager pnpm --no-git --no-intent -y > spa.log 2>&1 || { tail -n 20 spa.log; exit 1; }; cd tsspa && pnpm build > build.log 2>&1 || { tail -n 20 build.log; exit 1; }; [ -f dist/index.html ] && [ -f src/routeTree.gen.ts ]' 900
fi

# Drupal hosting CLIs (Pantheon, Acquia, Upsun) and DDEV global settings
if has install-drupal; then
    section "Drupal hosting: Terminus, Acquia CLI, Upsun CLI, DDEV globals (install-drupal)"
    # Every call is non-interactive with stdin closed: acli asks about telemetry on first run and would wait.
    check "terminus (Pantheon) runs under this PHP"         'command -v terminus && timeout 60 terminus --version --no-interaction 2> /dev/null | tail -n 1 | grep -i terminus'
    hint  "rerun the installer with install-drupal; both phars need PHP >= 8.2 (php-cli in the base section)"
    check "acli (Acquia) runs under this PHP"               'command -v acli && timeout 60 acli --version --no-interaction 2> /dev/null | tail -n 1 | grep -i "acquia cli"'
    check "upsun CLI"                                       'command -v upsun && timeout 60 upsun --version 2> /dev/null | tail -n 1 | grep -i upsun'
    check "rsync and a MariaDB client on the host"          'rsync --version | head -n 1 && { mariadb --version || mysql --version; }'
    check "bash completion files for all three CLIs"        'for c in terminus acli upsun; do [ -s ~/.local/share/bash-completion/completions/$c ] || { echo "missing: $c"; exit 1; }; done'
    warn  "Terminus rsync plugin installed"                  'l=$(timeout 60 terminus self:plugin:list --format=csv --fields=name --no-interaction 2>&1); echo "$l"; echo "$l" | grep -q terminus-rsync-plugin' 120
    hint  "terminus self:plugin:install pantheon-systems/terminus-rsync-plugin (needs Composer and packagist.org)"
    # v70: secrets are core in Terminus 4; the separate secrets-manager plugin is deprecated.
    check "Terminus has the built-in secret commands"       'timeout 60 terminus list --no-interaction 2> /dev/null | grep -E "^ +secret:site:(set|list)" | head -n 2; timeout 60 terminus list --no-interaction 2> /dev/null | grep -qE "^ +secret:site:set"' 120
    check "DDEV usage telemetry is off"                     'grep -q "^instrumentation_opt_in: false" ~/.ddev/global_config.yaml'
    hint  "ddev config global --instrumentation-opt-in=false"
    warn  "terminus is logged in to Pantheon"               'timeout 60 terminus auth:whoami --no-interaction 2> /dev/null | grep "@"' 90
    hint  "optional, only if you use Pantheon: machine token (dashboard.pantheon.io > Account > Machine tokens) into TERMINUS_MACHINE_TOKEN_ONCE in secrets.env, then run dev-init with install-drupal"
    warn  "acli is authenticated with Acquia"               'timeout 90 acli api:accounts:find --no-interaction > /dev/null 2>&1 && echo authenticated' 120
    hint  "optional, only if you use Acquia: API token (cloud.acquia.com > profile > API Tokens) into ACQUIA_API_KEY_ONCE / ACQUIA_API_SECRET_ONCE in secrets.env, then run dev-init with install-drupal"
    # Upsun is optional: only judged when a token or a saved login exists.
    check "upsun login (only if configured)"                '_u="$UPSUN_CLI_TOKEN"; [ -f ~/.config/dev-init/secrets.env ] && { set -a; . ~/.config/dev-init/secrets.env; set +a; }; export UPSUN_CLI_TOKEN="${_u:-$UPSUN_CLI_TOKEN}"; if [ -z "$UPSUN_CLI_TOKEN" ] && ! ls ~/.upsun-cli/.session* ~/.upsun/.session* > /dev/null 2>&1; then echo "SKIPPED: Upsun not configured (optional)"; exit 0; fi; timeout 90 upsun auth:info --no-auto-login --no-interaction' 120
    hint  "the token in UPSUN_CLI_TOKEN was rejected, or the saved login expired: 'upsun login'"
    warn  "DDEV global config has a platform token for ddev pull" 'grep -E "^ *- (TERMINUS_MACHINE_TOKEN|ACQUIA_API_KEY|ACQUIA_API_SECRET|UPSUN_CLI_TOKEN)=" ~/.ddev/global_config.yaml | sed "s/=.*/=(set)/"; grep -qE "^ *- (TERMINUS_MACHINE_TOKEN|ACQUIA_API_KEY|UPSUN_CLI_TOKEN)=" ~/.ddev/global_config.yaml'
    hint  "expected until you add a platform token: dev-init copies them from secrets.env into ~/.ddev/global_config.yaml, and 'ddev pull pantheon / acquia' needs them"
    check "DDEV global config is not world-readable once it holds tokens" 'f=~/.ddev/global_config.yaml; if grep -qE "^ *- (TERMINUS_MACHINE_TOKEN|ACQUIA_API_KEY|ACQUIA_API_SECRET|UPSUN_CLI_TOKEN)=" "$f"; then m=$(stat -c %a "$f"); echo "mode $m"; [ "$m" = 600 ]; else echo "no tokens in it"; fi'
    hint  "chmod 600 ~/.ddev/global_config.yaml (dev-init does this; ddev itself writes the file 644)"
    warn  "drupal.org recognises your SSH key (git.drupalcode.org)" 'timeout 25 ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 git@git.drupal.org 2>&1 | grep -i welcome' 40
    hint  "only needed to push contrib work: add ~/.ssh/id_ed25519.pub at https://git.drupalcode.org/-/user_settings/ssh_keys (no API for it, so dev-init cannot)"
fi

# Laravel (v87, install-laravel). Quick checks: PHP 8.3+, the extensions laravel/framework requires
# plus the ones apps and 'php artisan dev' use, the installer and the ~/.bashrc block. Slow checks build
# the skeleton with Composer (about 110 packages into ~/.cache/composer on the first run), run its
# migrations and tests, serve the welcome page, build the front end with Vite, and have the installer
# make a second app from the warm cache. Everything is built under $WORK.
if has install-laravel; then
    section "Laravel (install-laravel)"
    check "PHP 8.3 or newer (Laravel 13)"                   'php -r "exit(PHP_VERSION_ID >= 80300 ? 0 : 1);" && php --version | head -n 1'
    check "PHP extensions: framework (ctype filter hash mbstring openssl session tokenizer) + dom curl fileinfo pdo_sqlite pcntl bcmath" 'for e in ctype filter hash mbstring openssl session tokenizer dom curl fileinfo pdo_sqlite pcntl bcmath; do php -m | grep -qix "$e" || { echo "missing: $e"; exit 1; }; done'
    hint  "install-web adds most; php-bcmath comes from install-laravel; pcntl is built into Debian's php-cli (laravel/pail and the queue worker need it)"
    check "laravel installer on PATH (Composer's global bin)" 'command -v laravel && laravel --version 2> /dev/null | head -n 1'
    hint  "rerun setup with install-laravel (composer global require laravel/installer), then open a new terminal"
    check "Composer's global bin on PATH (the laravel block in ~/.bashrc)" 'grep -q "^# >>> dev-setup laravel >>>$" ~/.bashrc'
    mkdir -p "$WORK/laravel"
    slow  "composer create-project laravel/laravel (key, SQLite file, migrations)" 'cd "$WORK/laravel" && COMPOSER_NO_INTERACTION=1 composer create-project laravel/laravel lvapp --prefer-dist --no-progress > create.log 2>&1 || { tail -n 8 create.log; exit 1; }; cd lvapp && php artisan --version && [ -f database/database.sqlite ] && php artisan migrate:status --no-ansi | grep -c Ran' 900
    hint  "Composer needs repo.packagist.org; a failed platform check names the PHP extension that is missing"
    slow  "artisan: a model + migration of our own, then the tests" 'cd "$WORK/laravel/lvapp" 2> /dev/null || { echo "create the app first"; exit 1; }; php artisan make:model Note --migration --no-interaction > /dev/null && php artisan migrate --force --no-interaction --no-ansi | tail -n 2 && php artisan tinker --execute="App\\Models\\Note::query()->count();" > /dev/null || exit 1; php artisan test --no-ansi > test.log 2>&1; rc=$?; grep -E "Tests:" test.log || tail -n 5 test.log; [ $rc -eq 0 ]' 300
    slow  "php artisan serve answers the welcome page"      'cd "$WORK/laravel/lvapp" 2> /dev/null || { echo "create the app first"; exit 1; }; P=$(python3 -c "import socket; s=socket.socket(); s.bind((\"127.0.0.1\",0)); print(s.getsockname()[1])"); setsid php artisan serve --host=127.0.0.1 --port="$P" > serve.log 2>&1 < /dev/null & S=$!; trap "kill -TERM -- -$S 2> /dev/null" EXIT; for i in $(seq 1 30); do curl -fsS -o /dev/null "http://127.0.0.1:$P/" 2> /dev/null && break; sleep 0.5; done; c=$(curl -s -o page.html -w "%{http_code}" "http://127.0.0.1:$P/"); echo "HTTP $c from artisan serve on :$P"; [ "$c" = 200 ] && grep -qi "laravel" page.html' 120
    slow  "npm install + vite build (the front end)"        'cd "$WORK/laravel/lvapp" 2> /dev/null || { echo "create the app first"; exit 1; }; npm install --no-audit --no-fund --silent > npm.log 2>&1 || { tail -n 5 npm.log; exit 1; }; npm run build --silent > build.log 2>&1 || { tail -n 5 build.log; exit 1; }; ls public/build/manifest.json' 600
    hint  "the build downloads the welcome page's font (Instrument Sans) from fonts.bunny.net; offline, drop the fonts entry from vite.config.js"
    slowwarn "laravel new (the installer, from the warm Composer cache)" 'cd "$WORK/laravel" && laravel new lvnew --no-interaction --database=sqlite --phpunit --no-boost --no-node > new.log 2>&1 || { tail -n 8 new.log; exit 1; }; cd lvnew && php artisan --version' 600
    info  "DDEV and Sail" "ddev config --project-type=laravel --docroot=public (DDEV's MariaDB, https); Sail is per project (php artisan sail:install), heavy on 8 GB"
fi

# Symfony (v88, install-symfony). Quick checks: PHP 8.4+ and the extensions Symfony needs, the Symfony
# CLI and its requirements check. Slow checks: 'symfony new --webapp' (Composer, Flex recipes from
# GitHub, Stimulus and Turbo from jsDelivr), an entity + migration on SQLite through MakerBundle and
# Doctrine, a controller with its WebTestCase run by PHPUnit, the CLI's web server answering it, and
# 'symfony check:security' (WARN: it downloads the advisory database). Everything is built under $WORK.
if has install-symfony; then
    section "Symfony (install-symfony)"
    check "PHP 8.4 or newer (Symfony 8)"                    'php -r "exit(PHP_VERSION_ID >= 80400 ? 0 : 1);" && php --version | head -n 1'
    hint  "Symfony 7.4 LTS runs on PHP 8.2+ (symfony new <app> --version=lts)"
    check "PHP extensions: ctype iconv pcre session simplexml tokenizer + intl pdo_sqlite" 'for e in ctype iconv pcre session simplexml tokenizer intl pdo_sqlite; do php -m | grep -qix "$e" || { echo "missing: $e"; exit 1; }; done'
    hint  "install-web adds php-xml (simplexml), php-intl and php-sqlite3"
    check "symfony CLI (the .deb from its GitHub releases)" 'symfony version --no-ansi > v.txt 2>&1 || { cat v.txt; exit 1; }; head -n 1 v.txt; dpkg-query -W -f="symfony-cli \${Version} (.deb)\n" symfony-cli 2> /dev/null || echo "(not from the .deb: $(command -v symfony))"'
    hint  "rerun setup with install-symfony"
    check "symfony check:requirements"                      'symfony check:requirements --no-ansi | grep -E "\[OK\]|ready"'
    mkdir -p "$WORK/symfony"
    slow  "symfony new --webapp (Composer, Flex recipes, importmap)" 'cd "$WORK/symfony" && symfony new sfapp --webapp --no-git > new.log 2>&1 || { tail -n 8 new.log; exit 1; }; cd sfapp && php bin/console about --no-ansi | grep -E "Symfony  *[0-9]" | head -n 1 && [ -f config/packages/doctrine.yaml ]' 900
    hint  "Composer needs repo.packagist.org, Flex reads its recipes from raw.githubusercontent.com, and importmap fetches Stimulus and Turbo from cdn.jsdelivr.net"
    # DBAL 4 cannot 'CREATE DATABASE' on SQLite (doctrine:database:create fails there): the file appears on
    # the first connection, so the migration below is what creates it. doctrine:schema:validate writes its
    # report to stderr, hence the 2>&1 before the grep.
    slow  "SQLite: make:entity + make:migration + migrate, schema in sync" 'cd "$WORK/symfony/sfapp" 2> /dev/null || { echo "create the app first"; exit 1; }; echo "DATABASE_URL=\"sqlite:///%kernel.project_dir%/var/data_%kernel.environment%.db\"" > .env.local; php bin/console make:entity Note --no-interaction > make.log 2>&1 && php bin/console make:migration --no-interaction >> make.log 2>&1 || { tail -n 5 make.log; exit 1; }; php bin/console doctrine:migrations:migrate --no-interaction --no-ansi > migrate.log 2>&1 || { tail -n 5 migrate.log; exit 1; }; grep -o "Successfully migrated.*" migrate.log; php bin/console doctrine:schema:validate --no-ansi 2>&1 | grep -i "in sync"' 300
    slow  "make:controller --with-tests, then PHPUnit"      'cd "$WORK/symfony/sfapp" 2> /dev/null || { echo "create the app first"; exit 1; }; php bin/console make:controller Hello --with-tests --no-interaction > make.log 2>&1 || { tail -n 5 make.log; exit 1; }; php bin/phpunit --colors=never > phpunit.log 2>&1; rc=$?; tail -n 2 phpunit.log; [ $rc -eq 0 ]' 300
    slow  "symfony server:start -d answers /hello, then stops" 'cd "$WORK/symfony/sfapp" 2> /dev/null || { echo "create the app first"; exit 1; }; P=$(python3 -c "import socket; s=socket.socket(); s.bind((\"127.0.0.1\",0)); print(s.getsockname()[1])"); symfony server:start -d --no-tls --no-workers --port="$P" --no-ansi > serve.log 2>&1 || { tail -n 5 serve.log; exit 1; }; trap "symfony server:stop --no-ansi > /dev/null 2>&1" EXIT; for i in $(seq 1 30); do curl -fsS -o /dev/null "http://127.0.0.1:$P/hello" 2> /dev/null && break; sleep 0.5; done; c=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$P/hello"); echo "HTTP $c from symfony serve on :$P"; [ "$c" = 200 ]' 120
    slowwarn "symfony check:security (the app against the advisory database)" 'cd "$WORK/symfony/sfapp" 2> /dev/null || { echo "create the app first"; exit 1; }; timeout 120 symfony check:security --no-ansi 2>&1 | tail -n 3 | tee /dev/stderr | grep -qi "no packages have known vulnerabilities"' 180
    hint  "it downloads FriendsOfPHP/security-advisories from GitHub each run; a vulnerable package is named in the output"
    info  "DDEV and HTTPS" "ddev config --project-type=symfony --docroot=public; 'symfony server:ca:install' (optional) gives symfony serve https"
fi

# Apollo GraphQL (v90, install-graphql). Quick checks: the three binaries (the router must be v2), Rover's
# plugins, setup's ~/.bashrc block, and composition offline: two Federation 2 subgraphs that split a Film
# entity compose, and a conflicting pair is refused. Slow checks run the chain end to end on free ports,
# all under $WORK/graphql and stopped again: a stand-in subgraph (standard-library Python, serving both
# subgraphs' fields), the router in front of it, then apollo-mcp-server over the router, spoken to with
# curl (MCP initialize, tools/list, tools/call as JSON-RPC over streamable HTTP) and, with install-agentic,
# the MCP Inspector's CLI. No npm, Composer or account; APOLLO_KEY is unset for every step.
if has install-graphql; then
    section "Apollo GraphQL: Rover, Router v2, Apollo MCP Server (install-graphql)"
    mkdir -p "$WORK/graphql/operations"
    cat > "$WORK/graphql/films.graphql" << 'EOF'
extend schema @link(url: "https://specs.apollo.dev/federation/v2.7", import: ["@key"])

type Query {
  film(id: ID!): Film
}

type Film @key(fields: "id") {
  id: ID!
  title: String!
  year: Int
}
EOF
    cat > "$WORK/graphql/reviews.graphql" << 'EOF'
extend schema @link(url: "https://specs.apollo.dev/federation/v2.7", import: ["@key"])

type Query {
  topRated: [Film!]!
}

type Film @key(fields: "id") {
  id: ID!
  rating: Float
}
EOF
    # The conflicting pair: both subgraphs share Film.title, one as a String and one as an Int.
    cat > "$WORK/graphql/conflict-a.graphql" << 'EOF'
extend schema @link(url: "https://specs.apollo.dev/federation/v2.7", import: ["@key", "@shareable"])

type Query {
  film(id: ID!): Film
}

type Film @key(fields: "id") {
  id: ID!
  title: String! @shareable
}
EOF
    cat > "$WORK/graphql/conflict-b.graphql" << 'EOF'
extend schema @link(url: "https://specs.apollo.dev/federation/v2.7", import: ["@key", "@shareable"])

type Query {
  films: [Film!]!
}

type Film @key(fields: "id") {
  id: ID!
  title: Int @shareable
}
EOF
    cat > "$WORK/graphql/operations/GetFilm.graphql" << 'EOF'
# A film by id, with its rating from the reviews subgraph.
query GetFilm($id: ID!) {
  film(id: $id) {
    title
    year
    rating
  }
}
EOF
    # The stand-in subgraph: one port, two paths (/films and /reviews). It answers the root field with a
    # fixed film and an _entities fetch with a rating for each representation, as a real subgraph would.
    # The id is "f1", not "1": a numeric-looking id can reach a tool as a number (the Inspector CLI does that).
    cat > "$WORK/graphql/subgraph.py" << 'EOF'
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FILM = {"__typename": "Film", "id": "f1", "title": "Dev Test", "year": 2026}


class H(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        query, variables = body.get("query", ""), body.get("variables") or {}
        with open("subgraph-requests.log", "a") as log:
            log.write(self.path + " " + " ".join(query.split()) + "\n")
        if "_entities" in query:
            data = {"_entities": [{"__typename": "Film", "id": r.get("id"), "rating": 4.5}
                                  for r in variables.get("representations", [])]}
        elif "film" in query:
            data = {"film": FILM}
        else:
            data = None
        out = json.dumps({"data": data}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
    cat > "$WORK/graphql/graphql-check.sh" << 'CHECK_EOF'
# graphql-check.sh STEP: the install-graphql checks, run by dev-test from $WORK/graphql.
#   compose    films + reviews -> supergraph.graphql
#   conflict   conflict-a + conflict-b must be refused
#   router     stand-in subgraph + router: one query that needs both subgraphs, and the health endpoint
#   mcp        ... + apollo-mcp-server: initialize, tools/list and tools/call with curl (JSON-RPC)
#   inspector  ... + the MCP Inspector's CLI: tools/list and tools/call
set -u
cd "$(dirname "$0")" || exit 1
# Offline means offline: no GraphOS (an exported key would make the router and the MCP server report to
# it), no Rover self-update or plugin update, no telemetry, no licence prompt.
unset APOLLO_KEY APOLLO_GRAPH_REF
export APOLLO_ROVER_SKIP_UPDATE=1 APOLLO_TELEMETRY_DISABLED=true APOLLO_ELV2_LICENSE=accept
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
PIDS=()
cleanup() {
    local p
    for p in "${PIDS[@]}"; do kill -TERM -- "-$p" 2> /dev/null || kill -TERM "$p" 2> /dev/null; done
    sleep 1
    for p in "${PIDS[@]}"; do kill -KILL -- "-$p" 2> /dev/null || kill -KILL "$p" 2> /dev/null; done
}
trap cleanup EXIT
listening() { (exec 3<> "/dev/tcp/127.0.0.1/$1") 2> /dev/null; }

compose() {   # compose A B PORT OUT: rover supergraph compose, subgraphs routed to the stand-in on PORT
    cat > supergraph.yaml << EOF
subgraphs:
  ${1%%.*}:
    routing_url: http://127.0.0.1:$3/${1%%.*}
    schema:
      file: ./$1
  ${2%%.*}:
    routing_url: http://127.0.0.1:$3/${2%%.*}
    schema:
      file: ./$2
EOF
    rover supergraph compose --config supergraph.yaml --elv2-license accept --skip-update > "$4" 2> compose.log
}

start_chain() {   # stand-in subgraph, composition, router; sets SP, RP, HP
    SP=$(free_port); RP=$(free_port); HP=$(free_port)
    setsid python3 subgraph.py "$SP" > subgraph.log 2>&1 < /dev/null & PIDS+=($!)
    compose films.graphql reviews.graphql "$SP" supergraph.graphql || { echo "composition failed:"; tail -n 5 compose.log; exit 1; }
    # The health check gets its own free port: the default (8088) would collide with a second router.
    cat > router.yaml << EOF
supergraph:
  listen: 127.0.0.1:$RP
  introspection: true
health_check:
  enabled: true
  listen: 127.0.0.1:$HP
  path: /health
EOF
    setsid router --supergraph supergraph.graphql --config router.yaml > router.log 2>&1 < /dev/null & PIDS+=($!)
    local i
    for i in $(seq 1 60); do curl -fsS "http://127.0.0.1:$HP/health" > /dev/null 2>&1 && return 0; sleep 0.5; done
    echo "the router did not report healthy on :$HP"; tail -n 8 router.log; exit 1
}

gql() {   # gql PORT QUERY: POST a GraphQL query to the router
    curl -sS --max-time 20 -H 'Content-Type: application/json' \
        --data "$(python3 -c 'import json, sys; print(json.dumps({"query": sys.argv[1]}))' "$2")" "http://127.0.0.1:$1/"
}

start_mcp() {   # the router's API schema through 'rover graph introspect', then apollo-mcp-server; sets MP
    rover graph introspect "http://127.0.0.1:$RP/" > api.graphql 2> introspect.log \
        || { echo "rover graph introspect failed:"; tail -n 5 introspect.log; exit 1; }
    grep -q "rating" api.graphql || { echo "the introspected schema has no rating field"; exit 1; }
    MP=$(free_port)
    cat > mcp.yaml << EOF
endpoint: http://127.0.0.1:$RP/
transport:
  type: streamable_http
  address: 127.0.0.1
  port: $MP
schema:
  source: local
  path: ./api.graphql
operations:
  source: local
  paths:
    - ./operations
EOF
    setsid apollo-mcp-server mcp.yaml > mcp.log 2>&1 < /dev/null & PIDS+=($!)
    local i
    for i in $(seq 1 60); do listening "$MP" && return 0; sleep 0.5; done
    echo "apollo-mcp-server did not listen on :$MP"; tail -n 8 mcp.log; exit 1
}

SID=""; PV=""
rpc() {   # rpc JSON: one JSON-RPC message to /mcp; prints the body (plain JSON or SSE 'data:' lines)
    curl -sS --max-time 30 -D headers.txt -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' ${SID:+-H "Mcp-Session-Id: $SID"} \
        ${PV:+-H "MCP-Protocol-Version: $PV"} --data "$1" "http://127.0.0.1:$MP/mcp"
}

case "${1:-}" in
    compose)
        compose films.graphql reviews.graphql 4001 supergraph.graphql || { tail -n 8 compose.log; exit 1; }
        grep -qE 'join__graph\(name: *"films"' supergraph.graphql && grep -qE 'join__graph\(name: *"reviews"' supergraph.graphql \
            || { echo "the supergraph does not name both subgraphs"; head -n 20 supergraph.graphql; exit 1; }
        echo "supergraph.graphql names films and reviews ($(wc -l < supergraph.graphql) lines)"
        ;;
    conflict)
        if compose conflict-a.graphql conflict-b.graphql 4001 conflict.graphql; then
            echo "the conflicting pair composed; it should not have"; exit 1
        fi
        grep -oE 'FIELD_TYPE_MISMATCH|INVALID_FIELD_SHARING|E029' compose.log | sort -u | tr '\n' ' ' | grep . \
            || { echo "refused, but not with a composition error:"; tail -n 5 compose.log; exit 1; }
        echo "(refused, as it should be)"
        ;;
    router)
        start_chain
        r=$(gql "$RP" '{ film(id: "f1") { title year rating } }')
        echo "$r" | python3 -c 'import json, sys; f = json.load(sys.stdin)["data"]["film"]; assert f == {"title": "Dev Test", "year": 2026, "rating": 4.5}, f; print("router :'"$RP"' -> films + reviews:", f)' \
            || { echo "$r"; tail -n 5 router.log; exit 1; }
        grep -q '^/reviews .*_entities' subgraph-requests.log || { echo "the router never asked the reviews subgraph for the entity"; exit 1; }
        curl -fsS "http://127.0.0.1:$HP/health" | grep -q UP && echo "health :$HP UP"
        ;;
    mcp)
        start_chain; start_mcp
        r=$(rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"dev-test","version":"92"}}}')
        echo "$r" | grep -q '"serverInfo"' || { echo "no initialize result: $r"; tail -n 5 mcp.log; exit 1; }
        SID=$(grep -i '^mcp-session-id:' headers.txt | awk '{print $2}' | tr -d '\r')
        PV=$(echo "$r" | grep -oE '"protocolVersion":"[^"]+"' | head -n 1 | cut -d'"' -f4)
        echo "initialize: $(echo "$r" | grep -oE '"serverInfo":\{[^}]*\}' | head -n 1), protocol ${PV:-?}${SID:+, session}"
        rpc '{"jsonrpc":"2.0","method":"notifications/initialized"}' > /dev/null
        r=$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
        echo "$r" | grep -q '"name":"GetFilm"' || { echo "GetFilm is not in tools/list: $r"; tail -n 5 mcp.log; exit 1; }
        echo "tools/list: $(echo "$r" | grep -oE '"name":"[A-Za-z0-9_-]+"' | cut -d'"' -f4 | sort -u | tr '\n' ' ')"
        r=$(rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"GetFilm","arguments":{"id":"f1"}}}')
        echo "$r" | grep -q 'Dev Test' && echo "$r" | grep -q '4.5' || { echo "tools/call GetFilm: $r"; tail -n 5 mcp.log; exit 1; }
        echo "tools/call GetFilm: Dev Test, rating 4.5 (MCP -> router -> both subgraphs)"
        ;;
    inspector)
        start_chain; start_mcp
        r=$(mcp-inspector --cli "http://127.0.0.1:$MP/mcp" --transport http --method tools/list 2>&1)
        echo "$r" | grep -q '"GetFilm"' || { echo "$r" | tail -n 5; exit 1; }
        r=$(mcp-inspector --cli "http://127.0.0.1:$MP/mcp" --transport http --method tools/call --tool-name GetFilm --tool-arg id=f1 2>&1)
        echo "$r" | grep -q 'Dev Test' || { echo "$r" | tail -n 5; exit 1; }
        echo "Inspector CLI: tools/list has GetFilm, tools/call returns Dev Test"
        ;;
    *) echo "usage: graphql-check.sh compose|conflict|router|mcp|inspector"; exit 2 ;;
esac
CHECK_EOF
    check "rover (~/.local/bin, from its GitHub release)"  'rover --version 2>&1 | head -n 1 | grep -E "[0-9]+\.[0-9]+\.[0-9]+"'
    hint  "rerun setup with install-graphql"
    check "router is the Apollo Router v2"                 'command -v router | grep -q "/.local/bin/router$" || echo "note: router on PATH is $(command -v router)"; v=$(~/.local/bin/router --version 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -n 1); echo "Apollo Router $v"; [ "${v%%.*}" = 2 ]'
    hint  "rerun setup with install-graphql (it installs the newest v2 release; v1 is out of support)"
    check "apollo-mcp-server"                              'apollo-mcp-server --version 2>&1 | head -n 1 | grep -E "[0-9]+\.[0-9]+\.[0-9]+"'
    warn  "Rover plugins in ~/.rover/bin (supergraph v2, router)" 'ls ~/.rover/bin 2> /dev/null | grep -E "^supergraph-v2\." | sort -V | tail -n 1 | grep . && ls ~/.rover/bin | grep -E "^router-v" | sort -V | tail -n 1 | grep .'
    hint  "setup fetches them with 'rover install --plugin'; without them the first composition downloads one from rover.apollo.dev"
    check "~/.bashrc block (dev-setup graphql): telemetry off, ELv2 accepted" 'b=$(sed -n "/^# >>> dev-setup graphql >>>$/,/^# <<< dev-setup graphql <<<$/p" ~/.bashrc); echo "$b" | grep -q "^export APOLLO_TELEMETRY_DISABLED=" && echo "$b" | grep -q "^export APOLLO_ELV2_LICENSE=accept" && echo "$b" | grep "^export"'
    check "rover supergraph compose (two subgraphs share Film, offline)" 'bash "$WORK/graphql/graphql-check.sh" compose' 180
    hint  "offline it needs the supergraph plugin in ~/.rover/bin; compose.log in the test log has Rover's own message"
    check "composition refuses a conflicting pair (Film.title String vs Int)" 'bash "$WORK/graphql/graphql-check.sh" conflict' 180
    slow  "router v2: a query through both subgraphs (stand-in), health" 'bash "$WORK/graphql/graphql-check.sh" router' 180
    hint  "the lines above end with the router's own (router.log); a port or config error names the key it refused"
    slow  "apollo-mcp-server over the router: initialize, tools/list, tools/call (curl)" 'bash "$WORK/graphql/graphql-check.sh" mcp' 180
    hint  "the lines above end with the server's own (mcp.log); run 'apollo-mcp-server --version' and rerun setup with install-graphql if it is old"
    if has install-agentic && has install-node; then
        slow  "MCP Inspector CLI lists and calls the GraphQL tool" 'command -v mcp-inspector > /dev/null || { echo "mcp-inspector missing (install-agentic)"; exit 1; }; bash "$WORK/graphql/graphql-check.sh" inspector' 240
    fi
    # APOLLO_KEY belongs in Rover's profile (dev-init), not in the environment.
    warn  "APOLLO_KEY is not exported (GraphOS rate limit)" 'bad=0; if [ -n "${APOLLO_KEY:-}" ]; then echo "APOLLO_KEY is in this shell'"'"'s environment"; bad=1; fi; for f in ~/.bashrc ~/.config/dev-init/secrets.env; do grep -qE "^[[:space:]]*export[[:space:]]+APOLLO_KEY=\"?[^\" ]" "$f" 2> /dev/null && { echo "$f exports APOLLO_KEY"; bad=1; }; done; exit $bad'
    hint  "exported, every local router and MCP server reports to GraphOS, where the Free plan allows self-hosted routers 60 requests a minute: keep it unexported in secrets.env (dev-init gives it to Rover's profile)"
    info  "Apollo telemetry" "off: APOLLO_TELEMETRY_DISABLED in setup's ~/.bashrc block (Rover, the router)"
    info  "Elastic License v2" "accepted by setup for Rover's composition and router plugins (APOLLO_ELV2_LICENSE=accept)"
fi

# PowerShell
if has install-pwsh; then
    section "PowerShell (install-pwsh)"
    check "pwsh runs a command"                            'pwsh -NoProfile -NonInteractive -Command "\$PSVersionTable.PSVersion.ToString(); Write-Output pwsh-ok" | grep -q pwsh-ok'
fi

# C / C++ tooling
if has install-cpp; then
    section "C/C++ tooling: gdb, valgrind, cmake, ninja, clang, meson (install-cpp)"
    check "g++, clang, clang++, clangd, clang-format, clang-tidy on PATH" 'for t in g++ clang clang++ clangd clang-format clang-tidy; do command -v "$t" > /dev/null || { echo "missing: $t"; exit 1; }; done; g++ --version | head -n 1; clang --version | head -n 1'
    check "gdb, lldb, valgrind, cmake, ninja, meson, ccache, pkg-config on PATH" 'for t in gdb lldb valgrind cmake ninja meson ccache pkg-config; do command -v "$t" > /dev/null || { echo "missing: $t"; exit 1; }; done; cmake --version | head -n 1'
    # brew shellenv puts linuxbrew/bin ahead of /usr/bin. If a formula ever pulls in brew's own cmake,
    # pkgconf or an unversioned gcc, native builds start resolving against Homebrew's libraries
    # instead of Debian's -dev packages. WARN, because nothing is broken until you link something.
    warn  "system compilers/build tools not shadowed by Homebrew" 'bad=0; for t in cc gcc g++ make cmake ninja pkg-config; do p=$(command -v "$t"); case "$p" in /usr/bin/*|/bin/*|/usr/local/bin/*) ;; *) echo "$t -> $p"; bad=1;; esac; done; exit $bad'
    hint  "a Homebrew copy is first on PATH; call the /usr/bin one explicitly for native builds, or 'brew unlink <formula>'"
    check "pkg-config finds Debian's -dev packages (x11, gtk+-3.0)" 'pkg-config --exists x11 gtk+-3.0 && pkg-config --modversion gtk+-3.0'
    hint  "if the WARN above fired too, Homebrew's pkgconf is answering instead of /usr/bin/pkg-config"
    check "g++ compiles and runs a C++20 program"          'printf "#include <iostream>\n#include <ranges>\n#include <vector>\nint main(){std::vector<int> v{1,2,3,4};int s=0;for(int x: v|std::views::filter([](int i){return i%%2==0;}))s+=x;std::cout<<\"hello from c++20 \"<<s<<\"\\\\n\";}\n" > hello.cpp && g++ -std=c++20 -Wall -g hello.cpp -o hello_gpp && ./hello_gpp | grep -q "hello from c++20 6"'
    check "clang++ compiles and runs the same program"     'clang++ -std=c++20 -Wall hello.cpp -o hello_clangpp && ./hello_clangpp | grep -q "hello from c++20 6"'
    check "clang-format and clang-tidy process it"         'clang-format hello.cpp > /dev/null && clang-tidy hello.cpp --quiet -- -std=c++20 > /dev/null 2>&1'
    check "cmake + ninja configure, build and run a project" 'mkdir -p cmk && cd cmk && printf "cmake_minimum_required(VERSION 3.20)\nproject(hello CXX)\nset(CMAKE_CXX_STANDARD 20)\nadd_executable(hello ../hello.cpp)\n" > CMakeLists.txt && cmake -G Ninja -S . -B build > /dev/null && cmake --build build > /dev/null && build/hello | grep -q "hello from c++20"' 300
    check "meson + ninja build a C project"                'mkdir -p msn && cd msn && printf "#include <stdio.h>\nint main(void){puts(\"hello from meson\");return 0;}\n" > main.c && printf "project(\x27hello\x27, \x27c\x27)\nexecutable(\x27hello\x27, \x27main.c\x27)\n" > meson.build && meson setup build > /dev/null && meson compile -C build > /dev/null && build/hello | grep -q "hello from meson"' 300
    check "gdb runs the program to completion (ptrace works)" 'gdb -q -batch -ex run ./hello_gpp 2>&1 | grep -q "hello from c++20"'
    hint  "if ptrace is refused inside the container, check /proc/sys/kernel/yama/ptrace_scope"
    check "valgrind memcheck runs it clean"                'valgrind -q --error-exitcode=9 ./hello_gpp | grep -q "hello from c++20"' 300
    hint  "valgrind's memcheck needs libc6-dbg on Debian; the installer adds it"
fi

# Assembly
if has install-asm; then
    section "Assembly: nasm, yasm, GNU as (install-asm)"
    check "nasm, yasm, as, ld on PATH"                     'nasm -v && yasm --version | head -n 1 && as --version | head -n 1 && ld --version | head -n 1'
    check "nasm -f elf64 + ld: static syscall hello runs"  'printf "global _start\nsection .data\nmsg: db \"hello from nasm\", 10\nlen: equ \$ - msg\nsection .text\n_start:\n  mov rax, 1\n  mov rdi, 1\n  lea rsi, [rel msg]\n  mov rdx, len\n  syscall\n  mov rax, 60\n  xor rdi, rdi\n  syscall\n" > hello_nasm.asm && nasm -f elf64 hello_nasm.asm -o hello_nasm.o && ld hello_nasm.o -o hello_nasm && ./hello_nasm | grep -q "hello from nasm"'
    check "yasm assembles the same source"                 'yasm -f elf64 hello_nasm.asm -o hello_yasm.o && ld hello_yasm.o -o hello_yasm && ./hello_yasm | grep -q "hello from nasm"'
    check "GNU as (Intel syntax) via gcc -nostdlib runs"   'printf ".intel_syntax noprefix\n.globl _start\n.data\nmsg: .ascii \"hello from gas\\\\n\"\n.text\n_start:\n  mov rax, 1\n  mov rdi, 1\n  lea rsi, msg[rip]\n  mov rdx, 15\n  syscall\n  mov rax, 60\n  xor rdi, rdi\n  syscall\n" > hello_gas.s && gcc -nostdlib -static hello_gas.s -o hello_gas && ./hello_gas | grep -q "hello from gas"'
    check "nasm object links against libc through gcc"     'printf "global main\nextern puts\nsection .rodata\nmsg: db \"hello from nasm+libc\", 0\nsection .text\nmain:\n  sub rsp, 8\n  lea rdi, [rel msg]\n  call puts wrt ..plt\n  xor eax, eax\n  add rsp, 8\n  ret\nsection .note.GNU-stack noalloc noexec nowrite progbits\n" > hello_libc.asm && nasm -f elf64 hello_libc.asm -o hello_libc.o && gcc hello_libc.o -o hello_libc && ./hello_libc | grep -q "hello from nasm+libc"'
fi

# AArch64 cross toolchain (opt-in flag, not in install-all)
if has install-asm-arm; then
    section "AArch64 cross toolchain + qemu-user (install-asm-arm)"
    check "aarch64-linux-gnu-gcc / -as and qemu-aarch64 on PATH" 'aarch64-linux-gnu-gcc --version | head -n 1 && aarch64-linux-gnu-as --version | head -n 1 && qemu-aarch64 --version | head -n 1'
    check "AArch64 assembly hello runs under qemu-aarch64"  'printf ".globl _start\n.data\nmsg: .ascii \"hello from aarch64\\\\n\"\n.text\n_start:\n  mov x0, #1\n  adr x1, msg\n  mov x2, #19\n  mov x8, #64\n  svc #0\n  mov x0, #0\n  mov x8, #93\n  svc #0\n" > hello_a64.s && aarch64-linux-gnu-gcc -nostdlib -static hello_a64.s -o hello_a64 && qemu-aarch64 ./hello_a64 | grep -q "hello from aarch64"'
    check "cross-compiled C (dynamic) runs with -L sysroot" 'printf "#include <stdio.h>\nint main(){puts(\"hello from aarch64 c\");return 0;}\n" > hello_a64c.c && aarch64-linux-gnu-gcc hello_a64c.c -o hello_a64c && qemu-aarch64 -L /usr/aarch64-linux-gnu ./hello_a64c | grep -q "hello from aarch64 c"'
fi

# .NET SDK (C#, VB.NET)
if has install-dotnet; then
    section ".NET SDK: C# and VB.NET (install-dotnet)"
    check "dotnet CLI"                                     'dotnet --version'
    check ".NET 10 SDK listed"                             'dotnet --list-sdks && dotnet --list-sdks | grep -q "^10\."'
    hint  "rerun the installer with install-dotnet (dotnet-sdk-10.0 from packages.microsoft.com)"
    check "dotnet is the Microsoft .deb (/usr/bin/dotnet)" '[ "$(command -v dotnet)" = /usr/bin/dotnet ] && dpkg_has dotnet-sdk-10.0'
    check "packages-microsoft-prod repo configured"        'dpkg_has packages-microsoft-prod && ls /etc/apt/sources.list.d/ | grep -qi microsoft-prod'
    check "telemetry opt-out + tools PATH in ~/.bashrc"    'grep -q DOTNET_CLI_TELEMETRY_OPTOUT ~/.bashrc && grep -q ".dotnet/tools" ~/.bashrc'
    check "console template offers both C# and VB"         'dotnet new list console 2> /dev/null | grep -i "console" | grep -q "VB"'
    slow  "C#: dotnet new console + build + run"           'dotnet new console -o hello_cs > /dev/null && cd hello_cs && dotnet run | grep -q "Hello, World!"' 600
    # The VB template prints "Hello World!" (no comma), the C# one "Hello, World!"; accept either.
    slow  "VB.NET: dotnet new console -lang VB + build + run" 'dotnet new console -lang VB -o hello_vb > /dev/null && cd hello_vb && dotnet run | grep -qE "Hello,? World!"' 600
    slow  "VB app calling a C# class library (mixed-language build)" 'dotnet new classlib -o mixlib > /dev/null && printf "namespace MixLib;\npublic static class Greeter { public static string Hi() => \"hello from c# lib\"; }\n" > mixlib/Class1.cs && dotnet new console -lang VB -o mixapp > /dev/null && dotnet add mixapp reference mixlib > /dev/null && printf "Module Program\n    Sub Main()\n        Console.WriteLine(MixLib.Greeter.Hi())\n    End Sub\nEnd Module\n" > mixapp/Program.vb && dotnet run --project mixapp | grep -q "hello from c# lib"' 600
fi

# Java: JDK, Maven, Gradle
if has install-java; then
    section "Java: JDK, Maven, Gradle (install-java)"
    check "java and javac (default-jdk)"                   'java -version && javac -version'
    check "java and javac on PATH are Debian's JDK, not Homebrew's" 'for t in java javac jar; do p=$(readlink -f "$(command -v $t)"); echo "$t -> $p"; case "$p" in /usr/lib/jvm/*) ;; *) exit 1;; esac; done'
    hint  "brew's openjdk (a dependency of gradle and kotlin) links itself ahead of /usr/bin on Linux: 'brew unlink openjdk'"
    check "PATH javac and JAVA_HOME javac are the same release" '[ "$(javac -version 2>&1)" = "$("$JAVA_HOME/bin/javac" -version 2>&1)" ] || { javac -version; "$JAVA_HOME/bin/javac" -version; exit 1; }'
    check "JAVA_HOME in ~/.bashrc and javac there"         'grep -q "^export JAVA_HOME" ~/.bashrc && [ -x "$JAVA_HOME/bin/javac" ] && "$JAVA_HOME/bin/javac" -version'
    check "javac compiles and java runs a class"           'mkdir -p jv && cd jv && printf "public class Hello {\n  record Greeting(String who) {}\n  public static void main(String[] a) {\n    var g = new Greeting(\"java\");\n    System.out.println(\"hello from \" + g.who());\n  }\n}\n" > Hello.java && javac Hello.java && java Hello | grep -q "hello from java"'
    check "single-file source launch (java Hello.java)"    'cd jv && rm -f ./*.class && java Hello.java | grep -q "hello from java"'
    check "jar packages it and java -jar runs it"          'cd jv && javac Hello.java && jar --create --file hello.jar --main-class Hello ./*.class && java -jar hello.jar | grep -q "hello from java"'
    check "mvn (apt) runs on the Debian JDK"               'mvn -version && mvn -version | grep -q "/usr/lib/jvm"'
    check "gradle (brew)"                                  'gradle --version | grep -m1 "^Gradle"' 300
    hint  "Debian's own 'gradle' package is too old and deliberately not installed; the installer uses 'brew install gradle'"
    # brew's launcher falls back to brew's openjdk when JAVA_HOME is unset; WARN if that is what it picked.
    warn  "gradle runs on the Debian JDK (JAVA_HOME honoured)" 'maj=$(javac -version 2>&1 | grep -oE "[0-9]+" | head -n 1); gradle --version | grep -E "JVM" ; gradle --version | grep -E "JVM" | grep -q "/usr/lib/jvm\|[^0-9]$maj\."' 300
    hint  "open a new terminal or 'source ~/.bashrc' so JAVA_HOME is exported before gradle starts"
    # Both slow tests download from Maven Central into ~/.m2 / ~/.gradle on first run (a few hundred MB).
    slow  "maven: quickstart archetype + package + run"    'mvn -q -B archetype:generate -DgroupId=demo -DartifactId=mdemo -DarchetypeArtifactId=maven-archetype-quickstart -DarchetypeVersion=1.5 -DinteractiveMode=false && cd mdemo && mvn -q -B package && java -cp target/classes demo.App | grep -q "Hello World!"' 900
    slow  "gradle: init java-application + run (no daemon left behind)" 'maj=$("$JAVA_HOME/bin/javac" -version 2>&1 | grep -oE "[0-9]+" | head -n 1); mkdir -p gdemo && cd gdemo && gradle init --type java-application --dsl kotlin --test-framework junit-jupiter --project-name gdemo --package gdemo --java-version "$maj" --use-defaults --no-daemon -q > /dev/null && gradle run --no-daemon -q | grep -q "Hello World!"' 900
    hint  "'gradle init' options shift between major versions; run it by hand in an empty dir to see which flag it rejects"
fi

# Ruby & Jekyll
if has install-ruby; then
    section "Ruby & Jekyll (install-ruby)"
    check "ruby"                                           'ruby --version'
    check "GEM_HOME lines in ~/.bashrc"                    'grep -q "GEM_HOME" ~/.bashrc && grep -q ".gems/bin" ~/.bashrc'
    check "gem home is ~/.gems"                            'gem env gemhome | grep -q "$HOME/.gems"'
    check "bundler"                                        'bundle --version'
    check "jekyll"                                         'jekyll --version'
    check "jekyll-feed / jekyll-seo-tag gems"              'gem list | grep -q "^jekyll-feed " && gem list | grep -q "^jekyll-seo-tag "'
    slow  "jekyll new + bundle install + build"            'jekyll new --skip-bundle jk > /dev/null && cd jk && bundle install --quiet && bundle exec jekyll build --quiet && [ -f _site/index.html ]' 900
fi

# VS Code
if has install-vscode; then
    section "VS Code (install-vscode)"
    check "code"                                           'code --version'
    check "VS Code apt source"                             '[ -f /etc/apt/sources.list.d/vscode.list ] && [ -f /etc/apt/keyrings/packages.microsoft.gpg ]'
fi

# Cursor
if has install-cursor; then
    section "Cursor (install-cursor)"
    check "~/.local/bin/cursor is an executable AppImage"  '[ -x ~/.local/bin/cursor ] && file ~/.local/bin/cursor | grep -qE "ELF|executable|AppImage"'
    hint  "download the AppImage from cursor.com/download into ./assets, then rerun the installer with install-cursor"
    check "~/.local/bin PATH line in ~/.bashrc"            'grep -q ".local/bin" ~/.bashrc'
    # v52: 'cursor --version' launches the whole IDE (and dies headless on the GPU check).
    # --appimage-mount only FUSE-mounts the image and prints the mount point, which is the real test.
    check "ChromeOS launcher entry for Cursor"             'f=~/.local/share/applications/cursor.desktop; [ -f "$f" ] && grep -q "^Type=Application" "$f" && ! grep -q "^NoDisplay=true" "$f" && exe=$(sed -n "s/^Exec=\\(.*\\) %F\$/\\1/p" "$f") && echo "Exec=$exe" && [ -x "$exe" ]'
    hint  "rerun the installer with install-cursor; v66 writes ~/.local/share/applications/cursor.desktop"
    warn  "Cursor launcher icon extracted from the AppImage" '[ -s ~/.local/share/icons/cursor.png ] && file ~/.local/share/icons/cursor.png | grep -q "PNG image"'
    hint  "cosmetic: the entry falls back to a generic icon. Any PNG saved as ~/.local/share/icons/cursor.png fixes it"
    check "cursor AppImage runtime works"                  'cursor --appimage-offset | grep -qE "^[0-9]+$"' 30
    warn  "cursor AppImage FUSE-mounts"                    'timeout 15 cursor --appimage-mount | head -n 1 | grep -q "^/tmp/.mount_"' 30
    hint  "launch it from a Linux terminal with 'cursor &' to confirm the GUI comes up"

fi

# Windsurf
if has install-windsurf; then
    section "Windsurf (install-windsurf)"
    check "windsurf"                                       'windsurf --version'
    check "Windsurf apt source"                            '[ -f /etc/apt/sources.list.d/windsurf.list ]'
fi

# Lazarus
if has install-lazarus; then
    section "Lazarus / Free Pascal (install-lazarus)"
    check "fpc"                                            'fpc -iV'
    check "lazbuild"                                       'lazbuild --version'
    check "fpc source present (fpc-src)"                   'dpkg_has fpc-src'
    check "fpc compiles and runs a program"                'printf "program h;\nbegin writeln(\047hello from fpc\047); end.\n" > h.pas && fpc h.pas > /dev/null && ./h | grep -q "hello from fpc"'
    check "installers were cleaned up"                     '! ls "$ASSETS"/downloads/*.deb ~/fpc-laz*.deb ~/fpc-src*.deb ~/lazarus-project*.deb 2> /dev/null | grep -q .'
fi

# Flatpak & media tools
# Godot: standard + .NET editors
if has install-godot; then
    section "Godot: standard + .NET editors, Compatibility renderer (install-godot)"
    # Fixture projects, written here so the commands below stay readable. Both pin the
    # Compatibility renderer, the one that works on Crostini's OpenGL (virgl) stack.
    mkdir -p "$WORK/gd-gds" "$WORK/gd-cs"
    cat > "$WORK/gd-gds/project.godot" <<'EOF'
config_version=5

[application]
config/name="devtest"
run/main_scene="res://main.tscn"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
    cat > "$WORK/gd-gds/main.gd" <<'EOF'
extends Node2D
var frames := 0
func _ready() -> void:
    print("hello from gdscript on ", Engine.get_version_info().string)
func _process(_d: float) -> void:
    frames += 1
    if frames == 20:
        print("rendered 20 frames: method=", RenderingServer.get_current_rendering_method(), " adapter=", RenderingServer.get_video_adapter_name())
        get_tree().quit(0)
EOF
    cat > "$WORK/gd-gds/main.tscn" <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://main.gd" id="1"]

[node name="Main" type="Node2D"]
script = ExtResource("1")
EOF
    cat > "$WORK/gd-gds/export_presets.cfg" <<'EOF'
[preset.0]

name="Linux"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/devtest.x86_64"

[preset.0.options]

binary_format/embed_pck=true

[preset.1]

name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="web/index.html"

[preset.1.options]

variant/thread_support=false
EOF
    cat > "$WORK/gd-cs/project.godot" <<'EOF'
config_version=5

[application]
config/name="devtestcs"
run/main_scene="res://main.tscn"

[dotnet]
project/assembly_name="devtestcs"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
    cat > "$WORK/gd-cs/Main.cs" <<'EOF'
using Godot;

public partial class Main : Node2D
{
    public override void _Ready()
    {
        GD.Print("hello from c# on godot " + Engine.GetVersionInfo()["string"]);
        GetTree().Quit(0);
    }
}
EOF
    cat > "$WORK/gd-cs/main.tscn" <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Main.cs" id="1"]

[node name="Main" type="Node2D"]
script = ExtResource("1")
EOF
    check "godot and godot-mono launchers report a version" 'godot --version && godot-mono --version | grep -q mono'
    hint  "rerun the installer with install-godot; the launchers live in ~/.local/bin"
    check "both editors are the same release, under ~/.local/opt/godot/current" '[ -x ~/.local/opt/godot/current/standard/godot.x86_64 ] && [ -d ~/.local/opt/godot/current/mono/GodotSharp ] && [ "$(godot --version | cut -d. -f1-3)" = "$(godot-mono --version | cut -d. -f1-3)" ]'
    check "launchers default to the OpenGL driver"          'grep -q "rendering-driver" ~/.local/bin/godot && grep -q "rendering-driver" ~/.local/bin/godot-mono'
    check "app-drawer entries for both editors"            '[ -f ~/.local/share/applications/godot.desktop ] && [ -f ~/.local/share/applications/godot-mono.desktop ] && grep -q "^Exec=.*/godot-mono " ~/.local/share/applications/godot-mono.desktop'
    # Headless editor runs sometimes abort on exit ("singleton is null", exit 134) after doing their
    # work, a Godot shutdown bug seen with 4.7.2. So imports and exports below are judged by what
    # they produce, not by their exit code.
    slow  "GDScript project imports and runs headless"     'cd gd-gds && { godot --headless --path . --import > import.log 2>&1 || true; }; godot --headless --path . 2>&1 | tee run.log | grep -q "hello from gdscript" || { tail -n 15 import.log run.log; exit 1; }' 300
    warn  "a display is available for the rendering test"   '[ -n "$DISPLAY$WAYLAND_DISPLAY" ] && echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY"'
    hint  "run the test from the ChromeOS Terminal app (not over ssh) so Godot can open a window"
    # The check that matters on a Chromebook: a real window, the OpenGL driver, 20 rendered frames.
    # A small Godot window flashes up for a second.
    slow  "renders 20 frames with the Compatibility renderer (OpenGL via virgl)" 'if [ -z "$DISPLAY$WAYLAND_DISPLAY" ]; then echo "SKIPPED: no display"; exit 0; fi; cd gd-gds && godot --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 320x240 2>&1 | tee render.log | grep -E "OpenGL API|rendered 20 frames"; grep -q "rendered 20 frames: method=gl_compatibility" render.log' 180
    hint  "see the log: the 'OpenGL API ... Using Device' line says which GPU path Godot got. Crashes here are the virgl path; try the previous Godot release with GODOT_VERSION=<x.y.z>-stable"
    warn  "rendering is GPU-accelerated (virgl), not software (llvmpipe)" 'if [ ! -f gd-gds/render.log ]; then echo "no render log (no display?)"; exit 1; fi; grep "adapter=" gd-gds/render.log; ! grep -qi "llvmpipe\|softpipe" gd-gds/render.log'
    hint  "software rendering: the three checks below say where it comes from"
    # v68: v67's first run on a Tiger Lake Chromebook rendered with llvmpipe. These narrow it down:
    # no render node = the VM was started without a GPU; a render node but llvmpipe under X11 =
    # the Xwayland path is unaccelerated while native Wayland may still be.
    warn  "the Linux VM exposes a GPU (/dev/dri/renderD*)"    'ls -l /dev/dri/ 2>&1; ls /dev/dri/renderD* > /dev/null 2>&1'
    hint  "no /dev/dri: set chrome://flags/#crostini-gpu-support to Enabled, then SHUT DOWN Linux (right-click Terminal > Shut down Linux) or reboot; restarting the terminal is not enough"
    # v69: the suspected cause of v68's llvmpipe result. renderD128 is root:render 0660 and the user
    # was only in 'video'. It is sommelier, started by the systemd user session at login, that
    # needs the node (it gives Xwayland and Wayland clients their GPU device), so the group only
    # helps after the whole container restarts; changing one app's groups proves nothing.
    warn  "sommelier (X11/Wayland bridge) runs with the render group" 'pid=$(pgrep -u "$USER" -f sommelier | head -n 1); [ -n "$pid" ] || { echo "no sommelier process"; exit 1; }; gid=$(getent group render | cut -d: -f3); echo "sommelier pid $pid groups: $(grep ^Groups: /proc/$pid/status | cut -f2-) (render gid $gid)"; grep ^Groups: /proc/$pid/status | tr "\t " "\n\n" | grep -qx "$gid"'
    hint  "sommelier started before you were in the render group: shut Linux down (right-click Terminal > Shut down Linux) and reopen it"
    warn  "this session can open the render node (groups video + render)" 'for g in video render; do if id -nG | tr " " "\n" | grep -qx "$g"; then echo "$g: active"; elif getent group "$g" | grep -qw "$USER"; then echo "$g: configured, NOT active in this session"; else echo "$g: not a member"; fi; done; r=$(ls /dev/dri/renderD* 2> /dev/null | head -n 1); [ -n "$r" ] && [ -r "$r" ] && [ -w "$r" ]'
    hint  "not a member: rerun the installer (v69 adds both groups) or 'sudo usermod -aG video,render $USER'. Configured but not active: shut Linux down (right-click Terminal > Shut down Linux) and reopen it. There is no shortcut: 'sg render' or 'newgrp' only changes the app, while sommelier (the X11/Wayland bridge that hands apps the GPU) was started at login with the old groups"
    # eglinfo -p gbm talks to /dev/dri directly: it answers "is there a GPU at all" without needing
    # a window, so it still works when DISPLAY is unset or Xwayland is not running.
    warn  "the GPU itself is usable (eglinfo, GBM, no window needed)" 'r=$(eglinfo -B -p gbm 2>&1 | grep -i -m2 "renderer\|OpenGL vendor"); echo "${r:-no GBM output}"; [ -n "$r" ] && ! echo "$r" | grep -qi "llvmpipe\|softpipe\|failed"' 60
    hint  "hardware here but llvmpipe in Godot means the windowing path (Xwayland) is the problem, not the GPU"
    warn  "X11 apps get a hardware GL renderer (glxinfo)"    'if [ -z "$DISPLAY" ]; then echo "SKIPPED: no DISPLAY"; exit 0; fi; r=$(glxinfo -B 2> /dev/null | grep -i "OpenGL renderer"); echo "$r"; [ -n "$r" ] && ! echo "$r" | grep -qi "llvmpipe\|softpipe"' 60
    hint  "'unable to open display' means no X server for this shell (DISPLAY unset or Xwayland not running): run the test from the ChromeOS Terminal app, not over ssh. Otherwise compare with the GBM and Wayland results"
    slowwarn "Godot on native Wayland gets a hardware renderer" 'if [ -z "$WAYLAND_DISPLAY" ]; then echo "SKIPPED: no WAYLAND_DISPLAY"; exit 0; fi; cd gd-gds && godot --path . --display-driver wayland --rendering-driver opengl3 --audio-driver Dummy --resolution 320x240 2>&1 | tee render-wayland.log | grep -E "OpenGL API|rendered 20 frames"; grep -q "rendered 20 frames" render-wayland.log && ! grep -qi "llvmpipe\|softpipe" render-wayland.log' 180
    hint  "if this one is accelerated and the X11 one is not, launch the editor with: godot --display-driver wayland (or GODOT_DISPLAY_DRIVER in the launcher)"
    # C#: the editor normally generates the .csproj/.sln from its menu; written by hand here. The
    # target framework follows the installed SDK, and Godot's bundled packages are added as a local
    # NuGet source next to nuget.org.
    slow  "C# project builds with godot-mono and runs headless" 'cd gd-cs && ver=$(godot-mono --version | cut -d. -f1-3) && tf="net$(dotnet --version | cut -d. -f1).0" && printf "<Project Sdk=\"Godot.NET.Sdk/%s\">\n  <PropertyGroup>\n    <TargetFramework>%s</TargetFramework>\n    <EnableDynamicLoading>true</EnableDynamicLoading>\n  </PropertyGroup>\n</Project>\n" "$ver" "$tf" > devtestcs.csproj && printf "<?xml version=\"1.0\"?>\n<configuration><packageSources><add key=\"godot-bundled\" value=\"%s\" /></packageSources></configuration>\n" "$HOME/.local/opt/godot/current/mono/GodotSharp/Tools/nupkgs" > NuGet.config && dotnet new sln -n devtestcs > /dev/null && dotnet sln add devtestcs.csproj > /dev/null && echo "Godot.NET.Sdk $ver, $tf" && { godot-mono --headless --path . --build-solutions --quit > build.log 2>&1 || true; }; ls .godot/mono/temp/bin/Debug/devtestcs.dll > /dev/null 2>&1 || { echo "godot-mono --build-solutions produced no assembly; dotnet build says:"; dotnet build devtestcs.csproj 2>&1 | grep -E "error|Build succeeded" | sort -u | head -n 8; exit 1; }; godot-mono --headless --path . 2>&1 | tee run.log | grep -q "hello from c#" || { tail -n 15 run.log; exit 1; }' 900
    hint  "needs the .NET SDK (install-dotnet, pulled in by install-godot). If the build log rejects the target framework, Godot.NET.Sdk does not support this SDK major yet: install the SDK it names"
fi

# Godot export templates (opt-in flag, not in install-all)
if has install-godot-templates; then
    section "Godot export templates (install-godot-templates)"
    check "templates match both editors' versions"         'v=$(godot --version | cut -d. -f1-4); ls ~/.local/share/godot/export_templates/; [ -f ~/.local/share/godot/export_templates/$v/version.txt ] && [ -f ~/.local/share/godot/export_templates/$v.mono/version.txt ]'
    hint  "rerun the installer with install-godot-templates (about 1.2 GB per flavour)"
    slow  "exports a Linux build that runs"                'cd gd-gds && mkdir -p build && { godot --headless --path . --export-release Linux build/devtest.x86_64 > export-linux.log 2>&1 || true; }; [ -x build/devtest.x86_64 ] || { grep -v "^\[" export-linux.log | tail -n 15; exit 1; }; build/devtest.x86_64 --headless 2>&1 | grep -q "hello from gdscript"' 600
    slow  "exports a Web build (index.html + wasm)"        'cd gd-gds && mkdir -p web && { godot --headless --path . --export-release Web web/index.html > export-web.log 2>&1 || true; }; [ -s web/index.html ] && [ -s web/index.wasm ] || { grep -v "^\[" export-web.log | tail -n 15; exit 1; }' 600
fi

if has install-media; then
    section "Flatpak, HandBrake, KDiff3 (install-media)"
    check "flatpak"                                        'flatpak --version'
    check "flathub remote"                                 'flatpak remotes | grep -q flathub'
    check "HandBrake installed"                            'flatpak list --app | grep -q fr.handbrake.ghb'
    check "KDiff3 installed"                               'flatpak list --app | grep -q org.kde.kdiff3'
fi

# Google Antigravity
if has install-antigravity; then
    section "Google Antigravity (install-antigravity)"
    check "~/.antigravity-env has google-antigravity"      '~/.antigravity-env/bin/pip show google-antigravity > /dev/null'
    # The remote install.sh puts the CLI at ~/.local/bin/agy.
    check "agy (Antigravity CLI) in ~/.local/bin"           '[ -x ~/.local/bin/agy ] && agy --version'

    # v73: the graphical app lives under /opt and is installed from a tarball you put in ./assets.
    warn  "Antigravity IDE or desktop app installed (from a tarball in ./assets)" 'ok=1; for p in /opt/antigravity-ide/current/antigravity-ide /opt/antigravity/current/antigravity; do [ -x "$p" ] && { echo "$p"; ok=0; }; done; exit $ok'
    hint  "download the Linux x64 tarball from antigravity.google/download into ./assets, then rerun the installer with install-antigravity"
    check "Antigravity GUI install is launchable (if installed)" 'n=0; for pair in "/opt/antigravity-ide antigravity-ide" "/opt/antigravity antigravity"; do set -- $pair; [ -x "$1/current/$2" ] || continue; n=1; s="$1/current/chrome-sandbox"; if [ -f "$s" ]; then m=$(stat -c "%U:%G:%a" "$s"); echo "$s $m"; [ "$m" = root:root:4755 ] || exit 1; fi; [ -L "$HOME/.local/bin/$2" ] && [ -f "$HOME/.local/share/applications/$2.desktop" ] || { echo "missing command link or launcher entry for $2"; exit 1; }; echo "$2: command link and launcher entry present"; done; [ $n = 1 ] || echo "SKIPPED: no GUI install"'
    hint  "rerun the installer with install-antigravity: it sets chrome-sandbox to root:root 4755 and writes the launcher entry"
fi

# Mobile base: Android SDK / JDK / NDK (same trigger as the installer)
if has install-mobile || has install-tauri || has install-rn || has install-flutter || has install-android-native; then
    section "Android SDK, JDK, NDK (mobile base)"
    check "java (default-jdk)"                             'java -version'
    check "JAVA_HOME in ~/.bashrc and javac there"         'grep -q "^export JAVA_HOME" ~/.bashrc && [ -x "$JAVA_HOME/bin/javac" ] && "$JAVA_HOME/bin/javac" -version'
    check "ANDROID_HOME lines in ~/.bashrc"                'grep -q "^export ANDROID_HOME" ~/.bashrc'
    check "sdkmanager (cmdline-tools/latest)"              'sdkmanager --version'
    check "adb (platform-tools)"                           'adb --version'
    check "an Android platform is installed"               'ls -d "$ANDROID_HOME"/platforms/android-*'
    check "build-tools installed"                          'ls -d "$ANDROID_HOME"/build-tools/*/'
    check "NDK installed and NDK_HOME points at it"        'grep -q "^export NDK_HOME" ~/.bashrc && [ -x "$NDK_HOME/ndk-build" ]'
    check "all SDK licenses accepted"                      '(yes 2> /dev/null || true) | sdkmanager --licenses 2>&1 | grep -q "All SDK package licenses accepted"' 180
    # v56: the Android runtime isn't auto-discovered from Crostini; connect to it first. 'arc' is the
    # ChromeOS hostname for the container (100.115.92.2:5555 is the same thing). The first connect
    # pops an "Allow USB debugging?" dialog on the ChromeOS side that has to be accepted once.
    warn  "adb sees this Chromebook's Android runtime"     'adb connect arc > /dev/null 2>&1 || adb connect 100.115.92.2:5555 > /dev/null 2>&1; adb devices; adb devices | tail -n +2 | grep -qE "\bdevice$"' 30
    hint  "enable ADB debugging (ChromeOS Settings -> About ChromeOS -> Linux development environment -> Develop Android apps), restart, then accept the 'Allow USB debugging?' dialog that 'adb connect arc' triggers; 'unauthorized' in the list above means the dialog is still pending"

    if has install-mobile || has install-tauri; then
        section "Tauri mobile (install-tauri)"
        check "tauri CLI (npm build)"                      'tauri --version'
        check "Android Rust targets installed"             'for t in aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android; do rustup target list --installed | grep -qx "$t" || { echo "missing: $t"; exit 1; }; done'
        check "librsvg2-dev (tauri build prerequisite)"    'pkg-config --modversion librsvg-2.0'
        slowwarn "tauri info (environment report)"         'tauri info' 300
    fi

    if has install-mobile || has install-rn; then
        section "React Native / Expo (install-rn)"
        check "eas CLI"                                    'eas --version'
    fi

    if has install-mobile || has install-flutter; then
        section "Flutter (install-flutter)"
        check "~/.flutter is a git checkout on stable"     'git -C ~/.flutter rev-parse --abbrev-ref HEAD | grep -qx stable'
        check "flutter PATH line in ~/.bashrc"             'grep -q ".flutter/bin" ~/.bashrc'
        check "Linux desktop toolchain (clang, cmake, ninja)" 'clang++ --version && cmake --version && ninja --version'
        slow  "flutter --version (first run downloads the Dart SDK)" 'flutter --version' 900
        slowwarn "flutter doctor"                          'flutter doctor -v' 600
        hint  "doctor complaints about Android Studio / cmdline-tools are informational unless you use those features"
    fi
fi

# Native Android (Kotlin)
if has install-android-native; then
    section "Native Android / Kotlin (install-android-native)"
    check "Android Studio at /opt/android-studio"          '[ -x /opt/android-studio/bin/studio.sh ] || [ -x /opt/android-studio/bin/studio ]'
    # v70: Wayland mode dims the focused IDE window on ChromeOS; setup pins the X11 toolkit.
    # v71: judge the setting that wins. Android Studio reads the install-wide file and then the per-user
    # file, so a per-user line overrides the install-wide one (the install-wide file ships
    # '-Dawt.toolkit.name=auto', which means Wayland when available). v70's check demanded
    # XToolkit in the install-wide file and failed on a machine where only the per-user file
    # had been fixed by hand, although the IDE was running on X11.
    check "Android Studio runs on the X11 toolkit (effective VM option)" 'u=$(grep -h "^-Dawt.toolkit.name=" ~/.config/Google/AndroidStudio*/studio64.vmoptions 2> /dev/null | tail -n 1); g=$(grep -h "^-Dawt.toolkit.name=" /opt/android-studio/bin/studio64.vmoptions 2> /dev/null | tail -n 1); echo "install-wide: ${g:-(none)}   per-user: ${u:-(none)}"; e=${u:-$g}; echo "effective: ${e:-(none: runtime default, Wayland)}"; [ "$e" = "-Dawt.toolkit.name=XToolkit" ]'
    warn  "Android Studio install-wide VM options pinned too (fresh profiles)" 'grep -H "^-Dawt.toolkit.name=" /opt/android-studio/bin/studio64.vmoptions; grep -q "^-Dawt.toolkit.name=XToolkit" /opt/android-studio/bin/studio64.vmoptions'
    hint  "only matters for a new Android Studio profile (after an upgrade to a new version): rerun the installer with install-android-native"
    hint  "rerun the v52 installer with install-android-native (it scrapes the current -cros.deb link), or pass ANDROID_STUDIO_URL=<...-cros.deb>"
    check "java on PATH is still Debian's JDK (brew openjdk unlinked)" 'p=$(readlink -f "$(command -v java)"); echo "$p"; case "$p" in /usr/lib/jvm/*) ;; *) exit 1;; esac'
    hint  "'brew unlink openjdk'; kotlinc keeps working, it uses JAVA_HOME"
    check "kotlinc (brew)"                                 'kotlinc -version 2>&1 | grep -qi kotlinc'
    slow  "kotlinc compiles and runs a program"            'printf "fun main() { println(\"hello from kotlin\") }\n" > h.kt && kotlinc h.kt -include-runtime -d h.jar 2> /dev/null && java -jar h.jar | grep -q "hello from kotlin"' 300
fi

# v80: a small Lazarus / Free Pascal SQLdb program for the Firebird and InterBase checks. It opens a
# database through TIBConnection (Firebird's and InterBase's shared client API) and counts the system
# tables, so it works against any database of either. Arguments: DATABASE [LIBRARY] [USER] [PASSWORD];
# with LIBRARY a TSQLDBLibraryLoader loads that client library first, without it SQLdb uses FPC's own
# list of library names. Compiled once per run, only when fpc is present (install-lazarus).
build_sqldb_probe() {
    [ -x "$WORK/fbsqldb" ] && return 0
    cat > "$WORK/fbsqldb.pas" << 'EOF'
program fbsqldb;
{$mode objfpc}{$H+}
uses SysUtils, sqldb, sqldblib, IBConnection;
var
  Loader: TSQLDBLibraryLoader;
  Conn: TIBConnection;
  Tran: TSQLTransaction;
  Q: TSQLQuery;
begin
  Loader := nil;
  try
    if (ParamCount >= 2) and (ParamStr(2) <> '') then
    begin
      Loader := TSQLDBLibraryLoader.Create(nil);
      Loader.ConnectionType := 'Firebird';
      Loader.LibraryName := ParamStr(2);
      Loader.Enabled := True;
    end;
    Conn := TIBConnection.Create(nil);
    Conn.DatabaseName := ParamStr(1);
    if ParamCount >= 3 then Conn.UserName := ParamStr(3) else Conn.UserName := 'SYSDBA';
    if ParamCount >= 4 then Conn.Password := ParamStr(4);
    Tran := TSQLTransaction.Create(nil);
    Tran.DataBase := Conn;
    Conn.Transaction := Tran;
    Q := TSQLQuery.Create(nil);
    Q.DataBase := Conn;
    Q.Transaction := Tran;
    Conn.Open;
    Q.SQL.Text := 'SELECT COUNT(*) FROM RDB$RELATIONS';
    Q.Open;
    WriteLn('sqldb-ok: ', Q.Fields[0].AsInteger, ' tables in ', ParamStr(1));
    Q.Close;
    Conn.Close;
  except
    on E: Exception do
    begin
      WriteLn('sqldb-error: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
EOF
    check "Free Pascal compiles an SQLdb (TIBConnection) program" 'fpc -O1 -vew fbsqldb.pas > fpc.log 2>&1 || { tail -n 15 fpc.log; exit 1; }; [ -x fbsqldb ]' 180
    hint  "the fcl-db units come with Lazarus's fpc-laz package (install-lazarus)"
}

# Database connectivity
if has install-db; then
    section "Database connectivity, Firebird 4 (install-db)"
    check "unixODBC (odbcinst -j)"                         'odbcinst -j'
    check "Microsoft apt repo configured"                  '[ -f /etc/apt/sources.list.d/microsoft-prod.list ]'
    check "ODBC Driver 18 for SQL Server registered"       'odbcinst -q -d | grep -q "ODBC Driver 18 for SQL Server"'
    check "MDBTools ODBC driver registered"                'odbcinst -q -d | grep -qi mdb'
    check "pxlib (Paradox)"                                'dpkg_has pxlib1 && dpkg_has pxlib-dev'
    check "libpq-dev (PostgreSQL client)"                  'pkg-config --modversion libpq'
    check "libmariadb-dev (MariaDB/MySQL client)"          'pkg-config --modversion libmariadb 2> /dev/null || mariadb_config --version'
    check "libsqlite3-dev"                                 'pkg-config --modversion sqlite3'
    # v80: Firebird 4, embedded (no server). Apply the lock-directory block setup writes when the
    # default directory is not writable for this user, the way a new terminal would.
    fb_blk=$(sed -n '/^# >>> dev-setup firebird >>>$/,/^# <<< dev-setup firebird <<<$/p' ~/.bashrc 2> /dev/null)
    [ -n "$fb_blk" ] && eval "$fb_blk"
    unset fb_blk
    info  "Firebird lock directory" "${FIREBIRD_LOCK:-default (/tmp/firebird)}"
    # v81: firebird-utils too: in Debian's multi-version packaging it holds the /usr/bin command names.
    check "Firebird 4 packages (client, dev, tools, embedded engine)" 'for p in libfbclient2 firebird-dev firebird-utils firebird4.0-utils firebird4.0-server-core; do dpkg_has "$p" || { echo "missing: $p"; exit 1; }; done; ls /usr/lib/*/libfbclient.so*'
    hint  "rerun setup with install-db (v80 adds Firebird; v81 names firebird-utils, which holds isql-fb and gbak)"
    check "isql-fb and gbak are Firebird's (unixODBC keeps 'isql')" 'command -v isql-fb && command -v gbak && isql-fb -z < /dev/null 2>&1 | head -n 1 | grep -iE "firebird|LI-V"'
    cat > "$WORK/fb.sql" << EOF
CREATE DATABASE '$WORK/fbtest.fdb' DEFAULT CHARACTER SET UTF8;
CREATE TABLE airports (code CHAR(3) NOT NULL PRIMARY KEY, name VARCHAR(60), delay_min INTEGER);
INSERT INTO airports VALUES ('DCA', 'Reagan National', 5);
INSERT INTO airports VALUES ('IAD', 'Dulles', 42);
INSERT INTO airports VALUES ('BWI', 'Baltimore', 0);
COMMIT;
SELECT 'rows=' || COUNT(*) FROM airports;
QUIT;
EOF
    printf "SELECT 'rows=' || COUNT(*) FROM airports;\nQUIT;\n" > "$WORK/fb_count.sql"
    check "Firebird embedded: create a database, write, read (no server)" 'rm -f fbtest.fdb; ISC_USER=SYSDBA timeout 60 isql-fb -q -b -i fb.sql 2>&1 | tee fb.out; grep -q "rows=3" fb.out' 90
    hint  "'lock files directory' in the output: rerun setup with install-db (it probes and adds FIREBIRD_LOCK to ~/.bashrc when needed)"
    check "Firebird gbak: backup, restore, read the copy"   'rm -f fbtest.fbk fbrest.fdb; ISC_USER=SYSDBA gbak -b fbtest.fdb fbtest.fbk && ISC_USER=SYSDBA gbak -c fbtest.fbk fbrest.fdb && ISC_USER=SYSDBA isql-fb -q -i fb_count.sql fbrest.fdb | grep -q "rows=3"' 90
    if command -v fpc > /dev/null 2>&1; then
        build_sqldb_probe
        check "Lazarus SQLdb opens the Firebird file (loader: libfbclient.so.2)" 'ISC_USER=SYSDBA ./fbsqldb "$WORK/fbtest.fdb" libfbclient.so.2' 60
        hint  "the file comes from the embedded check above; if that passed, see the sqldb-error line"
        warn  "Lazarus SQLdb without a loader (FPC's built-in library names)" 'ISC_USER=SYSDBA ./fbsqldb "$WORK/fbtest.fdb"' 60
        hint  "FPC's own library names did not match this system (firebird-dev's unversioned libfbclient.so usually does): give your Lazarus programs a TSQLDBLibraryLoader (ConnectionType 'Firebird', LibraryName 'libfbclient.so.2'); dev-demo's db/firebird shows one"
    fi
fi

# Extra ODBC drivers
if has install-db-extra; then
    section "Extra ODBC drivers: SQLite, PostgreSQL, MariaDB, DuckDB (install-db-extra)"
    check "[SQLite3] ODBC driver registered"               'odbcinst -q -d | grep -q "^\[SQLite3\]"'
    check "[PostgreSQL Unicode] ODBC driver registered"    'odbcinst -q -d | grep -q "^\[PostgreSQL Unicode\]"'
    check "[MariaDB Unicode] ODBC driver registered"       'odbcinst -q -d | grep -q "^\[MariaDB Unicode\]"'
    check "[DuckDB] ODBC driver registered and .so present" 'odbcinst -q -d | grep -q "^\[DuckDB\]" && [ -f /opt/duckdb-odbc/libduckdb_odbc.so ]'
    check "[CSV] DSN in ~/.odbc.ini"                       'grep -q "^\[CSV\]" ~/.odbc.ini'
    check "ODBC tracing is NOT globally enabled"           '! grep -qiE "^Trace *= *(yes|1|on)" /etc/odbcinst.ini'
    printf 'id,name\n1,a\n2,b\n3,c\n' > "$WORK/t.csv"
    printf "SELECT count(*) AS n FROM '%s';\n" "$WORK/t.csv" > "$WORK/csv.sql"
    check "isql CSV queries a CSV file through DuckDB"     'isql -b CSV < csv.sql | grep -q 3'
    printf 'SELECT 42 AS answer;\n' > "$WORK/sqlite.sql"
    check "SQLite3 ODBC driver answers a query"            'isql -b -k "Driver=SQLite3;Database=$WORK/t.sqlite" < sqlite.sql | grep -q 42'
fi

# InterBase (v80, install-interbase; opt-in, not in install-all; since v82 part of install-db-server)
if has install-interbase; then
    section "InterBase (install-interbase, part of install-db-server)"
    # SYSDBA's password: the environment, then secrets.env, then InterBase's documented default.
    IB_PW=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${INTERBASE_SYSDBA_PASSWORD:-}"' _ "$HOME/.config/dev-init/secrets.env" 2> /dev/null)
    export IB_PW="${INTERBASE_SYSDBA_PASSWORD:-${IB_PW:-masterkey}}"
    # v81: what the ~/.bashrc block gives a new terminal. The client finds interbase.msg through it,
    # so a failing check below shows InterBase's own error text instead of a bare status code.
    export INTERBASE="${INTERBASE:-/opt/interbase}"
    # v83 review: install-db-server pulls this flag in, so it is often given without an InterBase
    # download in ./assets. Setup then only prints a NOTICE; here that is one WARN, not a row of FAILs.
    # With an installer in ./assets (or an existing /opt/interbase), the checks below apply as before.
    IB_INSTALLER=$(find "$ASSETS" -maxdepth 5 -type f \( -name 'ib_install_linux_x86_64.bin' -o -name 'install_linux_x86_64.sh' -o -iname '*interbase*.zip' \) 2> /dev/null | head -n 1)
    if [ ! -x /opt/interbase/bin/isql ] && [ -z "$IB_INSTALLER" ]; then
        warn  "InterBase installed (needs the Embarcadero download in ./assets)" 'echo "not installed, and no InterBase installer in $ASSETS"; false'
        hint  "optional: download InterBase for Linux (the free Developer Edition) from embarcadero.com, put the zip in ./assets, then rerun setup with install-interbase. SQL Server and Oracle do not need it"
    else
        check "InterBase installed in /opt/interbase (isql, gbak, libgds.so)" '[ -x /opt/interbase/bin/isql ] && [ -x /opt/interbase/bin/gbak ] && ls -l /opt/interbase/lib/libgds.so*'
        hint  "put the InterBase download from Embarcadero (the zip, or ib_install_linux_x86_64.bin) in ./assets, then rerun setup with install-interbase"
        check "InterBase programs find all their shared libraries (ldd)" 'm=$(for f in /opt/interbase/bin/isql /opt/interbase/bin/gbak /opt/interbase/bin/ibserver /opt/interbase/bin/ibguard /opt/interbase/bin/ibmgr /opt/interbase/lib/libgds.so; do [ -e "$f" ] && ldd "$f" 2> /dev/null | grep "not found" | sed "s|^|${f##*/}: |"; done); [ -z "$m" ] || { echo "$m" | sort -u; exit 1; }'
        hint  "InterBase is built for older distributions: 'apt-file search <missing name>' finds the Debian package that provides it"
        check "ib-isql / ib-gbak / ib-mgr in ~/.bashrc, InterBase kept off PATH" 'blk=$(sed -n "/^# >>> dev-setup interbase >>>$/,/^# <<< dev-setup interbase <<<$/p" ~/.bashrc); [ -n "$blk" ] || { echo "no dev-setup interbase block in ~/.bashrc"; exit 1; }; eval "$blk"; declare -F ib-isql ib-gbak ib-mgr || exit 1; case "$(command -v isql)" in /opt/interbase/*) echo "isql on PATH is the InterBase one"; exit 1 ;; esac'
        hint  "rerun setup with install-interbase; the block is rewritten on every run"
        # v92: a server whose processes run but which never listens (started before registration, then
        # restarted by ibguard) is told apart from one that is simply stopped.
        warn  "InterBase server listens on port 3050"            'if (exec 3<> /dev/tcp/127.0.0.1/3050) 2> /dev/null; then echo listening; exit 0; fi; p=$(pids=$(pgrep -x "ibguard|ibserver" | paste -sd, -); [ -n "$pids" ] && ps -o pid=,pcpu=,etime=,comm= -p "$pids"); if [ -n "$p" ]; then echo "STUCK: InterBase processes run but nothing listens on 3050:"; echo "$p"; echo "stop and restart: ib-server stop; ib-server start   (register first: dev-init with install-interbase)"; else echo "not running: ib-server start (after registering: dev-init with install-interbase)"; fi; exit 1'
        IB_UP=0; [ "$LAST" = pass ] && IB_UP=1
        hint  "an unregistered Developer Edition does not start: run dev-init with install-interbase (License Manager, then it starts the server)"
        # v92: a scratch database the test creates, queries and drops, not examples/database/employee.gdb,
        # which the Server install set does not include. In /tmp: the server (root) owns the file.
        cat > "$WORK/ib_scratch.sh" << 'IBS_EOF'
#!/bin/bash
# ib_scratch.sh [sqldb]: create localhost:/tmp/devtest-<pid>.ib as SYSDBA, read a row back through isql
# (or, with 'sqldb', through the Free Pascal SQLdb probe), then drop the database again.
# v93: no -q. InterBase's isql exits 1 with -q even when CREATE DATABASE worked (Oct 4 2026: without -q it
# exits 0), so v92 reported a working server as failing and left its scratch file behind. The file the
# server writes counts as success too.
isql=/opt/interbase/bin/isql
db="/tmp/devtest-$$.ib"
printf "CREATE DATABASE 'localhost:%s' USER 'SYSDBA' PASSWORD '%s';\nCREATE TABLE devtest (n INTEGER);\nINSERT INTO devtest VALUES (42);\nCOMMIT;\nQUIT;\n" "$db" "$IB_PW" > ibs-create.sql
out=$(timeout 60 "$isql" -i ibs-create.sql 2>&1); rc=$?; echo "$out"
if [ "$rc" != 0 ] && ! sudo -n test -f "$db" 2> /dev/null && [ ! -f "$db" ]; then
    echo "could not create $db (server not running, or SYSDBA's password is not '$IB_PW')"; exit 1
fi
rc=0
if [ "${1:-}" = sqldb ]; then
    ./fbsqldb "localhost:$db" /opt/interbase/lib/libgds.so SYSDBA "$IB_PW" || rc=1
else
    printf 'SELECT n FROM devtest;\nQUIT;\n' > ibs-query.sql
    out=$(timeout 60 "$isql" -user SYSDBA -password "$IB_PW" -i ibs-query.sql "localhost:$db" 2>&1); echo "$out"
    echo "$out" | grep -qw 42 || rc=1
fi
printf "CONNECT 'localhost:%s' USER 'SYSDBA' PASSWORD '%s';\nDROP DATABASE;\nQUIT;\n" "$db" "$IB_PW" > ibs-drop.sql
timeout 60 "$isql" -i ibs-drop.sql > /dev/null 2>&1
if sudo -n test -f "$db" 2> /dev/null || [ -f "$db" ]; then echo "note: could not drop $db (sudo rm -f $db)"; fi
exit $rc
IBS_EOF
        if [ "$IB_UP" = 1 ]; then
            warn  "InterBase creates, queries and drops a scratch database as SYSDBA" 'bash ib_scratch.sh' 120
            hint  "SYSDBA's password is not masterkey any more: put it in INTERBASE_SYSDBA_PASSWORD in secrets.env"
        else
            skipped "InterBase creates, queries and drops a scratch database as SYSDBA" "(the server is not listening, see above)"
        fi
        if command -v fpc > /dev/null 2>&1; then
            build_sqldb_probe
            if [ "$IB_UP" = 1 ]; then
                warn  "Lazarus SQLdb talks to InterBase (loader: /opt/interbase/lib/libgds.so)" 'bash ib_scratch.sh sqldb' 120
                hint  "the same program reads Firebird through libfbclient.so.2: the loader decides which product a Lazarus app talks to"
            else
                skipped "Lazarus SQLdb talks to InterBase (loader: /opt/interbase/lib/libgds.so)" "(the server is not listening, see above)"
            fi
        fi
    fi
fi

# =================================================================
# Database servers in Docker (v82: install-mssql and install-oracle, which install-db-server
# expands to together with install-interbase; opt-in, not in install-all). Setup creates the
# containers stopped. Quick checks look at the clients, the ODBC drivers and the container
# settings; each slow check starts its engine with the 'mssql' / 'oracle' command (DEVDB_BOTH=1,
# so an engine you already have running is never stopped), creates a small table, reads it back
# through the native client and through ODBC, drops it, and stops the engine again if the test is
# what started it. Loaded Ollama models are unloaded first, as for kind.
# =================================================================
if has install-mssql || has install-oracle; then
    # jq filter over 'docker inspect': is the container the way setup creates it?
    cat > "$WORK/devdb.jq" << 'EOF'
.[0] as $c
| ($c.HostConfig.PortBindings[$port] // []) as $b
| "image   \($c.Config.Image)",
  "ports   \($b | map(.HostIp + ":" + .HostPort) | join(" "))",
  "memory  \(if $c.HostConfig.Memory > 0 then "\($c.HostConfig.Memory / 1048576 | floor) MB cap" else "no cap" end)",
  "volume  \([$c.Mounts[] | select(.Name == $vol) | $vol + " at " + .Destination] | join(" "))",
  if ($b | length) > 0 and all($b[]; .HostIp == "127.0.0.1")
     and ([$c.Mounts[] | select(.Name == $vol)] | length) == 1
     and (($mem | not) or $c.HostConfig.Memory > 0)
  then "as setup creates it" else error("not the way setup creates it") end
EOF
    # One round-trip per engine: devdb_smoke.sh mssql|oracle
    cat > "$WORK/devdb_smoke.sh" << 'EOF'
e=$1; c=devdb-$e
command -v "$e" > /dev/null || { echo "no '$e' command (rerun setup with install-$e)"; exit 1; }
was=$(docker inspect -f '{{.State.Running}}' "$c" 2> /dev/null)
[ -n "$was" ] || { echo "no $c container (rerun setup with install-$e)"; exit 1; }
if command -v ollama > /dev/null; then
    for m in $(ollama ps 2> /dev/null | awk 'NR > 1 {print $1}'); do ollama stop "$m" > /dev/null 2>&1; done
fi
echo "available before the start: $(free -m | awk '/^Mem:/ {print $7}') MB"
if [ "$was" != true ]; then trap 'echo "--- stopping $c again (the test started it):"; "$e" down' EXIT; fi
if ! DEVDB_BOTH=1 "$e" up > up.log 2>&1; then cat up.log; exit 1; fi
head -n 1 up.log
pw=$("$e" password)
case "$e" in
mssql)
    export SQLCMDPASSWORD="$pw"
    if command -v sqlcmd > /dev/null; then
        S=(sqlcmd -S "127.0.0.1,1433" -U sa -C -h -1 -W -b); F=mssql_smoke.sql
    else
        echo "(no Go sqlcmd on this machine: using the container's)"
        docker cp mssql_smoke.sql "$c:/tmp/mssql_smoke.sql" > /dev/null || exit 1
        S=(docker exec -e "SQLCMDPASSWORD=$pw" "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -h -1 -W -b); F=/tmp/mssql_smoke.sql
    fi
    "${S[@]}" -Q "SET NOCOUNT ON; SELECT CONCAT('version=', CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(40)), ' ', CAST(SERVERPROPERTY('Edition') AS nvarchar(80)));" || exit 1
    "${S[@]}" -i "$F" > native.out 2>&1; rc=$?; cat native.out
    { [ "$rc" -eq 0 ] && grep -q 'rows=3' native.out; } || exit 1
    echo "--- the same table through ODBC Driver 18 (isql)"
    echo "SELECT COUNT(*) FROM devtest.dbo.airports" \
        | isql -b -k "DRIVER={ODBC Driver 18 for SQL Server};Server=127.0.0.1,1433;Uid=sa;Pwd=$pw;TrustServerCertificate=yes" > odbc.out 2>&1
    cat odbc.out
    grep -qw 3 odbc.out || exit 1
    "${S[@]}" -Q "DROP DATABASE devtest;" > /dev/null ;;
oracle)
    command -v sql > /dev/null || { echo "SQLcl (sql) is missing: rerun setup with install-oracle"; exit 1; }
    sql -S -L "system/$pw@//127.0.0.1:1521/FREEPDB1" @oracle_smoke.sql > native.out 2>&1; rc=$?; cat native.out
    { [ "$rc" -eq 0 ] && grep -q 'rows=3' native.out; } || exit 1
    echo "--- the same table through the Oracle ODBC driver (isql)"
    echo "SELECT COUNT(*) FROM devtest_airports" \
        | isql -b -k "DRIVER={Oracle ODBC};DBQ=127.0.0.1:1521/FREEPDB1;UID=system;PWD=$pw" > odbc.out 2>&1
    cat odbc.out
    grep -qw 3 odbc.out || exit 1
    printf 'DROP TABLE devtest_airports PURGE;\nEXIT\n' | sql -S -L "system/$pw@//127.0.0.1:1521/FREEPDB1" > /dev/null 2>&1 ;;
esac
EOF
    cat > "$WORK/mssql_smoke.sql" << 'EOF'
SET NOCOUNT ON;
IF DB_ID('devtest') IS NOT NULL DROP DATABASE devtest;
GO
CREATE DATABASE devtest;
GO
USE devtest;
CREATE TABLE dbo.airports (code CHAR(3) NOT NULL PRIMARY KEY, name NVARCHAR(60) NOT NULL, delay_min INT NOT NULL);
INSERT INTO dbo.airports VALUES ('DCA', N'Reagan National', 5), ('IAD', N'Dulles', 42), ('BWI', N'Baltimore', 0);
SELECT CONCAT('rows=', COUNT(*)) FROM dbo.airports;
GO
EOF
    cat > "$WORK/oracle_smoke.sql" << 'EOF'
SET FEEDBACK OFF
SET HEADING OFF
WHENEVER SQLERROR EXIT FAILURE
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE devtest_airports PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE devtest_airports (code CHAR(3) PRIMARY KEY, name VARCHAR2(60) NOT NULL, delay_min NUMBER NOT NULL);
INSERT INTO devtest_airports VALUES ('DCA', 'Reagan National', 5);
INSERT INTO devtest_airports VALUES ('IAD', 'Dulles', 42);
INSERT INTO devtest_airports VALUES ('BWI', 'Baltimore', 0);
COMMIT;
SELECT 'rows=' || COUNT(*) FROM devtest_airports;
SELECT 'version=' || version_full FROM product_component_version WHERE ROWNUM = 1;
EXIT
EOF
fi

if has install-mssql; then
    section "SQL Server 2025 in Docker (install-mssql, part of install-db-server)"
    check "mssql / oracle commands (~/.local/bin/devdb)"   '[ -x ~/.local/bin/devdb ] && [ "$(readlink ~/.local/bin/mssql)" = devdb ] && [ "$(readlink ~/.local/bin/oracle)" = devdb ]'
    hint  "rerun setup with install-mssql (or install-db-server); it writes ~/.local/bin/devdb and the two links"
    warn  "sqlcmd (Go) in ~/.local/bin"                     '[ -x ~/.local/bin/sqlcmd ] && sqlcmd --version'
    hint  "setup downloads it from github.com/microsoft/go-sqlcmd; without it 'mssql sql' and this test use the sqlcmd inside the container"
    check "ODBC Driver 18 for SQL Server registered"       'odbcinst -q -d | grep -q "ODBC Driver 18 for SQL Server"'
    check "devdb-mssql container: 127.0.0.1:1433, memory cap, data volume" 'docker inspect devdb-mssql > ms.json || { r=$(cat ~/.config/devdb/mssql.skipped 2> /dev/null); [ -n "$r" ] && echo "setup skipped it: $r"; exit 1; }; jq -r -e --arg port 1433/tcp --arg vol devdb-mssql-data --argjson mem true -f devdb.jq ms.json'
    hint  "no such container: rerun setup with install-mssql (a disk skip: DEV_DB_MIN_FREE_GB=<n>, or a bigger Linux disk). 'permission denied': open a new terminal (docker group)"
    # v92: no container, no round trip: one FAIL above, carrying setup's recorded reason, not a second one here.
    if [ "$LAST" = fail ]; then
        skipped "SQL Server starts, answers sqlcmd and ODBC, stops again" "(no devdb-mssql container, see above)"
    else
        slow  "SQL Server starts, answers sqlcmd and ODBC, stops again" 'bash devdb_smoke.sh mssql' 1200
        hint  "\"Login failed for user 'sa'\": MSSQL_SA_PASSWORD in secrets.env is not the server's password. A start that never finishes: free memory ('ollama stop <model>', close Chrome tabs); 'mssql logs' shows the server's side"
    fi
fi

if has install-oracle; then
    section "Oracle AI Database 26ai Free in Docker (install-oracle / install-oracle-full)"
    check "mssql / oracle commands (~/.local/bin/devdb)"   '[ -x ~/.local/bin/devdb ] && [ "$(readlink ~/.local/bin/oracle)" = devdb ]'
    hint  "rerun setup with install-oracle (or install-db-server)"
    check "SQLcl (~/.local/bin/sql, /opt/oracle/sqlcl) runs on this JDK" '[ -x /opt/oracle/sqlcl/bin/sql ] && v=$(timeout 90 sql -V 2>&1); echo "$v" | head -n 3; echo "$v" | grep -qi sqlcl' 120
    hint  "SQLcl needs Java 17 or 21 (default-jdk is 21 on trixie); rerun setup with install-oracle"
    check "Instant Client in /opt/oracle/instantclient, known to ldconfig" 'ls -l /opt/oracle/instantclient && ls /opt/oracle/instantclient/libclntsh.so* && /sbin/ldconfig -p | grep -q "/opt/oracle/instantclient/"'
    check "Instant Client finds all its libraries (ldd; libaio on trixie)" 'm=$(ldd /opt/oracle/instantclient/libsqora.so /opt/oracle/instantclient/libclntsh.so* 2>&1 | grep "not found" | sort -u); [ -z "$m" ] || { echo "$m"; exit 1; }'
    hint  "libaio.so.1 not found: rerun setup with install-oracle (it links /usr/lib/x86_64-linux-gnu/libaio.so.1 to trixie's libaio.so.1t64)"
    check "[Oracle ODBC] driver registered"                'odbcinst -q -d | grep -q "^\[Oracle ODBC\]"'
    # v83: Lite and full images keep their data in different volumes. The container's label says which
    # it runs (a devdb-oracle made by v82 has none: Lite).
    ORA_VARIANT=$(docker inspect -f '{{index .Config.Labels "dev-setup.oracle-variant"}}' devdb-oracle 2> /dev/null)
    if [ "$ORA_VARIANT" = full ]; then ORA_VOL=devdb-oracle-full-data; else ORA_VARIANT=lite; ORA_VOL=devdb-oracle-data; fi
    check "devdb-oracle container: 127.0.0.1:1521, data volume ($ORA_VARIANT image)" "docker inspect devdb-oracle > ora.json || { r=\$(cat ~/.config/devdb/oracle.skipped 2> /dev/null); [ -n \"\$r\" ] && echo \"setup skipped it: \$r\"; exit 1; }; jq -r -e --arg port 1521/tcp --arg vol $ORA_VOL --argjson mem false -f devdb.jq ora.json"
    hint  "no such container: rerun setup with install-oracle (a disk skip: DEV_DB_MIN_FREE_GB=<n>, or a bigger Linux disk). 'permission denied': open a new terminal (docker group)"
    ORA_HAVE=1; [ "$LAST" = fail ] && ORA_HAVE=0
    if has install-oracle-full && [ "$ORA_HAVE" = 1 ]; then
        check "devdb-oracle runs the full image (install-oracle-full)" 'l=$(docker inspect -f "{{index .Config.Labels \"dev-setup.oracle-variant\"}}" devdb-oracle) || exit 1; echo "image $(docker inspect -f "{{.Config.Image}}" devdb-oracle), variant label: ${l:-none}"; [ "$l" = full ] && exit 0; r=$(cat ~/.config/devdb/oracle.skipped 2> /dev/null); [ -n "$r" ] && echo "setup kept Lite: $r"; exit 1'
        hint  "setup keeps the Lite container when the full image is not here yet: most often disk space (it needs about 13 GB plus DEV_DB_MIN_FREE_GB free); setup's log says why. Rerun setup with install-oracle-full"
    fi
    if [ "$ORA_HAVE" = 0 ]; then
        skipped "Oracle starts, answers SQLcl and ODBC, stops again" "(no devdb-oracle container, see above)"
    else
        slow  "Oracle starts, answers SQLcl and ODBC, stops again" 'bash devdb_smoke.sh oracle' 1800
    fi
    hint  "ORA-01017 (invalid password): ORACLE_PWD in secrets.env is not the database's password. ORA-00442: another Oracle Free instance runs on this machine. A slow first start: 'oracle logs' shows progress"
fi

# =================================================================
# LDAP (v83): install-ldap (lldap, the lite directory) and install-ldap-full (OpenLDAP's slapd, plus
# lldap). Opt-in, not in install-all. The checks read what setup chose from ~/.config/devldap/ldap.env
# and use the same people on both: alice, bob and carol, and the read-only service account drupal-bind.
# The OpenLDAP write check adds a throwaway entry and deletes it again. The slow checks start a small
# alpine:3 container to prove Docker containers (DDEV's, for Drupal) reach each directory.
# =================================================================
if has install-ldap; then
    if has install-ldap-full; then
        section "LDAP: OpenLDAP (slapd) and lldap (install-ldap-full)"
    else
        section "LDAP: lldap (install-ldap)"
    fi
    # ldap_check.sh lite|full admin|search|login|group|write
    cat > "$WORK/ldap_check.sh" << 'EOF'
. "$HOME/.config/devldap/ldap.env" || exit 1
B=$LDAP_BASE_DN; P="ou=people,$B"; G="ou=groups,$B"; S="uid=drupal-bind,$P"
case $1 in
    lite) U=ldap://127.0.0.1:3890; A="uid=admin,$P"; AP=$LLDAP_ADMIN_PASSWORD ;;
    full) U=ldap://127.0.0.1:389;  A="cn=admin,$B";  AP=$OPENLDAP_ADMIN_PASSWORD ;;
    *) echo "usage: ldap_check.sh lite|full admin|search|login|group|write"; exit 2 ;;
esac
q() { ldapsearch -x -LLL -o ldif-wrap=no -H "$U" "$@"; }
case $2 in
    admin)
        ldapwhoami -x -H "$U" -D "$A" -w "$AP" ;;
    search)
        q -D "$S" -w "$LDAP_BIND_PASSWORD" -b "$P" '(|(uid=alice)(uid=bob)(uid=carol))' uid mail > search.out
        rc=$?; cat search.out
        [ "$rc" = 0 ] && [ "$(grep -c '^uid: ' search.out)" = 3 ] ;;
    login)
        ldapwhoami -x -H "$U" -D "uid=alice,$P" -w "$LDAP_SAMPLE_PASSWORD" || exit 1
        if ldapwhoami -x -H "$U" -D "uid=alice,$P" -w "wrong-$LDAP_SAMPLE_PASSWORD" > /dev/null 2>&1; then
            echo "a wrong password was accepted"; exit 1
        fi
        echo "a wrong password is refused" ;;
    group)
        q -D "$S" -w "$LDAP_BIND_PASSWORD" -b "$G" '(cn=drupal_editors)' objectClass member uniqueMember | tee group.out
        grep -qiE "^(member|uniqueMember): uid=alice,ou=people," group.out ;;
    write)
        e="uid=devtest-$$,$P"
        printf 'dn: %s\nobjectClass: inetOrgPerson\nuid: devtest-%s\ncn: dev-test\nsn: test\nmail: before@example.com\n' "$e" "$$" \
            | ldapadd -x -H "$U" -D "$A" -w "$AP" || exit 1
        printf 'dn: %s\nchangetype: modify\nreplace: mail\nmail: after@example.com\n' "$e" \
            | ldapmodify -x -H "$U" -D "$A" -w "$AP" > /dev/null
        q -D "$A" -w "$AP" -b "$e" -s base mail | grep -q '^mail: after@example.com'; rc=$?
        ldapdelete -x -H "$U" -D "$A" -w "$AP" "$e" && echo "added, modified, read back and deleted $e"
        exit $rc ;;
esac
EOF
    # jq filter over 'docker inspect devldap-lldap': is the container the way setup creates it?
    cat > "$WORK/ldap.jq" << 'EOF'
.[0] as $c
| ($c.HostConfig.PortBindings["3890/tcp"] // []) as $b
| "state   \($c.State.Status) (restart policy \($c.HostConfig.RestartPolicy.Name))",
  "ldap    \($b | map(.HostIp + ":" + .HostPort) | join(" "))",
  "volume  \([$c.Mounts[] | select(.Name == "devldap-lldap-data") | .Name + " at " + .Destination] | join(" "))",
  if $c.State.Running and ($b | length) > 0 and all($b[]; .HostIp == "127.0.0.1")
     and ([$c.Mounts[] | select(.Name == "devldap-lldap-data")] | length) == 1
  then "as setup creates it" else error("not running, or not the way setup creates it") end
EOF
    check "ldap-utils (ldapsearch, ldapwhoami, ldapadd, ldapmodify) and PHP's ldap extension" 'for c in ldapsearch ldapwhoami ldapadd ldapmodify ldapdelete; do command -v "$c" > /dev/null || { echo "missing: $c"; exit 1; }; done; php -m | grep -qix ldap || { echo "PHP has no ldap extension (php-ldap)"; exit 1; }'
    hint  "rerun setup with install-ldap (it installs ldap-utils and php-ldap)"
    check "the ldap command, and ~/.config/devldap/ldap.env (mode 600)" 'f=~/.config/devldap/ldap.env; [ -x ~/.local/bin/ldap ] || { echo "no ~/.local/bin/ldap"; exit 1; }; [ -f "$f" ] || { echo "no $f"; exit 1; }; m=$(stat -c %a "$f"); . "$f"; echo "mode $m, base DN $LDAP_BASE_DN"; [ "$m" = 600 ] && [ -n "$LDAP_BIND_PASSWORD" ] && [ -n "$LDAP_SAMPLE_PASSWORD" ]'
    hint  "rerun setup with install-ldap: it writes both"
    check "devldap-lldap container: running, 127.0.0.1 only, data volume" 'docker inspect devldap-lldap > ll.json || exit 1; jq -r -e -f ldap.jq ll.json'
    hint  "no such container: rerun setup with install-ldap. Stopped: 'ldap up'. 'permission denied': open a new terminal (docker group)"
    # With no container, the lldap checks below would all fail for that one reason: the check above says it.
    if docker container inspect devldap-lldap > /dev/null 2>&1; then
        check "lldap: admin binds (uid=admin)"                      'bash ldap_check.sh lite admin'
        hint  "lldap takes its admin password when its volume is first created: ldap.env must hold that one (dev-setup's install-ldap notes say how to start over)"
        check "lldap: the service account finds alice, bob and carol" 'bash ldap_check.sh lite search'
        hint  "lldap's bootstrap.sh creates them: see assets/logs/ldap-bootstrap.log, then rerun setup with install-ldap"
        check "lldap: alice logs in with her password, a wrong one is refused" 'bash ldap_check.sh lite login'
        check "lldap: alice is a member of drupal_editors"          'bash ldap_check.sh lite group'
        warn  "lldap web UI answers (http://127.0.0.1:17170)"       'curl -fsS -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:17170/'
    fi
    warn  "lldap is on DDEV's network (only once a DDEV project has run)" 'if ! docker network inspect ddev_default > /dev/null 2>&1; then echo "SKIPPED: no ddev_default network yet"; exit 0; fi; docker network inspect ddev_default -f "{{range .Containers}}{{.Name}} {{end}}" | tee /dev/stderr | grep -qw devldap-lldap'
    hint  "'ldap up' joins it (DDEV recreates the network after 'ddev poweroff')"
    slowwarn "a container on DDEV's network reaches ldap://lldap:3890" 'if ! docker network inspect ddev_default > /dev/null 2>&1; then echo "SKIPPED: no ddev_default network yet"; exit 0; fi; docker run --rm --network ddev_default alpine:3 nc -z -w 5 lldap 3890 && echo "lldap:3890 is open from ddev_default"' 300
    hint  "not joined (the check above), or Docker Hub unreachable for alpine:3"
    if has install-ldap-full; then
        check "slapd installed, running and enabled"                 'dpkg_has slapd && systemctl is-active slapd && systemctl is-enabled slapd'
        hint  "sudo systemctl enable --now slapd; 'journalctl -u slapd' says why it stopped"
        check "OpenLDAP's suffix is LDAP_BASE_DN (cn=config)"        '. ~/.config/devldap/ldap.env; s=$(sudo -n ldapsearch -Q -LLL -o ldif-wrap=no -Y EXTERNAL -H ldapi:/// -b cn=config "(olcSuffix=*)" olcSuffix | sed -n "s/^olcSuffix: //p"); echo "suffix: $s (wanted $LDAP_BASE_DN)"; echo "$s" | grep -qixF "$LDAP_BASE_DN"'
        hint  "rerun setup with install-ldap-full: it reconfigures a slapd that serves another suffix"
        check "OpenLDAP: admin binds (cn=admin)"                     'bash ldap_check.sh full admin'
        check "OpenLDAP: the service account finds alice, bob and carol" 'bash ldap_check.sh full search'
        hint  "setup's seed log: assets/logs/ldap-openldap-seed.log"
        check "OpenLDAP: alice logs in, a wrong password is refused" 'bash ldap_check.sh full login'
        check "OpenLDAP: alice is a member of drupal_editors"        'bash ldap_check.sh full group'
        check "OpenLDAP: add, modify, read back and delete an entry" 'bash ldap_check.sh full write'
        slowwarn "a Docker container reaches slapd at host.docker.internal:389" 'docker run --rm --add-host=host.docker.internal:host-gateway alpine:3 nc -z -w 5 host.docker.internal 389 && echo "host.docker.internal:389 is open"' 300
        hint  "slapd must listen on every interface: Debian's default SLAPD_SERVICES=\"ldap:/// ldapi:///\" in /etc/default/slapd"
    fi
fi

# =================================================================
# Test tools (v91): install-testing = install-playwright + install-selenium + install-bdd + install-robot, and
# the opt-in install-cypress. Every browser check runs against one small app written here, links_app.py
# (standard-library Python: a list of links, an add form that refuses a non-web address, /links.json, and
# POST /reset), on a free port on 127.0.0.1, so nothing needs the internet but the per-project packages
# the slow checks download (npm, PyPI, Packagist, NuGet, Maven Central) into the usual caches. One Gherkin
# file, links.feature, is run by each BDD runner whose language is installed. The Selenium Grid's checks
# sit with the other devsvc services, further down, and reuse these files.
# =================================================================
T_ANY=0
for _t in playwright selenium bdd robot cypress; do has "install-$_t" && T_ANY=1; done
if [ "$T_ANY" = 1 ]; then
    section "Test tools: Playwright, Selenium, Gherkin runners, Robot Framework, Cypress"
    mkdir -p "$WORK/testing"
    cat > "$WORK/testing/links_app.py" << 'EOF'
#!/usr/bin/env python3
"""links: the small app the browser tests run against (dev-test v91). Standard library only.
GET / lists the links and has an add form; POST /add validates (a title, an http(s) URL) and redirects
back, or answers 422 with the error; GET /links.json is the list as JSON; POST /reset restores the two
starting links. python3 links_app.py [--host 127.0.0.1] [--port 0] [--port-file FILE]"""
import argparse, html, json, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

SEED = [{"title": "Debian", "url": "https://www.debian.org/"},
        {"title": "Playwright", "url": "https://playwright.dev/"}]
LINKS = [dict(x) for x in SEED]
LOCK = threading.Lock()

def page(error="", title="", url=""):
    items = "\n".join(f'    <li data-testid="link"><a href="{html.escape(l["url"])}">{html.escape(l["title"])}</a></li>'
                      for l in LINKS)
    err = f'  <p class="error" role="alert" data-testid="error">{html.escape(error)}</p>\n' if error else ""
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Links</title></head>
<body>
  <h1>Links</h1>
  <p data-testid="count">{len(LINKS)} links</p>
  <ul id="links">
{items}
  </ul>
{err}  <form method="post" action="/add">
    <label for="title">Title</label> <input id="title" name="title" value="{html.escape(title)}">
    <label for="url">URL</label> <input id="url" name="url" value="{html.escape(url)}">
    <button id="add" type="submit">Add link</button>
  </form>
</body></html>
"""

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body, ctype="text/html; charset=utf-8", extra=None):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.end_headers()
        self.wfile.write(b)
    def do_GET(self):
        path = self.path.split("?")[0]
        with LOCK:
            if path == "/": self.send(200, page())
            elif path == "/links.json": self.send(200, json.dumps(LINKS), "application/json")
            elif path == "/health": self.send(200, "ok", "text/plain")
            else: self.send(404, "not found", "text/plain")
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        form = {k: v[0] for k, v in parse_qs(self.rfile.read(n).decode()).items()}
        path = self.path.split("?")[0]
        with LOCK:
            if path == "/reset":
                LINKS[:] = [dict(x) for x in SEED]
                self.send(200, "reset", "text/plain")
            elif path == "/add":
                t, u = form.get("title", "").strip(), form.get("url", "").strip()
                if not t: self.send(422, page("Title is required.", t, u))
                elif not u.startswith(("http://", "https://")): self.send(422, page("URL must start with http:// or https://.", t, u))
                else:
                    LINKS.append({"title": t, "url": u})
                    self.send(303, "", extra={"Location": "/"})
            else: self.send(404, "not found", "text/plain")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--port-file")
    a = ap.parse_args()
    srv = ThreadingHTTPServer((a.host, a.port), H)
    if a.port_file:
        with open(a.port_file, "w") as f: f.write(str(srv.server_address[1]))
    print(f"links app on http://{a.host}:{srv.server_address[1]}/", flush=True)
    srv.serve_forever()
EOF
    cat > "$WORK/testing/links.feature" << 'EOF'
Feature: Links
  The links app keeps a list of useful links, and refuses one without a web address.

  Background:
    Given the links app has its two starting links

  Scenario: Add a link
    When I add the link "Behat" with the URL "https://behat.org/"
    Then I see 3 links
    And I see a link named "Behat"

  Scenario: A link needs a web address
    When I add the link "Broken" with the URL "ftp://example.org/"
    Then I see the error "URL must start with http:// or https://."
    And I see 2 links
EOF
    # sel_links.py: Selenium (Python) adds a link. Local Chrome through Selenium Manager, or the Grid when
    # GRID_URL is set (BASE_URL is then the address the Grid's browser uses, APP_URL this machine's).
    cat > "$WORK/testing/sel_links.py" << 'EOF'
import os, urllib.request
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait

base = os.environ["BASE_URL"]; app = os.environ.get("APP_URL", base); grid = os.environ.get("GRID_URL")
urllib.request.urlopen(urllib.request.Request(app + "/reset", data=b"", method="POST")).read()
o = webdriver.ChromeOptions()
if grid:
    d = webdriver.Remote(grid, options=o)             # headed, in the Grid's Xvfb: noVNC shows it
else:
    o.binary_location = "/usr/bin/google-chrome-stable"
    o.add_argument("--headless=new"); o.add_argument("--disable-gpu")
    d = webdriver.Chrome(options=o)                   # Selenium Manager finds chromedriver
try:
    print("browser", d.capabilities.get("browserVersion"), "driver", d.capabilities.get("chrome", {}).get("chromedriverVersion", "?").split(" ")[0])
    d.get(base + "/")
    assert len(d.find_elements(By.CSS_SELECTOR, "[data-testid=link]")) == 2
    d.find_element(By.ID, "title").send_keys("Selenium")
    d.find_element(By.ID, "url").send_keys("https://www.selenium.dev/")
    d.find_element(By.ID, "add").click()
    WebDriverWait(d, 15).until(lambda x: len(x.find_elements(By.CSS_SELECTOR, "[data-testid=link]")) == 3)
    if os.environ.get("SHOT"):
        d.save_screenshot(os.environ["SHOT"])
    print("added a link: 3 links")
finally:
    d.quit()
EOF
    # The app for this section, on a free port; stopped at the end of the section (and on exit).
    python3 "$WORK/testing/links_app.py" --port-file "$WORK/testing/links.port" > "$WORK/testing/links_app.log" 2>&1 &
    LINKS_PID=$!
    trap '[ -n "${LINKS_PID:-}" ] && kill "$LINKS_PID" 2> /dev/null; rm -rf "$WORK"' EXIT
    for _ in $(seq 1 20); do [ -s "$WORK/testing/links.port" ] && break; sleep 0.25; done
    LINKS_URL="http://127.0.0.1:$(cat "$WORK/testing/links.port" 2> /dev/null)"; export LINKS_URL
    check "the test app (links_app.py) answers on $LINKS_URL"  'curl -fsS "$LINKS_URL/links.json" | jq -e "length == 2"'
    hint  "python3 runs it from the temp dir; its output: $WORK/testing/links_app.log"
fi

if has install-playwright; then
    # Playwright's browser builds are tied to its release: the scratch project uses the release setup's
    # 'npx playwright@latest' installed the browsers for (npx's cache), so nothing is downloaded but the
    # npm package.
    check "Playwright's browsers in ~/.cache/ms-playwright (chromium, firefox, webkit)" 'cd ~/.cache/ms-playwright 2> /dev/null || { echo "no ~/.cache/ms-playwright"; exit 1; }; ls -d chromium-* chromium_headless_shell-* firefox-* webkit-* 2> /dev/null | xargs; for b in chromium firefox webkit; do ls -d "$b"-* > /dev/null 2>&1 || { echo "missing: $b"; exit 1; }; done'
    hint  "rerun setup with install-playwright (playwright install --with-deps chromium firefox webkit)"
    check "the Playwright release setup used is in npx's cache" 'v=$(timeout 60 npx -y --prefer-offline playwright@latest --version 2> /dev/null | awk "{print \$2}"); echo "playwright $v"; [ -n "$v" ] && echo "$v" > "$WORK/testing/pw.version"'
    hint  "rerun setup with install-playwright; npm's cache (~/.npm/_npx) may have been cleared"
    mkdir -p "$WORK/testing/pw/tests"
    cat > "$WORK/testing/pw/playwright.config.ts" << 'EOF'
import { defineConfig, devices } from '@playwright/test'
// dev-test (install-playwright): the links app at BASE_URL, one worker (8 GB of RAM), a trace for Chromium.
export default defineConfig({
  testDir: 'tests',
  workers: 1,
  reporter: [['line']],
  use: { baseURL: process.env.BASE_URL },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'], trace: 'on' } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    { name: 'chrome', use: { ...devices['Desktop Chrome'], channel: 'chrome' } },
  ],
})
EOF
    cat > "$WORK/testing/pw/tests/links.spec.ts" << 'EOF'
import { test, expect } from '@playwright/test'

test.beforeEach(async ({ page, request }) => {
  await request.post('/reset')
  await page.goto('/')
  await expect(page.getByTestId('link')).toHaveCount(2)
})

test('add a link', async ({ page }) => {
  await page.getByLabel('Title').fill('Behat')
  await page.getByLabel('URL').fill('https://behat.org/')
  await page.getByRole('button', { name: 'Add link' }).click()
  await expect(page.getByTestId('link')).toHaveCount(3)
  await expect(page.getByRole('link', { name: 'Behat' })).toBeVisible()
})

test('a link needs a web address', async ({ page }) => {
  await page.getByLabel('Title').fill('Broken')
  await page.getByLabel('URL').fill('ftp://example.org/')
  await page.getByRole('button', { name: 'Add link' }).click()
  await expect(page.getByRole('alert')).toHaveText('URL must start with http:// or https://.')
  await expect(page.getByTestId('link')).toHaveCount(2)
})
EOF
    echo '{ "name": "dev-test-playwright", "private": true }' > "$WORK/testing/pw/package.json"
    slow  "Playwright Test installs into a scratch project (the same release)" 'cd testing/pw && v=$(cat ../pw.version 2> /dev/null); [ -n "$v" ] || { echo "no Playwright release from the check above"; exit 1; }; npm install -D --no-audit --no-fund "@playwright/test@$v" > npm.log 2>&1 || { tail -n 15 npm.log; exit 1; }; npx playwright --version' 600
    if [ "$LAST" = pass ]; then
        for _p in chromium firefox webkit chrome; do
            slow  "Playwright Test: the links spec passes in $_p" "cd testing/pw && BASE_URL=\$LINKS_URL npx playwright test --project=$_p --output=out-$_p" 300
        done
        hint  "chrome = the system Chrome (channel: 'chrome'); the other three are Playwright's builds. A missing library: rerun setup with install-playwright (--with-deps)"
        check "Playwright wrote a trace for the Chromium run (npx playwright show-trace opens it)" 'ls testing/pw/out-chromium/*/trace.zip'
    fi
    slowwarn "pytest-playwright (Python, through uv) on the system Chrome" 'cd testing && cat > test_pw_links.py << "PY"
from playwright.sync_api import Page, expect

def test_add_a_link(page: Page):
    page.request.post("/reset")
    page.goto("/")
    page.get_by_label("Title").fill("pytest")
    page.get_by_label("URL").fill("https://docs.pytest.org/")
    page.get_by_role("button", name="Add link").click()
    expect(page.get_by_test_id("link")).to_have_count(3)
PY
uv run --no-project --quiet --with pytest-playwright pytest -q -p no:cacheprovider --browser-channel chrome --base-url "$LINKS_URL" test_pw_links.py' 600
    warn  "Playwright MCP starts from npx's cache (@playwright/mcp)" 'timeout 90 npx -y --prefer-offline @playwright/mcp@latest --help 2>&1 | grep -m1 -- "--browser"'
    hint  "rerun setup with install-playwright; then: claude mcp add playwright -- npx @playwright/mcp@latest"
fi

if has install-selenium; then
    check "~/.bashrc has the dev-setup selenium block (SE_AVOID_STATS)" 'grep -q "^# >>> dev-setup selenium >>>$" ~/.bashrc && grep -q "^export SE_AVOID_STATS=true$" ~/.bashrc'
    hint  "rerun setup with install-selenium"
    warn  "no chromedriver on PATH (Selenium Manager picks the one matching Chrome)" 'w=$(command -v chromedriver); [ -z "$w" ] || { echo "chromedriver on PATH: $w (Selenium Manager uses it only if it matches Chrome)"; exit 1; }'
    warn  "Selenium Manager's cache has a chromedriver for this Chrome (~/.cache/selenium)" 'm=$(google-chrome-stable --version | grep -oE "[0-9]+" | head -n 1); ls -d ~/.cache/selenium/chromedriver/linux64/"$m".* 2> /dev/null || { echo "none for Chrome $m: Chrome updated since setup; the next Selenium run fetches it"; exit 1; }'
    slow  "Selenium (Python) drives this Chrome headless (Selenium Manager)" 'cd testing && BASE_URL=$LINKS_URL SE_AVOID_STATS=true uv run --no-project --quiet --with selenium python sel_links.py' 600
    hint  "'unable to obtain driver': googlechromelabs.github.io unreachable and nothing cached; rerun setup with install-selenium when online"
    if has install-node; then
        slowwarn "selenium-webdriver (Node) drives this Chrome headless" 'mkdir -p testing/swd && cd testing/swd && echo "{ \"private\": true, \"type\": \"module\" }" > package.json && npm install --no-audit --no-fund selenium-webdriver > npm.log 2>&1 || { tail -n 10 npm.log; exit 1; }; cat > swd.mjs << "JS"
import { Builder, By } from "selenium-webdriver"
import chrome from "selenium-webdriver/chrome.js"
const base = process.env.BASE_URL
const o = new chrome.Options().addArguments("--headless=new", "--disable-gpu").setChromeBinaryPath("/usr/bin/google-chrome-stable")
const d = await new Builder().forBrowser("chrome").setChromeOptions(o).build()
try {
  await fetch(base + "/reset", { method: "POST" })
  await d.get(base + "/")
  await d.findElement(By.id("title")).sendKeys("WebDriver")
  await d.findElement(By.id("url")).sendKeys("https://w3c.github.io/webdriver/")
  await d.findElement(By.id("add")).click()
  await d.wait(async () => (await d.findElements(By.css("[data-testid=link]"))).length === 3, 15000)
  console.log("selenium-webdriver: 3 links")
} finally { await d.quit() }
JS
BASE_URL=$LINKS_URL SE_AVOID_STATS=true node swd.mjs' 600
    fi
fi

if has install-bdd; then
    # The same links.feature, each runner with its own step definitions (Gherkin is the shared layer).
    if has install-dotnet; then
        check "Reqnroll's templates for 'dotnet new' (reqnroll-project)" 'dotnet new list reqnroll-project 2>&1 | grep -i reqnroll'
        hint  "rerun setup with install-bdd (dotnet new install Reqnroll.Templates.DotNet)"
        if [ "$LAST" = pass ]; then
            slow  "Reqnroll (C#, NUnit): dotnet new reqnroll-project, links.feature passes" 'cd testing && rm -rf reqnroll && dotnet new reqnroll-project -t nunit -n LinksSpecs -o reqnroll > new.log 2>&1 || { tail -n 10 new.log; exit 1; }; cd reqnroll && rm -f Features/*.feature StepDefinitions/*.cs && mkdir -p Features StepDefinitions && cp ../links.feature Features/Links.feature && cat > StepDefinitions/LinksSteps.cs << "CS"
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using NUnit.Framework;
using Reqnroll;

namespace LinksSpecs.StepDefinitions;

// Over HTTP with HttpClient (no browser); dev-demo pairs Reqnroll with Playwright for .NET.
[Binding]
public class LinksSteps
{
    static readonly string Base = Environment.GetEnvironmentVariable("BASE_URL") ?? "http://127.0.0.1:8000";
    static readonly HttpClient Http = new();
    string _page = "";

    [Given("the links app has its two starting links")]
    public async Task Start()
    {
        await Http.PostAsync(Base + "/reset", null);
        _page = await Http.GetStringAsync(Base + "/");
    }

    [When("I add the link {string} with the URL {string}")]
    public async Task Add(string title, string url)
    {
        var form = new FormUrlEncodedContent(new Dictionary<string, string> { ["title"] = title, ["url"] = url });
        _page = await (await Http.PostAsync(Base + "/add", form)).Content.ReadAsStringAsync();
    }

    [Then("I see {int} links")]
    public void Count(int n) => Assert.That(Regex.Matches(_page, "data-testid=\"link\"").Count, Is.EqualTo(n));

    [Then("I see a link named {string}")]
    public void Named(string name) => Assert.That(_page, Does.Contain(">" + name + "</a>"));

    [Then("I see the error {string}")]
    public void Error(string text) => Assert.That(Regex.Match(_page, "role=\"alert\"[^>]*>([^<]*)<").Groups[1].Value, Is.EqualTo(text));
}
CS
BASE_URL=$LINKS_URL dotnet test --nologo -v q 2>&1 | tail -n 5; [ "${PIPESTATUS[0]}" = 0 ]' 900
            hint  "the first run fetches Reqnroll, NUnit and the test SDK from nuget.org into ~/.nuget"
        fi
    fi
    if has install-node; then
        mkdir -p "$WORK/testing/cucjs/features"
        cp "$WORK/testing/links.feature" "$WORK/testing/cucjs/features/"
        echo '{ "name": "dev-test-cucumber", "private": true, "type": "module" }' > "$WORK/testing/cucjs/package.json"
        cat > "$WORK/testing/cucjs/features/steps.mjs" << 'EOF'
// cucumber-js step definitions: Playwright's library (playwright-core) on the system Chrome (channel 'chrome').
import { Before, After, BeforeAll, AfterAll, Given, When, Then, setDefaultTimeout } from '@cucumber/cucumber'
import { chromium } from 'playwright-core'
import assert from 'node:assert/strict'

setDefaultTimeout(30_000)
const BASE = process.env.BASE_URL
let browser, page
BeforeAll(async () => { browser = await chromium.launch({ channel: 'chrome', headless: true }) })
AfterAll(async () => { await browser?.close() })
Before(async () => { page = await browser.newPage() })
After(async () => { await page?.close() })

Given('the links app has its two starting links', async () => {
  await fetch(`${BASE}/reset`, { method: 'POST' })
  await page.goto(`${BASE}/`)
})
When('I add the link {string} with the URL {string}', async (title, url) => {
  await page.getByLabel('Title').fill(title)
  await page.getByLabel('URL').fill(url)
  await page.getByRole('button', { name: 'Add link' }).click()
  await page.waitForLoadState()
})
Then('I see {int} links', async (n) => {
  assert.equal(await page.getByTestId('link').count(), n)
})
Then('I see a link named {string}', async (name) => {
  assert.ok(await page.getByRole('link', { name }).isVisible())
})
Then('I see the error {string}', async (text) => {
  assert.equal((await page.getByRole('alert').textContent()).trim(), text)
})
EOF
        slowwarn "cucumber-js + Playwright (playwright-core, system Chrome): links.feature" 'cd testing/cucjs && npm install -D --no-audit --no-fund @cucumber/cucumber playwright-core > npm.log 2>&1 || { tail -n 10 npm.log; exit 1; }; BASE_URL=$LINKS_URL npx cucumber-js --import "features/**/*.mjs" --format summary' 600
    fi
    mkdir -p "$WORK/testing/behave/features/steps"
    cp "$WORK/testing/links.feature" "$WORK/testing/behave/features/"
    cat > "$WORK/testing/behave/features/steps/links_steps.py" << 'EOF'
# behave step definitions over HTTP with the standard library (what Mink's BrowserKit driver does in PHP):
# no browser, so no JavaScript; dev-demo's bake-off runs behave with Playwright instead.
import os, urllib.error, urllib.parse, urllib.request
from html.parser import HTMLParser
from behave import given, when, then

BASE = os.environ["BASE_URL"]

class Page(HTMLParser):
    def __init__(self, text):
        super().__init__(); self.links, self.error, self._in = [], None, None
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if a.get("data-testid") == "link": self.links.append("")
        if a.get("role") == "alert": self._in = "error"; self.error = ""
        if tag == "a" and self.links: self._in = "link"
    def handle_endtag(self, tag):
        if tag in ("a", "p"): self._in = None
    def handle_data(self, data):
        if self._in == "link": self.links[-1] += data
        elif self._in == "error": self.error += data

def fetch(path, form=None):
    data = urllib.parse.urlencode(form).encode() if form is not None else None
    try:
        with urllib.request.urlopen(BASE + path, data) as r: return r.read().decode()
    except urllib.error.HTTPError as e:
        return e.read().decode()

@given("the links app has its two starting links")
def step_start(ctx):
    fetch("/reset", {})
    ctx.page = Page(fetch("/"))

@when('I add the link "{title}" with the URL "{url}"')
def step_add(ctx, title, url):
    ctx.page = Page(fetch("/add", {"title": title, "url": url}))

@then("I see {n:d} links")
def step_count(ctx, n):
    assert len(ctx.page.links) == n, ctx.page.links

@then('I see a link named "{name}"')
def step_named(ctx, name):
    assert name in ctx.page.links, ctx.page.links

@then('I see the error "{text}"')
def step_error(ctx, text):
    assert (ctx.page.error or "").strip() == text, ctx.page.error
EOF
    slowwarn "behave (Python, through uv): links.feature over HTTP" 'cd testing/behave && BASE_URL=$LINKS_URL uv run --no-project --quiet --with behave behave --format progress' 300
    if has install-web; then
        mkdir -p "$WORK/testing/behat/features/bootstrap"
        cp "$WORK/testing/links.feature" "$WORK/testing/behat/features/"
        cat > "$WORK/testing/behat/features/bootstrap/FeatureContext.php" << 'EOF'
<?php
// Behat 4 (PHP 8 attributes; no YAML config in 4.x, and none needed for the default suite) with Mink's
// BrowserKit driver: real HTTP and HTML forms, no browser. Mink is used directly, without MinkExtension.
use Behat\Behat\Context\Context;
use Behat\Mink\Driver\BrowserKitDriver;
use Behat\Mink\Session;
use Behat\Step\Given;
use Behat\Step\Then;
use Behat\Step\When;
use Symfony\Component\BrowserKit\HttpBrowser;

final class FeatureContext implements Context
{
    private Session $session;
    private string $base;

    public function __construct()
    {
        $this->base = rtrim((string) getenv('BASE_URL'), '/');
        $this->session = new Session(new BrowserKitDriver(new HttpBrowser()));
        $this->session->start();
    }

    #[Given('the links app has its two starting links')]
    public function start(): void
    {
        file_get_contents($this->base . '/reset', false, stream_context_create(['http' => ['method' => 'POST']]));
        $this->session->visit($this->base . '/');
    }

    #[When('I add the link :title with the URL :url')]
    public function add(string $title, string $url): void
    {
        $page = $this->session->getPage();
        $page->fillField('Title', $title);
        $page->fillField('URL', $url);
        $page->pressButton('Add link');
    }

    #[Then('I see :count links')]
    public function count(int $count): void
    {
        $n = count($this->session->getPage()->findAll('css', '[data-testid=link]'));
        if ($n !== $count) {
            throw new RuntimeException("expected $count links, found $n");
        }
    }

    #[Then('I see a link named :name')]
    public function named(string $name): void
    {
        if ($this->session->getPage()->findLink($name) === null) {
            throw new RuntimeException("no link named $name");
        }
    }

    #[Then('I see the error :text')]
    public function error(string $text): void
    {
        $e = $this->session->getPage()->find('css', '[role=alert]');
        if ($e === null || trim($e->getText()) !== $text) {
            throw new RuntimeException('the error was: ' . ($e ? $e->getText() : 'none'));
        }
    }
}
EOF
        slowwarn "Behat 4 + Mink (BrowserKit driver, Composer): links.feature" 'cd testing/behat && echo "{}" > composer.json && COMPOSER_NO_INTERACTION=1 composer require --dev --no-progress -q behat/behat:^4.0 behat/mink behat/mink-browserkit-driver symfony/http-client symfony/mime > composer.log 2>&1 || { grep -v "^require \[" composer.log | head -n 15; exit 1; }; vendor/bin/behat --version; BASE_URL=$LINKS_URL vendor/bin/behat --format progress --no-colors' 600
        hint  "Behat 4 is for Symfony 8 apps; Drupal's Drupal Extension still needs Behat 3 (dev-demo's drupal-behat uses it)"
    fi
    if has install-java; then
        mkdir -p "$WORK/testing/cucjvm/src/main/java/links" "$WORK/testing/cucjvm/features"
        cp "$WORK/testing/links.feature" "$WORK/testing/cucjvm/features/"
        cat > "$WORK/testing/cucjvm/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>devtest</groupId>
  <artifactId>links-cucumber</artifactId>
  <version>1</version>
  <!-- cucumber-jvm run by its own CLI (io.cucumber.core.cli.Main), so no JUnit or Surefire is involved. -->
  <properties>
    <maven.compiler.release>17</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
  <dependencies>
    <dependency>
      <groupId>io.cucumber</groupId>
      <artifactId>cucumber-java</artifactId>
      <version>[7.34,8)</version>
    </dependency>
  </dependencies>
</project>
EOF
        cat > "$WORK/testing/cucjvm/src/main/java/links/LinksSteps.java" << 'EOF'
package links;

import io.cucumber.java.en.Given;
import io.cucumber.java.en.Then;
import io.cucumber.java.en.When;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// Over HTTP with java.net.http (no browser).
public class LinksSteps {
    static final String BASE = System.getenv().getOrDefault("BASE_URL", "http://127.0.0.1:8000");
    static final HttpClient HTTP = HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NORMAL).build();
    String page = "";

    String send(String path, String form) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(BASE + path));
        if (form != null) {
            b.header("Content-Type", "application/x-www-form-urlencoded").POST(HttpRequest.BodyPublishers.ofString(form));
        }
        return HTTP.send(b.build(), HttpResponse.BodyHandlers.ofString()).body();
    }

    static String enc(String s) { return URLEncoder.encode(s, StandardCharsets.UTF_8); }

    @Given("the links app has its two starting links")
    public void start() throws Exception { send("/reset", ""); page = send("/", null); }

    @When("I add the link {string} with the URL {string}")
    public void add(String title, String url) throws Exception { page = send("/add", "title=" + enc(title) + "&url=" + enc(url)); }

    @Then("I see {int} links")
    public void count(int n) {
        int c = 0;
        Matcher m = Pattern.compile("data-testid=\"link\"").matcher(page);
        while (m.find()) c++;
        if (c != n) throw new AssertionError("expected " + n + " links, found " + c);
    }

    @Then("I see a link named {string}")
    public void named(String name) {
        if (!page.contains(">" + name + "</a>")) throw new AssertionError("no link named " + name);
    }

    @Then("I see the error {string}")
    public void error(String text) {
        Matcher m = Pattern.compile("role=\"alert\"[^>]*>([^<]*)<").matcher(page);
        String got = m.find() ? m.group(1) : "none";
        if (!got.equals(text)) throw new AssertionError("the error was: " + got);
    }
}
EOF
        slowwarn "cucumber-jvm (Java, Maven): links.feature" 'cd testing/cucjvm && mvn -q -B compile dependency:build-classpath -Dmdep.outputFile=cp.txt > mvn.log 2>&1 || { tail -n 15 mvn.log; exit 1; }; BASE_URL=$LINKS_URL java -cp "target/classes:$(cat cp.txt)" io.cucumber.core.cli.Main --glue links --plugin progress --plugin summary features' 900
    fi
fi

if has install-robot; then
    check "Robot Framework: robot, rebot, libdoc and rfbrowser in ~/.local/bin" 'for c in robot rebot libdoc rfbrowser; do [ -x "$HOME/.local/bin/$c" ] || { echo "missing: ~/.local/bin/$c"; exit 1; }; done; robot --version | head -n 1'
    hint  "rerun setup with install-robot (uv tool install robotframework ... --with-executables-from robotframework-browser)"
    check "Robot's tool venv is on Debian's Python, with its three libraries" 'd=$HOME/.local/share/uv/tools/robotframework; grep "^home = " "$d/pyvenv.cfg"; grep -q "^home = /usr/bin$" "$d/pyvenv.cfg" && "$d/bin/python" -c "import Browser, SeleniumLibrary, RequestsLibrary; print(\"Browser\", Browser.__version__)"'
    hint  "rerun setup with install-robot: it reinstalls the tool on /usr/bin/python3"
    check "the Browser library's Node side is in place (rfbrowser init)" 'w=$("$HOME/.local/share/uv/tools/robotframework/bin/python" -c "import Browser, os; print(os.path.join(os.path.dirname(Browser.__file__), \"wrapper\"))"); ls -d "$w/node_modules/playwright" "$w/node_modules/@grpc/grpc-js"'
    hint  "rerun setup with install-robot (rfbrowser init --skip-browsers needs npm, which install-node provides)"
    cat > "$WORK/testing/links_browser.robot" << 'EOF'
*** Settings ***
Documentation     The links app through Robot Framework's Browser library (Playwright) on the system Chrome.
Library           Browser
Library           RequestsLibrary
Suite Setup       New Browser    chromium    headless=True    channel=chrome
Suite Teardown    Close Browser    ALL
Test Setup        Start With Two Links

*** Variables ***
${BASE_URL}       http://127.0.0.1:8000

*** Test Cases ***
Add A Link
    Add Link    Behat    https://behat.org/
    Get Element Count    css=[data-testid=link]    ==    3
    Get Text    css=#links    contains    Behat

A Link Needs A Web Address
    Add Link    Broken    ftp://example.org/
    Get Text    css=[role=alert]    ==    URL must start with http:// or https://.
    Get Element Count    css=[data-testid=link]    ==    2

*** Keywords ***
Start With Two Links
    POST    ${BASE_URL}/reset
    New Page    ${BASE_URL}/

Add Link
    [Arguments]    ${title}    ${url}
    Fill Text    id=title    ${title}
    Fill Text    id=url    ${url}
    Click    id=add
EOF
    cat > "$WORK/testing/links_selenium.robot" << 'EOF'
*** Settings ***
Documentation     The links app through SeleniumLibrary: headless Chrome, chromedriver from Selenium Manager.
Library           SeleniumLibrary
Library           RequestsLibrary
Suite Setup       Open Browser    about:blank    headlesschrome
Suite Teardown    Close All Browsers

*** Variables ***
${BASE_URL}       http://127.0.0.1:8000

*** Test Cases ***
Add A Link
    POST    ${BASE_URL}/reset
    Go To    ${BASE_URL}/
    Input Text    id:title    Robot
    Input Text    id:url    https://robotframework.org/
    Click Button    id:add
    Wait Until Page Contains Element    link:Robot
    Page Should Contain Element    css:[data-testid=link]    limit=3
EOF
    cat > "$WORK/testing/links_requests.robot" << 'EOF'
*** Settings ***
Documentation     The links app's JSON through RequestsLibrary (no browser).
Library           RequestsLibrary
Library           Collections

*** Variables ***
${BASE_URL}       http://127.0.0.1:8000

*** Test Cases ***
The JSON List Has The Two Starting Links
    POST    ${BASE_URL}/reset
    ${resp}=    GET    ${BASE_URL}/links.json    expected_status=200
    Length Should Be    ${resp.json()}    2
    Should Be Equal    ${resp.json()}[0][title]    Debian
EOF
    check "Robot: RequestsLibrary reads the app's JSON"        'cd testing && robot --outputdir rf-requests --variable "BASE_URL:$LINKS_URL" --console dotted links_requests.robot'
    slow  "Robot: Browser library suite on the system Chrome (channel=chrome)" 'cd testing && robot --outputdir rf-browser --variable "BASE_URL:$LINKS_URL" --console dotted links_browser.robot && ls rf-browser/log.html' 300
    hint  "the full log: $WORK/testing/rf-browser/log.html (removed at exit; run the suite by hand to keep it)"
    if has install-selenium; then
        slow  "Robot: SeleniumLibrary suite (headless Chrome)" 'cd testing && SE_AVOID_STATS=true robot --outputdir rf-selenium --variable "BASE_URL:$LINKS_URL" --console dotted links_selenium.robot' 300
    fi
fi

if has install-cypress; then
    check "Cypress's system libraries (Debian 13's t64 names, Xvfb)" 'for p in libgtk-3-0t64 libgbm-dev libnotify-dev libnss3 libxss1 libasound2t64 libxtst6 xauth xvfb; do dpkg_has "$p" || { echo "missing: $p"; exit 1; }; done; echo all there'
    hint  "rerun setup with install-cypress"
    check "~/.bashrc has the dev-setup cypress block (no crash reports)" 'grep -q "^# >>> dev-setup cypress >>>$" ~/.bashrc && grep -q "^export CYPRESS_CRASH_REPORTS=0$" ~/.bashrc'
    hint  "rerun setup with install-cypress"
    mkdir -p "$WORK/testing/cy/cypress/e2e"
    cat > "$WORK/testing/cy/package.json" << 'EOF'
{ "name": "dev-test-cypress", "private": true, "allowScripts": { "cypress": true } }
EOF
    cat > "$WORK/testing/cy/cypress.config.js" << 'EOF'
const { defineConfig } = require('cypress')
module.exports = defineConfig({
  e2e: { baseUrl: process.env.BASE_URL, supportFile: false, video: false, screenshotOnRunFailure: false },
})
EOF
    cat > "$WORK/testing/cy/cypress/e2e/links.cy.js" << 'EOF'
describe('links', () => {
  beforeEach(() => {
    cy.request('POST', '/reset')
    cy.visit('/')
    cy.get('[data-testid=link]').should('have.length', 2)
  })
  it('adds a link', () => {
    cy.get('#title').type('Cypress')
    cy.get('#url').type('https://www.cypress.io/')
    cy.contains('button', 'Add link').click()
    cy.get('[data-testid=link]').should('have.length', 3)
    cy.contains('a', 'Cypress')
  })
  it('needs a web address', () => {
    cy.get('#title').type('Broken')
    cy.get('#url').type('ftp://example.org/')
    cy.contains('button', 'Add link').click()
    cy.get('[role=alert]').should('have.text', 'URL must start with http:// or https://.')
    cy.get('[data-testid=link]').should('have.length', 2)
  })
})
EOF
    slow  "Cypress installs into a scratch project (its install script allowed) and verifies" 'cd testing/cy && npm install -D --no-audit --no-fund cypress > npm.log 2>&1 || { tail -n 15 npm.log; exit 1; }; npx cypress install > install.log 2>&1 || { tail -n 10 install.log; exit 1; }; CYPRESS_CRASH_REPORTS=0 npx cypress verify' 900
    hint  "the first run downloads Cypress's Electron build (~250 MB) into ~/.cache/Cypress; 'npx cypress cache prune' later"
    if [ "$LAST" = pass ]; then
        slow  "Cypress: the links spec headless in Electron"   'cd testing/cy && BASE_URL=$LINKS_URL CYPRESS_CRASH_REPORTS=0 npx cypress run --browser electron' 600
        hint  "a GPU error from Electron: uncomment ELECTRON_EXTRA_LAUNCH_ARGS=--disable-gpu in ~/.bashrc's dev-setup cypress block"
        slow  "Cypress: the same spec in the system Chrome (--browser chrome)" 'cd testing/cy && BASE_URL=$LINKS_URL CYPRESS_CRASH_REPORTS=0 npx cypress run --browser chrome' 600
    fi
fi
if [ -n "${LINKS_PID:-}" ]; then
    kill "$LINKS_PID" 2> /dev/null
    LINKS_PID=""
fi

# =================================================================
# GitLab and Vue.js (v91): install-gitlab (glab, gitlab-ci-local), install-gitlab-runner (opt-in) and
# install-vue. The pipeline checks run a small .gitlab-ci.yml in a scratch git repository: shell jobs offline, a
# Docker job with a Redis service as a slow check (it pulls redis:8-alpine). The Vue checks scaffold create-vue and
# Nuxt projects in the temp dir and install their packages (slow; they warm ~/.npm). Nothing reaches gitlab.com
# unless glab is logged in, and then only 'glab auth status'.
# =================================================================
if has install-gitlab; then
    section "GitLab: glab, gitlab-ci-local$(has install-gitlab-runner && echo ', GitLab Runner') (install-gitlab)"
    check "glab (GitLab's CLI, from Homebrew)"                'v=$(glab version 2>&1 | head -n 1); echo "$v"; echo "$v" | grep -qi "glab"; w=$(command -v glab); case "$w" in /home/linuxbrew/*) ;; *) echo "glab on PATH is $w, not Homebrew'"'"'s"; exit 1 ;; esac'
    hint  "rerun setup with install-gitlab (brew install glab); Debian's own glab package is years behind"
    warn  "glab's bash completion"                            '[ -s ~/.local/share/bash-completion/completions/glab ]'
    warn  "glab is logged in (only if GITLAB_TOKEN_ONCE is set)"   'set -a; [ -f ~/.config/dev-init/secrets.env ] && . ~/.config/dev-init/secrets.env; set +a; if [ -z "${GITLAB_TOKEN_ONCE:-}" ] && ! grep -qs "token:" ~/.config/glab-cli/config.yml; then echo "SKIPPED: no GITLAB_TOKEN_ONCE (optional)"; exit 0; fi; timeout 60 glab auth status 2>&1 | tail -n 6; timeout 60 glab auth status > /dev/null 2>&1'
    hint  "dev-init logs glab in with GITLAB_TOKEN_ONCE from secrets.env (scopes api, write_repository)"
    check "gitlab-ci-local, with git and rsync"               'gitlab-ci-local --version && command -v git > /dev/null && command -v rsync > /dev/null || { echo "missing: $(for c in gitlab-ci-local git rsync; do command -v "$c" > /dev/null || printf "%s " "$c"; done)"; exit 1; }'
    hint  "rerun setup with install-gitlab (npm install -g gitlab-ci-local, apt install rsync)"
    mkdir -p "$WORK/gitlab/pipeline"
    cat > "$WORK/gitlab/pipeline/.gitlab-ci.yml" << 'EOF'
# dev-test's pipeline for gitlab-ci-local: jobs without an image run in the shell, the rest in Docker.
stages: [build, test]

variables:
  GREETING: "hello from gitlab-ci-local"

build:
  stage: build
  script:
    - mkdir -p out
    - echo "$GREETING" > out/greeting.txt
  artifacts:
    paths: [out/]

test:
  stage: test
  needs: [build]
  script:
    - grep -q "hello from gitlab-ci-local" out/greeting.txt
    - echo "artifact received"

redis-service:
  stage: test
  image: redis:8-alpine
  needs: []
  services:
    - name: redis:8-alpine
      alias: cache
  script:
    - redis-cli -h cache ping | grep -q PONG
    - echo "the service answered"
EOF
    ( cd "$WORK/gitlab/pipeline" && git init -q -b main && git remote add origin https://gitlab.com/dev-test/pipeline.git \
        && git config user.name dev-test && git config user.email dev-test@localhost \
        && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main \
        && git add -A && git commit -qm pipeline ) > /dev/null 2>&1
    check "gitlab-ci-local lists the pipeline's jobs"          'cd gitlab/pipeline && gitlab-ci-local --list 2> /dev/null | tee list.out; grep -q "redis-service" list.out'
    check "gitlab-ci-local: stages, needs and an artifact, in the shell" 'cd gitlab/pipeline && gitlab-ci-local build test > run.log 2>&1; rc=$?; grep -E "PASS|FAIL|artifact" run.log; [ $rc = 0 ] && grep -q "PASS  *test" run.log' 180
    slow  "gitlab-ci-local: a job with an image and a Redis service, in Docker" 'cd gitlab/pipeline && gitlab-ci-local redis-service > docker.log 2>&1; rc=$?; grep -E "PASS|FAIL|answered" docker.log; [ $rc = 0 ] && grep -q "PASS  *redis-service" docker.log' 600
    hint  "it pulls redis:8-alpine and gitlab-ci-local's helper image from Docker Hub; 'docker info' must work for $(id -un)"
    if has install-gitlab-runner; then
        check "gitlab-runner installed, its service active"  'gitlab-runner --version | head -n 1 && systemctl is-active gitlab-runner'
        hint  "rerun setup with install-gitlab-runner; 'sudo systemctl status gitlab-runner' says why it stopped"
        check "the gitlab-runner user is in the docker group (Docker executor)" 'id -nG gitlab-runner | tr " " "\n" | grep -qx docker'
        warn  "the runner is registered and GitLab knows it (only if GITLAB_RUNNER_TOKEN_ONCE is set)" 'set -a; [ -f ~/.config/dev-init/secrets.env ] && . ~/.config/dev-init/secrets.env; set +a; if ! sudo -n grep -qs "^\[\[runners\]\]" /etc/gitlab-runner/config.toml; then if [ -z "${GITLAB_RUNNER_TOKEN_ONCE:-}" ]; then echo "SKIPPED: not registered and no GITLAB_RUNNER_TOKEN_ONCE (optional)"; exit 0; fi; echo "GITLAB_RUNNER_TOKEN_ONCE is set but the runner is not registered: run dev-init with install-gitlab-runner"; exit 1; fi; timeout 60 sudo -n gitlab-runner verify 2>&1 | tail -n 3; timeout 60 sudo -n gitlab-runner verify 2>&1 | grep -qi "is valid\|is alive"' 90
    fi
fi

if has install-vue; then
    section "Vue.js: create-vue (Vite, Router, Pinia, Vitest, Playwright) and Nuxt (install-vue)"
    check "create-vue answers from npx's cache"              'timeout 60 npx -y --prefer-offline create-vue@latest --help | head -n 1'
    hint  "rerun setup with install-vue (it warms npx's cache)"
    mkdir -p "$WORK/vue"
    slow  "create-vue scaffolds a TypeScript app with Router, Pinia, Vitest and Playwright" 'cd vue && npx -y --prefer-offline create-vue@latest vapp --ts --router --pinia --vitest --playwright --eslint > new.log 2>&1 || { tail -n 10 new.log; exit 1; }; cd vapp && npm install --no-audit --no-fund > npm.log 2>&1 || { tail -n 15 npm.log; exit 1; }; npm ls vue --depth=0 | grep vue@' 600
    if [ "$LAST" = pass ]; then
        cat > "$WORK/vue/vapp/playwright.chrome.config.ts" << 'EOF'
import { defineConfig, devices } from '@playwright/test'
import base from './playwright.config'

// dev-test: create-vue's Playwright setup (its preview server on :4173) on the system Chrome only.
export default defineConfig({ ...base, reporter: 'line', projects: [{ name: 'chrome', use: { ...devices['Desktop Chrome'], channel: 'chrome' } }] })
EOF
        check "Vue: Vitest runs the scaffold's component test"   'cd vue/vapp && npx vitest run 2>&1 | tail -n 5; npx vitest run > /dev/null 2>&1' 180
        check "Vue: type-check and build (vue-tsc, Vite)"        'cd vue/vapp && npm run build > build.log 2>&1; rc=$?; tail -n 4 build.log; [ $rc = 0 ] && [ -f dist/index.html ]' 300
        slow  "Vue: the scaffold's Playwright test on the system Chrome" 'cd vue/vapp && CI=1 npx playwright test -c playwright.chrome.config.ts' 300
        hint  "port 4173 busy? 'ss -ltnp | grep 4173' (vite preview serves the build there)"
    fi
    slow  "Nuxt: scaffold from the cached template, install, build" 'cd vue && npx -y --prefer-offline create-nuxt@latest nuxapp --template minimal --packageManager npm --gitInit=false --no-install --preferOffline > new.log 2>&1 || { tail -n 10 new.log; exit 1; }; cd nuxapp && printf "%s\n" "<template>" "  <main><h1>Hello from Nuxt</h1><p data-testid=\"ssr\">rendered on the server</p></main>" "</template>" > app/app.vue && npm install --no-audit --no-fund > npm.log 2>&1 || { tail -n 15 npm.log; exit 1; }; npx nuxt build > build.log 2>&1 || { tail -n 15 build.log; exit 1; }; ls .output/server/index.mjs' 900
    if [ "$LAST" = pass ]; then
        check "Nuxt: the built server renders the page on the server" 'cd vue/nuxapp && p=$(python3 -c "import socket; s=socket.socket(); s.bind((\"127.0.0.1\",0)); print(s.getsockname()[1])"); HOST=127.0.0.1 PORT=$p node .output/server/index.mjs > srv.log 2>&1 & pid=$!; trap "kill $pid 2>/dev/null" EXIT; for _ in $(seq 1 30); do curl -fsS "http://127.0.0.1:$p/" -o page.html 2>/dev/null && break; sleep 1; done; grep -o "rendered on the server" page.html' 90
    fi
fi

# =================================================================
# Puppet and Chef (v91): install-puppet (OpenVox, OpenBolt) and install-chef (Cinc Workstation), opt-in, both in
# install-config-mgmt. Masterless throughout: 'puppet apply' and 'cinc-client --local-mode' converge small
# configurations into the temp dir (a second run must change nothing), Bolt runs a command here and a plan
# in a scratch debian:trixie-slim container, and Test Kitchen converges and verifies a cookbook in a Dokken
# container (the container checks are slow and pull images from Docker Hub).
# =================================================================
if has install-puppet; then
    section "Puppet: OpenVox (puppet, facter) and OpenBolt (install-puppet)"
    check "OpenVox's puppet and facter (/opt/puppetlabs/bin)"  'dpkg-query -W -f="\${Package} \${Version}\n" openvox-agent && for c in puppet facter; do [ "$(command -v "$c")" = "/opt/puppetlabs/bin/$c" ] || { echo "$c is $(command -v "$c" || echo missing), not /opt/puppetlabs/bin/$c"; exit 1; }; done; puppet --version'
    hint  "rerun setup with install-puppet; a Perforce or Debian puppet-agent must be removed first (setup says so)"
    check "facter reports this Debian"                         'facter os.name os.release.major; facter os.name | grep -qx Debian'
    check "the agent service stays off (masterless)"           '! systemctl is-active --quiet puppet && ! systemctl is-enabled --quiet puppet 2> /dev/null; s=$?; echo "puppet service: $(systemctl is-enabled puppet 2>&1 | head -n 1)"; exit $s'
    hint  "sudo systemctl disable --now puppet (setup does it): with no server, the agent only logs failures"
    mkdir -p "$WORK/puppet" "$WORK/bolt/plans"
    cat > "$WORK/puppet/site.pp" << 'EOF'
# dev-test: a directory and a file with facts in it, under FACTER_devtest_out (a fact from the environment).
$out = $facts['devtest_out']

file { "${out}/puppet":
  ensure => directory,
}

file { "${out}/puppet/hello.txt":
  ensure  => file,
  content => "puppet ok on ${facts['os']['name']} ${facts['os']['release']['major']}\n",
  mode    => '0644',
}
EOF
    check "puppet parser validate"                             'cd puppet && puppet parser validate site.pp'
    check "puppet apply converges, a second run changes nothing" 'cd puppet && export FACTER_devtest_out=$PWD; puppet apply --detailed-exitcodes site.pp > run1.log 2>&1; rc=$?; [ $rc = 0 ] || [ $rc = 2 ] || { tail -n 10 run1.log; exit 1; }; cat puppet/hello.txt; grep -q "puppet ok on Debian" puppet/hello.txt || exit 1; puppet apply --detailed-exitcodes site.pp > run2.log 2>&1; rc=$?; echo "second run: exit $rc (0 = nothing to change)"; [ $rc = 0 ]' 180
    check "puppet apply --noop reports a change and makes none" 'cd puppet && export FACTER_devtest_out=$PWD; rm -f puppet/hello.txt; puppet apply --noop site.pp > noop.log 2>&1; grep -m1 "(noop)" noop.log; grep -q "(noop)" noop.log && [ ! -e puppet/hello.txt ]' 120
    cat > "$WORK/bolt/bolt-project.yaml" << 'EOF'
---
name: devtest
EOF
    cat > "$WORK/bolt/plans/hello.yaml" << 'EOF'
# devtest::hello: two commands on the targets (no agent needed on them), the first one's output returned.
parameters:
  targets:
    type: TargetSpec

steps:
  - name: release
    command: cat /etc/debian_version
    targets: $targets
  - name: mark
    command: touch /tmp/bolt-ok
    targets: $targets

return: $release
EOF
    check "OpenBolt runs a command on localhost"                'cd bolt && bolt --version && bolt command run "uname -s" --targets localhost 2>&1 | tee run.log | tail -n 4; grep -q Linux run.log' 120
    hint  "setup installs openbolt from the OpenVox repositories; 'bolt' must resolve to /opt/puppetlabs/bin/bolt"
    slow  "OpenBolt: a plan in a debian:trixie-slim container (docker transport)" 'cd bolt && docker rm -f devtest-bolt > /dev/null 2>&1; trap "docker rm -f devtest-bolt > /dev/null 2>&1" EXIT; docker run -d --name devtest-bolt debian:trixie-slim sleep 600 > /dev/null || exit 1; bolt plan run devtest::hello --targets docker://devtest-bolt 2>&1 | tail -n 6; docker exec devtest-bolt test -f /tmp/bolt-ok' 600
    hint  "needs the docker group active in this shell and Docker Hub reachable for debian:trixie-slim"
fi

if has install-chef; then
    section "Chef: Cinc Workstation (install-chef)"
    export CHEF_LICENSE=accept-no-persist
    check "Cinc Workstation: cinc-client, knife, kitchen, cookstyle, cinc-auditor" 'dpkg-query -W -f="\${Package} \${Version}\n" cinc-workstation && for c in cinc-client knife kitchen cookstyle cinc-auditor berks; do command -v "$c" > /dev/null || { echo "missing: $c"; exit 1; }; done; cinc-client --version | head -n 1'
    hint  "rerun setup with install-chef; a new terminal has /opt/cinc-workstation/bin on PATH"
    warn  "knife and kitchen are Cinc's (not Progress's Chef Workstation)" 'for c in knife kitchen; do r=$(readlink -f "$(command -v "$c")"); echo "$c -> $r"; case "$r" in /opt/cinc-workstation/*) ;; *) exit 1 ;; esac; done'
    mkdir -p "$WORK/chef/cookbooks/devtest/recipes" "$WORK/chef/cookbooks/devtest/attributes" "$WORK/chef/cookbooks/devtest/spec" \
        "$WORK/chef/cookbooks/devtest/test/integration/default" "$WORK/chef/audit/controls"
    cat > "$WORK/chef/cookbooks/devtest/metadata.rb" << 'EOF'
name 'devtest'
maintainer 'dev-test'
maintainer_email 'dev-test@localhost'
license 'Apache-2.0'
description 'dev-test: a directory and a file with node attributes in it'
version '0.1.0'
chef_version '>= 18.0'
supports 'debian'
EOF
    cat > "$WORK/chef/cookbooks/devtest/attributes/default.rb" << 'EOF'
default['devtest']['out'] = ENV.fetch('DEVTEST_OUT', '/tmp/devtest')
EOF
    cat > "$WORK/chef/cookbooks/devtest/recipes/default.rb" << 'EOF'
out = node['devtest']['out']

directory "#{out}/chef" do
  recursive true
end

file "#{out}/chef/hello.txt" do
  content "chef ok on #{node['platform']} #{node['platform_version']}\n"
  mode '0644'
end
EOF
    cat > "$WORK/chef/cookbooks/devtest/spec/default_spec.rb" << 'EOF'
require 'chefspec'

describe 'devtest::default' do
  platform 'debian'
  default_attributes['devtest']['out'] = '/srv/devtest'

  it { is_expected.to create_directory('/srv/devtest/chef') }
  it { is_expected.to create_file('/srv/devtest/chef/hello.txt').with(mode: '0644') }
end
EOF
    cat > "$WORK/chef/cookbooks/devtest/kitchen.yml" << 'EOF'
# Test Kitchen with Dokken: the cookbook converges in a Debian 13 container with Cinc Client, then cinc-auditor
# (kitchen-inspec) checks it.
driver:
  name: dokken
  chef_image: cincproject/cinc
  chef_version: latest
provisioner:
  name: dokken
  product_name: cinc
  chef_binary: /opt/cinc/bin/cinc-client
transport:
  name: dokken
verifier:
  name: inspec
platforms:
  - name: debian-13
    driver:
      image: dokken/debian-13
suites:
  - name: default
    run_list:
      - recipe[devtest::default]
EOF
    cat > "$WORK/chef/cookbooks/devtest/test/integration/default/default_test.rb" << 'EOF'
describe file('/tmp/devtest/chef/hello.txt') do
  it { should exist }
  its('content') { should match(/^chef ok on debian/) }
end
EOF
    cat > "$WORK/chef/client.rb" << 'EOF'
# cinc-client --local-mode, everything under this directory.
cookbook_path [File.join(__dir__, 'cookbooks')]
node_path File.join(__dir__, 'nodes')
file_cache_path File.join(__dir__, 'cache')
EOF
    cat > "$WORK/chef/audit/inspec.yml" << 'EOF'
name: devtest-audit
title: dev-test's check of the converged file
version: 0.1.0
supports:
  - platform: linux
EOF
    cat > "$WORK/chef/audit/controls/hello.rb" << 'EOF'
control 'devtest-hello' do
  title 'cinc-client wrote the file'
  describe file(File.join(ENV.fetch('DEVTEST_OUT'), 'chef/hello.txt')) do
    it { should exist }
    its('content') { should match(/^chef ok on debian/) }
  end
end
EOF
    check "cinc-client --local-mode converges, a second run updates nothing" 'cd chef && export DEVTEST_OUT=$PWD; cinc-client -c client.rb -z -o "recipe[devtest]" > run1.log 2>&1 || { tail -n 15 run1.log; exit 1; }; cat chef/hello.txt; grep -q "^chef ok on debian" chef/hello.txt || exit 1; cinc-client -c client.rb -z -o "recipe[devtest]" > run2.log 2>&1 || { tail -n 15 run2.log; exit 1; }; grep -E "resources updated" run2.log | tail -n 1; grep -qE " 0/[0-9]+ resources updated" run2.log' 300
    check "cinc-auditor checks the converged file"               'cd chef && DEVTEST_OUT=$PWD cinc-auditor exec audit --no-color 2>&1 | tail -n 4; DEVTEST_OUT=$PWD cinc-auditor exec audit > /dev/null 2>&1' 180
    warn  "Cookstyle passes the cookbook"                         'cd chef/cookbooks/devtest && cookstyle --format progress . 2>&1 | tail -n 4; cookstyle . > /dev/null 2>&1'
    slowwarn "ChefSpec: the recipe's resources in a simulated Debian run" 'cd chef/cookbooks/devtest && /opt/cinc-workstation/embedded/bin/rspec 2>&1 | tail -n 4; /opt/cinc-workstation/embedded/bin/rspec > /dev/null 2>&1' 300
    slowwarn "Test Kitchen + Dokken: converge and verify in a Debian 13 container" 'cd chef/cookbooks/devtest && trap "kitchen destroy > /dev/null 2>&1" EXIT; kitchen test --destroy=always > kitchen.log 2>&1; rc=$?; grep -E "Finished|resources updated|examples|successful|failure" kitchen.log | tail -n 6; exit $rc' 1200
    hint  "it pulls cincproject/cinc and dokken/debian-13 from Docker Hub; 'kitchen.log' in the temp dir has the rest (run with verbose to see it)"
fi

# =================================================================
# Shared development services (v89): install-cache = install-redis + install-memcached, install-search
# = install-solr + install-opensearch + install-meilisearch + install-typesense, install-vector =
# install-qdrant + sqlite-vec, install-mongodb, and the opt-in install-elasticsearch, install-milvus and
# install-mongodb-atlas-local, all run through the 'devsvc' command (v91: and the Selenium Grid, install-selenium). The quick checks look at the command, the keys file and each
# container's settings (127.0.0.1 only, restart policy per DEVSVC_AUTOSTART, the memory guard). The
# round-trips start a stopped service with 'devsvc up' (DEVSVC_FORCE=1, so the budget never hides a
# broken service), write, read and delete a record, and leave the service as the test found it. The
# client-library checks (Python through uv, Node through a scratch npm install) download packages,
# so they are slow checks and only WARN.
# =================================================================
SVC_HAVE=""
for _s in redis memcached solr opensearch elasticsearch meilisearch typesense qdrant milvus mongodb selenium; do has "install-$_s" && SVC_HAVE+=" $_s"; done
has install-mongodb-atlas-local && SVC_HAVE+=" atlas-local"
SVC_HAVE=${SVC_HAVE# }
if [ -n "$SVC_HAVE" ]; then
    section "Shared services (devsvc): $SVC_HAVE"
    # svc_up.sh NAME: remember whether it ran, then start it. svc_restore.sh NAME: stop it again if
    # the test started it.
    cat > "$WORK/svc_up.sh" << 'EOF'
n=$1; c=devsvc-$n
st=$(docker inspect -f '{{.State.Running}}' "$c" 2> /dev/null) || { echo "no $c container (rerun setup with install-$n)"; exit 1; }
[ -f "svc_$n.was" ] || echo "$st" > "svc_$n.was"
echo "$c was $( [ "$st" = true ] && echo running || echo stopped) before the test"
DEVSVC_FORCE=1 devsvc up "$n" > "svc_$n.up" 2>&1; rc=$?; head -n 2 "svc_$n.up"; exit $rc
EOF
    cat > "$WORK/svc_restore.sh" << 'EOF'
n=$1
[ -f "svc_$n.was" ] || { echo "the test did not touch $n"; exit 0; }
now=$(docker inspect -f '{{.State.Running}}' "devsvc-$n" 2> /dev/null)
if [ "$(cat "svc_$n.was")" != true ]; then
    if [ "$now" = true ]; then devsvc down "$n"; else echo "devsvc-$n is stopped, as before the test"; fi
elif [ "$now" = true ]; then echo "devsvc-$n was running: left running"
else echo "devsvc-$n was running before the test (another Java engine stopped it): starting it again"; DEVSVC_FORCE=1 devsvc up "$n" > /dev/null; fi
EOF
    # svc_release NAME: once a service's checks are done, stop it again if the test started it, so the
    # services the test starts never all run at once (their caps add up to more than the ~6.4 GB Linux
    # has). Services that ran before the test are put back at the end of the section.
    svc_release() {
        [ -f "$WORK/svc_$1.was" ] && [ "$(cat "$WORK/svc_$1.was")" != true ] || return 0
        check "devsvc-$1 stopped again (the test started it)" "bash svc_restore.sh $1"
        mv "$WORK/svc_$1.was" "$WORK/svc_$1.released"
    }
    # rcli ARGS: redis-cli against the shared Redis, with REDIS_PASSWORD from devsvc.env when set
    cat > "$WORK/rcli" << 'EOF'
#!/bin/bash
REDIS_PASSWORD=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${REDIS_PASSWORD:-}"' _ "$HOME/.config/devsvc/devsvc.env")
[ -n "$REDIS_PASSWORD" ] && export REDISCLI_AUTH="$REDIS_PASSWORD"
exec redis-cli -h 127.0.0.1 -p 6379 --no-auth-warning "$@"
EOF
    chmod +x "$WORK/rcli"
    # jq filter over 'docker inspect': 127.0.0.1-only port, and the restart policy DEVSVC_AUTOSTART asks for
    cat > "$WORK/devsvc.jq" << 'EOF'
.[0] as $c
| ($c.HostConfig.PortBindings[$port] // []) as $b
| "image   \($c.Config.Image)",
  "port    \($b | map(.HostIp + ":" + .HostPort) | join(" "))",
  "start   \($c.HostConfig.RestartPolicy.Name) (wanted \($policy))",
  if ($b | length) > 0 and all($b[]; .HostIp == "127.0.0.1") and $c.HostConfig.RestartPolicy.Name == $policy
  then "as setup creates it" else error("not the way setup creates it") end
EOF
    DEVSVC_AUTO=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${DEVSVC_AUTOSTART:-}"' _ ~/.config/dev-init/secrets.env 2> /dev/null)
    [ -n "$DEVSVC_AUTO" ] || DEVSVC_AUTO="redis memcached"
    # The client checks (PHP, Python, Node, a DDEV container) take Redis's password from REDISCLI_AUTH.
    REDISCLI_AUTH=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${REDIS_PASSWORD:-}"' _ ~/.config/devsvc/devsvc.env 2> /dev/null)
    if [ -n "$REDISCLI_AUTH" ]; then export REDISCLI_AUTH; else unset REDISCLI_AUTH; fi
    svc_policy() { if [[ " $(echo "$DEVSVC_AUTO" | tr ',;' '  ') " == *" $1 "* ]]; then echo unless-stopped; else echo no; fi; }

    check "the devsvc command, and ~/.config/devsvc/devsvc.env (mode 600)" '[ -x ~/.local/bin/devsvc ] || { echo "no ~/.local/bin/devsvc"; exit 1; }; f=$HOME/.config/devsvc/devsvc.env; [ -f "$f" ] || { echo "no $f"; exit 1; }; m=$(stat -c %a "$f"); echo "mode $m"; [ "$m" = 600 ] && devsvc status'
    hint  "rerun setup with install-cache: it writes both"
    check "memory guard: refuses past DEVSVC_RAM_MB, allows within it" 'DEVSVC_RAM_MB=1 devsvc fits '"${SVC_HAVE%% *}"' 2>&1; rc=$?; echo "(DEVSVC_RAM_MB=1: exit $rc)"; [ "$rc" = 3 ] && DEVSVC_RAM_MB=100000 devsvc fits '"${SVC_HAVE%% *}"
    hint  "the devsvc in ~/.local/bin is older than setup v89's: rerun setup with install-cache"

    if has install-redis; then
        check "redis-cli (Debian's redis-tools)"                  'redis-cli --version; [ "$(readlink -f "$(command -v redis-cli)")" = /usr/bin/redis-cli ]'
        hint  "rerun setup with install-redis (apt install redis-tools); a Homebrew redis-cli first on PATH is the v68 shadowing problem"
        check "devsvc-redis container: 127.0.0.1:6379, start policy per DEVSVC_AUTOSTART" "docker inspect devsvc-redis > rd.json || exit 1; jq -r -e --arg port 6379/tcp --arg policy $(svc_policy redis) -f devsvc.jq rd.json"
        hint  "no such container: rerun setup with install-redis. A different start policy: DEVSVC_AUTOSTART changed since setup ran; rerun it. 'permission denied': open a new terminal (docker group)"
        if docker container inspect devsvc-redis > /dev/null 2>&1; then
            check "Redis starts and answers PING (devsvc up redis)"   'bash svc_up.sh redis && ./rcli ping | grep -q PONG'
            hint  "'devsvc logs redis' shows the server's side. NOAUTH: REDIS_PASSWORD in secrets.env changed since setup ran; rerun setup with install-redis"
            check "Redis 8 with its modules: search, JSON, time series, bloom" './rcli INFO server | grep -E "^redis_version"; m=$(./rcli MODULE LIST | tr "[:upper:]" "[:lower:]"); for x in search "(re)?json" timeseries bf; do echo "$m" | grep -qxE "$x" || { echo "module missing: $x (loaded: $(echo "$m" | grep -vE "^(name|ver|path|args|[0-9]+)$" | xargs))"; exit 1; }; done; echo "modules: search json timeseries bf"'
            hint  "the image's entrypoint loads them: a REDIS_IMAGE other than redis:8 (e.g. Valkey or redis:7) has none"
            check "Redis: write, read and delete a key"                './rcli SET devtest:key hello > /dev/null && [ "$(./rcli GET devtest:key)" = hello ] && ./rcli DEL devtest:key | grep -qx 1 && echo "SET, GET and DEL worked"'
            check "Redis: JSON document and a vector search (FT.CREATE + KNN)" 'python3 -c "import struct,sys; open(\"a.bin\",\"wb\").write(struct.pack(\"<2f\",1,0)); open(\"b.bin\",\"wb\").write(struct.pack(\"<2f\",0,1)); open(\"q.bin\",\"wb\").write(struct.pack(\"<2f\",0.9,0.1))"
./rcli FT.DROPINDEX devtest_idx DD > /dev/null 2>&1
./rcli JSON.SET devtest:json "\$" "{\"airport\":\"DCA\",\"delay\":5}" > /dev/null && [ "$(./rcli JSON.GET devtest:json "\$.airport")" = "[\"DCA\"]" ] || { echo "JSON.SET / JSON.GET failed"; exit 1; }
./rcli DEL devtest:json > /dev/null; echo "JSON.SET / JSON.GET worked"
./rcli FT.CREATE devtest_idx ON HASH PREFIX 1 devtest:v: SCHEMA name TEXT emb VECTOR FLAT 6 TYPE FLOAT32 DIM 2 DISTANCE_METRIC L2 | grep -q OK || exit 1
./rcli HSET devtest:v:a name alpha > /dev/null; ./rcli -x HSET devtest:v:a emb < a.bin > /dev/null
./rcli HSET devtest:v:b name beta > /dev/null;  ./rcli -x HSET devtest:v:b emb < b.bin > /dev/null
r=$(./rcli -x FT.SEARCH devtest_idx "*=>[KNN 1 @emb \$q AS dist]" RETURN 1 name DIALECT 2 PARAMS 2 q < q.bin); echo "nearest to (0.9, 0.1): $(echo "$r" | tr "\n" " ")"
./rcli FT.DROPINDEX devtest_idx DD > /dev/null
echo "$r" | grep -qx alpha'
            hint  "an unknown command means the modules are not loaded (the check above)"
            if bash -c '. ~/.config/devsvc/devsvc.env 2> /dev/null; [ -n "${REDIS_PASSWORD:-}" ]'; then
                check "Redis refuses a client without REDIS_PASSWORD"   'r=$(env -u REDISCLI_AUTH redis-cli -h 127.0.0.1 -p 6379 ping 2>&1); echo "$r"; echo "$r" | grep -q NOAUTH'
            else
                info  "Redis login" "none (127.0.0.1 only; set REDIS_PASSWORD in secrets.env before sharing Redis)"
            fi
            if has install-web; then
                check "PHP's redis extension (phpredis) talks to it"   'php -m | grep -qix redis || { echo "PHP has no redis extension (php-redis, install-web)"; exit 1; }; php -r "\$r = new Redis(); \$r->connect(\"127.0.0.1\", 6379); \$p = getenv(\"REDISCLI_AUTH\"); if (\$p) \$r->auth(\$p); \$r->set(\"devtest:php\", \"ok\"); echo \"phpredis \", phpversion(\"redis\"), \": \", \$r->get(\"devtest:php\"), PHP_EOL; \$r->del(\"devtest:php\");" | tee /dev/stderr | grep -q ": ok"'
                hint  "rerun setup with install-web (php-redis)"
            fi
            slowwarn "Python client (redis-py through uv, throwaway env)" 'uv run --no-project --with redis python -c "import os, redis; r = redis.Redis(password=os.environ.get(\"REDISCLI_AUTH\") or None); r.set(\"devtest:py\", \"ok\"); print(\"redis-py\", redis.__version__, r.get(\"devtest:py\")); r.delete(\"devtest:py\")" | grep -q "ok"' 300
            has install-node && slowwarn "Node client (node-redis, scratch npm install)" 'mkdir -p redis-js && cd redis-js && npm init -y > /dev/null && npm install --silent --no-audit --no-fund redis && node -e "const {createClient}=require(\"redis\");(async()=>{const c=createClient({url:\"redis://127.0.0.1:6379\",password:process.env.REDISCLI_AUTH||undefined});await c.connect();await c.set(\"devtest:js\",\"ok\");console.log(\"node-redis:\",await c.get(\"devtest:js\"));await c.del(\"devtest:js\");await c.quit();})().catch(e=>{console.error(e);process.exit(1)})" | grep -q ok' 300
            hint  "network only: these download the client library; 'devsvc info redis' has the connection settings"
            warn  "devsvc-redis is on DDEV's network as devredis (once a DDEV project has run)" 'if ! docker network inspect ddev_default > /dev/null 2>&1; then echo "SKIPPED: no ddev_default network yet"; exit 0; fi; devsvc ddev | grep "^redis:"; docker inspect -f "{{json .NetworkSettings.Networks.ddev_default.Aliases}}" devsvc-redis | tee /dev/stderr | grep -q "\"devredis\""'
            hint  "'devsvc ddev' joins it (DDEV recreates the network after 'ddev poweroff')"
            slowwarn "a container on DDEV's network reaches devredis:6379" 'if ! docker network inspect ddev_default > /dev/null 2>&1; then echo "SKIPPED: no ddev_default network yet"; exit 0; fi; img=$(docker inspect -f "{{.Config.Image}}" devsvc-redis); docker run --rm --network ddev_default -e REDISCLI_AUTH --entrypoint redis-cli "$img" -h devredis --no-auth-warning ping | grep -q PONG && echo "devredis:6379 answers PONG from ddev_default"' 300
        fi
        warn  "Redis Insight desktop app, in the ChromeOS launcher" 'dpkg-query -W -f="\${Package} \${Version}\n" "redisinsight*" 2> /dev/null | grep . || { echo "Redis Insight is not installed"; exit 1; }; ls /usr/share/applications | grep -i insight'
        hint  "setup downloads it from Redis Insight's GitHub release; its log says why it did not (rerun setup with install-redis). REDIS_INSIGHT=0 skips it on purpose"
    fi
    svc_release redis

    if has install-memcached; then
        check "devsvc-memcached container: 127.0.0.1:11211, start policy per DEVSVC_AUTOSTART" "docker inspect devsvc-memcached > mc.json || exit 1; jq -r -e --arg port 11211/tcp --arg policy $(svc_policy memcached) -f devsvc.jq mc.json"
        hint  "no such container: rerun setup with install-memcached. A different start policy: rerun setup (DEVSVC_AUTOSTART changed)"
        if docker container inspect devsvc-memcached > /dev/null 2>&1; then
            check "Memcached starts and answers (devsvc up memcached)" 'bash svc_up.sh memcached && devsvc cli memcached version | grep "^VERSION"'
            check "Memcached: set, get and delete a key"           'r=$(exec 3<> /dev/tcp/127.0.0.1/11211; printf "set devtest:key 0 60 5\r\nhello\r\nget devtest:key\r\ndelete devtest:key\r\nget devtest:key\r\nquit\r\n" >&3; timeout 5 cat <&3 | tr -d "\r"); echo "$r"; echo "$r" | grep -q "^STORED$" && echo "$r" | grep -qx hello && echo "$r" | grep -q "^DELETED$"'
            if has install-web; then
                check "PHP's memcached extension talks to it"      'php -m | grep -qix memcached || { echo "PHP has no memcached extension (php-memcached, install-web)"; exit 1; }; php -r "\$m = new Memcached(); \$m->addServer(\"127.0.0.1\", 11211); \$m->set(\"devtest:php\", \"ok\", 60); echo \"php-memcached \", phpversion(\"memcached\"), \": \", \$m->get(\"devtest:php\"), PHP_EOL; \$m->delete(\"devtest:php\");" | tee /dev/stderr | grep -q ": ok"'
                hint  "rerun setup with install-web (php-memcached)"
            fi
            slowwarn "Python client (pymemcache through uv, throwaway env)" 'uv run --no-project --with pymemcache python -c "from pymemcache.client.base import Client; c = Client((\"127.0.0.1\", 11211)); c.set(\"devtest:py\", \"ok\"); print(\"pymemcache:\", c.get(\"devtest:py\")); c.delete(\"devtest:py\")" | grep -q ok' 300
            warn  "devsvc-memcached is on DDEV's network as devmemcached (once a DDEV project has run)" 'if ! docker network inspect ddev_default > /dev/null 2>&1; then echo "SKIPPED: no ddev_default network yet"; exit 0; fi; devsvc ddev | grep "^memcached:"; docker inspect -f "{{json .NetworkSettings.Networks.ddev_default.Aliases}}" devsvc-memcached | tee /dev/stderr | grep -q "\"devmemcached\""'
            hint  "'devsvc ddev' joins it"
        fi
    fi
    svc_release memcached
    # --- v89 stage 2: the search engines. Each block: the container's settings (quick), then a start
    # with 'devsvc up' and, when it answered, its login and a record round-trip through 'devsvc cli'
    # (curl with the service's login). Solr, OpenSearch and Elasticsearch stop one another as they start
    # (one Java engine at a time); the end of this section starts again whatever ran before the test.
    # search_rt.sh ENGINE: create an index/collection, add a record, find it, delete it.
    cat > "$WORK/search_rt.sh" << 'EOF'
e=$1; set -o pipefail
j() { devsvc cli "$e" "$@"; }
case $e in
solr)
    C=devtest_$$
    j "/solr/admin/collections?action=CREATE&name=$C&numShards=1&replicationFactor=1&collection.configName=_default" | jq -e '.responseHeader.status == 0' > /dev/null || { echo "collection CREATE failed (the _default configset lives in ZooKeeper)"; exit 1; }
    echo "created collection $C"
    j "/solr/$C/update?commit=true" -X POST -d '[{"id":"dca","name_s":"Reagan National"}]' | jq -e '.responseHeader.status == 0' > /dev/null || exit 1
    n=$(j "/solr/$C/select?q=id:dca" | jq '.response.numFound'); echo "select id:dca -> $n document(s)"
    j "/solr/admin/collections?action=DELETE&name=$C" | jq -e '.responseHeader.status == 0' > /dev/null && echo "deleted collection $C"
    [ "$n" = 1 ] ;;
opensearch|elasticsearch)
    I=devtest-$$
    j "/$I/_doc/dca?refresh=true" -X PUT -d '{"airport":"DCA","name":"Reagan National"}' | jq -e '.result == "created"' > /dev/null || { echo "indexing failed"; exit 1; }
    n=$(j "/$I/_search?q=name:reagan" | jq '.hits.total.value'); echo "search name:reagan -> $n hit(s)"
    j "/$I" -X DELETE | jq -e '.acknowledged' > /dev/null && echo "deleted index $I"
    [ "$n" = 1 ] ;;
meilisearch)
    I=devtest_$$
    wait_task() { local s i; for i in $(seq 1 30); do s=$(j "/tasks/$1" | jq -r '.status'); case $s in succeeded) return 0 ;; failed|canceled) j "/tasks/$1"; return 1 ;; esac; sleep 1; done; return 1; }
    t=$(j "/indexes/$I/documents" -X POST -d '[{"id":1,"airport":"DCA","name":"Reagan National"}]' | jq -r '.taskUid'); wait_task "$t" || { echo "adding the document failed"; exit 1; }
    n=$(j "/indexes/$I/search" -X POST -d '{"q":"regan"}' | jq '.hits | length'); echo "search 'regan' (a typo) -> $n hit(s)"
    t=$(j "/indexes/$I" -X DELETE | jq -r '.taskUid'); wait_task "$t" && echo "deleted index $I"
    [ "$n" = 1 ] ;;
typesense)
    C=devtest_$$
    j "/collections" -X POST -d "{\"name\":\"$C\",\"fields\":[{\"name\":\"airport\",\"type\":\"string\"},{\"name\":\"name\",\"type\":\"string\"}]}" | jq -e '.name' > /dev/null || { echo "creating the collection failed"; exit 1; }
    j "/collections/$C/documents" -X POST -d '{"id":"dca","airport":"DCA","name":"Reagan National"}' | jq -e '.id' > /dev/null || exit 1
    n=$(j "/collections/$C/documents/search?q=regan&query_by=name" | jq '.found'); echo "search 'regan' (a typo) -> $n hit(s)"
    j "/collections/$C" -X DELETE | jq -e '.name' > /dev/null && echo "deleted collection $C"
    [ "$n" = 1 ] ;;
esac
EOF
    # search_login.sh ENGINE: an unauthenticated request must get 401
    cat > "$WORK/search_login.sh" << 'EOF'
case $1 in
    solr) u=http://127.0.0.1:8983/solr/admin/info/system ;;
    opensearch) u=http://127.0.0.1:9200/ ;;
    elasticsearch) u=http://127.0.0.1:9201/ ;;
    meilisearch) u=http://127.0.0.1:7700/indexes ;;
    typesense) u=http://127.0.0.1:8108/collections ;;
esac
c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$u"); echo "without the login: HTTP $c"
[ "$c" = 401 ] || [ "$c" = 403 ]
EOF
    # svc_search ENGINE HOSTPORT CONTAINERPORT DDEVNAME TITLE UP-TIMEOUT
    svc_search() {
        local e=$1 hp=$2 cp=$3 dn=$4 title=$5 to=$6
        check "devsvc-$e container: 127.0.0.1:$hp, start policy per DEVSVC_AUTOSTART" "docker inspect devsvc-$e > $e.json || exit 1; jq -r -e --arg port $cp/tcp --arg policy $(svc_policy "$e") -f devsvc.jq $e.json"
        hint  "no such container: rerun setup with install-$e (its log says why: most often the image pull). 'permission denied': open a new terminal (docker group)"
        docker container inspect "devsvc-$e" > /dev/null 2>&1 || return 0
        slow  "$title starts and answers (devsvc up $e)" "bash svc_up.sh $e" "$to"
        hint  "'devsvc logs $e' shows why. A Java engine that dies at once is usually memory: 'devsvc status', 'ollama ps'"
        [ "$LAST" = pass ] || return 0
        check "$title requires its login"                 "bash search_login.sh $e"
        hint  "Solr: its first 'devsvc up' puts security.json into ZooKeeper; 'devsvc down solr && devsvc up solr' retries"
        check "$title: create, add a record, find it, delete it" "bash search_rt.sh $e" 180
        hint  "the password or key in ~/.config/devsvc/devsvc.env is not the one the service was created with: start it over (dev-setup's notes)"
        slowwarn "a container on DDEV's network reaches $dn:$cp" "if ! docker network inspect ddev_default > /dev/null 2>&1; then echo 'SKIPPED: no ddev_default network yet'; exit 0; fi; c=\$(docker run --rm --network ddev_default curlimages/curl:latest -s -o /dev/null -w '%{http_code}' --max-time 20 http://$dn:$cp/); echo \"http://$dn:$cp/ -> HTTP \$c\"; [ \"\$c\" != 000 ]" 300
        hint  "'devsvc ddev' joins it; Docker Hub unreachable for curlimages/curl also makes this WARN"
    }
    # What ran before the test (the Java engines stop one another; SQL Server and Oracle stop for them).
    SVC_DB_BEFORE=""
    for _c in devdb-mssql devdb-oracle; do
        [ "$(docker inspect -f '{{.State.Running}}' "$_c" 2> /dev/null)" = true ] && SVC_DB_BEFORE+=" ${_c#devdb-}"
    done
    if has install-opensearch || has install-elasticsearch; then
        info "vm.max_map_count (OpenSearch/Elasticsearch run with mmap off)" "$(cat /proc/sys/vm/max_map_count 2> /dev/null)"
    fi
    has install-solr          && svc_search solr          8983 8983 devsolr       "Solr"          600
    svc_release solr
    has install-opensearch    && svc_search opensearch    9200 9200 devopensearch "OpenSearch"    600
    has install-opensearch    && [ "$(docker inspect -f '{{.State.Running}}' devsvc-opensearch 2> /dev/null)" = true ] \
        && slowwarn "Python client (opensearch-py through uv)" 'uv run --no-project --with opensearch-py python -c "from opensearchpy import OpenSearch; import subprocess; pw = subprocess.check_output([\"devsvc\", \"password\", \"opensearch\"], stderr=subprocess.DEVNULL, text=True).strip(); c = OpenSearch(\"http://127.0.0.1:9200\", http_auth=(\"admin\", pw)); print(\"opensearch-py:\", c.info()[\"version\"][\"number\"])"' 300
    svc_release opensearch
    has install-elasticsearch && svc_search elasticsearch 9201 9200 develastic    "Elasticsearch" 600
    svc_release elasticsearch
    has install-meilisearch   && svc_search meilisearch   7700 7700 devmeili      "Meilisearch"   300
    has install-meilisearch   && [ "$(docker inspect -f '{{.State.Running}}' devsvc-meilisearch 2> /dev/null)" = true ] \
        && slowwarn "Python client (meilisearch through uv)" 'uv run --no-project --with meilisearch python -c "import meilisearch, subprocess; k = subprocess.check_output([\"devsvc\", \"password\", \"meilisearch\"], stderr=subprocess.DEVNULL, text=True).strip(); print(\"meilisearch-python:\", meilisearch.Client(\"http://127.0.0.1:7700\", k).get_version()[\"pkgVersion\"])"' 300
    svc_release meilisearch
    has install-typesense     && svc_search typesense     8108 8108 devtypesense  "Typesense"     300
    svc_release typesense
    # --- v89 stage 3: vector stores and MongoDB ---
    if has install-vector; then
        check "sqlite3 on PATH is Debian's (not a Homebrew copy)"   'p=$(readlink -f "$(command -v sqlite3)"); echo "sqlite3: $p ($(sqlite3 --version | cut -d" " -f1))"; [ "$p" = /usr/bin/sqlite3 ]'
        hint  "a Homebrew sqlite3 first on PATH is the v68 shadowing problem: rerun setup (it moves Homebrew to the end of PATH)"
        cat > "$WORK/vec.sql" << EOF
.load $HOME/.local/lib/sqlite-vec/vec0
select vec_version();
create virtual table t using vec0(e float[2]);
insert into t(rowid, e) values (1, '[1,0]'), (2, '[0,1]');
select rowid from t where e match '[0.9,0.1]' and k = 1;
EOF
        check "sqlite-vec loads in sqlite3 and finds the nearest vector" '[ -f ~/.local/lib/sqlite-vec/vec0.so ] || { echo "no ~/.local/lib/sqlite-vec/vec0.so (rerun setup with install-vector)"; exit 1; }; r=$(sqlite3 :memory: < vec.sql 2>&1); echo "$r"; [ "$(echo "$r" | tail -n 1)" = 1 ]'
        hint  "'Error: ... cannot open shared object': the download failed (setup's NOTICE says why); rerun setup with install-vector"
    fi
    # vec_rt.sh ENGINE: a collection of two 2-d vectors, the nearest one to (0.9, 0.1), then cleaned up
    cat > "$WORK/vec_rt.sh" << 'EOF'
e=$1; set -o pipefail
j() { devsvc cli "$e" "$@"; }
case $e in
qdrant)
    C=devtest_$$
    j "/collections/$C" -X PUT -d '{"vectors":{"size":2,"distance":"Euclid"}}' | jq -e '.result == true' > /dev/null || { echo "creating the collection failed"; exit 1; }
    j "/collections/$C/points?wait=true" -X PUT -d '{"points":[{"id":1,"vector":[1,0],"payload":{"name":"alpha"}},{"id":2,"vector":[0,1],"payload":{"name":"beta"}}]}' | jq -e '.status == "ok"' > /dev/null || exit 1
    r=$(j "/collections/$C/points/query" -X POST -d '{"query":[0.9,0.1],"limit":1,"with_payload":true}' | jq -r '.result.points[0].payload.name'); echo "nearest to (0.9, 0.1): $r"
    j "/collections/$C" -X DELETE | jq -e '.result == true' > /dev/null && echo "deleted collection $C"
    [ "$r" = alpha ] ;;
milvus)
    C=devtest_$$
    j /v2/vectordb/collections/create -X POST -d "{\"collectionName\":\"$C\",\"dimension\":2,\"metricType\":\"L2\"}" | jq -e '.code == 0' > /dev/null || { echo "creating the collection failed"; exit 1; }
    j /v2/vectordb/entities/insert -X POST -d "{\"collectionName\":\"$C\",\"data\":[{\"id\":1,\"vector\":[1,0]},{\"id\":2,\"vector\":[0,1]}]}" | jq -e '.code == 0' > /dev/null || exit 1
    r=""; for _ in $(seq 1 20); do
        r=$(j /v2/vectordb/entities/search -X POST -d "{\"collectionName\":\"$C\",\"data\":[[0.9,0.1]],\"limit\":1}" | jq -r '.data[0].id // empty'); [ -n "$r" ] && break; sleep 1
    done
    echo "nearest to (0.9, 0.1): id ${r:-none}"
    j /v2/vectordb/collections/drop -X POST -d "{\"collectionName\":\"$C\"}" | jq -e '.code == 0' > /dev/null && echo "dropped collection $C"
    [ "$r" = 1 ] ;;
esac
EOF
    cat > "$WORK/mongo_rt.js" << 'EOF'
const d = db.getSiblingDB("devtest"), c = d.airports;
c.drop();
c.insertMany([{code: "DCA", name: "Reagan National"}, {code: "IAD", name: "Dulles"}]);
const n = c.countDocuments({code: "DCA"});
print("inserted 2, found " + n + " for code DCA; server " + db.version());
d.dropDatabase();
if (n !== 1) quit(1);
EOF
    cat > "$WORK/atlas_vec.js" << 'EOF'
const d = db.getSiblingDB("devtest"), c = d.vec;
c.drop();
c.insertMany([{_id: 1, name: "alpha", v: [1, 0]}, {_id: 2, name: "beta", v: [0, 1]}]);
c.createSearchIndex("vidx", "vectorSearch", {fields: [{type: "vector", path: "v", numDimensions: 2, similarity: "euclidean"}]});
let r = [];
for (let i = 0; i < 90 && r.length === 0; i++) {
    try { r = c.aggregate([{$vectorSearch: {index: "vidx", path: "v", queryVector: [0.9, 0.1], numCandidates: 2, limit: 1}}]).toArray(); } catch (e) {}
    if (r.length === 0) sleep(2000);
}
print("nearest to (0.9, 0.1): " + (r.length ? r[0].name : "none (the index did not become queryable)"));
d.dropDatabase();
if (r.length === 0 || r[0].name !== "alpha") quit(1);
EOF
    if has install-qdrant; then
        check "devsvc-qdrant container: 127.0.0.1:6333, start policy per DEVSVC_AUTOSTART" "docker inspect devsvc-qdrant > qd.json || exit 1; jq -r -e --arg port 6333/tcp --arg policy $(svc_policy qdrant) -f devsvc.jq qd.json"
        hint  "no such container: rerun setup with install-qdrant (or install-vector)"
        if docker container inspect devsvc-qdrant > /dev/null 2>&1; then
            check "Qdrant starts and answers (devsvc up qdrant)"  'bash svc_up.sh qdrant'
            if [ "$LAST" = pass ]; then
                if bash -c '. ~/.config/devsvc/devsvc.env 2> /dev/null; [ -n "${QDRANT_API_KEY:-}" ]'; then
                    check "Qdrant refuses a client without QDRANT_API_KEY" 'c=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:6333/collections); echo "without the key: HTTP $c"; [ "$c" = 401 ] || [ "$c" = 403 ]'
                else
                    info  "Qdrant API key" "none (127.0.0.1 only; set QDRANT_API_KEY in secrets.env before sharing Qdrant)"
                fi
                check "Qdrant: collection, two points, nearest-vector query, delete" 'bash vec_rt.sh qdrant'
                slowwarn "Python client (qdrant-client through uv)" 'uv run --no-project --with qdrant-client python -c "import subprocess; from qdrant_client import QdrantClient; k = subprocess.check_output([\"devsvc\", \"password\", \"qdrant\"], stderr=subprocess.DEVNULL, text=True).strip() or None; print(\"qdrant-client:\", QdrantClient(url=\"http://127.0.0.1:6333\", api_key=k, https=False).get_collections())"' 300
            fi
        fi
    fi
    svc_release qdrant
    if has install-milvus; then
        check "devsvc-milvus container: 127.0.0.1:19530, start policy per DEVSVC_AUTOSTART" "docker inspect devsvc-milvus > mv.json || exit 1; jq -r -e --arg port 19530/tcp --arg policy $(svc_policy milvus) -f devsvc.jq mv.json"
        hint  "no such container: rerun setup with install-milvus"
        if docker container inspect devsvc-milvus > /dev/null 2>&1; then
            slow  "Milvus starts and answers (devsvc up milvus; asks for 8 GB)" 'bash svc_up.sh milvus' 900
            hint  "Milvus asks for more memory than this VM has: 'devsvc down' everything else, stop Ollama models, close Chrome tabs; 'devsvc logs milvus'"
            [ "$LAST" = pass ] && check "Milvus: collection, two vectors, nearest-vector search, drop" 'bash vec_rt.sh milvus' 300
        fi
    fi
    svc_release milvus
    if has install-mongodb; then
        warn  "mongosh on this machine"                        'mongosh --version'
        hint  "setup installs MongoDB's .deb (rerun setup with install-mongodb); 'devsvc cli mongodb' falls back to the container's mongosh"
        warn  "MongoDB Database Tools (mongodump, mongorestore, mongoimport)" 'for c in mongodump mongorestore mongoimport mongoexport; do command -v "$c" > /dev/null || { echo "missing: $c"; exit 1; }; done; mongodump --version | head -n 1'
        warn  "MongoDB Compass desktop app, in the ChromeOS launcher" 'dpkg-query -W -f="\${Package} \${Version}\n" mongodb-compass && ls /usr/share/applications | grep -i compass'
        hint  "MONGODB_COMPASS=0 skips it on purpose; otherwise setup's log says why"
        check "devsvc-mongodb container: 127.0.0.1:27017, start policy per DEVSVC_AUTOSTART" "docker inspect devsvc-mongodb > mg.json || exit 1; jq -r -e --arg port 27017/tcp --arg policy $(svc_policy mongodb) -f devsvc.jq mg.json"
        hint  "no such container: rerun setup with install-mongodb"
        if docker container inspect devsvc-mongodb > /dev/null 2>&1; then
            check "MongoDB starts and answers (devsvc up mongodb)"  'bash svc_up.sh mongodb'
            if [ "$LAST" = pass ]; then
                check "MongoDB: insert, find and drop (mongosh)"     'devsvc cli mongodb --quiet --eval "$(cat mongo_rt.js)"'
                hint  "'Authentication failed': MONGO_ROOT_PASSWORD in secrets.env changed since setup ran; rerun setup with install-mongodb"
                if bash -c '. ~/.config/devsvc/devsvc.env 2> /dev/null; [ -n "${MONGO_ROOT_PASSWORD:-}" ]'; then
                    check "MongoDB refuses a client without MONGO_ROOT_PASSWORD" 'r=$(docker exec devsvc-mongodb mongosh --quiet --eval "db.adminCommand({listDatabases: 1}).ok" 2>&1); echo "$r" | tail -n 1; ! echo "$r" | grep -qx 1'
                else
                    info  "MongoDB login" "none (127.0.0.1 only; set MONGO_ROOT_PASSWORD in secrets.env before sharing MongoDB)"
                fi
                warn  "mongoimport and mongoexport round-trip"  'command -v mongoimport > /dev/null || { echo "no Database Tools"; exit 1; }; pw=$(devsvc password mongodb 2> /dev/null); u=mongodb://127.0.0.1:27017; [ -n "$pw" ] && u="mongodb://root:$pw@127.0.0.1:27017/?authSource=admin"; printf "{\"code\":\"DCA\"}\n{\"code\":\"IAD\"}\n" > air.json; mongoimport --quiet --uri "$u" --db devtest --collection air --drop --file air.json && n=$(mongoexport --quiet --uri "$u" --db devtest --collection air | wc -l); echo "imported 2, exported $n"; devsvc cli mongodb --quiet --eval "db.getSiblingDB(\"devtest\").dropDatabase()" > /dev/null; [ "$n" = 2 ]'
                if has install-web; then
                    check "PHP's mongodb extension (ext-mongodb 1.21+ for Laravel / Doctrine ODM) talks to it" 'php -m | grep -qix mongodb || { echo "PHP has no mongodb extension (php-mongodb, install-web)"; exit 1; }; pw=$(devsvc password mongodb 2> /dev/null); u=mongodb://127.0.0.1:27017; [ -n "$pw" ] && u="mongodb://root:$pw@127.0.0.1:27017/?authSource=admin"; MONGO_URL=$u php -r "\$m = new MongoDB\Driver\Manager(getenv(\"MONGO_URL\")); \$b = new MongoDB\Driver\BulkWrite; \$b->insert([\"code\" => \"DCA\"]); \$m->executeBulkWrite(\"devtest.php\", \$b); \$n = count(\$m->executeQuery(\"devtest.php\", new MongoDB\Driver\Query([\"code\" => \"DCA\"]))->toArray()); \$m->executeCommand(\"devtest\", new MongoDB\Driver\Command([\"dropDatabase\" => 1])); \$v = phpversion(\"mongodb\"); echo \"ext-mongodb \$v: found \$n\", PHP_EOL; exit(\$n === 1 && version_compare(\$v, \"1.21\", \">=\") ? 0 : 1);"'
                    hint  "an extension older than 1.21 is too old for mongodb/laravel-mongodb 5 and Doctrine ODM 2: 'pecl install mongodb' gives the current one"
                fi
                slowwarn "Python client (pymongo through uv)" 'pw=$(devsvc password mongodb 2> /dev/null); u=mongodb://127.0.0.1:27017; [ -n "$pw" ] && u="mongodb://root:$pw@127.0.0.1:27017/?authSource=admin"; MONGO_URL=$u uv run --no-project --with pymongo python -c "import os, pymongo; c = pymongo.MongoClient(os.environ[\"MONGO_URL\"], serverSelectionTimeoutMS=5000); print(\"pymongo\", pymongo.version, \"server\", c.server_info()[\"version\"])"' 300
            fi
        fi
    fi
    svc_release mongodb
    if has install-mongodb-atlas-local; then
        warn  "Atlas CLI (atlas)"                              'atlas --version 2>&1 | head -n 1; command -v atlas > /dev/null'
        hint  "setup installs MongoDB's .deb (rerun setup with install-mongodb-atlas-local); the container works without it"
        check "devsvc-atlas-local container: 127.0.0.1:27018, start policy per DEVSVC_AUTOSTART" "docker inspect devsvc-atlas-local > al.json || exit 1; jq -r -e --arg port 27017/tcp --arg policy $(svc_policy atlas-local) -f devsvc.jq al.json"
        hint  "no such container: rerun setup with install-mongodb-atlas-local"
        if docker container inspect devsvc-atlas-local > /dev/null 2>&1; then
            slow  "Atlas Local starts and reports healthy (devsvc up atlas-local)" 'bash svc_up.sh atlas-local' 900
            if [ "$LAST" = pass ]; then
                check "Atlas Local: insert, find and drop (mongosh)" 'devsvc cli atlas-local --quiet --eval "$(cat mongo_rt.js)"'
                slowwarn "Atlas Local: a Vector Search index answers \$vectorSearch" 'devsvc cli atlas-local --quiet --eval "$(cat atlas_vec.js)"' 300
                hint  "mongot builds the index in the background; on a busy machine it can take longer than the three minutes allowed here"
            fi
        fi
    fi
    svc_release atlas-local
    # v91: the Selenium Grid (install-selenium). Its round trip opens the test tools section's links app in
    # the Grid's Chrome: a second copy of the app listens on Docker's address (docker0), which the container
    # reaches as host.docker.internal.
    if has install-selenium; then
        cat > "$WORK/grid_rt.sh" << 'EOF'
ip=$(ip -4 -o addr show docker0 2> /dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)
[ -n "$ip" ] || { echo "no docker0 address"; exit 1; }
[ -f testing/links_app.py ] || { echo "no test app (the test tools section did not run)"; exit 1; }
python3 testing/links_app.py --host "$ip" --port-file grid.port > grid_app.log 2>&1 & pid=$!
trap 'kill $pid 2> /dev/null' EXIT
for _ in $(seq 1 20); do [ -s grid.port ] && break; sleep 0.25; done
p=$(cat grid.port)
echo "the app on $ip:$p; the Grid's browser opens http://host.docker.internal:$p/"
(cd testing && GRID_URL=http://127.0.0.1:4444 BASE_URL="http://host.docker.internal:$p" APP_URL="http://$ip:$p" SHOT="$WORK/grid.png" \
    uv run --no-project --quiet --with selenium python sel_links.py) || exit 1
s=$(stat -c %s "$WORK/grid.png" 2> /dev/null || echo 0); echo "screenshot: $s bytes"; [ "$s" -gt 1000 ]
EOF
        check "devsvc-selenium container: 127.0.0.1:4444, start policy per DEVSVC_AUTOSTART" "docker inspect devsvc-selenium > se.json || exit 1; jq -r -e --arg port 4444/tcp --arg policy $(svc_policy selenium) -f devsvc.jq se.json"
        hint  "no such container: rerun setup with install-selenium"
        if docker container inspect devsvc-selenium > /dev/null 2>&1; then
            check "the Grid's noVNC is on 127.0.0.1 too; it runs as a heavy engine (one at a time)" 'jq -e "[.[0].HostConfig.PortBindings[\"7900/tcp\"][]?.HostIp] == [\"127.0.0.1\"]" se.json && grep -q "^selenium|.*|heavy|4444|install-selenium$" ~/.local/bin/devsvc'
            hint  "the devsvc in ~/.local/bin is older than setup v91's: rerun setup with install-selenium"
            slow  "Selenium Grid starts and reports ready (devsvc up selenium)" 'bash svc_up.sh selenium' 600
            hint  "'devsvc logs selenium'; the Grid wants ~1.6 GB: 'devsvc status' shows what else runs"
            if [ "$LAST" = pass ]; then
                slow  "RemoteWebDriver through the Grid: the links app, and a screenshot" 'bash grid_rt.sh' 300
                hint  "'connection refused' from the page: the app must listen on Docker's address; the Grid reaches this machine as host.docker.internal"
                warn  "noVNC answers on http://localhost:7900 (watch the Grid's browser)" 'curl -fsS --max-time 10 http://127.0.0.1:7900/ | grep -qi novnc'
            fi
        fi
    fi
    svc_release selenium
    # Leave each service as the test found it: first stop what the test started, then start again what
    # ran before (a Java engine another one stopped; SQL Server or Oracle, which a Java engine stops).
    for _s in $SVC_HAVE; do
        [ -f "$WORK/svc_$_s.was" ] && [ "$(cat "$WORK/svc_$_s.was")" != true ] && check "devsvc-$_s stopped again (the test started it)" "bash svc_restore.sh $_s"
    done
    for _s in $SVC_HAVE; do
        [ -f "$WORK/svc_$_s.was" ] && [ "$(cat "$WORK/svc_$_s.was")" = true ] && check "devsvc-$_s running again, as before the test" "bash svc_restore.sh $_s" 600
    done
    for _e in $SVC_DB_BEFORE; do
        [ "$(docker inspect -f '{{.State.Running}}' "devdb-$_e" 2> /dev/null)" = true ] || slow "$_e running again, as before the test ($_e up)" "DEVDB_BOTH=1 $_e up > /dev/null" 1200
    done
fi

# Local lakehouse stack
if has install-lakehouse; then
    section "Local lakehouse: DuckDB, DuckLake, Iceberg, Delta Lake, dbt (install-lakehouse)"
    check "duckdb CLI"                                     'duckdb --version'
    check "~/.duckdbrc and ~/.duckdb/tmp present"          '[ -f ~/.duckdbrc ] && [ -d ~/.duckdb/tmp ]'
    check "duckdb extensions load (iceberg, ducklake, delta, httpfs, sqlite, postgres)" 'duckdb -c "LOAD iceberg; LOAD ducklake; LOAD delta; LOAD httpfs; LOAD sqlite; LOAD postgres; SELECT 1;"'
    hint  "a missing extension (delta is new in v79): rerun setup with install-lakehouse, which installs them from extensions.duckdb.org"
    cat > "$WORK/ducklake.sql" << EOF
ATTACH 'ducklake:$WORK/cat.ducklake' AS lake (DATA_PATH '$WORK/lakedata/');
CREATE TABLE lake.t AS SELECT 42 AS a;
SELECT a FROM lake.t;
EOF
    check "DuckLake catalog: attach, create table, query"  'duckdb < ducklake.sql | grep -q 42'
    check "~/.lakehouse-env: duckdb, pyarrow, pandas import" '~/.lakehouse-env/bin/python -c "import duckdb, pyarrow, pandas; duckdb.sql(\"select 1\")"'
    check "~/.lakehouse-env python has iceberg/ducklake/delta ext" '~/.lakehouse-env/bin/python -c "import duckdb; c=duckdb.connect(); [c.load_extension(e) for e in (\"iceberg\",\"ducklake\",\"delta\",\"httpfs\")]"'
    # v79: Delta Lake. delta-rs (deltalake) creates the table, because DuckDB's Delta support writes
    # INSERT only; DuckDB then reads it, appends to it, and time-travels to the version delta-rs wrote.
    check "~/.lakehouse-env: deltalake (delta-rs) imports"  '~/.lakehouse-env/bin/python -c "import deltalake; print(\"deltalake\", deltalake.__version__)"'
    hint  "rerun setup with install-lakehouse: v79 adds deltalake to ~/.lakehouse-env"
    cat > "$WORK/delta_smoke.py" << 'EOF'
"""dev-test Delta Lake round-trip.  delta_smoke.py read|append PATH"""
import os
import sys

import duckdb
import pyarrow as pa
from deltalake import DeltaTable, write_deltalake


def done(ok):
    # os._exit, not sys.exit: after an INSERT into a Delta table the process sometimes aborts in
    # teardown ("terminate called without an active exception", exit 134) once the work is done.
    sys.stdout.flush()
    os._exit(0 if ok else 1)


mode, path = sys.argv[1], os.path.abspath(sys.argv[2])
con = duckdb.connect()
con.execute("LOAD delta")
if mode == "read":
    write_deltalake(path, pa.table({"airport": ["DCA", "IAD"], "delay_min": [5, 42]}))
    n = con.execute(f"SELECT count(*) FROM delta_scan('{path}')").fetchone()[0]
    print(f"delta-rs wrote version {DeltaTable(path).version()}; DuckDB delta_scan reads {n} rows")
    done(n == 2)
con.execute(f"ATTACH '{path}' AS lake (TYPE delta)")
con.execute("INSERT INTO lake VALUES ('BWI', 0)")
now = con.execute("SELECT count(*) FROM lake").fetchone()[0]
then = con.execute("SELECT count(*) FROM lake AT (VERSION => 0)").fetchone()[0]
dt = DeltaTable(path)
rows = dt.to_pyarrow_table().num_rows
print(f"DuckDB INSERT made version {dt.version()}; DuckDB sees {now} rows now and {then} at version 0; delta-rs reads {rows}")
done((now, then, rows, dt.version()) == (3, 2, 3, 1))
EOF
    check "Delta: delta-rs creates a table, DuckDB reads it (delta_scan)" 'rm -rf deltatbl && ~/.lakehouse-env/bin/python delta_smoke.py read deltatbl'
    warn  "Delta: DuckDB appends (INSERT), delta-rs reads it back, time travel" '[ -d deltatbl/_delta_log ] || { echo "no table: the check above failed"; exit 1; }; ~/.lakehouse-env/bin/python delta_smoke.py append deltatbl'
    hint  "DuckDB's Delta writes are INSERT-only and recent: rerun setup with install-lakehouse for the latest duckdb and delta extension. Reading (the check above) is what the flag promises"
    check "dbt1 alias in ~/.bashrc"                        'grep -q "alias dbt1=" ~/.bashrc'
    check "dbt Core v1 with dbt-duckdb adapter"            '~/.lakehouse-env/bin/dbt --version 2>&1 | grep -qi duckdb'
    check "dbt Fusion (v2) at ~/.local/bin/dbt"            '[ -x ~/.local/bin/dbt ] && ~/.local/bin/dbt --version'
    check "~/lakehouse project dir"                        '[ -d ~/lakehouse ]'
    mkdir -p "$WORK/dbt_demo/models"
    cat > "$WORK/dbt_demo/dbt_project.yml" << 'EOF'
name: dbt_demo
version: '1.0'
config-version: 2
profile: dbt_demo
model-paths: ["models"]
EOF
    cat > "$WORK/dbt_demo/profiles.yml" << EOF
dbt_demo:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: $WORK/dbt_demo/demo.duckdb
EOF
    echo "select 42 as answer" > "$WORK/dbt_demo/models/answer.sql"
    slow     "dbt Core v1 runs a model against DuckDB"     'cd dbt_demo && ~/.lakehouse-env/bin/dbt run --profiles-dir . --no-use-colors && duckdb demo.duckdb "select answer from answer" | grep -q 42' 300
    slowwarn "dbt Fusion v2 runs the same model"           'cd dbt_demo && rm -f demo.duckdb && ~/.local/bin/dbt run --profiles-dir . && duckdb demo.duckdb "select answer from answer" | grep -q 42' 300
fi

# Ollama server (v77: its own flag; install-gemma and install-models pull it in)
if has install-ollama; then
    section "Ollama server (install-ollama)"
    check "ollama"                                         'ollama --version'
    check "ollama server responds"                         'ollama list > /dev/null'
    hint  "sudo systemctl start ollama (or 'ollama serve' where there is no systemd)"
    check "ollama service starts with Linux"               'systemctl is-enabled ollama'
    hint  "sudo systemctl enable --now ollama (setup v77 and dev-init both do this)"
    # v77: the six settings setup writes to the drop-in. A different value comes from an override.conf
    # ('sudo systemctl edit ollama'), which is the documented way to change one, so it passes with a note.
    check "server settings on the service (drop-in from setup v77)" 'e=$(systemctl show ollama -p Environment --value 2> /dev/null); bad=0; for kv in OLLAMA_LOAD_TIMEOUT=15m OLLAMA_MAX_LOADED_MODELS=2 OLLAMA_NUM_PARALLEL=1 OLLAMA_CONTEXT_LENGTH=8192 OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0; do k=${kv%%=*}; v=$(echo "$e" | tr " " "\n" | sed -n "s/^$k=//p" | tail -n 1); if [ -z "$v" ]; then echo "$k: missing"; bad=1; elif [ "$v" != "${kv#*=}" ]; then echo "$k=$v (setup writes ${kv#*=}; an override wins, which is fine)"; else echo "$k=$v"; fi; done; exit $bad'
    hint  "rerun setup with install-ollama: v77 writes /etc/systemd/system/ollama.service.d/dev-setup.conf"
    check "client block in ~/.bashrc (OLLAMA_API_BASE, ollama-remote)" 'blk=$(sed -n "/^# >>> dev-setup ollama >>>$/,/^# <<< dev-setup ollama <<<$/p" ~/.bashrc); [ -n "$blk" ] || { echo "no dev-setup ollama block in ~/.bashrc"; exit 1; }; eval "$blk"; echo "OLLAMA_API_BASE=$OLLAMA_API_BASE"; declare -F ollama-remote && [ "$OLLAMA_API_BASE" = http://127.0.0.1:11434 ]'
    hint  "rerun setup with install-ollama; the block is rewritten on every run"
    warn  "OLLAMA_HOST is not exported globally (plain ollama stays local)" 'f=$(grep -lE "^[[:space:]]*export[[:space:]]+OLLAMA_HOST=" ~/.bashrc ~/.config/dev-init/secrets.env 2> /dev/null); [ -z "$f" ] || { echo "exported in: $f"; exit 1; }'
    hint  "an exported OLLAMA_HOST sends every client (gemma, aider, LangChain) to that server; put the address in OLLAMA_REMOTE and use 'ollama-remote' instead"
    # v80: install-ollama-containers. The drop-in stays across runs without the flag, so it is checked
    # whenever it exists; without it, containers cannot reach Ollama and an INFO line says so.
    if has install-ollama-containers || [ -f /etc/systemd/system/ollama.service.d/dev-setup-containers.conf ]; then
        check "Ollama listens for containers (OLLAMA_HOST=0.0.0.0:11434)" 'systemctl show ollama -p Environment --value | tr " " "\n" | grep -x "OLLAMA_HOST=0.0.0.0:11434" && ss -ltnH "sport = :11434" | tee /dev/stderr | grep -qE "(0\.0\.0\.0|\*|\[::\]):11434"'
        hint  "rerun setup with install-ollama-containers: it writes ollama.service.d/dev-setup-containers.conf and restarts Ollama"
        slow  "a Docker container reaches Ollama at host.docker.internal:11434" 'docker run --rm --add-host=host.docker.internal:host-gateway curlimages/curl:latest -fsS --max-time 20 http://host.docker.internal:11434/api/version' 300
        hint  "needs the docker group active in this shell (open a new terminal). DDEV maps host.docker.internal in its containers by itself"
    else
        info  "Ollama reachable from Docker containers (DDEV, Drupal AI)" "no: 127.0.0.1 only (setup with install-ollama-containers opens it)"
    fi
    warn  "remote Ollama answers (only if OLLAMA_REMOTE is set)"  '_r="$OLLAMA_REMOTE"; [ -f ~/.config/dev-init/secrets.env ] && { set -a; . ~/.config/dev-init/secrets.env; set +a; }; r="${_r:-$OLLAMA_REMOTE}"; if [ -z "$r" ]; then echo "SKIPPED: OLLAMA_REMOTE not set (optional)"; exit 0; fi; case "$r" in http://*|https://*) ;; *) r="http://$r" ;; esac; hp=${r#*://}; hp=${hp%%/*}; case "$hp" in *:*) ;; *) r="${r%%://*}://$hp:11434" ;; esac; v=$(curl -fsS --max-time 10 "$r/api/version") || { echo "no answer from $r"; exit 1; }; echo "$r: $v"; echo "models there: $(curl -fsS --max-time 10 "$r/api/tags" | jq -r "[.models[].name] | join(\", \")")"' 60
    hint  "is that machine awake and sharing Ollama? A Chromebook: LAN_SHARE=ollama there (install-lan-share; v93: over Tailscale, and OLLAMA_REMOTE=NAME.internal or the 100.x address, since Ollama answers a plain laptop name with 403). Windows: OLLAMA_HOST=0.0.0.0:11434 and its firewall open to your private network"
    # A cloud model through the local server: needs 'ollama signin' once and costs a fraction of a cent,
    # so it only runs when asked for. The pull fetches a small manifest, not weights.
    slowwarn "live call to an Ollama :cloud model (only with OLLAMA_TEST_CLOUD=1)" 'if [ "${OLLAMA_TEST_CLOUD:-0}" != 1 ]; then echo "SKIPPED: set OLLAMA_TEST_CLOUD=1 to spend a fraction of a cent on this"; exit 0; fi; m="${OLLAMA_CLOUD_TEST_MODEL:-deepseek-v4.1-flash:cloud}"; ollama pull "$m" > /dev/null 2>&1; r=$(curl -sS --max-time 150 http://127.0.0.1:11434/api/chat -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly the word PONG.\"}],\"stream\":false,\"think\":false,\"options\":{\"num_predict\":64}}"); echo "$r" | jq -c "{model, error, answer: .message.content}"; echo "$r" | jq -e "(.message.content // \"\") | length > 0" > /dev/null' 240
    hint  "unauthorized: run 'ollama signin' once (it links this machine's Ollama key to your ollama.com account); paid models need credit on the account. A model without thinking may reject \"think\": pick another with OLLAMA_CLOUD_TEST_MODEL"
fi

# Gemma 4 / Ollama
if has install-gemma; then
    section "Gemma 4 and the hybrid client (install-gemma)"
    # v77: the Ollama server checks moved to the install-ollama section (this flag pulls it in).
    check "model $GEMMA_MODEL is pulled"                   'ollama list | grep -q "^$GEMMA_MODEL"'
    check "~/.gemma-env imports torch, transformers, accelerate, ollama, google.genai" '~/.gemma-env/bin/python -c "import torch, transformers, accelerate, ollama; from google import genai; print(torch.__version__)"'
    check "torch is the CPU-only build"                    '~/.gemma-env/bin/python -c "import torch, sys; print(torch.__version__); sys.exit(1 if torch.version.cuda else 0)"'
    # v65: compile() in memory; 'py_compile' wrote a __pycache__ next to the script.
    check "assets/gemma_client.py compiles"                '~/.gemma-env/bin/python -c "import sys; compile(open(sys.argv[1]).read(), sys.argv[1], \"exec\")" "$ASSETS/gemma_client.py"'
    hint  "rerun the installer with install-gemma: v65 writes it to ./assets and clears the old ~/gemma_client.py"
    check "gemma client takes -m / --local / --think (v77)"   '~/.gemma-env/bin/python "$ASSETS/gemma_client.py" --help | grep -E -- "--model|--local|--no-think" | sed "s/^ *//"; ~/.gemma-env/bin/python "$ASSETS/gemma_client.py" --help | grep -q -- "--no-think"'
    hint  "rerun setup with install-gemma: v77 writes the new client"
    check "'gemma' launcher in ~/.bashrc points at assets/gemma_client.py" 'blk=$(sed -n "/^# >>> dev-setup gemma launcher >>>$/,/^# <<< dev-setup gemma launcher <<<$/p" ~/.bashrc); [ -n "$blk" ] || { echo "no launcher block in ~/.bashrc"; exit 1; }; eval "$blk"; declare -f gemma; declare -f gemma | grep -qF "$ASSETS/gemma_client.py" && [ -x "$HOME/.gemma-env/bin/python" ]'
    hint  "rerun the installer with install-gemma from this folder; the block is rewritten to point at ./assets each time"
    warn  "only one gemma() definition in ~/.bashrc"       'n=$(grep -cE "^[[:space:]]*(function[[:space:]]+)?gemma[[:space:]]*\(\)" ~/.bashrc); echo "$n definition(s)"; [ "$n" -le 1 ]'
    hint  "a hand-pasted gemma() further down ~/.bashrc overrides the launcher and still points at ~/gemma_client.py; delete it"
    warn  "GEMINI_API_KEY set (cloud route)"               '[ -n "$GEMINI_API_KEY" ] || grep -qE "^export GEMINI_API_KEY=\"?[^\"]+" ~/.bashrc || grep -qE "^export GEMINI_API_KEY=\"[^\"]+\"" ~/.config/dev-init/secrets.env 2> /dev/null'
    hint  "set GEMINI_API_KEY in ~/.config/dev-init/secrets.env and run dev-init; without it the client stays local"
    warn  "Hugging Face login (Transformers route)"        '~/.gemma-env/bin/hf auth whoami' 60
    # --keepalive 0 + ollama stop: unload the ~4GB model right away instead of Ollama's default 5-minute
    # hold, so the sections that follow (Temporal, dbt) aren't started into a VM with <1GB free.
    # v70: the generate test failed in two runs after ~5 minutes, Ollama's default load limit. The
    # v69 log explained it: before the load 4.5 GB was "used" while the largest process held 34 MB,
    # and afterwards 1.9 GB of that had come back with nothing killed. That is ChromeOS's memory
    # balloon: the host keeps VM memory and returns it only under pressure, slowly, so a cold
    # load crawls. So: stop leftover compiler daemons, generate, and retry once if the first load
    # was abandoned. Setup v70 also raises Ollama's limit to 15 min.
    # v71: the v70 step that read the model file first is gone: its before/after numbers were
    # identical (page cache is reclaimable, so reading it puts no pressure on the balloon).
    # Each attempt now logs 'available' memory before it starts, which is what predicted speed
    # in every run so far.
    cat > "$WORK/ollama_gen.sh" <<'EOF'
# Bracketed pkill patterns cannot match this script's own command line.
{ dotnet build-server shutdown; gradle --stop; pkill -f "[k]otlin-daemon"; pkill -f "[K]otlinCompileDaemon"; } > /dev/null 2>&1
show_mem() {
    echo "$1"; free -h | head -n 2
    # v72: where the memory is. v73: 'unaccounted' is memory in none of these categories. It was
    # labelled host-reclaimed, but v72's run loaded the model in 27 s with ~3.7 GB unaccounted, so
    # it did not predict speed; 'available' did (the load needed a little over 2 GB).
    awk '/^(MemTotal|MemFree|MemAvailable|Buffers|Cached|AnonPages|Shmem|Slab|SUnreclaim|PageTables|KernelStack):/{v[$1]=$2}
         END{acct=v["MemFree:"]+v["Buffers:"]+v["Cached:"]+v["AnonPages:"]+v["Slab:"]+v["PageTables:"]+v["KernelStack:"]
             printf "  MB: anon %d, shmem/tmpfs %d, slab %d, cache %d, free %d, available %d; unaccounted ~%d of %d\n",
                 v["AnonPages:"]/1024, v["Shmem:"]/1024, v["Slab:"]/1024, v["Cached:"]/1024, v["MemFree:"]/1024,
                 v["MemAvailable:"]/1024, (v["MemTotal:"]-acct)/1024, v["MemTotal:"]/1024}' /proc/meminfo
}
show_mem "before:"
ps -eo rss,comm --sort=-rss | head -n 6 | awk 'NR==1{print "  RSS(MB) process"; next} {printf "  %7d %s\n", $1/1024, $2}'
clean() { sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$1" | tr '\r' '\n' | sed 's/\xe2[\xa0-\xa3][\x80-\xbf]//g' | grep '[A-Za-z]' | tail -n 3 | cut -c1-300; }
attempt() {
    ollama run "$GEMMA_MODEL" --keepalive 0 "Reply with exactly the word PONG and nothing else." > gen.out 2> gen.err
    rc=$?
    grep -qi pong gen.out
}
ok=1
for n in 1 2; do
    start=$(date +%s)
    echo "attempt $n starting with $(free -m | awk '/^Mem:/{print $7}') MB available"
    if attempt; then ok=0; echo "attempt $n: PONG after $(( $(date +%s) - start ))s"; break; fi
    err=$(clean gen.err); echo "attempt $n failed after $(( $(date +%s) - start ))s (ollama exit $rc): ${err:-no error text, only the progress spinner}"
    show_mem "memory now:"
done
ollama stop "$GEMMA_MODEL" > /dev/null 2>&1
exit $ok
EOF
    slow  "ollama generates with $GEMMA_MODEL (loads model, ~4GB RAM)" 'bash ollama_gen.sh' 1800
    hint  "\"timed out waiting for llama runner\" = the load outlasted Ollama's limit (rerun setup with install-ollama: it sets a 15-minute limit); \"requires more system memory\" = genuinely not enough RAM. Either way, closing Chrome tabs and Android apps on the ChromeOS side gives the Linux VM memory back"
fi

# Curated local models (v77, install-models; opt-in, not in install-all)
if has install-models; then
    section "Local models: DeepSeek-R1 1.5B, Qwen3.5 4B, Qwen3 embeddings (install-models)"
    check "setup recorded the model list (assets/ollama-models.txt)" '[ -s "$ASSETS/ollama-models.txt" ] && tr "\n" " " < "$ASSETS/ollama-models.txt"'
    hint  "rerun setup with install-models. An empty list means every pull was skipped: setup's NOTICE lines say why (disk guard, network)"
    mapfile -t TEST_MODELS < <(grep -v '^[[:space:]]*$' "$ASSETS/ollama-models.txt" 2> /dev/null)
    [ ${#TEST_MODELS[@]} -gt 0 ] || TEST_MODELS=(deepseek-r1:1.5b qwen3.5:4b qwen3-embedding:0.6b)
    for m in "${TEST_MODELS[@]}"; do
        want=$m; [[ "$want" == *:* ]] || want="$want:latest"
        check "model $m is pulled"                         "ollama list | awk 'NR > 1 {print \$1}' | grep -qxF '$want'"
    done
    hint  "ollama pull <model>, or rerun setup with install-models"
    warn  "at least 10 GB free where Ollama keeps models"  'd=/usr/share/ollama; [ -d "$d" ] || d="$HOME"; df -h "$d" | tail -n 1; [ "$(df -Pk "$d" | awk "NR == 2 {print \$4}")" -ge $((10 * 1024 * 1024)) ]'
    hint  "'ollama rm <model>' for models you no longer use, or give Linux more disk (ChromeOS Settings > About ChromeOS > Linux development environment)"
    # Thinking off and 32 tokens: this proves the model loads and answers, not how well it reasons.
    # Whatever is loaded is stopped first, so the load time is comparable between runs.
    cat > "$WORK/models_gen.sh" <<'EOF'
m=deepseek-r1:1.5b
ollama list | awk 'NR > 1 {print $1}' | grep -qxF "$m" || { echo "SKIPPED: $m is not pulled"; exit 0; }
{ dotnet build-server shutdown; gradle --stop; pkill -f "[k]otlin-daemon"; pkill -f "[K]otlinCompileDaemon"; } > /dev/null 2>&1
for x in $(ollama ps 2> /dev/null | awk 'NR > 1 {print $1}'); do ollama stop "$x" > /dev/null 2>&1; done
echo "starting with $(free -m | awk '/^Mem:/{print $7}') MB available"
t0=$(date +%s)
r=$(curl -sS --max-time 1500 http://127.0.0.1:11434/api/generate -d "{\"model\":\"$m\",\"prompt\":\"Reply with exactly the word PONG and nothing else.\",\"think\":false,\"stream\":false,\"keep_alive\":\"2m\",\"options\":{\"num_predict\":32}}")
echo "after $(( $(date +%s) - t0 ))s: $(echo "$r" | jq -c '{response, error, load_s: ((.load_duration // 0) / 1e9 | floor), eval_count}')"
ollama ps | tee ollama_ps.txt
ollama stop "$m" > /dev/null 2>&1
echo "$r" | jq -r 'if (.eval_duration // 0) > 0 then (.eval_count / (.eval_duration / 1e9) * 10 | floor / 10) else empty end' > tps.txt
echo "$r" | jq -e '(.error == null) and ((.response // "") | length > 0)' > /dev/null
EOF
    slow  "deepseek-r1:1.5b answers (thinking off, 32 tokens)" 'bash models_gen.sh' 1800
    hint  "a first load reads the model from disk into RAM; a timeout usually means little memory was available (close Chrome tabs and Android apps on the ChromeOS side)"
    if [ -s "$WORK/ollama_ps.txt" ]; then
        info "where deepseek-r1:1.5b ran (Ollama's PROCESSOR column)" "$(awk 'NR == 2' "$WORK/ollama_ps.txt" | grep -oE '[0-9]+%/[0-9]+% CPU/GPU|[0-9]+% (CPU|GPU)' | head -n 1) (always CPU in Crostini)"
    fi
    [ -s "$WORK/tps.txt" ] && info "deepseek-r1:1.5b generation speed" "$(cat "$WORK/tps.txt") tokens/s"
    # Whether the 8K context and the q8_0 KV cache took effect: Ollama falls back to an f16 cache,
    # silently for the client, when flash attention is unavailable for a model. The server log says.
    if [ -s "$WORK/ollama_ps.txt" ]; then
        ctx=$(awk 'NR == 2' "$WORK/ollama_ps.txt" | grep -oE '(CPU|GPU) +[0-9]+ ' | grep -oE '[0-9]+' | tail -n 1)
        [ -n "$ctx" ] && info "deepseek-r1:1.5b context length (Ollama's CONTEXT column)" "$ctx (setup sets 8192)"
        kv=$(sudo -n journalctl -u ollama --since "-30min" --no-pager 2> /dev/null | grep -iE 'flash.?attn|flash attention|kv.?cache.?type|type_k' | tail -n 1 | sed -E 's/.*(msg=|level=[A-Z]+ )//' | cut -c1-90)
        info "KV cache / flash attention (Ollama's log)" "${kv:-nothing logged in the last 30 min}"
    fi
    slow  "qwen3-embedding:0.6b returns embeddings"        'm=qwen3-embedding:0.6b; ollama list | awk "NR > 1 {print \$1}" | grep -qxF "$m" || { echo "SKIPPED: $m is not pulled"; exit 0; }; r=$(curl -sS --max-time 900 http://127.0.0.1:11434/api/embed -d "{\"model\":\"$m\",\"input\":[\"Crostini runs Debian\",\"Ollama serves local models\"],\"keep_alive\":0}"); echo "$r" | jq -c "{error, vectors: (.embeddings | length?), dims: (.embeddings[0] | length?)}"; echo "$r" | jq -e "(.embeddings | length) == 2 and (.embeddings[0] | length) > 0" > /dev/null' 1200
fi

# Agentic workflow stack
if has install-agentic; then
    section "Agentic stack: Temporal, LangGraph, Pydantic, Langfuse (install-agentic)"
    check "temporal CLI (brew)"                            'temporal --version'
    check "aliases agentic / tsdb in ~/.bashrc"            'grep -q "alias agentic=" ~/.bashrc && grep -q "alias tsdb=" ~/.bashrc'
    check "~/agentic/langfuse/docker-compose.yml fetched"  '[ -s ~/agentic/langfuse/docker-compose.yml ]'
    check "~/agentic/.env.example present"                 '[ -f ~/agentic/.env.example ]'
    warn  "~/agentic/.env has Langfuse keys"               'grep -q "^LANGFUSE_SECRET_KEY=sk-lf-" ~/agentic/.env'
    hint  "cp ~/agentic/.env.example ~/agentic/.env and add your cloud.langfuse.com keys"
    check "~/.agentic-env import smoke (same set as the installer)" '~/.agentic-env/bin/python -c "import temporalio, temporalio.contrib.pydantic, langgraph, langgraph.checkpoint.sqlite, pydantic, langfuse, langfuse.langchain, langchain_ollama, langchain_anthropic, langchain_google_genai, dotenv, rich, pytest, pytest_asyncio"'

    cat > "$WORK/pydantic_smoke.py" << 'EOF'
from pydantic import BaseModel, ValidationError
class Candidate(BaseModel):
    name: str
    score: int
assert Candidate(name="x", score="42").score == 42          # coercion
try:
    Candidate(name="x", score="not a number"); raise SystemExit("validation did not fire")
except ValidationError:
    pass
print("pydantic ok")
EOF
    check "Pydantic validates and coerces"                 '~/.agentic-env/bin/python pydantic_smoke.py | grep -q "pydantic ok"'

    cat > "$WORK/langgraph_smoke.py" << 'EOF'
from typing import TypedDict
from langgraph.graph import StateGraph, START, END
from langgraph.checkpoint.sqlite import SqliteSaver
class S(TypedDict):
    n: int
g = StateGraph(S)
g.add_node("inc", lambda s: {"n": s["n"] + 1})
g.add_edge(START, "inc"); g.add_edge("inc", END)
with SqliteSaver.from_conn_string("checkpoints.sqlite") as saver:
    app = g.compile(checkpointer=saver)
    out = app.invoke({"n": 41}, config={"configurable": {"thread_id": "t1"}})
    assert out["n"] == 42, out
    assert app.get_state({"configurable": {"thread_id": "t1"}}).values["n"] == 42
print("langgraph ok")
EOF
    check "LangGraph graph runs with SqliteSaver checkpoints" '~/.agentic-env/bin/python langgraph_smoke.py | grep -q "langgraph ok"'

    # v52: the workflow sandbox re-imports the module that defines the workflow. If that module is
    # the script itself (with a bare asyncio.run at top level), the re-import re-runs main() inside
    # the sandbox and fails. Same rule applies to your real worker.py: keep workflows in their own
    # module, or guard the entry point with  if __name__ == "__main__":
    cat > "$WORK/smoke_workflows.py" << 'EOF'
from datetime import timedelta
from pydantic import BaseModel
from temporalio import activity, workflow

class Ping(BaseModel):
    msg: str

@activity.defn
async def echo(p: Ping) -> Ping:
    return Ping(msg=f"echo:{p.msg}")

@workflow.defn
class SmokeWorkflow:
    @workflow.run
    async def run(self, p: Ping) -> Ping:
        return await workflow.execute_activity(echo, p, start_to_close_timeout=timedelta(seconds=10))
EOF
    cat > "$WORK/temporal_smoke.py" << 'EOF'
import asyncio, uuid
from temporalio.client import Client
from temporalio.worker import Worker
from temporalio.contrib.pydantic import pydantic_data_converter
from smoke_workflows import Ping, SmokeWorkflow, echo

async def main():
    print("[1/4] connecting to localhost:17233", flush=True)
    client = await asyncio.wait_for(Client.connect("localhost:17233", data_converter=pydantic_data_converter), 20)
    print("[2/4] connected; starting worker", flush=True)
    tq = "dev-test-" + uuid.uuid4().hex[:8]
    async with Worker(client, task_queue=tq, workflows=[SmokeWorkflow], activities=[echo]):
        print("[3/4] worker up; executing workflow", flush=True)
        r = await asyncio.wait_for(client.execute_workflow(
            SmokeWorkflow.run, Ping(msg="pong"), id="dev-test-" + uuid.uuid4().hex, task_queue=tq), 60)
    assert r.msg == "echo:pong", r
    print("[4/4] temporal ok", flush=True)

if __name__ == "__main__":
    asyncio.run(main())
EOF
    # Port 17233 so it never collides with a 'tsdb' dev server. v55: a stale server from an interrupted
    # run is found by the port it holds (ss), NOT with pkill -f: this whole check runs as bash -c "...",
    # so a pkill pattern that appears in the command text would kill the check's own shell (exit 143).
    # v54: unloads any Ollama model first (RAM), logs free memory, and on failure prints
    # the client's step trail and the server log tail instead of timing out silently.
    slow  "Temporal: dev server + worker + Pydantic workflow round-trip" 'for p in $(ss -ltnpH "sport = :17233" 2> /dev/null | grep -oE "pid=[0-9]+" | cut -d= -f2 | sort -u); do kill "$p" 2> /dev/null; done; if command -v ollama > /dev/null; then for m in $(ollama ps 2> /dev/null | tail -n +2 | awk "{print \$1}"); do ollama stop "$m" > /dev/null 2>&1; done; fi; free -h | head -2; temporal server start-dev --headless --port 17233 --log-level warn > temporal-server.log 2>&1 & pid=$!; trap "kill $pid 2> /dev/null" EXIT; for _ in $(seq 1 30); do temporal operator cluster health --address localhost:17233 > /dev/null 2>&1 && break; kill -0 $pid 2> /dev/null || break; sleep 1; done; ~/.agentic-env/bin/python temporal_smoke.py > temporal-client.log 2>&1; rc=$?; cat temporal-client.log; if [ $rc -ne 0 ] || ! grep -q "temporal ok" temporal-client.log; then echo "--- server log tail:"; tail -20 temporal-server.log; exit 1; fi' 180
    # v89: MCP tooling. A two-line FastMCP server; FastMCP's own client calls its tool, then the MCP
    # Inspector's CLI mode does, once as 'mcp-inspector' and once through npx with no network (the copy
    # setup left in npm's cache, which 'fastmcp dev inspector' uses too).
    cat > "$WORK/mcp_server.py" << 'EOF'
from fastmcp import FastMCP

mcp = FastMCP("devtest")


@mcp.tool
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b
EOF
    check "fastmcp CLI (uv tool fastmcp-slim, with fastmcp)"   'fastmcp version 2>&1 | grep -E "FastMCP version|MCP version"'
    hint  "rerun setup with install-agentic: v89 installs it with 'uv tool install fastmcp-slim --with fastmcp'"
    check "fastmcp: list and call a tool on a local server"    'fastmcp list mcp_server.py 2>&1 | grep -q "add(" && r=$(fastmcp call mcp_server.py add a=2 b=3 --json 2>&1); echo "$r" | tr -d " \n" | grep -o "\"result\":5" || { echo "$r" | tail -n 5; exit 1; }' 180
    if has install-node; then
        check "MCP Inspector (mcp-inspector, global npm)"      'command -v mcp-inspector && npm ls -g --depth=0 @modelcontextprotocol/inspector | grep -o "inspector@[0-9.]*"'
        hint  "rerun setup with install-agentic (it needs install-node for the Inspector)"
        check "Inspector CLI calls the tool through fastmcp run" 'r=$(mcp-inspector --cli fastmcp run mcp_server.py --method tools/call --tool-name add --tool-arg a=2 --tool-arg b=3 2>&1); echo "$r" | tr -d " \n" | grep -o "\"result\":5" || { echo "$r" | tail -n 5; exit 1; }' 180
        warn  "npx starts the Inspector offline (the cached copy fastmcp dev uses)" 'r=$(npx --offline @modelcontextprotocol/inspector --cli fastmcp run mcp_server.py --method tools/list 2>&1); echo "$r" | grep -q "\"add\"" && echo "tools/list over npx --offline: add" || { echo "$r" | tail -n 5; exit 1; }' 180
        hint  "a newer Inspector release than the cached one makes npx want the network: rerun setup with install-agentic"
    else
        info  "MCP Inspector" "not installed: it is a Node app (rerun setup with install-agentic install-node)"
    fi
fi

# Cloud provider CLIs (install-cloud = install-aws install-azure install-gcp)
if has install-aws; then
    section "AWS CLI (install-aws)"
    check "aws CLI v2 (brew)"                              'aws --version | grep -q "^aws-cli/2\."'
    warn  "aws credentials resolve (sts get-caller-identity)" 'aws sts get-caller-identity --output text' 60
    hint  "run dev-init with install-aws: 'aws configure sso', or static keys in ~/.config/dev-init/secrets.env"
fi

if has install-azure; then
    section "Azure CLI (install-azure)"
    # the first 'az' call after install is slow (extension index, Python startup); allow 3 minutes
    check "az CLI (brew)"                                  'az version --query "\"azure-cli\"" -o tsv' 180
    warn  "az is logged in"                                'az account show --query name -o tsv' 60
    hint  "run dev-init with install-azure: 'az login --use-device-code'"
fi

if has install-gcp; then
    section "Google Cloud CLI (install-gcp)"
    check "Google Cloud apt source + keyring"              '[ -f /etc/apt/sources.list.d/google-cloud-sdk.list ] && [ -f /etc/apt/keyrings/cloud.google.gpg ]'
    check "gcloud"                                         'gcloud --version | grep -q "Google Cloud SDK"'
    warn  "gcloud has an active account"                   'gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"' 60
    hint  "run dev-init with install-gcp: 'gcloud auth login'"
    warn  "application default credentials for the SDKs"   '[ -f ~/.config/gcloud/application_default_credentials.json ] || [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ] || grep -qE "^export GOOGLE_APPLICATION_CREDENTIALS=\"[^\"]+\"" ~/.config/dev-init/secrets.env 2> /dev/null'
    hint  "gcloud auth application-default login (or a service-account key path in secrets.env)"
fi

# Vercel CLI
if has install-vercel; then
    section "Vercel CLI (install-vercel)"
    check "vercel CLI"                                     'vercel --version 2> /dev/null | tail -n 1 | grep -E "^[0-9]+\."'
    hint  "rerun the installer with install-vercel (npm install -g vercel)"
    check "vercel telemetry is off"                        'vercel telemetry status 2>&1 | grep -qi "disabled"'
    hint  "vercel telemetry disable"
    warn  "vercel is logged in (saved login or VERCEL_TOKEN)" 'vercel whoami < /dev/null 2>&1 | tail -n 2; vercel whoami < /dev/null > /dev/null 2>&1' 60
    hint  "run dev-init with install-vercel: 'vercel login', or set VERCEL_TOKEN in secrets.env"
fi

# Cloudflare (v89): wrangler (install-cloudflare, in install-cloud) and cloudflared (install-cloudflared,
# opt-in). The local check runs a Worker with a local D1 database under 'wrangler dev': workerd and
# miniflare on this machine, no account. No tunnel is ever opened here.
if has install-cloudflare; then
    section "Cloudflare wrangler (install-cloudflare)"
    check "wrangler CLI (global npm)"                      'wrangler --version 2> /dev/null | tail -n 1 | grep -E "^[0-9]+\."'
    hint  "rerun setup with install-cloudflare (npm install -g wrangler)"
    mkdir -p "$WORK/cf-worker"
    cat > "$WORK/cf-worker/index.js" << 'EOF'
export default {
  async fetch(request, env) {
    await env.DB.exec("CREATE TABLE IF NOT EXISTS hits (n INTEGER)");
    await env.DB.prepare("INSERT INTO hits VALUES (1)").run();
    const row = await env.DB.prepare("SELECT count(*) AS c FROM hits").first();
    return new Response("worker-ok d1=" + row.c);
  },
};
EOF
    cat > "$WORK/cf-worker/wrangler.toml" << 'EOF'
name = "devtest-worker"
main = "index.js"
compatibility_date = "2026-09-01"

[[d1_databases]]
binding = "DB"
database_name = "devtest"
database_id = "00000000-0000-0000-0000-000000000000"
EOF
    cat > "$WORK/cf_dev.sh" << 'EOF'
cd cf-worker || exit 1
p=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
CI=1 WRANGLER_SEND_METRICS=false wrangler dev --ip 127.0.0.1 --port "$p" > dev.log 2>&1 &
pid=$!
trap 'kill $pid 2> /dev/null; wait $pid 2> /dev/null' EXIT
for i in $(seq 1 90); do
    r=$(curl -s --max-time 5 "http://127.0.0.1:$p/") && [ -n "$r" ] && break
    kill -0 $pid 2> /dev/null || break
    sleep 1
done
echo "GET / -> ${r:-no answer} (after ${i}s)"
[ "${r#worker-ok}" != "$r" ] || { tail -n 8 dev.log; exit 1; }
EOF
    slow  "wrangler dev runs a Worker with a local D1 database (no account)" 'bash cf_dev.sh' 300
    hint  "workerd, the local runtime, comes with wrangler's npm install: rerun setup with install-cloudflare"
    warn  "wrangler is logged in (CLOUDFLARE_API_TOKEN or a saved login)" 'if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] && ! grep -qE "^[[:space:]]*(export[[:space:]]+)?CLOUDFLARE_API_TOKEN=\"?[^\"]+" ~/.config/dev-init/secrets.env 2> /dev/null && [ ! -f ~/.config/.wrangler/config/default.toml ]; then echo "SKIPPED: no CLOUDFLARE_API_TOKEN and no saved login (optional)"; exit 0; fi; [ -f ~/.config/dev-init/secrets.env ] && { set -a; . ~/.config/dev-init/secrets.env; set +a; }; CI=1 wrangler whoami < /dev/null 2>&1 | grep -viE "^ *$|proxy" | tail -n 4; CI=1 wrangler whoami < /dev/null 2>&1 | grep -qiE "associated with the email|You are logged in"' 90
    hint  "a rejected token: create one at dash.cloudflare.com/profile/api-tokens (template 'Edit Cloudflare Workers'), put it in secrets.env, rerun dev-init"
fi
if has install-cloudflared; then
    section "Cloudflare Tunnel: cloudflared (install-cloudflared)"
    check "cloudflared (Cloudflare's apt repository)"      'cloudflared --version | head -n 1 && apt-cache policy cloudflared | grep -q pkg.cloudflare.com'
    hint  "rerun setup with install-cloudflared; its log says whether apt could read pkg.cloudflare.com"
    check "the repository is signed with Cloudflare's current key" 'grep -q "signed-by=/usr/share/keyrings/cloudflare-main.gpg" /etc/apt/sources.list.d/cloudflared.list && [ -s /usr/share/keyrings/cloudflare-main.gpg ]'
    info  "tunnels" "none opened by setup or this test; 'cloudflared tunnel --url http://localhost:PORT' makes a public URL"
fi

# Jev (TypeSafe AI): hosted decision model; SDKs are per project, so these run in throwaway projects
if has install-jev; then
    section "Jev / TypeSafe AI: SDKs, keys, live smoke calls (install-jev)"
    cat > "$WORK/jev_smoke.py" <<'EOF'
import sys
from typesafe_sdk import Choice, Noul, TypeSafeClient, TypeSafeError

teams = {"billing": "Payment or subscription issues",
         "technical": "Bugs or integration problems",
         "other": "Anything else"}
try:
    r = TypeSafeClient(timeout=30).system_one(
        state="I was charged twice for order A-104. Please refund the duplicate.",
        questions={
            "team": Choice(instructions="Which team should handle this", criteria=teams),
            "refund": Noul(instructions="The customer is explicitly asking for a refund"),
        },
    )
except TypeSafeError as e:  # one readable line instead of a traceback
    sys.exit(f"Jev call failed: {type(e).__name__}: {e}")
team, refund = r.answers["team"], r.answers["refund"]
print(f"model={r.model} team={team.choice} confidence={team.confidence:.3f} refund={refund.noul:.3f}")
# Type safety is the point: the choice must be one of ours and the probability a probability.
sys.exit(0 if team.choice in teams and 0.0 <= refund.noul <= 1.0 else 1)
EOF
    cat > "$WORK/jev_gateway.mjs" <<'EOF'
import { experimental_evaluate as evaluate } from 'ai';

if (typeof evaluate !== 'function') {
  console.error('this AI SDK has no experimental_evaluate (needs ai >= 7.0.105)');
  process.exit(2);
}
try {
  const result = await evaluate({
    model: 'typesafe-ai/jev',
    state: 'I was charged twice for order A-104. Please refund the duplicate.',
    questions: {
      refund: { type: 'boolean', instructions: 'The customer is explicitly asking for a refund' },
    },
  });
  console.log('gateway answers:', JSON.stringify(result.answers));
  process.exit(result.answers && 'refund' in result.answers ? 0 : 1);
} catch (e) {
  // One readable line instead of a dumped error object.
  console.error(`gateway call failed: ${e?.name ?? 'Error'} ${e?.statusCode ?? ''} ${e?.message ?? e}`);
  process.exit(1);
}
EOF
    # Keys: a value already in the environment wins, otherwise secrets.env supplies it (this script
    # does not source ~/.bashrc, and an empty template line in secrets.env must not blank a real key).
    slow  "Python SDK installs and imports (uv, throwaway env)" 'uv run --no-project --with typesafe-sdk python -c "import sys, typesafe_sdk; from typesafe_sdk import Choice, Score, Noul, TypeSafeClient; print(\"typesafe-sdk\", typesafe_sdk.__version__, \"on python\", sys.version.split()[0])"' 600
    hint  "if this Python has no wheels for a dependency yet, pin one that does: uv run --python 3.12 --with typesafe-sdk ..."
    slow  "JavaScript SDK installs and imports (throwaway project)" 'mkdir -p jev-js && cd jev-js && npm init -y > /dev/null && npm install --silent --no-audit --no-fund @typesafe-ai/sdk && node --input-type=module -e "import { choice, noul, TypeSafeClient } from \"@typesafe-ai/sdk\"; console.log(\"@typesafe-ai/sdk ok:\", typeof TypeSafeClient, typeof choice, typeof noul)"' 600
    warn  "a Jev key is configured (TYPESAFE_API_KEY or AI_GATEWAY_API_KEY)" '_t="$TYPESAFE_API_KEY"; _g="$AI_GATEWAY_API_KEY"; [ -f ~/.config/dev-init/secrets.env ] && { set -a; . ~/.config/dev-init/secrets.env; set +a; }; export TYPESAFE_API_KEY="${_t:-$TYPESAFE_API_KEY}" AI_GATEWAY_API_KEY="${_g:-$AI_GATEWAY_API_KEY}"; [ -n "$TYPESAFE_API_KEY" ] && echo "TYPESAFE_API_KEY set"; [ -n "$AI_GATEWAY_API_KEY" ] && echo "AI_GATEWAY_API_KEY set"; [ -n "$TYPESAFE_API_KEY$AI_GATEWAY_API_KEY" ]'
    hint  "console.typesafe.ai (early access is waitlisted) or the AI Gateway tab of the Vercel dashboard; put the key in secrets.env and run dev-init with install-jev"
    # v68: slowwarn, not slow. A rejected or unfunded key is a credentials matter (WARN), not a broken install.
    slowwarn "live call to Jev, direct (skipped without TYPESAFE_API_KEY)" '_t="$TYPESAFE_API_KEY"; _g="$AI_GATEWAY_API_KEY"; [ -f ~/.config/dev-init/secrets.env ] && { set -a; . ~/.config/dev-init/secrets.env; set +a; }; export TYPESAFE_API_KEY="${_t:-$TYPESAFE_API_KEY}" AI_GATEWAY_API_KEY="${_g:-$AI_GATEWAY_API_KEY}"; if [ -z "$TYPESAFE_API_KEY" ]; then echo "SKIPPED: no TYPESAFE_API_KEY"; exit 0; fi; uv run --no-project --with typesafe-sdk python jev_smoke.py' 300
    hint  "401/403: the key is wrong or the account is still waitlisted. 429: rate limited, rerun later"
    slowwarn "live call to Jev through Vercel AI Gateway (skipped without AI_GATEWAY_API_KEY)" '_t="$TYPESAFE_API_KEY"; _g="$AI_GATEWAY_API_KEY"; [ -f ~/.config/dev-init/secrets.env ] && { set -a; . ~/.config/dev-init/secrets.env; set +a; }; export TYPESAFE_API_KEY="${_t:-$TYPESAFE_API_KEY}" AI_GATEWAY_API_KEY="${_g:-$AI_GATEWAY_API_KEY}"; if [ -z "$AI_GATEWAY_API_KEY" ]; then echo "SKIPPED: no AI_GATEWAY_API_KEY"; exit 0; fi; mkdir -p jev-gw && cd jev-gw && cp ../jev_gateway.mjs . && npm init -y > /dev/null && npm install --silent --no-audit --no-fund ai@latest && node jev_gateway.mjs' 600
    hint  "needs AI SDK 7.0.105+ (experimental_evaluate) and a gateway key with credit; the API is marked experimental, so its shape may move"
    warn  "TypeSafe skill installed in Claude Code"         'claude plugin list 2> /dev/null | grep -qi typesafe || grep -rqsi "typesafe" ~/.claude/plugins/ 2> /dev/null'
    hint  "claude plugin marketplace add typesafe-ai/skills && claude plugin install typesafe@typesafe-ai"
fi

# Infrastructure as Code
if has install-iac; then
    section "IaC: Terraform, tflint, Bicep (install-iac)"
    check "terraform (hashicorp/tap)"                      'terraform version | grep -qE "^Terraform v[0-9]"'
    check "tflint (release binary, /usr/local/bin)"        '[ -x /usr/local/bin/tflint ] && tflint --version'
    hint  "tflint left homebrew-core; setup v61+ installs the upstream release zip. Rerun setup with install-iac"
    warn  "provider plugin cache configured (~/.terraformrc)" 'grep -q plugin_cache_dir ~/.terraformrc'
    hint  "run dev-init with install-iac; it writes ~/.terraformrc so providers download once per machine"
    mkdir -p "$WORK/tf"
    cat > "$WORK/tf/main.tf" << 'EOF'
terraform {
  required_providers {
    local = { source = "hashicorp/local" }
  }
}
resource "local_file" "t" {
  filename = "${path.module}/out.txt"
  content  = "tf ok"
}
EOF
    slow  "terraform init + apply (hashicorp/local only, no cloud)" 'cd tf && terraform init -input=false -no-color > /dev/null && terraform apply -auto-approve -input=false -no-color > /dev/null && grep -q "tf ok" out.txt' 300
    if command -v az > /dev/null 2>&1; then
        check "bicep via az (installed alongside the Azure CLI)" 'az bicep version' 180
    else
        warn  "bicep (needs the Azure CLI: add install-azure)" 'false'
    fi
fi

# Ansible (v76). Full and core share one pipx venv, 'ansible-core'; full adds the 'ansible' package.
if has install-ansible-full || has install-ansible-core; then
    if has install-ansible-full; then
        section "Ansible: full community package (install-ansible-full, part of install-iac)"
    else
        section "Ansible: core only (install-ansible-core)"
    fi
    export ANSIBLE_NOCOLOR=1 ANSIBLE_PYTHON_INTERPRETER=auto_silent
    check "pipx venv 'ansible-core' built on /usr/bin/python3"  'v="$(pipx environment --value PIPX_LOCAL_VENVS)/ansible-core"; h=$(sed -n "s/^home = //p" "$v/pyvenv.cfg"); echo "$v: home = $h"; [ "$h" = /usr/bin ]'
    hint  "rerun setup with install-iac (full) or install-ansible-core: v76 keeps Ansible in one pipx venv named ansible-core"
    check "ansible commands resolve to that venv"               'for c in ansible ansible-playbook ansible-galaxy ansible-vault ansible-doc ansible-inventory ansible-lint molecule; do p=$(command -v "$c") || { echo "missing: $c"; exit 1; }; case "$(readlink -f "$p")" in */pipx/venvs/ansible-core/*) ;; *) echo "$c -> $(readlink -f "$p") (not the bundle venv)"; exit 1 ;; esac; done; ansible --version'
    hint  "another Ansible is earlier on PATH (apt, brew or a pipx venv named ansible): remove it and rerun setup"
    if has install-ansible-full; then
        check "full package: ansible-community + bundled collections" 'ansible-community --version && n=$(ansible-galaxy collection list 2> /dev/null | grep -cE "^[a-z0-9_]+\.[a-z0-9_]+ +[0-9]"); echo "$n collections"; [ "$n" -gt 50 ]'
        check "kubernetes.core bundled (for kind clusters)"   'ansible-galaxy collection list kubernetes.core 2> /dev/null | grep -q "^kubernetes.core "'
    fi
    check "community.docker collection"                         'ansible-galaxy collection list community.docker 2> /dev/null | grep -E "^community.docker "'
    hint  "install-ansible-core gets it from Galaxy: ansible-galaxy collection install community.docker"
    check "Docker SDK + requests in the venv (community.docker modules)" '"$(pipx environment --value PIPX_LOCAL_VENVS)/ansible-core/bin/python" -c "import docker, requests; print(\"docker\", docker.__version__, \"requests\", requests.__version__)"'
    check "ansible-lint and molecule"                           'ansible-lint --version && molecule --version'
    check "venv dependencies consistent (pip check)"            'pipx runpip ansible-core check'
    hint  "usually 'pipx upgrade-all' moved ansible-core past the ansible package's pin: rerun setup with the same flags"
    warn  "vault password file readable (ANSIBLE_VAULT_PASSWORD_FILE, optional)" 'if [ -z "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ]; then echo "not set (optional)"; exit 0; fi; f="${ANSIBLE_VAULT_PASSWORD_FILE/#\~/$HOME}"; ls -l "$f" && [ -r "$f" ]'
    hint  "secrets.env exports ANSIBLE_VAULT_PASSWORD_FILE but the file is missing: every ansible command stops on it. Create it (one line, chmod 600) or comment the line out"
    # The scratch projects below use no vault. With the variable set, 'ansible-vault encrypt' sees two
    # default vault ids and refuses, and a missing file stops every command, so they run without it.
    unset ANSIBLE_VAULT_PASSWORD_FILE
    mkdir -p "$WORK/ansible"
    cat > "$WORK/ansible/site.yml" << 'EOF'
---
- name: Dev-test play
  hosts: all
  gather_facts: true
  tasks:
    - name: Write a file
      ansible.builtin.copy:
        dest: "{{ out_dir }}/ansible-ok.txt"
        content: "ansible ok on {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}\n"
        mode: "0644"

    - name: Check it is there
      ansible.builtin.stat:
        path: "{{ out_dir }}/ansible-ok.txt"
      register: ok_file

    - name: Assert the file exists
      ansible.builtin.assert:
        that: ok_file.stat.exists
EOF
    cat > "$WORK/ansible/docker-inventory.yml" << 'EOF'
---
all:
  hosts:
    devtest-ansible:
      ansible_connection: community.docker.docker
      ansible_python_interpreter: /usr/local/bin/python3
EOF
    check "ad-hoc ping on localhost"                            'ansible all -i localhost, -c local -m ansible.builtin.ping'
    check "playbook on localhost, then an idempotent rerun"     'cd ansible && ansible-playbook -i localhost, -c local -e out_dir="$PWD" site.yml && cat ansible-ok.txt && grep -q "^ansible ok on Debian" ansible-ok.txt && ansible-playbook -i localhost, -c local -e out_dir="$PWD" site.yml | tail -n 3 | tee /dev/stderr | grep -qE "changed=0 .*failed=0"'
    check "ansible-lint passes the playbook (production profile)" 'cd ansible && ansible-lint --offline site.yml'
    check "ansible-vault encrypt + view round-trip"             'cd ansible && printf "devtest\n" > vpass && chmod 600 vpass && echo "secret: 42" > s.yml && ansible-vault encrypt --vault-password-file vpass s.yml > /dev/null && head -c 14 s.yml | grep -qF "\$ANSIBLE_VAULT" && ansible-vault view --vault-password-file vpass s.yml | grep -q "secret: 42"'
    # Container targets. python:3.13-slim is Debian 13 with a Python in /usr/local (Ansible modules
    # need one on the target). Both containers are removed on exit, pass or fail, and the log shows it.
    slow  "playbook against a Docker container (community.docker connection)" 'cd ansible && docker rm -f devtest-ansible > /dev/null 2>&1; trap "echo \"--- teardown:\"; docker rm -f devtest-ansible 2>&1" EXIT; docker run -d --name devtest-ansible python:3.13-slim sleep 600 > /dev/null && ansible-playbook -i docker-inventory.yml -e out_dir=/tmp site.yml && docker exec devtest-ansible cat /tmp/ansible-ok.txt | tee /dev/stderr | grep -q "^ansible ok on Debian"' 600
    hint  "needs the docker group active in this shell (open a new terminal) and Docker Hub reachable for python:3.13-slim"
    mkdir -p "$WORK/ansible-mol/molecule/default"
    cat > "$WORK/ansible-mol/molecule/default/molecule.yml" << 'EOF'
---
ansible:
  executor:
    args:
      ansible_playbook:
        - --inventory=${MOLECULE_SCENARIO_DIRECTORY}/inventory.yml
scenario:
  test_sequence:
    - destroy
    - syntax
    - create
    - converge
    - idempotence
    - verify
    - destroy
EOF
    cat > "$WORK/ansible-mol/molecule/default/inventory.yml" << 'EOF'
---
all:
  hosts:
    devtest-molecule:
      ansible_connection: community.docker.docker
      ansible_python_interpreter: /usr/local/bin/python3
EOF
    cat > "$WORK/ansible-mol/molecule/default/create.yml" << 'EOF'
---
- name: Create
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Start the test container
      community.docker.docker_container:
        name: devtest-molecule
        image: python:3.13-slim
        command: sleep 900
        state: started
EOF
    cat > "$WORK/ansible-mol/molecule/default/destroy.yml" << 'EOF'
---
- name: Destroy
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Remove the test container
      community.docker.docker_container:
        name: devtest-molecule
        state: absent
EOF
    cat > "$WORK/ansible-mol/molecule/default/converge.yml" << 'EOF'
---
- name: Converge
  hosts: all
  gather_facts: false
  tasks:
    - name: Write a file
      ansible.builtin.copy:
        dest: /tmp/molecule-ok.txt
        content: "molecule ok\n"
        mode: "0644"
EOF
    cat > "$WORK/ansible-mol/molecule/default/verify.yml" << 'EOF'
---
- name: Verify
  hosts: all
  gather_facts: false
  tasks:
    - name: Read the file back
      ansible.builtin.slurp:
        src: /tmp/molecule-ok.txt
      register: ok_file

    - name: Assert its content
      ansible.builtin.assert:
        that: (ok_file.content | b64decode) == "molecule ok\n"
EOF
    slow  "molecule test: create, converge, idempotence, verify, destroy" 'cd ansible-mol && trap "echo \"--- teardown:\"; docker rm -f devtest-molecule 2>&1" EXIT; molecule test 2>&1 | grep -E "INFO|ERROR|fatal|FAILED|PLAY RECAP|devtest-molecule +:"; [ "${PIPESTATUS[0]}" -eq 0 ]' 900
    hint  "the create step starts python:3.13-slim with community.docker.docker_container, which needs 'requests' in the venv (rerun setup); the log has Molecule's full output"
fi

# Kubernetes tooling
if has install-k8s; then
    section "Kubernetes: kubectl, helm, kind, k9s (install-k8s)"
    check "kubectl (brew)"                                 'kubectl version --client'
    check "helm"                                           'helm version --short'
    check "kind"                                           'kind version'
    check "k9s"                                            'k9s version'
    # v74: completion lives in bash-completion's per-user directory; ~/.bashrc must not run kubectl at startup.
    check "kubectl completion files + k alias (nothing run at shell start)" 'd=~/.local/share/bash-completion/completions; [ -s $d/kubectl ] && [ -s $d/k ] && grep -q "complete -o default -F __start_kubectl k" $d/k && grep -qx "alias k=kubectl" ~/.bashrc && ! grep -q "kubectl completion bash" ~/.bashrc'
    hint  "rerun the installer with install-k8s: v74 writes the completion files and removes the old ~/.bashrc lines"
    # Pulls the ~1GB kind node image on first run and needs ~2GB RAM, so any Ollama model is unloaded
    # first (same trick as the Temporal check). The cluster uses its own kubeconfig in $WORK, so
    # ~/.kube/config is never touched, and it is deleted again on exit, pass or fail.
    # v60: verified on Crostini (passed in 50s, Ready after 17s, with 1.8GiB 'available'). Read the
    # 'available' column of the free -h line: the VM sees ~6.4GB of an 8GB machine and crosvm's
    # balloon shows up as 'used'. The EXIT-trap delete now prints, so the log proves the teardown.
    slow  "kind: create cluster, node Ready, helm reaches it, delete" 'if command -v ollama > /dev/null; then for m in $(ollama ps 2> /dev/null | tail -n +2 | awk "{print \$1}"); do ollama stop "$m" > /dev/null 2>&1; done; fi; free -h | head -2; kind delete cluster --name dev-test --kubeconfig kubeconfig > /dev/null 2>&1; trap "echo \"--- teardown:\"; kind delete cluster --name dev-test --kubeconfig kubeconfig 2>&1" EXIT; kind create cluster --name dev-test --kubeconfig kubeconfig --wait 180s && kubectl --kubeconfig kubeconfig get nodes && kubectl --kubeconfig kubeconfig get nodes --no-headers | grep -q " Ready " && helm --kubeconfig kubeconfig list > /dev/null' 900
    hint  "kind needs the docker group active in this shell and ~2GB free RAM; if the node container fails to start, check 'docker logs dev-test-control-plane'"
fi

# =================================================================
# LAPTOP NETWORK (v84): install-lan (the address book in /etc/hosts and the 'lan' command) and
# install-lan-share (the relay that shares this machine's services). Opt-in, not in install-all.
# v93: over Tailscale (unless LAN_TAILSCALE=0): normal mode (tailscale0), tailscale0 holding this laptop's
# LAN_HOSTS address, 'tailscale serve' publishing every LAN_SHARE port, and per other laptop a 'tailscale ping'
# (direct or DERP, INFO) and 'lan probe': each service that accepts a connection gets one exchange in its own
# protocol, because 'tailscale serve' accepts connections even when the service behind it is stopped (a WARN
# naming the service) and Ollama answers a Host name it does not accept with 403 (a FAIL naming the cause).
# The relay's checks and its "reached from the network" record stay for LAN_TAILSCALE=0 only.
# Other laptops that are off or asleep are WARNs, never FAILs. The relay's own code is checked with a
# throwaway relay and web server on free high ports (a few seconds), so the check does not depend on
# what LAN_SHARE says or which services run. Whether a ChromeOS port forward works cannot be seen from
# inside Linux: it is reported as INFO, from the relay's record of connections from the network.
# =================================================================
if has install-lan; then
    section "Laptop network: address book and the lan command (install-lan)"
    # The settings, read once in a subshell (not exported by secrets.env).
    _lan_cfg() { bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$HOME/.config/dev-init/secrets.env" "$1" 2> /dev/null; }
    LAN_HOSTS_V=$(_lan_cfg LAN_HOSTS); LAN_SHARE_V=$(_lan_cfg LAN_SHARE)
    LAN_SELF_V=$(_lan_cfg LAN_SELF); [ -n "$LAN_SELF_V" ] || LAN_SELF_V=$(_lan_cfg MACHINE_LABEL)
    # v93: over Tailscale unless LAN_TAILSCALE=0 (the v84 relay and ChromeOS port forwarding).
    LAN_TS_V=$(_lan_cfg LAN_TAILSCALE); [ -n "$LAN_TS_V" ] || LAN_TS_V=1
    LAN_TS=0; [ "$LAN_TS_V" != 0 ] && command -v tailscale > /dev/null 2>&1 && LAN_TS=1
    export LAN_ADDR; LAN_ADDR=$(ip -4 -o addr show 2> /dev/null | awk '$2 !~ /^(lo|docker|br-|veth|virbr|cni|flannel|kube|tailscale|wg)/ { split($4, a, "/"); print a[1]; exit }')
    check "the lan command runs"                               '[ -x ~/.local/bin/lan ] || { echo "no ~/.local/bin/lan"; exit 1; }; lan help > /dev/null && lan status'
    hint  "rerun setup with install-lan"
    check "iproute2 (ip, ss)"                                  'ip -V && ss -V'
    if [ "$LAN_TS_V" != 0 ]; then
        check "Tailscale is installed (v93: the laptops talk over it)" 'command -v tailscale && tailscale version | head -n 1'
        hint  "rerun setup with install-lan (v93 installs it from pkgs.tailscale.com); LAN_TAILSCALE=0 in secrets.env keeps the v84 relay instead"
        check "Tailscale runs in normal mode (tailscale0, not userspace)" 'grep -H "^FLAGS=" /etc/default/tailscaled; grep -q "^FLAGS=.*--tun=tailscale0" /etc/default/tailscaled && ip -4 -o addr show dev tailscale0'
        hint  "rerun setup with install-lan: it sets FLAGS=\"--tun=tailscale0\" in /etc/default/tailscaled and restarts tailscaled (in userspace mode Linux tools cannot reach the 100.x addresses)"
        warn  "Tailscale is connected to your tailnet"         'tailscale status --json | jq -e -r "select(.BackendState == \"Running\") | .BackendState"'
        hint  "dev-init with install-lan joins it (sudo tailscale up --operator=\$USER --hostname=<this laptop>); after a key expiry, log in again"
        LAN_ADDR=$(ip -4 -o addr show dev tailscale0 2> /dev/null | awk '{ split($4, a, "/"); print a[1]; exit }')
    else
        check "this Linux has a network address (ChromeOS forwards to it)" '[ -n "$LAN_ADDR" ] && echo "$LAN_ADDR"'
        hint  "only loopback and bridges found: 'ip -4 addr' shows what Linux has; restarting Linux usually brings eth0 back"
    fi
    warn  "the address book (LAN_HOSTS) is filled in"          "[ -n \"$(echo "$LAN_HOSTS_V" | tr -d ' ,;')\" ] && echo \"$LAN_HOSTS_V\""
    hint  "optional: LAN_HOSTS in ~/.config/dev-init/secrets.env, every laptop as name=address (the same list on each; over Tailscale the 100.x addresses 'tailscale status' lists), then dev-init"
    if [ -n "$(echo "$LAN_HOSTS_V" | tr -d ' ,;')" ]; then
        check "LAN_HOSTS has no malformed entries"             'e=$(lan hosts 2>&1 > /dev/null | grep "skipped"); [ -z "$e" ] || { echo "$e"; exit 1; }; echo "all name=address"'
        hint  "each entry is name=address, e.g. joxer=100.64.0.11; names are letters, digits, dots, dashes"
        check "/etc/hosts has the address book, with NAME.internal (lan hosts check)" 'lan hosts check && sed -n "/^# >>> dev-lan hosts >>>$/,/^# <<< dev-lan hosts <<<$/p" /etc/hosts'
        hint  "dev-init with install-lan writes it ('lan hosts apply' does the same; v93 adds the NAME.internal names). If it is gone after every Linux restart, tell the bundle's author: ChromeOS would be rewriting /etc/hosts"
        check "every laptop name resolves to its address (this one to 127.0.0.1)" 'bad=0; while read -r n ip; do w=$ip; [ "$n" = "'"$LAN_SELF_V"'" ] && w=127.0.0.1; g=$(getent ahostsv4 "$n" | awk "{print \$1; exit}"); gi=$(getent ahostsv4 "$n.internal" | awk "{print \$1; exit}"); echo "$n -> ${g:-nothing}, $n.internal -> ${gi:-nothing} (want $w)"; [ "$g" = "$w" ] && [ "$gi" = "$w" ] || bad=1; done < <(lan hosts 2> /dev/null | awk "NF >= 2 && \$2 ~ /^[0-9.]+$/ {print \$1, \$2}"); exit $bad'
        warn  "this machine is in the address book"            "[ -n \"$LAN_SELF_V\" ] && echo \"$LAN_HOSTS_V\" | tr ',; ' '\n\n\n' | grep -q \"^$LAN_SELF_V=\" && echo \"$LAN_SELF_V\""
        hint  "set MACHINE_LABEL (or LAN_SELF) to this machine's name in LAN_HOSTS, and list it with its address, so every laptop's list is the same"
        LAN_SELF_IP=$(echo "$LAN_HOSTS_V" | tr ',; ' '\n\n\n' | sed -n "s/^$LAN_SELF_V=//p" | head -n 1)
        if [ "$LAN_TS" = 1 ] && [ -n "$LAN_SELF_IP" ]; then
            # v93: the check v92 passed on 100.115.92.26, the internal address every Chromebook's Linux has.
            check "tailscale0 holds this laptop's address in LAN_HOSTS ($LAN_SELF_V=$LAN_SELF_IP)" "a=\$(ip -4 -o addr show dev tailscale0 2> /dev/null | awk '{ split(\$4, x, \"/\"); print x[1]; exit }'); echo \"tailscale0: \${a:-none}\"; [ \"\$a\" = '$LAN_SELF_IP' ]"
            hint  "put the address 'tailscale ip -4' prints into LAN_HOSTS ($LAN_SELF_V=...) on every laptop, then dev-init"
        fi
        while read -r LAN_N LAN_IP; do
            [ -n "$LAN_N" ] && [ "$LAN_N" != "$LAN_SELF_V" ] || continue
            if [ "$LAN_TS" != 1 ]; then
                warn "laptop $LAN_N ($LAN_IP) answers on a known service port" "lan scan --brief '$LAN_N'" 60
                hint "off, asleep or sharing nothing ('lan share' on $LAN_N says what it serves). If every laptop is silent, the Wi-Fi may keep devices apart (guest networks, 'client/AP isolation' on the router)"
                continue
            fi
            # v93: how Tailscale gets there, then each service that accepts a connection, in its own protocol.
            info "laptop $LAN_N: path" "$(lan path "$LAN_N" 2> /dev/null | sed 's/^[^ ]* *[^ ]* *//' | head -n 1)"
            LAN_PROBE=$(timeout 120 lan probe --tsv "$LAN_N" 2> /dev/null)
            if [ -z "$LAN_PROBE" ]; then
                warn "laptop $LAN_N ($LAN_IP): a shared service accepts connections" "lan probe '$LAN_N'" 120
                hint "off, asleep, not on your tailnet, or sharing nothing ('lan share' on $LAN_N lists what it publishes)"
                continue
            fi
            while IFS=$'\t' read -r LAN_P LAN_SVC LAN_STATE _; do
                case "$LAN_STATE" in
                    up)
                        check "$LAN_N: $LAN_SVC ($LAN_P) answers in its own protocol" "lan probe '$LAN_N' $LAN_P"
                        hint  "it answered a moment ago: 'lan probe $LAN_N $LAN_P' again" ;;
                    forbidden)
                        check "$LAN_N: $LAN_SVC ($LAN_P) accepts this laptop's Host name" "lan probe '$LAN_N' $LAN_P"
                        hint  "Ollama refuses the Host name $LAN_N.internal: 'lan hosts apply' here (v93 writes the .internal names); the address http://$LAN_IP:$LAN_P works meanwhile" ;;
                    *)
                        warn  "$LAN_N: $LAN_SVC ($LAN_P) answers behind its open port" "lan probe '$LAN_N' $LAN_P"
                        hint  "$LAN_N publishes the port but the service behind it is stopped: start it there ('ollama' service, 'mssql up', 'oracle up', 'ddev start', 'devsvc up NAME'; 'lan share' on $LAN_N shows which)" ;;
                esac
            done <<< "$LAN_PROBE"
        done < <(lan hosts 2> /dev/null | awk 'NF >= 2 && $2 ~ /^[0-9.]+$/ {print $1, $2}')
    fi
fi

# v93: over Tailscale, sharing is 'tailscale serve' (the relay is stopped); the relay checks stay for LAN_TAILSCALE=0.
if has install-lan-share && [ "${LAN_TS:-0}" = 1 ]; then
    section "Laptop network: sharing over Tailscale (install-lan-share)"
    check "the shared-port list matches LAN_SHARE (relay.tsv)"  'diff <(lan share plan 2> /dev/null) <(grep -v "^#" ~/.config/dev-lan/relay.tsv) && echo "$(grep -vc "^#" ~/.config/dev-lan/relay.tsv) port(s)"'
    hint  "LAN_SHARE changed since: 'lan share apply' (dev-init does it too)"
    if [ -f ~/.config/dev-lan/sharing-off ]; then
        skipped "Tailscale publishes every LAN_SHARE port" "(sharing is switched off: 'lan share on')"
    elif [ "$(tailscale status --json 2> /dev/null | jq -r '.BackendState // ""')" != Running ]; then
        skipped "Tailscale publishes every LAN_SHARE port" "(Tailscale is not connected: dev-init with install-lan)"
    else
        check "Tailscale publishes every LAN_SHARE port (tailscale serve)" 'have=" $(tailscale serve status --json 2> /dev/null | jq -r ".TCP // {} | keys[]" | xargs) "; m=""; while IFS=$'"'"'\t'"'"' read -r p lp label; do case "$p" in ""|\#*) continue ;; esac; [[ "$have" == *" $p "* ]] || m="$m $p($label)"; done < ~/.config/dev-lan/relay.tsv; echo "published:$have"; [ -z "$m" ] || { echo "not published:$m"; echo "fix: lan share apply"; exit 1; }'
        hint  "'lan share apply' publishes them (dev-init does it too); 'tailscale serve' refusing means this user is not Tailscale's operator: sudo tailscale set --operator=\$USER"
        LAN_EXTRA_PUB=$(tailscale serve status --json 2> /dev/null | jq -r '.TCP // {} | keys[]' 2> /dev/null | while read -r _p; do grep -v '^#' ~/.config/dev-lan/relay.tsv 2> /dev/null | cut -f1 | grep -qx "$_p" || echo "$_p"; done | xargs)
        [ -z "$LAN_EXTRA_PUB" ] || info "also published by hand with 'tailscale serve'" "$LAN_EXTRA_PUB (lan leaves them alone)"
    fi
    if systemctl is-active --quiet dev-lan-relay.service 2> /dev/null; then
        info "the v84 relay" "running: not needed over Tailscale ('lan share apply' stops it)"
    else
        info "the v84 relay" "off (not used over Tailscale; LAN_TAILSCALE=0 brings it back)"
    fi
    check "lan shares a devsvc service only with a login (the rule, in a scratch home)" 'h=$PWD/lanhome; mkdir -p "$h/.config/devsvc"; : > "$h/.config/devsvc/devsvc.env"
s="redis qdrant mongodb solr typesense memcached milvus"
a=$(HOME=$h LAN_SHARE="$s" lan share plan 2> notes.txt | cut -f1 | xargs); echo "no logins: ports $a; refused: $(grep -c . notes.txt)"
printf "REDIS_PASSWORD=x
QDRANT_API_KEY=k
MONGO_ROOT_PASSWORD=m
" > "$h/.config/devsvc/devsvc.env"
b=$(HOME=$h LAN_SHARE="$s" lan share plan 2> notes2.txt | cut -f1 | xargs); echo "with logins: ports $b; refused: $(grep -c . notes2.txt)"
[ "$a" = "8983 8108" ] && [ "$(grep -c . notes.txt)" = 5 ] && [ "$b" = "6379 6333 6334 27017 8983 8108" ] && [ "$(grep -c . notes2.txt)" = 2 ]'
    hint  "the lan command is older than setup v89's: rerun setup with install-lan"
    warn  "every service in LAN_SHARE is shared (lan share plan refuses none)" 'n=$(lan share plan 2>&1 > /dev/null | grep -E "not shared|never shared|unknown service|ignoring"); [ -z "$n" ] || { echo "$n"; exit 1; }; echo "none refused"'
    hint  "redis, qdrant and mongodb need REDIS_PASSWORD / QDRANT_API_KEY / MONGO_ROOT_PASSWORD in secrets.env and a dev-setup run; memcached, milvus and atlas-local are never shared"
    # Each shared service here, in its own protocol, on this machine (another laptop's dev-test checks the
    # whole path through Tailscale). A service that is not running is reported, not failed.
    if [ -n "$LAN_SELF_V" ]; then
        while IFS=$'\t' read -r LAN_P LAN_LP LAN_LABEL; do
            [ -n "$LAN_P" ] || continue
            if ! { (exec 3<> "/dev/tcp/127.0.0.1/$LAN_LP") 2> /dev/null || (exec 3<> "/dev/tcp/::1/$LAN_LP") 2> /dev/null; }; then
                info "$LAN_P $LAN_LABEL" "not running here right now (published anyway; other laptops' 'lan probe' report it as down)"
            elif [ "$LAN_P" = "$LAN_LP" ]; then
                warn "$LAN_P $LAN_LABEL: answers here in its own protocol" "lan probe '$LAN_SELF_V' $LAN_P"
                hint "it listens on $LAN_LP but does not answer like $LAN_LABEL: 'lan probe $LAN_SELF_V $LAN_P' shows what came back"
            else
                info "$LAN_P $LAN_LABEL" "running here on $LAN_LP (published as $LAN_P)"
            fi
        done < <(lan share plan 2> /dev/null)
    fi
    for LAN_KIND in dev mcp; do
        case " $(echo "$LAN_SHARE_V" | tr ',;' '  ') " in *" $LAN_KIND "*) ;; *) continue ;; esac
        if [ "$LAN_KIND" = dev ]; then LAN_PORTS=$(_lan_cfg LAN_DEV_PORTS); LAN_PORTS=${LAN_PORTS:-3000 4200 5173}
        else LAN_PORTS=$(_lan_cfg LAN_MCP_PORTS); LAN_PORTS=${LAN_PORTS:-8770}; fi
        for LAN_P in $(echo "$LAN_PORTS" | tr ',;' '  '); do
            warn "$LAN_P ($LAN_KIND server): not listening on this machine only" "l=\$(ss -Htln 'sport = :$LAN_P' | awk '{print \$4}'); if [ -z \"\$l\" ]; then echo 'SKIPPED: nothing listens on $LAN_P right now'; exit 0; fi; echo \"\$l\"; echo \"\$l\" | grep -qvE '^(127\\.|\\[::1\\]|::1:|\\[::ffff:127\\.)'"
            hint "it listens on 127.0.0.1 only, so no other laptop reaches it: restart it with --host (Vite), --host 0.0.0.0 (ng serve), -H 0.0.0.0 (next dev), host=\"0.0.0.0\" (MCP)"
        done
    done
fi

if has install-lan-share && [ "${LAN_TS:-0}" != 1 ]; then
    section "Laptop network: sharing through the relay (install-lan-share, LAN_TAILSCALE=0)"
    cat > "$WORK/relay_selftest.sh" << 'EOF'
# A throwaway relay (the installed lan-relay.py) and web servers on free ports: IPv4 and IPv6-only
# targets pass through, a port with nothing behind it closes, and this machine's own connections are
# not counted as coming from the network.
R=$HOME/.local/lib/dev-lan/lan-relay.py
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
P1=$(free_port); P2=$(free_port); P3=$(free_port); P4=$(free_port); P5=$(free_port); P6=$(free_port)
mkdir -p www state && echo "relay-token-$$" > www/token.txt
python3 -m http.server "$P1" --bind 127.0.0.1 --directory www > http4.log 2>&1 & S1=$!
V6=0; S2=""
if python3 -c 'import socket; socket.socket(socket.AF_INET6).bind(("::1", 0))' 2> /dev/null; then
    python3 -m http.server "$P5" --bind ::1 --directory www > http6.log 2>&1 & S2=$!; V6=1
fi
printf '%s\t%s\tselftest ok\n%s\t%s\tselftest down\n' "$P2" "$P1" "$P3" "$P4" > relay.tsv
[ "$V6" = 1 ] && printf '%s\t%s\tselftest v6\n' "$P6" "$P5" >> relay.tsv
python3 "$R" relay.tsv state > relay.log 2>&1 & RP=$!
trap 'kill $RP $S1 $S2 2> /dev/null' EXIT
for _ in $(seq 50); do [ -f state/relay-status.json ] && break; sleep 0.2; done
sleep 1
cat relay.log
t=$(curl -fsS --max-time 5 "http://$LAN_ADDR:$P2/token.txt") || { echo "no answer through the relay on $LAN_ADDR:$P2"; exit 1; }
[ "$t" = "relay-token-$$" ] || { echo "wrong answer: $t"; exit 1; }
echo "OK: $LAN_ADDR:$P2 -> 127.0.0.1:$P1"
if [ "$V6" = 1 ]; then
    t=$(curl -fsS --max-time 5 "http://$LAN_ADDR:$P6/token.txt") || { echo "a server on ::1 only was not reached"; exit 1; }
    echo "OK: $LAN_ADDR:$P6 -> [::1]:$P5 (a server that bound localhost as IPv6 only)"
fi
if curl -fsS --max-time 5 -o /dev/null "http://$LAN_ADDR:$P3/" 2> /dev/null; then echo "a port with nothing behind it answered"; exit 1; fi
echo "OK: nothing behind $P3, connection closed"
sleep 1.5   # the status file is written once a second
jq -e --arg a "$P2" --arg b "$P3" '.ports[$a].connections >= 1 and .ports[$b].target_failures >= 1' state/relay-status.json > /dev/null \
    || { echo "the status file does not show the connections:"; cat state/relay-status.json; exit 1; }
if [ -s state/seen.json ]; then echo "a connection from this machine was counted as coming from the network:"; cat state/seen.json; exit 1; fi
echo "OK: status file counts the connections; none counted as coming from the network"
EOF
    cat > "$WORK/lan_port_check.sh" << 'EOF'
# lan_port_check.sh LAN_PORT LOCAL_PORT: does the service answer through the relay, on this Linux's
# network address? Starts nothing: a service that is not running here is skipped.
lan=$1; lp=$2; A=$LAN_ADDR
up() { (exec 3<> "/dev/tcp/127.0.0.1/$1") 2> /dev/null || (exec 3<> "/dev/tcp/::1/$1") 2> /dev/null; }
tcp() { (exec 3<> "/dev/tcp/$A/$lan") 2> /dev/null && echo "port $lan answers on $A"; }
up "$lp" || { echo "SKIPPED: nothing runs on port $lp here right now, so there is nothing to pass through"; exit 0; }
case $lan in
    11434) curl -fsS --max-time 10 "http://$A:11434/api/version" ;;
    17170) curl -fsS --max-time 10 -o /dev/null -w "lldap web UI: HTTP %{http_code}\n" "http://$A:17170/" ;;
    3890|1389)
        . "$HOME/.config/devldap/ldap.env" || exit 1
        ldapwhoami -x -H "ldap://$A:$lan" -D "uid=drupal-bind,ou=people,$LDAP_BASE_DN" -w "$LDAP_BIND_PASSWORD" ;;
    8080|8443)
        s=http; [ "$lan" = 8443 ] && s=https
        site=$(ddev list -j 2> /dev/null | jq -r '[.raw[]? | select(.status == "running") | .name][0] // empty')
        if [ -n "$site" ]; then
            code=$(curl -ksS --max-time 30 -o /dev/null -w "%{http_code}" --resolve "$site.ddev.site:$lan:$A" "$s://$site.ddev.site:$lan/")
            echo "$s://$site.ddev.site:$lan through $A: HTTP $code"; [ "$code" != 000 ]
        else
            tcp && echo "(no DDEV project running to fetch a page from)"
        fi ;;
    1433)
        if command -v sqlcmd > /dev/null && command -v mssql > /dev/null; then
            SQLCMDPASSWORD=$(mssql password) sqlcmd -S "$A,1433" -U sa -C -h -1 -Q "SET NOCOUNT ON; SELECT 'through the relay: ' + @@SERVERNAME"
        else tcp; fi ;;
    1521)
        if command -v sql > /dev/null && command -v oracle > /dev/null; then
            echo "SELECT 'through the relay: ' || sys_context('USERENV', 'CON_NAME') FROM dual;" | timeout 150 sql -S -L "system/$(oracle password)@//$A:1521/FREEPDB1" | grep -m1 'through the relay'
        else tcp; fi ;;
    *) tcp ;;
esac
EOF
    check "the relay: lan-relay.py is in place and parses"   'f=~/.local/lib/dev-lan/lan-relay.py; [ -f "$f" ] && python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$f" && echo "$f"'
    hint  "rerun setup with install-lan-share"
    check "the relay passes connections through (throwaway relay + server)" 'bash relay_selftest.sh' 60
    hint  "the log has the relay's own output; this tests the code only, not LAN_SHARE or ChromeOS"
    check "dev-lan-relay.service is installed and enabled"    'systemctl cat dev-lan-relay.service > /dev/null && systemctl is-enabled dev-lan-relay.service'
    hint  "'lan share on' switches it on (setup leaves it as it was, so a 'lan share off' before a trip stays off)"
    check "dev-lan-relay.service is running"                  'systemctl is-active dev-lan-relay.service'
    hint  "'journalctl -u dev-lan-relay' says why; 'lan share on' starts it"
    check "the relay's config matches LAN_SHARE"              'diff <(lan share plan 2> /dev/null) <(grep -v "^#" ~/.config/dev-lan/relay.tsv) && echo "$(grep -vc "^#" ~/.config/dev-lan/relay.tsv) port(s)"'
    hint  "LAN_SHARE changed since the relay was configured: 'lan share apply' (dev-init does it too)"
    # v89: the devsvc services. The rule itself, in a throwaway home: redis, qdrant and mongodb are shared only
    # with their login, the search engines always, memcached / milvus / atlas-local never.
    check "lan shares a devsvc service only with a login (the rule, in a scratch home)" 'h=$PWD/lanhome; mkdir -p "$h/.config/devsvc"; : > "$h/.config/devsvc/devsvc.env"
s="redis qdrant mongodb solr typesense memcached milvus"
a=$(HOME=$h LAN_SHARE="$s" lan share plan 2> notes.txt | cut -f1 | xargs); echo "no logins: ports $a; refused: $(grep -c . notes.txt)"
printf "REDIS_PASSWORD=x
QDRANT_API_KEY=k
MONGO_ROOT_PASSWORD=m
" > "$h/.config/devsvc/devsvc.env"
b=$(HOME=$h LAN_SHARE="$s" lan share plan 2> notes2.txt | cut -f1 | xargs); echo "with logins: ports $b; refused: $(grep -c . notes2.txt)"
[ "$a" = "8983 8108" ] && [ "$(grep -c . notes.txt)" = 5 ] && [ "$b" = "6379 6333 6334 27017 8983 8108" ] && [ "$(grep -c . notes2.txt)" = 2 ]'
    hint  "the lan command is older than setup v89's: rerun setup with install-lan"
    warn  "every service in LAN_SHARE is shared (lan share plan refuses none)" 'n=$(lan share plan 2>&1 > /dev/null | grep -E "not shared|never shared|unknown service|ignoring"); [ -z "$n" ] || { echo "$n"; exit 1; }; echo "none refused"'
    hint  "redis, qdrant and mongodb need REDIS_PASSWORD / QDRANT_API_KEY / MONGO_ROOT_PASSWORD in secrets.env and a dev-setup run; memcached, milvus and atlas-local are never shared"
    if [ -z "$(echo "$LAN_SHARE_V" | tr -d ' ,;')" ]; then
        info  "shared services" "none (optional: LAN_SHARE in secrets.env, from ollama mssql oracle ldap ddev dev mcp redis solr opensearch elasticsearch meilisearch typesense qdrant mongodb)"
    elif systemctl is-active --quiet dev-lan-relay.service 2> /dev/null; then
        while IFS=$'\t' read -r LAN_P LAN_LP LAN_LABEL; do
            [ -n "$LAN_P" ] || continue
            check "$LAN_P $LAN_LABEL: the relay listens on this Linux's address" "jq -e -r --arg p '$LAN_P' '.ports[\$p] | select(.status == \"relaying\" or .status == \"direct\") | \"\\(.status) \\(.listen | join(\" \")) \\(.detail)\"' ~/.local/state/dev-lan/relay-status.json"
            hint  "'journalctl -u dev-lan-relay' names what holds the port; 'lan share' shows every port"
            warn  "$LAN_P $LAN_LABEL: the service answers through the relay" "bash lan_port_check.sh '$LAN_P' '$LAN_LP'" 180
            hint  "the service answers on 127.0.0.1:$LAN_LP but not through $LAN_ADDR:$LAN_P; 'lan share' and the relay's journal say more"
        done < <(lan share plan 2> /dev/null)
        LAN_SEEN=$(lan share seen)
        if [ -n "$LAN_SEEN" ]; then
            info "reached from the network (ChromeOS forward works)" "$(echo "$LAN_SEEN" | awk '{printf "%s%s from %s", (NR > 1 ? "; " : ""), $1, $2}')"
        else
            info "reached from the network" "no port yet: add the ChromeOS forwards ('lan share ports'), then run 'lan scan' on another laptop"
        fi
    fi
    # dev and mcp servers listen on the network themselves; one bound to 127.0.0.1 only is unreachable.
    for LAN_KIND in dev mcp; do
        case " $(echo "$LAN_SHARE_V" | tr ',;' '  ') " in *" $LAN_KIND "*) ;; *) continue ;; esac
        if [ "$LAN_KIND" = dev ]; then LAN_PORTS=$(_lan_cfg LAN_DEV_PORTS); LAN_PORTS=${LAN_PORTS:-3000 4200 5173}
        else LAN_PORTS=$(_lan_cfg LAN_MCP_PORTS); LAN_PORTS=${LAN_PORTS:-8770}; fi
        for LAN_P in $(echo "$LAN_PORTS" | tr ',;' '  '); do
            warn "$LAN_P ($LAN_KIND server): not listening on this machine only" "l=\$(ss -Htln 'sport = :$LAN_P' | awk '{print \$4}'); if [ -z \"\$l\" ]; then echo 'SKIPPED: nothing listens on $LAN_P right now'; exit 0; fi; echo \"\$l\"; echo \"\$l\" | grep -qvE '^(127\\.|\\[::1\\]|::1:|\\[::ffff:127\\.)'"
            hint "it listens on 127.0.0.1 only, so no other laptop reaches it: restart it with --host (Vite), --host 0.0.0.0 (ng serve), -H 0.0.0.0 (next dev), host=\"0.0.0.0\" (MCP)"
        done
    done
fi

# =================================================================
# COM development under Wine (v85, install-com). Quick checks: the tools (wine, mingw i686 + x86_64,
# widl) and the pieces widl needs (the system .idl files, stdole2.tlb), the COM Wine prefix and the
# ~/.bashrc block. Slow checks build a small COM server FROM SOURCE with widl + mingw and exercise it
# under Wine, at BOTH bitnesses: an in-process server (a DLL, registered with regsvr32 and created with
# CoCreateInstance), an out-of-process local server (an EXE, the same activation path DCOM uses across
# machines), a two-way method call, and a read-back of the generated type library. The build writes
# only into $WORK; registration goes into the COM prefix and is undone afterwards. Everything here was
# run before release on Ubuntu 24.04's Wine 9 (no ChromeOS in the sandbox).
# =================================================================
if has install-com; then
    section "COM development under Wine (install-com)"
    export WINEPREFIX="${DEV_COM_PREFIX:-$HOME/.local/share/wine/com}"
    export WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
    export COM_IDL_INC="${DEV_COM_IDL_INC:-$(dirname "$(find /usr/include/wine -name unknwn.idl 2> /dev/null | head -n 1)" 2> /dev/null)}"
    export COM_TLB64="${DEV_COM_TLB64:-/usr/lib/x86_64-linux-gnu/wine/x86_64-windows}"
    export COM_TLB32="${DEV_COM_TLB32:-/usr/lib/i386-linux-gnu/wine/i386-windows}"
    check "wine (the COM runtime: ole32, oleaut32, rpcss)"     'wine --version'
    hint  "rerun dev-setup with install-com"
    check "mingw-w64 cross-compilers (i686 and x86_64) + windres" 'i686-w64-mingw32-gcc --version | head -n 1 && x86_64-w64-mingw32-gcc --version | head -n 1 && x86_64-w64-mingw32-windres --version | head -n 1'
    check "widl (both bitnesses)"                              'i686-w64-mingw32-widl -V | head -n 1 && x86_64-w64-mingw32-widl -V | head -n 1'
    check "COM headers for mingw (objbase.h, oleauto.h)"       'for h in objbase.h oleauto.h unknwn.h; do [ -f /usr/x86_64-w64-mingw32/include/$h ] || { echo "missing: $h"; exit 1; }; done'
    check "system .idl files for widl (unknwn.idl, oaidl.idl)" '[ -n "$COM_IDL_INC" ] && [ -f "$COM_IDL_INC/unknwn.idl" ] && [ -f "$COM_IDL_INC/oaidl.idl" ] && echo "$COM_IDL_INC"'
    hint  "libwine-dev provides these; rerun dev-setup with install-com"
    check "stdole2.tlb for both bitnesses (type libraries importlib it)" '[ -f "$COM_TLB64/stdole2.tlb" ] && [ -f "$COM_TLB32/stdole2.tlb" ] && echo "64: $COM_TLB64  32: $COM_TLB32"'
    check "the COM Wine prefix exists (WoW64: 64-bit + 32-bit)"   '[ -f "$WINEPREFIX/system.reg" ] && [ -d "$WINEPREFIX/drive_c/windows/syswow64" ]'
    hint  "rerun dev-setup with install-com; it runs 'wineboot -i' in $WINEPREFIX"
    check "~/.bashrc has the COM block (DEV_COM_* + wine-com)"    'blk=$(sed -n "/^# >>> dev-setup com >>>$/,/^# <<< dev-setup com <<<$/p" ~/.bashrc); [ -n "$blk" ] || { echo "no dev-setup com block"; exit 1; }; eval "$blk"; declare -F wine-com > /dev/null && [ -n "$DEV_COM_PREFIX" ]'
    warn  "winetricks (for vcrun / mfc42 / dotnet redistributables)" 'command -v winetricks && winetricks --version'
    hint  "optional; rerun dev-setup with install-com, or run it later: winetricks --self-update"

    # Fixtures: a small COM component (IDevHello: Greet + Add), built as an in-process DLL and an
    # out-of-process EXE from one object, plus a client that finds it by ProgID.
    mkdir -p "$WORK/com" && cd "$WORK/com" || true
    cat > devhello.idl << 'IDL_EOF'
// devhello.idl - a small COM interface, compiled by widl into a C header, IIDs and a type library.
import "oaidl.idl";

[
    object,
    uuid(6f1c2c9e-4b6a-4d0a-9a51-8d2f3e7b1a01),
    oleautomation,
    helpstring("DevHello: says hello and adds numbers")
]
interface IDevHello : IUnknown
{
    HRESULT Greet([in] BSTR who, [out, retval] BSTR *message);
    HRESULT Add([in] LONG a, [in] LONG b, [out, retval] LONG *sum);
}

[
    uuid(6f1c2c9e-4b6a-4d0a-9a51-8d2f3e7b1a00),
    version(1.0),
    helpstring("DevHello 1.0 Type Library")
]
library DevHelloLib
{
    importlib("stdole2.tlb");

    [uuid(6f1c2c9e-4b6a-4d0a-9a51-8d2f3e7b1a02), helpstring("DevHello, in-process server (DLL)")]
    coclass DevHello { [default] interface IDevHello; }

    [uuid(6f1c2c9e-4b6a-4d0a-9a51-8d2f3e7b1a03), helpstring("DevHello, out-of-process server (EXE)")]
    coclass DevHelloLocal { [default] interface IDevHello; }
}
IDL_EOF
    cat > devhello_obj.c << 'OBJ_EOF'
/* devhello_obj.c - the DevHello COM object, shared by the DLL (in-process) and EXE (out-of-process)
   servers. Plain C against the header widl generated from devhello.idl. */
#define COBJMACROS
#include <windows.h>
#include <ole2.h>
#include <olectl.h>
#include <stdio.h>
#include "devhello.h"

LONG g_objects = 0, g_locks = 0;
extern void on_last_release(void);   /* the EXE quits, the DLL does nothing */
extern const wchar_t *g_where;       /* "in-process" or "out-of-process" */

typedef struct { IDevHello iface; LONG ref; } HelloObj;

static HRESULT STDMETHODCALLTYPE dh_QueryInterface(IDevHello *This, REFIID riid, void **ppv)
{
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IDevHello)) {
        *ppv = This; IDevHello_AddRef(This); return S_OK;
    }
    *ppv = NULL; return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE dh_AddRef(IDevHello *This) { return InterlockedIncrement(&((HelloObj *)This)->ref); }
static ULONG STDMETHODCALLTYPE dh_Release(IDevHello *This)
{
    HelloObj *o = (HelloObj *)This;
    LONG r = InterlockedDecrement(&o->ref);
    if (r == 0) { HeapFree(GetProcessHeap(), 0, o); if (InterlockedDecrement(&g_objects) == 0 && g_locks == 0) on_last_release(); }
    return r;
}
static HRESULT STDMETHODCALLTYPE dh_Greet(IDevHello *This, BSTR who, BSTR *message)
{
    wchar_t buf[256];
    swprintf(buf, 256, L"hello %ls from DevHello (%d-bit, %ls, pid %lu)",
             who ? who : L"there", (int)(sizeof(void *) * 8), g_where, GetCurrentProcessId());
    *message = SysAllocString(buf);
    return *message ? S_OK : E_OUTOFMEMORY;
}
static HRESULT STDMETHODCALLTYPE dh_Add(IDevHello *This, LONG a, LONG b, LONG *sum) { *sum = a + b; return S_OK; }

static IDevHelloVtbl dh_vtbl = { dh_QueryInterface, dh_AddRef, dh_Release, dh_Greet, dh_Add };

/* The class factory: one static instance per server. */
static HRESULT STDMETHODCALLTYPE cf_QueryInterface(IClassFactory *This, REFIID riid, void **ppv)
{
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IClassFactory)) { *ppv = This; return S_OK; }
    *ppv = NULL; return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE cf_AddRef(IClassFactory *This) { return 2; }
static ULONG STDMETHODCALLTYPE cf_Release(IClassFactory *This) { return 1; }
static HRESULT STDMETHODCALLTYPE cf_CreateInstance(IClassFactory *This, IUnknown *outer, REFIID riid, void **ppv)
{
    HelloObj *o; HRESULT hr;
    if (outer) return CLASS_E_NOAGGREGATION;
    o = HeapAlloc(GetProcessHeap(), 0, sizeof(*o));
    if (!o) return E_OUTOFMEMORY;
    o->iface.lpVtbl = &dh_vtbl; o->ref = 1;
    InterlockedIncrement(&g_objects);
    hr = IDevHello_QueryInterface(&o->iface, riid, ppv);
    IDevHello_Release(&o->iface);
    return hr;
}
static HRESULT STDMETHODCALLTYPE cf_LockServer(IClassFactory *This, BOOL lock)
{
    if (lock) InterlockedIncrement(&g_locks);
    else if (InterlockedDecrement(&g_locks) == 0 && g_objects == 0) on_last_release();
    return S_OK;
}
static IClassFactoryVtbl cf_vtbl = { cf_QueryInterface, cf_AddRef, cf_Release, cf_CreateInstance, cf_LockServer };
IClassFactory g_factory = { &cf_vtbl };

/* Registry helpers for DllRegisterServer and /regserver. */
static LONG set_key(const wchar_t *path, const wchar_t *name, const wchar_t *value)
{
    HKEY k; LONG r = RegCreateKeyExW(HKEY_CLASSES_ROOT, path, 0, NULL, 0, KEY_WRITE, NULL, &k, NULL);
    if (r) return r;
    r = RegSetValueExW(k, name, 0, REG_SZ, (const BYTE *)value, (DWORD)((wcslen(value) + 1) * sizeof(wchar_t)));
    RegCloseKey(k);
    return r;
}
HRESULT register_class(REFCLSID clsid, const wchar_t *progid, const wchar_t *desc, const wchar_t *server_key,
                       const wchar_t *module_path, int dll)
{
    wchar_t cls[64], key[256];
    ITypeLib *tl = NULL; HRESULT hr;
    StringFromGUID2(clsid, cls, 64);
    swprintf(key, 256, L"CLSID\\%ls", cls);                   if (set_key(key, NULL, desc)) return SELFREG_E_CLASS;
    swprintf(key, 256, L"CLSID\\%ls\\%ls", cls, server_key);  if (set_key(key, NULL, module_path)) return SELFREG_E_CLASS;
    if (dll) set_key(key, L"ThreadingModel", L"Both");
    swprintf(key, 256, L"CLSID\\%ls\\ProgID", cls);           set_key(key, NULL, progid);
    swprintf(key, 256, L"%ls\\CLSID", progid);                if (set_key(key, NULL, cls)) return SELFREG_E_CLASS;
    swprintf(key, 256, L"%ls", progid);                        set_key(key, NULL, desc);
    /* The type library is a resource of this module: registering it also registers IDevHello with the
       type-library marshaler (it is [oleautomation]), which is what carries calls between processes. */
    hr = LoadTypeLibEx(module_path, REGKIND_REGISTER, &tl);
    if (SUCCEEDED(hr)) ITypeLib_Release(tl);
    return SUCCEEDED(hr) ? S_OK : SELFREG_E_TYPELIB;
}
HRESULT unregister_class(REFCLSID clsid, const wchar_t *progid)
{
    wchar_t cls[64], key[256];
    StringFromGUID2(clsid, cls, 64);
    swprintf(key, 256, L"CLSID\\%ls", cls);  RegDeleteTreeW(HKEY_CLASSES_ROOT, key);
    RegDeleteTreeW(HKEY_CLASSES_ROOT, progid);
    /* The type library goes too, with the marshaling entry it registered for IDevHello. The DLL and
       the EXE share it, so unregistering either removes it; the other re-registers it on /regserver. */
    UnRegisterTypeLib(&LIBID_DevHelloLib, 1, 0, LOCALE_NEUTRAL, sizeof(void *) == 8 ? SYS_WIN64 : SYS_WIN32);
    return S_OK;
}
OBJ_EOF
    cat > devhello_dll.c << 'DLL_EOF'
/* devhello_dll.c - DevHello as an in-process server: regsvr32 devhello.dll */
#include <windows.h>
#include <ole2.h>
#include <olectl.h>
#include "devhello.h"

extern LONG g_objects, g_locks;
extern IClassFactory g_factory;
HRESULT register_class(REFCLSID, const wchar_t *, const wchar_t *, const wchar_t *, const wchar_t *, int);
HRESULT unregister_class(REFCLSID, const wchar_t *);
const wchar_t *g_where = L"in-process";
void on_last_release(void) {}
static HMODULE g_module;

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID reserved)
{
    if (reason == DLL_PROCESS_ATTACH) { g_module = h; DisableThreadLibraryCalls(h); }
    return TRUE;
}
HRESULT WINAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void **ppv)
{
    if (!IsEqualCLSID(clsid, &CLSID_DevHello)) return CLASS_E_CLASSNOTAVAILABLE;
    return g_factory.lpVtbl->QueryInterface(&g_factory, riid, ppv);
}
HRESULT WINAPI DllCanUnloadNow(void) { return (g_objects == 0 && g_locks == 0) ? S_OK : S_FALSE; }
HRESULT WINAPI DllRegisterServer(void)
{
    wchar_t path[MAX_PATH];
    GetModuleFileNameW(g_module, path, MAX_PATH);
    return register_class(&CLSID_DevHello, L"DevTest.Hello", L"DevHello (in-process)", L"InprocServer32", path, 1);
}
HRESULT WINAPI DllUnregisterServer(void) { return unregister_class(&CLSID_DevHello, L"DevTest.Hello"); }
DLL_EOF
    cat > devhello_exe.c << 'EXE_EOF'
/* devhello_exe.c - DevHello as an out-of-process (local) server.
     devhello_local.exe /regserver     register (LocalServer32 + type library)
     devhello_local.exe /unregserver   unregister
   COM starts it with -Embedding when a client asks for CLSID_DevHelloLocal; it serves until the last
   object is released. Across machines this is the same mechanism DCOM uses. */
#include <windows.h>
#include <ole2.h>
#include <stdio.h>
#include "devhello.h"

extern LONG g_objects, g_locks;
extern IClassFactory g_factory;
HRESULT register_class(REFCLSID, const wchar_t *, const wchar_t *, const wchar_t *, const wchar_t *, int);
HRESULT unregister_class(REFCLSID, const wchar_t *);
const wchar_t *g_where = L"out-of-process";
static DWORD g_main_thread;
void on_last_release(void) { PostThreadMessageW(g_main_thread, WM_QUIT, 0, 0); }

int wmain(int argc, wchar_t **argv)
{
    wchar_t path[MAX_PATH]; DWORD cookie; MSG msg; HRESULT hr;
    GetModuleFileNameW(NULL, path, MAX_PATH);
    if (argc > 1 && (!_wcsicmp(argv[1], L"/regserver") || !_wcsicmp(argv[1], L"-regserver"))) {
        hr = register_class(&CLSID_DevHelloLocal, L"DevTest.HelloLocal", L"DevHello (out-of-process)", L"LocalServer32", path, 0);
        wprintf(L"register: 0x%08lx\n", hr); return FAILED(hr);
    }
    if (argc > 1 && (!_wcsicmp(argv[1], L"/unregserver") || !_wcsicmp(argv[1], L"-unregserver"))) {
        return FAILED(unregister_class(&CLSID_DevHelloLocal, L"DevTest.HelloLocal"));
    }
    g_main_thread = GetCurrentThreadId();
    PeekMessageW(&msg, NULL, 0, 0, PM_NOREMOVE);   /* make sure this thread has a message queue */
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    hr = CoRegisterClassObject(&CLSID_DevHelloLocal, (IUnknown *)&g_factory, CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, &cookie);
    if (FAILED(hr)) { fwprintf(stderr, L"CoRegisterClassObject: 0x%08lx\n", hr); return 1; }
    while (GetMessageW(&msg, NULL, 0, 0) > 0) DispatchMessageW(&msg);
    CoRevokeClassObject(cookie);
    CoUninitialize();
    return 0;
}
EXE_EOF
    cat > devhello_client.c << 'CLI_EOF'
/* devhello_client.c - finds DevHello by ProgID, creates it with CoCreateInstance, calls it, and reads
   its type library back from the registry.   devhello_client.exe [inproc|local] */
#define COBJMACROS
#include <windows.h>
#include <ole2.h>
#include <stdio.h>
#include "devhello.h"

int wmain(int argc, wchar_t **argv)
{
    int local = argc > 1 && !_wcsicmp(argv[1], L"local");
    const wchar_t *progid = local ? L"DevTest.HelloLocal" : L"DevTest.Hello";
    CLSID clsid; IDevHello *p = NULL; BSTR msg = NULL, who; LONG sum = 0; HRESULT hr;
    ITypeLib *tl; ITypeInfo *ti; TYPEATTR *ta;

    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    hr = CLSIDFromProgID(progid, &clsid);
    if (FAILED(hr)) { wprintf(L"CLSIDFromProgID(%ls) failed: 0x%08lx (not registered?)\n", progid, hr); return 2; }
    hr = CoCreateInstance(&clsid, NULL, local ? CLSCTX_LOCAL_SERVER : CLSCTX_INPROC_SERVER, &IID_IDevHello, (void **)&p);
    if (FAILED(hr)) { wprintf(L"CoCreateInstance(%ls) failed: 0x%08lx\n", progid, hr); return 3; }
    who = SysAllocString(L"client");
    if (FAILED(hr = IDevHello_Greet(p, who, &msg))) { wprintf(L"Greet failed: 0x%08lx\n", hr); return 4; }
    if (FAILED(hr = IDevHello_Add(p, 2, 40, &sum))) { wprintf(L"Add failed: 0x%08lx\n", hr); return 5; }
    wprintf(L"%ls\n", msg);
    wprintf(L"Add(2, 40) = %ld   (client: %d-bit, pid %lu)\n", sum, (int)(sizeof(void *) * 8), GetCurrentProcessId());
    SysFreeString(msg); SysFreeString(who);
    IDevHello_Release(p);
    if (SUCCEEDED(LoadRegTypeLib(&LIBID_DevHelloLib, 1, 0, LOCALE_NEUTRAL, &tl))) {
        if (SUCCEEDED(ITypeLib_GetTypeInfoOfGuid(tl, &IID_IDevHello, &ti)) && SUCCEEDED(ITypeInfo_GetTypeAttr(ti, &ta))) {
            wprintf(L"type library: IDevHello has %d methods of its own\n", ta->cFuncs);
            ITypeInfo_ReleaseTypeAttr(ti, ta); ITypeInfo_Release(ti);
        }
        ITypeLib_Release(tl);
    } else {
        wprintf(L"type library: not registered\n");
    }
    CoUninitialize();
    return sum == 42 ? 0 : 6;
}
CLI_EOF
    cat > devhello.def << 'DEF_EOF'
LIBRARY devhello
EXPORTS
    DllGetClassObject PRIVATE
    DllCanUnloadNow PRIVATE
    DllRegisterServer PRIVATE
    DllUnregisterServer PRIVATE
DEF_EOF
    cat > devhello.rc << 'RC_EOF'
1 TYPELIB "devhello.tlb"
RC_EOF
    cat > build.sh << 'BUILD_EOF'
# build.sh ARCH(32|64): widl + mingw build devhello.dll, devhello_local.exe and devhello_client.exe.
set -e
a=$1
if [ "$a" = 32 ]; then T=i686-w64-mingw32; L=$COM_TLB32; else T=x86_64-w64-mingw32; L=$COM_TLB64; fi
rm -rf "w$a"; mkdir "w$a"
$T-widl -m"$a" -I"$COM_IDL_INC" -L "$L" -h -H "w$a/devhello.h" -u -U "w$a/devhello_i.c" -t -T "w$a/devhello.tlb" devhello.idl
cd "w$a"
cp ../devhello_obj.c ../devhello_dll.c ../devhello_exe.c ../devhello_client.c ../devhello.def ../devhello.rc .
$T-windres devhello.rc -O coff -o devhello_res.o
CF="-O2 -municode -I."
# 32-bit: the .def names the exports without their @N stdcall decoration; this lets ld match them
# quietly instead of warning once per export. Compiler errors are left visible for the check's output.
LF=; [ "$a" = 32 ] && LF=-Wl,--enable-stdcall-fixup
# shellcheck disable=SC2086
$T-gcc $CF $LF -shared -o devhello.dll devhello_dll.c devhello_obj.c devhello_i.c devhello_res.o devhello.def -lole32 -loleaut32 -luuid -ladvapi32 -static-libgcc
# shellcheck disable=SC2086
$T-gcc $CF $LF -o devhello_local.exe devhello_exe.c devhello_obj.c devhello_i.c devhello_res.o -lole32 -loleaut32 -luuid -ladvapi32 -static-libgcc
# shellcheck disable=SC2086
$T-gcc $CF -o devhello_client.exe devhello_client.c devhello_i.c -lole32 -loleaut32 -luuid -static-libgcc
BUILD_EOF

    slow  "COM: widl + mingw build a server (DLL, EXE, client), 64-bit"   'cd "$WORK/com" && COM_IDL_INC="'"$COM_IDL_INC"'" COM_TLB64="'"$COM_TLB64"'" COM_TLB32="'"$COM_TLB32"'" bash build.sh 64 && file w64/devhello.dll w64/devhello_client.exe | sed "s/,.*//"' 300
    hint  "the earlier checks say which piece is missing (widl, the .idl files, stdole2.tlb, mingw)"
    slow  "COM 64-bit: regsvr32 the DLL, then CoCreateInstance + a method call (in-process)" 'cd "$WORK/com/w64" 2> /dev/null || { echo "build first"; exit 1; }; wine regsvr32 /s devhello.dll || exit 1; out=$(wine devhello_client.exe inproc 2>/dev/null); echo "$out"; wine regsvr32 /u /s devhello.dll 2>/dev/null; echo "$out" | grep -q "Add(2, 40) = 42"' 300
    hint  "0x80040154 (class not registered) means regsvr32 did not run; 0x80004005 often means the type-library marshaler is missing (stdole2.tlb)"
    slow  "COM 64-bit: out-of-process (local) server, the DCOM activation path" 'cd "$WORK/com/w64" 2> /dev/null || { echo "build first"; exit 1; }; wine devhello_local.exe /regserver >/dev/null 2>&1 || exit 1; out=$(wine devhello_client.exe local 2>/dev/null); echo "$out"; wine devhello_local.exe /unregserver >/dev/null 2>&1; echo "$out" | grep -q "out-of-process" && echo "$out" | grep -q "Add(2, 40) = 42"' 300
    hint  "COM launches the .exe on demand and marshals the call into it; the same mechanism carries DCOM across machines"
    slow  "COM 32-bit: build, regsvr32 and call in-process (most legacy COM is 32-bit)" 'cd "$WORK/com" && COM_IDL_INC="'"$COM_IDL_INC"'" COM_TLB64="'"$COM_TLB64"'" COM_TLB32="'"$COM_TLB32"'" bash build.sh 32 && cd w32 && wine regsvr32 /s devhello.dll || exit 1; out=$(wine devhello_client.exe inproc 2>/dev/null); echo "$out"; wine regsvr32 /u /s devhello.dll 2>/dev/null; echo "$out" | grep -q "32-bit, in-process"' 300
    info  "ATL / MFC"        "MSVC-only, so not built here; the clang-cl + xwin route is per project (Microsoft's license)"
    info  "ActiveX in a browser" "retired everywhere; an ActiveX control inside a container app can work under Wine (see the demo)"
    # Let the prefix's wineserver finish writing the registry and exit, so nothing is left running.
    timeout 60 wineserver -w 2> /dev/null || wineserver -k 2> /dev/null || true
    cd "$WORK" || true
fi

# =================================================================
# DOS / Windows 3.x development, and the Wine <-> DOSBox-X matrix (v85, install-retro). Open Watcom
# builds one small program for each target; each is then run on the engine that suits it, which is the
# comparison the matrix draws. DOS programs write a file under a mounted drive and DOSBox-X runs
# headless (SDL's dummy driver); Windows programs run under Wine. The Win16 program is what proves the
# 16-bit path Delphi 1 needs. Nothing here needs a real copy of Windows.
# =================================================================
if has install-retro; then
    section "DOS / Windows 3.x toolchain and the Wine <-> DOSBox-X matrix (install-retro)"
    export WATCOM=/opt/watcom
    export INCLUDE="$WATCOM/h"
    export PATH="$PATH:$WATCOM/binl64:$WATCOM/binl"
    export WINEPREFIX="${DEV_COM_PREFIX:-$HOME/.local/share/wine/com}" WINEDEBUG=-all
    check "DOSBox-X"                                        'dosbox-x --version 2>&1 | grep -m1 -i "dosbox-x version"'
    hint  "rerun dev-setup with install-retro (Debian's dosbox-x package)"
    check "Open Watcom on PATH (wcl 16-bit, wcl386 32-bit)" 'command -v wcl && command -v wcl386 && [ -x "$WATCOM/binw/dos4gw.exe" ]'
    hint  "rerun dev-setup with install-retro; it installs Open Watcom v2 into /opt/watcom and adds it to ~/.bashrc"
    check "~/.bashrc has the retro block (WATCOM, INCLUDE, PATH)" 'grep -q "^# >>> dev-setup retro >>>$" ~/.bashrc && grep -q "export WATCOM=/opt/watcom" ~/.bashrc'
    check "the win31 command and ~/win31 workspace"        '[ -x ~/.local/bin/win31 ] && [ -d ~/win31/drive_c ] && [ -d ~/win31/install/windows ] && [ -f ~/win31/dosbox-x.conf ]'
    hint  "rerun dev-setup with install-retro"
    # v92: the retro helper and its five guests (win31 and win95 on DOSBox-X, winnt40 and win2000 on QEMU,
    # delphi1 on Wine) plus the umbrella 'retro'. No operating system can be installed here (the media is
    # yours), so the slow checks prove the engines and the helper's own pieces.
    check "QEMU (qemu-system-i386, qemu-img) and its GTK window module" 'qemu-system-i386 --version | head -n 1 && qemu-img --version | head -n 1 && dpkg_has qemu-system-gui'
    hint  "rerun dev-setup with install-retro (v92 adds qemu-system-x86, qemu-system-gui, qemu-utils)"
    check "mtools and mkfs.fat (the exchange disk)"         'command -v mcopy && command -v mkfs.fat'
    check "the retro helper and its commands (win95, winnt40, win2000, delphi1, delphi, retro)" 'h=~/.local/lib/dev-retro/dev-retro; [ -x "$h" ] || { echo "no $h"; exit 1; }; bash -n "$h" || exit 1; for c in win31 win95 winnt40 win2000 delphi1 delphi retro; do grep -q "dev-retro/dev-retro\" $c " ~/.local/bin/$c 2> /dev/null || { echo "~/.local/bin/$c is not the v93 wrapper"; exit 1; }; done; grep -q "^delphi_n_cmd()" "$h" || { echo "the helper is older than v93"; exit 1; }; echo all seven'
    hint  "rerun dev-setup with install-retro: v93 writes the helper and the seven wrappers ('delphi' is new)"
    check "workspaces ~/win95, ~/winnt40, ~/win2000 (install/, and config for the QEMU two)" 'for g in win95 winnt40 win2000; do [ -d ~/$g/install ] || { echo "no ~/$g/install"; exit 1; }; done; for g in winnt40 win2000; do [ -f ~/$g/config ] || { echo "no ~/$g/config"; exit 1; }; bash -n ~/$g/config || exit 1; done; echo ok'
    # v93: program CDs per guest, the Delphi 3-7 media folders, bsdtar for a Delphi CD's .iso
    check "app-CD folders ~/<guest>/install/apps and ~/delphi/install/{3,4,5,6,7}" 'm=""; for g in win31 win95 winnt40 win2000; do [ -d ~/$g/install/apps ] || m="$m ~/$g/install/apps"; done; for n in 3 4 5 6 7; do [ -d ~/delphi/install/$n ] || m="$m ~/delphi/install/$n"; done; [ -z "$m" ] || { echo "missing:$m"; exit 1; }; echo ok'
    hint  "rerun dev-setup with install-retro (v93 creates them)"
    warn  "bsdtar (libarchive-tools): 'delphi N setup' unpacks a CD's .iso" 'command -v bsdtar && bsdtar --version | head -n 1'
    hint  "rerun dev-setup with install-retro; without it, copy the Delphi CD's files (not the .iso) into ~/delphi/install/N"
    check "retro sizes: RETRO_EXCHANGE_MB and RETRO_WIN95_DISK_MB are valid" '~/.local/lib/dev-retro/dev-retro retro sizes'
    hint  "a size in ~/.config/dev-init/secrets.env is out of range: RETRO_EXCHANGE_MB 64-2047, RETRO_WIN95_DISK_MB 512-8192"
    info  "retro disk sizes" "$(~/.local/lib/dev-retro/dev-retro retro sizes 2> /dev/null | grep -E '^(Exchange|Windows 95)' | sed 's/ (D: in win95, winnt40, win2000)//; s/, for a disk created from now on//' | paste -sd ';' | sed 's/;/; /')"
    for G in win31 win95 winnt40 win2000; do
        _apps=$(find ~/"$G"/install/apps -maxdepth 1 -type f -iname '*.iso' 2> /dev/null | wc -l)
        [ "$_apps" -gt 0 ] && info "app CDs for $G" "$_apps in ~/$G/install/apps; F: at the next start: $(cd /tmp && HOME="$HOME" ~/.local/lib/dev-retro/dev-retro "$G" cd list 2> /dev/null | sed -n 's/^  \* \([^ ]*\).*/\1/p' | head -n 1)"
    done
    warn  "launcher icons for the five guests"            'm=""; for g in win31 win95 winnt40 win2000; do [ -f ~/.local/share/applications/dev-retro-$g.desktop ] || m="$m $g"; done; [ -f ~/.local/share/applications/dev-retro-delphi1.desktop ] || grep -rqs "/.local/bin/delphi1" ~/.local/share/applications/wine || m="$m delphi1"; [ -z "$m" ] || { echo "missing:$m"; exit 1; }; echo all five'
    hint  "'<cmd> launcher' writes one again (delphi1's also points Delphi's own Wine entries at delphi1)"
    if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        info  "QEMU acceleration" "KVM: NT 4.0 and 2000 run at close to native speed here"
    elif [ -c /dev/kvm ]; then
        info  "QEMU acceleration" "/dev/kvm is here but not usable yet (kvm group: shut Linux down and reopen it); software emulation until then"
    else
        info  "QEMU acceleration" "no /dev/kvm on this Chromebook: NT 4.0 and 2000 run in software emulation (slow)"
    fi
    for G in win31 win95 winnt40 win2000 delphi1; do
        info  "retro guest $G" "$(~/.local/lib/dev-retro/dev-retro "$G" status 2> /dev/null | head -n 1 | sed 's/^[^ ]* *//; s/ *$//; s/   */, /g')"
    done
    slow  "QEMU starts a blank disk headless (accelerator, QMP answers)" 'cd "$WORK" || exit 1; qemu-img create -q -f qcow2 blank.qcow2 64M || exit 1
        if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then acc=kvm; else acc=tcg; fi
        qemu-system-i386 -accel $acc -machine pc -cpu pentium3 -m 32 -display none -drive file=blank.qcow2,format=qcow2,if=ide -nic none -qmp unix:qmp.sock,server=on,wait=off > qemu.log 2>&1 & q=$!
        for i in $(seq 1 30); do [ -S qmp.sock ] && break; sleep 0.5; done
        st=$(python3 -c "
import json, socket
s = socket.socket(socket.AF_UNIX); s.settimeout(10); s.connect(\"qmp.sock\"); f = s.makefile(\"rw\"); f.readline()
for c in ({\"execute\": \"qmp_capabilities\"}, {\"execute\": \"query-status\"}):
    f.write(json.dumps(c) + \"\n\"); f.flush(); r = json.loads(f.readline())
print(r[\"return\"][\"status\"])
f.write(json.dumps({\"execute\": \"quit\"}) + \"\n\"); f.flush()" 2>&1); wait $q; echo "accelerator $acc, guest status: $st"; cat qemu.log; [ "$st" = running ]' 120
    hint  "qemu.log above says why; with KVM, 'Permission denied' on /dev/kvm means the kvm group is not active yet (shut Linux down and reopen it)"
    slow  "the exchange disk takes a file in and gives it back (1 GB, mtools, through the helper)" 'rh="$WORK/retro-home"; mkdir -p "$rh/winnt40/install" && cd "$WORK" || exit 1; echo "exchange $$" > XFER.TXT
        H=~/.local/lib/dev-retro/dev-retro
        HOME="$rh" RETRO_EXCHANGE_MB=1024 "$H" winnt40 put XFER.TXT < /dev/null || exit 1
        HOME="$rh" "$H" winnt40 get XFER.TXT < /dev/null > /dev/null || exit 1
        cmp XFER.TXT "$rh/winnt40/from-guest/XFER.TXT" || exit 1
        HOME="$rh" "$H" winnt40 exchange info < /dev/null | head -n 1
        HOME="$rh" "$H" winnt40 exchange info < /dev/null | grep -q "1024 MB, FAT16, 2080 cylinders x 16 heads" || { echo "not the 1 GB layout"; exit 1; }
        HOME="$rh" RETRO_EXCHANGE_MB=512 "$H" winnt40 exchange recreate --yes < /dev/null > /dev/null || exit 1
        HOME="$rh" "$H" winnt40 exchange info < /dev/null | grep -q "512 MB" || { echo "recreate at 512 MB did not take"; exit 1; }
        [ -f "$rh/winnt40/from-guest/XFER.TXT" ] || { echo "recreate did not save the files first"; exit 1; }
        echo "round trip ok on 1 GB; recreated at 512 MB ($(du -h "$rh/winnt40/exchange.img" | cut -f1) on disk)"; rm -rf "$rh"' 180
    # v93: win95 end to end in a scratch home (never ~/win95): IMGMAKE at 512 MB, the exchange disk as D:,
    # a stand-in app CD as F: (DOS reads both from a stand-in WIN95\SETUP.BAT), then a snapshot saved, the
    # disk changed with mtools, and the snapshot restored.
    cat > "$WORK/w95_check.sh" << 'W95_EOF'
rh="$WORK/w95-home"; H=$HOME/.local/lib/dev-retro/dev-retro; mk=""
if command -v genisoimage > /dev/null; then mk="genisoimage -quiet -J -o"
elif command -v xorriso > /dev/null; then mk="xorriso -as mkisofs -quiet -J -o"
else echo "SKIPPED: no genisoimage or xorriso here to make the stand-in CDs"; exit 0; fi
export MTOOLS_SKIP_CHECK=1
mkdir -p "$rh/win95/install/apps" "$WORK/w95cd/WIN95" "$WORK/w95app"
printf '%s\r\n' 'dir d:\ > c:\report.txt' 'type f:\APPFILE.TXT >> c:\report.txt' 'exit' > "$WORK/w95cd/WIN95/SETUP.BAT"
echo "app cd ok" > "$WORK/w95app/APPFILE.TXT"
$mk "$rh/win95/install/win95.iso" "$WORK/w95cd" > /dev/null 2>&1 && $mk "$rh/win95/install/apps/app.iso" "$WORK/w95app" > /dev/null 2>&1 || { echo "could not make the stand-in CDs"; exit 1; }
echo "xfer $$" > "$WORK/XFER.TXT"
HOME="$rh" "$H" win95 put "$WORK/XFER.TXT" < /dev/null > /dev/null || exit 1
HOME="$rh" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy RETRO_WIN95_DISK_MB=512 RETRO_FORCE=1 timeout 240 "$H" win95 setup < /dev/null > "$WORK/w95.log" 2>&1
img="$rh/win95/hdd.img"
[ -f "$img" ] || { echo "no hdd.img:"; tail -n 5 "$WORK/w95.log"; tail -n 5 "$rh/.local/state/dev-retro/imgmake.log" 2> /dev/null; exit 1; }
off=$(python3 -c 'import struct, sys; m = open(sys.argv[1], "rb").read(512); print(struct.unpack("<I", m[454:458])[0] * 512)' "$img")
mcopy -n -i "$img@@$off" ::REPORT.TXT "$WORK/report.txt" 2> /dev/null || { echo "the stand-in SETUP.BAT did not run (no C:\REPORT.TXT):"; tail -n 5 "$WORK/w95.log"; exit 1; }
tr -d '\r' < "$WORK/report.txt" | grep -E 'XFER|app cd|EXCHANGE'
grep -q "app cd ok" "$WORK/report.txt" || { echo "F: was not the app CD"; exit 1; }
grep -q XFER "$WORK/report.txt" || { echo "D: (the exchange disk) was not readable"; exit 1; }
HOME="$rh" "$H" win95 snapshot save clean < /dev/null || exit 1
echo changed > "$WORK/C.TXT"; mcopy -i "$img@@$off" "$WORK/C.TXT" ::CHANGED.TXT || exit 1
HOME="$rh" "$H" win95 snapshot restore clean --yes < /dev/null || exit 1
if mdir -i "$img@@$off" ::CHANGED.TXT > /dev/null 2>&1; then echo "the restore did not undo the change"; exit 1; fi
echo "512 MB FAT32 disk made, D: and F: read from DOS, snapshot restored"
rm -rf "$rh"
W95_EOF
    slow  "win95: setup boots headless with an app CD as F:, D: readable, snapshot save/restore" 'bash w95_check.sh' 420
    hint  "w95_check.sh runs the helper in a scratch home; DOSBox-X's own log lines are in the test log above"

    mkdir -p "$WORK/retro" && cd "$WORK/retro" || true
    cat > bits.c << 'EOF'
#include <stdio.h>
/* The pointer size tells the targets apart: 16-bit small model 2, Win32 4, Win64 8 (int is 4 on both). */
int main(void) { printf("hello from %d-bit\n", (int)sizeof(void *) * 8); return 0; }
EOF
    cat > dosfile.c << 'EOF'
/* DOS program: write a file on the mounted drive so a headless DOSBox-X run can be checked. */
#include <stdio.h>
int main(void) { FILE *f = fopen("OUT.TXT", "w"); if (!f) return 1; fprintf(f, "dos %d-bit ok\n", (int)sizeof(int) * 8); fclose(f); return 0; }
EOF
    cat > win16.c << 'EOF'
/* A real Win16 GUI app (NE executable), the format Delphi 1 produces. It writes a file and exits, so
   Wine can run it headless and the test can read the result. */
#include <windows.h>
#include <stdio.h>
int PASCAL WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR lpCmd, int nShow)
{
    FILE *f = fopen("WIN16.TXT", "w");
    if (f) { fprintf(f, "win16 ok on windows %u.%u\n", (unsigned)LOBYTE(LOWORD(GetVersion())), (unsigned)HIBYTE(LOWORD(GetVersion()))); fclose(f); }
    return 0;
}
EOF

    # Build one program per target. Win16 needs h/win on INCLUDE and must not see h/nt.
    slow  "Open Watcom builds DOS 16, DOS/4GW 32, Win16, Win32; mingw builds Win64" 'cd "$WORK/retro" || exit 1
        wcl -q -bt=dos -ms -fe=dos16.exe dosfile.c > b.log 2>&1 || { echo "DOS16 build failed"; tail -3 b.log; exit 1; }
        wcl386 -q -bt=dos -l=dos4g -fe=dos32.exe dosfile.c >> b.log 2>&1 || { echo "DOS32 build failed"; tail -3 b.log; exit 1; }
        INCLUDE="$WATCOM/h:$WATCOM/h/win" wcl -q -bt=windows -zw -ml -l=windows -fe=win16.exe win16.c >> b.log 2>&1 || { echo "Win16 build failed"; tail -3 b.log; exit 1; }
        wcl386 -q -bt=nt -l=nt -fe=win32.exe bits.c >> b.log 2>&1 || { echo "Win32 build failed"; tail -3 b.log; exit 1; }
        x86_64-w64-mingw32-gcc -O2 -o win64.exe bits.c >> b.log 2>&1 || { echo "Win64 build failed"; tail -3 b.log; exit 1; }
        cp "$WATCOM/binw/dos4gw.exe" .
        file dos16.exe dos32.exe win16.exe win32.exe win64.exe | sed "s/, .*//"' 400
    hint  "the checks above say whether Open Watcom and mingw are installed"

    # --- DOS on DOSBox-X (headless) ---
    slow  "DOSBox-X runs the DOS 16-bit program (Wine cannot: it hands DOS off to DOSBox)" 'cd "$WORK/retro" || exit 1; [ -x dos16.exe ] || { echo "build first"; exit 1; }; rm -f OUT.TXT; SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 90 dosbox-x -silent -nogui -nomenu -c "mount c \"$WORK/retro\"" -c "c:" -c "dos16.exe" -c "exit" > dbx16.log 2>&1; cat OUT.TXT 2>/dev/null; grep -q "dos 16-bit ok" OUT.TXT' 180
    hint  "headless DOSBox-X uses SDL's dummy driver; if it hangs, a real ChromeOS terminal session runs it fine"
    slow  "DOSBox-X runs the DOS/4GW 32-bit program (dos4gw.exe extender)" 'cd "$WORK/retro" || exit 1; [ -x dos32.exe ] || { echo "build first"; exit 1; }; rm -f OUT.TXT; SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 90 dosbox-x -silent -nogui -nomenu -c "mount c \"$WORK/retro\"" -c "c:" -c "dos32.exe" -c "exit" > dbx32.log 2>&1; cat OUT.TXT 2>/dev/null; grep -q "dos 32-bit ok" OUT.TXT' 180

    # --- Windows on Wine ---
    slow  "Wine runs the Win16 program (the 16-bit path Delphi 1 uses)" 'cd "$WORK/retro" || exit 1; [ -x win16.exe ] || { echo "build first"; exit 1; }; rm -f WIN16.TXT; timeout 90 wine win16.exe > /dev/null 2>&1; cat WIN16.TXT 2>/dev/null; grep -q "win16 ok" WIN16.TXT' 180
    hint  "if this fails, Wine may be built without 16-bit support (the WoW64-only builds); Debian's wine32 has it. 16-bit code also needs vm.mmap_min_addr low enough, which Crostini allows"
    slow  "Wine runs the Win32 program"                    'cd "$WORK/retro" || exit 1; [ -x win32.exe ] || { echo "build first"; exit 1; }; timeout 90 wine win32.exe 2>/dev/null | tee /dev/stderr | grep -q "32-bit"' 180
    slow  "Wine runs the Win64 program"                    'cd "$WORK/retro" || exit 1; [ -x win64.exe ] || { echo "build first"; exit 1; }; timeout 90 wine win64.exe 2>/dev/null | tee /dev/stderr | grep -q "64-bit"' 180
    # The matrix line: confirm Wine turns the DOS program away, which is why DOSBox-X is here.
    info  "the matrix" "DOS 16/32 -> DOSBox-X; Win16/Win32/Win64 -> Wine (Wine refuses DOS: \"you need to install DOSBox\")"
    # v92: 'retro run' picks the engine from the header; the matrix's builds are the test cases.
    slow  "retro which classifies DOS 16, DOS/4GW, Win16, Win32 and Win64 builds" 'cd "$WORK/retro" || exit 1; [ -x win64.exe ] || { echo "build first"; exit 1; }; bad=0
        for p in dos16.exe:dos dos32.exe:dos win16.exe:win16 win32.exe:win32 win64.exe:win64; do o=$(retro which "${p%%:*}" 2>&1); echo "$o"; case "$o" in *": ${p##*:} -> "*) ;; *) bad=1 ;; esac; done; exit $bad' 60
    hint  "the classifier reads the MZ header and the NE/PE/LE signature at offset 0x3C ('retro which FILE' shows its reason)"
    # v92: delphi1, the Wine route for Delphi 1 (media is yours, so most of it is INFO until 'delphi1 setup' has run).
    D1P="$HOME/.local/share/wine/delphi1"
    if [ -n "$(find "$D1P/drive_c" -maxdepth 3 -ipath '*/delphi/bin/delphi.exe' 2> /dev/null | head -n 1)" ]; then
        check "delphi1: Delphi's native 16-bit OLE2 in C:\\WINDOWS\\SYSTEM (what the IDE starts on)" 'cd "$HOME/.local/share/wine/delphi1/drive_c/windows" || exit 1; sys=$(find . -maxdepth 1 -iname system -type d | head -n 1); m=""; for d in compobj ole2 ole2disp ole2nls storage typelib; do [ -n "$(find "$sys" -maxdepth 1 -iname "$d.dll")" ] || m="$m $d.dll"; done; [ -z "$m" ] || { echo "missing:$m"; exit 1; }; echo all six'
        hint  "Delphi's setup copies them; without them the IDE dies in compobj.dll16 (CoGetMalloc16). 'delphi1 setup' again"
        warn  "delphi1: the 32-bit prefix and its settings (black desktop, TEMP=C:\\TEMP, DELPHI.INI)" 'grep -q "#arch=win32" "$HOME/.local/share/wine/delphi1/system.reg" && grep -q "\"Background\"=\"0 0 0\"" "$HOME/.local/share/wine/delphi1/user.reg" && grep -qi "\"TEMP\"=.*C:\\\\\\\\TEMP" "$HOME/.local/share/wine/delphi1/user.reg" || exit 1; ini=$(find "$HOME/.local/share/wine/delphi1/drive_c/windows" -maxdepth 1 -iname delphi.ini | head -n 1); [ -n "$ini" ] && tr -d "\r" < "$ini" | grep -qix "integrateddebugging=0" || { echo "DELPHI.INI does not have IntegratedDebugging=0 (Run fails under Wine with it on)"; exit 1; }; echo ok'
        hint  "'delphi1 setup' applies them again"
    else
        info  "delphi1" "not set up yet: Delphi 1's SETUP.EXE in ~/win31/install/apps, then 'delphi1 setup' (the media is yours)"
    fi
    # v93: Delphi 3, 4, 5, 6 and 7 under Wine ('delphi N'): checked once set up; otherwise an INFO with its media.
    cat > "$WORK/delphi_check.sh" << 'DN_EOF'
# delphi_check.sh N ide|settings
P="$HOME/.local/share/wine/delphi$1"
case "$2" in
    ide)
        grep -q '#arch=win32' "$P/system.reg" || { echo "not a 32-bit prefix"; exit 1; }
        grep -m1 '"ProductName"=' "$P/system.reg"
        f=$(find "$P/drive_c" -maxdepth 6 -type f -iname delphi32.exe | head -n 1)
        [ -n "$f" ] || { echo "no delphi32.exe: 'delphi $1 setup' did not finish"; exit 1; }
        echo "$f" ;;
    settings)
        grep -q '"Background"="0 0 0"' "$P/user.reg" || { echo "no black desktop"; exit 1; }
        grep -qi '"TEMP"=.*C:\\\\TEMP' "$P/user.reg" || { echo "TEMP is not C:\\TEMP"; exit 1; }
        [ -f "$HOME/.local/share/applications/dev-retro-delphi$1.desktop" ] \
            || grep -rqs "/.local/bin/delphi $1" "$HOME/.local/share/applications/wine" || { echo "no launcher entry"; exit 1; }
        echo ok ;;
esac
DN_EOF
    for DN in 3 4 5 6 7; do
        if [ -d "$HOME/.local/share/wine/delphi$DN" ]; then
            check "delphi $DN: 32-bit prefix, Windows version, the IDE (delphi32.exe)" "bash delphi_check.sh $DN ide"
            hint  "'delphi $DN setup' again (its CD in ~/delphi/install/$DN)"
            warn  "delphi $DN: settings (black desktop, TEMP) and a launcher entry" "bash delphi_check.sh $DN settings"
            hint  "'delphi $DN setup' applies them again; 'delphi $DN launcher' rewrites the entries"
        elif [ -n "$(find ~/delphi/install/$DN -mindepth 1 -maxdepth 1 ! -name '.*' 2> /dev/null | head -n 1)" ]; then
            info  "delphi $DN" "media in ~/delphi/install/$DN, not set up yet: 'delphi $DN setup'"
        fi
    done
    timeout 60 wineserver -w 2> /dev/null || wineserver -k 2> /dev/null || true
    cd "$WORK" || true
fi

# =================================================================
# Personal agents (v86, install-hermes / install-openclaw). Quick checks: the commands, the safer
# defaults setup and init set (Hermes keeps to its own logins; OpenClaw's gateway on loopback with auth,
# feature statistics off), and whether init gave each a model (WARN). Slow checks need no key and no model:
# agent-check.sh starts mockllm.py, a stand-in OpenAI-compatible model, points a SCRATCH copy of each
# agent at it, has it answer one prompt, and for OpenClaw also runs the gateway on a free port, checks
# it listens on loopback only and refuses a wrong token. Your ~/.hermes and ~/.openclaw are not used
# (Hermes's scratch home is ~/.hermes/.dev-test-PID, removed afterwards). With AGENT_TEST_LIVE=1 each
# agent also answers one prompt with the model init configured (a fraction of a cent on a cloud key).
# =================================================================
if has install-hermes || has install-openclaw; then
    mkdir -p "$WORK/agents" && cd "$WORK/agents" || true
    cat > mockllm.py << 'MOCK_EOF'
#!/usr/bin/env python3
"""mockllm.py PORT [REPLY]: a tiny OpenAI-compatible server (standard library only) for offline agent
checks. /v1/models lists one model, 'mock-model'; /v1/chat/completions answers every request with
REPLY, streamed (SSE) or not, as the client asks; /api/tags answers like Ollama. Every request body is
appended to requests.log in the current directory, so a test can see what the agent sent."""
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18999
REPLY = sys.argv[2] if len(sys.argv) > 2 else "MOCK-OK: hello from the mock model"
MODEL = "mock-model"

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        p = self.path.split("?")[0].rstrip("/")
        if p.endswith("/models"):
            self._json({"object": "list", "data": [{"id": MODEL, "object": "model", "created": 0, "owned_by": "mock",
                        "context_length": 131072}]})
        elif p.endswith("/api/tags"):
            self._json({"models": [{"name": MODEL, "model": MODEL}]})
        elif p.endswith("/api/version"):
            self._json({"version": "0.0.0-mock"})
        else:
            self._json({"ok": True})
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b"{}"
        with open("requests.log", "ab") as f: f.write(raw + b"\n")
        try: req = json.loads(raw or b"{}")
        except ValueError: req = {}
        p = self.path.split("?")[0]
        if p.endswith("/api/show"):
            return self._json({"model_info": {"general.context_length": 131072}, "capabilities": ["completion", "tools"]})
        if not p.endswith("/chat/completions"):
            return self._json({"error": {"message": "not implemented: " + p}}, 404)
        cid, now = "chatcmpl-mock", int(time.time())
        usage = {"prompt_tokens": 10, "completion_tokens": 8, "total_tokens": 18}
        if req.get("stream"):
            self.send_response(200); self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache"); self.end_headers()
            def ev(d): self.wfile.write(b"data: " + json.dumps(d).encode() + b"\n\n"); self.wfile.flush()
            base = {"id": cid, "object": "chat.completion.chunk", "created": now, "model": MODEL}
            ev({**base, "choices": [{"index": 0, "delta": {"role": "assistant", "content": ""}, "finish_reason": None}]})
            ev({**base, "choices": [{"index": 0, "delta": {"content": REPLY}, "finish_reason": None}]})
            ev({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
            ev({**base, "choices": [], "usage": usage})
            self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()
        else:
            self._json({"id": cid, "object": "chat.completion", "created": now, "model": MODEL,
                        "choices": [{"index": 0, "message": {"role": "assistant", "content": REPLY}, "finish_reason": "stop"}],
                        "usage": usage})

ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
MOCK_EOF
    cat > agent-check.sh << 'CHECK_EOF'
# agent-check.sh STEP: the offline checks for the personal agents, run by dev-test from $WORK/agents.
# Each step starts mockllm.py (a stand-in OpenAI-compatible model) on a free port, points a SCRATCH
# copy of the agent at it and stops everything again; your own ~/.hermes and ~/.openclaw are not used.
set -u
cd "$(dirname "$0")" || exit 1
# Offline means offline: the scratch agents never see your API keys (dev-init exports them), so no
# fallback path can reach a real provider.
unset ANTHROPIC_API_KEY OPENROUTER_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY NOUS_API_KEY DEEPSEEK_API_KEY OLLAMA_API_KEY OLLAMA_REMOTE
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
PIDS=(); CLEAN=()
cleanup() {
    local p d
    for p in "${PIDS[@]}"; do kill -TERM -- "-$p" 2> /dev/null || kill -TERM "$p" 2> /dev/null; done
    sleep 1
    for p in "${PIDS[@]}"; do kill -KILL -- "-$p" 2> /dev/null || kill -KILL "$p" 2> /dev/null; done
    for d in "${CLEAN[@]}"; do rm -rf "$d"; done
}
trap cleanup EXIT
start_mock() {   # start_mock: sets MP (port); the model answers "MOCK-OK: ..."
    MP=$(free_port); rm -f requests.log
    setsid python3 mockllm.py "$MP" > mock.log 2>&1 < /dev/null & PIDS+=($!)
    local _i; for _i in $(seq 1 40); do curl -fsS "http://127.0.0.1:$MP/v1/models" > /dev/null 2>&1 && return 0; sleep 0.25; done
    echo "the stand-in model did not start"; cat mock.log; exit 1
}
sent() {   # what the agent sent: requests and tools offered
    python3 - << 'PY'
import json
reqs = [json.loads(l) for l in open("requests.log") if l.strip()]
chat = [r for r in reqs if r.get("messages")]
if chat:
    big = max(chat, key=lambda r: len(json.dumps(r)))
    size = sum(len(json.dumps(m.get("content", ""))) for m in big["messages"])
    tools = max(len(r.get("tools") or []) for r in chat)
    print(f"sent {len(chat)} model request(s); up to {tools} tools offered, {size} characters of messages in the largest")
PY
}
oc_onboard() {   # oc_onboard DIR: a scratch OpenClaw state dir, onboarded against the stand-in model
    export OPENCLAW_STATE_DIR="$1/state" OPENCLAW_CONFIG_PATH="$1/state/openclaw.json"
    mkdir -p "$1/state"
    openclaw telemetry off > /dev/null 2>&1
    openclaw onboard --non-interactive --accept-risk --mode local --flow manual \
        --auth-choice custom-api-key --custom-base-url "http://127.0.0.1:$MP/v1" --custom-model-id mock-model \
        --custom-api-key offline --custom-text-input --gateway-bind loopback --gateway-auth token \
        --skip-daemon --skip-channels --skip-skills --skip-search --skip-ui --skip-health --skip-hooks \
        --workspace "$1/workspace" --json > "$1/onboard.log" 2>&1 || { echo "onboarding failed:"; tail -n 5 "$1/onboard.log"; exit 1; }
}
case "${1:-}" in
    hermes-offline)
        start_mock
        # Under ~/.hermes on purpose: Hermes then shares the installed runtime instead of preparing
        # a second one for a home it has never seen.
        export HERMES_HOME="$HOME/.hermes/.dev-test-$$"; rm -rf "$HERMES_HOME"; mkdir -p "$HERMES_HOME"; CLEAN+=("$HERMES_HOME")
        # A new home would borrow Claude Code's and Codex's logins (single-use refresh tokens); not this one.
        hermes config set auth.adopt_external_logins false > /dev/null 2>&1 \
            && hermes config set model.provider custom > /dev/null 2>&1 \
            && hermes config set model.base_url "http://127.0.0.1:$MP/v1" > /dev/null 2>&1 \
            && hermes config set model.default mock-model > /dev/null 2>&1 || { echo "hermes config set failed"; exit 1; }
        out=$(hermes -z "Reply with a greeting" 2> hermes.err); rc=$?
        echo "$out" | tail -n 3; [ $rc -eq 0 ] || tail -n 5 hermes.err
        echo "$out" | grep -q "MOCK-OK" || exit 1
        sent ;;
    openclaw-offline)
        start_mock
        D="$PWD/oc-offline"; CLEAN+=("$D"); oc_onboard "$D"
        out=$(openclaw agent --local -m "Reply with a greeting" 2>&1)
        echo "$out" | grep "MOCK-OK" | tail -n 1
        echo "$out" | grep -q "MOCK-OK" || { echo "$out" | tail -n 5; exit 1; }
        sent ;;
    openclaw-gateway)
        start_mock
        D="$PWD/oc-gateway"; CLEAN+=("$D"); oc_onboard "$D"
        GP=$(free_port)
        setsid openclaw gateway run --port "$GP" > "$D/gateway.log" 2>&1 < /dev/null & PIDS+=($!)
        for _ in $(seq 1 90); do ss -ltnH "sport = :$GP" | grep -q . && break; sleep 1; done
        addrs=$(ss -ltnH "sport = :$GP" | awk '{print $4}')
        [ -n "$addrs" ] || { echo "the gateway did not start listening in 90 s:"; tail -n 5 "$D/gateway.log"; exit 1; }
        echo "listening on: $(echo $addrs)"
        if echo "$addrs" | grep -vqE '^(127\.0\.0\.1|\[::1\]):'; then echo "listening beyond this machine"; exit 1; fi
        h=$(openclaw gateway health --port "$GP" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
        echo "$h" | grep -m1 -E "^OK|rror"
        echo "$h" | grep -q "^OK" || exit 1
        # Auth is on: the same request with a wrong token must be turned away.
        if openclaw gateway health --port "$GP" --token not-the-token > "$D/wrong-token.log" 2>&1; then
            echo "the gateway answered a client with the wrong token"; exit 1
        fi
        echo "a wrong token is refused: $(sed 's/\x1b\[[0-9;]*m//g' "$D/wrong-token.log" | grep -m1 -o 'unauthorized[^(]*' || echo refused)" ;;
    *) echo "usage: agent-check.sh hermes-offline|openclaw-offline|openclaw-gateway"; exit 2 ;;
esac
CHECK_EOF
    cd "$WORK" || true
fi
if has install-hermes; then
    section "Personal agent: Hermes Agent (install-hermes)"
    check "hermes on PATH (~/.local/bin/hermes)"                'command -v hermes && hermes --version 2> /dev/null | head -n 2'
    hint  "rerun dev-setup with install-hermes; its installer log is ~/.hermes/logs/install.log"
    check "Hermes code is a git checkout (~/.hermes/hermes-agent)" 'o=$(git -C "$HOME/.hermes/hermes-agent" log -1 --format="%h %cs %s") && echo "${o:0:70}"'
    check "Hermes keeps to its own logins (not Claude Code's or Codex's)" 'v=$(hermes config get auth.adopt_external_logins 2> /dev/null); echo "auth.adopt_external_logins=$v"; [ "$v" = false ]'
    hint  "hermes config set auth.adopt_external_logins false (setup sets it): borrowed single-use refresh tokens log Claude Code out"
    warn  "Hermes has a model (dev-init configures it from secrets.env)" 'p=$(hermes config get model.provider 2> /dev/null); m=$(hermes config get model.default 2> /dev/null); echo "provider=${p:-unset} model=${m:-unset}"; [ -n "$p" ] && [ "$p" != auto ] && [ -n "$m" ]'
    hint  "fill in AGENT_ANTHROPIC_API_KEY or OPENROUTER_API_KEY (or OLLAMA_REMOTE + AGENT_MODEL) in secrets.env and rerun dev-init with install-hermes"
    slow  "Hermes offline: one prompt to a stand-in model (no key, no model)" 'bash "$WORK/agents/agent-check.sh" hermes-offline' 300
    hint  "'hermes doctor' names a missing piece; 64K+ context is required, the stand-in reports 128K"
    slowwarn "Hermes answers with your model (only with AGENT_TEST_LIVE=1)" 'if [ "${AGENT_TEST_LIVE:-0}" != 1 ]; then echo "SKIPPED: set AGENT_TEST_LIVE=1 to spend a fraction of a cent on this"; exit 0; fi; out=$(hermes -z "Reply with exactly the word PONG." 2>&1); echo "$out" | tail -n 3; echo "$out" | grep -q PONG' 300
fi
if has install-openclaw; then
    section "Personal agent: OpenClaw (install-openclaw)"
    check "Node satisfies OpenClaw (24.16+ or 26.1+)"            'node --version && node -e '"'"'const [a,b]=process.versions.node.split(".").map(Number); process.exit((a===24&&b>=16)||(a===26&&b>=1)||a>26?0:1)'"'"''
    hint  "rerun dev-setup with install-node install-openclaw (nvm moves to the current LTS)"
    check "openclaw on PATH (npm global on nvm's Node)"      'command -v openclaw && openclaw --version 2> /dev/null | head -n 1'
    hint  "rerun dev-setup with install-openclaw"
    warn  "OpenClaw is onboarded (dev-init runs it non-interactively)" 'f="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"; t=$(jq -r ".wizard.lastRunAt // empty" "$f" 2> /dev/null); m=$(jq -r ".agents.defaults.model.primary // empty" "$f" 2> /dev/null); echo "onboarded=${t:-never} model=${m:-unset}"; [ -n "$t" ] && [ -n "$m" ]'
    hint  "fill in AGENT_ANTHROPIC_API_KEY or OPENROUTER_API_KEY (or OLLAMA_REMOTE + AGENT_MODEL) in secrets.env and rerun dev-init with install-openclaw"
    check "OpenClaw gateway config: loopback only, auth on"      'f="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"; [ -f "$f" ] || { echo "no config yet: the defaults are loopback + token"; exit 0; }; b=$(jq -r ".gateway.bind // \"loopback\"" "$f"); a=$(jq -r ".gateway.auth.mode // \"token\"" "$f"); echo "bind=$b auth=$a"; [ "$b" = loopback ] && [ "$a" != none ]'
    hint  "openclaw config set gateway.bind loopback; for other devices prefer Tailscale Serve over a LAN bind (OpenClaw's own advice)"
    check "no OpenClaw gateway listening beyond this machine"   'f="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"; p=$(jq -r ".gateway.port // 18789" "$f" 2> /dev/null || echo 18789); l=$(ss -ltnH "sport = :${p:-18789}" | awk "{print \$4}"); echo "port ${p:-18789}: ${l:-not listening}"; ! echo "$l" | grep -vqE "^(127\.0\.0\.1|\[::1\]):|^$"'
    warn  "OpenClaw asks before running commands (tools.exec.mode)" 'f="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"; m=$(jq -r ".tools.exec.mode // empty" "$f" 2> /dev/null); s=$(jq -r ".tools.exec.security // empty" "$f" 2> /dev/null); a=$(jq -r ".tools.exec.ask // empty" "$f" 2> /dev/null); echo "mode=${m:-unset} security=${s:-unset} ask=${a:-unset} (unset = run anything without asking)"; case "$m" in ask|allowlist|deny|auto) exit 0 ;; esac; [ "$a" = on-miss ] || [ "$a" = always ] || [ "$s" = deny ] || [ "$s" = allowlist ]'
    hint  "dev-init sets it once OpenClaw is onboarded: openclaw config set tools.exec.mode ask (the Crostini user has passwordless sudo)"
    warn  "OpenClaw feature statistics recorded as off"          'f="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"; v=$(jq -r ".telemetry.enabled | tostring" "$f" 2> /dev/null); [ "$v" = null ] && v=""; echo "telemetry.enabled=${v:-not recorded (off by default; a wizard may ask)}"; [ "$v" = false ]'
    hint  "openclaw telemetry off (setup and dev-init run it); the daily update check is separate and stays on"
    warn  "openclaw security audit: nothing critical"           'out=$(openclaw security audit 2>&1 | sed "s/\x1b\[[0-9;]*m//g"); echo "$out" | grep -m1 "^Summary"; echo "$out" | grep -q "Summary: 0 critical"' 120
    slow  "OpenClaw offline: one agent turn against a stand-in model" 'bash "$WORK/agents/agent-check.sh" openclaw-offline' 300
    slow  "OpenClaw gateway: loopback only, health OK, wrong token refused" 'bash "$WORK/agents/agent-check.sh" openclaw-gateway' 300
    slowwarn "OpenClaw answers with your model (only with AGENT_TEST_LIVE=1)" 'if [ "${AGENT_TEST_LIVE:-0}" != 1 ]; then echo "SKIPPED: set AGENT_TEST_LIVE=1 to spend a fraction of a cent on this"; exit 0; fi; out=$(openclaw agent --local -m "Reply with exactly the word PONG." 2>&1); echo "$out" | grep -v "^\[" | tail -n 3; echo "$out" | grep -q PONG' 300
    info  "ClawHub skills" "none are installed by the bundle; read a skill before 'openclaw skills install' (malicious ones have been found there)"
fi

# =================================================================
# DISK USAGE (v77): what each stack actually takes on this machine. INFO lines only (never PASS,
# FAIL or WARN), plus a tab-separated copy in assets/logs/disk-<timestamp>.tsv to compare machines.
# Sizes are real disk usage (du, blocks), read with sudo so root-owned trees count. Lines are per
# stack; the totals at the end overlap them on purpose (apt and Homebrew hold several stacks each).
# 'nodisk' skips this section (du over the home directory takes a minute or two).
# =================================================================
if ! has nodisk; then
    section "Disk usage by stack (measured; INFO lines, not counted)"
    DISK_TSV="$ASSETS/logs/disk-$(date +%Y%m%d-%H%M%S).tsv"
    # Every Crostini container is called 'penguin', so label the file with MACHINE_LABEL when set.
    DISK_HOST=$(sed -n 's/^MACHINE_LABEL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' ~/.config/dev-init/secrets.env 2> /dev/null | tail -n 1)
    [ -n "$DISK_HOST" ] || DISK_HOST=$(hostname)
    printf 'machine\tstack\titem\tbytes\tmeasured\n' > "$DISK_TSV"
    CELLAR=/home/linuxbrew/.linuxbrew/Cellar
    DU=(du); sudo -n true 2> /dev/null && DU=(sudo -n du)
    _disk_bytes() {   # real disk usage of the paths that exist, each hard link counted once
        local p ex=()
        # v93: tested through sudo when du runs through it: /var/lib/docker is root-only (0710), so a plain
        # -e called every Docker volume "not present" (the devdb data volumes in v92's report).
        for p in "$@"; do
            if [ -e "$p" ] || { [ "${DU[0]}" = sudo ] && sudo -n test -e "$p" 2> /dev/null; }; then ex+=("$p"); fi
        done
        [ ${#ex[@]} -gt 0 ] || { echo 0; return; }
        timeout 300 "${DU[@]}" -sc -B1 "${ex[@]}" 2> /dev/null | tail -n 1 | cut -f1
    }
    _apt_bytes() {    # installed size of the apt packages matching the patterns (the packages named, not their dependencies)
        dpkg-query -W -f='${db:Status-Abbrev}\t${Installed-Size}\n' "$@" 2> /dev/null | awk -F'\t' '$1 ~ /^ii/ {s += $2} END {printf "%.0f\n", s * 1024}'
    }
    _disk_report() {  # _disk_report STACK ITEM BYTES WHAT-WAS-MEASURED
        local b=${3:-0}
        [[ "$b" =~ ^[0-9]+$ ]] || b=0
        printf '%s\t%s\t%s\t%s\t%s\n' "$DISK_HOST" "$1" "$2" "$b" "$4" >> "$DISK_TSV"
        if [ "$b" -eq 0 ]; then info "$1: $2" "not present"; else info "$1: $2" "$(numfmt --to=iec --suffix=B "$b")"; fi
    }
    dpaths() { local s=$1 i=$2; shift 2; _disk_report "$s" "$i" "$(_disk_bytes "$@")" "du: $*"; }
    dapt()   { local s=$1 i=$2; shift 2; _disk_report "$s" "$i" "$(_apt_bytes "$@")" "apt: $*"; }

    dpaths base "Google Chrome"                              /opt/google/chrome
    dapt   base "Docker Engine"                              docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    dpaths base "Homebrew formulae: gcc, ddev, gh, mkcert"   "$CELLAR/gcc" "$CELLAR/ddev" "$CELLAR/gh" "$CELLAR/mkcert"
    dpaths base "pipx and uv"                                "$HOME/.local/share/pipx/venvs/uv" "$HOME/.local/share/pipx/shared"
    has install-vscode   && dapt   editors "VS Code"         code
    has install-windsurf && dapt   editors "Windsurf"        windsurf
    has install-cursor   && dpaths editors "Cursor AppImage" "$HOME/.local/bin/cursor"
    has install-lazarus  && dapt   editors "Lazarus + Free Pascal" fpc-laz fpc-src lazarus-project
    has install-rust     && dpaths rust "rustup toolchains + cargo (incl. wasm and Android targets)" "$HOME/.rustup" "$HOME/.cargo"
    if has install-node; then
        dpaths node "Node (nvm) + global CLIs: Codex, Gemini, Angular, TanStack, Tauri, eas, Vercel, wrangler, MCP Inspector, OpenClaw" "$NVM_DIR"
        dpaths node "Claude Code (native)"                   "$HOME/.local/share/claude"
        dpaths node "aider + its Python 3.12 (uv)"           "$HOME/.local/share/uv/tools/aider-chat" "$HOME/.local/share/uv/python"
    fi
    has install-go       && dpaths go "Go toolchain + GOPATH" /usr/local/go "$HOME/go"
    has install-pwsh     && dpaths pwsh "PowerShell"         /opt/microsoft/powershell
    if has install-ruby; then
        dapt   ruby "Ruby (apt)"                             'ruby*' 'libruby*'
        dpaths ruby "gems: Jekyll, bundler"                  "$HOME/.gems"
    fi
    has install-cpp      && dapt   cpp "C/C++ tools (clang/LLVM, lldb, gdb, valgrind, cmake, meson...)" 'clang*' 'libclang*' 'llvm*' 'libllvm*' 'lldb*' 'liblldb*' gdb valgrind libc6-dbg 'cmake*' ninja-build meson ccache
    has install-asm      && dapt   asm "nasm, yasm"          nasm yasm
    if has install-dotnet; then
        dpaths dotnet ".NET SDK"                             /usr/lib/dotnet /usr/share/dotnet
        dpaths dotnet ".NET caches (~/.nuget, ~/.dotnet)"    "$HOME/.nuget" "$HOME/.dotnet"
    fi
    if has install-java || has install-mobile || has install-android-native || has install-oracle; then
        dpaths java "JDKs (/usr/lib/jvm)"                    /usr/lib/jvm
    fi
    if has install-java; then
        dpaths java "Gradle + Homebrew's openjdk"            "$CELLAR/gradle" "$CELLAR/openjdk"
        dapt   java "Maven (apt)"                            maven 'libmaven*'
        dpaths java "Maven and Gradle caches (~/.m2, ~/.gradle)" "$HOME/.m2" "$HOME/.gradle"
    fi
    has install-antigravity && dpaths antigravity "Antigravity SDK venv + GUI apps" "$HOME/.antigravity-env" /opt/antigravity /opt/antigravity-ide
    has install-media    && dpaths media "Flatpak: HandBrake, KDiff3 + runtimes" /var/lib/flatpak
    if has install-com; then
        dapt   com "Wine (64 + 32-bit), mingw-w64, libwine-dev" 'wine*' 'libwine*' 'gcc-mingw-w64*' 'g++-mingw-w64*' mingw-w64-common mingw-w64-tools 'libz-mingw-w64*' cabextract
        dpaths com "COM Wine prefix + winetricks" "$HOME/.local/share/wine/com" "$HOME/.local/bin/winetricks"
    fi
    has install-retro    && dpaths retro "Open Watcom v2 + ~/win31" /opt/watcom "$HOME/win31"
    has install-retro    && dapt   retro "DOSBox-X (apt)" dosbox-x
    # v92: QEMU and the new guests' workspaces (their disk images grow as Windows is installed)
    has install-retro    && dapt   retro "QEMU, mtools, dosfstools (apt)" qemu-system-x86 qemu-system-gui qemu-system-common qemu-system-data qemu-utils qemu-block-extra mtools dosfstools
    has install-retro    && dpaths retro "~/win95 (DOSBox-X: hdd.img, exchange disk, media)" "$HOME/win95"
    has install-retro    && dpaths retro "~/winnt40 (QEMU: disk, exchange disk, media)" "$HOME/winnt40"
    has install-retro    && dpaths retro "~/win2000 (QEMU: disk, exchange disk, media)" "$HOME/win2000"
    has install-retro    && dpaths retro "delphi1 Wine prefix" "$HOME/.local/share/wine/delphi1"
    # v93: Delphi 3, 4, 5, 6, 7 (each prefix, and the media with the unpacked CDs) and win95's snapshots
    if has install-retro; then
        for _n in 3 4 5 6 7; do
            [ -d "$HOME/.local/share/wine/delphi$_n" ] && dpaths retro "delphi $_n Wine prefix" "$HOME/.local/share/wine/delphi$_n"
        done
        [ -d "$HOME/delphi" ] && dpaths retro "~/delphi (Delphi 3-7 media and unpacked CDs)" "$HOME/delphi"
        [ -d "$HOME/win95/snapshots" ] && dpaths retro "~/win95/snapshots (also inside ~/win95 above)" "$HOME/win95/snapshots"
    fi
    has install-hermes   && dpaths hermes "Hermes Agent: code, runtime, data (~/.hermes)" "$HOME/.hermes"
    # OpenClaw's npm package (about 900 MB) sits inside $NVM_DIR, so the node row counts it; this is its state.
    has install-openclaw && dpaths openclaw "OpenClaw state: config, sessions, workspace (~/.openclaw)" "$HOME/.openclaw"
    if has install-ollama; then
        dpaths ollama "Ollama server bundle"                 /usr/local/lib/ollama /usr/local/bin/ollama
        dpaths ollama "Ollama models, all pulled ($(ollama list 2> /dev/null | tail -n +2 | grep -c .))" /usr/share/ollama/.ollama/models "$HOME/.ollama/models"
    fi
    has install-gemma    && dpaths gemma "~/.gemma-env (CPU torch, transformers)" "$HOME/.gemma-env"
    if has install-mobile || has install-tauri || has install-rn || has install-flutter || has install-android-native; then
        _sdk=$(_disk_bytes "$HOME/.android/sdk"); _ndk=$(_disk_bytes "$HOME/.android/sdk/ndk")
        _disk_report mobile "Android SDK without the NDK" "$(( ${_sdk:-0} - ${_ndk:-0} ))" "du: ~/.android/sdk minus ndk"
        _disk_report mobile "Android NDK"                "$_ndk" "du: ~/.android/sdk/ndk"
    fi
    { has install-mobile || has install-flutter; } && dpaths mobile "Flutter + pub cache" "$HOME/.flutter" "$HOME/.pub-cache"
    if has install-android-native; then
        dpaths android "Android Studio"                      /opt/android-studio
        dpaths android "Android Studio config + caches"      "$HOME/.config/Google" "$HOME/.cache/Google" "$HOME/.local/share/Google"
        dpaths android "Kotlin (Homebrew)"                   "$CELLAR/kotlin"
    fi
    has install-godot    && dpaths godot "Godot editors (+ export templates)" "$HOME/.local/opt/godot" "$HOME/.local/share/godot"
    has install-db       && dapt   db "ODBC drivers + client libs (MSSQL, MDB, Paradox, pq, MariaDB, SQLite)" msodbcsql18 unixodbc 'unixodbc*' odbc-mdbtools pxlib1 pxlib-dev libpq-dev libmariadb-dev libsqlite3-dev
    has install-db       && dapt   db "Firebird 4 (client, tools, embedded engine)" libfbclient2 firebird-dev firebird-utils 'firebird4.0-*'
    has install-interbase && dpaths db "InterBase (/opt/interbase)" /opt/interbase
    # v82: the database servers. An image's size is what 'docker image inspect' reports (its layers, some
    # of which images can share); a data volume is measured with du.
    for _e in mssql oracle; do
        has "install-$_e" || continue
        _img=$(docker inspect -f '{{.Config.Image}}' "devdb-$_e" 2> /dev/null)
        _disk_report db-server "$_e image (${_img:-no container})" "$( [ -n "$_img" ] && docker image inspect -f '{{.Size}}' "$_img" 2> /dev/null)" "docker image inspect: ${_img:-none}"
        _lbl="$_e data volume (devdb-$_e-data)"
        # v83 review: on the full image devdb-oracle-data is the Lite database left behind by the move
        if [ "$_e" = oracle ] && [ "$(docker inspect -f '{{index .Config.Labels "dev-setup.oracle-variant"}}' devdb-oracle 2> /dev/null)" = full ]; then
            _lbl="oracle Lite data volume, unused since the move to full (devdb-oracle-data)"
        fi
        dpaths db-server "$_lbl"  "/var/lib/docker/volumes/devdb-$_e-data"
    done
    # v83: the full image's own volume, and a Lite image left behind by the move to full
    if has install-oracle; then
        if docker volume inspect devdb-oracle-full-data > /dev/null 2>&1; then
            dpaths db-server "oracle full-image data volume (devdb-oracle-full-data)" /var/lib/docker/volumes/devdb-oracle-full-data
        fi
        _img=$(docker inspect -f '{{.Config.Image}}' devdb-oracle 2> /dev/null)
        _lite=container-registry.oracle.com/database/free:latest-lite
        if [ -n "$_img" ] && [ "$_img" != "$_lite" ] && docker image inspect "$_lite" > /dev/null 2>&1; then
            _disk_report db-server "oracle Lite image, unused since the move to full" "$(docker image inspect -f '{{.Size}}' "$_lite" 2> /dev/null)" "docker rmi $_lite"
        fi
    fi
    has install-mssql    && dpaths db-server "Go sqlcmd"    "$HOME/.local/bin/sqlcmd"
    has install-oracle   && dpaths db-server "SQLcl + Instant Client (/opt/oracle)" /opt/oracle
    # v83: LDAP (install-ldap / install-ldap-full)
    if has install-ldap; then
        _img=$(docker inspect -f '{{.Config.Image}}' devldap-lldap 2> /dev/null)
        _disk_report ldap "lldap image (${_img:-no container})" "$( [ -n "$_img" ] && docker image inspect -f '{{.Size}}' "$_img" 2> /dev/null)" "docker image inspect: ${_img:-none}"
        dpaths ldap "lldap data volume (devldap-lldap-data)" /var/lib/docker/volumes/devldap-lldap-data
        if has install-ldap-full; then
            dapt   ldap "OpenLDAP (slapd, ldap-utils)" slapd ldap-utils 'libldap*'
            dpaths ldap "OpenLDAP database (/var/lib/ldap)" /var/lib/ldap
        fi
    fi
    # v89: the shared services (install-cache, install-search, install-elasticsearch). Image size from
    # 'docker image inspect' (layers images share are counted in each), volume with du.
    for _s in redis memcached solr opensearch elasticsearch meilisearch typesense qdrant milvus mongodb atlas-local; do
        if [ "$_s" = atlas-local ]; then has install-mongodb-atlas-local || continue; else has "install-$_s" || continue; fi
        _img=$(docker inspect -f '{{.Config.Image}}' "devsvc-$_s" 2> /dev/null)
        _disk_report services "$_s image (${_img:-no container})" "$( [ -n "$_img" ] && docker image inspect -f '{{.Size}}' "$_img" 2> /dev/null)" "docker image inspect: ${_img:-none}"
        case "$_s" in memcached|selenium) ;; *) dpaths services "$_s data volume (devsvc-$_s-data)" "/var/lib/docker/volumes/devsvc-$_s-data" ;; esac
    done
    has install-redis    && dapt   services "redis-tools (redis-cli, redis-benchmark)" redis-tools
    has install-redis    && dapt   services "Redis Insight desktop app" 'redisinsight*'
    has install-vector   && dpaths services "sqlite-vec (~/.local/lib/sqlite-vec)" "$HOME/.local/lib/sqlite-vec"
    has install-mongodb  && dapt   services "mongosh, Database Tools, Compass" mongodb-mongosh mongodb-database-tools mongodb-compass
    has install-mongodb  && dpaths services "mongodb config volume (devsvc-mongodb-config)" /var/lib/docker/volumes/devsvc-mongodb-config
    has install-mongodb-atlas-local && dapt services "Atlas CLI" mongodb-atlas-cli
    has install-mongodb-atlas-local && dpaths services "atlas-local config volume (devsvc-atlas-local-config)" /var/lib/docker/volumes/devsvc-atlas-local-config
    if has install-db-extra; then
        dapt   db "extra ODBC drivers (SQLite, PostgreSQL, MariaDB)" libsqliteodbc odbc-postgresql odbc-mariadb
        dpaths db "DuckDB ODBC driver"                       /opt/duckdb-odbc
    fi
    has install-lakehouse && dpaths lakehouse "DuckDB CLI, dbt Fusion, ~/.lakehouse-env (incl. deltalake), ~/lakehouse" "$HOME/.lakehouse-env" "$HOME/.local/bin/duckdb" "$HOME/.local/bin/dbt" "$HOME/.duckdb" "$HOME/lakehouse"
    has install-agentic  && dpaths agentic "Temporal CLI, ~/.agentic-env, ~/agentic" "$CELLAR/temporal" "$HOME/.agentic-env" "$HOME/agentic"
    has install-agentic  && dpaths agentic "fastmcp (uv tool fastmcp-slim + fastmcp)" "$HOME/.local/share/uv/tools/fastmcp-slim"
    has install-cloudflared && dapt cloud "cloudflared"      cloudflared
    has install-aws      && dpaths cloud "AWS CLI (Homebrew)"  "$CELLAR/awscli" "$HOME/.aws"
    has install-azure    && dpaths cloud "Azure CLI (Homebrew) + ~/.azure (Bicep)" "$CELLAR/azure-cli" "$HOME/.azure"
    has install-gcp      && dpaths cloud "Google Cloud CLI"    /usr/lib/google-cloud-sdk "$HOME/.config/gcloud"
    has install-iac      && dpaths iac "Terraform, tflint, provider cache" "$CELLAR/terraform" /usr/local/bin/tflint "$HOME/.terraform.d"
    { has install-ansible-full || has install-ansible-core; } && dpaths iac "Ansible venv + collections" "$HOME/.local/share/pipx/venvs/ansible-core" "$HOME/.ansible"
    has install-web      && dapt   web "Composer + PHP incl. base php-cli (Angular CLI is in the Node line)" composer 'php8*'
    has install-k8s      && dpaths k8s "kubectl, helm, kind, k9s" "$CELLAR/kubernetes-cli" "$CELLAR/helm" "$CELLAR/kind" "$CELLAR/k9s"
    has install-symfony  && dapt   symfony "Symfony CLI (.deb)" symfony-cli
    has install-laravel  && dpaths laravel "Laravel installer (Composer global) + Composer's package cache" "$HOME/.config/composer" "$HOME/.cache/composer"
    if has install-drupal; then
        dpaths drupal "Terminus, acli, Upsun + plugins"      "$HOME/.local/bin/terminus" "$HOME/.local/bin/acli" "$HOME/.local/bin/upsun" "$HOME/.terminus" "$HOME/.acquia" "$HOME/.upsun-cli"
        dapt   drupal "rsync, MariaDB client"                rsync 'mariadb-client*'
    fi
    # v90: Apollo's three binaries and Rover's plugins; the drupal-graphql demo's two Umami sites once they
    # exist (the DDEV one keeps its database in a Docker volume).
    has install-graphql  && dpaths graphql "Rover, Router v2, Apollo MCP Server + Rover's plugins (~/.rover)" "$HOME/.local/bin/rover" "$HOME/.local/bin/router" "$HOME/.local/bin/apollo-mcp-server" "$HOME/.rover"
    [ -d "$HOME/dev-demo/drupal/drupal-graphql/local" ] && dpaths graphql "dev-demo drupal-graphql, local site (code + SQLite)" "$HOME/dev-demo/drupal/drupal-graphql/local"
    # v91: the test tools. The Grid's image is in the services lines above.
    has install-playwright && dpaths testing "Playwright browsers (~/.cache/ms-playwright)" "$HOME/.cache/ms-playwright"
    has install-selenium   && dpaths testing "Selenium Manager's drivers (~/.cache/selenium)" "$HOME/.cache/selenium"
    has install-robot      && dpaths testing "Robot Framework tool venv + the Browser library's Node side" "$HOME/.local/share/uv/tools/robotframework"
    has install-cypress    && dpaths testing "Cypress binaries (~/.cache/Cypress, one per version)" "$HOME/.cache/Cypress"
    has install-cypress    && dapt   testing "Cypress's system libraries (Xvfb and friends)" xvfb xauth libgbm-dev libnotify-dev libxss1 libxtst6
    has install-puppet     && dpaths config-mgmt "OpenVox (Puppet) + OpenBolt (/opt/puppetlabs)" /opt/puppetlabs
    has install-chef       && dpaths config-mgmt "Cinc Workstation (/opt/cinc-workstation)" /opt/cinc-workstation "$HOME/.kitchen"
    [ -d "$HOME/dev-demo/iac/cm-bakeoff" ] && dpaths config-mgmt "dev-demo cm-bakeoff (the three configurations)" "$HOME/dev-demo/iac/cm-bakeoff"
    has install-gitlab     && dpaths gitlab "glab (Homebrew) + gitlab-ci-local (npm) + its caches" "$CELLAR/glab" "$(npm root -g 2> /dev/null)/gitlab-ci-local" "$HOME/.gitlab-ci-local"
    has install-gitlab-runner && dapt gitlab "GitLab Runner (+ its helper images)" gitlab-runner gitlab-runner-helper-images
    has install-vue        && dpaths vue "create-vue / create-nuxt in npx's cache + Nuxt templates" "$HOME/.cache/giget"
    [ -d "$HOME/dev-demo/vue/vue-links" ] && dpaths vue "dev-demo vue-links (node_modules, dist)" "$HOME/dev-demo/vue/vue-links"
    [ -d "$HOME/dev-demo/drupal/drupal-nuxt" ] && dpaths vue "dev-demo drupal-nuxt (Drupal on SQLite + the Nuxt app)" "$HOME/dev-demo/drupal/drupal-nuxt"
    [ -d "$HOME/dev-demo/gitlab/ci-local" ] && dpaths gitlab "dev-demo gitlab ci-local (the pipelines' projects)" "$HOME/dev-demo/gitlab/ci-local"
    [ -d "$HOME/dev-demo/testing/e2e-bakeoff" ] && dpaths testing "dev-demo e2e-bakeoff (node_modules, vendor, venvs)" "$HOME/dev-demo/testing/e2e-bakeoff"
    [ -d "$HOME/dev-demo/drupal/drupal-behat" ] && dpaths testing "dev-demo drupal-behat (code; its database is in DDEV's volume)" "$HOME/dev-demo/drupal/drupal-behat"
    [ -d "$HOME/dev-demo/drupal/drupal-graphql/ddev" ] && dpaths graphql "dev-demo drupal-graphql, DDEV site (code + MariaDB volume)" "$HOME/dev-demo/drupal/drupal-graphql/ddev" /var/lib/docker/volumes/devdemo-drupal-graphql-mariadb

    # Totals: these overlap the lines above (apt and Homebrew each hold several stacks).
    dapt   total "all apt packages (system + every apt stack)" '*'
    dpaths total "Homebrew, every formula"                  /home/linuxbrew/.linuxbrew
    if [ -d "$CELLAR" ]; then
        while read -r b f; do
            _disk_report total "  Homebrew formula: ${f##*/}" "$b" "du: $f"
        done < <(timeout 300 "${DU[@]}" -s -B1 "$CELLAR"/* 2> /dev/null | sort -rn | head -n 8)
    fi
    dpaths total "Docker data: images, containers, volumes" /var/lib/docker
    dpaths total "~/.cache (uv, pip, puppeteer, dev-test...)" "$HOME/.cache"
    dpaths total "npm and pnpm stores"                      "$HOME/.npm" "$HOME/.local/share/pnpm"
    dpaths total "~/dev-demo"                               "$HOME/dev-demo"
    dpaths total "home directory, everything in it"         "$HOME"
    read -r _dsize _dused _davail < <(df -B1 --output=size,used,avail / | tail -n 1)
    _disk_report total "Linux disk used (of $(numfmt --to=iec --suffix=B "${_dsize:-0}"), $(numfmt --to=iec --suffix=B "${_davail:-0}") free)" "${_dused:-0}" "df /"
    echo "      Disk report saved to $DISK_TSV"
fi

# =================================================================
# SUMMARY
# =================================================================
echo
echo "================================================================="
echo "Test Version 93 complete: ${GRN}PASS $PASS${RST}   ${RED}FAIL $FAIL${RST}   ${YEL}WARN $WARN${RST}   SKIP $SKIP"
if [ ${#FAILED[@]} -gt 0 ]; then
    echo
    echo "Failed (must fix to get started):"
    printf '  - %s\n' "${FAILED[@]}"
fi
if [ ${#WARNED[@]} -gt 0 ]; then
    echo
    echo "Warnings (optional: logins, keys, extras):"
    printf '  - %s\n' "${WARNED[@]}"
    [ "$INIT_PENDING" != 0 ] && { echo; init_pending_note; }
fi
echo
echo "Full output of every check: $LOG"
[ -n "${DISK_TSV:-}" ] && echo "Disk usage by stack:        $DISK_TSV"
echo "================================================================="
{ echo; echo "SUMMARY: PASS $PASS FAIL $FAIL WARN $WARN SKIP $SKIP"; } >> "$LOG"

[ "$FAIL" -eq 0 ]
