#!/bin/bash
# dev-demo-chromebook - Version 93
# Version history: CHANGELOG.md, next to this script in the bundle
# (one section per script, newest version first).
#
# Same flags as dev-setup / dev-test / dev-init, with the SAME flag expansion. With no flags you get
# the demos for the base install (Docker). Run it after setup (and init, for the few demos that can
# use a login), from the bundle folder:
#
#   ./dev-demo-chromebook.sh install-all
#   ./dev-demo-chromebook.sh install-rust install-go install-godot
#
# Demo-only flags:
#   demo-refresh   update demos already downloaded: git clones are fast-forwarded (your edits
#                  are kept, or the pull is skipped); copied/generated demos are replaced, the old
#                  copy moved to ~/.cache/dev-demo/replaced/
#   demo-clean     remove the demo folders for the selected flags (asks once). Stop a demo's
#                  containers/clusters first with its launcher ('run-*.sh down' where offered).
#
# What it does, per demo:
#   - downloads it (shallow git clone, sparse checkout for monorepos, or a generated project)
#   - does only cheap preparation; big builds (raylib, Tauri, JetNews, petclinic...) happen the
#     first time you launch the demo, so an install-all pass takes minutes, not an hour
#   - writes ~/dev-demo/<stack>/run-<demo>.sh, which sets up PATH like a new terminal, starts
#     whatever the demo needs, opens the browser in ChromeOS when there is a page to show, and
#     stops its background pieces when you press Ctrl-C
#   - lists everything in ~/dev-demo/README.md and ~/dev-demo/dev-demo.code-workspace
#
# Unattended except for demo-clean's question. Apt is used only for small build dependencies
# (raylib's X11 headers, PHP's SQLite driver). Log: ./assets/logs/dev-demo-<timestamp>.log.
# Memory: these Chromebooks give Linux ~6.4 GB. Run one heavy demo at a time (Gemma, local models,
# the Drupal RAG site, Langfuse, SQL Server, Oracle, kind, Android builds); the launchers say when a
# demo is heavy.

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

# Deliberately NO 'set -e': one demo failing to download must not stop the others.

VERSION=92

# =================================================================
# FLAG EXPANSION (STACK SWITCHES)  -- copied verbatim from the installer
# =================================================================
FLAGS=" $* "

echo "Active Demo Flags: $FLAGS"

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

# v85: install-retro pulls in install-com (matches the installer); the com demo then appears too.
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

# shellcheck disable=SC2076  # literal match on purpose, as in the other three scripts
has() { [[ "$FLAGS" =~ " $1 " ]]; }

REFRESH=0; CLEAN=0
has demo-refresh && REFRESH=1
has demo-clean   && CLEAN=1

# =================================================================
# PATHS, LOG
# =================================================================
DEMO_ROOT="$HOME/dev-demo"
CACHE="$HOME/.cache/dev-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd || true)"
[ -n "$SCRIPT_DIR" ] || SCRIPT_DIR="$PWD"
ASSETS="$SCRIPT_DIR/assets"
mkdir -p "$ASSETS/logs" "$DEMO_ROOT/.index" "$CACHE"
LOG="$ASSETS/logs/dev-demo-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

if [ -t 1 ]; then GRN=$'\e[32m' RED=$'\e[31m' YEL=$'\e[33m' DIM=$'\e[2m' BLD=$'\e[1m' RST=$'\e[0m'; else GRN=; RED=; YEL=; DIM=; BLD=; RST=; fi

echo "dev-demo Version $VERSION: demos go to $DEMO_ROOT   (log: $LOG)"

# =================================================================
# ENVIRONMENT (same as dev-test: what a new terminal would have)
# =================================================================
# This block is also written to ~/dev-demo/.demo-env.sh, which every launcher sources, so a launcher
# works from any terminal (or a file manager) without 'source ~/.bashrc'.
write_demo_env() {
cat > "$DEMO_ROOT/.demo-env.sh" << 'ENVEOF'
# ~/dev-demo/.demo-env.sh - written by dev-demo-chromebook; rewritten on every run.
# Sourced by every run-*.sh launcher: PATH like a new terminal, plus small helpers.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.gems/bin:$HOME/.flutter/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
_demo_brew_after_system() {   # Homebrew goes AFTER the system directories, as setup v68+ writes it
    local p parts out=""
    IFS=: read -ra parts <<< "$PATH"
    for p in "${parts[@]}"; do
        case "$p" in /home/linuxbrew/.linuxbrew/bin|/home/linuxbrew/.linuxbrew/sbin|"") ;; *) out="${out:+$out:}$p" ;; esac
    done
    PATH="$out:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin"
}
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && _demo_brew_after_system
if [ -d "$HOME/.config/nvm" ]; then export NVM_DIR="$HOME/.config/nvm"; else export NVM_DIR="$HOME/.nvm"; fi
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" > /dev/null 2>&1
export GEM_HOME="$HOME/.gems"
export ANDROID_HOME="$HOME/.android/sdk"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/.dotnet/tools"
export JAVA_HOME="${JAVA_HOME:-$(grep -m1 '^export JAVA_HOME=' ~/.bashrc 2>/dev/null | cut -d'"' -f2)}"
export NDK_HOME="${NDK_HOME:-$(grep -m1 '^export NDK_HOME=' ~/.bashrc 2>/dev/null | cut -d'"' -f2)}"
export GEMMA_MODEL="${GEMMA_MODEL:-gemma4:e2b-it-qat}"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0 NG_CLI_ANALYTICS=false
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
# v80: Firebird's lock directory, when setup had to give you your own (the line a new terminal gets).
if [ -z "${FIREBIRD_LOCK:-}" ] && grep -q '^export FIREBIRD_LOCK=' "$HOME/.bashrc" 2> /dev/null; then
    eval "$(grep -m1 '^export FIREBIRD_LOCK=' "$HOME/.bashrc")"
fi
# v81: InterBase's client finds its message file through INTERBASE (setup's ~/.bashrc block exports it).
[ -d /opt/interbase ] && export INTERBASE="${INTERBASE:-/opt/interbase}"
# v87: Composer's global bin (install-laravel's laravel command), at the end of PATH like setup's block.
for _cb in "$HOME/.config/composer/vendor/bin" "$HOME/.composer/vendor/bin"; do
    [ -d "$_cb" ] && case ":$PATH:" in *":$_cb:"*) ;; *) export PATH="$PATH:$_cb" ;; esac
done; unset _cb
# v85: Open Watcom (install-retro), as setup's retro block has it: appended to PATH so its vi and wrc
# do not shadow the system ones. And the COM block's variables (install-com), read from ~/.bashrc.
if [ -d /opt/watcom ]; then
    export WATCOM=/opt/watcom
    export INCLUDE="${INCLUDE:-$WATCOM/h}" EDPATH="$WATCOM/eddat" WIPFC="$WATCOM/wipfc"
    case ":$PATH:" in *":$WATCOM/binl64:"*) ;; *) export PATH="$PATH:$WATCOM/binl64:$WATCOM/binl" ;; esac
fi
if [ -z "${DEV_COM_PREFIX:-}" ] && grep -q '^# >>> dev-setup com >>>$' "$HOME/.bashrc" 2> /dev/null; then
    eval "$(sed -n '/^# >>> dev-setup com >>>$/,/^# <<< dev-setup com <<</p' "$HOME/.bashrc" | grep '^export DEV_COM_')"
fi
# Keys that dev-init exported into ~/.bashrc are not visible to a non-interactive launcher; read the
# few that demos can use (all optional) straight from dev-init's secrets file. (The mssql and oracle
# commands read their passwords from that file themselves.)
if [ -r "$HOME/.config/dev-init/secrets.env" ]; then
    for _k in ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY OLLAMA_REMOTE INTERBASE_SYSDBA_PASSWORD; do
        [ -n "${!_k:-}" ] && continue
        _v=$(grep -E "^(export )?$_k=" "$HOME/.config/dev-init/secrets.env" | tail -1 | cut -d= -f2- | sed -E "s/^['\"]//;s/['\"]\$//")
        [ -n "$_v" ] && export "$_k=$_v"
    done
    unset _k _v
fi

DEMO_ROOT="$HOME/dev-demo"
DEMO_LOGS="$HOME/.cache/dev-demo/logs"; mkdir -p "$DEMO_LOGS"
DEMO_PIDS=(); DEMO_ON_EXIT=(); DEMO_CHOICE=""
if [ -t 1 ]; then _Y=$'\e[33m' _B=$'\e[1m' _D=$'\e[2m' _R=$'\e[0m'; else _Y=; _B=; _D=; _R=; fi

demo_note() { echo "${_Y}>>${_R} $*"; }
demo_step() { echo; echo "${_B}== $* ==${_R}"; }
# demo_need CMD FLAG: stop with a pointer to the setup flag when a tool is missing
demo_need() { command -v "$1" > /dev/null 2>&1 || { echo "This demo needs '$1': run dev-setup with $2 first (then open a new terminal)."; exit 1; }; }
# demo_open URL: open in the ChromeOS browser (Crostini's URL handler), else the Linux default browser
demo_open() {
    echo "  -> $1"
    if [ -x /opt/google/cros-containers/bin/garcon-url-handler ]; then
        /opt/google/cros-containers/bin/garcon-url-handler "$1" > /dev/null 2>&1 &
    elif command -v xdg-open > /dev/null 2>&1; then
        xdg-open "$1" > /dev/null 2>&1 &
    fi
}
# demo_wait_port PORT [SECONDS] [quiet]: wait until something listens on localhost:PORT
demo_wait_port() {
    local port=$1 secs=${2:-180} i
    [ "${3:-}" = quiet ] || printf 'Waiting for localhost:%s ' "$port"
    for ((i = 0; i < secs; i++)); do
        if (exec 3<> "/dev/tcp/127.0.0.1/$port") 2> /dev/null; then [ "${3:-}" = quiet ] || echo " up"; return 0; fi
        [ "${3:-}" = quiet ] || { [ $((i % 5)) -eq 0 ] && printf '.'; }
        sleep 1
    done
    [ "${3:-}" = quiet ] || echo " not up after ${secs}s"
    return 1
}
# demo_open_when_ready PORT URL [SECONDS]: open the page in the background once the port answers
demo_open_when_ready() {
    ( demo_wait_port "$1" "${3:-600}" quiet && sleep 1 && demo_open "$2" ) &
    DEMO_PIDS+=($!)
}
# demo_bg NAME CMD...: run in the background (own session, log in ~/.cache/dev-demo/logs), stopped on exit
demo_bg() {
    local name=$1; shift
    setsid "$@" > "$DEMO_LOGS/$name.log" 2>&1 < /dev/null &
    DEMO_PIDS+=($!)
    echo "  started $name in the background (log: $DEMO_LOGS/$name.log)"
}
demo_on_exit() { DEMO_ON_EXIT+=("$1"); }
demo_cleanup() {
    local p c
    for p in "${DEMO_PIDS[@]}"; do kill -TERM -- "-$p" 2> /dev/null || kill -TERM "$p" 2> /dev/null; done
    for c in "${DEMO_ON_EXIT[@]}"; do echo "cleanup: $c"; eval "$c" > /dev/null 2>&1; done
}
trap demo_cleanup EXIT
trap 'exit 130' INT TERM
# demo_menu "Title" ITEM...: numbered menu; the launcher's first argument picks an item directly
demo_menu() {
    local title=$1 i; shift
    [ $# -gt 0 ] || { echo "Nothing to choose from."; return 1; }
    if [ -n "${DEMO_ARG:-}" ]; then
        # v85: an item written "name: description" is picked by its name alone (run-hello-com.sh local64).
        for i in "$@"; do { [ "$i" = "$DEMO_ARG" ] || [ "${i%%:*}" = "$DEMO_ARG" ]; } && { DEMO_CHOICE=$i; DEMO_ARG=""; return 0; }; done
        echo "'$DEMO_ARG' is not one of the choices."; DEMO_ARG=""
    fi
    echo; echo "${_B}$title${_R}"
    local PS3="Number (Ctrl-D quits): "
    select DEMO_CHOICE in "$@"; do [ -n "$DEMO_CHOICE" ] && return 0; echo "Type one of the numbers."; done
    echo; return 1
}
demo_hold() { echo; read -rp "${1:-Press Enter to stop the demo} " _ || true; }
docker_ok() {
    demo_need docker "the base install (Docker)"
    docker info > /dev/null 2>&1 && return 0
    echo "Docker is installed but not reachable. Open a new terminal (docker group) or shut Linux down"
    echo "once (right-click the Terminal icon > Shut down Linux) and try again."
    exit 1
}
ENVEOF
}

# =================================================================
# DOWNLOADER HELPERS
# =================================================================
READY=(); SKIPPED=(); FAILED=(); NOTES=()
STACK=""; NAME=""; DESC=""; SRC=""; DIR=""; FRESH=0

# begin STACK NAME "DESCRIPTION" SOURCE: announce a demo and set DIR. In demo-clean mode it removes
# the demo instead and returns 1. A function's last demo uses 'begin ... || return 0'; any earlier
# one is an 'if begin ...; then ... fi' block, so demo-clean goes on to the next (v81).
begin() {
    STACK=$1; NAME=$2; DESC=$3; SRC=$4; DIR="$DEMO_ROOT/$STACK/$NAME"; FRESH=0
    echo; echo "${BLD}== $STACK/$NAME ==${RST}  ${DIM}$DESC${RST}"
    if [ "$CLEAN" = 1 ]; then
        if [ -e "$DIR" ] || [ -e "$DEMO_ROOT/$STACK/run-$NAME.sh" ]; then
            rm -rf "$DIR" "$DEMO_ROOT/$STACK/run-$NAME.sh" "$DEMO_ROOT/.index/$STACK--$NAME"
            rmdir "$DEMO_ROOT/$STACK" 2> /dev/null
            echo "  removed"
        else
            echo "  not present"
        fi
        return 1
    fi
    return 0
}
# need CMD FLAG: record a skip when a tool the demo needs is missing
need() {
    command -v "$1" > /dev/null 2>&1 && return 0
    echo "  ${YEL}skip${RST}: needs '$1' (dev-setup with $2)"
    SKIPPED+=("$STACK/$NAME: needs '$1' ($2)")
    return 1
}
fail() {
    echo "  ${RED}FAILED${RST}: $*"
    FAILED+=("$STACK/$NAME: $*")
    return 1
}
# stash_old: move an existing demo aside before a refresh replaces it
stash_old() {
    local to
    to="$CACHE/replaced/$STACK-$NAME-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$CACHE/replaced"
    mv "$DIR" "$to" && echo "  previous copy moved to $to"
}
# present: true when the demo is already there and should be kept (no demo-refresh)
present() {
    [ -e "$DIR" ] || return 1
    if [ "$REFRESH" = 1 ]; then stash_old; return 1; fi
    echo "  already downloaded (demo-refresh replaces it)"
    return 0
}
# fetch_repo URL [BRANCH]: shallow clone into DIR; with demo-refresh, fast-forward an existing clone
fetch_repo() {
    local url=$1 branch=${2:-}
    if [ -d "$DIR/.git" ]; then
        if [ "$REFRESH" = 1 ]; then
            echo "  updating the existing clone..."
            git -C "$DIR" pull -q --ff-only > /dev/null 2>&1 \
                || echo "  ${YEL}note${RST}: could not fast-forward (local changes?); kept as is"
        else
            echo "  already downloaded (demo-refresh updates it)"
        fi
        return 0
    fi
    [ -e "$DIR" ] && stash_old
    echo "  cloning $url${branch:+ (branch $branch)}..."
    if git clone -q --depth 1 ${branch:+--branch "$branch"} "$url" "$DIR"; then
        FRESH=1; return 0
    fi
    rm -rf "$DIR"
    fail "git clone $url failed"
}
# fetch_subdir URL SUBDIR [BRANCH]: sparse-clone a monorepo and copy one folder out (like gitpick),
# so the demo does not sit inside the monorepo's workspace (pnpm/npm would treat it as a member).
fetch_subdir() {
    local url=$1 sub=$2 branch=${3:-} tmp sha
    present && return 0
    echo "  fetching $sub from $url..."
    tmp=$(mktemp -d "$CACHE/sparse.XXXXXX")
    if git clone -q --depth 1 --filter=blob:none --sparse ${branch:+--branch "$branch"} "$url" "$tmp/r" \
        && git -C "$tmp/r" sparse-checkout set "$sub" \
        && [ -d "$tmp/r/$sub" ]; then
        sha=$(git -C "$tmp/r" rev-parse --short HEAD)
        mkdir -p "$(dirname "$DIR")"
        cp -a "$tmp/r/$sub" "$DIR"
        printf 'Copied from %s (%s) at commit %s on %s by dev-demo v%s\n' "$url" "$sub" "$sha" "$(date +%F)" "$VERSION" > "$DIR/.dev-demo-source"
        rm -rf "$tmp"; FRESH=1
        return 0
    fi
    rm -rf "$tmp"
    fail "could not fetch $sub from $url"
}
# fetch_file URL DEST: download one file (resumable), skip when present (unused since v78; kept for demos to come)
fetch_file() {
    local url=$1 dest=$2
    [ -s "$dest" ] && [ "$REFRESH" != 1 ] && return 0
    echo "  downloading $(basename "$dest")..."
    curl -fsSL --retry 3 --retry-delay 2 -C - -o "$dest.part" "$url" && mv "$dest.part" "$dest"
}
# gen_file PATH: write stdin to PATH unless it exists (demo-refresh rewrites it)
gen_file() {
    if [ -e "$1" ] && [ "$REFRESH" != 1 ]; then cat > /dev/null; return 0; fi
    mkdir -p "$(dirname "$1")"
    cat > "$1"
}
# apt_need PKG...: install small build dependencies a demo needs, only the missing ones
apt_need() {
    local p missing=()
    for p in "$@"; do dpkg -s "$p" > /dev/null 2>&1 || missing+=("$p"); done
    [ ${#missing[@]} -eq 0 ] && return 0
    echo "  installing build dependencies: ${missing[*]}"
    sudo apt-get install -y -qq "${missing[@]}" > /dev/null
}
# write_run: the launcher ~/dev-demo/<stack>/run-<name>.sh, body on stdin (runs inside DEMO_DIR)
write_run() {
    local f="$DEMO_ROOT/$STACK/run-$NAME.sh"
    mkdir -p "$DEMO_ROOT/$STACK"
    {
        echo '#!/bin/bash'
        echo "# $STACK/$NAME: $DESC"
        echo "# Source: $SRC"
        echo "# Written by dev-demo-chromebook-v$VERSION.sh and rewritten on every run: copy it before editing."
        echo 'source "$HOME/dev-demo/.demo-env.sh" || exit 1'
        echo "DEMO_DIR=\"\$HOME/dev-demo/$STACK/$NAME\""
        echo 'cd "$DEMO_DIR" 2> /dev/null || { echo "Missing $DEMO_DIR: rerun dev-demo with the matching flag."; exit 1; }'
        echo 'DEMO_ARG="${1:-}"'
        cat
    } > "$f"
    chmod +x "$f"
}
# done_demo: register the demo in the index that README.md is built from
done_demo() {
    printf '%s\t%s\t%s\n' "$DESC" "run-$NAME.sh" "$SRC" > "$DEMO_ROOT/.index/$STACK--$NAME"
    echo "  ${GRN}ready${RST}: ~/dev-demo/$STACK/run-$NAME.sh"
    READY+=("$STACK/$NAME")
}
note() { NOTES+=("$*"); }

# =================================================================
# DEMOS: base, languages
# =================================================================

demo_base() {
    begin base voting-app "Docker's 5-container voting app: vote on :8080, live results on :8081" \
        "https://github.com/dockersamples/example-voting-app" || return 0
    need docker "the base install" || return 0
    fetch_repo https://github.com/dockersamples/example-voting-app.git || return 0
    write_run << 'EOF'
docker_ok
# Prebuilt images: nothing to compile. Python vote app, Node results app, .NET worker, Redis, Postgres.
COMPOSE=(docker compose -f docker-compose.images.yml -p devdemo-voting)
demo_on_exit "docker compose -f '$DEMO_DIR/docker-compose.images.yml' -p devdemo-voting down"
"${COMPOSE[@]}" up -d || exit 1
# v92: results first, the vote page last, so it opens on top in a freshly laid-out window. The upstream
# vote page's "Processed by container ID" label can sit over the buttons until the window is resized.
demo_wait_port 8081 300 && demo_open http://localhost:8081
demo_wait_port 8080 300 && demo_open http://localhost:8080
demo_note "Vote in one tab and watch the other update. If a vote button won't click, resize the window (upstream CSS). Ctrl-C stops and removes the containers."
"${COMPOSE[@]}" logs -f --tail 3 worker
EOF
    done_demo
}

demo_rust() {
    begin rust ratatui "Ratatui terminal UIs: demo2 (tabs, charts, 'd' for destroy mode) and 30 more apps" \
        "https://github.com/ratatui/ratatui (branch 'latest')" || return 0
    need cargo install-rust || return 0
    fetch_repo https://github.com/ratatui/ratatui.git latest || return 0
    write_run << 'EOF'
demo_need cargo install-rust
APPS=(); for d in examples/apps/*/; do d=${d%/}; d=${d##*/}; [ "$d" = demo2 ] || APPS+=("$d"); done
demo_menu "Which Ratatui app? (demo2 is the flagship; try color-explorer, weather, mouse-drawing too)" demo2 "${APPS[@]}" || exit 0
demo_note "The first run compiles the workspace (a few minutes); later runs start in seconds. Quit with q or Esc."
cargo run -q -p "$DEMO_CHOICE"
EOF
    done_demo
}

demo_go() {
    begin go bubbletea "Bubble Tea: 60 small terminal apps (doom-fire, spinners, file picker, package manager...)" \
        "https://github.com/charmbracelet/bubbletea" || return 0
    need go install-go || return 0
    fetch_repo https://github.com/charmbracelet/bubbletea.git || return 0
    write_run << 'EOF'
demo_need go install-go
cd examples || exit 1
FEATURED=(doom-fire package-manager progress-animated spinners eyes splash file-picker list-fancy table chat)
mapfile -t REST < <(for d in */; do d=${d%/}; [[ " ${FEATURED[*]} " == *" $d "* ]] || echo "$d"; done)
while demo_menu "Which Bubble Tea example? (featured first; q or Ctrl-C quits most of them)" "${FEATURED[@]}" "${REST[@]}"; do
    go run "./$DEMO_CHOICE"
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

demo_cpp() {
    begin cpp raylib "raylib: ~200 small OpenGL games and effects in C, built with CMake + Ninja" \
        "https://github.com/raysan5/raylib" || return 0
    need cmake install-cpp || return 0
    need ninja install-cpp || return 0
    fetch_repo https://github.com/raysan5/raylib.git || return 0
    # GLFW (built into raylib) needs these X11/GL headers; libx11-dev is already in the base install.
    apt_need libxcursor-dev libxinerama-dev libxi-dev libxrandr-dev libgl1-mesa-dev \
        || fail "apt could not install raylib's X11 headers" || return 0
    write_run << 'EOF'
demo_need cmake install-cpp
if [ ! -x build/examples/core_basic_window ]; then
    demo_note "First run: building raylib and all its examples (5-10 minutes on an i3)."
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_EXAMPLES=ON -DPLATFORM=Desktop > /dev/null \
        && cmake --build build || exit 1
fi
cd build/examples || exit 1     # resources/ is copied here, so examples must run from this folder
mapfile -t CATS < <(find . -maxdepth 1 -type f -executable -printf '%f\n' | sed 's/_.*//' | sort -u)
while demo_menu "Category? (models/shaders show off the GPU path; Esc closes an example)" "${CATS[@]}"; do
    cat=$DEMO_CHOICE
    mapfile -t EX < <(find . -maxdepth 1 -type f -executable -name "${cat}_*" -printf '%f\n' | sort)
    while demo_menu "$cat example? (Ctrl-D goes back)" "${EX[@]}"; do "./$DEMO_CHOICE"; done
done
EOF
    done_demo
}

demo_asm() {
    begin asm x86-64-nasm "NASM x86-64 programs on raw Linux syscalls: hello, strings, stack, floats, C interop" \
        "https://github.com/0xAX/asm" || return 0
    need nasm install-asm || return 0
    fetch_repo https://github.com/0xAX/asm.git || return 0
    write_run << 'EOF'
demo_need nasm install-asm
cd examples || exit 1
mapfile -t EX < <(find . -name Makefile -printf '%h\n' | sed 's|^\./||' | sort)
while demo_menu "Which example? (each folder has a README explaining the code)" "${EX[@]}"; do
    ( cd "$DEMO_CHOICE" || exit
      [ -f README.md ] && head -n 15 README.md && echo "..."
      make -s || exit
      bin=$(find . -maxdepth 1 -type f -executable ! -name '*.sh' -newer Makefile -printf '%f\n' | head -n 1)
      [ -n "$bin" ] || bin=$(find . -maxdepth 1 -type f -executable -printf '%f\n' | head -n 1)
      demo_step "./$bin"; "./$bin"; echo "(exit status $?)"
      demo_note "Look inside: objdump -d -M intel $DEMO_DIR/examples/$DEMO_CHOICE/$bin | less" )
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

demo_asm_arm() {
    begin asm-arm aarch64-hello "AArch64 assembly and C, cross-built and run under qemu-user on this x86-64 machine" \
        "generated by dev-demo" || return 0
    need aarch64-linux-gnu-as install-asm-arm || return 0
    need qemu-aarch64 install-asm-arm || return 0
    gen_file "$DIR/hello.s" << 'EOF'
// hello.s - AArch64 Linux: write(1, msg, len); exit(0). Syscall number in x8, args in x0-x2.
    .global _start
    .text
_start:
    mov     x0, #1              // fd 1 = stdout
    ldr     x1, =msg            // buffer
    mov     x2, #len            // length
    mov     x8, #64             // __NR_write
    svc     #0
    mov     x0, #0              // status 0
    mov     x8, #93             // __NR_exit
    svc     #0
    .data
msg:
    .ascii  "Hello from AArch64 assembly, running under qemu-aarch64 on an x86-64 Chromebook!\n"
    len = . - msg
EOF
    gen_file "$DIR/sysinfo.c" << 'EOF'
#include <stdio.h>
#include <sys/utsname.h>
int main(void) {
    struct utsname u;
    uname(&u);
    printf("C cross-compiled for AArch64 says: machine=%s (qemu-user translates every instruction)\n", u.machine);
    return 0;
}
EOF
    FRESH=1
    write_run << 'EOF'
demo_need aarch64-linux-gnu-as install-asm-arm
demo_step "assemble + link hello.s for AArch64"
aarch64-linux-gnu-as -o hello.o hello.s && aarch64-linux-gnu-ld -o hello hello.o || exit 1
file hello
demo_step "run it under qemu-aarch64"
qemu-aarch64 ./hello
demo_step "cross-compile sysinfo.c (static) and run it"
aarch64-linux-gnu-gcc -static -O2 -o sysinfo sysinfo.c && qemu-aarch64 ./sysinfo
demo_note "Disassemble: aarch64-linux-gnu-objdump -d $DEMO_DIR/hello"
EOF
    done_demo
}

demo_dotnet() {
    if begin dotnet spectre-examples "Spectre.Console in C#: tables, trees, live progress, charts, canvas, figlet (30 apps)" \
        "https://github.com/spectreconsole/examples"; then
        if need dotnet install-dotnet && fetch_repo https://github.com/spectreconsole/examples.git; then
            write_run << 'EOF'
demo_need dotnet install-dotnet
# The examples target net8.0 and this machine has the .NET 10 runtime: let them roll forward.
export DOTNET_ROLL_FORWARD=Major
EX=(); for d in examples/Console/*/; do d=${d%/}; d=${d##*/}; [ "$d" = Showcase ] || EX+=("$d"); done
while demo_menu "Which Spectre.Console example? (the first build restores packages)" Showcase "${EX[@]}"; do
    dotnet run --project "examples/Console/$DEMO_CHOICE"
    [ -n "${1:-}" ] && break
done
EOF
            done_demo
        fi
    fi

    begin dotnet vb-spectre "The same library from VB.NET (this bundle's BASIC): figlet, table, bar chart, calendar, prompt" \
        "generated by dev-demo (NuGet: Spectre.Console)" || return 0
    need dotnet install-dotnet || return 0
    if [ ! -f "$DIR/VbSpectre.vbproj" ] || [ "$REFRESH" = 1 ]; then
        [ -e "$DIR" ] && stash_old
        echo "  creating a VB.NET console project and adding Spectre.Console..."
        dotnet new console -lang VB -n VbSpectre -o "$DIR" > /dev/null \
            && dotnet add "$DIR/VbSpectre.vbproj" package Spectre.Console > /dev/null \
            || { rm -rf "$DIR"; fail "dotnet new / add package failed"; return 0; }
        cat > "$DIR/Program.vb" << 'EOF'
Imports System
Imports Spectre.Console
Imports Spectre.Console.Rendering

' VB.NET calling Spectre.Console. Properties are set directly and instance methods are preferred,
' because VB resolves a property before an extension method of the same name.
Module Program
    Sub Main()
        Console.OutputEncoding = System.Text.Encoding.UTF8

        Dim title As New FigletText("VB.NET")
        title.Color = Color.Green
        AnsiConsole.Write(title)
        AnsiConsole.Write(New Rule("[yellow]Spectre.Console from Visual Basic[/]"))

        Dim table As New Table()
        table.Border = TableBorder.Rounded
        table.AddColumn(New TableColumn("[bold]Language[/]"))
        table.AddColumn(New TableColumn("[bold]Flag[/]"))
        table.AddColumn(New TableColumn("[bold]Demo[/]"))
        table.AddRow(New IRenderable() {New Markup("C#"), New Markup("install-dotnet"), New Markup("spectre-examples")})
        table.AddRow(New IRenderable() {New Markup("[green]VB.NET[/]"), New Markup("install-dotnet"), New Markup("this one")})
        table.AddRow(New IRenderable() {New Markup("PowerShell"), New Markup("install-pwsh"), New Markup("spectre-demo")})
        AnsiConsole.Write(table)

        Dim chart As New BarChart()
        chart.Width = 60
        chart.Label = "[underline]Lines of code in this demo[/]"
        chart.AddItem("Imports", 3, Color.Blue)
        chart.AddItem("Table", 11, Color.Green)
        chart.AddItem("Chart", 6, Color.Yellow)
        AnsiConsole.Write(chart)

        Dim cal As New Calendar(DateTime.Today.Year, DateTime.Today.Month)
        cal.AddCalendarEvent(DateTime.Today.Year, DateTime.Today.Month, DateTime.Today.Day)
        AnsiConsole.Write(cal)

        AnsiConsole.Status().Start("Thinking in VB...", Sub(ctx) Threading.Thread.Sleep(1500))

        Dim prompt As New SelectionPrompt(Of String)()
        prompt.Title = "Which BASIC did you grow up with?"
        prompt.AddChoices(New String() {"GW-BASIC", "QBasic", "Visual Basic 6", "VB.NET", "None, I'm here for C#"})
        Dim pick As String = AnsiConsole.Prompt(prompt)
        AnsiConsole.MarkupLine("You picked [bold aqua]" & Markup.Escape(pick) & "[/]. Good choice.")
    End Sub
End Module
EOF
        FRESH=1
    else
        echo "  already created (demo-refresh recreates it)"
    fi
    write_run << 'EOF'
demo_need dotnet install-dotnet
dotnet run
EOF
    done_demo
}

demo_pwsh() {
    begin pwsh spectre-demo "PwshSpectreConsole: Start-SpectreDemo, an interactive tour of rich terminal UI in PowerShell" \
        "https://github.com/ShaunLawrie/PwshSpectreConsole (PowerShell Gallery)" || return 0
    need pwsh install-pwsh || return 0
    if [ ! -d "$DIR/modules/PwshSpectreConsole" ] || [ "$REFRESH" = 1 ]; then
        rm -rf "$DIR/modules"; mkdir -p "$DIR/modules"
        echo "  saving the module into ~/dev-demo/pwsh/spectre-demo/modules (not your profile's module path)..."
        DEST="$DIR/modules" pwsh -NoLogo -NoProfile -Command '
            try { Save-PSResource -Name PwshSpectreConsole -Path $env:DEST -TrustRepository -ErrorAction Stop }
            catch { Save-Module -Name PwshSpectreConsole -Path $env:DEST -Force -ErrorAction Stop }' \
            || { fail "could not save PwshSpectreConsole from the PowerShell Gallery"; return 0; }
        FRESH=1
    else
        echo "  already downloaded (demo-refresh updates it)"
    fi
    write_run << 'EOF'
demo_need pwsh install-pwsh
DEMO_MODULES="$DEMO_DIR/modules" pwsh -NoLogo -NoProfile -Command '
    $env:PSModulePath = $env:DEMO_MODULES + [IO.Path]::PathSeparator + $env:PSModulePath
    Import-Module PwshSpectreConsole
    Start-SpectreDemo'
EOF
    done_demo
}

demo_java() {
    begin java spring-petclinic "Spring PetClinic: the classic Spring Boot app on :8080 (in-memory H2 database)" \
        "https://github.com/spring-projects/spring-petclinic" || return 0
    need java install-java || return 0
    fetch_repo https://github.com/spring-projects/spring-petclinic.git || return 0
    write_run << 'EOF'
demo_need java install-java
export MAVEN_OPTS="-Xmx768m"
demo_note "First run downloads the Maven dependencies (a few minutes). Ctrl-C stops the app."
demo_open_when_ready 8080 http://localhost:8080
./mvnw spring-boot:run
EOF
    done_demo
}

demo_ruby() {
    begin ruby just-the-docs "Just the Docs: a full Jekyll documentation site with search, served live on :4000" \
        "https://github.com/just-the-docs/just-the-docs" || return 0
    need bundle install-ruby || return 0
    fetch_repo https://github.com/just-the-docs/just-the-docs.git || return 0
    write_run << 'EOF'
demo_need bundle install-ruby
bundle config set --local path vendor/bundle > /dev/null
bundle install --quiet || exit 1
demo_open_when_ready 4000 http://localhost:4000
demo_note "Edit any page under docs/ and the browser reloads. Ctrl-C stops the server."
bundle exec jekyll serve --livereload --host 127.0.0.1 --port 4000
EOF
    done_demo
}

demo_lazarus() {
    begin lazarus examples "Lazarus 4.8's own example projects (OpenGL, grids, databases, charts), copied so they can build" \
        "/usr/share/lazarus/<version>/examples (installed with install-lazarus)" || return 0
    local src
    src=$(ls -d /usr/share/lazarus/*/examples 2> /dev/null | sort -V | tail -n 1)
    if [ -z "$src" ]; then
        echo "  ${YEL}skip${RST}: no Lazarus examples folder (dev-setup with install-lazarus)"
        SKIPPED+=("$STACK/$NAME: Lazarus not installed (install-lazarus)"); return 0
    fi
    if ! present; then
        echo "  copying $src (the system copy is read-only, and Lazarus builds inside the project folder)..."
        mkdir -p "$DEMO_ROOT/$STACK" && cp -a "$src" "$DIR" || { fail "copy failed"; return 0; }
        FRESH=1
    fi
    write_run << 'EOF'
IDE=$(command -v startlazarus || command -v lazarus-ide) || { echo "Lazarus IDE not found (install-lazarus)."; exit 1; }
mapfile -t LPI < <(find . -maxdepth 3 -name '*.lpi' -printf '%P\n' | sort)
demo_menu "Open which project in Lazarus? (try opengl*, grid*, chart*, db*; press F9 in the IDE to run)" "${LPI[@]}" || exit 0
"$IDE" "$DEMO_DIR/$DEMO_CHOICE" > /dev/null 2>&1 &
disown
EOF
    done_demo
}

# =================================================================
# DEMOS: web, Drupal, TanStack
# =================================================================

demo_web() {
    if begin web angular-example-app "Angular 21 example app: signals, i18n, lazy routes, auth against the author's hosted API" \
        "https://github.com/Ismaestro/angular-example-app"; then
        if need npm install-node && fetch_repo https://github.com/Ismaestro/angular-example-app.git; then
            write_run << 'EOF'
demo_need npm install-node
[ -d node_modules ] || npm install --no-audit --no-fund || exit 1
demo_note "Logins and the Pokemon catalogue use the author's hosted API and the public PokeAPI (internet needed)."
demo_open_when_ready 4200 http://localhost:4200
npx ng serve --configuration=localhost-en --port 4200
EOF
            done_demo
        fi
    fi

    begin web drupal-umami "Drupal core's Umami food-magazine demo on PHP's built-in server + SQLite; v89: Redis, Memcached, Solr and OpenSearch items" \
        "https://www.drupal.org/project/drupal (composer: drupal/recommended-project)" || return 0
    need composer install-web || return 0
    need php "the base install" || return 0
    # quick-start installs into SQLite; install-web's Drupal extensions may not include the driver.
    php -m 2> /dev/null | grep -qi '^pdo_sqlite$' || apt_need php-sqlite3 || { fail "php-sqlite3 missing"; return 0; }
    if ! present; then
        echo "  composer create-project drupal/recommended-project (a couple of minutes)..."
        COMPOSER_NO_INTERACTION=1 composer create-project drupal/recommended-project "$DIR" --no-progress -q \
            || { rm -rf "$DIR"; fail "composer create-project failed"; return 0; }
        FRESH=1
    fi
    write_run << 'EOF'
demo_need php "the base install"
SETTINGS=web/sites/default/settings.php
installed() { [ -f "$SETTINGS" ] && grep -q sqlite "$SETTINGS"; }
drush() { php -d memory_limit=512M vendor/bin/drush "$@"; }
need_site() { installed || { echo "Install Umami first: the 'serve' item (it installs on its first run)."; return 1; }; }
# settings_block NAME [CONTENT]: replace the marked block NAME at the end of settings.php (removed when
# CONTENT is empty). Drupal makes settings.php and its folder read-only after installing; this opens them
# for the edit and closes them again.
settings_block() {
    local name=$1 content=${2:-} tmp
    chmod u+w web/sites/default "$SETTINGS"
    tmp=$(mktemp)
    awk -v b="// >>> dev-demo $name >>>" -v e="// <<< dev-demo $name <<<" '$0 == b { skip = 1; next } skip && $0 == e { skip = 0; next } !skip' "$SETTINGS" > "$tmp"
    if [ -n "$content" ]; then
        { echo "// >>> dev-demo $name >>>"; echo "// Written by dev-demo's web/drupal-umami launcher ('cache-off' removes it)."; echo "$content"; echo "// <<< dev-demo $name <<<"; } >> "$tmp"
    fi
    cat "$tmp" > "$SETTINGS"; rm -f "$tmp"
    chmod a-w "$SETTINGS"; chmod u-w web/sites/default
}
# add_module PROJECT MODULE...: composer require drupal/PROJECT (and Drush, once), then enable the modules
add_module() {
    local project=$1; shift
    [ -x vendor/bin/drush ] || { demo_step "composer require drush/drush"; composer require -q --no-interaction drush/drush || return 1; }
    if ! composer show "drupal/$project" > /dev/null 2>&1; then
        demo_step "composer require drupal/$project"
        composer require -q --no-interaction "drupal/$project" || return 1
    fi
    drush -y pm:install "$@" || return 1
}
svc() {   # svc NAME: the shared service must be running ('devsvc up' starts it; it stays running)
    demo_need devsvc "install-$1"
    # One start; on failure its output (the memory guard's advice, or the service's last log lines) is shown.
    [ "$(docker inspect -f '{{.State.Running}}' "devsvc-$1" 2> /dev/null)" = true ] \
        || demo_note "Starting $1 (Solr, OpenSearch, Elasticsearch and Atlas Local take a minute or two)..."
    local out; out=$(devsvc up "$1" 2>&1) || { printf '%s\n' "$out"; return 1; }
    grep '^Stopping' <<< "$out"
    demo_note "$1 is running (shared service; 'devsvc down $1' when you are done)."
}
while demo_menu "Drupal Umami (PHP's built-in server + SQLite)" \
        "serve: Umami on http://127.0.0.1:8888 (installs it the first time); Ctrl-C stops" \
        "redis: Drupal's cache in the shared Redis (drupal/redis, phpredis)" \
        "memcache: Drupal's cache in the shared Memcached (drupal/memcache)" \
        "solr: Search API Solr against the shared Solr (enables the modules, prints the server form's values)" \
        "opensearch: Search API OpenSearch against the shared OpenSearch (the same)" \
        "cache-off: back to Drupal's own database cache (removes the redis / memcache settings)"; do
    case "$DEMO_CHOICE" in
        serve*)
            if installed; then
                demo_note "Umami is installed: starting the server (it prints a one-time login link)."
                php -d memory_limit=512M web/core/scripts/drupal server --host=127.0.0.1 --port=8888
            else
                demo_note "Installing Umami into SQLite (about a minute), then serving it on :8888."
                php -d memory_limit=512M web/core/scripts/drupal quick-start demo_umami --host=127.0.0.1 --port=8888
            fi ;;
        redis*)
            need_site || continue
            php -m | grep -qix redis || { echo "PHP has no redis extension: dev-setup with install-web (php-redis)."; continue; }
            svc redis || continue
            add_module redis redis || continue
            settings_block memcache
            pw=$(devsvc password redis 2> /dev/null)
            settings_block redis "\$settings['redis.connection']['interface'] = 'PhpRedis';
\$settings['redis.connection']['host'] = '127.0.0.1';
\$settings['redis.connection']['port'] = 6379;
$( [ -n "$pw" ] && echo "\$settings['redis.connection']['password'] = '$pw';")
\$settings['cache_prefix'] = 'umami_';
\$settings['cache']['default'] = 'cache.backend.redis';"
            drush cr > /dev/null 2>&1
            curl -s -o /dev/null http://127.0.0.1:8888/ 2> /dev/null || true
            demo_note "Drupal's cache now lives in Redis. Keys so far: $(devsvc cli redis --scan --pattern 'umami_*' 2> /dev/null | wc -l)"
            demo_note "Serve the site and browse; 'devsvc cli redis --scan --pattern \"umami_*\"' shows the cache filling up."
            demo_note "In DDEV the same settings take host 'devredis' (the add-on route: ddev add-on get ddev/ddev-redis)." ;;
        memcache*)
            need_site || continue
            php -m | grep -qix memcached || { echo "PHP has no memcached extension: dev-setup with install-web (php-memcached)."; continue; }
            svc memcached || continue
            add_module memcache memcache || continue
            settings_block redis
            settings_block memcache "\$settings['memcache']['servers'] = ['127.0.0.1:11211' => 'default'];
\$settings['memcache']['bins'] = ['default' => 'default'];
\$settings['memcache']['key_prefix'] = 'umami';
\$settings['cache']['default'] = 'cache.backend.memcache';"
            drush cr > /dev/null 2>&1
            demo_note "Drupal's cache now lives in Memcached: $(devsvc cli memcached stats 2> /dev/null | grep -E '^STAT curr_items ' | tr -d '\r')"
            demo_note "In DDEV the same settings take 'devmemcached:11211' (the add-on route: ddev add-on get ddev/ddev-memcached)." ;;
        solr*)
            need_site || continue
            svc solr || continue
            add_module search_api_solr search_api search_api_solr search_api_solr_admin || continue
            cat << SOLR

Configuration > Search and metadata > Search API > Add server   (http://127.0.0.1:8888/admin/config/search/search-api/add-server)
  Server name        Shared Solr
  Backend            Solr
  Solr Connector     Solr Cloud with Basic Auth
  HTTP protocol      http          Solr host   127.0.0.1          Solr port   8983
  Solr path          /             Default Solr collection         umami
  Username           solr          Password    $(devsvc password solr 2> /dev/null)
Save. Then on the server's page, 'Upload Configset' (search_api_solr_admin) with 'Create the collection'
ticked and 1 shard: Solr gets search_api_solr's configset and the umami collection. Add an index
(Content, the article and recipe bundles, this server), add fields, 'Index now'.
In DDEV the host is 'devsolr'. The add-on route (ddev add-on get ddev/ddev-solr) runs a Solr per project.
SOLR
            ;;
        opensearch*)
            need_site || continue
            svc opensearch || continue
            add_module search_api_opensearch search_api search_api_opensearch || continue
            cat << OSRCH

Configuration > Search and metadata > Search API > Add server   (http://127.0.0.1:8888/admin/config/search/search-api/add-server)
  Server name        Shared OpenSearch
  Backend            OpenSearch
  Connector          Basic Auth
  OpenSearch URL     http://127.0.0.1:9200
  Username           admin         Password    $(devsvc password opensearch 2> /dev/null)
Save, add an index (Content, this server), add fields, 'Index now'. In DDEV the URL is http://devopensearch:9200.
OSRCH
            ;;
        cache-off*)
            need_site || continue
            settings_block redis; settings_block memcache
            drush cr > /dev/null 2>&1
            demo_note "Back on Drupal's database cache. The modules stay enabled; 'drush pmu redis memcache' removes them." ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

demo_drupal() {
    # v80: this function now holds two demos, so the first one must not 'return' (demo-clean included).
    if begin drupal drupal-cms "Drupal CMS (Starshot) in DDEV: the full installer with recipes, in containers" \
        "https://www.drupal.org/project/cms (composer: drupal/cms)" && need ddev install-drupal; then
        if ! present; then
            mkdir -p "$DIR"
            ( cd "$DIR" && ddev config --project-type=drupal11 --docroot=web --project-name=devdemo-drupal-cms > /dev/null ) \
                || { rm -rf "$DIR"; fail "ddev config failed"; }
            FRESH=1
        fi
        if [ -d "$DIR/.ddev" ]; then
            write_run << 'EOF'
demo_need ddev install-drupal
docker_ok
if [ "${1:-}" = down ]; then ddev stop; exit; fi
demo_note "First start pulls DDEV's images and downloads Drupal CMS (several minutes, ~2 GB)."
ddev start || exit 1
[ -f composer.json ] || ddev composer create-project drupal/cms || exit 1
ddev launch
demo_note "The site keeps running. Stop it with: $0 down   (or 'ddev poweroff' to stop all DDEV projects)."
demo_note "The Pantheon/Acquia/Upsun CLIs have no demo here: they need your platform tokens (dev-init)."
EOF
            done_demo
        fi
    fi

    # v80: a Drupal AI RAG site. Drupal runs in DDEV; the vectors live in a pgvector sidecar container;
    # embeddings and answers come from this machine's Ollama, which DDEV's web container reaches at
    # host.docker.internal once setup ran with install-ollama-containers. Everything heavy (images,
    # Composer, site install) happens on the first launch, not here.
    begin drupal drupal-rag "Drupal AI RAG: local Ollama embeds articles into pgvector, a chatbot answers from them" \
        "https://www.drupal.org/project/ai (+ ai_search, ai_agents, ai_provider_ollama, ai_vdb_provider_postgres)" || return 0
    need ddev install-drupal || return 0
    if ! present; then
        mkdir -p "$DIR"
        ( cd "$DIR" && ddev config --project-type=drupal11 --docroot=web --project-name=devdemo-drupal-rag > /dev/null ) \
            || { rm -rf "$DIR"; fail "ddev config failed"; return 0; }
        FRESH=1
    fi
    gen_file "$DIR/.ddev/docker-compose.pgvector.yaml" << 'EOF'
# pgvector sidecar for dev-demo's Drupal RAG site (written by dev-demo). DDEV starts and stops it
# with the project. From the web container it is host 'pgvector', port 5432, user and password
# 'db', database 'vectors'. Its data is a named volume that 'ddev delete' leaves in place:
#   docker volume rm ddev-devdemo-drupal-rag-pgvector
services:
  pgvector:
    container_name: ddev-${DDEV_SITENAME}-pgvector
    image: pgvector/pgvector:pg17
    restart: "no"
    labels:
      com.ddev.site-name: ${DDEV_SITENAME}
      com.ddev.approot: ${DDEV_APPROOT}
    environment:
      POSTGRES_USER: db
      POSTGRES_PASSWORD: db
      POSTGRES_DB: vectors
    volumes:
      - pgvector-data:/var/lib/postgresql/data
volumes:
  pgvector-data:
    name: ddev-${DDEV_SITENAME}-pgvector
EOF
    gen_file "$DIR/.ddev/devdemo/seed.php" << 'EOF'
<?php

/**
 * @file
 * dev-demo: sample articles for the Drupal RAG site (the notes models/local-rag indexes, plus one
 * about Firebird). Run with: ddev drush php:script /var/www/html/.ddev/devdemo/seed.php
 */

use Drupal\node\Entity\Node;

$articles = [
  'Run order of the Chromebook bundle' => [
    'The bundle is four scripts that take the same flags: dev-setup installs, dev-init applies logins and keys from secrets.env, dev-test verifies, and dev-demo downloads hands-on demos.',
    'The order is init, setup, init again, then test. The first init run only writes the secrets template. Setup never prompts, and the test reports every login as a warning until init has applied secrets.env.',
    'All four scripts share one version number: a change to any of them bumps all four.',
  ],
  'Memory on an 8 GB Chromebook' => [
    'The Linux VM sees about 6.4 GB of the 8 GB. The ChromeOS memory balloon shows up as used memory in free, so judge headroom by the available column.',
    'Run one heavy thing at a time: an Ollama model, a kind cluster (about 2 GB), self-hosted Langfuse (about 3 GB), SQL Server or Oracle (about 2 GB each), this Drupal site with its two models, or an Android Gradle build.',
    'The command ollama stop gives a model its memory back at once; otherwise Ollama unloads it after five idle minutes. mssql down and oracle down do the same for the database servers.',
  ],
  'Ollama in the bundle' => [
    'install-ollama installs the server with a systemd drop-in: a 15-minute load timeout, at most two models loaded, one request per model, an 8192-token default context, flash attention and a q8_0 KV cache.',
    'Inference is CPU-only in Crostini, because the container gets OpenGL through virgl but no CUDA, ROCm or Vulkan.',
    'Docker containers, such as DDEV running this site, reach Ollama at host.docker.internal only after setup runs with install-ollama-containers, which makes the server listen on every interface.',
  ],
  'Models pulled by install-models' => [
    'deepseek-r1:1.5b is DeepSeek-R1 distilled into a 1.5B Qwen model, and the DeepSeek that fits on these Chromebooks. It reasons before answering.',
    'qwen3.5:4b handles text and images, calls tools and can think. It answers the questions in this chatbot. qwen3-embedding:0.6b turns text into 1024-dimension vectors for search; it cannot chat.',
    'A 7B model needs everything else closed. Bigger models run on another machine through OLLAMA_REMOTE, or as Ollama cloud models.',
  ],
  'Which flag installs what' => [
    'install-all covers every stack except the opt-in flags: install-models, install-godot-templates, install-asm-arm, install-ansible-core, install-db-server (SQL Server, Oracle and InterBase), install-oracle-full (Oracle on its full image), install-ldap (an lldap directory), install-ldap-full (OpenLDAP next to it), install-ollama-containers, install-lan and install-lan-share (the laptop network), install-com and install-retro (COM under Wine; DOS, Windows 3.1, 95, NT 4.0 and 2000, Delphi 1, and Delphi 3, 4, 5, 6 and 7 under Wine), and install-hermes and install-openclaw (the personal agents Hermes Agent and OpenClaw).',
    'install-laravel installs the Laravel installer (laravel new) and install-symfony the Symfony CLI (symfony new), both on top of install-web's Composer and PHP extensions. install-drupal installs Terminus, the Acquia CLI and the Upsun CLI next to DDEV. install-iac installs Terraform, tflint, Bicep and the full Ansible package. install-agentic installs Temporal, LangGraph, Pydantic and Langfuse.',
  ],
  'Firebird and InterBase on the Chromebook' => [
    'install-db installs Firebird 4 with its embedded engine, so a program opens a .fdb file with no server running. Its isql is called isql-fb, because unixODBC owns isql.',
    'Firebird forked from InterBase 6.0 in 2000 and cannot open a modern InterBase database. install-interbase, part of install-db-server, installs Embarcadero InterBase from a download placed in the bundle assets folder; the free Developer Edition must be registered before its server starts.',
    'Lazarus programs reach both through SQLdb TIBConnection. A TSQLDBLibraryLoader picks the client library: libfbclient.so.2 for Firebird, /opt/interbase/lib/libgds.so for InterBase.',
  ],
];

foreach ($articles as $title => $paragraphs) {
  $existing = \Drupal::entityQuery('node')
    ->accessCheck(FALSE)
    ->condition('type', 'article')
    ->condition('title', $title)
    ->execute();
  if ($existing) {
    echo "exists:  $title\n";
    continue;
  }
  Node::create([
    'type' => 'article',
    'title' => $title,
    'body' => [
      'value' => '<p>' . implode('</p><p>', $paragraphs) . '</p>',
      'format' => 'basic_html',
    ],
    'status' => 1,
  ])->save();
  echo "created: $title\n";
}
EOF
    gen_file "$DIR/.ddev/devdemo/STEPS.md" << 'EOF'
# Drupal AI RAG demo: the admin-UI steps

The launcher (~/dev-demo/drupal/run-drupal-rag.sh) starts DDEV and the pgvector container, installs
Drupal 11 with the AI modules, points the Ollama provider at http://host.docker.internal:11434 and
the Postgres vector database at the pgvector container where this module version has those settings,
and creates six sample articles. What is left is wiring the index, the assistant and the chatbot.
Menu labels move between AI module releases; if one is not where this says, search the admin menu.

Versions: AI core 1.5 (the 1.x line; 2.x is still in development), AI Search 1.3 (its own project
since AI 1.5, alpha releases so far) and AI Agents, which AI Assistants runs on in 1.5.

Log in as admin / admin, or with the one-time link the launcher prints.

1. Ollama provider: Configuration > AI > Provider settings > Ollama. Host http://host.docker.internal,
   port 11434. Save; the model lists should fill in from this machine's Ollama.
2. Defaults: Configuration > AI > AI Default Settings. Chat: Ollama, qwen3.5:4b.
   Embeddings: Ollama, qwen3-embedding:0.6b.
3. Vector database: Configuration > AI > Vector DBs Settings > Postgres. Host pgvector, port 5432,
   username db, password db (store it as a Key if the form asks for one), database vectors.
4. Search server: Configuration > Search and metadata > Search API > Add server. Backend "AI Search".
   Embeddings engine Ollama / qwen3-embedding:0.6b; vector database Postgres; dimensions 1024
   (what qwen3-embedding:0.6b returns); collection devdemo. Save.
5. Search index: Add index "Articles": datasource Content, bundle Article, the server from step 4.
   Add the Title and Body fields; on the index's Fields tab mark Body as main content and Title as
   contextual content. Save, then Index now. Embedding runs on the CPU: a few seconds per article.
6. Try the retrieval alone: Configuration > AI > AI API Explorer (the vector database / search
   explorer). Ask "How much memory does the Linux VM see?" and look at the matched chunks.
7. Assistant: Configuration > AI > AI Assistants > Add. Give it a RAG action on the Articles index,
   chat model Ollama / qwen3.5:4b, and instructions to answer only from the retrieved articles.
   In AI 1.5 an assistant is backed by an AI Agent: if the form asks for one, let it create the agent,
   or add the RAG tool on the Articles index to an agent under Configuration > AI > AI Agents.
8. Chatbot: Structure > Block layout > place the AI chatbot block (DeepChat) in a region and pick
   the assistant from step 7. Open the front page and ask it something from the articles.

Memory: DDEV (web, MariaDB, pgvector) takes about 1.2 GB and the two models about 4 GB more, so close
other demos first. The first answer waits for qwen3.5:4b to load.

Stop the site:  ~/dev-demo/drupal/run-drupal-rag.sh down
Start over:     ddev delete -Oy devdemo-drupal-rag && docker volume rm ddev-devdemo-drupal-rag-pgvector
                then rerun dev-demo with install-drupal demo-refresh
Faster answers: add a hosted chat model (drupal/ai_provider_anthropic with your ANTHROPIC_API_KEY)
                and keep Ollama for the embeddings.
EOF
    write_run << 'EOF'
demo_need ddev install-drupal
docker_ok
if [ "${1:-}" = down ]; then ddev stop; exit; fi
EMBED_MODEL="${RAG_EMBED_MODEL:-qwen3-embedding:0.6b}"
CHAT_MODEL="${RAG_CHAT_MODEL:-qwen3.5:4b}"
demo_need ollama install-models
for m in "$EMBED_MODEL" "$CHAT_MODEL"; do
    ollama list 2> /dev/null | awk 'NR > 1 {print $1}' | grep -qxF "$m" \
        || { echo "Missing Ollama model $m: rerun dev-setup with install-models (or: ollama pull $m)."; exit 1; }
done
demo_note "HEAVY: DDEV (web, MariaDB, pgvector) plus two Ollama models is most of this machine's RAM. Close other demos."

demo_step "DDEV: web, database and the pgvector container"
ddev start || exit 1
if ! ddev exec curl -fsS --max-time 10 http://host.docker.internal:11434/api/version > /dev/null 2>&1; then
    echo "DDEV's web container cannot reach Ollama at http://host.docker.internal:11434: Ollama listens on"
    echo "127.0.0.1 only. Rerun dev-setup with install-ollama-containers, then run this again."
    exit 1
fi
demo_note "Ollama answers from inside DDEV's web container."
for _ in $(seq 60); do ddev exec -s pgvector pg_isready -q -U db -d vectors > /dev/null 2>&1 && break; sleep 1; done
ddev exec -s pgvector psql -q -U db -d vectors -c 'CREATE EXTENSION IF NOT EXISTS vector;' || exit 1

if [ ! -f composer.json ]; then
    demo_step "Drupal 11 and the AI modules (first run: several minutes)"
    ddev composer create-project drupal/recommended-project || exit 1
    # v81: AI core 1.5 moved AI Search into its own project, which has only alpha releases so far, and
    # runs AI Assistants on the AI Agents module. Development builds are allowed so those resolve, but
    # prefer-stable and the constraints keep everything on its most stable release and on the AI 1.x
    # line (AI 2.x exists only as a development branch).
    ddev composer config minimum-stability dev
    ddev composer config prefer-stable true
    ddev composer require drush/drush 'drupal/ai:^1.5' 'drupal/ai_search:^1.3' 'drupal/ai_agents:^1' \
        drupal/ai_provider_ollama drupal/ai_vdb_provider_postgres || exit 1
fi
if ! ddev drush status --field=bootstrap 2> /dev/null | grep -q Successful; then
    demo_step "Installing Drupal (standard profile; admin / admin)"
    ddev drush -y site:install standard --site-name="dev-demo RAG" --account-name=admin --account-pass=admin || exit 1
fi

demo_step "Enabling the AI modules"
for mod in key search_api ai ai_provider_ollama ai_search ai_vdb_provider_postgres ai_agents ai_assistant_api ai_chatbot ai_api_explorer; do
    if ddev drush -y pm:install "$mod" > /dev/null 2>&1; then echo "  $mod"; else echo "  $mod: could not enable (renamed in this release? ddev drush pm:list | grep -i ai)"; fi
done

# Only settings this module version actually has are written, so a renamed key is never invented.
cset_if() {   # cset_if CONFIG KEY VALUE
    if ddev drush config:get "$1" "$2" > /dev/null 2>&1; then
        ddev drush -y config:set "$1" "$2" "$3" > /dev/null 2>&1 && echo "  $1 $2 = $3"
    else
        echo "  ($1 has no '$2' here: set it in the admin UI, STEPS.md)"
    fi
}
demo_step "Pointing the Ollama provider and the vector database at their containers"
cset_if ai_provider_ollama.settings host_name http://host.docker.internal
cset_if ai_provider_ollama.settings port 11434
cset_if ai_vdb_provider_postgres.settings host pgvector
cset_if ai_vdb_provider_postgres.settings port 5432
cset_if ai_vdb_provider_postgres.settings username db
cset_if ai_vdb_provider_postgres.settings default_database vectors

demo_step "Sample articles"
ddev drush php:script /var/www/html/.ddev/devdemo/seed.php

demo_step "What is left: index, assistant and chatbot in the admin UI"
cat .ddev/devdemo/STEPS.md
ULI=$(ddev drush uli --no-browser 2> /dev/null | tail -n 1)
if [ -n "$ULI" ]; then
    demo_note "One-time admin login: $ULI"
    ddev launch "/${ULI#*://*/}"
else
    ddev launch /user/login
fi
demo_note "The site keeps running. Stop it with: $0 down. The steps stay in $DEMO_DIR/.ddev/devdemo/STEPS.md"
EOF
    done_demo
}

# v83: drupal/drupal-ldap (install-ldap / install-ldap-full): Drupal 11 in DDEV logs people in from the
# LDAP directories setup created. The launcher wires up the contrib 'ldap' suite (drupal/ldap: servers,
# users, authentication) against lldap (lite) or OpenLDAP (full); one menu item swaps in miniOrange's
# 'ldap_auth' instead. DDEV's web container reaches lldap as ldap://lldap:3890 ('ldap up' puts lldap
# on DDEV's network) and slapd as ldap://host.docker.internal:389.
demo_ldap() {
    begin drupal drupal-ldap "Drupal logs LDAP people in: the contrib 'ldap' suite (or miniOrange's 'ldap_auth') against lldap or OpenLDAP" \
        "https://www.drupal.org/project/ldap + https://www.drupal.org/project/ldap_auth (directories from install-ldap)" || return 0
    need ddev "the base install" || return 0
    need ldap install-ldap || return 0
    if ! present; then
        mkdir -p "$DIR"
        ( cd "$DIR" && ddev config --project-type=drupal11 --docroot=web --project-name=devdemo-drupal-ldap > /dev/null ) \
            || { rm -rf "$DIR"; fail "ddev config failed"; return 0; }
        FRESH=1
    fi
    gen_file "$DIR/.ddev/devdemo/ldap_ping.php" << 'EOF'
<?php

/**
 * @file
 * dev-demo: binds to one of the LDAP directories from PHP in DDEV's web container, the way drupal/ldap
 * will. Usage: php .ddev/devdemo/ldap_ping.php lite|full
 * Reads .ddev/devdemo/ldap-values.json, which run-drupal-ldap.sh writes from ~/.config/devldap/ldap.env.
 */

$which = $argv[1] ?? 'lite';
if (!function_exists('ldap_connect')) {
  fwrite(STDERR, "PHP in this container has no ldap extension\n");
  exit(2);
}
$v = json_decode(file_get_contents(__DIR__ . '/ldap-values.json'), TRUE);
$s = $v['servers'][$which] ?? NULL;
if (!$s) {
  fwrite(STDERR, "No '$which' directory in ldap-values.json\n");
  exit(2);
}
$uri = "ldap://{$s['host']}:{$s['port']}";
$c = ldap_connect($uri);
ldap_set_option($c, LDAP_OPT_PROTOCOL_VERSION, 3);
ldap_set_option($c, LDAP_OPT_NETWORK_TIMEOUT, 5);
if (!@ldap_bind($c, $v['bind_dn'], $v['bind_pw'])) {
  fwrite(STDERR, "Bind to $uri as {$v['bind_dn']} failed: " . ldap_error($c) . "\n");
  exit(1);
}
$r = @ldap_search($c, $v['people_dn'], '(uid=alice)', ['uid', 'mail']);
$e = $r ? ldap_get_entries($c, $r) : ['count' => 0];
echo "PHP in DDEV bound to $uri as the service account; alice: " . ($e['count'] ? $e[0]['mail'][0] : 'NOT FOUND') . "\n";
exit($e['count'] ? 0 : 1);
EOF
    gen_file "$DIR/.ddev/devdemo/configure.php" << 'EOF'
<?php

/**
 * @file
 * dev-demo: points drupal/ldap at the LDAP directories dev-setup created. Run by run-drupal-ldap.sh:
 *   ddev drush php:script /var/www/html/.ddev/devdemo/configure.php
 * It reads .ddev/devdemo/ldap-values.json (written by the launcher from ~/.config/devldap/ldap.env).
 * One server entity per directory (devldap_lite, devldap_full); logins go through the one in "use".
 * Only settings this module version declares in its config schema are written, so a renamed key is
 * reported ("set it in the UI") instead of invented.
 */

$v = json_decode(file_get_contents('/var/www/html/.ddev/devdemo/ldap-values.json'), TRUE);
$typed = \Drupal::service('config.typed');
$etm = \Drupal::entityTypeManager();
if (!$etm->hasDefinition('ldap_server')) {
  echo "No ldap_server entity type: is ldap_servers enabled?\n";
  exit(1);
}

/**
 * Sets the values whose keys the config schema mapping declares; reports the others.
 */
function devdemo_apply($target, array $mapping, array $values, string $what): void {
  foreach ($values as $key => $value) {
    if (!isset($mapping[$key])) {
      echo "  ($what has no '$key' in this version: set it in the UI if you need it)\n";
      continue;
    }
    $type = $mapping[$key]['type'] ?? '';
    if ($type === 'sequence' && !is_array($value)) {
      $value = [$value];
    }
    elseif ($type !== 'sequence' && is_array($value)) {
      $value = implode("\n", $value);
    }
    $target->set($key, $value);
  }
}

$storage = $etm->getStorage('ldap_server');
foreach ($v['servers'] as $name => $s) {
  $id = 'devldap_' . $name;
  $mapping = $typed->getDefinition('ldap_servers.server.' . $id)['mapping'] ?? [];
  $server = $storage->load($id) ?: $storage->create(['id' => $id, 'label' => $s['label']]);
  devdemo_apply($server, $mapping, [
    'status' => TRUE,
    'type' => 'openldap',
    'address' => $s['host'],
    'port' => (int) $s['port'],
    'timeout' => 10,
    'encryption' => 'none',
    'bind_method' => 'service_account',
    'binddn' => $v['bind_dn'],
    'bindpw' => $v['bind_pw'],
    'basedn' => [$v['people_dn']],
    'user_attr' => 'uid',
    'mail_attr' => 'mail',
    'unique_persistent_attr' => 'entryuuid',
    'testing_drupal_username' => 'alice',
    'testing_drupal_user_dn' => 'uid=alice,' . $v['people_dn'],
  ], "ldap_servers.server.$id");
  $server->save();
  echo "server $id: ldap://{$s['host']}:{$s['port']} ({$s['label']})\n";
}

$use = 'devldap_' . $v['use'];
$auth = \Drupal::configFactory()->getEditable('ldap_authentication.settings');
devdemo_apply($auth, $typed->getDefinition('ldap_authentication.settings')['mapping'] ?? [],
  ['sids' => [$use => $use]], 'ldap_authentication.settings');
$auth->save();

// Create the Drupal account the first time a directory user logs in.
$user = \Drupal::configFactory()->getEditable('ldap_user.settings');
$triggers = (array) ($user->get('drupalAcctProvisionTriggers') ?? []);
$triggers['drupal_on_login'] = 'drupal_on_login';
devdemo_apply($user, $typed->getDefinition('ldap_user.settings')['mapping'] ?? [],
  ['drupalAcctProvisionServer' => $use, 'drupalAcctProvisionTriggers' => $triggers], 'ldap_user.settings');
$user->save();
echo "logins go through $use\n";
EOF
    gen_file "$DIR/.ddev/devdemo/STEPS.md" << 'EOF'
# Drupal + LDAP demo: what the launcher does, and what is left for the admin UI

run-drupal-ldap.sh starts DDEV and the LDAP directories ('ldap up'), installs Drupal 11 with the
contrib LDAP suite (drupal/ldap 4.x: ldap_servers, ldap_user, ldap_authentication), creates one LDAP
server per directory (devldap_lite for lldap, devldap_full for OpenLDAP) and sends logins through the
one you picked. Logins are mixed mode: Drupal's own admin / admin still works next to LDAP people.

Log in as alice, bob or carol with the password 'ldap passwords' shows. Drupal checks it against the
directory and creates the Drupal account on the first login.

Where things are (menu labels move between module releases; search the admin menu if one is not here):
- Servers and their Test form: Configuration > People > LDAP > Servers (/admin/config/people/ldap/server)
- Login settings: Configuration > People > LDAP > Authentication
- Account sync (fields, when accounts are created): Configuration > People > LDAP > User

Not wired up by the launcher:
1. Roles from groups. Enable ldap_authorization (add drupal/authorization with Composer first if it is
   not there yet), then Configuration > People > Authorization > Add profile: provider LDAP (server devldap_lite or
   devldap_full), consumer Drupal roles, map cn=drupal_editors,ou=groups,<base DN> to Content editor.
   Groups live in ou=groups; 'ldap drupal' prints their object class and membership attribute.
2. miniOrange's module instead of the contrib login: run-drupal-ldap.sh miniorange installs
   drupal/ldap_auth and turns ldap_authentication off (one login validator at a time); its settings
   are under Configuration > People. Its free tier covers login against one server: use the values
   'ldap drupal' prints. run-drupal-ldap.sh lite (or full) switches back.

Stop the site:  ~/dev-demo/drupal/run-drupal-ldap.sh down   (the directories keep running: 'ldap down')
Start over:     ddev delete -Oy devdemo-drupal-ldap, then rerun dev-demo with install-ldap demo-refresh
EOF
    write_run << 'EOF'
demo_need ddev "the base install"
demo_need ldap install-ldap
docker_ok
if [ "${1:-}" = down ]; then ddev stop; exit; fi
# shellcheck disable=SC1091
. "$HOME/.config/devldap/ldap.env" || exit 1
HAVE_FULL=0; [ -x /usr/sbin/slapd ] && HAVE_FULL=1
MODE=${1:-}; DEMO_ARG=""
if [ -z "$MODE" ]; then
    ITEMS=("lite: log in through lldap (contrib drupal/ldap)")
    [ "$HAVE_FULL" = 1 ] && ITEMS+=("full: log in through OpenLDAP (contrib drupal/ldap)")
    ITEMS+=("miniorange: miniOrange's ldap_auth instead of the contrib login")
    demo_menu "Drupal + LDAP" "${ITEMS[@]}" || exit 0
    MODE=${DEMO_CHOICE%%:*}
fi
case "$MODE" in
    lite|miniorange) ;;
    full) [ "$HAVE_FULL" = 1 ] || { echo "OpenLDAP is not installed: dev-setup with install-ldap-full."; exit 1; } ;;
    *) echo "usage: $0 [lite|full|miniorange|down]"; exit 2 ;;
esac
USE=$MODE; [ "$MODE" = miniorange ] && USE=lite

demo_step "DDEV (web + database)"
ddev start || exit 1
demo_step "LDAP directories (and lldap onto DDEV's network)"
ldap up || exit 1
if ! ddev exec php -m 2> /dev/null | grep -qix ldap; then
    demo_note "DDEV's PHP has no ldap extension here: adding php-ldap to the web image (a minute)."
    ddev config --webimage-extra-packages='php${DDEV_PHP_VERSION}-ldap' > /dev/null && ddev restart || exit 1
    ldap up > /dev/null
fi

# What configure.php and ldap_ping.php read (mode 600; DDEV's container runs as you, so it can read it).
PEOPLE="ou=people,$LDAP_BASE_DN"
( umask 077
  jq -n --arg base "$LDAP_BASE_DN" --arg people "$PEOPLE" --arg bdn "uid=drupal-bind,$PEOPLE" \
        --arg bpw "$LDAP_BIND_PASSWORD" --arg use "$USE" --argjson full "$([ "$HAVE_FULL" = 1 ] && echo true || echo false)" \
      '{base: $base, people_dn: $people, bind_dn: $bdn, bind_pw: $bpw, use: $use,
        servers: ({lite: {host: "lldap", port: 3890, label: "lldap (lite)"}}
                  + (if $full then {full: {host: "host.docker.internal", port: 389, label: "OpenLDAP (full)"}} else {} end))}' \
      > .ddev/devdemo/ldap-values.json ) || exit 1

demo_step "PHP in DDEV's web container binds to the directories"
ddev exec php .ddev/devdemo/ldap_ping.php lite || { echo "Not reachable: 'ldap status' shows whether lldap is on DDEV's network."; exit 1; }
[ "$HAVE_FULL" = 1 ] && { ddev exec php .ddev/devdemo/ldap_ping.php full || echo "OpenLDAP is not reachable from DDEV (host.docker.internal:389); the lite directory still works."; }

if [ ! -f composer.json ]; then
    demo_step "Drupal 11 and the LDAP suite (first run: several minutes)"
    ddev composer create-project drupal/recommended-project || exit 1
    ddev composer require drush/drush 'drupal/ldap:^4.13' || exit 1
fi
if ! ddev drush status --field=bootstrap 2> /dev/null | grep -q Successful; then
    demo_step "Installing Drupal (standard profile; admin / admin)"
    ddev drush -y site:install standard --site-name="dev-demo LDAP" --account-name=admin --account-pass=admin || exit 1
fi

if [ "$MODE" = miniorange ]; then
    demo_step "miniOrange's LDAP / Active Directory Integration (drupal/ldap_auth)"
    ddev composer show drupal/ldap_auth > /dev/null 2>&1 || ddev composer require drupal/ldap_auth || exit 1
    # One login validator at a time: the contrib suite's authentication module goes off.
    ddev drush -y pm:uninstall ldap_authentication > /dev/null 2>&1
    ddev drush -y pm:install ldap_auth || exit 1
    ddev drush cr > /dev/null
    ldap drupal lite | sed -n '/^miniOrange/,$p'
    demo_note "Its settings are under Configuration > People (the module's own wizard: server, bind account, search base, Test)."
    ddev launch /admin/config/people
    demo_note "Back to the contrib login: $0 lite. The site keeps running; stop it with: $0 down"
    exit 0
fi

if ddev drush pm:list --status=enabled --field=name 2> /dev/null | grep -qx ldap_auth; then
    demo_note "Switching back from miniOrange's ldap_auth to the contrib suite."
    ddev drush -y pm:uninstall ldap_auth > /dev/null
fi
demo_step "The contrib LDAP suite: servers, users, authentication"
ddev drush -y pm:install ldap_servers ldap_user ldap_authentication || exit 1
demo_step "Pointing drupal/ldap at the directories (logins through $USE)"
ddev drush php:script /var/www/html/.ddev/devdemo/configure.php || exit 1
ddev drush cr > /dev/null
demo_step "What is left for the admin UI"
cat .ddev/devdemo/STEPS.md
ddev launch /user/login
demo_note "Log in as alice (or bob, carol) with $LDAP_SAMPLE_PASSWORD: Drupal checks it against $USE and creates"
demo_note "her account on the first login. admin / admin still works. Server Test form: /admin/config/people/ldap/server"
demo_note "The site keeps running. Stop it with: $0 down. The steps stay in $DEMO_DIR/.ddev/devdemo/STEPS.md"
EOF
    done_demo
}

demo_tanstack() {
    begin tanstack trellaux "Trellaux: a Trello-style board on TanStack Start + Router + Query (SSR, server functions)" \
        "https://github.com/TanStack/router/tree/main/examples/react/start-trellaux" || return 0
    need node install-node || return 0
    fetch_subdir https://github.com/TanStack/router.git examples/react/start-trellaux || return 0
    write_run << 'EOF'
demo_need node install-node
PNPM=(pnpm); command -v pnpm > /dev/null || PNPM=(corepack pnpm)
[ -d node_modules ] || "${PNPM[@]}" install || exit 1
demo_note "Drag cards between columns; open a second tab to see the server state. Ctrl-C stops."
demo_open_when_ready 3000 http://localhost:3000
"${PNPM[@]}" dev --port 3000
EOF
    done_demo
}

# =================================================================
# DEMOS: Godot, mobile
# =================================================================

demo_godot() {
    begin godot demo-projects "Godot's official demo projects: dozens of 2D/3D games and techniques, GDScript and C# (mono/)" \
        "https://github.com/godotengine/godot-demo-projects" || return 0
    need godot install-godot || return 0
    # The repo keeps a branch per stable Godot line (4.3, 4.2...); master tracks the newest release.
    local ver branch=""
    ver=$(godot --version 2> /dev/null | grep -oE '^[0-9]+\.[0-9]+' | head -n 1)
    if [ -n "$ver" ] && git ls-remote --exit-code --heads https://github.com/godotengine/godot-demo-projects.git "$ver" > /dev/null 2>&1; then
        branch=$ver
    fi
    echo "  Godot ${ver:-?} installed: using the ${branch:-master} branch of the demos (~1 GB)"
    fetch_repo https://github.com/godotengine/godot-demo-projects.git "$branch" || return 0
    write_run << 'EOF'
demo_need godot install-godot
mapfile -t PROJ < <(find . -name project.godot -not -path './.git/*' -printf '%h\n' | sed 's|^\./||' | sort)
demo_note "Your launchers use the OpenGL (Compatibility) renderer, the one virgl supports: 2D demos and"
demo_note "Compatibility demos look right; Forward+ 3D demos fall back and may look plainer."
demo_menu "Open which demo? (mono/... = C#, opens in the .NET editor)" "${PROJ[@]}" || exit 0
if [[ "$DEMO_CHOICE" == mono/* ]]; then GD=godot-mono; else GD=godot; fi
demo_need "$GD" install-godot
demo_note "The editor imports the project (a minute the first time). Press F5 to play."
"$GD" -e --path "$DEMO_DIR/$DEMO_CHOICE" > /dev/null 2>&1 &
disown
EOF
    done_demo
}

demo_flutter() {
    begin flutter material-3-demo "Flutter's Material 3 gallery: every component, color scheme and typography, as a Linux desktop app" \
        "https://github.com/flutter/samples/tree/main/material_3_demo" || return 0
    need flutter install-flutter || return 0
    fetch_subdir https://github.com/flutter/samples.git material_3_demo || return 0
    write_run << 'EOF'
demo_need flutter install-flutter
flutter config --enable-linux-desktop > /dev/null 2>&1
[ -d linux ] || flutter create --platforms=linux . > /dev/null
flutter pub get > /dev/null || exit 1
demo_note "First run builds the Linux runner (a few minutes). In the app: r = hot reload, q = quit."
flutter run -d linux
EOF
    done_demo
}

demo_rn() {
    begin rn expo-router "Expo Router (React Native) app, run in the browser with react-native-web" \
        "https://github.com/expo/examples/tree/master/with-router" || return 0
    need npm install-node || return 0
    fetch_subdir https://github.com/expo/examples.git with-router || return 0
    write_run << 'EOF'
demo_need npm install-node
[ -d node_modules ] || npm install --no-audit --no-fund || exit 1
demo_note "Web target on :8081 (Crostini has no Android emulator). Press w if the browser does not open."
npx expo start --web --port 8081
EOF
    done_demo
}

demo_tauri() {
    begin tauri tauri-app "A fresh Tauri 2 desktop app from the official create-tauri-app (vanilla TypeScript)" \
        "https://github.com/tauri-apps/create-tauri-app" || return 0
    need npm install-node || return 0
    need cargo install-rust || return 0
    # Tauri's own examples/api is wired into the monorepo (it builds packages/api from source), so the
    # demo is the official scaffold instead: a real native window with a Rust command behind it.
    if ! present; then
        mkdir -p "$DEMO_ROOT/$STACK"
        ( cd "$DEMO_ROOT/$STACK" && npm create --yes tauri-app@latest "$NAME" -- \
            --template vanilla-ts --manager npm --identifier studio.devdemo.tauriapp --yes > /dev/null ) \
            || { rm -rf "$DIR"; fail "create-tauri-app failed"; return 0; }
        FRESH=1
    fi
    write_run << 'EOF'
demo_need cargo install-rust
[ -d node_modules ] || npm install --no-audit --no-fund || exit 1
# WebKitGTK's DMA-BUF renderer shows a blank window on some virgl setups; the plain path is reliable.
export WEBKIT_DISABLE_DMABUF_RENDERER=1
demo_note "First run compiles the Rust side (10-15 minutes on an i3). Edit src/ and the window reloads."
npm run tauri dev
EOF
    done_demo
}

demo_android() {
    begin android-native jetnews "JetNews (Jetpack Compose sample), built with Gradle and installed on ChromeOS's Android side" \
        "https://github.com/android/compose-samples/tree/main/JetNews" || return 0
    need adb install-android-native || return 0
    fetch_subdir https://github.com/android/compose-samples.git JetNews || return 0
    write_run << 'EOF'
demo_need adb install-android-native
demo_note "Needs ChromeOS Settings > About ChromeOS > Linux development environment > Develop Android apps > Enable ADB debugging."
adb connect arc > /dev/null 2>&1
adb devices | grep -qw device || { echo "No Android device: enable ADB debugging (above), accept the prompt, and retry."; exit 1; }
demo_note "HEAVY: the first Gradle build takes 10-20 minutes and most of the RAM. Close other demos first."
./gradlew --no-daemon -Dorg.gradle.jvmargs=-Xmx2g installDebug || exit 1
adb shell monkey -p com.example.jetnews -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
demo_note "JetNews is installed: it opens now and stays in the ChromeOS launcher."
EOF
    done_demo
}

# =================================================================
# DEMOS: local AI and agents
# =================================================================

demo_gemma() {
    begin gemma ollama-python "Ollama's Python examples pointed at your local Gemma: chat, streaming, tools, structured output" \
        "https://github.com/ollama/ollama-python/tree/main/examples" || return 0
    need ollama install-gemma || return 0
    fetch_subdir https://github.com/ollama/ollama-python.git examples || return 0
    if [ "$FRESH" = 1 ]; then
        # The examples name whatever model their author had (gemma4, llama3.1, qwen3, deepseek-r1...).
        # Point every one of them at the model install-gemma pulled, so nothing extra downloads.
        sed -i -E "s/(['\"])(gemma|llama|qwen|deepseek|mistral|gpt-oss|phi)[A-Za-z0-9:._-]*\1/\1${GEMMA_MODEL}\1/g" "$DIR"/*.py
        echo "  examples now use $GEMMA_MODEL"
    fi
    write_run << 'EOF'
demo_need ollama install-gemma
PY="$HOME/.gemma-env/bin/python"; [ -x "$PY" ] || PY=(uv run --with ollama python)
curl -fs http://127.0.0.1:11434/api/version > /dev/null \
    || { echo "Ollama is not answering on :11434. Start it: sudo systemctl start ollama"; exit 1; }
demo_note "The first answer can take a few minutes while $GEMMA_MODEL loads into memory."
FEATURED=(chat-stream.py structured-outputs.py tools.py multi-tool.py chat-with-history.py thinking.py)
mapfile -t REST < <(ls ./*.py | sed 's|^\./||' | grep -vxF -f <(printf '%s\n' "${FEATURED[@]}"))
while demo_menu "Which example? (web-search*/gpt-oss* need an Ollama account key; images need a file path)" "${FEATURED[@]}" "${REST[@]}"; do
    "${PY[@]}" "$DEMO_CHOICE"
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

demo_models() {
    if begin models local-rag "Local RAG: qwen3-embedding indexes a folder of notes, qwen3.5:4b answers with sources, all on this machine" \
        "generated by dev-demo (models from install-models)"; then
        if need ollama install-models && need python3 "the base install"; then
            gen_file "$DIR/rag.py" << 'EOF'
#!/usr/bin/env python3
"""Local RAG on Ollama, with the vectors in a store of your choice.

  index DIR [--store S]   split every .md/.txt/.rst file under DIR into chunks, embed them with the
                          embedding model, save them to index.json next to this script, and load them
                          into store S
  load --store S          load the chunks of index.json into store S (no re-embedding)
  ask [--store S]         answer questions with the chat model, using the closest chunks from store S
                          as context and citing the files they came from
  stores                  which stores this machine has

Stores (--store, or RAG_STORE; default json):
  json         index.json itself, compared in Python (standard library)
  sqlite-vec   a SQLite file (rag.sqlite) with sqlite-vec's vec0 table; the extension from install-vector
               (SQLITE_VEC, default ~/.local/lib/sqlite-vec/vec0)
  qdrant       the shared Qdrant (install-qdrant), collection devdemo_rag, over its REST API
  redis        the shared Redis 8 (install-redis), index devdemo_rag on hashes rag:*; needs redis-py
  milvus-lite  Milvus Lite in a local file (rag-milvus.db), no server; needs pymilvus[milvus-lite]
  atlas-local  MongoDB Atlas Local (install-mongodb-atlas-local), a Vector Search index; needs pymongo
The launcher brings the Python packages with 'uv run --with ...' and starts a shared service first.
Logins come from the environment: QDRANT_API_KEY, REDIS_PASSWORD (the launcher reads 'devsvc password').

Models (environment variables): RAG_EMBED_MODEL (default qwen3-embedding:0.6b),
RAG_CHAT_MODEL (default qwen3.5:4b). OLLAMA_URL picks the server (default this machine's).
"""
import json
import math
import os
import pathlib
import struct
import sys
import time
import urllib.error
import urllib.request

OLLAMA = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
EMBED_MODEL = os.environ.get("RAG_EMBED_MODEL", "qwen3-embedding:0.6b")
CHAT_MODEL = os.environ.get("RAG_CHAT_MODEL", "qwen3.5:4b")
HERE = pathlib.Path(__file__).resolve().parent
INDEX = HERE / "index.json"
MAX_FILES = 300
MAX_CHUNKS = 600    # embedding runs on the CPU here: roughly a few chunks a second
SKIP_DIRS = {"node_modules", "target", "build", "dist", "vendor", "__pycache__", "venv", ".venv"}
TOP_K = 4
STORES = ["json", "sqlite-vec", "qdrant", "redis", "milvus-lite", "atlas-local"]
NAME = "devdemo_rag"


def post(path, payload, stream=False, timeout=1200):
    req = urllib.request.Request(OLLAMA + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    resp = urllib.request.urlopen(req, timeout=timeout)
    if stream:
        return (json.loads(line) for line in resp if line.strip())
    with resp:
        return json.load(resp)


def chunks(text, size=900, overlap=150):
    """Paragraph-aware chunks of about `size` characters, overlapping a little."""
    out, buf = [], ""
    for para in (p.strip() for p in text.split("\n\n")):
        if not para:
            continue
        if buf and len(buf) + len(para) > size:
            out.append(buf)
            buf = buf[-overlap:]
        buf = (buf + "\n\n" + para).strip()
    if buf:
        out.append(buf)
    return out


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    return dot / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)) or 1.0)


# ---------------------------------------------------------------- stores
# Each store: load(items, dim) puts the chunks in, search(vec, k) returns the k closest as
# [{"file": ..., "text": ...}], best first.

class JsonStore:
    def load(self, items, dim):
        pass   # index.json is the store

    def search(self, vec, k):
        items = json.loads(INDEX.read_text())["items"]
        return sorted(items, key=lambda it: cosine(vec, it["vec"]), reverse=True)[:k]


class SqliteVecStore:
    DB = HERE / "rag.sqlite"

    def connect(self):
        import sqlite3
        ext = os.environ.get("SQLITE_VEC") or str(pathlib.Path.home() / ".local/lib/sqlite-vec/vec0")
        db = sqlite3.connect(self.DB)
        try:
            db.enable_load_extension(True)
            db.load_extension(ext)
        except (AttributeError, sqlite3.OperationalError) as e:
            sys.exit(f"Cannot load sqlite-vec from {ext} ({e}): dev-setup with install-vector installs it.")
        return db

    def load(self, items, dim):
        db = self.connect()
        db.executescript("DROP TABLE IF EXISTS chunks; DROP TABLE IF EXISTS vec_chunks;")
        db.execute("CREATE TABLE chunks (id INTEGER PRIMARY KEY, file TEXT, text TEXT)")
        db.execute(f"CREATE VIRTUAL TABLE vec_chunks USING vec0(embedding float[{dim}] distance_metric=cosine)")
        for i, it in enumerate(items):
            db.execute("INSERT INTO chunks VALUES (?, ?, ?)", (i, it["file"], it["text"]))
            db.execute("INSERT INTO vec_chunks (rowid, embedding) VALUES (?, ?)", (i, json.dumps(it["vec"])))
        db.commit()
        print(f"sqlite-vec {db.execute('SELECT vec_version()').fetchone()[0]}: {len(items)} chunks in {self.DB.name}")

    def search(self, vec, k):
        db = self.connect()
        rows = db.execute("SELECT c.file, c.text FROM (SELECT rowid, distance FROM vec_chunks "
                          "WHERE embedding MATCH ? AND k = ?) v JOIN chunks c ON c.id = v.rowid "
                          "ORDER BY v.distance", (json.dumps(vec), k)).fetchall()
        return [{"file": f, "text": t} for f, t in rows]


class QdrantStore:
    URL = os.environ.get("QDRANT_URL", "http://127.0.0.1:6333")

    def call(self, method, path, body=None):
        h = {"Content-Type": "application/json"}
        if os.environ.get("QDRANT_API_KEY"):
            h["api-key"] = os.environ["QDRANT_API_KEY"]
        req = urllib.request.Request(self.URL + path, method=method, headers=h,
                                     data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404 and method == "DELETE":
                return {}
            sys.exit(f"Qdrant: {method} {path}: HTTP {e.code} {e.read().decode(errors='replace')[:300]}")
        except urllib.error.URLError as e:
            sys.exit(f"Qdrant does not answer at {self.URL} ({e.reason}): 'devsvc up qdrant' first.")

    def load(self, items, dim):
        self.call("DELETE", f"/collections/{NAME}")
        self.call("PUT", f"/collections/{NAME}", {"vectors": {"size": dim, "distance": "Cosine"}})
        for s in range(0, len(items), 128):
            pts = [{"id": i, "vector": it["vec"], "payload": {"file": it["file"], "text": it["text"]}}
                   for i, it in enumerate(items[s:s + 128], start=s)]
            self.call("PUT", f"/collections/{NAME}/points?wait=true", {"points": pts})
        n = self.call("GET", f"/collections/{NAME}")["result"]["points_count"]
        print(f"Qdrant: {n} chunks in collection {NAME}")

    def search(self, vec, k):
        r = self.call("POST", f"/collections/{NAME}/points/query", {"query": vec, "limit": k, "with_payload": True})
        return [p["payload"] for p in r["result"]["points"]]


class RedisStore:
    def connect(self):
        try:
            import redis
        except ImportError:
            sys.exit("redis-py is missing: run through the launcher, or: uv run --with redis python3 rag.py ...")
        r = redis.Redis(host="127.0.0.1", port=6379, password=os.environ.get("REDIS_PASSWORD") or None)
        try:
            mods = r.module_list()
        except redis.exceptions.ConnectionError as e:
            sys.exit(f"Redis does not answer ({e}): 'devsvc up redis' first.")
        names = set()
        for m in mods:
            n = (m.get(b"name") or m.get("name")) if isinstance(m, dict) else m[1]
            names.add((n.decode() if isinstance(n, bytes) else str(n)).lower())
        if "search" not in names:
            sys.exit("This Redis has no search module: Redis 8's image (install-redis) has it.")
        return r

    def load(self, items, dim):
        r = self.connect()
        try:
            r.execute_command("FT.DROPINDEX", NAME, "DD")
        except Exception:
            pass
        r.execute_command("FT.CREATE", NAME, "ON", "HASH", "PREFIX", "1", "rag:", "SCHEMA", "file", "TAG",
                          "text", "TEXT", "embedding", "VECTOR", "HNSW", "6", "TYPE", "FLOAT32", "DIM", str(dim),
                          "DISTANCE_METRIC", "COSINE")
        p = r.pipeline(transaction=False)
        for i, it in enumerate(items):
            p.hset(f"rag:{i}", mapping={"file": it["file"], "text": it["text"],
                                        "embedding": struct.pack(f"<{dim}f", *it["vec"])})
        p.execute()
        print(f"Redis: {len(items)} chunks in index {NAME} (hashes rag:*)")

    def search(self, vec, k):
        r = self.connect()
        res = r.execute_command("FT.SEARCH", NAME, f"*=>[KNN {k} @embedding $v AS score]", "PARAMS", "2", "v",
                                struct.pack(f"<{len(vec)}f", *vec), "SORTBY", "score", "RETURN", "2", "file", "text",
                                "DIALECT", "2")
        out = []
        for fields in res[2::2]:
            d = {fields[j].decode(): fields[j + 1].decode() for j in range(0, len(fields), 2)}
            out.append({"file": d.get("file", "?"), "text": d.get("text", "")})
        return out


class MilvusLiteStore:
    DB = HERE / "rag-milvus.db"

    def connect(self):
        try:
            from pymilvus import MilvusClient
        except ImportError:
            sys.exit("pymilvus is missing: run through the launcher, or: uv run --with 'pymilvus[milvus-lite]' python3 rag.py ...")
        return MilvusClient(str(self.DB))

    def load(self, items, dim):
        c = self.connect()
        if c.has_collection(NAME):
            c.drop_collection(NAME)
        c.create_collection(NAME, dimension=dim, metric_type="COSINE")
        c.insert(NAME, [{"id": i, "vector": it["vec"], "file": it["file"], "text": it["text"]}
                        for i, it in enumerate(items)])
        print(f"Milvus Lite: {len(items)} chunks in {self.DB.name}, collection {NAME}")

    def search(self, vec, k):
        c = self.connect()
        c.load_collection(NAME)   # a new process finds the collection released
        res = c.search(NAME, data=[vec], limit=k, output_fields=["file", "text"])
        return [{"file": h["entity"]["file"], "text": h["entity"]["text"]} for h in res[0]]


class AtlasLocalStore:
    URL = os.environ.get("ATLAS_LOCAL_URL", "mongodb://127.0.0.1:27018/?directConnection=true")

    def coll(self):
        try:
            import pymongo
        except ImportError:
            sys.exit("pymongo is missing: run through the launcher, or: uv run --with pymongo python3 rag.py ...")
        c = pymongo.MongoClient(self.URL, serverSelectionTimeoutMS=8000)
        try:
            c.admin.command("ping")
        except pymongo.errors.PyMongoError as e:
            sys.exit(f"Atlas Local does not answer at {self.URL} ({e}): 'devsvc up atlas-local' first.")
        return c["devdemo"]["rag"]

    def load(self, items, dim):
        from pymongo.operations import SearchIndexModel
        col = self.coll()
        col.drop()
        col.insert_many([{"_id": i, "file": it["file"], "text": it["text"], "embedding": it["vec"]}
                         for i, it in enumerate(items)])
        col.create_search_index(SearchIndexModel(name="rag_vec", type="vectorSearch", definition={
            "fields": [{"type": "vector", "path": "embedding", "numDimensions": dim, "similarity": "cosine"}]}))
        print("Atlas Local: waiting for the vector index (mongot builds it in the background)...", end="", flush=True)
        for _ in range(180):
            ix = [i for i in col.list_search_indexes() if i.get("name") == "rag_vec"]
            if ix and ix[0].get("queryable"):
                break
            print(".", end="", flush=True)
            time.sleep(2)
        print(f"\nAtlas Local: {len(items)} chunks in devdemo.rag, vector index rag_vec")

    def search(self, vec, k):
        pipe = [{"$vectorSearch": {"index": "rag_vec", "path": "embedding", "queryVector": vec,
                                   "numCandidates": k * 10, "limit": k}},
                {"$project": {"_id": 0, "file": 1, "text": 1}}]
        return list(self.coll().aggregate(pipe))


def store(name):
    cls = {"json": JsonStore, "sqlite-vec": SqliteVecStore, "qdrant": QdrantStore, "redis": RedisStore,
           "milvus-lite": MilvusLiteStore, "atlas-local": AtlasLocalStore}.get(name)
    if not cls:
        sys.exit(f"Unknown store '{name}': {' '.join(STORES)}")
    return cls()


# ---------------------------------------------------------------- commands
def index(docs_dir, store_name):
    docs = pathlib.Path(docs_dir).expanduser().resolve()
    if not docs.is_dir():
        sys.exit(f"Not a folder: {docs}")
    # Walk with pruning, so a tree full of node_modules or build output is never read at all.
    files = []
    for root, dirs, names in os.walk(docs):
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS)
        files += [pathlib.Path(root) / n for n in sorted(names) if n.lower().endswith((".md", ".txt", ".rst"))]
        if len(files) >= MAX_FILES:
            print(f"Stopping at {MAX_FILES} files.")
            files = files[:MAX_FILES]
            break
    items = [{"file": str(f.relative_to(docs)), "text": c}
             for f in files for c in chunks(f.read_text(errors="ignore"))]
    if not items:
        sys.exit(f"No .md/.txt/.rst files under {docs}")
    if len(items) > MAX_CHUNKS:
        print(f"{len(items)} chunks; indexing the first {MAX_CHUNKS} (pick a smaller folder for all of it).")
        items = items[:MAX_CHUNKS]
    print(f"Embedding {len(items)} chunks from {len(files)} files with {EMBED_MODEL}...")
    vecs = []
    for k in range(0, len(items), 16):
        batch = [it["text"] for it in items[k:k + 16]]
        vecs += post("/api/embed", {"model": EMBED_MODEL, "input": batch, "keep_alive": "1m"})["embeddings"]
        print(f"  {min(k + 16, len(items))}/{len(items)}", end="\r", flush=True)
    for it, v in zip(items, vecs):
        it["vec"] = v
    INDEX.write_text(json.dumps({"docs": str(docs), "embed_model": EMBED_MODEL, "items": items}))
    print(f"\nIndex of {docs} written to {INDEX}")
    load(store_name)


def load(store_name):
    if not INDEX.exists():
        sys.exit("No index yet: run with 'index <folder>' first.")
    items = json.loads(INDEX.read_text())["items"]
    store(store_name).load(items, len(items[0]["vec"]))
    (HERE / ".store").write_text(store_name)


def ask(store_name):
    if not INDEX.exists():
        sys.exit("No index yet: run with 'index <folder>' first.")
    data = json.loads(INDEX.read_text())
    loaded = (HERE / ".store").read_text().strip() if (HERE / ".store").exists() else "json"
    if store_name not in ("json", loaded):
        print(f"(the index was last loaded into {loaded}; loading it into {store_name} first)")
        load(store_name)
    st = store(store_name)
    print(f"{len(data['items'])} chunks from {data['docs']}, store {store_name}. Chat model: {CHAT_MODEL}. "
          "Empty line or Ctrl-D quits.")
    while True:
        try:
            q = input("\nQuestion: ").strip()
        except EOFError:
            print()
            return
        if not q:
            return
        qv = post("/api/embed", {"model": data["embed_model"], "input": [q], "keep_alive": "1m"})["embeddings"][0]
        t0 = time.perf_counter()
        best = st.search(qv, TOP_K)
        ms = (time.perf_counter() - t0) * 1000
        context = "\n\n".join(f"[{i + 1}] ({it['file']})\n{it['text']}" for i, it in enumerate(best))
        messages = [
            {"role": "system", "content": "Answer from the numbered sources only, citing them like [1]. "
                                          "If the sources do not contain the answer, say so."},
            {"role": "user", "content": f"Sources:\n{context}\n\nQuestion: {q}"},
        ]
        print(f"(sources from {store_name} in {ms:.0f} ms: {', '.join(dict.fromkeys(it['file'] for it in best))})\n")
        payload = {"model": CHAT_MODEL, "messages": messages, "stream": True, "think": False}
        try:
            for part in post("/api/chat", payload, stream=True):
                if "error" in part:
                    print(f"\n[Ollama: {part['error']}]", end="")
                print(part.get("message", {}).get("content", ""), end="", flush=True)
        except urllib.error.HTTPError as e:
            if e.code != 400:
                raise
            payload.pop("think")  # a chat model without a thinking switch rejects "think"
            for part in post("/api/chat", payload, stream=True):
                if "error" in part:
                    print(f"\n[Ollama: {part['error']}]", end="")
                print(part.get("message", {}).get("content", ""), end="", flush=True)
        print()


def stores():
    home = pathlib.Path.home()
    print("json         always")
    vec = os.environ.get("SQLITE_VEC") or str(home / ".local/lib/sqlite-vec/vec0")
    print(f"sqlite-vec   {'yes' if pathlib.Path(vec + '.so').exists() else 'no (install-vector)'}")
    print("qdrant       the shared Qdrant (install-qdrant)")
    print("redis        the shared Redis 8 (install-redis)")
    print("milvus-lite  a local file; the launcher brings pymilvus")
    print("atlas-local  MongoDB Atlas Local (install-mongodb-atlas-local)")


def main():
    args = sys.argv[1:]
    store_name = os.environ.get("RAG_STORE", "json")
    if "--store" in args:
        i = args.index("--store")
        if i + 1 >= len(args):
            sys.exit("--store needs a name: " + " ".join(STORES))
        store_name = args[i + 1]
        del args[i:i + 2]
    if store_name not in STORES:
        sys.exit(f"Unknown store '{store_name}': {' '.join(STORES)}")
    if len(args) >= 2 and args[0] == "index":
        index(args[1], store_name)
    elif args[:1] == ["load"]:
        load(store_name)
    elif args[:1] == ["ask"]:
        ask(store_name)
    elif args[:1] == ["stores"]:
        stores()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
EOF
            gen_file "$DIR/docs/run-order.md" << 'EOF'
# Run order of the Chromebook bundle

The bundle is four scripts that take the same flags: dev-setup installs, dev-init applies logins and
keys from ~/.config/dev-init/secrets.env, dev-test verifies, and dev-demo downloads hands-on demos.

The order is init, setup, init again, then test. The first init run only writes the secrets template.
Setup never prompts. The test reports every login as a WARN until init has applied secrets.env.

All four scripts share one version number: a change to any of them bumps all four.
EOF
            gen_file "$DIR/docs/memory.md" << 'EOF'
# Memory on an 8 GB Chromebook

The Linux VM sees about 6.4 GB of the 8 GB. ChromeOS's memory balloon shows up as "used" in free,
so judge headroom by the "available" column.

Run one heavy thing at a time: an Ollama model, a kind cluster (about 2 GB), self-hosted Langfuse
(about 3 GB), SQL Server or Oracle (about 2 GB each), or an Android Gradle build. 'ollama stop <model>'
gives a model's memory back at once; otherwise Ollama unloads it after 5 idle minutes. 'mssql down'
and 'oracle down' stop the database servers.
EOF
            gen_file "$DIR/docs/ollama.md" << 'EOF'
# Ollama in the bundle

install-ollama installs the server with a systemd drop-in: a 15-minute load timeout, at most two
models loaded (Ollama loads a second one only when both fit), one request per model, an 8192-token default context, flash attention and a q8_0 KV cache.
Change a value with 'sudo systemctl edit ollama', which writes an override that wins.

Inference is CPU-only in Crostini, because the container exposes OpenGL through virgl but no CUDA,
ROCm or Vulkan. 'ollama ps' shows 100% CPU for every model.

OLLAMA_REMOTE in secrets.env points the 'ollama-remote' command at a bigger machine's Ollama, for
models that do not fit here. Plain 'ollama' always stays on this machine.
EOF
            gen_file "$DIR/docs/models.md" << 'EOF'
# Models pulled by install-models

deepseek-r1:1.5b (1.1 GB) is DeepSeek-R1 distilled into a 1.5B Qwen model, and the DeepSeek that
fits on these Chromebooks. It reasons before answering; '--think=false' makes it answer directly.
DeepSeek's current V4 models are about 760B parameters and run only as Ollama cloud models, such as
deepseek-v4.1-flash:cloud, after 'ollama signin'. They are billed per token.

qwen3.5:4b (3.4 GB) handles text and images, calls tools and can think. It is the chat model of this
RAG demo. qwen3-embedding:0.6b (639 MB) turns text into vectors for search; it cannot chat.

OLLAMA_EXTRA_MODELS="deepseek-r1:7b" adds models on the next setup run. A 7B model (4.7 GB) loads
only with nothing else running.
EOF
            gen_file "$DIR/docs/flags.md" << 'EOF'
# Which flag installs what

install-all covers every stack except the opt-in flags: install-models, install-godot-templates,
install-asm-arm, install-ansible-core, install-db-server, install-oracle-full, install-ldap,
install-ldap-full, install-ollama-containers, install-lan, install-lan-share, install-com,
install-retro, install-hermes, install-openclaw, install-elasticsearch, install-milvus,
install-mongodb-atlas-local and install-cloudflared. Since v89 install-all also runs shared services
in Docker through one 'devsvc' command: install-cache (Redis 8, Memcached), install-search (Solr 9.10,
OpenSearch, Meilisearch, Typesense), install-vector (Qdrant, and sqlite-vec for sqlite3) and
install-mongodb (MongoDB 8 with mongosh and Compass). Only Redis and Memcached start with Linux; the
others start with 'devsvc up NAME'. install-cloud gains install-cloudflare (wrangler), and
install-agentic gains FastMCP's CLI and the MCP Inspector. install-k8s installs kubectl, helm, kind and k9s.
install-com sets up COM development under Wine and install-retro DOS and old Windows (DOSBox-X for
Windows 3.1 and 95, QEMU for NT 4.0 and 2000, a Wine prefix for Delphi 1, Open Watcom). install-hermes and install-openclaw install the personal agents Hermes Agent and OpenClaw;
they need a model with a 64K-token context, so a cloud key or a bigger machine's Ollama. install-lan gives every laptop an address book and the 'lan' command;
install-lan-share lets this one share Ollama, the databases, LDAP, DDEV sites and dev servers.
install-ldap runs lldap, a small LDAP directory in Docker; install-ldap-full adds OpenLDAP (slapd).
install-db-server installs the database servers: SQL Server 2025 and Oracle 26ai Free in Docker
(install-mssql, install-oracle) and Embarcadero InterBase (install-interbase). install-oracle-full
runs Oracle on its full image instead of the Lite one (about 9.5 GB on disk against 1.8 GB).
install-iac installs Terraform, tflint, Bicep (with the Azure CLI) and the full Ansible package.
install-agentic installs Temporal, LangGraph, Pydantic and Langfuse. install-gemma installs Gemma 4
with the hybrid 'gemma' client and pulls in install-ollama. Since v90 install-graphql installs Apollo's
GraphQL tools: Rover, the Apollo Router (v2) and the Apollo MCP Server; local federation needs no account.
EOF
            write_run << 'EOF'
demo_need ollama install-models
curl -fs http://127.0.0.1:11434/api/version > /dev/null \
    || { echo "Ollama is not answering on :11434. Start it: sudo systemctl start ollama"; exit 1; }
for m in "${RAG_EMBED_MODEL:-qwen3-embedding:0.6b}" "${RAG_CHAT_MODEL:-qwen3.5:4b}"; do
    ollama list | awk 'NR > 1 {print $1}' | grep -qxF "$m" || { echo "Missing $m: rerun dev-setup with install-models (or ollama pull $m)."; exit 1; }
done
# v89: the vectors can live in another store. RAG_STORE picks it for 'ask' and 'folder' (default json);
# the 'store' item picks one from the stores this machine has.
STORE=${RAG_STORE:-json}
svc_up() {   # svc_up NAME: start a shared service for a store (it keeps running afterwards)
    command -v devsvc > /dev/null 2>&1 || { echo "The $1 store needs the shared services: dev-setup with install-$1."; return 1; }
    # One start; on failure its output (the memory guard's advice, or the service's last log lines) is shown.
    [ "$(docker inspect -f '{{.State.Running}}' "devsvc-$1" 2> /dev/null)" = true ] \
        || demo_note "Starting $1 (Solr, OpenSearch, Elasticsearch and Atlas Local take a minute or two)..."
    local out; out=$(devsvc up "$1" 2>&1) || { printf '%s\n' "$out"; return 1; }
    grep '^Stopping' <<< "$out"
    demo_note "$1 is running and stays running ('devsvc down $1' when you are done)."
}
# rag STORE ARGS...: rag.py with the Python package and the shared service STORE needs
rag() {
    local s=$1; shift
    case "$s" in
        qdrant)      svc_up qdrant || return 1
                     QDRANT_API_KEY=$(devsvc password qdrant 2> /dev/null) python3 rag.py "$@" --store qdrant ;;
        redis)       svc_up redis || return 1
                     REDIS_PASSWORD=$(devsvc password redis 2> /dev/null) uv run --no-project --with redis python3 rag.py "$@" --store redis ;;
        milvus-lite) demo_need uv "the base install"
                     uv run --no-project --with 'pymilvus[milvus-lite]' python3 rag.py "$@" --store milvus-lite ;;
        atlas-local) svc_up atlas-local || return 1
                     uv run --no-project --with pymongo python3 rag.py "$@" --store atlas-local ;;
        *)           python3 rag.py "$@" --store "$s" ;;
    esac
}
stores_here() {
    local s
    echo "json: index.json, compared in Python"
    [ -f "$HOME/.local/lib/sqlite-vec/vec0.so" ] && echo "sqlite-vec: a SQLite file with sqlite-vec (install-vector)"
    for s in qdrant redis atlas-local; do
        docker container inspect "devsvc-$s" > /dev/null 2>&1 || continue
        case "$s" in
            qdrant)      echo "qdrant: the shared Qdrant (starts it)" ;;
            redis)       echo "redis: the shared Redis 8, vector search on hashes (starts it)" ;;
            atlas-local) echo "atlas-local: MongoDB Atlas Local, a Vector Search index (starts it; ~2 GB)" ;;
        esac
    done
    command -v uv > /dev/null 2>&1 && echo "milvus-lite: Milvus Lite in a local file, no server (first use downloads pymilvus)"
}
demo_note "Try: 'How much memory does the Linux VM see?' or 'Which DeepSeek model fits here?'"
demo_note "The embedding and chat models stay loaded side by side when memory allows (setup allows two);"
demo_note "when it does not, Ollama swaps them per question, which is slower. Close Chrome tabs to help."
while demo_menu "Local RAG, vectors in: $STORE (the chat model takes a minute to load the first time)" \
        "ask: questions about this bundle (sample notes in docs/)" \
        "folder: index a folder of your own .md/.txt files, then ask" \
        "store: pick another vector store this machine has (sqlite-vec, Qdrant, Redis, Milvus Lite, Atlas Local) and ask"; do
    case "$DEMO_CHOICE" in
        ask*)    rag "$STORE" index "$DEMO_DIR/docs" && rag "$STORE" ask ;;
        folder*) read -rep "Folder to index (up to 300 files / 600 chunks): " -i "$HOME/dev-demo" f || continue
                 f="${f/#\~/$HOME}"
                 rag "$STORE" index "$f" && rag "$STORE" ask ;;
        store*)  mapfile -t S < <(stores_here)
                 demo_menu "Vector store (the same chunks; no re-embedding)" "${S[@]}" || continue
                 STORE=${DEMO_CHOICE%%:*}
                 [ -f index.json ] || rag json index "$DEMO_DIR/docs" || continue
                 rag "$STORE" load && rag "$STORE" ask ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
            done_demo
        fi
    fi

    begin models compare "The same prompt through every local model, one at a time: load time, tokens per second, answer" \
        "generated by dev-demo" || return 0
    need python3 "the base install" || return 0
    gen_file "$DIR/compare.py" << 'EOF'
#!/usr/bin/env python3
"""Send one prompt to several Ollama models, one at a time, and compare load time, speed and answer.

  compare.py [--prompt TEXT] [MODEL ...]     no models = every chat model on the server

OLLAMA_URL picks the server, so the same run on another machine's Ollama compares hardware too.
Each model is unloaded right after its answer, so only one is ever in memory.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

OLLAMA = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")


def post(path, payload, timeout=1800):
    req = urllib.request.Request(OLLAMA + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def get(path):
    with urllib.request.urlopen(OLLAMA + path, timeout=30) as r:
        return json.load(r)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--prompt", default="In two sentences: why does a small language model run slower on a laptop CPU than on a GPU?")
    ap.add_argument("models", nargs="*")
    a = ap.parse_args()
    tags = get("/api/tags")["models"]
    sizes = {m["name"]: m.get("size", 0) for m in tags}
    models = a.models or [m["name"] for m in tags
                          if "embed" not in m["name"] and not m["name"].endswith(("-cloud", ":cloud"))]
    if not models:
        sys.exit(f"No chat models on {OLLAMA}")
    print(f"Server: {OLLAMA}   prompt: {a.prompt}\n")
    rows = []
    for name in models:
        print(f"== {name} ({sizes.get(name, 0) / 1e9:.1f} GB) ...", flush=True)
        payload = {"model": name, "messages": [{"role": "user", "content": a.prompt}],
                   "stream": False, "think": False, "keep_alive": 0, "options": {"num_predict": 160}}
        t0 = time.time()
        try:
            try:
                r = post("/api/chat", payload)
            except urllib.error.HTTPError as e:
                if e.code != 400:
                    raise
                payload.pop("think")  # models without a thinking switch reject "think"
                r = post("/api/chat", payload)
        except Exception as e:  # keep going with the next model
            print(f"   failed: {e}\n")
            rows.append((name, None, None, None))
            continue
        load = r.get("load_duration", 0) / 1e9
        tps = r.get("eval_count", 0) / (r.get("eval_duration", 0) / 1e9 or 1)
        answer = " ".join(r.get("message", {}).get("content", "").split())
        print(f"   {time.time() - t0:.0f}s total, {load:.0f}s loading, {tps:.1f} tokens/s")
        print(f"   {answer[:400]}\n")
        rows.append((name, load, tps, r.get("eval_count", 0)))
    print(f"{'model':<36} {'load s':>7} {'tok/s':>7} {'tokens':>7}")
    for name, load, tps, n in rows:
        if load is None:
            print(f"{name:<36} {'failed':>7}")
        else:
            print(f"{name:<36} {load:>7.0f} {tps:>7.1f} {n:>7}")


if __name__ == "__main__":
    main()
EOF
    FRESH=1
    write_run << 'EOF'
# 'remote' as the argument runs the comparison on OLLAMA_REMOTE's server instead (a hardware comparison).
if [ "${1:-}" = remote ]; then
    [ -n "${OLLAMA_REMOTE:-}" ] || { echo "Set OLLAMA_REMOTE in ~/.config/dev-init/secrets.env first."; exit 1; }
    case "$OLLAMA_REMOTE" in http://*|https://*) OLLAMA_URL=$OLLAMA_REMOTE ;; *) OLLAMA_URL="http://$OLLAMA_REMOTE" ;; esac
    _hp=${OLLAMA_URL#*://}; _hp=${_hp%%/*}   # v84: a laptop name or bare address means Ollama's port, 11434
    case "$_hp" in *:*) ;; *) OLLAMA_URL="${OLLAMA_URL%%://*}://$_hp:11434" ;; esac
    export OLLAMA_URL
    shift
else
    demo_need ollama install-ollama
    curl -fs http://127.0.0.1:11434/api/version > /dev/null \
        || { echo "Ollama is not answering on :11434. Start it: sudo systemctl start ollama"; exit 1; }
fi
demo_note "One model at a time; each is unloaded after its answer. A cold load of a 3-4 GB model takes minutes here."
python3 compare.py "$@"
demo_note "Your own prompt: $0 --prompt 'Explain DuckLake in one sentence'   Other machine: $0 remote"
EOF
    done_demo
}

demo_agentic() {
    if begin agentic temporal-ai-agent "Temporal's durable AI agent: multi-turn chat with tools and confirmations; kill the worker and it resumes" \
        "https://github.com/temporal-community/temporal-ai-agent"; then
        if need temporal install-agentic && need uv "the base install" && fetch_repo https://github.com/temporal-community/temporal-ai-agent.git; then
            if [ ! -f "$DIR/.env" ]; then
                # Local Gemma through Ollama by default; the mock tool data needs no keys.
                sed -e "s|^LLM_MODEL=.*|LLM_MODEL=ollama/${GEMMA_MODEL}\nLLM_BASE_URL=http://127.0.0.1:11434|" \
                    -e 's|^LLM_KEY=.*|LLM_KEY=|' -e 's|^STRIPE_API_KEY=.*|STRIPE_API_KEY=|' \
                    "$DIR/.env.example" > "$DIR/.env"
                cat >> "$DIR/.env" << 'EOF'

# dev-demo: runs on the local Gemma. A small local model can fumble the tool-calling JSON; for a
# smoother run use a hosted model instead, e.g.
#   LLM_MODEL=anthropic/claude-sonnet-4-5   and   LLM_KEY=<your ANTHROPIC_API_KEY>
# (then remove LLM_BASE_URL).
EOF
                echo "  wrote .env for the local Gemma model (edit it to use a hosted model)"
            fi
            write_run << 'EOF'
demo_need temporal install-agentic
demo_need uv "the base install"
demo_need npm install-node
grep -q '^LLM_BASE_URL=http://127.0.0.1:11434' .env && ! curl -fs http://127.0.0.1:11434/api/version > /dev/null \
    && demo_note "Ollama is not answering: sudo systemctl start ollama (or switch .env to a hosted model)."
demo_step "Temporal dev server (Web UI on :8233)"
demo_bg temporal temporal server start-dev --ui-port 8233 --log-level warn
demo_wait_port 7233 60 || exit 1
demo_step "Python deps, worker and API"
uv sync -q || exit 1
demo_bg agent-worker uv run scripts/run_worker.py
demo_bg agent-api uv run uvicorn api.main:app --host 127.0.0.1 --port 8000
demo_step "Chat UI (React + Vite)"
( cd frontend && { [ -d node_modules ] || npm install --no-audit --no-fund; } ) || exit 1
demo_open_when_ready 8233 http://localhost:8233
demo_open_when_ready 5173 http://localhost:5173
demo_note "Chat on :5173; watch every LLM call and tool step as workflow history on :8233."
demo_note "Try it: kill the worker mid-conversation (pkill -f run_worker.py), then start it again. Ctrl-C stops all."
cd frontend && npx vite --port 5173 --strictPort
EOF
            done_demo
        fi
    fi

    if begin agentic local-deep-researcher "LangGraph research agent on your local Gemma: searches, reflects, loops, writes a sourced summary" \
        "https://github.com/langchain-ai/local-deep-researcher"; then
        if need uv "the base install" && fetch_repo https://github.com/langchain-ai/local-deep-researcher.git; then
            if [ ! -f "$DIR/.env" ]; then
                sed -e "s|^SEARCH_API=.*|SEARCH_API='duckduckgo'|" -e 's|^LLM_PROVIDER=.*|LLM_PROVIDER=ollama|' \
                    -e "s|^LOCAL_LLM=.*|LOCAL_LLM=${GEMMA_MODEL}|" \
                    -e 's/^\(TAVILY_API_KEY\|PERPLEXITY_API_KEY\)=/# &/' \
                    "$DIR/.env.example" > "$DIR/.env"
                echo "  wrote .env: Ollama + $GEMMA_MODEL, DuckDuckGo search (no keys)"
            fi
            write_run << 'EOF'
demo_need uvx "the base install (uv)"
curl -fs http://127.0.0.1:11434/api/version > /dev/null \
    || { echo "Ollama is not answering on :11434. Start it: sudo systemctl start ollama"; exit 1; }
demo_note "LangGraph Studio opens on smith.langchain.com and talks to the server on :2024 on this machine"
demo_note "(it may ask you to sign in to LangSmith; the free tier is enough). Give it a topic in the 'research_topic' field."
demo_note "If the browser does not open: https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024"
uvx --refresh --from "langgraph-cli[inmem]" --with-editable . --python 3.11 langgraph dev
EOF
            done_demo
        fi
    fi

    begin agentic langfuse "Langfuse (self-hosted LLM tracing) from the compose file install-agentic fetched, on :3000" \
        "https://github.com/langfuse/langfuse (docker-compose.yml)" || return 0
    need docker "the base install" || return 0
    mkdir -p "$DIR"
    write_run << 'EOF'
docker_ok
F="$HOME/agentic/langfuse/docker-compose.yml"
if [ ! -f "$F" ]; then
    F="$DEMO_DIR/docker-compose.yml"
    [ -f "$F" ] || curl -fsSL https://raw.githubusercontent.com/langfuse/langfuse/main/docker-compose.yml -o "$F" || exit 1
fi
demo_note "HEAVY: Postgres, ClickHouse, Redis, MinIO and two Langfuse services (~3 GB of RAM)."
if command -v ollama > /dev/null && ollama ps 2> /dev/null | grep -q .; then
    demo_note "Unloading the Gemma model to make room (it reloads on its next request)."
    ollama stop "$GEMMA_MODEL" 2> /dev/null
fi
COMPOSE=(docker compose -f "$F" -p devdemo-langfuse)
demo_on_exit "docker compose -f '$F' -p devdemo-langfuse stop"
"${COMPOSE[@]}" up -d || exit 1
demo_wait_port 3000 300 && demo_open http://localhost:3000
demo_note "Sign up locally (the account lives in this Postgres), create a project, and copy its keys into"
demo_note "LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY / LANGFUSE_HOST=http://localhost:3000 for your agents."
demo_note "Ctrl-C stops the containers (data is kept; 'docker compose -p devdemo-langfuse down -v' wipes it)."
"${COMPOSE[@]}" logs -f --tail 3 langfuse-web
EOF
    done_demo
}

# =================================================================
# DEMOS: data
# =================================================================

demo_lakehouse() {
    if begin lakehouse jaffle-shop "dbt's jaffle_shop on DuckDB: seeds, models and tests in seconds, then the dbt docs site" \
        "https://github.com/dbt-labs/jaffle_shop_duckdb"; then
        if [ ! -x "$HOME/.lakehouse-env/bin/dbt" ]; then
            echo "  ${YEL}skip${RST}: needs ~/.lakehouse-env/bin/dbt (dev-setup with install-lakehouse)"
            SKIPPED+=("$STACK/$NAME: needs ~/.lakehouse-env (install-lakehouse)")
        else
            if fetch_repo https://github.com/dbt-labs/jaffle_shop_duckdb.git; then
                write_run << 'EOF'
DBT="$HOME/.lakehouse-env/bin/dbt"      # classic dbt Core + dbt-duckdb (Fusion's 'dbt' is a different engine)
[ -x "$DBT" ] || { echo "Needs ~/.lakehouse-env (dev-setup with install-lakehouse)."; exit 1; }
export DBT_PROFILES_DIR="$DEMO_DIR"
demo_step "dbt build (seeds, models, tests)"
"$DBT" build || exit 1
demo_step "Query the result with the DuckDB CLI"
duckdb jaffle_shop.duckdb -c "select first_name, last_name, number_of_orders, customer_lifetime_value from customers order by customer_lifetime_value desc nulls last limit 5"
demo_step "dbt docs (lineage graph) on :8580"
"$DBT" docs generate > /dev/null || exit 1
demo_open_when_ready 8580 http://localhost:8580
"$DBT" docs serve --port 8580 --no-browser
EOF
                done_demo
            fi
        fi
    fi

    begin lakehouse duckdb-tour "DuckDB tour: 3M NYC taxi trips over HTTPS, DuckLake and Delta Lake snapshots + time travel, the DuckDB UI" \
        "generated by dev-demo (data: NYC TLC trip records)" || return 0
    need duckdb install-lakehouse || return 0
    gen_file "$DIR/taxi.sql" << 'EOF'
-- 3 million NYC yellow-cab trips (January 2024), fetched once from the NYC TLC over HTTPS into taxi.duckdb.
.timer on
INSTALL httpfs; LOAD httpfs;
CREATE TABLE IF NOT EXISTS trips AS
    SELECT * FROM read_parquet('https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet');
SELECT count(*) AS trips, round(sum(total_amount) / 1e6, 1) AS revenue_musd FROM trips;
SELECT hour(tpep_pickup_datetime) AS pickup_hour, count(*) AS trips,
       round(avg(trip_distance), 2) AS avg_miles, round(avg(fare_amount), 2) AS avg_fare,
       round(avg(tip_amount), 2) AS avg_tip
FROM trips GROUP BY ALL ORDER BY pickup_hour;
SUMMARIZE SELECT trip_distance, fare_amount, tip_amount, passenger_count FROM trips;
EOF
    gen_file "$DIR/ducklake.sql" << 'EOF'
-- DuckLake: a lakehouse table format whose catalog is a database. Every change is a snapshot you can query.
INSTALL ducklake; LOAD ducklake;
ATTACH 'ducklake:lake/metadata.ducklake' AS lake (DATA_PATH 'lake/data/');
USE lake;
CREATE TABLE flights (id INTEGER, airport VARCHAR, delay_min INTEGER);
INSERT INTO flights VALUES (1, 'DCA', 5), (2, 'IAD', 42), (3, 'BWI', 0);
UPDATE flights SET delay_min = 90 WHERE airport = 'IAD';
DELETE FROM flights WHERE airport = 'BWI';
SELECT 'now' AS as_of, * FROM flights;
SELECT * FROM ducklake_snapshots('lake');
SELECT 'version 2' AS as_of, * FROM flights AT (VERSION => 2);
EOF
    # v79: Delta Lake, the format Databricks and Spark write. delta-rs creates the table and does the
    # UPDATE and DELETE (DuckDB writes Delta INSERT-only); DuckDB appends, reads and time-travels.
    gen_file "$DIR/delta.py" << 'EOF'
#!/usr/bin/env python3
"""Delta Lake without Spark: delta-rs (the 'deltalake' package) creates and changes a table, DuckDB's
delta extension reads it, appends to it and time-travels through it. Run with ~/.lakehouse-env's python.

  delta.py [DIR]     builds a fresh table in DIR (default delta/flights)
"""
import os
import pathlib
import shutil
import sys

try:
    import duckdb
    import pyarrow as pa
    from deltalake import DeltaTable, write_deltalake
except ImportError as e:
    sys.exit(f"{e}: run with ~/.lakehouse-env/bin/python, and rerun dev-setup with install-lakehouse (v79+) for deltalake.")

path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "delta/flights").resolve()
shutil.rmtree(path, ignore_errors=True)
path.parent.mkdir(parents=True, exist_ok=True)


def step(title):
    print(f"\n== {title} ==")


step("delta-rs: create the table (version 0)")
write_deltalake(str(path), pa.table({"id": [1, 2, 3], "airport": ["DCA", "IAD", "BWI"], "delay_min": [5, 42, 0]}))

step("delta-rs: IAD's delay becomes 90 (version 1), BWI is deleted (version 2)")
dt = DeltaTable(str(path))
dt.update(predicate="airport = 'IAD'", updates={"delay_min": "90"})
dt.delete("airport = 'BWI'")

con = duckdb.connect()
con.execute("LOAD delta")
con.execute(f"ATTACH '{path}' AS flights (TYPE delta)")

step("DuckDB: append a row with INSERT (version 3)")
try:
    con.execute("INSERT INTO flights VALUES (4, 'RIC', 12)")
except duckdb.Error as e:
    print(f"DuckDB could not append ({e}); its Delta writes are recent, so update duckdb with dev-setup install-lakehouse.")

step("DuckDB: the table now")
con.sql("SELECT * FROM flights ORDER BY id").show()

step("DuckDB: time travel to version 0, before any change")
con.sql("SELECT * FROM flights AT (VERSION => 0) ORDER BY id").show()

step("delta-rs: the commit log (newest first; every write is a JSON file in _delta_log/)")
for h in DeltaTable(str(path)).history():
    op = h.get("operation")
    print(f"  version {h.get('version', '?')}: {op if op and op != 'UNKNOWN' else 'append (DuckDB INSERT)'}")

step("on disk")
for root, _, files in sorted(os.walk(path)):
    for f in sorted(files):
        print("  " + os.path.relpath(os.path.join(root, f), path.parent))
print(f"\nParquet data files plus JSON commits under {path}.")
print("Spark, Databricks, Polars and Snowflake read this table as it is: that is what Delta Lake is for.")
# After a DuckDB INSERT into a Delta table the process sometimes aborts in teardown ("terminate called
# without an active exception") once everything is done; os._exit skips that teardown.
sys.stdout.flush()
os._exit(0)
EOF
    FRESH=1
    write_run << 'EOF'
demo_need duckdb install-lakehouse
while demo_menu "DuckDB tour" "taxi: 3M trips over HTTPS (first run downloads ~50 MB)" \
        "ducklake: snapshots and time travel (starts a fresh lake each time)" \
        "delta: a Delta Lake table: delta-rs writes, DuckDB reads, appends and time-travels" \
        "ui: the DuckDB UI in the browser on :4213 (on taxi.duckdb)"; do
    case "$DEMO_CHOICE" in
        taxi*)     duckdb taxi.duckdb < taxi.sql ;;
        ducklake*) rm -rf lake && mkdir -p lake/data && duckdb < ducklake.sql && tree -L 2 lake 2> /dev/null ;;
        delta*)    [ -x "$HOME/.lakehouse-env/bin/python" ] || { echo "Needs ~/.lakehouse-env (dev-setup with install-lakehouse)."; continue; }
                   "$HOME/.lakehouse-env/bin/python" delta.py delta/flights ;;
        ui*)       demo_note "Type .exit (or Ctrl-D) to stop the UI."; duckdb -ui taxi.duckdb ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

demo_db() {
    begin db chinook "Chinook music store in SQLite, Postgres, MariaDB and SQL Server 2025, queried over ODBC; Northwind .mdb via mdbtools" \
        "https://github.com/lerocha/chinook-database + https://github.com/mdbtools/mdbtestdata" || return 0
    if ! present; then
        fetch_subdir https://github.com/lerocha/chinook-database.git ChinookDatabase/DataSources || return 0
        find "$DIR" -type f ! -name 'Chinook_Sqlite.sqlite' ! -name 'Chinook_PostgreSql.sql' \
            ! -name 'Chinook_MySql.sql' ! -name 'Chinook_SqlServer.sql' ! -name '.dev-demo-source' -delete
        local tmp; tmp=$(mktemp -d "$CACHE/sparse.XXXXXX")
        if git clone -q --depth 1 --filter=blob:none --sparse https://github.com/mdbtools/mdbtestdata.git "$tmp/r" \
            && git -C "$tmp/r" sparse-checkout set data > /dev/null && [ -f "$tmp/r/data/nwind.mdb" ]; then
            cp "$tmp/r/data/nwind.mdb" "$DIR/"
        else
            echo "  ${YEL}note${RST}: could not fetch nwind.mdb; the Access item will be missing"
        fi
        rm -rf "$tmp"
    fi
    # install-db's ODBC driver for Access files does not bring the mdb-* command-line tools.
    has install-db && { apt_need mdbtools || echo "  ${YEL}note${RST}: could not install mdbtools; the Access item will not work"; }
    write_run << 'EOF'
# Top-10 artists by sales: the same question in each engine's naming (Postgres's script is snake_case).
Q_PASCAL="SELECT ar.Name, ROUND(SUM(il.UnitPrice * il.Quantity), 2) AS Sales FROM InvoiceLine il JOIN Track t ON t.TrackId = il.TrackId JOIN Album al ON al.AlbumId = t.AlbumId JOIN Artist ar ON ar.ArtistId = al.ArtistId GROUP BY ar.Name ORDER BY Sales DESC"
Q_SNAKE="SELECT ar.name, ROUND(SUM(il.unit_price * il.quantity), 2) AS sales FROM invoice_line il JOIN track t ON t.track_id = il.track_id JOIN album al ON al.album_id = t.album_id JOIN artist ar ON ar.artist_id = al.artist_id GROUP BY ar.name ORDER BY sales DESC"
have_driver() { odbcinst -q -d 2> /dev/null | grep -qF "[$1]"; }
odbc() {   # odbc DRIVER CONNSTR SQL: run one statement through unixODBC's isql
    if have_driver "$1"; then
        echo "-- via ODBC driver [$1]"
        echo "$3" | isql -b -k "DRIVER={$1};$2"
    else
        echo "(ODBC driver [$1] not registered: run dev-setup with install-db-extra / install-db)"; return 1
    fi
}
start_db() {   # start_db NAME PORT IMAGE ENV... : one container per engine, removed when you leave the demo
    docker_ok
    docker rm -f "$1" > /dev/null 2>&1
    demo_on_exit "docker rm -f $1"
    docker run -d --name "$1" -p "$2" "${@:4}" "$3" > /dev/null || return 1
}
while demo_menu "Chinook everywhere" \
        "sqlite: sqlite3 CLI, then the same query over ODBC" \
        "postgres: Postgres 17 in Docker, load, query via ODBC" \
        "mariadb: MariaDB 11 in Docker, load, query via ODBC" \
        "sqlserver: SQL Server 2025 (HEAVY: 2 GB RAM), query via ODBC Driver 18" \
        "access: Northwind .mdb with mdbtools (tables, CSV export, SQL)"; do
    case "$DEMO_CHOICE" in
    sqlite*)
        demo_step "sqlite3"
        sqlite3 -box Chinook_Sqlite.sqlite "$Q_PASCAL LIMIT 10;"
        demo_step "SQLite through ODBC"
        odbc SQLite3 "Database=$DEMO_DIR/Chinook_Sqlite.sqlite" "$Q_PASCAL LIMIT 10" ;;
    postgres*)
        start_db devdemo-pg 55432:5432 postgres:17 -e POSTGRES_PASSWORD=devdemo || continue
        until docker exec devdemo-pg pg_isready -U postgres > /dev/null 2>&1; do sleep 1; done; sleep 2
        demo_step "loading Chinook (creates database chinook)"
        docker exec -i devdemo-pg psql -q -U postgres -v ON_ERROR_STOP=1 < Chinook_PostgreSql.sql > /dev/null || continue
        odbc "PostgreSQL Unicode" "Server=127.0.0.1;Port=55432;Database=chinook;Uid=postgres;Pwd=devdemo" "$Q_SNAKE LIMIT 10"
        demo_note "psql -h localhost -p 55432 -U postgres chinook   (password devdemo) while this menu is open" ;;
    mariadb*)
        start_db devdemo-mariadb 53306:3306 mariadb:11 -e MARIADB_ROOT_PASSWORD=devdemo || continue
        until docker exec devdemo-mariadb mariadb-admin -uroot -pdevdemo ping > /dev/null 2>&1; do sleep 1; done
        demo_step "loading Chinook (creates database Chinook)"
        docker exec -i devdemo-mariadb mariadb -uroot -pdevdemo < Chinook_MySql.sql || continue
        odbc "MariaDB Unicode" "Server=127.0.0.1;Port=53306;Database=Chinook;Uid=root;Pwd=devdemo" "$Q_PASCAL LIMIT 10" ;;
    sqlserver*)
        docker_ok
        if docker container inspect devdb-mssql > /dev/null 2>&1 && command -v mssql > /dev/null; then
            # v82: the SQL Server that install-mssql created. Chinook stays in it afterwards; the server
            # is stopped again on exit if this demo is what started it.
            MS_C=devdb-mssql; MS_PORT=1433; MS_PW=$(mssql password)
            [ "$(docker inspect -f '{{.State.Running}}' devdb-mssql)" = true ] || demo_on_exit "mssql down"
            mssql up || continue
            demo_note "Using install-mssql's server (devdb-mssql); the Chinook database stays in it."
        else
            MS_C=devdemo-mssql; MS_PORT=51433; MS_PW='DevDemo#2026'
            start_db devdemo-mssql 51433:1433 mcr.microsoft.com/mssql/server:2025-latest \
                -e ACCEPT_EULA=Y -e "MSSQL_SA_PASSWORD=$MS_PW" || continue
            demo_note "A throwaway SQL Server 2025 (install-mssql gives you a lasting one). Waiting for it to start (30-60 s)..."
            for _ in $(seq 60); do
                docker exec -e "SQLCMDPASSWORD=$MS_PW" devdemo-mssql /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -Q 'SELECT 1' > /dev/null 2>&1 && break
                sleep 2
            done
        fi
        docker cp Chinook_SqlServer.sql "$MS_C:/tmp/chinook.sql" > /dev/null
        demo_step "loading Chinook with the container's sqlcmd"
        docker exec -e "SQLCMDPASSWORD=$MS_PW" "$MS_C" /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -i /tmp/chinook.sql > /dev/null || continue
        odbc "ODBC Driver 18 for SQL Server" "Server=127.0.0.1,$MS_PORT;Database=Chinook;Uid=sa;Pwd=$MS_PW;TrustServerCertificate=yes" \
            "${Q_PASCAL/SELECT/SELECT TOP 10}" ;;
    access*)
        [ -f nwind.mdb ] || { echo "nwind.mdb was not downloaded; rerun dev-demo with demo-refresh."; continue; }
        demo_need mdb-tables install-db
        demo_step "tables in nwind.mdb"; mdb-tables -1 nwind.mdb | column
        demo_step "first rows of Products (CSV export)"; mdb-export nwind.mdb Products | head -n 6
        demo_step "SQL over the file (mdb-sql)"
        printf 'select ProductName, UnitPrice from Products where UnitPrice > 50\ngo\n' | mdb-sql nwind.mdb ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# v80: Firebird (install-db) and InterBase (install-interbase). One schema, one Free Pascal program:
# the TSQLDBLibraryLoader's LibraryName is the only thing that decides which product it talks to.
demo_firebird() {
    begin db firebird "Firebird 4 embedded (no server): isql-fb, gbak backup/restore, the same file from Lazarus SQLdb; InterBase too" \
        "generated by dev-demo (Debian firebird4.0; Embarcadero InterBase when installed)" || return 0
    if ! command -v isql-fb > /dev/null 2>&1 && [ ! -x /opt/interbase/bin/isql ]; then
        echo "  ${YEL}skip${RST}: needs isql-fb (dev-setup with install-db) or InterBase (install-interbase)"
        SKIPPED+=("$STACK/$NAME: needs Firebird (install-db) or InterBase (install-interbase)"); return 0
    fi
    gen_file "$DIR/airports.sql" << 'EOF'
-- Loaded into a fresh database by run-firebird.sh. Firebird and InterBase both read it as it is:
-- the PSQL procedure syntax (SET TERM, FOR SELECT ... DO SUSPEND) is what they share from InterBase 6.
CREATE TABLE airports (
    code      CHAR(3)     NOT NULL PRIMARY KEY,
    name      VARCHAR(60) NOT NULL,
    city      VARCHAR(40),
    delay_min INTEGER DEFAULT 0
);
INSERT INTO airports VALUES ('DCA', 'Ronald Reagan Washington National', 'Arlington', 5);
INSERT INTO airports VALUES ('IAD', 'Washington Dulles International', 'Dulles', 42);
INSERT INTO airports VALUES ('BWI', 'Baltimore/Washington International', 'Baltimore', 0);
INSERT INTO airports VALUES ('RIC', 'Richmond International', 'Richmond', 12);
COMMIT;

SET TERM ^ ;
CREATE PROCEDURE late_airports (min_delay INTEGER)
RETURNS (code CHAR(3), delay_min INTEGER)
AS
BEGIN
  FOR SELECT code, delay_min FROM airports WHERE delay_min >= :min_delay ORDER BY delay_min DESC
      INTO :code, :delay_min
  DO SUSPEND;
END^
SET TERM ; ^
COMMIT;
EOF
    gen_file "$DIR/queries.sql" << 'EOF'
SELECT code, name, delay_min FROM airports ORDER BY delay_min DESC;
SELECT * FROM late_airports(10);
EOF
    gen_file "$DIR/airports.pas" << 'EOF'
program airports;
{ dev-demo: the airports database from Free Pascal / Lazarus SQLdb. (CHAR columns come back padded to
  their byte width under UTF8, hence the Trim.)
  TIBConnection speaks the client API Firebird and InterBase share; the TSQLDBLibraryLoader loads
  the client library first, and that is what decides which product the program talks to:
    libfbclient.so.2                   Firebird (a file path = embedded, no server)
    /opt/interbase/lib/libgds.so       InterBase (localhost:/path = through its server)
  Usage: airports DATABASE LIBRARY [USER] [PASSWORD]
  In a Lazarus form app: put a TSQLDBLibraryLoader, a TIBConnection, a TSQLTransaction and a
  TSQLQuery on the form, set the same properties, and enable the loader before the connection opens. }
{$mode objfpc}{$H+}
uses SysUtils, sqldb, sqldblib, IBConnection;
var
  Loader: TSQLDBLibraryLoader;
  Conn: TIBConnection;
  Tran: TSQLTransaction;
  Q: TSQLQuery;
begin
  if ParamCount < 2 then
  begin
    WriteLn('usage: airports DATABASE LIBRARY [USER] [PASSWORD]');
    Halt(2);
  end;
  try
    Loader := TSQLDBLibraryLoader.Create(nil);
    Loader.ConnectionType := 'Firebird';
    Loader.LibraryName := ParamStr(2);
    Loader.Enabled := True;
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
    WriteLn('Connected to ', ParamStr(1), ' through ', ParamStr(2));
    WriteLn;
    Q.SQL.Text := 'SELECT code, name, delay_min FROM airports ORDER BY delay_min DESC';
    Q.Open;
    while not Q.EOF do
    begin
      WriteLn(Format('  %-4s %-38s %4d min', [Trim(Q.FieldByName('code').AsString),
        Q.FieldByName('name').AsString, Q.FieldByName('delay_min').AsInteger]));
      Q.Next;
    end;
    Q.Close;
    WriteLn;
    WriteLn('Stored procedure late_airports(10):');
    Q.SQL.Text := 'SELECT code, delay_min FROM late_airports(10)';
    Q.Open;
    while not Q.EOF do
    begin
      WriteLn(Format('  %-4s %4d min', [Trim(Q.FieldByName('code').AsString), Q.FieldByName('delay_min').AsInteger]));
      Q.Next;
    end;
    Q.Close;
    Tran.Commit;
    Conn.Close;
  except
    on E: Exception do
    begin
      WriteLn('Error: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
EOF
    FRESH=1
    write_run << 'EOF'
# Embedded Firebird checks no password; it only wants a user name.
export ISC_USER="${ISC_USER:-SYSDBA}"
FB_DB="$DEMO_DIR/airports.fdb"
IB_PW="${INTERBASE_SYSDBA_PASSWORD:-masterkey}"
IB_DB=/tmp/devdemo-airports.ib      # written by the InterBase server process, so somewhere it can write
IB_ISQL=/opt/interbase/bin/isql
build_pas() {   # compile airports.pas once, and again after you edit it
    command -v fpc > /dev/null || { echo "Needs fpc: dev-setup with install-lazarus."; return 1; }
    if [ ! -x airports ] || [ airports.pas -nt airports ]; then
        fpc -O2 -vew airports.pas > fpc.log 2>&1 || { tail -n 15 fpc.log; return 1; }
    fi
}
ITEMS=()
if command -v isql-fb > /dev/null; then
    ITEMS+=("isql: create airports.fdb (embedded, no server) and query it"
            "backup: gbak backup + restore of airports.fdb, then read the copy"
            "lazarus: the same file from Free Pascal SQLdb (TIBConnection + TSQLDBLibraryLoader)")
fi
[ -x "$IB_ISQL" ] && ITEMS+=("interbase: the same schema in the InterBase server, from InterBase's isql and from SQLdb")
while demo_menu "Firebird / InterBase" "${ITEMS[@]}"; do
    case "$DEMO_CHOICE" in
    isql*)
        rm -f "$FB_DB"
        demo_step "CREATE DATABASE, then airports.sql (a table, four rows, a stored procedure) and two queries"
        { printf "CREATE DATABASE '%s' DEFAULT CHARACTER SET UTF8;\n" "$FB_DB"; cat airports.sql queries.sql
          printf "SELECT rdb\$get_context('SYSTEM', 'ENGINE_VERSION') AS firebird_engine FROM rdb\$database;\n"; } \
            | isql-fb -q || continue
        ls -l "$FB_DB"
        demo_note "Open it yourself: isql-fb $FB_DB   (no server, no password; ISC_USER=SYSDBA)" ;;
    backup*)
        [ -f "$FB_DB" ] || { echo "Run 'isql' first."; continue; }
        rm -f airports.fbk airports-restored.fdb
        demo_step "gbak -b: backup (a portable, compacted copy; what you move between machines and versions)"
        gbak -b "$FB_DB" "$DEMO_DIR/airports.fbk" || continue
        demo_step "gbak -c: restore into a new database file"
        gbak -c "$DEMO_DIR/airports.fbk" "$DEMO_DIR/airports-restored.fdb" || continue
        ls -l airports.fdb airports.fbk airports-restored.fdb
        demo_step "read the restored copy"
        isql-fb -q "$DEMO_DIR/airports-restored.fdb" < queries.sql ;;
    lazarus*)
        [ -f "$FB_DB" ] || { echo "Run 'isql' first."; continue; }
        build_pas || continue
        demo_step "./airports airports.fdb libfbclient.so.2"
        ./airports "$FB_DB" libfbclient.so.2
        demo_note "In the Lazarus IDE: TSQLDBLibraryLoader (ConnectionType Firebird, LibraryName libfbclient.so.2) enabled before the TIBConnection opens." ;;
    interbase*)
        (exec 3<> /dev/tcp/127.0.0.1/3050) 2> /dev/null \
            || { echo "The InterBase server is not running: dev-init with install-interbase registers it and starts it."; continue; }
        "$IB_ISQL" -z < /dev/null 2>&1 | head -n 1
        demo_step "InterBase server: (re)create $IB_DB and load the same airports.sql"
        printf "CONNECT 'localhost:%s' USER 'SYSDBA' PASSWORD '%s';\nDROP DATABASE;\n" "$IB_DB" "$IB_PW" | "$IB_ISQL" -q > /dev/null 2>&1
        { printf "CREATE DATABASE 'localhost:%s' USER 'SYSDBA' PASSWORD '%s';\n" "$IB_DB" "$IB_PW"; cat airports.sql queries.sql; } \
            | "$IB_ISQL" -q || continue
        if build_pas; then
            demo_step "./airports localhost:$IB_DB /opt/interbase/lib/libgds.so"
            ./airports "localhost:$IB_DB" /opt/interbase/lib/libgds.so SYSDBA "$IB_PW"
            demo_note "Same program, same SQL: only the loader's LibraryName decides InterBase or Firebird."
        fi ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# v82: SQL Server and Oracle (install-mssql / install-oracle, from install-db-server): the airports schema
# db/firebird uses, now in T-SQL and in PL/SQL, through each engine's own client and through ODBC. The
# servers are setup's devdb-* containers (Oracle Free allows one instance per machine, so the demo
# never starts its own). One engine runs at a time; the launcher stops again what it started.
demo_dbservers() {
    begin db servers "SQL Server 2025 and Oracle 26ai Free: one airports schema in T-SQL and PL/SQL, via sqlcmd, SQLcl and ODBC" \
        "generated by dev-demo (containers from install-mssql / install-oracle)" || return 0
    if ! command -v mssql > /dev/null 2>&1; then
        echo "  ${YEL}skip${RST}: needs the mssql / oracle commands (dev-setup with install-mssql, install-oracle or install-db-server)"
        SKIPPED+=("$STACK/$NAME: needs install-mssql or install-oracle (install-db-server)"); return 0
    fi
    gen_file "$DIR/airports-mssql.sql" << 'EOF'
-- dev-demo db/servers: the airports schema in SQL Server (T-SQL), in a database called devdemo.
-- run-servers.sh loads it with:  mssql sql -W -i airports-mssql.sql
SET NOCOUNT ON;
IF DB_ID('devdemo') IS NULL CREATE DATABASE devdemo;
GO
USE devdemo;
DROP PROCEDURE IF EXISTS dbo.late_airports;
DROP TABLE IF EXISTS dbo.airports;
CREATE TABLE dbo.airports (
    code      CHAR(3)      NOT NULL PRIMARY KEY,
    name      NVARCHAR(60) NOT NULL,
    city      NVARCHAR(40),
    delay_min INT          NOT NULL DEFAULT 0
);
INSERT INTO dbo.airports VALUES
    ('DCA', N'Ronald Reagan Washington National', N'Arlington', 5),
    ('IAD', N'Washington Dulles International', N'Dulles', 42),
    ('BWI', N'Baltimore/Washington International', N'Baltimore', 0),
    ('RIC', N'Richmond International', N'Richmond', 12);
GO
CREATE PROCEDURE dbo.late_airports @min_delay INT AS
BEGIN
    SET NOCOUNT ON;
    SELECT code, delay_min FROM dbo.airports WHERE delay_min >= @min_delay ORDER BY delay_min DESC;
END
GO
PRINT '== the table';
SELECT code, name, delay_min FROM dbo.airports ORDER BY delay_min DESC;
PRINT '== EXEC dbo.late_airports @min_delay = 10   (a T-SQL stored procedure)';
EXEC dbo.late_airports @min_delay = 10;
PRINT '== FOR JSON PATH: rows straight to JSON';
SELECT code, delay_min FROM dbo.airports ORDER BY code FOR JSON PATH;
PRINT '== the server';
SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(40)) AS version, CAST(SERVERPROPERTY('Edition') AS nvarchar(80)) AS edition;
GO
EOF
    gen_file "$DIR/airports-oracle.sql" << 'EOF'
-- dev-demo db/servers: the airports schema in Oracle (PL/SQL), in SYSTEM's schema of FREEPDB1.
-- run-servers.sh loads it with:  oracle sql -S @airports-oracle.sql
SET FEEDBACK OFF
SET SQLFORMAT ansiconsole
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE airports PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
CREATE TABLE airports (
    code      CHAR(3)      NOT NULL PRIMARY KEY,
    name      VARCHAR2(60) NOT NULL,
    city      VARCHAR2(40),
    delay_min NUMBER       DEFAULT 0 NOT NULL
);
INSERT INTO airports VALUES ('DCA', 'Ronald Reagan Washington National', 'Arlington', 5);
INSERT INTO airports VALUES ('IAD', 'Washington Dulles International', 'Dulles', 42);
INSERT INTO airports VALUES ('BWI', 'Baltimore/Washington International', 'Baltimore', 0);
INSERT INTO airports VALUES ('RIC', 'Richmond International', 'Richmond', 12);
COMMIT;
CREATE OR REPLACE FUNCTION late_airports (p_min_delay IN NUMBER) RETURN SYS_REFCURSOR AS
  c SYS_REFCURSOR;
BEGIN
  OPEN c FOR SELECT code, delay_min FROM airports WHERE delay_min >= p_min_delay ORDER BY delay_min DESC;
  RETURN c;
END;
/
PROMPT == the table
SELECT code, name, delay_min FROM airports ORDER BY delay_min DESC;
PROMPT == late_airports(10)   (a PL/SQL function returning a cursor)
SELECT late_airports(10) AS late FROM dual;
PROMPT == JSON_ARRAYAGG / JSON_OBJECT: rows straight to JSON
SELECT JSON_ARRAYAGG(JSON_OBJECT('code' VALUE code, 'delay_min' VALUE delay_min) ORDER BY code) AS json FROM airports;
PROMPT == the server
SELECT banner_full FROM v$version;
PROMPT == its optional components (the full image, install-oracle-full, has more of them than Lite)
SELECT comp_id, comp_name, status FROM dba_registry ORDER BY comp_id;
EXIT
EOF
    FRESH=1
    write_run << 'EOF'
docker_ok
have() { docker container inspect "devdb-$1" > /dev/null 2>&1; }
ITEMS=()
have mssql  && ITEMS+=("sqlserver: load and query airports in SQL Server 2025 (T-SQL procedure, FOR JSON) with sqlcmd")
have oracle && ITEMS+=("oracle: load and query airports in Oracle 26ai Free (PL/SQL function, JSON) with SQLcl")
{ have mssql || have oracle; } && ITEMS+=("odbc: the same SELECT against each engine through unixODBC's isql")
have mssql  && ITEMS+=("shell-sqlserver: an interactive sqlcmd session in the devdemo database")
have oracle && ITEMS+=("shell-oracle: an interactive SQLcl session (airports sits in SYSTEM's schema)")
[ ${#ITEMS[@]} -gt 0 ] || { echo "No devdb-mssql or devdb-oracle container: run dev-setup with install-db-server."; exit 1; }
# Engines that are stopped now are stopped again when this launcher ends.
for _e in mssql oracle; do
    if have "$_e" && [ "$(docker inspect -f '{{.State.Running}}' "devdb-$_e")" != true ]; then demo_on_exit "$_e down"; fi
done
demo_note "HEAVY: each engine holds ~2 GB, so only one runs at a time: picking one stops the other."
load_mssql() {
    mssql up || { echo "SQL Server did not start: 'mssql logs' shows why."; return 1; }
    if command -v sqlcmd > /dev/null; then
        mssql sql -W -i "$DEMO_DIR/airports-mssql.sql"
    else
        docker cp airports-mssql.sql devdb-mssql:/tmp/airports-mssql.sql > /dev/null \
            && docker exec -e "SQLCMDPASSWORD=$(mssql password)" devdb-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -i /tmp/airports-mssql.sql
    fi
}
load_oracle() {
    oracle up || { echo "Oracle did not start: 'oracle logs' shows why."; return 1; }
    oracle sql -S @airports-oracle.sql
}
while demo_menu "SQL Server and Oracle" "${ITEMS[@]}"; do
    case "$DEMO_CHOICE" in
    sqlserver*)
        demo_step "SQL Server 2025: airports-mssql.sql"
        load_mssql ;;
    oracle*)
        demo_step "Oracle 26ai Free: airports-oracle.sql"
        demo_note "SQLcl is a Java program: it takes a few seconds to start."
        load_oracle ;;
    odbc*)
        if have mssql && mssql up && load_mssql > /dev/null 2>&1; then
            demo_step "SQL Server through [ODBC Driver 18 for SQL Server]"
            echo "SELECT code, delay_min FROM devdemo.dbo.airports ORDER BY delay_min DESC" \
                | isql -b -k "DRIVER={ODBC Driver 18 for SQL Server};Server=127.0.0.1,1433;Uid=sa;Pwd=$(mssql password);TrustServerCertificate=yes"
        fi
        if have oracle && oracle up && load_oracle > /dev/null 2>&1; then
            demo_step "Oracle through [Oracle ODBC] (Instant Client)"
            echo "SELECT code, delay_min FROM airports ORDER BY delay_min DESC" \
                | isql -b -k "DRIVER={Oracle ODBC};DBQ=127.0.0.1:1521/FREEPDB1;UID=system;PWD=$(oracle password)"
        fi
        demo_note "Same SQL, same isql, two drivers. LibreOffice Base, pyodbc or a Lazarus TODBCConnection connect the same way." ;;
    shell-sqlserver*)
        mssql up > /dev/null || continue
        demo_note "Try: SELECT * FROM dbo.airports;  then GO. 'exit' leaves."
        mssql sql -d devdemo ;;
    shell-oracle*)
        oracle up > /dev/null || continue
        demo_note "Try: SELECT * FROM airports;  'help' lists SQLcl's commands, 'exit' leaves."
        oracle sql ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# =================================================================
# DEMOS: Kubernetes, IaC, cloud
# =================================================================

demo_k8s() {
    begin k8s podinfo "podinfo on a kind cluster via Helm: 2 replicas, a live web UI on :9898, browse it with k9s" \
        "https://github.com/stefanprodan/podinfo (Helm chart from ghcr.io)" || return 0
    need helm install-k8s || return 0
    need kind install-k8s || return 0
    if ! present; then
        mkdir -p "$DIR"
        helm pull oci://ghcr.io/stefanprodan/charts/podinfo --untar --untardir "$DIR/chart" > /dev/null \
            || { rm -rf "$DIR"; fail "helm pull of the podinfo chart failed"; return 0; }
        FRESH=1
    fi
    write_run << 'EOF'
demo_need kind install-k8s
docker_ok
if [ "${1:-}" = down ]; then kind delete cluster --name devdemo; exit; fi
kind get clusters 2> /dev/null | grep -qx devdemo || kind create cluster --name devdemo || exit 1
kubectl config use-context kind-devdemo > /dev/null
demo_step "helm install podinfo"
helm upgrade --install podinfo ./chart/podinfo --set replicaCount=2 \
    --set ui.message="Hello from kind on a Chromebook" --wait --timeout 5m || exit 1
kubectl get pods -l app.kubernetes.io/name=podinfo -o wide
demo_bg port-forward kubectl port-forward svc/podinfo 9898:9898
demo_wait_port 9898 60 && demo_open http://localhost:9898
demo_note "In another terminal: k9s --context kind-devdemo   (or: k get pods -w)"
demo_note "Scale it: helm upgrade podinfo $DEMO_DIR/chart/podinfo --reuse-values --set replicaCount=4"
demo_note "The cluster keeps running after you stop; delete it with: $0 down"
demo_hold "Press Enter to stop the port-forward"
EOF
    done_demo
}

demo_iac() {
    begin iac terraform-nginx "Terraform with the Docker provider: 'apply' starts an nginx container serving a page on :8088" \
        "generated by dev-demo (provider: kreuzwerker/docker)" || return 0
    need terraform install-iac || return 0
    gen_file "$DIR/main.tf" << 'EOF'
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

variable "message" {
  type    = string
  default = "Deployed by Terraform on a Chromebook"
}

resource "docker_image" "nginx" {
  name         = "nginx:alpine"
  keep_locally = true
}

resource "docker_container" "web" {
  name  = "devdemo-terraform-nginx"
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = 8088
  }

  upload {
    file    = "/usr/share/nginx/html/index.html"
    content = "<!doctype html><title>dev-demo</title><h1>${var.message}</h1><p>Change the message: terraform apply -var 'message=...'</p>"
  }
}

output "url" {
  value = "http://localhost:8088"
}
EOF
    FRESH=1
    write_run << 'EOF'
demo_need terraform install-iac
docker_ok
if [ "${1:-}" = down ]; then terraform destroy -auto-approve; exit; fi
terraform init -input=false -upgrade > /dev/null || exit 1
if command -v tflint > /dev/null; then demo_step "tflint"; tflint && echo "tflint: no issues"; fi
demo_step "terraform plan + apply"
terraform apply -auto-approve -input=false || exit 1
demo_wait_port 8088 30 && demo_open http://localhost:8088
demo_note "Try: terraform apply -var 'message=Hello DC'   then reload. Remove it all with: $0 down"
EOF
    done_demo
}

demo_ansible() {
    begin ansible docker-web "Ansible turns a Debian container into an nginx server (page on :8089); Molecule tests the same role" \
        "generated by dev-demo (collection: community.docker)" || return 0
    need ansible-playbook "install-iac or install-ansible-core" || return 0
    gen_file "$DIR/ansible.cfg" << 'EOF'
[defaults]
inventory = inventory
roles_path = roles
interpreter_python = auto_silent
EOF
    gen_file "$DIR/inventory/hosts.yml" << 'EOF'
---
# The target is a Docker container: no SSH, Ansible talks to it through 'docker exec'.
all:
  hosts:
    devdemo-ansible-web:
      ansible_connection: community.docker.docker
      ansible_python_interpreter: /usr/bin/python3
EOF
    gen_file "$DIR/site.yml" << 'EOF'
---
- name: Configure the web container
  hosts: all
  gather_facts: false # the role gathers them once Python is on the target
  roles:
    - role: web
EOF
    gen_file "$DIR/roles/web/defaults/main.yml" << 'EOF'
---
web_message: Configured by Ansible on a Chromebook
EOF
    gen_file "$DIR/roles/web/tasks/main.yml" << 'EOF'
---
- name: Make sure the target has Python (the Debian image ships without it)
  ansible.builtin.raw: >-
    test -x /usr/bin/python3 && echo present ||
    (apt-get update -qq && apt-get install -y -qq python3 python3-apt > /dev/null && echo installed)
  register: web_bootstrap
  changed_when: "'installed' in web_bootstrap.stdout"

- name: Gather facts now that Python is there
  ansible.builtin.setup:

- name: Install nginx
  ansible.builtin.apt:
    name: nginx
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: Publish the page
  ansible.builtin.template:
    src: index.html.j2
    dest: /var/www/html/index.html
    mode: "0644"

- name: Listen on IPv4 only (Docker's default network gives containers no IPv6)
  ansible.builtin.lineinfile:
    path: /etc/nginx/sites-available/default
    regexp: '^\s*listen \[::\]:80'
    state: absent

- name: Start nginx (a container has no init system to do it)
  ansible.builtin.command: nginx
  args:
    creates: /run/nginx.pid
EOF
    gen_file "$DIR/roles/web/templates/index.html.j2" << 'EOF'
<!doctype html>
<title>dev-demo: Ansible</title>
<h1>{{ web_message }}</h1>
<p>{{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }} container, nginx configured by Ansible {{ ansible_version.full }}.</p>
<p>Change the message: <code>ansible-playbook site.yml -e 'web_message=Hello DC'</code>, then reload.</p>
EOF
    gen_file "$DIR/molecule/default/molecule.yml" << 'EOF'
---
# Molecule's default driver with a static inventory: create.yml / destroy.yml start and remove the
# container, the inventory reaches it over the community.docker connection.
ansible:
  env:
    ANSIBLE_ROLES_PATH: ${MOLECULE_PROJECT_DIRECTORY}/roles
  executor:
    args:
      ansible_playbook:
        - --inventory=${MOLECULE_SCENARIO_DIRECTORY}/inventory
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
    gen_file "$DIR/molecule/default/inventory/hosts.yml" << 'EOF'
---
all:
  hosts:
    devdemo-ansible-molecule:
      ansible_connection: community.docker.docker
      ansible_python_interpreter: /usr/bin/python3
EOF
    gen_file "$DIR/molecule/default/create.yml" << 'EOF'
---
- name: Create
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Start a throwaway Debian container
      community.docker.docker_container:
        name: devdemo-ansible-molecule
        image: debian:trixie-slim
        command: sleep infinity
        state: started
EOF
    gen_file "$DIR/molecule/default/destroy.yml" << 'EOF'
---
- name: Destroy
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Remove the container
      community.docker.docker_container:
        name: devdemo-ansible-molecule
        state: absent
EOF
    gen_file "$DIR/molecule/default/converge.yml" << 'EOF'
---
- name: Converge
  hosts: all
  gather_facts: false
  roles:
    - role: web
EOF
    gen_file "$DIR/molecule/default/verify.yml" << 'EOF'
---
- name: Verify
  hosts: all
  gather_facts: false
  tasks:
    - name: Fetch the page from inside the container
      ansible.builtin.uri:
        url: http://localhost/
        return_content: true
      register: web_page

    - name: Assert nginx serves the role's page
      ansible.builtin.assert:
        that: "'Configured by Ansible' in web_page.content"
EOF
    FRESH=1
    write_run << 'EOF'
demo_need ansible-playbook "install-iac or install-ansible-core"
docker_ok
C=devdemo-ansible-web
if [ "${1:-}" = down ]; then docker rm -f "$C" devdemo-ansible-molecule 2> /dev/null; exit 0; fi
demo_note "deploy   : start a Debian container, let Ansible make it an nginx server, open the page on :8089"
demo_note "molecule : the same role through a full Molecule cycle in a throwaway container"
demo_note "lint     : ansible-lint over the whole project"
demo_menu "What to run?" deploy molecule lint || exit 0
case "$DEMO_CHOICE" in
    deploy)
        # A stopped container keeps nginx's stale pid file, so start from a fresh one instead.
        if [ "$(docker inspect -f '{{.State.Running}}' "$C" 2> /dev/null)" != true ]; then
            docker rm -f "$C" > /dev/null 2>&1
            docker run -d --name "$C" -p 8089:80 debian:trixie-slim sleep infinity > /dev/null || exit 1
        fi
        demo_step "ansible-playbook site.yml"
        ansible-playbook site.yml || exit 1
        demo_wait_port 8089 30 && demo_open http://localhost:8089
        demo_note "Change the page: ansible-playbook site.yml -e 'web_message=Hello DC', then reload."
        demo_note "Run it again unchanged to see changed=0. The container keeps running; remove it with: $0 down"
        ;;
    molecule)
        demo_step "molecule test"
        molecule test
        ;;
    lint)
        demo_step "ansible-lint"
        ansible-lint --offline && echo "ansible-lint: no issues"
        ;;
esac
EOF
    done_demo
}

demo_cloud() {
    if has install-aws; then
        begin cloud aws-moto "AWS CLI against Moto's local AWS: S3, DynamoDB and SQS round-trips, no account needed" \
            "https://github.com/getmoto/moto (PyPI: moto[server])" && {
        if need aws install-aws && need uvx "the base install (uv)"; then
            mkdir -p "$DIR"
            write_run << 'EOF'
demo_need aws install-aws
# Throwaway credentials: Moto accepts anything, and these keep the real ones (if any) out of it.
export AWS_ACCESS_KEY_ID=devdemo AWS_SECRET_ACCESS_KEY=devdemo AWS_DEFAULT_REGION=us-east-1 AWS_PAGER=""
unset AWS_PROFILE AWS_SESSION_TOKEN
EP=http://127.0.0.1:5055
awsl() { aws --endpoint-url "$EP" "$@"; }
demo_step "Moto server on :5055 (first start downloads it with uvx)"
demo_bg moto uvx --from "moto[server]" moto_server -H 127.0.0.1 -p 5055
demo_wait_port 5055 180 || exit 1
demo_step "S3"
awsl s3 mb s3://devdemo-bucket
date | awsl s3 cp - s3://devdemo-bucket/hello.txt
awsl s3 ls s3://devdemo-bucket
demo_step "DynamoDB"
awsl dynamodb create-table --table-name Airports --attribute-definitions AttributeName=code,AttributeType=S \
    --key-schema AttributeName=code,KeyType=HASH --billing-mode PAY_PER_REQUEST --query TableDescription.TableStatus
awsl dynamodb put-item --table-name Airports --item '{"code":{"S":"DCA"},"name":{"S":"Reagan National"}}'
awsl dynamodb put-item --table-name Airports --item '{"code":{"S":"IAD"},"name":{"S":"Dulles"}}'
awsl dynamodb scan --table-name Airports --query 'Items[].{code: code.S, name: name.S}' --output table
demo_step "SQS"
Q=$(awsl sqs create-queue --queue-name devdemo --query QueueUrl --output text)
awsl sqs send-message --queue-url "$Q" --message-body "hello from the AWS CLI" --query MessageId --output text
awsl sqs receive-message --queue-url "$Q" --query 'Messages[0].Body' --output text
demo_open "$EP/moto-api/"
demo_note "Moto's dashboard shows everything created. Keep experimenting: aws --endpoint-url $EP ..."
demo_hold "Press Enter to stop Moto (all data is in memory and disappears)"
EOF
            done_demo
        fi; }
    fi

    if has install-azure; then
        begin cloud azure-azurite "Azure CLI against Azurite (local Azure Storage): blobs, queues and tables, no subscription" \
            "https://github.com/Azure/Azurite (image: mcr.microsoft.com/azure-storage/azurite)" && {
        if need az install-azure && need docker "the base install"; then
            mkdir -p "$DIR"
            write_run << 'EOF'
demo_need az install-azure
docker_ok
docker rm -f devdemo-azurite > /dev/null 2>&1
demo_on_exit "docker rm -f devdemo-azurite"
docker run -d --name devdemo-azurite -p 10000-10002:10000-10002 mcr.microsoft.com/azure-storage/azurite > /dev/null || exit 1
demo_wait_port 10000 120 || exit 1
# Azurite's published development account (the same fixed key in every Azurite install).
export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;QueueEndpoint=http://127.0.0.1:10001/devstoreaccount1;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1;"
export AZURE_CORE_ONLY_SHOW_ERRORS=true
demo_step "Blob storage"
az storage container create -n devdemo -o table
date > "$DEMO_LOGS/azurite-hello.txt"
az storage blob upload -c devdemo -n hello.txt -f "$DEMO_LOGS/azurite-hello.txt" --overwrite -o none
az storage blob list -c devdemo --query '[].{name:name, size:properties.contentLength}' -o table
demo_step "Queue storage"
az storage queue create -n devdemo -o table
az storage message put -q devdemo --content "hello from the Azure CLI" -o none
az storage message peek -q devdemo --query '[].content' -o tsv
demo_step "Table storage"
az storage table create -n Airports -o table
az storage entity insert -t Airports -e PartitionKey=DC RowKey=DCA Name="Reagan National" -o none
az storage entity insert -t Airports -e PartitionKey=DC RowKey=IAD Name=Dulles -o none
az storage entity query -t Airports --query 'items[].{code:RowKey, name:Name}' -o table
demo_note "Azure Storage Explorer or any SDK can use the same connection string while this runs."
demo_hold "Press Enter to stop Azurite"
EOF
            done_demo
        fi; }
    fi

    if has install-gcp; then
        begin cloud gcp-pubsub "gcloud against the Pub/Sub emulator: create a topic and subscription, publish, pull" \
            "Google Cloud SDK emulator image (gcr.io/google.com/cloudsdktool/google-cloud-cli:emulators)" && {
        if need gcloud install-gcp && need docker "the base install"; then
            mkdir -p "$DIR"
            write_run << 'EOF'
demo_need gcloud install-gcp
docker_ok
demo_note "The emulator image is large (~1.5 GB) the first time."
docker rm -f devdemo-pubsub > /dev/null 2>&1
demo_on_exit "docker rm -f devdemo-pubsub"
docker run -d --name devdemo-pubsub -p 8085:8085 gcr.io/google.com/cloudsdktool/google-cloud-cli:emulators \
    gcloud beta emulators pubsub start --host-port=0.0.0.0:8085 --project=devdemo > /dev/null || exit 1
demo_wait_port 8085 300 || exit 1
sleep 3
# Point gcloud at the emulator, with no credentials and a throwaway project id.
export CLOUDSDK_API_ENDPOINT_OVERRIDES_PUBSUB=http://localhost:8085/ CLOUDSDK_AUTH_DISABLE_CREDENTIALS=true CLOUDSDK_CORE_PROJECT=devdemo
export PUBSUB_EMULATOR_HOST=localhost:8085      # what the client libraries read
demo_step "topic + subscription"
gcloud pubsub topics create hello
gcloud pubsub subscriptions create hello-sub --topic hello
demo_step "publish 3 messages"
for m in one two three; do gcloud pubsub topics publish hello --message "message $m" --format='value(messageIds)'; done
demo_step "pull them"
gcloud pubsub subscriptions pull hello-sub --auto-ack --limit 10 --format='table(message.data.decode(base64), message.messageId)'
demo_note "Client libraries use it too with PUBSUB_EMULATOR_HOST=localhost:8085."
demo_hold "Press Enter to stop the emulator"
EOF
            done_demo
        fi; }
    fi

    if has install-vercel; then
        begin cloud vercel-nextjs "Vercel's Next.js boilerplate: runs locally, and 'vercel' deploys a preview once you are logged in" \
            "https://github.com/vercel/examples/tree/main/framework-boilerplates/nextjs" && {
        if need npm install-node; then
            fetch_subdir https://github.com/vercel/examples.git framework-boilerplates/nextjs && {
            write_run << 'EOF'
demo_need npm install-node
[ -d node_modules ] || npm install --no-audit --no-fund || exit 1
if command -v vercel > /dev/null && vercel whoami > /dev/null 2>&1; then
    demo_note "Logged in to Vercel: 'vercel' in $DEMO_DIR deploys a preview; 'vercel dev' mirrors the platform locally."
else
    demo_note "Not logged in to Vercel (dev-init install-vercel): running the plain Next.js dev server."
fi
demo_open_when_ready 3000 http://localhost:3000
npm run dev -- --port 3000
EOF
            done_demo; }
        fi; }
    fi
}

# =================================================================
# DEMOS: media
# =================================================================

demo_media() {
    begin media sintel "Blender's open movie Sintel (60 s clip): play, transcode and GIF with ffmpeg, open in HandBrake, diff in KDiff3" \
        "https://archive.org/details/Sintel (Blender Foundation, CC-BY 3.0)" || return 0
    need ffmpeg "the base install" || return 0
    # v78: download.blender.org answers curl with a Cloudflare browser challenge (HTTP 403 since mid-2026),
    # so the clip comes from the Blender Foundation's own upload on archive.org. ffmpeg reads only the
    # byte ranges of the stretch it cuts (stream copy, ~20 MB), not the 283 MB film. When archive.org
    # is unreachable too, a test clip is generated locally so the demo still works; every later run
    # (not only demo-refresh) tries the download again while that stand-in is in place.
    local clip="$DIR/sintel-clip.mp4" src="https://archive.org/download/Sintel/sintel-2048-stereo.mp4"
    local start="${SINTEL_START:-150}" secs="${SINTEL_SECONDS:-60}"
    mkdir -p "$DIR"
    # A trailer that v75-v77 did manage to download is kept under the new name.
    [ -s "$DIR/sintel-trailer-480p.mp4" ] && [ ! -e "$clip" ] && mv "$DIR/sintel-trailer-480p.mp4" "$clip" \
        && echo "Sintel trailer (c) Blender Foundation, CC-BY 3.0, downloaded by dev-demo v77 or earlier" > "$DIR/.dev-demo-source"
    if [ ! -s "$clip" ] || [ "$REFRESH" = 1 ] || grep -q '^Generated' "$DIR/.dev-demo-source" 2> /dev/null; then
        echo "  cutting a ${secs}-second clip (from ${start}s) out of $src..."
        if ffmpeg -hide_banner -loglevel error -nostdin -y -reconnect 1 -reconnect_delay_max 5 \
                -ss "$start" -t "$secs" -i "$src" -c copy -movflags +faststart "$clip.part.mp4" \
            && [ -s "$clip.part.mp4" ]; then
            mv "$clip.part.mp4" "$clip"
            printf 'Sintel (c) Blender Foundation, CC-BY 3.0: %ss from %ss of %s, cut on %s by dev-demo v%s\n' \
                "$secs" "$start" "$src" "$(date +%F)" "$VERSION" > "$DIR/.dev-demo-source"
        elif [ -s "$clip" ] && ! grep -q '^Generated' "$DIR/.dev-demo-source" 2> /dev/null; then
            rm -f "$clip.part.mp4"
            echo "  ${YEL}note${RST}: archive.org unreachable; kept the clip already downloaded"
        else
            rm -f "$clip.part.mp4"
            echo "  archive.org unreachable: generating a 30-second test clip instead (no network needed)"
            ffmpeg -hide_banner -loglevel error -nostdin -y \
                -f lavfi -i "testsrc2=size=854x480:rate=24" -f lavfi -i "sine=frequency=440:sample_rate=48000" \
                -t 30 -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart "$clip" \
                || { rm -f "$clip" "$DIR/.dev-demo-source"; rmdir "$DIR" 2> /dev/null; fail "could not fetch the Sintel clip from archive.org or generate a test clip"; return 0; }
            printf 'Generated test pattern (testsrc2 + 440 Hz tone) by dev-demo v%s on %s; the next dev-demo run retries archive.org\n' \
                "$VERSION" "$(date +%F)" > "$DIR/.dev-demo-source"
            note "media/sintel: archive.org was unreachable, so the demo uses a generated test clip; the next dev-demo run retries."
        fi
        FRESH=1
    fi
    write_run << 'EOF'
IN=sintel-clip.mp4
head -n 1 .dev-demo-source 2> /dev/null | cut -c1-120
fp() { flatpak run --filesystem="$DEMO_DIR" "$@" > /dev/null 2>&1 & disown; }
while demo_menu "Media demo" \
        "play: ffplay (q quits)" \
        "transcode: 360p WebM (VP9 + Opus) with ffmpeg" \
        "gif: a 6-second GIF with a generated palette" \
        "handbrake: open the clip in HandBrake" \
        "kdiff3: compare ffprobe reports, original vs transcode"; do
    case "$DEMO_CHOICE" in
        play*)      ffplay -autoexit -loglevel error "$IN" ;;
        transcode*) ffmpeg -hide_banner -y -i "$IN" -vf scale=-2:360 -c:v libvpx-vp9 -b:v 600k -row-mt 1 -deadline realtime -cpu-used 8 \
                        -c:a libopus sintel-360p.webm && ls -lh "$IN" sintel-360p.webm ;;
        gif*)       ffmpeg -hide_banner -loglevel error -y -ss 20 -t 6 -i "$IN" \
                        -vf "fps=12,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" sintel.gif \
                        && ls -lh sintel.gif && demo_open "file://$DEMO_DIR/sintel.gif" ;;
        handbrake*) flatpak info fr.handbrake.ghb > /dev/null 2>&1 || { echo "HandBrake not installed (install-media)."; continue; }
                    fp fr.handbrake.ghb "$DEMO_DIR/$IN"; demo_note "HandBrake is open: pick a preset and Start Encode." ;;
        kdiff3*)    flatpak info org.kde.kdiff3 > /dev/null 2>&1 || { echo "KDiff3 not installed (install-media)."; continue; }
                    [ -f sintel-360p.webm ] || { echo "Run 'transcode' first."; continue; }
                    ffprobe -hide_banner -show_format -show_streams "$IN" 2> /dev/null > probe-original.txt
                    ffprobe -hide_banner -show_format -show_streams sintel-360p.webm 2> /dev/null > probe-360p.txt
                    fp org.kde.kdiff3 "$DEMO_DIR/probe-original.txt" "$DEMO_DIR/probe-360p.txt" ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# =================================================================
# DEMOS: laptop network
# =================================================================

# v84: net/mcp-hello (install-lan): a small MCP server you start on one laptop and call from another.
# It listens on the network itself (host 0.0.0.0): an MCP server on 127.0.0.1 turns away requests
# addressed to anything but localhost, so it cannot go through the relay the way Ollama does. Its tools
# say which laptop answered, what it shares and which Ollama models it has, and can ask one of them,
# so a Chromebook can use the 32 GB laptop's models through MCP. Server and client are single-file
# uv scripts (PEP 723): uv fetches the MCP Python SDK (mcp 2.x) into its cache on the first run.
demo_lan() {
    begin net mcp-hello "MCP across your laptops: start a server on one, call it (or add it to Claude Code) from another" \
        "generated here; MCP Python SDK: https://github.com/modelcontextprotocol/python-sdk" || return 0
    need uv "the base install" || return 0
    need lan install-lan || return 0
    present || FRESH=1
    gen_file "$DIR/server.py" << 'EOF_PY'
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=2.2,<3"]
# ///
"""mcp-hello: a small MCP server that tells other laptops about this one (dev-demo, install-lan).

Listens on every interface (host 0.0.0.0), so another laptop reaches it at http://<this laptop>:PORT/mcp.
An MCP server on 127.0.0.1 turns away requests addressed to anything but localhost (the SDK's DNS
rebinding protection), which is why it binds 0.0.0.0 itself instead of going through the 'lan' relay.
There is no login: run it on your home network only, and stop it with Ctrl-C.

    uv run server.py [--port 8770]
"""

import argparse
import json
import os
import platform
import shutil
import socket
import subprocess
import time
import urllib.request

from mcp.server.mcpserver import MCPServer

OLLAMA = "http://127.0.0.1:11434"
mcp = MCPServer("mcp-hello", instructions="Facts about one of Damien's laptops, and its local Ollama models.")


def _meminfo():
    out = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            out[k] = int(v.split()[0]) * 1024
    return out


def _ollama(path, payload=None, timeout=30):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(OLLAMA + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


@mcp.tool()
def whoami() -> dict:
    """Which laptop this is: its name, CPU, memory, disk and load right now."""
    mem = _meminfo()
    disk = shutil.disk_usage(os.path.expanduser("~"))
    with open("/proc/uptime") as f:
        up = float(f.read().split()[0])
    return {
        "machine": os.environ.get("LAN_SELF") or os.environ.get("MACHINE_LABEL") or socket.gethostname(),
        "linux": platform.freedesktop_os_release().get("PRETTY_NAME", platform.platform()),
        "cpus": os.cpu_count(),
        "load_1_5_15": [round(x, 2) for x in os.getloadavg()],
        "memory_gb": {"total": round(mem["MemTotal"] / 1e9, 1), "available": round(mem["MemAvailable"] / 1e9, 1)},
        "home_disk_free_gb": round(disk.free / 1e9, 1),
        "uptime_hours": round(up / 3600, 1),
        "time": time.strftime("%Y-%m-%d %H:%M:%S %Z"),
    }


@mcp.tool()
def shared_services() -> str:
    """What this laptop shares with the others ('lan share status')."""
    try:
        return subprocess.run(["lan", "share", "status"], capture_output=True, text=True, timeout=30).stdout.strip()
    except (OSError, subprocess.SubprocessError) as e:
        return f"'lan' is not available here ({e}): dev-setup with install-lan"


@mcp.tool()
def ollama_models() -> list[dict]:
    """The Ollama models on this laptop, with their size in GB."""
    try:
        tags = _ollama("/api/tags")["models"]
    except OSError as e:
        return [{"error": f"Ollama is not answering on this laptop ({e})"}]
    return [{"name": m["name"], "size_gb": round(m.get("size", 0) / 1e9, 1)} for m in tags]


@mcp.tool()
def ask_model(prompt: str, model: str = "") -> str:
    """Ask one of this laptop's Ollama models (default: its first chat model). CPU only: expect minutes on a cold load."""
    try:
        if not model:
            names = [m["name"] for m in _ollama("/api/tags")["models"]
                     if "embed" not in m["name"] and not m["name"].endswith(("-cloud", ":cloud"))]
            if not names:
                return "No chat model on this laptop (dev-setup with install-models, or 'ollama pull qwen3.5:4b')."
            model = names[0]
        r = _ollama("/api/chat", {"model": model, "messages": [{"role": "user", "content": prompt}],
                                  "stream": False, "options": {"num_predict": 300}}, timeout=900)
        return f"[{model} on {whoami()['machine']}] " + r.get("message", {}).get("content", "").strip()
    except OSError as e:
        return f"Ollama call failed: {e}"


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=int(os.environ.get("MCP_PORT", "8770")))
    a = ap.parse_args()
    print(f"mcp-hello on http://0.0.0.0:{a.port}/mcp   (Ctrl-C stops it)", flush=True)
    mcp.run("streamable-http", host="0.0.0.0", port=a.port)
EOF_PY
    gen_file "$DIR/client.py" << 'EOF_PY'
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=2.2,<3"]
# ///
"""mcp-hello client: call another laptop's mcp-hello server (dev-demo, install-lan).

    uv run client.py NAME_OR_URL [--port 8770] [--ask "a question for that laptop's model"]

NAME is a laptop from LAN_HOSTS ('lan hosts'); the URL form is http://host:port/mcp.
"""

import argparse
import asyncio
import json

from mcp import Client


def text_of(result):
    """A tool result as text: its structured value when there is one, else its text parts."""
    sc = getattr(result, "structured_content", None) or getattr(result, "structuredContent", None)
    if sc is not None:
        value = sc.get("result", sc) if isinstance(sc, dict) else sc
        return value if isinstance(value, str) else json.dumps(value, indent=2)
    return "\n".join(getattr(c, "text", None) or str(c) for c in result.content)


async def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target")
    ap.add_argument("--port", type=int, default=8770)
    ap.add_argument("--ask", default="")
    a = ap.parse_args()
    url = a.target if a.target.startswith(("http://", "https://")) else f"http://{a.target}:{a.port}/mcp"
    print(f"Connecting to {url}")
    async with Client(url) as client:
        tools = await client.list_tools()
        print("Tools:", ", ".join(t.name for t in tools.tools))
        for name in ("whoami", "shared_services", "ollama_models"):
            print(f"\n== {name}")
            print(text_of(await client.call_tool(name, {})))
        if a.ask:
            print(f"\n== ask_model: {a.ask}")
            print(text_of(await client.call_tool("ask_model", {"prompt": a.ask})))


if __name__ == "__main__":
    asyncio.run(main())
EOF_PY
    gen_file "$DIR/README.md" << 'EOF'
# mcp-hello: MCP between your laptops

A small MCP server (server.py) that tells whoever calls it which laptop answered, what that laptop shares
('lan share status'), which Ollama models it has, and can ask one of them. client.py calls it.

On the laptop that serves (it must be reachable from the others):
1. 'mcp' in LAN_SHARE in ~/.config/dev-init/secrets.env (port 8770 unless LAN_MCP_PORTS says otherwise; 8000
   is left to php artisan serve and symfony serve). Over Tailscale (v93) the other laptops reach it on this
   laptop's Tailscale address with nothing more; with LAN_TAILSCALE=0 it also needs a ChromeOS port forward
   ('lan share ports' lists it).
2. ../run-mcp-hello.sh server

On another laptop:
- ../run-mcp-hello.sh client <laptop>              lists the tools and calls them
- ../run-mcp-hello.sh client <laptop> "a question"  also asks that laptop's Ollama model
- ../run-mcp-hello.sh register <laptop>            adds it to Claude Code (lan mcp), then ask Claude
                                                   "which laptop answers the mcp-hello tools?"
With one laptop: ../run-mcp-hello.sh local runs the server and the client here.

The server binds 0.0.0.0 on purpose: the MCP SDK refuses requests addressed to anything but localhost
while it listens on 127.0.0.1 (DNS rebinding protection). There is no login, so run it on your home
network only. Stop it with Ctrl-C.
EOF
    echo "  preparing the MCP SDK in uv's cache (once)..."
    (cd "$DIR" && timeout 300 uv run -q server.py --help > /dev/null 2>&1) \
        || note "net/mcp-hello: uv could not fetch the MCP SDK now (network?); the launcher fetches it on first use."
    write_run << 'EOF'
demo_need uv "the base install"
demo_need lan install-lan
_cfg() { bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$HOME/.config/dev-init/secrets.env" "$1" 2> /dev/null; }
PORT=$(_cfg LAN_MCP_PORTS | tr ',;' '  ' | awk '{ print $1 }'); PORT=${PORT:-8770}
export LAN_SELF; LAN_SELF=$(_cfg LAN_SELF); [ -n "$LAN_SELF" ] || LAN_SELF=$(_cfg MACHINE_LABEL)
ask_name() {
    local n=${1:-}
    # The list goes to stderr: this runs inside $(...), whose stdout is the answer.
    if [ -z "$n" ]; then lan hosts >&2 2> /dev/null; read -rp "Which laptop? " n; fi
    [ -n "$n" ] || exit 1
    echo "$n"
}
demo_menu "mcp-hello: what now?" server client register local || exit 0
case "$DEMO_CHOICE" in
    server)
        me_ip=$(lan hosts 2> /dev/null | awk -v s="$LAN_SELF" '$1 == s { print $2 }')
        demo_note "Other laptops: 'run-mcp-hello.sh client ${LAN_SELF:-<this laptop>}' or http://${me_ip:-<address>}:$PORT/mcp"
        case " $(_cfg LAN_SHARE | tr ',;' '  ') " in
            *" mcp "*) if [ "$(_cfg LAN_TAILSCALE)" = 0 ]; then demo_note "The ChromeOS port forward for $PORT must be on ('lan share ports' lists it)."
                       else demo_note "Over Tailscale: the other laptops on your tailnet reach port $PORT directly ('lan probe ${LAN_SELF:-<this laptop>} $PORT' from one of them)."; fi ;;
            *) demo_note "'mcp' is not in LAN_SHARE: fine for a try, but 'lan share ports' will not list $PORT until it is." ;;
        esac
        demo_note "No login: home network only. Ctrl-C stops it."
        exec uv run -q server.py --port "$PORT" ;;
    client)
        n=$(ask_name "${2:-}")
        if [ -n "${3:-}" ]; then uv run -q client.py "$n" --port "$PORT" --ask "$3"
        else uv run -q client.py "$n" --port "$PORT"; fi ;;
    register)
        n=$(ask_name "${2:-}")
        lan mcp "$n" "$PORT" "$n-mcp-hello"
        demo_note "In Claude Code, try: which laptop answers the $n-mcp-hello tools, and what does it share?" ;;
    local)
        demo_bg mcp-hello-server uv run -q server.py --port "$PORT"
        demo_wait_port "$PORT" 120 || { echo "The server did not start: $DEMO_LOGS/mcp-hello-server.log"; exit 1; }
        uv run -q client.py 127.0.0.1 --port "$PORT"
        demo_note "That was this laptop talking to itself. From another laptop: run-mcp-hello.sh client ${LAN_SELF:-<this laptop>}" ;;
esac
EOF
    done_demo
}

# =================================================================
# INDEX: ~/dev-demo/README.md and a VS Code / Cursor / Windsurf / Antigravity workspace
# =================================================================
write_index() {
    local f stack name desc run src last=""
    {
        echo "# dev-demo"
        echo
        echo "Hands-on demos for the Chromebook dev environment, downloaded by \`dev-demo-chromebook-v$VERSION.sh\`."
        echo "Each folder is a stack; start a demo with its \`run-*.sh\` launcher (from any terminal). Launchers"
        echo "that take a menu also accept the item as an argument, e.g. \`rust/run-ratatui.sh demo2\`; those"
        echo "that leave something running (DDEV, kind, Terraform, Ansible) take \`down\`."
        echo
        echo "One heavy demo at a time: Linux gets ~6.4 GB of the 8 GB. Heavy: Gemma, the local models (RAG,"
        echo "compare), the Drupal RAG site, Langfuse, SQL Server, Oracle, kind, the Android and Tauri builds. Background logs: \`~/.cache/dev-demo/logs\`."
        for f in "$DEMO_ROOT"/.index/*--*; do
            [ -e "$f" ] || continue
            stack=$(basename "$f"); name=${stack#*--}; stack=${stack%%--*}
            [ -e "$DEMO_ROOT/$stack/run-$name.sh" ] || { rm -f "$f"; continue; }
            IFS=$'\t' read -r desc run src < "$f"
            [ "$stack" != "$last" ] && { echo; echo "## $stack"; echo; last=$stack; }
            echo "- **$name**: $desc  "
            echo "  \`~/dev-demo/$stack/$run\`  ${src:+(source: $src)}"
        done
        echo
        echo "_Updated $(date '+%F %H:%M') by dev-demo v$VERSION._"
    } > "$DEMO_ROOT/README.md"

    # A multi-root workspace of the stack folders, for any VS Code-family editor.
    {
        echo '{'
        echo '  "folders": ['
        local first=1 d
        for d in "$DEMO_ROOT"/*/; do
            d=$(basename "$d")
            compgen -G "$DEMO_ROOT/$d/run-*.sh" > /dev/null || continue
            [ "$first" = 1 ] || echo ','
            printf '    { "path": "%s" }' "$d"; first=0
        done
        echo
        echo '  ],'
        echo '  "settings": { "files.exclude": { "**/node_modules": true, "**/target": true, "**/build": true, "**/.godot": true } }'
        echo '}'
    } > "$DEMO_ROOT/dev-demo.code-workspace"
}

# =================================================================
# RUN
# =================================================================
if [ "$CLEAN" = 1 ]; then
    echo
    echo "demo-clean removes the demo folders for the flags above from $DEMO_ROOT."
    echo "Containers, the kind cluster and DDEV projects keep running: stop them first with their launchers."
    read -rp "Remove them? [y/N] " ans
    [[ "$ans" =~ ^[Yy] ]] || { echo "Nothing removed."; exit 0; }
else
    write_demo_env
    # shellcheck source=/dev/null
    source "$DEMO_ROOT/.demo-env.sh"      # same PATH as the launchers, so 'need' sees what they will see
    trap - EXIT INT TERM                  # the launcher traps are not for the downloader
fi


# =================================================================
# DEMOS: COM under Wine, and retro (DOS / Windows 3.x)
# =================================================================

demo_com() {
    begin com hello-com "Author a COM component (widl + mingw) and drive it under Wine: in-process DLL, out-of-process EXE, type library" \
        "generated by dev-demo (Wine + mingw-w64 + widl from install-com)" || return 0
    need x86_64-w64-mingw32-widl install-com || return 0
    need wine install-com || return 0
    gen_file "$DIR/devhello.idl" << 'IDL_EOF'
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
    gen_file "$DIR/devhello_obj.c" << 'OBJ_EOF'
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
    gen_file "$DIR/devhello_dll.c" << 'DLL_EOF'
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
    gen_file "$DIR/devhello_exe.c" << 'EXE_EOF'
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
    gen_file "$DIR/devhello_client.c" << 'CLI_EOF'
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
    gen_file "$DIR/devhello.def" << 'DEF_EOF'
LIBRARY devhello
EXPORTS
    DllGetClassObject PRIVATE
    DllCanUnloadNow PRIVATE
    DllRegisterServer PRIVATE
    DllUnregisterServer PRIVATE
DEF_EOF
    gen_file "$DIR/devhello.rc" << 'RC_EOF'
1 TYPELIB "devhello.tlb"
RC_EOF
    gen_file "$DIR/build.sh" << 'BUILD_EOF'
#!/bin/bash
# build.sh ARCH(32|64): widl compiles devhello.idl to a header, IIDs and a type library; mingw builds
# the in-process DLL, the out-of-process EXE and the client. Written by dev-demo; edit and rerun freely.
set -e
a=${1:-64}
: "${COM_IDL_INC:?run through run-hello-com.sh, which finds the IDL include dir}"
if [ "$a" = 32 ]; then T=i686-w64-mingw32; L=$COM_TLB32; else T=x86_64-w64-mingw32; L=$COM_TLB64; fi
rm -rf "w$a"; mkdir "w$a"
$T-widl -m"$a" -I"$COM_IDL_INC" -L "$L" -h -H "w$a/devhello.h" -u -U "w$a/devhello_i.c" -t -T "w$a/devhello.tlb" devhello.idl
cd "w$a"
cp ../devhello_obj.c ../devhello_dll.c ../devhello_exe.c ../devhello_client.c ../devhello.def ../devhello.rc .
$T-windres devhello.rc -O coff -o devhello_res.o
CF="-O2 -municode -I."
# 32-bit: lets ld match the .def's undecorated names to the stdcall exports without a warning each.
LF=; [ "$a" = 32 ] && LF=-Wl,--enable-stdcall-fixup
$T-gcc $CF $LF -shared -o devhello.dll devhello_dll.c devhello_obj.c devhello_i.c devhello_res.o devhello.def -lole32 -loleaut32 -luuid -ladvapi32 -static-libgcc
$T-gcc $CF $LF -o devhello_local.exe devhello_exe.c devhello_obj.c devhello_i.c devhello_res.o -lole32 -loleaut32 -luuid -ladvapi32 -static-libgcc
$T-gcc $CF -o devhello_client.exe devhello_client.c devhello_i.c -lole32 -loleaut32 -luuid -static-libgcc
echo "built w$a: devhello.dll, devhello_local.exe, devhello_client.exe"
BUILD_EOF
    FRESH=1
    write_run << 'EOF'
demo_need x86_64-w64-mingw32-widl install-com
demo_need wine install-com
export WINEPREFIX="${DEV_COM_PREFIX:-$HOME/.local/share/wine/com}" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
# The widl paths: from the ~/.bashrc COM block if a new terminal exported them, else discovered.
export COM_IDL_INC="${DEV_COM_IDL_INC:-$(dirname "$(find /usr/include/wine -name unknwn.idl 2> /dev/null | head -n 1)" 2> /dev/null)}"
export COM_TLB64="${DEV_COM_TLB64:-/usr/lib/x86_64-linux-gnu/wine/x86_64-windows}"
export COM_TLB32="${DEV_COM_TLB32:-/usr/lib/i386-linux-gnu/wine/i386-windows}"
[ -f "$COM_IDL_INC/unknwn.idl" ] || { echo "Cannot find unknwn.idl (libwine-dev): rerun dev-setup with install-com."; exit 1; }
build() { [ -x "w$1/devhello.dll" ] || { echo "Building $1-bit..."; bash build.sh "$1"; }; }
while demo_menu "COM under Wine (DevHello: Greet + Add)" \
        "inproc64: build 64-bit, regsvr32 the DLL, CoCreateInstance + call it" \
        "local64: 64-bit out-of-process server (the DCOM activation path)" \
        "inproc32: the 32-bit build (most legacy COM and ActiveX is 32-bit)" \
        "typelib: what widl generated (header, IIDs, .tlb) and the registry entries" \
        "unregister: remove DevHello from the COM prefix"; do
    case "$DEMO_CHOICE" in
        inproc64*) build 64; ( cd w64 && wine regsvr32 devhello.dll && echo "--- calling it:" && wine devhello_client.exe inproc )
                   demo_note "The DLL is loaded into the client process. 'unregister' cleans it out again." ;;
        local64*)  build 64; ( cd w64 && wine devhello_local.exe /regserver && echo "--- calling it:" && wine devhello_client.exe local )
                   demo_note "Client and server are different processes (different pids): COM marshaled the call between them, the way DCOM does across machines." ;;
        inproc32*) build 32; ( cd w32 && wine regsvr32 devhello.dll && echo "--- calling it:" && wine devhello_client.exe inproc ) ;;
        typelib*)  build 64
                   echo "widl generated in w64/:"; ls -1 w64/devhello.h w64/devhello_i.c w64/devhello.tlb
                   echo; echo "IDevHello methods, from devhello.h:"; grep -oE 'HRESULT[^;]*(Greet|Add)\b[^;]*' w64/devhello.h | head
                   echo; echo "Registry (in the Wine prefix), ProgID -> CLSID:"
                   wine reg query 'HKCR\DevTest.Hello\CLSID' 2>/dev/null || echo "  (register it first: the inproc64 item)" ;;
        unregister*) [ -x w64/devhello.dll ] && ( cd w64 && wine regsvr32 /u devhello.dll 2>/dev/null; wine devhello_local.exe /unregserver 2>/dev/null )
                     [ -x w32/devhello.dll ] && ( cd w32 && wine regsvr32 /u devhello.dll 2>/dev/null )
                     echo "DevHello unregistered." ;;
    esac
    [ -n "${1:-}" ] && break
done
demo_note "ATL/MFC need MSVC (clang-cl + xwin, per project). ActiveX in a browser is dead; an ActiveX control hosted in a container app can work under Wine."
EOF
    done_demo
}

demo_retro() {
    begin retro matrix "Build one program for DOS 16, DOS/4GW 32, Win16, Win32 and Win64, and run each on Wine, DOSBox-X or inside a retro guest" \
        "generated by dev-demo (Open Watcom + mingw + DOSBox-X + Wine from install-retro)" || return 0
    need wcl install-retro || return 0
    gen_file "$DIR/bits.c" << 'EOF'
#include <stdio.h>
/* The pointer size tells Win32 (4) and Win64 (8) apart; int is 4 bytes on both. */
int main(void) { printf("hello from %d-bit Windows\n", (int)sizeof(void *) * 8); return 0; }
EOF
    gen_file "$DIR/dosfile.c" << 'EOF'
/* A DOS program that writes a file, so a headless run can be checked; interactively it just runs. */
#include <stdio.h>
int main(void) {
    FILE *f = fopen("OUT.TXT", "w");
    printf("DOS %d-bit program running under DOSBox-X\n", (int)sizeof(int) * 8);
    if (f) { fprintf(f, "dos %d-bit ok\n", (int)sizeof(int) * 8); fclose(f); }
    return 0;
}
EOF
    gen_file "$DIR/win16.c" << 'EOF'
/* A Win16 GUI app (NE executable) - the format Delphi 1 produces. A message box, then it exits. */
#include <windows.h>
int PASCAL WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR lpCmd, int nShow)
{
    char buf[128];
    wsprintf(buf, "Win16 (NE) app running on Windows %u.%u, via Wine's 16-bit support.",
             (unsigned)LOBYTE(LOWORD(GetVersion())), (unsigned)HIBYTE(LOWORD(GetVersion())));
    MessageBox(NULL, buf, "dev-demo win16", MB_OK);
    return 0;
}
EOF
    gen_file "$DIR/build.sh" << 'BUILD_EOF'
#!/bin/bash
# Build all five targets. Open Watcom does DOS16, DOS/4GW 32, Win16 and Win32; mingw does Win64.
set -e
: "${WATCOM:?rerun dev-setup with install-retro, then open a new terminal}"
wcl -q -bt=dos -ms -fe=dos16.exe dosfile.c
wcl386 -q -bt=dos -l=dos4g -fe=dos32.exe dosfile.c
INCLUDE="$WATCOM/h:$WATCOM/h/win" wcl -q -bt=windows -zw -ml -l=windows -fe=win16.exe win16.c
wcl386 -q -bt=nt -l=nt -fe=win32.exe bits.c
x86_64-w64-mingw32-gcc -O2 -o win64.exe bits.c
cp "$WATCOM/binw/dos4gw.exe" .
echo "built: dos16.exe dos32.exe (DOSBox-X)  win16.exe win32.exe win64.exe (Wine)"
BUILD_EOF
    # v92: the two STEPS files are documentation the bundle owns, so they are rewritten on every run
    # (gen_file keeps a file that exists; a retro/matrix folder made by v85-v91 has the old Delphi notes).
    cat > "$DIR/STEPS-delphi1.md" << 'EOF'
# Delphi 1.0 on this Chromebook (dev-demo v93)
(Delphi 3, 4, 5, 6 and 7: STEPS-delphi.md.)

Delphi 1 is a 16-bit Windows 3.1 application. Two routes, both set up by install-retro. Put the Delphi 1
install files (the disks' contents or the CD's, SETUP.EXE with them) in ~/win31/install/apps first.

## Wine: the `delphi1` command (forms, code, non-database programs)

    delphi1 setup      # a 32-bit Wine prefix (~/.local/share/wine/delphi1), Delphi's SETUP.EXE in a
                       # virtual desktop (install into C:\DELPHI), then: black desktop, TEMP=C:\TEMP,
                       # MS Sans Serif -> Tahoma, smoothed fonts, launcher icons pointed at delphi1
    delphi1            # the IDE, in a virtual desktop the size of the screen
    delphi1 run X.EXE  # another program (Image Editor, a compiled project) in the same desktop

What makes it work (worked out by hand on Oct 2 2026; delphi1 does all of it):
- Delphi's own 16-bit OLE2 (COMPOBJ, OLE2, OLE2DISP, OLE2NLS, STORAGE, TYPELIB in C:\WINDOWS\SYSTEM) instead
  of Wine's built-in compobj.dll16, which hands Delphi's startup code no allocator. The override needs the
  .dll16 suffix: WINEDLLOVERRIDES="compobj.dll16,ole2.dll16,...=n".
- A virtual desktop (`wine explorer /desktop=...`): without one the IDE starts but its windows never show on
  ChromeOS. Sized to the X screen: a smaller one leaves an area Wine never repaints once the window grows.
- Its own prefix: Delphi installed into the COM prefix (the v85-v91 quick route) crashes on launch.
  `delphi1 setup` offers to remove that old install; it never does so unasked.

The IDE options: DELPHI.INI is in C:\WINDOWS (~/.local/share/wine/delphi1/drive_c/windows), not in
C:\DELPHI\BIN. `delphi1 setup` and every `delphi1` start set IntegratedDebugging=0 there (Wine only stubs
the Win16 debug hooks, so Run fails with "Error creating process: Internal Windows error (15)" otherwise),
and the editor font Courier New 10 where none is set. Other options you change (colours, palette, gallery):
`delphi1 ini save` keeps DELPHI.INI, and every later `delphi1 setup` restores it.

Limits of the Wine route, all confirmed on Oct 2 2026:
- No integrated debugger (above): run the program, debug in win31.
- No Database Desktop: it crashes right after GetTempFileName (Wine returns ~QQ3.tmp where Windows 3.1
  returned ~QQ0003.TMP). Its launcher entry opens win31 instead.
- No BDE table access (a TTable / DataSource / DBGrid at design time crashes the IDE): the Delphi 1 BDE uses
  DOS real-mode services Wine dropped. Database work belongs to win31.
- Object Inspector drop-down lists close at once. Double-click a fixed-choice value to cycle it; type other
  values (a component or table name).
- Optional: tables made in win31's Database Desktop can be opened from Delphi under Wine through a Wine drive
  mapped to the DOSBox-X C: (never with both running: Paradox locking does not span the two):
      ln -s ~/win31/drive_c ~/.local/share/wine/delphi1/dosdevices/w:

## DOSBox-X + real Windows 3.11: the `win31` command (everything, the debugger and the BDE included)
Needs your own Windows 3.1/3.11 media.

1. Copy the Windows 3.1x setup disks (loose files, or .img/.ima images) into ~/win31/install/windows
2. Delphi's files stay in ~/win31/install/apps   (D:\ inside win31)
3. win31 setup      # installs Windows 3.11 into C:\WINDOWS (leave 32-bit disk access OFF)
4. win31            # boots Windows; File > Run  D:\SETUP.EXE  installs Delphi onto C:
5. win31            # from then on, Delphi is in Program Manager

Both routes run the same 16-bit code, which this demo's win16 item exercises directly.
EOF
    # v93: STEPS-delphi.md, Delphi 3, 4, 5, 6 and 7 (real Windows guests and 'delphi N' under Wine).
    cat > "$DIR/STEPS-delphi.md" << 'EOF'
# Delphi 3, 4, 5, 6 and 7 on this Chromebook (dev-demo v93)

Every version gets two routes: a real Windows guest, where the integrated debugger and the BDE work as on
hardware, and a Wine prefix for quick editing and compiling. Delphi 1 has its own notes (STEPS-delphi1.md).
The media and serial numbers are yours; nothing is downloaded.

| Delphi | Real Windows guest (engine)          | Wine (`delphi N`, Windows version reported) | Wine status                 |
|--------|--------------------------------------|---------------------------------------------|-----------------------------|
| 1      | win31 (DOSBox-X)                     | `delphi1` (its own command)                 | works; no debugger, no BDE  |
| 3      | win95 (DOSBox-X) or winnt40 (QEMU)   | `delphi 3` (win95)                          | untested on real discs      |
| 4      | win95 (DOSBox-X) or winnt40 (QEMU)   | `delphi 4` (win98)                          | untested on real discs      |
| 5      | win2000 (QEMU); NT 4.0 also works    | `delphi 5` (win2k)                          | untested on real discs      |
| 6      | win2000 (QEMU); NT 4.0 SP6a likely   | `delphi 6` (win2k)                          | untested; old debugger reports |
| 7      | win2000 (QEMU)                       | `delphi 7` (winxp)                          | untested; the best-known case |

Delphi 6 and 7 do not support Windows 95, and Windows 3.1 runs only Delphi 1. Delphi 3 and 4 can share one
guest; 5, 6 and 7 share win2000 (Delphi 5 also runs on 95, 98 and NT 4.0, but 2000 is its era, as under Wine). The QEMU guests run close to native speed only with KVM (`retro` says whether
this Chromebook has it); without it they emulate the CPU and are slow.

## Media: where each CD goes

    ~/delphi/install/N            the CD for the Wine route: an .iso, or the CD's files (delphi N setup)
    ~/<guest>/install/apps        the same CD as an .iso for a real Windows guest: it is F: there

One .iso can serve both: copy it to both places, or link it (`ln ~/delphi/install/7/d7.iso ~/win2000/install/apps/`).

## Wine: the `delphi` command

    delphi                 which versions are set up, and where each one's media goes
    delphi 7 setup         a 32-bit prefix (~/.local/share/wine/delphi7), the CD as drive D: (an .iso is
                           unpacked once into ~/delphi/.cd/7), its installer in a virtual desktop (keep
                           the default folders), then: Windows XP reported, black desktop, TEMP=C:\TEMP,
                           MS Sans Serif -> Tahoma, smoothed core fonts, launcher icons pointed at 'delphi 7'
    delphi 7               the IDE, in a virtual desktop the size of the screen
    delphi 7 run X.EXE     another program in the same desktop (a compiled project, a tool from Bin\)
    delphi 7 ini save      keeps your IDE options (HKCU\Software\Borland) in ~/.config/dev-retro/delphi7.reg;
                           every later 'delphi 7 setup' restores them

`delphi 7 setup FILE` names the installer when the CD's own choice (autorun.inf, INSTALL.EXE, SETUP.EXE) is
the wrong one. The integrated debugger is left on. If Run stops with a debugger error, turn it off (Tools >
Debugger Options > Integrated debugging), run the program, and debug in the real Windows guest. Per-version
fixes get worked out on your discs, as Delphi 1's were: the order is 7, then 6, 4 and 3.

## A real Windows guest

Delphi 7, 6 or 5 in Windows 2000 (Delphi 3 or 4 in NT 4.0 the same way):

1. Install the guest first: STEPS-winnt.md ('win2000 setup').
2. Put the Delphi CD's .iso in ~/win2000/install/apps. Several CDs: `win2000 cd list`, and `win2000 cd NAME`
   picks one (it swaps the CD while the guest runs).
3. `win2000`, then inside Windows run F:\INSTALL.EXE (or the CD's autorun). The serial is on your sleeve.
4. Before trying risky options: `win2000 snapshot save delphi7` with the guest shut down; `snapshot restore`
   goes back.

Delphi 3 or 4 in Windows 95 (DOSBox-X):

1. 'win95 setup' (Windows 95 OSR2 CD in ~/win95/install), then 'win95'.
2. The Delphi CD's .iso in ~/win95/install/apps; it is F: at the next start ('win95 cd NAME' picks another;
   DOSBox-X cannot swap that CD while Windows 95 runs, so shut down first).
3. Inside Windows 95 run F:\SETUP.EXE.
4. Undo points: `win95 snapshot save NAME` with the guest shut down (a sparse copy of hdd.img in
   ~/win95/snapshots), `win95 snapshot restore NAME` to go back.
5. If Delphi's debugger misbehaves on DOSBox-X's fast core: `win95 --core normal`. NT 4.0 (winnt40) is the
   fallback guest for 3 and 4.

## Moving files and sizes

D: in win95, winnt40 and win2000 is the exchange disk: `<guest> put FILE` and `<guest> get` while the guest
is off. Its size is RETRO_EXCHANGE_MB (default 1 GB; 512 for less disk), Windows 95's disk RETRO_WIN95_DISK_MB
(default 2 GB), both in ~/.config/dev-init/secrets.env and read when the disk is made. A disk that exists
keeps its size: `<guest> exchange recreate` rebuilds the exchange disk (it offers to save its files first),
and `retro sizes` shows what is in effect.

## The BDE

Delphi 3-7 install the Borland Database Engine in the real guests as on hardware. Still open, to settle with
your discs: whether an old BDE reports "insufficient disk space" on these larger disks (some versions misread
large free space). If it does, a smaller disk is the first thing to try (RETRO_WIN95_DISK_MB for a new
win95 disk); note what happened, and the next bundle version can build the fix in.
EOF
    cat > "$DIR/STEPS-winnt.md" << 'EOF'
# Windows NT 4.0 and Windows 2000 in QEMU (dev-demo v93)

Your media, in each guest's install folder: the install CD as an .iso (both CDs boot). For NT 4.0 a set of
boot floppies (.img) works too when the CD does not boot. Program CDs (Delphi, Office, compilers) go in
install/apps as .iso files: the guest's second CD drive (F:) holds one ('<guest> cd list', '<guest> cd NAME',
which swaps it while the guest runs). A service-pack .iso in install/ rides in that drive when no program CD
is there. Product keys are yours too. Delphi in these guests: STEPS-delphi.md.

    winnt40 setup      # creates ~/winnt40/disk.qcow2 (4 GB) after a free-space check, boots the CD
    win2000 setup      # the same with an 8 GB disk
    winnt40            # boots the installed guest; 'winnt40 setup' again resumes a half-done install

Drives inside the guest: C: the disk, D: the exchange disk (FAT16, 1 GB by default: RETRO_EXCHANGE_MB in
~/.config/dev-init/secrets.env, read when it is made; `winnt40 put FILE` and `winnt40 get` while the guest is
off; `winnt40 exchange info`), E: the install CD (`winnt40 cd --windows FILE` swaps it), F: the program CD.

## First boot, NT 4.0
1. Text-mode setup: create the system partition on the 4 GB disk (NT 4.0 cannot format more), FAT or NTFS.
2. Graphical setup: network adapter "AMD PCNET Family"; on the display page do NOT press Test (it can hang);
   pick a resolution and continue.
3. At "Press Ctrl+Alt+Del to log on": `winnt40 keys ctrl-alt-del` in a terminal (ChromeOS keeps the real one).
4. The mouse is captured when you click in the window: Ctrl+Alt+G releases it.
5. Sound: Control Panel > Multimedia > Devices > Add > Creative Labs Sound Blaster 1.X, Pro, 16 (I/O 220, IRQ 5).
6. Service Pack 6a: put its .iso in ~/winnt40/install, boot, run F:\...\UPDATE.EXE when no program CD is
   in F: (`winnt40 cd eject` first), or `winnt40 cd --windows SP6A.ISO` while it runs to put it in E:.

## First boot, Windows 2000
1. Setup runs straight through; the PCnet network and AC97 sound drivers are on the CD.
2. Log on with `win2000 keys ctrl-alt-del` when it asks. The mouse is a USB tablet: no capture.
3. Service Pack 4: its .iso in ~/win2000/install, then run it from F:.

## Fonts and font smoothing (both guests, and win31 / win95)
`winnt40 fonts` (with the guest off) puts the TrueType core fonts and Tahoma from the Wine prefixes in
D:\FONTS with a README.TXT: Control Panel > Fonts > File > Install New Font, then D:\FONTS. ClearType began
with Windows XP; NT 4.0 (Display > Plus!) and 2000 (Display > Effects) have grayscale "Smooth edges of screen
fonts", in 16-bit colour or more. For sharp pixels, untick View > Zoom To Fit in QEMU's window.

## When something goes wrong
- Setup blue-screens early: CPU=pentium instead of pentium3 in ~/<guest>/config.
- NT 4.0 installs but will not boot a second time (QEMU's old qcow2 bug): `rm ~/winnt40/disk.qcow2`,
  then `winnt40 setup --raw` (a raw disk; no snapshots).
- Slow: without /dev/kvm QEMU emulates the CPU in software. `retro` says which this Chromebook has; the
  NT guests belong on one with KVM.
- Undo points: `winnt40 snapshot save clean` with the guest shut down, `winnt40 snapshot restore clean` later.
EOF
    FRESH=1
    write_run << 'EOF'
demo_need wcl install-retro
export WINEPREFIX="${DEV_COM_PREFIX:-$HOME/.local/share/wine/com}" WINEDEBUG=-all
build() { [ -x win64.exe ] || { echo "Building the five programs..."; bash build.sh; }; }
# v92 review: dev-setup before v92 has no 'retro'; fall back to the v91 commands (DOSBox-X, Wine, file).
RETRO_MISSING=0
if ! command -v retro > /dev/null 2>&1; then
    RETRO_MISSING=1
    demo_note "The retro command is missing (dev-setup v92 adds it with install-retro): DOS builds open in DOSBox-X, Windows ones in Wine."
    retro() {
        case "$1 ${2:-} ${3:-}" in
            "run --in dos") dosbox-x -c "mount c \"$PWD\"" -c "c:" -c "$4" ;;
            "run --in wine") wine "$4" ;;
            which*) file "$2" | sed 's/, .*//' ;;
            *) demo_note "Rerun dev-setup with install-retro (v92 or later) for the Windows guests." ;;
        esac
    }
fi
# v92: run a build inside an installed guest through 'retro run --in' (it puts the file on the guest's
# exchange disk, D:, or mounts its folder, then boots); a guest not installed yet says how.
in_guest() {   # in_guest GUEST PROGRAM
    build
    if [ "$RETRO_MISSING" = 1 ]; then demo_note "the retro command is missing: rerun dev-setup with install-retro (v92)"; return 0; fi
    if "$HOME/.local/lib/dev-retro/dev-retro" "$1" status 2> /dev/null | grep -q 'not installed'; then
        demo_note "$1 is not installed yet: your media in ~/$1/install (Windows 3.1: ~/win31/install/windows), then '$1 setup'."
        return 0
    fi
    retro run --in "$1" "$2"
}
demo_note "DOS programs open a DOSBox-X window (text in a TrueType font: ~/.config/dev-retro/dos.conf); Windows programs run under Wine, or inside a real Windows with the 'in-' items."
while demo_menu "Wine <-> DOSBox-X <-> QEMU matrix" \
        "build: compile all five (Open Watcom + mingw)" \
        "which: what 'retro run' picks for each build, and why" \
        "dos16: 16-bit DOS, in DOSBox-X" \
        "dos32: 32-bit DOS/4GW, in DOSBox-X" \
        "win16: 16-bit Windows (Delphi 1's format), on Wine" \
        "win32: 32-bit Windows, on Wine" \
        "win64: 64-bit Windows, on Wine" \
        "in-win31: win16.exe inside Windows 3.1 (DOSBox-X)" \
        "in-win95: win32.exe inside Windows 95 (DOSBox-X; it is on D:)" \
        "in-winnt40: win32.exe inside Windows NT 4.0 (QEMU; it is on D:)" \
        "in-win2000: win32.exe inside Windows 2000 (QEMU; it is on D:)" \
        "delphi1: Delphi 1 under Wine or in Windows 3.1 (STEPS-delphi1.md)" \
        "delphi: Delphi 3, 4, 5, 6, 7 in a real Windows guest and under Wine (STEPS-delphi.md)" \
        "winnt: NT 4.0 and 2000 first-boot steps (STEPS-winnt.md)"; do
    case "$DEMO_CHOICE" in
        build*) bash build.sh; file ./*.exe | sed 's/, .*//' ;;
        which*) build; for p in dos16.exe dos32.exe win16.exe win32.exe win64.exe; do retro which "$p"; done ;;
        dos16*) build; retro run --in dos dos16.exe ;;
        dos32*) build; retro run --in dos dos32.exe ;;
        win16*) build; demo_note "Wine runs the NE (16-bit) binary directly - the same path Delphi 1 uses."; retro run --in wine win16.exe ;;
        win32*) build; wine win32.exe ;;
        win64*) build; wine win64.exe ;;
        in-win31*) in_guest win31 win16.exe ;;
        in-win95*) in_guest win95 win32.exe ;;
        in-winnt40*) in_guest winnt40 win32.exe ;;
        in-win2000*) in_guest win2000 win32.exe ;;
        delphi1*) cat STEPS-delphi1.md
                  if [ -n "$(find ~/.local/share/wine/delphi1/drive_c -maxdepth 3 -ipath '*/delphi/bin/delphi.exe' 2> /dev/null | head -n 1)" ]; then
                      demo_note "Delphi 1 is set up under Wine: 'delphi1' (or its launcher icon) starts the IDE."
                  elif [ -n "$(find ~/win31/install/apps -maxdepth 4 -iname setup.exe 2> /dev/null | head -n 1)" ]; then
                      demo_note "Delphi's setup is in ~/win31/install/apps: 'delphi1 setup' (Wine), or install it inside win31 (D:)."
                  else
                      demo_note "Copy Delphi 1's files into ~/win31/install/apps first, then 'delphi1 setup' or win31."
                  fi ;;
        delphi\ *|delphi:*|delphi) cat STEPS-delphi.md
                  if command -v delphi > /dev/null 2>&1; then delphi
                  else demo_note "The 'delphi' command comes with dev-setup v93 (install-retro)."; fi ;;
        winnt*) cat STEPS-winnt.md; retro ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# =================================================================
# DEMOS: personal agents (v86): Hermes Agent and OpenClaw
# =================================================================

demo_hermes() {
    begin agents hermes "Hermes Agent: chat with your model, see what an agent sends a model (offline), add a skill of your own" \
        "generated here; Hermes Agent: https://github.com/NousResearch/hermes-agent" || return 0
    need hermes install-hermes || return 0
    present || FRESH=1
    gen_file "$DIR/mockllm.py" << 'MOCK_EOF'
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
    gen_file "$DIR/offline.sh" << 'OFFLINE_EOF'
#!/bin/bash
# offline.sh hermes|openclaw: one agent turn against mockllm.py, a stand-in model on this machine, with a
# SCRATCH copy of the agent (your own config, sessions and keys are not used). Shows what an agent
# actually sends to a model: how many requests, how many tools it offers, how big its prompt is.
cd "$(dirname "$0")" || exit 1
# Offline means offline: the scratch agent never sees your API keys, so nothing reaches a real provider.
unset ANTHROPIC_API_KEY OPENROUTER_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY NOUS_API_KEY DEEPSEEK_API_KEY OLLAMA_API_KEY OLLAMA_REMOTE
P=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
rm -f requests.log
python3 mockllm.py "$P" "MOCK-OK: this answer came from mockllm.py, not a real model" > mock.log 2>&1 & MOCK=$!
SCRATCH=""
trap 'kill $MOCK 2> /dev/null; [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"' EXIT
for _ in $(seq 1 40); do curl -fsS "http://127.0.0.1:$P/v1/models" > /dev/null 2>&1 && break; sleep 0.25; done
case "${1:-}" in
    hermes)
        SCRATCH="$HOME/.hermes/.dev-demo-$$"; mkdir -p "$SCRATCH"; export HERMES_HOME="$SCRATCH"
        # A new home would borrow Claude Code's and Codex's logins; this one keeps to itself.
        hermes config set auth.adopt_external_logins false > /dev/null && hermes config set model.provider custom > /dev/null && hermes config set model.base_url "http://127.0.0.1:$P/v1" > /dev/null \
            && hermes config set model.default mock-model > /dev/null || exit 1
        echo "--- hermes -z \"What can you do?\""
        hermes -z "What can you do?" 2> /dev/null ;;
    openclaw)
        SCRATCH="$PWD/.offline-openclaw"; rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
        export OPENCLAW_STATE_DIR="$SCRATCH" OPENCLAW_CONFIG_PATH="$SCRATCH/openclaw.json"
        openclaw telemetry off > /dev/null 2>&1
        openclaw onboard --non-interactive --accept-risk --mode local --flow manual --auth-choice custom-api-key \
            --custom-base-url "http://127.0.0.1:$P/v1" --custom-model-id mock-model --custom-api-key offline --custom-text-input \
            --gateway-bind loopback --gateway-auth token --skip-daemon --skip-channels --skip-skills --skip-search \
            --skip-ui --skip-health --skip-hooks > "$SCRATCH/onboard.log" 2>&1 || { tail -n 5 "$SCRATCH/onboard.log"; exit 1; }
        echo "--- openclaw agent --local -m \"What can you do?\""
        # --log-level error keeps OpenClaw's own progress lines out of the answer.
        openclaw --log-level error agent --local -m "What can you do?" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^\[[a-z/_-]+\] ' ;;
    *) echo "usage: offline.sh hermes|openclaw"; exit 2 ;;
esac
echo
echo "--- what the agent sent to the model (requests.log):"
python3 - << 'PY'
import json
reqs = [json.loads(l) for l in open("requests.log") if l.strip()]
chat = [r for r in reqs if r.get("messages")]
for n, r in enumerate(chat, 1):
    tools = [t.get("function", {}).get("name", "?") for t in (r.get("tools") or [])]
    chars = sum(len(json.dumps(m.get("content", ""))) for m in r["messages"])
    roles = ", ".join(m["role"] for m in r["messages"])
    print(f"request {n}: {len(r['messages'])} messages ({roles}), {chars} characters, {len(tools)} tools")
    if tools:
        print("  tools: " + ", ".join(tools[:30]) + (" ..." if len(tools) > 30 else ""))
big = max(chat, key=lambda r: len(json.dumps(r)), default=None)
if big:
    system = next((m.get("content") for m in big["messages"] if m["role"] == "system"), "")
    if isinstance(system, list):
        system = " ".join(p.get("text", "") for p in system if isinstance(p, dict))
    print("\nthe start of its system prompt:\n  " + str(system)[:600].replace("\n", "\n  "))
PY
OFFLINE_EOF
    gen_file "$DIR/skills/dev-bundle/SKILL.md" << 'SKILL_EOF'
---
name: dev-bundle
description: Answer questions about this Chromebook's dev-setup bundle - which stacks and demos are installed, and the helper commands it adds (lan, devdb, mssql, oracle, ldap, win31, wine-com, ollama-remote). Use when asked what is installed here, how to start a demo or a database, or how the laptops share services.
---

# The dev-setup bundle on this Chromebook

This Linux container was provisioned by a versioned bundle of four scripts (setup, init, test, demo).
Look before you change anything, and ask before you start, stop or install something.

## Where to look
- Installed demos: `~/dev-demo/README.md` lists every demo and its launcher (`~/dev-demo/<stack>/run-<name>.sh`).
- The newest test results: the most recent `dev-test-*.log` in the `assets/logs` folder next to the bundle scripts.
- The shell setup the bundle writes: the marked `# >>> dev-setup ... >>>` blocks in `~/.bashrc`.

## Helper commands (each explains itself with `help` or no arguments)
- `lan` - the laptop network: `lan status`, `lan scan`, `lan url NAME`, `lan share status`.
- `devdb`, `mssql`, `oracle` - the SQL Server and Oracle containers: `mssql up`, `mssql sql`, `mssql down`.
- `ldap` - the LDAP directories: `ldap status`.
- `win31` - Windows 3.1x in DOSBox-X: `win31 where`.
- `wine-com` - runs a program in the COM Wine prefix.
- `ollama` (this machine), `ollama-remote` (the machine in OLLAMA_REMOTE).

## Never
- Never print, copy, summarise or send the contents of `~/.config/dev-init/secrets.env` or any `.env` file: they hold API keys.
- Never open a port to the network or change `LAN_SHARE` without being asked.
SKILL_EOF
    write_run << 'EOF'
demo_need hermes install-hermes
chmod +x offline.sh 2> /dev/null
has_model() { p=$(hermes config get model.provider 2> /dev/null); [ -n "$p" ] && [ "$p" != auto ]; }
while demo_menu "Hermes Agent" \
        "chat: talk to Hermes with the model dev-init gave it (/exit leaves)" \
        "offline: one turn against a stand-in model on this machine, and what Hermes sent it (no key needed)" \
        "skill: add dev-bundle, a skill written here, to ~/.hermes/skills, then list your skills" \
        "doctor: hermes doctor (what is configured, what is missing)"; do
    case "$DEMO_CHOICE" in
        chat*)    if has_model; then
                      demo_note "Hermes asks before running a risky command; say no when unsure. Try: what is installed on this Chromebook? (after the skill item)"
                      hermes
                  else
                      demo_note "Hermes has no model yet: put a key (AGENT_ANTHROPIC_API_KEY, OPENROUTER_API_KEY) or OLLAMA_REMOTE + AGENT_MODEL in ~/.config/dev-init/secrets.env and rerun dev-init with install-hermes. The offline item works without one."
                  fi ;;
        offline*) ./offline.sh hermes
                  demo_note "Every turn sends the whole system prompt and the tool list, which is why agents need a big context window and why a cloud model bills more per message than a chat does." ;;
        skill*)   mkdir -p ~/.hermes/skills/dev-bundle && cp skills/dev-bundle/SKILL.md ~/.hermes/skills/dev-bundle/SKILL.md
                  hermes skills list 2> /dev/null | grep -E "Name|dev-bundle|local"
                  demo_note "A skill is a SKILL.md: a name, a description saying when to use it, and instructions. This one is local and yours; read any skill you did not write before you add it. Remove it: rm -r ~/.hermes/skills/dev-bundle" ;;
        doctor*)  hermes doctor
                  demo_note "Nous Portal, Nous Research's own model subscription, signs in through a browser: hermes portal" ;;
    esac
    [ -n "${1:-}" ] && break
done
demo_note "Messaging (Telegram, Discord, Slack...): 'hermes gateway setup', with a bot account made for it. The container sleeps with the Chromebook, so the bot does too."
EOF
    done_demo
}

demo_openclaw() {
    begin agents openclaw "OpenClaw: chat, the Control UI on loopback, see what an agent sends a model (offline), a skill of your own, a security audit" \
        "generated here; OpenClaw: https://github.com/openclaw/openclaw" || return 0
    need openclaw install-openclaw || return 0
    present || FRESH=1
    gen_file "$DIR/mockllm.py" << 'MOCK_EOF'
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
    gen_file "$DIR/offline.sh" << 'OFFLINE_EOF'
#!/bin/bash
# offline.sh hermes|openclaw: one agent turn against mockllm.py, a stand-in model on this machine, with a
# SCRATCH copy of the agent (your own config, sessions and keys are not used). Shows what an agent
# actually sends to a model: how many requests, how many tools it offers, how big its prompt is.
cd "$(dirname "$0")" || exit 1
# Offline means offline: the scratch agent never sees your API keys, so nothing reaches a real provider.
unset ANTHROPIC_API_KEY OPENROUTER_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY NOUS_API_KEY DEEPSEEK_API_KEY OLLAMA_API_KEY OLLAMA_REMOTE
P=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
rm -f requests.log
python3 mockllm.py "$P" "MOCK-OK: this answer came from mockllm.py, not a real model" > mock.log 2>&1 & MOCK=$!
SCRATCH=""
trap 'kill $MOCK 2> /dev/null; [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"' EXIT
for _ in $(seq 1 40); do curl -fsS "http://127.0.0.1:$P/v1/models" > /dev/null 2>&1 && break; sleep 0.25; done
case "${1:-}" in
    hermes)
        SCRATCH="$HOME/.hermes/.dev-demo-$$"; mkdir -p "$SCRATCH"; export HERMES_HOME="$SCRATCH"
        # A new home would borrow Claude Code's and Codex's logins; this one keeps to itself.
        hermes config set auth.adopt_external_logins false > /dev/null && hermes config set model.provider custom > /dev/null && hermes config set model.base_url "http://127.0.0.1:$P/v1" > /dev/null \
            && hermes config set model.default mock-model > /dev/null || exit 1
        echo "--- hermes -z \"What can you do?\""
        hermes -z "What can you do?" 2> /dev/null ;;
    openclaw)
        SCRATCH="$PWD/.offline-openclaw"; rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
        export OPENCLAW_STATE_DIR="$SCRATCH" OPENCLAW_CONFIG_PATH="$SCRATCH/openclaw.json"
        openclaw telemetry off > /dev/null 2>&1
        openclaw onboard --non-interactive --accept-risk --mode local --flow manual --auth-choice custom-api-key \
            --custom-base-url "http://127.0.0.1:$P/v1" --custom-model-id mock-model --custom-api-key offline --custom-text-input \
            --gateway-bind loopback --gateway-auth token --skip-daemon --skip-channels --skip-skills --skip-search \
            --skip-ui --skip-health --skip-hooks > "$SCRATCH/onboard.log" 2>&1 || { tail -n 5 "$SCRATCH/onboard.log"; exit 1; }
        echo "--- openclaw agent --local -m \"What can you do?\""
        # --log-level error keeps OpenClaw's own progress lines out of the answer.
        openclaw --log-level error agent --local -m "What can you do?" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^\[[a-z/_-]+\] ' ;;
    *) echo "usage: offline.sh hermes|openclaw"; exit 2 ;;
esac
echo
echo "--- what the agent sent to the model (requests.log):"
python3 - << 'PY'
import json
reqs = [json.loads(l) for l in open("requests.log") if l.strip()]
chat = [r for r in reqs if r.get("messages")]
for n, r in enumerate(chat, 1):
    tools = [t.get("function", {}).get("name", "?") for t in (r.get("tools") or [])]
    chars = sum(len(json.dumps(m.get("content", ""))) for m in r["messages"])
    roles = ", ".join(m["role"] for m in r["messages"])
    print(f"request {n}: {len(r['messages'])} messages ({roles}), {chars} characters, {len(tools)} tools")
    if tools:
        print("  tools: " + ", ".join(tools[:30]) + (" ..." if len(tools) > 30 else ""))
big = max(chat, key=lambda r: len(json.dumps(r)), default=None)
if big:
    system = next((m.get("content") for m in big["messages"] if m["role"] == "system"), "")
    if isinstance(system, list):
        system = " ".join(p.get("text", "") for p in system if isinstance(p, dict))
    print("\nthe start of its system prompt:\n  " + str(system)[:600].replace("\n", "\n  "))
PY
OFFLINE_EOF
    gen_file "$DIR/skills/dev-bundle/SKILL.md" << 'SKILL_EOF'
---
name: dev-bundle
description: Answer questions about this Chromebook's dev-setup bundle - which stacks and demos are installed, and the helper commands it adds (lan, devdb, mssql, oracle, ldap, win31, wine-com, ollama-remote). Use when asked what is installed here, how to start a demo or a database, or how the laptops share services.
---

# The dev-setup bundle on this Chromebook

This Linux container was provisioned by a versioned bundle of four scripts (setup, init, test, demo).
Look before you change anything, and ask before you start, stop or install something.

## Where to look
- Installed demos: `~/dev-demo/README.md` lists every demo and its launcher (`~/dev-demo/<stack>/run-<name>.sh`).
- The newest test results: the most recent `dev-test-*.log` in the `assets/logs` folder next to the bundle scripts.
- The shell setup the bundle writes: the marked `# >>> dev-setup ... >>>` blocks in `~/.bashrc`.

## Helper commands (each explains itself with `help` or no arguments)
- `lan` - the laptop network: `lan status`, `lan scan`, `lan url NAME`, `lan share status`.
- `devdb`, `mssql`, `oracle` - the SQL Server and Oracle containers: `mssql up`, `mssql sql`, `mssql down`.
- `ldap` - the LDAP directories: `ldap status`.
- `win31` - Windows 3.1x in DOSBox-X: `win31 where`.
- `wine-com` - runs a program in the COM Wine prefix.
- `ollama` (this machine), `ollama-remote` (the machine in OLLAMA_REMOTE).

## Never
- Never print, copy, summarise or send the contents of `~/.config/dev-init/secrets.env` or any `.env` file: they hold API keys.
- Never open a port to the network or change `LAN_SHARE` without being asked.
SKILL_EOF
    write_run << 'EOF'
demo_need openclaw install-openclaw
chmod +x offline.sh 2> /dev/null
onboarded() { [ -n "$(jq -r '.wizard.lastRunAt // empty' ~/.openclaw/openclaw.json 2> /dev/null)" ]; }
while demo_menu "OpenClaw" \
        "chat: OpenClaw's terminal UI with the model dev-init gave it (Ctrl-C leaves)" \
        "dashboard: run the gateway on loopback and open its Control UI in the browser (Enter stops it)" \
        "offline: one turn against a stand-in model on this machine, and what OpenClaw sent it (no key needed)" \
        "skill: add dev-bundle, a skill written here, to ~/.openclaw/skills, then list it" \
        "audit: openclaw security audit (what is exposed, what to tighten)"; do
    case "$DEMO_CHOICE" in
        chat*)      if onboarded; then openclaw chat
                    else demo_note "OpenClaw is not set up yet: put a key (AGENT_ANTHROPIC_API_KEY, OPENROUTER_API_KEY) or OLLAMA_REMOTE + AGENT_MODEL in ~/.config/dev-init/secrets.env and rerun dev-init with install-openclaw. The offline item works without one."; fi ;;
        dashboard*) if ! onboarded; then
                        demo_note "Set OpenClaw up first (see the chat item)."
                    else
                        PORT=$(jq -r '.gateway.port // 18789' ~/.openclaw/openclaw.json)
                        UP=1; GWPID=""
                        if ss -ltnH "sport = :$PORT" | grep -q .; then
                            demo_note "A gateway already listens on $PORT (your service?); opening its Control UI."
                        else
                            setsid openclaw gateway run > "$DEMO_LOGS/openclaw-gateway.log" 2>&1 < /dev/null & GWPID=$!; DEMO_PIDS+=("$GWPID")
                            demo_wait_port "$PORT" 90 || { UP=0; tail -n 5 "$DEMO_LOGS/openclaw-gateway.log"; }
                        fi
                        if [ "$UP" = 1 ]; then
                            # browserUrl carries a one-time pairing code; url carries the token itself.
                            URL=$(openclaw dashboard --no-open --json 2> /dev/null | jq -r '.browserUrl // .url // empty' 2> /dev/null)
                            demo_note "The link lets a browser into your agent: do not share it. The gateway listens on 127.0.0.1 only."
                            if [ -n "$URL" ]; then demo_open "$URL"; else openclaw dashboard --no-open; fi
                            demo_hold "Press Enter to stop the gateway"
                        fi
                        if [ -n "$GWPID" ]; then
                            kill -TERM -- "-$GWPID" 2> /dev/null
                            for _ in $(seq 1 20); do ss -ltnH "sport = :$PORT" | grep -q . || break; sleep 0.5; done
                            echo "gateway stopped"
                        fi
                    fi ;;
        offline*)   ./offline.sh openclaw
                    demo_note "Every turn sends the whole system prompt and the tool list, which is why agents need a big context window and why a cloud model bills more per message than a chat does." ;;
        skill*)     mkdir -p ~/.openclaw/skills/dev-bundle && cp skills/dev-bundle/SKILL.md ~/.openclaw/skills/dev-bundle/SKILL.md
                    openclaw skills list 2> /dev/null | grep -E "dev-bundle"
                    demo_note "A skill is a SKILL.md: a name, a description saying when to use it, and instructions. This one is local and yours; ClawHub's are other people's code and prompts, so read one before 'openclaw skills install'. Remove it: rm -r ~/.openclaw/skills/dev-bundle" ;;
        audit*)     openclaw security audit ;;
    esac
    [ -n "${1:-}" ] && break
done
demo_note "Channels (Telegram, WhatsApp, Slack...): 'openclaw channels add', with an account made for it. The always-on gateway: 'openclaw gateway install'; the container sleeps with the Chromebook."
EOF
    done_demo
}

# =================================================================
# DEMO: Laravel (v87)
# =================================================================

demo_laravel() {
    # The app itself arrives on the launcher's first run (Composer, ~110 packages); dev-demo writes only
    # the files that turn the skeleton into the demo, under overlay/.
    begin laravel links "Laravel 13: a small links app (SQLite, Eloquent, validation, Blade, Vite, tests), then the same app in DDEV" \
        "generated here on the laravel/laravel skeleton: https://github.com/laravel/laravel" || return 0
    need composer install-laravel || return 0
    need php install-laravel || return 0
    present || FRESH=1
    gen_file "$DIR/overlay/app/Models/Link.php" << 'LV_EOF_0'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;

// A saved link: a title, its URL and the stack it belongs to (laravel, drupal, ddev...).
// #[Fillable] is Laravel 13's attribute form of the $fillable property.
#[Fillable(['title', 'url', 'stack'])]
class Link extends Model
{
}
LV_EOF_0
    gen_file "$DIR/overlay/database/migrations/2026_09_30_000000_create_links_table.php" << 'LV_EOF_1'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('links', function (Blueprint $table) {
            $table->id();
            $table->string('title');
            $table->string('url')->unique();
            $table->string('stack')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('links');
    }
};
LV_EOF_1
    gen_file "$DIR/overlay/database/seeders/LinkSeeder.php" << 'LV_EOF_2'
<?php

namespace Database\Seeders;

use App\Models\Link;
use Illuminate\Database\Seeder;

// php artisan db:seed --class=LinkSeeder  (safe to run again: firstOrCreate keys on the URL)
class LinkSeeder extends Seeder
{
    public function run(): void
    {
        $links = [
            ['Laravel documentation', 'https://laravel.com/docs', 'laravel'],
            ['Laravel Bootcamp', 'https://bootcamp.laravel.com', 'laravel'],
            ['Laracasts', 'https://laracasts.com', 'laravel'],
            ['DDEV documentation', 'https://docs.ddev.com', 'ddev'],
            ['Drupal', 'https://www.drupal.org', 'drupal'],
        ];

        foreach ($links as [$title, $url, $stack]) {
            Link::firstOrCreate(['url' => $url], ['title' => $title, 'stack' => $stack]);
        }
    }
}
LV_EOF_2
    gen_file "$DIR/overlay/resources/views/links.blade.php" << 'LV_EOF_3'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Links - {{ config('app.name') }}</title>
    @if (file_exists(public_path('build/manifest.json')) || file_exists(public_path('hot')))
        @vite(['resources/css/app.css'])
    @endif
</head>
<body class="bg-gray-50 text-gray-900 antialiased">
<main class="mx-auto max-w-2xl p-6">
    <h1 class="text-2xl font-semibold">Links</h1>
    <p class="text-sm text-gray-600">A Laravel {{ app()->version() }} demo on PHP {{ PHP_VERSION }}: SQLite, Eloquent, validation, Blade and Vite. As JSON: <a class="underline" href="{{ route('links.json') }}">/links.json</a></p>

    @if (session('status'))
        <p class="mt-4 rounded bg-green-100 p-2 text-green-900">{{ session('status') }}</p>
    @endif

    <form method="POST" action="{{ route('links.store') }}" class="mt-6 grid gap-2">
        @csrf
        <input name="title" value="{{ old('title') }}" placeholder="Title" class="rounded border p-2" required>
        <input name="url" value="{{ old('url') }}" placeholder="https://..." class="rounded border p-2" required>
        <input name="stack" value="{{ old('stack') }}" placeholder="Stack (optional)" class="rounded border p-2">
        @if ($errors->any())
            <ul class="text-sm text-red-700">
                @foreach ($errors->all() as $error)
                    <li>{{ $error }}</li>
                @endforeach
            </ul>
        @endif
        <button class="rounded bg-gray-900 p-2 text-white">Add link</button>
    </form>

    <ul class="mt-6 divide-y rounded border bg-white">
        @forelse ($links as $link)
            <li class="flex justify-between p-3">
                <a class="underline" href="{{ $link->url }}">{{ $link->title }}</a>
                <span class="text-sm text-gray-500">{{ $link->stack }}</span>
            </li>
        @empty
            <li class="p-3 text-gray-500">No links yet.</li>
        @endforelse
    </ul>
</main>
</body>
</html>
LV_EOF_3
    gen_file "$DIR/overlay/routes/web.php" << 'LV_EOF_4'
<?php

use App\Models\Link;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

// The list, with a form to add a link.
Route::get('/', function () {
    return view('links', [
        'links' => Link::orderBy('stack')->orderBy('title')->get(),
    ]);
})->name('links.index');

// Add a link: validated, then back to the list with a flash message.
Route::post('/links', function (Request $request) {
    $data = $request->validate([
        'title' => ['required', 'string', 'max:120'],
        'url' => ['required', 'url:http,https', 'max:500', 'unique:links,url'],
        'stack' => ['nullable', 'string', 'max:40'],
    ]);

    Link::create($data);

    return redirect()->route('links.index')->with('status', 'Link added.');
})->name('links.store');

// The same data as JSON (Eloquent collections serialize themselves).
Route::get('/links.json', function () {
    return Link::orderBy('title')->get(['title', 'url', 'stack']);
})->name('links.json');
LV_EOF_4
    gen_file "$DIR/overlay/tests/Feature/LinksTest.php" << 'LV_EOF_5'
<?php

namespace Tests\Feature;

use App\Models\Link;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

// Runs against an in-memory SQLite database (phpunit.xml), migrated fresh for each test.
class LinksTest extends TestCase
{
    use RefreshDatabase;

    public function test_the_list_shows_saved_links(): void
    {
        Link::create(['title' => 'Laravel documentation', 'url' => 'https://laravel.com/docs', 'stack' => 'laravel']);

        $this->get('/')->assertOk()->assertSee('Laravel documentation');
    }

    public function test_a_link_can_be_added(): void
    {
        $this->post('/links', ['title' => 'DDEV', 'url' => 'https://ddev.com', 'stack' => 'ddev'])
            ->assertRedirect('/');

        $this->assertDatabaseHas('links', ['url' => 'https://ddev.com']);
    }

    public function test_a_bad_url_is_refused(): void
    {
        $this->post('/links', ['title' => 'Not a link', 'url' => 'not a url'])
            ->assertSessionHasErrors('url');

        $this->assertDatabaseCount('links', 0);
    }

    public function test_the_json_endpoint_lists_links(): void
    {
        Link::create(['title' => 'Laracasts', 'url' => 'https://laracasts.com', 'stack' => 'laravel']);

        $this->getJson('/links.json')->assertOk()->assertJsonFragment(['title' => 'Laracasts']);
    }
}
LV_EOF_5
    write_run << 'EOF'
demo_need php install-laravel
demo_need composer install-laravel
demo_need npm install-node
if [ "${1:-}" = down ]; then ( cd app 2> /dev/null && ddev stop ); exit; fi
if [ ! -f app/artisan ]; then
    demo_step "First run: creating the app (Composer downloads about 110 packages; a minute or two)"
    if command -v laravel > /dev/null 2>&1; then
        laravel new app --no-interaction --database=sqlite --phpunit --no-boost --no-node || exit 1
    else
        composer create-project laravel/laravel app --prefer-dist --no-interaction || exit 1
    fi
    # The demo's files on top of the skeleton. The skeleton's own feature test expects the stock
    # welcome page at /, which the links list replaces, so LinksTest takes its place.
    cp -r overlay/. app/ && rm -f app/tests/Feature/ExampleTest.php
fi
cd app || exit 1
# Each step below is safe to repeat, so a first run cut short (a network hiccup) finishes on the next.
if [ ! -f .devdemo-seeded ]; then
    php artisan migrate --force --no-interaction && php artisan db:seed --class=LinkSeeder --force --no-interaction \
        && touch .devdemo-seeded || exit 1
fi
if [ ! -f public/build/manifest.json ]; then
    demo_step "Building the front end (npm install + Vite)"
    { npm install --no-audit --no-fund && npm run build; } \
        || demo_note "The front-end build failed (it also fetches the Instrument Sans font from fonts.bunny.net). The pages work without the styles; the next launch tries again."
fi
open_later() { ( sleep "${2:-6}"; demo_open "$1" ) & }
while demo_menu "Laravel links (the app is in $DEMO_DIR/app)" \
        "dev: composer run dev (server, queue, logs and Vite together) on http://127.0.0.1:8000; Ctrl-C stops" \
        "serve: only php artisan serve, with the built assets; Ctrl-C stops" \
        "test: php artisan test (LinksTest: list, add, validation, JSON)" \
        "tour: php artisan about, route:list, model:show Link, migrate:status" \
        "ddev: the same app and SQLite file in DDEV (nginx + php-fpm, https); '$0 down' stops it" \
        "boost: add Laravel Boost, which gives Claude Code this app's docs and tools (interactive)" \
        "starter: laravel new with a starter kit: React, Vue, Svelte or Livewire (interactive)"; do
    case "$DEMO_CHOICE" in
        dev*)     open_later http://127.0.0.1:8000 8; composer run dev ;;
        serve*)   open_later http://127.0.0.1:8000 3; php artisan serve ;;
        test*)    php artisan test ;;
        tour*)    php artisan about; php artisan route:list; php artisan model:show 'App\Models\Link'; php artisan migrate:status ;;
        ddev*)    docker_ok
                  # DDEV normally rewrites .env for its MariaDB; settings management off keeps this app on its
                  # SQLite file, so the host items above keep working and both see the same links.
                  # The PHP version matches this machine's, which Composer resolved vendor/ against.
                  if [ -d .ddev ] || ddev config --project-type=laravel --docroot=public --project-name=devdemo-laravel \
                      --php-version="$(php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;')" \
                      --disable-settings-management > /dev/null; then
                      ddev start && ddev launch
                      demo_note "Served by DDEV at https://devdemo-laravel.ddev.site from the same files. Stop it: $0 down"
                  fi ;;
        boost*)   composer require laravel/boost --dev -W && php artisan boost:install
                  demo_note "Boost added its MCP server and guidelines (CLAUDE.md / AGENTS.md) to this app; start 'claude' here to use them." ;;
        starter*) if command -v laravel > /dev/null 2>&1; then
                      ( cd "$DEMO_DIR" && laravel new starter )
                      demo_note "Then: cd $DEMO_DIR/starter && composer run dev"
                  else
                      demo_note "The laravel command is missing: rerun dev-setup with install-laravel, then open a new terminal."
                  fi ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# =================================================================
# DEMO: Symfony (v88)
# =================================================================

demo_symfony() {
    # The app arrives on the launcher's first run ('symfony new --webapp': Composer, Flex recipes); dev-demo
    # writes only the files that turn the webapp skeleton into the demo, under overlay/.
    begin symfony links "Symfony 8: a small links app (Doctrine on SQLite, a validated form, Twig, a console command, tests), then DDEV" \
        "generated here on symfony new --webapp: https://symfony.com/doc/current/setup.html" || return 0
    need symfony install-symfony || return 0
    need composer install-symfony || return 0
    present || FRESH=1
    gen_file "$DIR/overlay/src/Command/SeedLinksCommand.php" << 'SF_EOF_0'
<?php

namespace App\Command;

use App\Entity\Link;
use App\Repository\LinkRepository;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Output\OutputInterface;

// php bin/console app:seed-links   (safe to run again: it skips URLs that are already saved)
#[AsCommand(name: 'app:seed-links', description: 'Add a few starter links')]
final class SeedLinksCommand
{
    public function __construct(
        private readonly LinkRepository $links,
        private readonly EntityManagerInterface $em,
    ) {
    }

    public function __invoke(OutputInterface $output): int
    {
        $added = 0;
        foreach ([
            ['Symfony documentation', 'https://symfony.com/doc/current/index.html', 'symfony'],
            ['SymfonyCasts', 'https://symfonycasts.com', 'symfony'],
            ['Doctrine ORM', 'https://www.doctrine-project.org/projects/orm.html', 'doctrine'],
            ['DDEV documentation', 'https://docs.ddev.com', 'ddev'],
            ['Drupal', 'https://www.drupal.org', 'drupal'],
        ] as [$title, $url, $stack]) {
            if (null === $this->links->findOneBy(['url' => $url])) {
                $this->em->persist((new Link())->setTitle($title)->setUrl($url)->setStack($stack));
                ++$added;
            }
        }
        $this->em->flush();
        $output->writeln(sprintf('Added %d link(s).', $added));

        return Command::SUCCESS;
    }
}
SF_EOF_0
    gen_file "$DIR/overlay/src/Controller/LinkController.php" << 'SF_EOF_1'
<?php

namespace App\Controller;

use App\Entity\Link;
use App\Form\LinkType;
use App\Repository\LinkRepository;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

final class LinkController extends AbstractController
{
    // The list and the form. An invalid submission re-renders with HTTP 422 (render() does that).
    #[Route('/', name: 'link_index', methods: ['GET', 'POST'])]
    public function index(Request $request, LinkRepository $links, EntityManagerInterface $em): Response
    {
        $link = new Link();
        $form = $this->createForm(LinkType::class, $link);
        $form->handleRequest($request);

        if ($form->isSubmitted() && $form->isValid()) {
            $em->persist($link);
            $em->flush();
            $this->addFlash('success', 'Link added.');

            return $this->redirectToRoute('link_index');
        }

        return $this->render('link/index.html.twig', [
            'links' => $links->findAllSorted(),
            'form' => $form,
        ]);
    }

    // The same data as JSON.
    #[Route('/links.json', name: 'link_json', methods: ['GET'])]
    public function asJson(LinkRepository $links): JsonResponse
    {
        return $this->json(array_map(
            fn (Link $l) => ['title' => $l->getTitle(), 'url' => $l->getUrl(), 'stack' => $l->getStack()],
            $links->findAllSorted(),
        ));
    }
}
SF_EOF_1
    gen_file "$DIR/overlay/src/Entity/Link.php" << 'SF_EOF_2'
<?php

namespace App\Entity;

use App\Repository\LinkRepository;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Bridge\Doctrine\Validator\Constraints\UniqueEntity;
use Symfony\Component\Validator\Constraints as Assert;

// A saved link. The Doctrine mapping and the validation rules both live on the class as attributes.
#[ORM\Entity(repositoryClass: LinkRepository::class)]
#[UniqueEntity('url', message: 'That link is already saved.')]
class Link
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\Column(length: 120)]
    #[Assert\NotBlank]
    #[Assert\Length(max: 120)]
    private ?string $title = null;

    #[ORM\Column(length: 500, unique: true)]
    #[Assert\NotBlank]
    #[Assert\Url(protocols: ['http', 'https'], requireTld: true)]
    private ?string $url = null;

    #[ORM\Column(length: 40, nullable: true)]
    #[Assert\Length(max: 40)]
    private ?string $stack = null;

    public function getId(): ?int
    {
        return $this->id;
    }

    public function getTitle(): ?string
    {
        return $this->title;
    }

    public function setTitle(?string $title): static
    {
        $this->title = $title;

        return $this;
    }

    public function getUrl(): ?string
    {
        return $this->url;
    }

    public function setUrl(?string $url): static
    {
        $this->url = $url;

        return $this;
    }

    public function getStack(): ?string
    {
        return $this->stack;
    }

    public function setStack(?string $stack): static
    {
        $this->stack = $stack;

        return $this;
    }
}
SF_EOF_2
    gen_file "$DIR/overlay/src/Form/LinkType.php" << 'SF_EOF_3'
<?php

namespace App\Form;

use App\Entity\Link;
use Symfony\Component\Form\AbstractType;
use Symfony\Component\Form\Extension\Core\Type\SubmitType;
use Symfony\Component\Form\Extension\Core\Type\TextType;
use Symfony\Component\Form\Extension\Core\Type\UrlType;
use Symfony\Component\Form\FormBuilderInterface;
use Symfony\Component\OptionsResolver\OptionsResolver;

// The add-a-link form. Validation comes from the entity's constraints; CSRF protection is on by default.
class LinkType extends AbstractType
{
    public function buildForm(FormBuilderInterface $builder, array $options): void
    {
        $builder
            ->add('title', TextType::class)
            ->add('url', UrlType::class, ['default_protocol' => 'https'])
            ->add('stack', TextType::class, ['required' => false])
            ->add('save', SubmitType::class, ['label' => 'Add link']);
    }

    public function configureOptions(OptionsResolver $resolver): void
    {
        $resolver->setDefaults(['data_class' => Link::class]);
    }
}
SF_EOF_3
    gen_file "$DIR/overlay/src/Repository/LinkRepository.php" << 'SF_EOF_4'
<?php

namespace App\Repository;

use App\Entity\Link;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<Link>
 */
class LinkRepository extends ServiceEntityRepository
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, Link::class);
    }

    /**
     * @return Link[] sorted by stack, then title
     */
    public function findAllSorted(): array
    {
        return $this->createQueryBuilder('l')
            ->orderBy('l.stack', 'ASC')
            ->addOrderBy('l.title', 'ASC')
            ->getQuery()
            ->getResult();
    }
}
SF_EOF_4
    gen_file "$DIR/overlay/templates/link/index.html.twig" << 'SF_EOF_5'
{% extends 'base.html.twig' %}

{% block title %}Links{% endblock %}

{% block body %}
<main style="max-width: 42rem; margin: 2rem auto; font-family: system-ui, sans-serif;">
    <h1>Links</h1>
    <p>A Symfony {{ constant('Symfony\\Component\\HttpKernel\\Kernel::VERSION') }} demo on PHP {{ constant('PHP_VERSION') }}:
        Doctrine on SQLite, a form with validation, Twig. As JSON: <a href="{{ path('link_json') }}">/links.json</a></p>

    {% for message in app.flashes('success') %}
        <p role="status" style="background: #e6f4ea; padding: .5rem;">{{ message }}</p>
    {% endfor %}

    {{ form(form) }}

    <ul>
        {% for link in links %}
            <li><a href="{{ link.url }}">{{ link.title }}</a> <small>{{ link.stack }}</small></li>
        {% else %}
            <li>No links yet.</li>
        {% endfor %}
    </ul>
</main>
{% endblock %}
SF_EOF_5
    gen_file "$DIR/overlay/tests/Controller/LinkControllerTest.php" << 'SF_EOF_6'
<?php

namespace App\Tests\Controller;

use App\Entity\Link;
use Doctrine\ORM\EntityManagerInterface;
use Doctrine\ORM\Tools\SchemaTool;
use Symfony\Bundle\FrameworkBundle\KernelBrowser;
use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;

// The test environment uses its own SQLite file (.env.test.local); each test starts from an empty schema.
final class LinkControllerTest extends WebTestCase
{
    private KernelBrowser $client;
    private EntityManagerInterface $em;

    protected function setUp(): void
    {
        $this->client = static::createClient();
        $this->em = static::getContainer()->get(EntityManagerInterface::class);
        $tool = new SchemaTool($this->em);
        $metadata = $this->em->getMetadataFactory()->getAllMetadata();
        $tool->dropSchema($metadata);
        $tool->createSchema($metadata);
    }

    public function testTheListShowsSavedLinks(): void
    {
        $this->em->persist((new Link())->setTitle('Symfony documentation')->setUrl('https://symfony.com/doc')->setStack('symfony'));
        $this->em->flush();

        $this->client->request('GET', '/');

        self::assertResponseIsSuccessful();
        self::assertSelectorTextContains('ul', 'Symfony documentation');
    }

    public function testALinkCanBeAdded(): void
    {
        $this->client->request('GET', '/');
        $this->client->submitForm('Add link', [
            'link[title]' => 'DDEV',
            'link[url]' => 'https://ddev.com',
            'link[stack]' => 'ddev',
        ]);

        self::assertResponseRedirects('/');
        $this->client->followRedirect();
        self::assertSelectorTextContains('[role=status]', 'Link added.');
        self::assertSame(1, $this->em->getRepository(Link::class)->count(['url' => 'https://ddev.com']));
    }

    public function testABadUrlIsRefused(): void
    {
        $this->client->request('GET', '/');
        $this->client->submitForm('Add link', ['link[title]' => 'Not a link', 'link[url]' => 'not a url']);

        self::assertResponseStatusCodeSame(422);
        self::assertSame(0, $this->em->getRepository(Link::class)->count([]));
    }

    public function testTheJsonEndpointListsLinks(): void
    {
        $this->em->persist((new Link())->setTitle('Doctrine ORM')->setUrl('https://www.doctrine-project.org')->setStack('doctrine'));
        $this->em->flush();

        $this->client->request('GET', '/links.json');

        self::assertResponseIsSuccessful();
        self::assertStringContainsString('Doctrine ORM', (string) $this->client->getResponse()->getContent());
    }
}
SF_EOF_6
    write_run << 'EOF'
demo_need php install-symfony
demo_need symfony install-symfony
demo_need composer install-symfony
if [ "${1:-}" = down ]; then ( cd app 2> /dev/null && ddev stop ); exit; fi
SQLITE_URL='DATABASE_URL="sqlite:///%kernel.project_dir%/var/data_%kernel.environment%.db"'
if [ ! -f app/bin/console ]; then
    demo_step "First run: creating the app with symfony new --webapp (Composer and Flex recipes; a minute or two)"
    symfony new app --webapp --no-git || exit 1
    cp -r overlay/. app/
    # SQLite instead of the webapp's default PostgreSQL. .env.local is for dev; the test environment
    # skips it and reads .env.test.local instead.
    echo "$SQLITE_URL" > app/.env.local
    echo "$SQLITE_URL" > app/.env.test.local
fi
cd app || exit 1
# Safe to repeat, so a first run cut short finishes on the next launch.
if [ ! -f .devdemo-seeded ]; then
    ls migrations/*.php > /dev/null 2>&1 || php bin/console make:migration --no-interaction || exit 1
    php bin/console doctrine:migrations:migrate --no-interaction && php bin/console app:seed-links && touch .devdemo-seeded || exit 1
fi
open_later() { ( sleep "${2:-4}"; demo_open "$1" ) & }
while demo_menu "Symfony links (the app is in $DEMO_DIR/app)" \
        "serve: symfony serve (the CLI's web server) on http://127.0.0.1:8000; Ctrl-C stops" \
        "test: php bin/phpunit (LinkControllerTest: list, add through the form, validation, JSON)" \
        "tour: bin/console about, debug:router, doctrine:mapping:info, debug:container LinkRepository" \
        "ddev: the same app and SQLite file in DDEV (nginx + php-fpm, https); '$0 down' stops it" \
        "security: symfony check:security (this app's packages against the advisory database)" \
        "tls: symfony server:ca:install, so symfony serve can use https (changes your trust stores; asks for sudo)"; do
    case "$DEMO_CHOICE" in
        serve*)    open_later http://127.0.0.1:8000; symfony serve --no-tls ;;
        test*)     php bin/phpunit ;;
        tour*)     php bin/console about; php bin/console debug:router; php bin/console doctrine:mapping:info
                   php bin/console debug:container 'App\Repository\LinkRepository' ;;
        ddev*)     docker_ok
                   # Settings management off, and DATABASE_URL set for the web container, keep DDEV on this app's
                   # SQLite file instead of its MariaDB, so the host items keep working on the same links.
                   # The PHP version matches this machine's: Symfony 8 needs 8.4, newer than some DDEV defaults.
                   if [ -d .ddev ] || ddev config --project-type=symfony --docroot=public --project-name=devdemo-symfony \
                       --php-version="$(php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;')" \
                       --disable-settings-management \
                       --web-environment-add='DATABASE_URL=sqlite:///%kernel.project_dir%/var/data_dev.db' > /dev/null; then
                       ddev start && ddev launch
                       demo_note "Served by DDEV at https://devdemo-symfony.ddev.site from the same files. Stop it: $0 down"
                   fi ;;
        security*) symfony check:security ;;
        tls*)      demo_note "This installs the Symfony CLI's own certificate authority into the system and browser trust stores."
                   symfony server:ca:install && demo_note "From now on 'symfony serve' (without --no-tls) serves https://127.0.0.1:8000" ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# =================================================================
# DEMOS: the shared services (v89: install-cache, install-search, install-mongodb), FastMCP
# (install-agentic) and Cloudflare (install-cloudflare)
# =================================================================

# get_films DIR: Apache Solr's example films (films.json, about 1,100 films from Freebase, CC BY 2.5, each
# with a 10-dimension vector) into DIR. From the Solr image when this machine has it (no download), else
# from Solr's GitHub repository. 1 = could not get them.
FILMS_URL=https://raw.githubusercontent.com/apache/solr/branch_9x/solr/example/films
films_ok() { python3 -c 'import json, sys; sys.exit(0 if len(json.load(open(sys.argv[1]))) > 1000 else 1)' "$1" 2> /dev/null; }
get_films() {
    local d=$1 img
    [ -s "$d/films.json" ] && [ "$REFRESH" != 1 ] && return 0
    mkdir -p "$d"
    img=$(docker inspect -f '{{.Config.Image}}' devsvc-solr 2> /dev/null || true)
    if [ -n "$img" ] && docker run --rm --pull=never --entrypoint cat "$img" /opt/solr/example/films/films.json > "$d/films.json.part" 2> /dev/null \
        && films_ok "$d/films.json.part"; then
        docker run --rm --pull=never --entrypoint cat "$img" /opt/solr/example/films/films-LICENSE.txt > "$d/films-LICENSE.txt" 2> /dev/null || true
        echo "  films.json from the $img image"
    elif curl -fsSL --retry 3 -o "$d/films.json.part" "$FILMS_URL/films.json" && films_ok "$d/films.json.part"; then
        curl -fsSL --retry 3 -o "$d/films-LICENSE.txt" "$FILMS_URL/films-LICENSE.txt" 2> /dev/null || true
        echo "  films.json from Solr's GitHub repository"
    else
        rm -f "$d/films.json.part"
        return 1
    fi
    mv "$d/films.json.part" "$d/films.json"
    [ -s "$d/films-LICENSE.txt" ] || printf '%s\n' "The films data (films.json) comes from Apache Solr's example/films and is licensed under the" \
        "Creative Commons Attribution 2.5 Generic License: http://creativecommons.org/licenses/by/2.5/" > "$d/films-LICENSE.txt"
}

demo_services() {
    # --- services/search-bakeoff: any search engine
    if { has install-solr || has install-opensearch || has install-elasticsearch || has install-meilisearch || has install-typesense; } \
        && begin services search-bakeoff "Search bake-off: 1,100 films in Solr, OpenSearch, Meilisearch, Typesense (and Elasticsearch); the same four questions side by side" \
            "Apache Solr's example films (CC BY 2.5): https://github.com/apache/solr/tree/branch_9x/solr/example/films"; then
        if need devsvc install-search && need python3 "the base install"; then
            if get_films "$DIR"; then
                gen_file "$DIR/bakeoff.py" << 'EOF_BAKEOFF'
#!/usr/bin/env python3
"""Search bake-off: the same films and the same four questions, on every search engine installed here.

  bakeoff.py load ENGINE    index films.json into ENGINE (an earlier bake-off index is replaced)
  bakeoff.py ask ENGINE     ask the four questions; prints the answers and saves results/ENGINE.json
  bakeoff.py report         the answers of every engine side by side, from results/*.json
  bakeoff.py drop ENGINE    remove the bake-off index from ENGINE

ENGINE is one of: solr opensearch elasticsearch meilisearch typesense. The engines are the shared
services of dev-setup's devsvc, on 127.0.0.1. Their logins come from the environment (SOLR_PASSWORD,
OPENSEARCH_ADMIN_PASSWORD, ELASTIC_PASSWORD, MEILI_MASTER_KEY, TYPESENSE_API_KEY), which the launcher
reads with 'devsvc password'. Standard library only.

The data is Apache Solr's example films (about 1,100 films from Freebase, CC BY 2.5): name, directors,
genres, release date and a 10-dimension 'film_vector' that Solr's authors made for their vector
tutorial. Because the vectors come with the data, the vector question needs no embedding model.
"""
import base64
import html
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
FILMS = HERE / "films.json"
RESULTS = HERE / "results"
INDEX = "bakeoff_films"
ENGINES = ["solr", "opensearch", "elasticsearch", "meilisearch", "typesense"]
PORTS = {"solr": 8983, "opensearch": 9200, "elasticsearch": 9201, "meilisearch": 7700, "typesense": 8108}
TITLES = {"solr": "Solr", "opensearch": "OpenSearch", "elasticsearch": "Elasticsearch",
          "meilisearch": "Meilisearch", "typesense": "Typesense"}

# The four questions.
FULLTEXT = "harry potter"      # every word must match
TYPO = "godzila"               # one letter short of Godzilla
VECTOR_OF = "Batman Begins"    # the films whose vectors lie closest to this one's
QUESTIONS = [
    ("fulltext", f"Full text: films named '{FULLTEXT}' (all words)"),
    ("facets", "Facets: the five biggest genres"),
    ("typo", f"Typo: '{TYPO}' (should find the Godzilla films)"),
    ("vector", f"Vectors: the three films nearest to '{VECTOR_OF}'"),
]


class EngineError(Exception):
    pass


def auth_headers(engine):
    env = os.environ.get
    if engine == "solr":
        return basic("solr", env("SOLR_PASSWORD", ""))
    if engine == "opensearch":
        return basic("admin", env("OPENSEARCH_ADMIN_PASSWORD", ""))
    if engine == "elasticsearch":
        return basic("elastic", env("ELASTIC_PASSWORD", ""))
    if engine == "meilisearch":
        return {"Authorization": "Bearer " + env("MEILI_MASTER_KEY", "")}
    return {"X-TYPESENSE-API-KEY": env("TYPESENSE_API_KEY", "")}


def basic(user, password):
    return {"Authorization": "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()}


def call(engine, method, path, body=None, raw=None, ctype="application/json", ok404=False, timeout=300):
    """One request to ENGINE on 127.0.0.1; returns the decoded JSON answer (None for 404 when ok404)."""
    url = f"http://127.0.0.1:{PORTS[engine]}{path}"
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    headers = dict(auth_headers(engine))
    if data is not None:
        headers["Content-Type"] = ctype
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            text = r.read().decode()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:400]
        if e.code == 404 and ok404:
            return None
        if e.code in (401, 403):
            raise EngineError(f"{TITLES[engine]} refused the login (HTTP {e.code}): is its password in the "
                              f"environment? ('devsvc password {engine}')") from None
        raise EngineError(f"{method} {path}: HTTP {e.code}: {detail}") from None
    except urllib.error.URLError as e:
        raise EngineError(f"{TITLES[engine]} does not answer on 127.0.0.1:{PORTS[engine]} ({e.reason}): "
                          f"'devsvc up {engine}' first") from None
    if not text.strip():
        return {}
    try:
        return json.loads(text)
    except ValueError:
        return [json.loads(line) for line in text.splitlines() if line.strip()]  # Typesense's import answer


def films():
    """The films, cleaned up: names unescaped, a short string key, dates where there are any."""
    if not FILMS.exists():
        sys.exit(f"No {FILMS}: rerun dev-demo with the search flags (it downloads the films).")
    out = []
    for i, f in enumerate(json.loads(FILMS.read_text())):
        out.append({
            "key": f"f{i}",
            "n": i,
            "name": html.unescape(f["name"]),
            "directed_by": [html.unescape(d) for d in f.get("directed_by", [])],
            "genre": [html.unescape(g) for g in f.get("genre", [])],
            "date": f.get("initial_release_date"),
            "vec": f["film_vector"],
        })
    return out


def vector_of(name):
    for f in films():
        if f["name"] == name:
            return f["vec"]
    sys.exit(f"'{name}' is not in films.json")


def timed(fn):
    t0 = time.perf_counter()
    res = fn()
    return res, round((time.perf_counter() - t0) * 1000)


# ---------------------------------------------------------------- Solr (SolrCloud, basic auth)
def solr_version():
    return call("solr", "GET", "/solr/admin/info/system?wt=json")["lucene"]["solr-spec-version"]


def solr_drop():
    if solr_has():
        call("solr", "GET", f"/solr/admin/collections?action=DELETE&name={INDEX}&wt=json")
    # The collection got its own copy of _default (no configName given), which outlives it: remove it too.
    try:
        call("solr", "GET", f"/solr/admin/configs?action=DELETE&name={INDEX}.AUTOCREATED&wt=json", ok404=True)
    except EngineError:
        pass


def solr_has():
    names = call("solr", "GET", "/solr/admin/collections?action=LIST&wt=json").get("collections", [])
    return INDEX in names


def solr_load(data):
    solr_drop()
    # No collection.configName: Solr copies _default into a configset of this collection's own
    # (bakeoff_films.AUTOCREATED), so the schema changes below never touch the shared _default.
    call("solr", "GET", f"/solr/admin/collections?action=CREATE&name={INDEX}&numShards=1&replicationFactor=1&wt=json")
    call("solr", "POST", f"/solr/{INDEX}/schema", {
        "add-field-type": {"name": "knn_vector_10", "class": "solr.DenseVectorField",
                           "vectorDimension": 10, "similarityFunction": "cosine"},
        "add-field": [
            {"name": "name", "type": "text_general", "stored": True, "multiValued": False},
            {"name": "directed_by", "type": "string", "multiValued": True},
            {"name": "genre", "type": "string", "multiValued": True},
            {"name": "initial_release_date", "type": "pdate"},
            {"name": "film_vector", "type": "knn_vector_10", "indexed": True, "stored": True},
        ],
    })
    docs = []
    for f in data:
        d = {"id": f["key"], "name": f["name"], "directed_by": f["directed_by"], "genre": f["genre"],
             "film_vector": f["vec"]}
        if f["date"]:
            d["initial_release_date"] = f["date"] + "T00:00:00Z"
        docs.append(d)
    call("solr", "POST", f"/solr/{INDEX}/update?commit=true&wt=json", docs)
    return call("solr", "GET", f"/solr/{INDEX}/select?q=*:*&rows=0&wt=json")["response"]["numFound"]


def solr_select(params):
    q = urllib.parse.urlencode({**params, "wt": "json"})
    return call("solr", "GET", f"/solr/{INDEX}/select?{q}")


def solr_ask(vec):
    a = {}
    r, ms = timed(lambda: solr_select({"defType": "edismax", "qf": "name", "q": FULLTEXT, "q.op": "AND",
                                       "fl": "name", "rows": 5}))
    a["fulltext"] = {"hits": r["response"]["numFound"], "names": [d["name"] for d in r["response"]["docs"]],
                     "ms": ms, "how": "edismax on name, q.op=AND"}
    r, ms = timed(lambda: solr_select({"q": "*:*", "rows": 0, "facet": "true", "facet.field": "genre",
                                       "facet.limit": 5, "facet.mincount": 1}))
    flat = r["facet_counts"]["facet_fields"]["genre"]
    a["facets"] = {"values": [[flat[i], flat[i + 1]] for i in range(0, len(flat), 2)], "ms": ms,
                   "how": "facet.field=genre"}
    r, ms = timed(lambda: solr_select({"q": f"name:{TYPO}~1", "fl": "name", "rows": 5}))
    a["typo"] = {"hits": r["response"]["numFound"], "names": [d["name"] for d in r["response"]["docs"]],
                 "ms": ms, "how": f"a fuzzy query you ask for: name:{TYPO}~1 (no typo tolerance by default)"}
    knn = "{!knn f=film_vector topK=4}[" + ",".join(str(x) for x in vec) + "]"
    r, ms = timed(lambda: solr_select({"q": knn, "fl": "name", "rows": 4}))
    a["vector"] = {"names": [d["name"] for d in r["response"]["docs"]], "ms": ms,
                   "how": "{!knn f=film_vector topK=4} on a DenseVectorField (cosine)"}
    return a


# ---------------------------------------------------------------- OpenSearch / Elasticsearch
def es_version(e):
    return call(e, "GET", "/")["version"]["number"]


def es_drop(e):
    call(e, "DELETE", f"/{INDEX}", ok404=True)


def es_load(e, data):
    es_drop(e)
    if e == "opensearch":
        settings = {"index": {"knn": True, "number_of_replicas": 0}}
        vec_field = {"type": "knn_vector", "dimension": 10,
                     "method": {"name": "hnsw", "engine": "lucene", "space_type": "cosinesimil"}}
    else:
        settings = {"index": {"number_of_replicas": 0}}
        vec_field = {"type": "dense_vector", "dims": 10, "index": True, "similarity": "cosine"}
    call(e, "PUT", f"/{INDEX}", {"settings": settings, "mappings": {"properties": {
        "name": {"type": "text"}, "directed_by": {"type": "keyword"}, "genre": {"type": "keyword"},
        "initial_release_date": {"type": "date"}, "film_vector": vec_field}}})
    lines = []
    for f in data:
        lines.append(json.dumps({"index": {"_index": INDEX, "_id": f["key"]}}))
        d = {"name": f["name"], "directed_by": f["directed_by"], "genre": f["genre"], "film_vector": f["vec"]}
        if f["date"]:
            d["initial_release_date"] = f["date"]
        lines.append(json.dumps(d))
    r = call(e, "POST", "/_bulk?refresh=true", raw=("\n".join(lines) + "\n").encode(), ctype="application/x-ndjson")
    if r.get("errors"):
        first = next((it["index"].get("error") for it in r.get("items", []) if it["index"].get("error")), None)
        raise EngineError(f"bulk indexing reported errors, e.g. {first}")
    return call(e, "GET", f"/{INDEX}/_count")["count"]


def es_search(e, body):
    return call(e, "POST", f"/{INDEX}/_search", body)


def es_ask(e, vec):
    a = {}
    total = lambda r: r["hits"]["total"]["value"] if isinstance(r["hits"]["total"], dict) else r["hits"]["total"]
    names = lambda r: [h["_source"]["name"] for h in r["hits"]["hits"]]
    r, ms = timed(lambda: es_search(e, {"size": 5, "_source": ["name"],
                                        "query": {"match": {"name": {"query": FULLTEXT, "operator": "and"}}}}))
    a["fulltext"] = {"hits": total(r), "names": names(r), "ms": ms, "how": "match on name, operator and"}
    r, ms = timed(lambda: es_search(e, {"size": 0, "aggs": {"g": {"terms": {"field": "genre", "size": 5}}}}))
    a["facets"] = {"values": [[b["key"], b["doc_count"]] for b in r["aggregations"]["g"]["buckets"]], "ms": ms,
                   "how": "terms aggregation on genre (keyword)"}
    r, ms = timed(lambda: es_search(e, {"size": 5, "_source": ["name"],
                                        "query": {"match": {"name": {"query": TYPO, "fuzziness": "AUTO"}}}}))
    a["typo"] = {"hits": total(r), "names": names(r), "ms": ms, "how": "match with fuzziness AUTO (asked for)"}
    if e == "opensearch":
        body = {"size": 4, "_source": ["name"], "query": {"knn": {"film_vector": {"vector": vec, "k": 4}}}}
        how = "knn query (k-NN plugin, Lucene HNSW, cosine)"
    else:
        body = {"size": 4, "_source": ["name"],
                "knn": {"field": "film_vector", "query_vector": vec, "k": 4, "num_candidates": 50}}
        how = "top-level knn on a dense_vector (cosine)"
    r, ms = timed(lambda: es_search(e, body))
    a["vector"] = {"names": names(r), "ms": ms, "how": how}
    return a


# ---------------------------------------------------------------- Meilisearch
def meili_version():
    return call("meilisearch", "GET", "/version")["pkgVersion"]


def meili_wait(task):
    uid = task["taskUid"]
    for _ in range(600):
        t = call("meilisearch", "GET", f"/tasks/{uid}")
        if t["status"] == "succeeded":
            return t
        if t["status"] in ("failed", "canceled"):
            raise EngineError(f"Meilisearch task {uid} {t['status']}: {t.get('error')}")
        time.sleep(0.5)
    raise EngineError(f"Meilisearch task {uid} did not finish in 5 minutes")


def meili_drop():
    t = call("meilisearch", "DELETE", f"/indexes/{INDEX}", ok404=True)
    if t:
        try:
            meili_wait(t)
        except EngineError:
            pass  # 'index not found' ends as a failed task; nothing to drop


def meili_load(data):
    meili_drop()
    meili_wait(call("meilisearch", "POST", "/indexes", {"uid": INDEX, "primaryKey": "id"}))
    meili_wait(call("meilisearch", "PATCH", f"/indexes/{INDEX}/settings", {
        "searchableAttributes": ["name"],
        "filterableAttributes": ["genre"],
        "faceting": {"maxValuesPerFacet": 1000, "sortFacetValuesBy": {"*": "count"}},
        "embedders": {"film": {"source": "userProvided", "dimensions": 10}},
    }))
    docs = [{"id": f["n"], "name": f["name"], "directed_by": f["directed_by"], "genre": f["genre"],
             "initial_release_date": f["date"], "_vectors": {"film": f["vec"]}} for f in data]
    meili_wait(call("meilisearch", "POST", f"/indexes/{INDEX}/documents", docs))
    return call("meilisearch", "GET", f"/indexes/{INDEX}/stats")["numberOfDocuments"]


def meili_search(body):
    return call("meilisearch", "POST", f"/indexes/{INDEX}/search", body)


def meili_ask(vec):
    a = {}
    names = lambda r: [h["name"] for h in r["hits"]]
    r, ms = timed(lambda: meili_search({"q": FULLTEXT, "limit": 5, "attributesToRetrieve": ["name"],
                                        "matchingStrategy": "all"}))
    a["fulltext"] = {"hits": r.get("estimatedTotalHits", len(r["hits"])), "names": names(r), "ms": ms,
                     "how": "search with matchingStrategy all"}
    r, ms = timed(lambda: meili_search({"q": "", "limit": 0, "facets": ["genre"]}))
    dist = r.get("facetDistribution", {}).get("genre", {})
    a["facets"] = {"values": sorted(([k, v] for k, v in dist.items()), key=lambda kv: -kv[1])[:5], "ms": ms,
                   "how": "facets on genre (filterable attribute)"}
    r, ms = timed(lambda: meili_search({"q": TYPO, "limit": 5, "attributesToRetrieve": ["name"]}))
    a["typo"] = {"hits": r.get("estimatedTotalHits", len(r["hits"])), "names": names(r), "ms": ms,
                 "how": "a plain search: typo tolerance is on by default"}
    r, ms = timed(lambda: meili_search({"vector": vec, "hybrid": {"embedder": "film", "semanticRatio": 1.0},
                                        "limit": 4, "attributesToRetrieve": ["name"]}))
    a["vector"] = {"names": names(r), "ms": ms, "how": "hybrid search, semanticRatio 1.0, a userProvided embedder"}
    return a


# ---------------------------------------------------------------- Typesense
def ts_version():
    return call("typesense", "GET", "/debug").get("version", "?")


def ts_drop():
    call("typesense", "DELETE", f"/collections/{INDEX}", ok404=True)


def ts_load(data):
    ts_drop()
    call("typesense", "POST", "/collections", {"name": INDEX, "fields": [
        {"name": "name", "type": "string"},
        {"name": "genre", "type": "string[]", "facet": True},
        {"name": "directed_by", "type": "string[]", "facet": True},
        {"name": "initial_release_date", "type": "string", "optional": True},
        {"name": "film_vector", "type": "float[]", "num_dim": 10},
    ]})
    lines = []
    for f in data:
        d = {"id": f["key"], "name": f["name"], "genre": f["genre"], "directed_by": f["directed_by"],
             "film_vector": f["vec"]}
        if f["date"]:
            d["initial_release_date"] = f["date"]
        lines.append(json.dumps(d))
    r = call("typesense", "POST", f"/collections/{INDEX}/documents/import?action=create",
             raw="\n".join(lines).encode(), ctype="text/plain")
    bad = [x for x in (r if isinstance(r, list) else [r]) if not x.get("success")]
    if bad:
        raise EngineError(f"{len(bad)} documents were refused, e.g. {bad[0]}")
    return call("typesense", "GET", f"/collections/{INDEX}")["num_documents"]


def ts_search(params):
    q = urllib.parse.urlencode({"query_by": "name", **params})
    return call("typesense", "GET", f"/collections/{INDEX}/documents/search?{q}")


def ts_ask(vec):
    a = {}
    names = lambda r: [h["document"]["name"] for h in r.get("hits", [])]
    r, ms = timed(lambda: ts_search({"q": FULLTEXT, "per_page": 5, "include_fields": "name",
                                     "drop_tokens_threshold": 0, "num_typos": 0}))
    a["fulltext"] = {"hits": r["found"], "names": names(r), "ms": ms, "how": "search on name, no dropped words, no typos"}
    r, ms = timed(lambda: ts_search({"q": "*", "facet_by": "genre", "max_facet_values": 5, "per_page": 0}))
    counts = r["facet_counts"][0]["counts"] if r.get("facet_counts") else []
    a["facets"] = {"values": [[c["value"], c["count"]] for c in counts], "ms": ms, "how": "facet_by genre"}
    r, ms = timed(lambda: ts_search({"q": TYPO, "per_page": 5, "include_fields": "name"}))
    a["typo"] = {"hits": r["found"], "names": names(r), "ms": ms, "how": "a plain search: typo tolerance is on by default"}
    vq = "film_vector:([" + ",".join(str(x) for x in vec) + "], k:4)"
    r, ms = timed(lambda: call("typesense", "POST", "/multi_search", {"searches": [
        {"collection": INDEX, "q": "*", "vector_query": vq, "per_page": 4, "include_fields": "name"}]}))
    res = r["results"][0]
    if "error" in res:
        raise EngineError(f"vector search: {res['error']}")
    a["vector"] = {"names": names(res), "ms": ms, "how": "vector_query on a float[] field (multi_search)"}
    return a


# ---------------------------------------------------------------- commands
def engine_arg():
    if len(sys.argv) < 3 or sys.argv[2] not in ENGINES:
        sys.exit(f"Name an engine: {' '.join(ENGINES)}")
    return sys.argv[2]


def version(e):
    return {"solr": solr_version, "meilisearch": meili_version, "typesense": ts_version}.get(e, lambda: es_version(e))()


def load(e):
    data = films()
    print(f"{TITLES[e]} {version(e)}: indexing {len(data)} films into '{INDEX}'...", flush=True)
    t0 = time.perf_counter()
    if e == "solr":
        n = solr_load(data)
    elif e in ("opensearch", "elasticsearch"):
        n = es_load(e, data)
    elif e == "meilisearch":
        n = meili_load(data)
    else:
        n = ts_load(data)
    secs = time.perf_counter() - t0
    print(f"  {n} documents in {secs:.1f} s")
    RESULTS.mkdir(exist_ok=True)
    (RESULTS / f"{e}.load.json").write_text(json.dumps({"docs": n, "seconds": round(secs, 1)}))


def ask(e):
    vec = vector_of(VECTOR_OF)
    fn = {"solr": solr_ask, "meilisearch": meili_ask, "typesense": ts_ask}.get(e, lambda v: es_ask(e, v))
    answers = fn(vec)
    # The film itself is its own nearest neighbour: drop it, keep three.
    answers["vector"]["names"] = [n for n in answers["vector"]["names"] if n != VECTOR_OF][:3]
    loadf = RESULTS / f"{e}.load.json"
    res = {"engine": e, "version": version(e), "asked": time.strftime("%Y-%m-%d %H:%M"),
           "load": json.loads(loadf.read_text()) if loadf.exists() else None, "answers": answers}
    RESULTS.mkdir(exist_ok=True)
    (RESULTS / f"{e}.json").write_text(json.dumps(res, indent=1))
    print_engine(res)


def short(names, n=3):
    s = ", ".join(names[:n])
    return s + (", ..." if len(names) > n else "")


def print_engine(res):
    a = res["answers"]
    print(f"\n{TITLES[res['engine']]} {res['version']}")
    for key, title in QUESTIONS:
        x = a[key]
        if key == "facets":
            val = ", ".join(f"{g} {c}" for g, c in x["values"])
        elif key == "vector":
            val = short(x["names"])
        else:
            val = f"{x['hits']} hit(s): {short(x['names'])}"
        print(f"  {title}\n     {val}   [{x['ms']} ms; {x['how']}]")


def report():
    rows = [json.loads(p.read_text()) for p in sorted(RESULTS.glob("*.json")) if not p.name.endswith(".load.json")]
    rows.sort(key=lambda r: ENGINES.index(r["engine"]))
    if not rows:
        sys.exit("No results yet: run an engine first.")
    w = max(len(f"{TITLES[r['engine']]} {r['version']}") for r in rows) + 2
    print("Search bake-off: the same 1,100 films, the same questions\n")
    print(f"{'engine':<{w}}{'docs':>6}{'load s':>8}")
    for r in rows:
        ld = r.get("load") or {}
        print(f"{TITLES[r['engine']] + ' ' + r['version']:<{w}}{ld.get('docs', '?'):>6}{ld.get('seconds', '?'):>8}")
    for key, title in QUESTIONS:
        print(f"\n{title}")
        for r in rows:
            x = r["answers"][key]
            if key == "facets":
                val = ", ".join(f"{g} {c}" for g, c in x["values"])
            elif key == "vector":
                val = short(x["names"])
            else:
                val = f"{x['hits']:>3}  {short(x['names'])}"
            print(f"  {TITLES[r['engine']]:<14}{x['ms']:>5} ms  {val}")
    print("\nTimes are one request each from Python on this machine, warm caches; read them as a rough feel.")
    print("Typos: Meilisearch and Typesense correct them by default; Solr, OpenSearch and Elasticsearch")
    print("only when the query asks (fuzzy, fuzziness). The vectors are a toy 10-dimension model, so 'nearest'")
    print("is about the mechanics, not taste.")


def drop(e):
    {"solr": solr_drop, "meilisearch": meili_drop, "typesense": ts_drop}.get(e, lambda: es_drop(e))()
    for p in (RESULTS / f"{e}.json", RESULTS / f"{e}.load.json"):
        p.unlink(missing_ok=True)
    print(f"Removed '{INDEX}' from {TITLES[e]}.")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if cmd == "load":
            load(engine_arg())
        elif cmd == "ask":
            ask(engine_arg())
        elif cmd == "report":
            report()
        elif cmd == "drop":
            drop(engine_arg())
        else:
            sys.exit(__doc__)
    except EngineError as e:
        sys.exit(f"bakeoff: {e}")


if __name__ == "__main__":
    main()
EOF_BAKEOFF
                FRESH=1
                write_run << 'EOF'
demo_need devsvc install-search
docker_ok
ENGINES=()
for e in solr opensearch elasticsearch meilisearch typesense; do
    docker container inspect "devsvc-$e" > /dev/null 2>&1 && ENGINES+=("$e")
done
[ ${#ENGINES[@]} -gt 0 ] || { echo "No search engine is installed: dev-setup with install-search (or install-elasticsearch)."; exit 1; }
# bakeoff.py reads each engine's login from the environment.
export SOLR_PASSWORD OPENSEARCH_ADMIN_PASSWORD ELASTIC_PASSWORD MEILI_MASTER_KEY TYPESENSE_API_KEY
SOLR_PASSWORD=$(devsvc password solr 2> /dev/null); OPENSEARCH_ADMIN_PASSWORD=$(devsvc password opensearch 2> /dev/null)
ELASTIC_PASSWORD=$(devsvc password elasticsearch 2> /dev/null); MEILI_MASTER_KEY=$(devsvc password meilisearch 2> /dev/null)
TYPESENSE_API_KEY=$(devsvc password typesense 2> /dev/null)
declare -A WAS
for e in "${ENGINES[@]}"; do WAS[$e]=$(docker inspect -f '{{.State.Running}}' "devsvc-$e" 2> /dev/null); done
# run_one ENGINE [ask-only]: start it (devsvc's memory guard first), index the films, ask, stop it again if
# this demo started it. Solr, OpenSearch and Elasticsearch stop one another as they start.
run_one() {
    local e=$1 rc=0 log="$DEMO_LOGS/bakeoff-up-$1.log"
    demo_step "$e"
    if ! devsvc up "$e" > "$log" 2>&1; then
        tail -n 8 "$log"
        demo_note "$e did not start (above: why), so it sits this one out."
        return 1
    fi
    grep '^Stopping' "$log"
    if [ "${2:-}" != ask-only ]; then python3 bakeoff.py load "$e" || rc=1; fi
    [ "$rc" = 0 ] && { python3 bakeoff.py ask "$e" || rc=1; }
    [ "${WAS[$e]}" = true ] || devsvc down "$e" > /dev/null
    return $rc
}
stopped_note() {
    local e
    for e in "${ENGINES[@]}"; do
        if [ "${WAS[$e]}" = true ] && [ "$(docker inspect -f '{{.State.Running}}' "devsvc-$e" 2> /dev/null)" != true ]; then
            demo_note "$e was running before and was stopped for another engine (one Java engine at a time): 'devsvc up $e' starts it again."
        fi
    done
}
demo_note "Engines here: ${ENGINES[*]}. Each one starts in turn and stops again afterwards (unless it was already running)."
demo_note "The Java engines (Solr, OpenSearch, Elasticsearch) take a minute or two to start on this machine."
ITEMS=("all: every engine here, one at a time, then the side-by-side report")
for e in "${ENGINES[@]}"; do ITEMS+=("$e: index the films into $e and ask it the four questions"); done
ITEMS+=("report: the side-by-side report of the last runs" "drop: remove the bake-off index from every engine here")
while demo_menu "Search bake-off (films.json: $(python3 -c 'import json; print(len(json.load(open("films.json"))))') films)" "${ITEMS[@]}"; do
    case "$DEMO_CHOICE" in
        all*)    for e in "${ENGINES[@]}"; do run_one "$e"; done
                 demo_step "Side by side"; python3 bakeoff.py report; stopped_note ;;
        report*) python3 bakeoff.py report ;;
        drop*)   for e in "${ENGINES[@]}"; do
                     devsvc up "$e" > /dev/null 2>&1 && python3 bakeoff.py drop "$e"
                     [ "${WAS[$e]}" = true ] || devsvc down "$e" > /dev/null 2>&1
                 done; stopped_note ;;
        *)       run_one "${DEMO_CHOICE%%:*}"; stopped_note ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
                done_demo
            else
                fail "could not get Solr's example films (from the Solr image or GitHub)"
            fi
        fi
    fi

    # --- services/redis: a stepped tour of Redis 8
    if has install-redis && begin services redis "Redis 8 tour: strings, hashes, lists, sets, sorted sets, streams, pub/sub, JSON, time series, Bloom, vector search" \
        "generated by dev-demo (the shared Redis of install-redis)"; then
        if need devsvc install-redis && need python3 "the base install"; then
            present || FRESH=1
            gen_file "$DIR/tour.sh" << 'EOF_TOUR'
#!/bin/bash
# A stepped tour of Redis 8 on the shared Redis ('devsvc up redis'), written by dev-demo. Every key it
# makes starts with 'tour:' and is removed at the end (or on Ctrl-C).
#   tour.sh            pauses after each step
#   tour.sh nonstop    runs straight through
# Each command is shown before it runs; 'devsvc cli redis' is redis-cli with the right host and password.
NONSTOP=0; [ "${1:-}" = nonstop ] && NONSTOP=1
cd "$(dirname "$0")" || exit 1
if [ -t 1 ]; then D=$'\e[2m' B=$'\e[1m' R=$'\e[0m'; else D=; B=; R=; fi
r() { printf '%s> %s%s\n' "$D" "$*" "$R"; devsvc cli redis "$@"; }   # show it, then run it
q() { devsvc cli redis "$@"; }                                        # run it quietly
step() { echo; echo "${B}== $1 ==${R}"; [ -z "${2:-}" ] || echo "$2"; }
pause() { [ "$NONSTOP" = 1 ] || read -rp "${D}Enter: next step (Ctrl-C stops and cleans up)${R} " _ || exit 0; }
has_mod() { q MODULE LIST 2> /dev/null | tr '[:upper:]' '[:lower:]' | grep -qxE "$1"; }
cleanup() {
    q FT.DROPINDEX tour:idx > /dev/null 2>&1
    q --scan --pattern 'tour:*' 2> /dev/null | while read -r k; do q DEL "$k" > /dev/null; done
    rm -f v1.bin v2.bin v3.bin vq.bin sub.out
}
trap cleanup EXIT
q PING > /dev/null 2>&1 || { echo "Redis does not answer: 'devsvc up redis' first."; exit 1; }
echo "Redis $(q INFO server | sed -n 's/^redis_version://p' | tr -d '\r')"
cleanup

step "Strings, counters and expiry" "The simplest values, an atomic counter, and a key that deletes itself."
r SET tour:greeting "hello from the tour"
r GET tour:greeting
r INCR tour:visits; r INCRBY tour:visits 41
r SET tour:session abc123 EX 30
r TTL tour:session
pause

step "Hashes" "A record with fields: one key per object, like a row."
r HSET tour:film:1 name "Batman Begins" year 2005 genre Action
r HGETALL tour:film:1
r HINCRBY tour:film:1 year 1
pause

step "Lists" "An ordered list: push at one end, pop at the other, and you have a work queue."
r RPUSH tour:queue job-1 job-2 job-3
r LPOP tour:queue
r LRANGE tour:queue 0 -1
pause

step "Sets" "Unordered and unique; set algebra on the server."
r SADD tour:genres:batman Action Crime Drama
r SADD tour:genres:catwoman Action Fantasy Crime
r SINTER tour:genres:batman tour:genres:catwoman
pause

step "Sorted sets" "Members ordered by a score (votes here): leaderboards, priority queues, time-ordered indexes."
r ZADD tour:ratings 1520 "Batman Begins" 310 "Catwoman" 640 "Empire"
r ZREVRANGE tour:ratings 0 -1 WITHSCORES
r ZRANK tour:ratings Empire
pause

step "Streams with a consumer group" "An append-only log; a consumer group shares the entries among workers and tracks acknowledgements."
r XADD tour:events '*' type view film "Batman Begins"
r XADD tour:events '*' type rate film "Batman Begins" stars 5
r XGROUP CREATE tour:events tour-workers 0
echo "${D}> XREADGROUP GROUP tour-workers worker-1 COUNT 1 STREAMS tour:events >${R}"
out=$(q XREADGROUP GROUP tour-workers worker-1 COUNT 1 STREAMS tour:events '>'); echo "$out"
id=$(echo "$out" | sed -n 2p)
r XPENDING tour:events tour-workers
[ -n "$id" ] && r XACK tour:events tour-workers "$id"
r XLEN tour:events
pause

step "Pub/sub" "Fire-and-forget messages to whoever listens right now (a background subscriber here)."
( timeout 4 devsvc cli redis SUBSCRIBE tour:news > sub.out 2>&1 ) &
sleep 1
r PUBLISH tour:news "Redis 8 is running"
wait
echo "${D}The subscriber received:${R}"; tail -n 3 sub.out
pause

if has_mod '(re)?json'; then
    step "JSON" "Whole JSON documents, read and changed by path."
    r JSON.SET tour:doc '$' '{"name":"Batman Begins","year":2005,"cast":["Christian Bale","Michael Caine"],"rating":8.2}'
    r JSON.GET tour:doc '$.cast'
    r JSON.ARRAPPEND tour:doc '$.cast' '"Liam Neeson"'
    r JSON.NUMINCRBY tour:doc '$.rating' 0.1
    r JSON.GET tour:doc
else
    step "JSON" "skipped: this Redis has no JSON module (Redis 8's image has it)"
fi
pause

if has_mod 'timeseries'; then
    step "Time series" "Timestamped samples with retention and server-side aggregation."
    r TS.CREATE tour:temp LABELS sensor kitchen
    for i in 0 1 2 3 4 5; do q TS.ADD tour:temp $((1767225600000 + i * 60000)) $((20 + i % 3)).$i > /dev/null; done
    r TS.RANGE tour:temp - + AGGREGATION avg 120000
else
    step "Time series" "skipped: this Redis has no time series module"
fi
pause

if has_mod 'bf'; then
    step "Bloom filter" "Answers 'have I seen this?' in little memory; 'no' is certain, 'yes' is very likely."
    r BF.RESERVE tour:seen 0.01 1000
    r BF.MADD tour:seen alice bob carol
    r BF.EXISTS tour:seen bob
    r BF.EXISTS tour:seen zoe
else
    step "Bloom filter" "skipped: this Redis has no probabilistic module"
fi
pause

if has_mod 'search'; then
    step "Vector search" "Three films as 3-dimension vectors in hashes, an HNSW index, and the nearest neighbours of a query vector."
    python3 -c 'import struct
for n, v in (("v1", (1, 0, 0)), ("v2", (0.9, 0.1, 0)), ("v3", (0, 0, 1)), ("vq", (1, 0.05, 0))):
    open(n + ".bin", "wb").write(struct.pack("<3f", *v))'
    r FT.CREATE tour:idx ON HASH PREFIX 1 tour:vec: SCHEMA name TEXT emb VECTOR HNSW 6 TYPE FLOAT32 DIM 3 DISTANCE_METRIC COSINE
    q HSET tour:vec:1 name "Batman Begins" > /dev/null; q -x HSET tour:vec:1 emb < v1.bin > /dev/null
    q HSET tour:vec:2 name "The Dark Knight" > /dev/null; q -x HSET tour:vec:2 emb < v2.bin > /dev/null
    q HSET tour:vec:3 name "Godzilla: Final Wars" > /dev/null; q -x HSET tour:vec:3 emb < v3.bin > /dev/null
    echo "${D}(three hashes, each with a name and a FLOAT32 vector)${R}"
    echo "${D}> FT.SEARCH tour:idx \"*=>[KNN 2 @emb \$q AS score]\" RETURN 2 name score SORTBY score DIALECT 2 PARAMS 2 q <vector>${R}"
    q -x FT.SEARCH tour:idx '*=>[KNN 2 @emb $q AS score]' RETURN 2 name score SORTBY score DIALECT 2 PARAMS 2 q < vq.bin
else
    step "Vector search" "skipped: this Redis has no search module (Redis 8's image has it)"
fi
pause

step "Done" "Removing the tour's keys (everything under tour:)."
EOF_TOUR
            chmod +x "$DIR/tour.sh"
            write_run << 'EOF'
demo_need devsvc install-redis
docker_ok
WAS=$(docker inspect -f '{{.State.Running}}' devsvc-redis 2> /dev/null)
UP=$(devsvc up redis 2>&1) || { printf '%s\n' "$UP"; exit 1; }
[ "$WAS" = true ] || demo_on_exit "devsvc down redis"
while demo_menu "Redis 8 tour" \
        "tour: step by step, a pause after each (Ctrl-C stops and cleans up)" \
        "nonstop: the whole tour without pauses" \
        "cli: redis-cli on the shared Redis (devsvc cli redis)" \
        "insight: open Redis Insight (add database 127.0.0.1:6379)"; do
    case "$DEMO_CHOICE" in
        tour*)    bash tour.sh ;;
        nonstop*) bash tour.sh nonstop ;;
        cli*)     devsvc cli redis ;;
        insight*) if command -v redisinsight > /dev/null 2>&1; then setsid redisinsight > /dev/null 2>&1 & disown
                  else demo_note "Redis Insight is not installed: rerun dev-setup with install-redis (REDIS_INSIGHT=1)."; fi ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
            done_demo
        fi
    fi

    # --- services/mongodb: documents, queries, aggregation, indexes
    has install-mongodb || return 0
    begin services mongodb "MongoDB tour: import 1,100 films, query, update, aggregate, a text index, explain() and export" \
        "Apache Solr's example films (CC BY 2.5) and generated scripts (the shared MongoDB of install-mongodb)" || return 0
    need devsvc install-mongodb || return 0
    get_films "$DIR" || { fail "could not get Solr's example films (from the Solr image or GitHub)"; return 0; }
    FRESH=1
    mkdir -p "$DIR/steps"
    gen_file "$DIR/steps/1-prepare.js" << 'EOF_JS'
// Turn the imported strings into types: release dates become real dates, names lose their HTML escapes.
db = db.getSiblingDB("devdemo_films");
db.films.updateMany({ initial_release_date: { $type: "string" } },
    [{ $set: { released: { $dateFromString: { dateString: "$initial_release_date" } } } }]);
db.films.updateMany({ name: /&amp;/ }, [{ $set: { name: { $replaceAll: { input: "$name", find: "&amp;", replacement: "&" } } } }]);
print(`films: ${db.films.countDocuments()}, with a release date: ${db.films.countDocuments({ released: { $exists: true } })}`);
printjson(db.films.findOne({ name: "Batman Begins" }, { _id: 0, film_vector: 0 }));
EOF_JS
    gen_file "$DIR/steps/2-find.js" << 'EOF_JS'
// Queries: a filter, a projection, a sort and a limit; counting; distinct values.
db = db.getSiblingDB("devdemo_films");
print("Comedies released from 2005 on, newest first:");
db.films.find({ genre: "Comedy", released: { $gte: ISODate("2005-01-01") } }, { _id: 0, name: 1, released: 1 })
    .sort({ released: -1 }).limit(5).forEach(f => print(`  ${f.released.toISOString().slice(0, 10)}  ${f.name}`));
print(`Films by Ridley Scott: ${db.films.countDocuments({ directed_by: "Ridley Scott" })}`);
print(`Different directors: ${db.films.distinct("directed_by").length}`);
EOF_JS
    gen_file "$DIR/steps/3-update.js" << 'EOF_JS'
// Updates: set a field, push to an array, increment a number, and read the document back.
db = db.getSiblingDB("devdemo_films");
db.films.updateOne({ name: "Batman Begins" }, { $set: { rating: 8.2 }, $push: { tags: "dev-demo" } });
db.films.updateOne({ name: "Batman Begins" }, { $inc: { rating: 0.1 } });
printjson(db.films.findOne({ name: "Batman Begins" }, { _id: 0, name: 1, rating: 1, tags: 1 }));
EOF_JS
    gen_file "$DIR/steps/4-aggregate.js" << 'EOF_JS'
// Aggregation pipelines: unwind an array and group, then group by year.
db = db.getSiblingDB("devdemo_films");
print("The five biggest genres:");
db.films.aggregate([{ $unwind: "$genre" }, { $group: { _id: "$genre", films: { $sum: 1 } } },
    { $sort: { films: -1 } }, { $limit: 5 }]).forEach(g => print(`  ${String(g.films).padStart(4)}  ${g._id}`));
print("Films per year, 2003-2008:");
db.films.aggregate([{ $match: { released: { $gte: ISODate("2003-01-01"), $lt: ISODate("2009-01-01") } } },
    { $group: { _id: { $year: "$released" }, films: { $sum: 1 } } }, { $sort: { _id: 1 } }])
    .forEach(y => print(`  ${y._id}  ${y.films}`));
EOF_JS
    gen_file "$DIR/steps/5-text.js" << 'EOF_JS'
// A text index on the names, and a text search ranked by score.
db = db.getSiblingDB("devdemo_films");
db.films.createIndex({ name: "text" });
db.films.find({ $text: { $search: "harry potter" } }, { _id: 0, name: 1, score: { $meta: "textScore" } })
    .sort({ score: { $meta: "textScore" } }).limit(5).forEach(f => print(`  ${f.score.toFixed(2)}  ${f.name}`));
EOF_JS
    gen_file "$DIR/steps/6-explain.js" << 'EOF_JS'
// explain(): the same query without and with an index on the release date.
db = db.getSiblingDB("devdemo_films");
const q = { released: { $gte: ISODate("2007-01-01") } };
try { db.films.dropIndex("released_1"); } catch (e) { /* not there yet */ }
// MongoDB 7+ wraps a slot-based-engine plan in queryPlan; the classic engine puts the stages directly.
const plan = e => { let s = e.queryPlanner.winningPlan.queryPlan || e.queryPlanner.winningPlan; while (s.inputStage) { if (s.stage === "IXSCAN" || s.stage === "COLLSCAN") break; s = s.inputStage; }
    return `${s.stage}, ${e.executionStats.totalDocsExamined} documents examined for ${e.executionStats.nReturned} returned`; };
print("Without an index: " + plan(db.films.find(q).explain("executionStats")));
db.films.createIndex({ released: 1 });
print("With { released: 1 }: " + plan(db.films.find(q).explain("executionStats")));
EOF_JS
    gen_file "$DIR/steps/8-drop.js" << 'EOF_JS'
db = db.getSiblingDB("devdemo_films");
db.dropDatabase();
print("Dropped the devdemo_films database.");
EOF_JS
    write_run << 'EOF'
demo_need devsvc install-mongodb
docker_ok
WAS=$(docker inspect -f '{{.State.Running}}' devsvc-mongodb 2> /dev/null)
UP=$(devsvc up mongodb 2>&1) || { printf '%s\n' "$UP"; exit 1; }
[ "$WAS" = true ] || demo_on_exit "devsvc down mongodb"
PW=$(devsvc password mongodb 2> /dev/null)
URI="mongodb://127.0.0.1:27017/?directConnection=true"
[ -n "$PW" ] && URI="mongodb://root:$PW@127.0.0.1:27017/?authSource=admin&directConnection=true"
NONSTOP=0; [ "${1:-}" = nonstop ] && NONSTOP=1
pause() { [ "$NONSTOP" = 1 ] || read -rp "Enter: next step (Ctrl-C stops) " _ || exit 0; }
js() { devsvc cli mongodb --quiet --eval "$(cat "$1")"; }
demo_step "Import: mongoimport --jsonArray films.json into devdemo_films.films"
if command -v mongoimport > /dev/null 2>&1; then
    mongoimport --quiet --uri "$URI" --db devdemo_films --collection films --jsonArray --drop --file films.json || exit 1
else
    # No Database Tools on this machine: the mongo image carries its own mongoimport.
    demo_note "mongoimport is not installed here (install-mongodb's Database Tools): using the one in the container."
    docker cp films.json devsvc-mongodb:/tmp/films.json > /dev/null || exit 1
    docker exec devsvc-mongodb mongoimport --quiet --uri "${URI/127.0.0.1/localhost}" --db devdemo_films --collection films \
        --jsonArray --drop --file /tmp/films.json || exit 1
fi
echo "imported $(devsvc cli mongodb --quiet --eval 'db.getSiblingDB("devdemo_films").films.countDocuments()') films"
pause
for s in steps/[1-6]-*.js; do
    demo_step "$(sed -n '1s#^// ##p' "$s")"
    js "$s"
    pause
done
demo_step "Export: mongoexport the documentaries to CSV"
if command -v mongoexport > /dev/null 2>&1; then
    mongoexport --quiet --uri "$URI" --db devdemo_films --collection films --type=csv --fields name,released \
        --query '{"genre": "Documentary film"}' --out documentaries.csv && head -n 6 documentaries.csv
    echo "... $(($(wc -l < documentaries.csv) - 1)) rows in $DEMO_DIR/documentaries.csv"
else
    demo_note "mongoexport is not installed here (install-mongodb's Database Tools); skipped."
fi
pause
if [ "$NONSTOP" = 1 ] || { read -rp "Drop the devdemo_films database now? [Y/n] " a; [ "${a,,}" != n ]; }; then
    js steps/8-drop.js
else
    demo_note "Kept: 'devsvc cli mongodb' then 'use devdemo_films'. Compass (ChromeOS launcher) shows it at mongodb://127.0.0.1:27017."
fi
EOF
    done_demo
}

demo_fastmcp() {
    begin agents fastmcp "FastMCP: a films server with tools and a resource, over stdio, inside FastAPI over HTTP, in the Inspector and in Claude Code" \
        "generated by dev-demo; FastMCP: https://gofastmcp.com (films: Apache Solr's example, CC BY 2.5)" || return 0
    need fastmcp install-agentic || return 0
    need uv "the base install" || return 0
    get_films "$DIR" || { fail "could not get Solr's example films (from the Solr image or GitHub)"; return 0; }
    FRESH=1
    gen_file "$DIR/server.py" << 'EOF_PY'
"""films: a FastMCP server over Apache Solr's example films (dev-demo, install-agentic).

Tools: search_films, films_by_director, top_genres. Resource: films://about.
    fastmcp run server.py                       stdio, as MCP clients start it
    fastmcp list server.py / fastmcp call server.py search_films query="harry potter"
    fastmcp dev inspector server.py             in the MCP Inspector
app.py serves the same server over HTTP inside a FastAPI app.
"""
import html
import json
import pathlib
from collections import Counter

from fastmcp import FastMCP

FILMS = [
    {"name": html.unescape(f["name"]), "directed_by": f.get("directed_by", []), "genre": f.get("genre", []),
     "released": f.get("initial_release_date")}
    for f in json.loads((pathlib.Path(__file__).parent / "films.json").read_text())
]

mcp = FastMCP("films", instructions="About 1,100 films (Freebase via Apache Solr's example): names, "
                                    "directors, genres and release dates. Use the tools to look films up.")


def _words(s):
    return "".join(c.lower() if c.isalnum() else " " for c in s).split()


@mcp.tool
def search_films(query: str, limit: int = 5) -> list[dict]:
    """Films whose name contains every word of the query, newest first."""
    want = _words(query)
    hits = [f for f in FILMS if all(w in _words(f["name"]) for w in want)]
    hits.sort(key=lambda f: f["released"] or "", reverse=True)
    return hits[:limit]


@mcp.tool
def films_by_director(director: str) -> list[dict]:
    """Every film by a director (case-insensitive match on the full name)."""
    d = director.strip().lower()
    return [f for f in FILMS if any(x.lower() == d for x in f["directed_by"])]


@mcp.tool
def top_genres(n: int = 5) -> list[dict]:
    """The n genres with the most films."""
    c = Counter(g for f in FILMS for g in f["genre"])
    return [{"genre": g, "films": k} for g, k in c.most_common(n)]


@mcp.resource("films://about")
def about() -> str:
    """Where the data comes from."""
    return (f"{len(FILMS)} films from Freebase, as shipped in Apache Solr's example/films "
            "(Creative Commons Attribution 2.5). Fields: name, directed_by, genre, released.")


if __name__ == "__main__":
    mcp.run()
EOF_PY
    gen_file "$DIR/app.py" << 'EOF_PY'
"""The films MCP server inside a FastAPI app: REST routes and MCP side by side (dev-demo).

    uv run --with fastmcp --with fastapi --with uvicorn uvicorn app:app --port 8765
REST:  http://127.0.0.1:8765/films?q=harry+potter      http://127.0.0.1:8765/docs
MCP:   http://127.0.0.1:8765/mcp/   (streamable HTTP)  ->  fastmcp list http://127.0.0.1:8765/mcp/
"""
from fastapi import FastAPI

from server import mcp, search_films, top_genres

mcp_app = mcp.http_app(path="/")
app = FastAPI(title="films", lifespan=mcp_app.lifespan)


@app.get("/films")
def films(q: str, limit: int = 5):
    return search_films.fn(q, limit) if hasattr(search_films, "fn") else search_films(q, limit)


@app.get("/genres")
def genres(n: int = 5):
    return top_genres.fn(n) if hasattr(top_genres, "fn") else top_genres(n)


app.mount("/mcp", mcp_app)
EOF_PY
    write_run << 'EOF'
demo_need fastmcp install-agentic
demo_need uv "the base install"
WITH=(--with fastmcp --with fastapi --with uvicorn)
while demo_menu "FastMCP films server" \
        "call: list the tools over stdio, then call each one (fastmcp list / fastmcp call)" \
        "http: the server inside a FastAPI app on :8765 (REST + MCP); Ctrl-C stops" \
        "inspector: the server in the MCP Inspector (a browser tab); Ctrl-C stops" \
        "claude: add it to Claude Code as 'films' (user scope), so 'claude' can use the tools" \
        "remove: take 'films' out of Claude Code again"; do
    case "$DEMO_CHOICE" in
        call*)      demo_step "fastmcp list server.py"; fastmcp list server.py
                    demo_step "fastmcp call server.py search_films query='harry potter'"; fastmcp call server.py search_films query="harry potter"
                    demo_step "fastmcp call server.py films_by_director director='Ridley Scott'"; fastmcp call server.py films_by_director director="Ridley Scott"
                    demo_step "fastmcp call server.py top_genres n=3"; fastmcp call server.py top_genres n=3 ;;
        http*)      demo_note "REST: http://127.0.0.1:8765/films?q=harry+potter (and /docs).  MCP: http://127.0.0.1:8765/mcp/"
                    demo_note "From another terminal: fastmcp list http://127.0.0.1:8765/mcp/"
                    demo_open_when_ready 8765 "http://127.0.0.1:8765/docs"
                    uv run --no-project "${WITH[@]}" uvicorn app:app --host 127.0.0.1 --port 8765 ;;
        inspector*) demo_note "The Inspector opens in the browser; its 'Connect' starts the server over stdio. Ctrl-C here stops both."
                    fastmcp dev inspector server.py ;;
        claude*)    demo_need claude install-node
                    claude mcp remove --scope user films > /dev/null 2>&1
                    claude mcp add --scope user films -- fastmcp run "$DEMO_DIR/server.py" \
                        && demo_note "Added. In 'claude', ask: Which films did Ridley Scott direct? ('claude mcp list' shows it.)" ;;
        remove*)    demo_need claude install-node; claude mcp remove --scope user films ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

demo_cloudflare() {
    begin cloud cloudflare "Cloudflare Worker with a D1 database: 'wrangler dev' runs it locally (no account); deploy with your token" \
        "generated by dev-demo; Workers: https://developers.cloudflare.com/workers/" || return 0
    need wrangler install-cloudflare || return 0
    present || FRESH=1
    gen_file "$DIR/wrangler.toml" << 'EOF_TOML'
# A Worker with one D1 database (written by dev-demo). 'wrangler dev' runs it in workerd on this machine,
# with the database in .wrangler/state; 'wrangler deploy' needs an account (the launcher's deploy item).
name = "devdemo-notes"
main = "src/index.js"
compatibility_date = "2026-09-01"

[[d1_databases]]
binding = "DB"
database_name = "devdemo-notes"
database_id = "00000000-0000-0000-0000-000000000000"   # replaced by the launcher's deploy item
migrations_dir = "migrations"
EOF_TOML
    gen_file "$DIR/migrations/0001_notes.sql" << 'EOF_SQL'
CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT NOT NULL, created TEXT NOT NULL DEFAULT (datetime('now')));
INSERT INTO notes (body) VALUES ('Hello from D1: this note came with the migration.');
EOF_SQL
    gen_file "$DIR/src/index.js" << 'EOF_JS'
// A notes page on a D1 database (dev-demo). GET / lists the notes; POST / adds one; GET /api/notes is JSON.
const page = (notes) => `<!doctype html><meta charset="utf-8"><title>D1 notes</title>
<style>body{font:16px system-ui;max-width:40rem;margin:2rem auto;padding:0 1rem}li{margin:.3rem 0}small{color:#777}</style>
<h1>Notes in D1</h1><form method="post"><input name="body" required autofocus size="40"> <button>Add</button></form>
<ul>${notes.map((n) => `<li>${n.body.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c])} <small>${n.created}</small></li>`).join("")}</ul>
<p><small>Served by a Cloudflare Worker; <a href="/api/notes">/api/notes</a> is the same as JSON.</small></p>`;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/") {
      const body = (await request.formData()).get("body");
      if (body) await env.DB.prepare("INSERT INTO notes (body) VALUES (?)").bind(String(body).slice(0, 500)).run();
      return Response.redirect(new URL("/", url), 303);
    }
    const { results } = await env.DB.prepare("SELECT id, body, created FROM notes ORDER BY id DESC LIMIT 50").all();
    if (url.pathname === "/api/notes") return Response.json(results);
    return new Response(page(results), { headers: { "content-type": "text/html; charset=utf-8" } });
  },
};
EOF_JS
    write_run << 'EOF'
demo_need wrangler install-cloudflare
export WRANGLER_SEND_METRICS=false
[ -r "$HOME/.config/dev-init/secrets.env" ] && for _k in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
    [ -n "${!_k:-}" ] && continue
    _v=$(grep -E "^(export )?$_k=" "$HOME/.config/dev-init/secrets.env" | tail -1 | cut -d= -f2- | sed -E "s/^['\"]//;s/['\"]\$//")
    [ -n "$_v" ] && export "$_k=$_v"
done
local_db() { CI=1 wrangler d1 migrations apply devdemo-notes --local > "$DEMO_LOGS/cloudflare-migrate.log" 2>&1 \
    || { tail -n 8 "$DEMO_LOGS/cloudflare-migrate.log"; return 1; }; }
ITEMS=("dev: run the Worker locally with wrangler dev on :8787 (no account); Ctrl-C stops"
       "deploy: create the D1 database in your account and deploy the Worker (asks first)")
command -v cloudflared > /dev/null 2>&1 && ITEMS+=("tunnel: the local Worker on a public trycloudflare.com URL (cloudflared quick tunnel)")
while demo_menu "Cloudflare Worker + D1" "${ITEMS[@]}"; do
    case "$DEMO_CHOICE" in
        dev*)    local_db || continue
                 demo_note "The database lives in $DEMO_DIR/.wrangler/state; add notes in the page."
                 demo_open_when_ready 8787 http://127.0.0.1:8787
                 wrangler dev --ip 127.0.0.1 --port 8787 ;;
        deploy*) if ! CI=1 wrangler whoami < /dev/null 2>&1 | grep -qiE 'associated with the email|You are logged in'; then
                     echo "Not logged in to Cloudflare: set CLOUDFLARE_API_TOKEN (and CLOUDFLARE_ACCOUNT_ID) in"
                     echo "~/.config/dev-init/secrets.env, or run 'wrangler login'. Then try again."; continue
                 fi
                 read -rp "This creates the D1 database 'devdemo-notes' and deploys the Worker 'devdemo-notes' to your account. Go on? [y/N] " a
                 [ "${a,,}" = y ] || continue
                 if grep -q '00000000-0000-0000-0000-000000000000' wrangler.toml; then
                     out=$(wrangler d1 create devdemo-notes 2>&1); echo "$out" | tail -n 12
                     id=$(echo "$out" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n 1)
                     [ -n "$id" ] || id=$(wrangler d1 info devdemo-notes --json 2> /dev/null | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n 1)
                     [ -n "$id" ] || { echo "Could not read the new database's id (above)."; continue; }
                     sed -i "s/00000000-0000-0000-0000-000000000000/$id/" wrangler.toml
                 fi
                 CI=1 wrangler d1 migrations apply devdemo-notes --remote && wrangler deploy \
                     && demo_note "Deployed. Remove it later: wrangler delete devdemo-notes; wrangler d1 delete devdemo-notes" ;;
        tunnel*) demo_note "WARNING: the URL cloudflared prints is PUBLIC: anyone who has it can read and add notes until you"
                 demo_note "press Ctrl-C. No account is needed for a quick tunnel."
                 read -rp "Open a public tunnel to the local Worker? [y/N] " a
                 [ "${a,,}" = y ] || continue
                 local_db || continue
                 demo_bg wrangler-dev wrangler dev --ip 127.0.0.1 --port 8787
                 demo_wait_port 8787 120 || continue
                 cloudflared tunnel --no-autoupdate --url http://127.0.0.1:8787 ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# =================================================================
# DEMOS: GraphQL with Apollo (v90, install-graphql)
# =================================================================

# v90: graphql/apollo-supergraph: the films data the v89 demos use, split across two subgraphs in two languages
# and federated by the Apollo Router. films (Python, Strawberry, :4001) owns Film; reviews (Node, Apollo Server
# with @apollo/subgraph, :4002) adds Film.reviews, Film.averageRating and an addReview mutation, kept in a JSON
# file. The router listens on :4000 and apollo-mcp-server on :8771. No account: APOLLO_KEY is unset in the
# launcher. Strawberry (uv) and the Node packages (npm) arrive on the first launch.
demo_graphql() {
    if begin graphql apollo-supergraph "Apollo federation: a Python films subgraph and a Node reviews subgraph behind the Apollo Router, then as MCP tools" \
        "generated by dev-demo; Rover, Router, MCP Server: https://www.apollographql.com/docs (films: Apache Solr's example, CC BY 2.5)" \
        && need rover install-graphql && need router install-graphql && need npm install-node && need uv "the base install"; then
        if get_films "$DIR"; then
            FRESH=1
            demo_graphql_files
            demo_graphql_run
            done_demo
        else
            fail "could not get Solr's example films (from the Solr image or GitHub)"
        fi
    fi
    demo_drupal_graphql
}

demo_graphql_files() {
    gen_file "$DIR/films/films.py" << 'EOF_PY'
"""films: the films subgraph (dev-demo graphql/apollo-supergraph). Strawberry, Apollo Federation 2, port 4001.

    uv run --no-project --with strawberry-graphql --with uvicorn uvicorn films:app --app-dir films --port 4001
Owns Film, keyed on id (a Freebase id such as /en/gladiator_2000): name, year, genres, directors.
The reviews subgraph adds Film.reviews and Film.averageRating; the router joins them on id.
"""
import html
import json
import pathlib
from typing import Optional

import strawberry
from strawberry.asgi import GraphQL

RAW = json.loads((pathlib.Path(__file__).resolve().parent.parent / "films.json").read_text())
BY_ID = {f["id"]: f for f in RAW}


def _words(s: str) -> list[str]:
    return "".join(c.lower() if c.isalnum() else " " for c in s).split()


@strawberry.federation.type(keys=["id"], description="A film from Freebase (Apache Solr's example films).")
class Film:
    id: strawberry.ID
    name: str
    year: Optional[int]
    genres: list[str]
    directors: list[str]

    @classmethod
    def resolve_reference(cls, id: strawberry.ID) -> Optional["Film"]:
        f = BY_ID.get(id)
        return to_film(f) if f else None


def to_film(f: dict) -> Film:
    date = f.get("initial_release_date") or ""
    return Film(id=strawberry.ID(f["id"]), name=html.unescape(f["name"]), year=int(date[:4]) if date[:4].isdigit() else None,
                genres=f.get("genre", []), directors=f.get("directed_by", []))


@strawberry.type
class Query:
    @strawberry.field(description="One film by its id.")
    def film(self, id: strawberry.ID) -> Optional[Film]:
        f = BY_ID.get(id)
        return to_film(f) if f else None

    @strawberry.field(description="Films, newest first: those in a genre, and/or whose name contains every word of search.")
    def films(self, genre: Optional[str] = None, search: Optional[str] = None, first: int = 10) -> list[Film]:
        want = _words(search or "")
        hits = [f for f in RAW
                if (genre is None or any(g.lower() == genre.lower() for g in f.get("genre", [])))
                and all(w in _words(html.unescape(f["name"])) for w in want)]
        hits.sort(key=lambda f: f.get("initial_release_date") or "", reverse=True)
        return [to_film(f) for f in hits[:max(0, min(first, 100))]]


try:
    schema = strawberry.federation.Schema(query=Query, federation_version="2.7")
except TypeError:   # Strawberry before federation_version (2024 and older)
    schema = strawberry.federation.Schema(query=Query, enable_federation_2=True)
app = GraphQL(schema)
EOF_PY
    gen_file "$DIR/reviews/schema.graphql" << 'EOF_GQL'
# The reviews subgraph (dev-demo graphql/apollo-supergraph). Film is owned by the films subgraph; this one adds
# its reviews. Review.film hands the router a Film reference, which films resolves.
extend schema @link(url: "https://specs.apollo.dev/federation/v2.7", import: ["@key"])

type Film @key(fields: "id") {
  id: ID!
  "Reviews of this film, oldest first."
  reviews: [Review!]!
  "The mean rating (1 to 5, one decimal), or null with no reviews."
  averageRating: Float
}

type Review {
  id: ID!
  film: Film!
  rating: Int!
  comment: String
  author: String!
  createdAt: String!
}

type Query {
  "The newest reviews first."
  latestReviews(first: Int = 5): [Review!]!
}

type Mutation {
  "Add a review: rating 1 to 5."
  addReview(filmId: ID!, rating: Int!, comment: String, author: String): Review!
}
EOF_GQL
    gen_file "$DIR/reviews/index.mjs" << 'EOF_JS'
// The reviews subgraph (dev-demo graphql/apollo-supergraph): Apollo Server with @apollo/subgraph on :4002.
// Data: reviews.json next to this file (written on every addReview). Run: node --watch reviews/index.mjs
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { ApolloServer } from '@apollo/server';
import { startStandaloneServer } from '@apollo/server/standalone';
import { buildSubgraphSchema } from '@apollo/subgraph';
import { GraphQLError, parse } from 'graphql';

const here = new URL('.', import.meta.url).pathname;
const DATA = here + 'reviews.json';
const load = () => (existsSync(DATA) ? JSON.parse(readFileSync(DATA, 'utf8')) : []);
const save = (all) => writeFileSync(DATA, JSON.stringify(all, null, 2) + '\n');
const of = (filmId) => load().filter((r) => r.filmId === filmId);

const resolvers = {
  Query: {
    latestReviews: (_, { first }) => load().slice(-Math.max(0, first)).reverse(),
  },
  Mutation: {
    addReview: (_, { filmId, rating, comment, author }) => {
      if (!Number.isInteger(rating) || rating < 1 || rating > 5) throw new GraphQLError('rating must be 1 to 5');
      const all = load();
      const review = { id: String(all.length + 1), filmId, rating, comment: comment ?? null, author: author || 'you', createdAt: new Date().toISOString() };
      all.push(review);
      save(all);
      return review;
    },
  },
  Film: {
    __resolveReference: (ref) => ({ id: ref.id }),
    reviews: (film) => of(film.id),
    averageRating: (film) => {
      const rs = of(film.id);
      return rs.length ? Math.round((rs.reduce((s, r) => s + r.rating, 0) / rs.length) * 10) / 10 : null;
    },
  },
  Review: {
    film: (review) => ({ __typename: 'Film', id: review.filmId }),
  },
};

const server = new ApolloServer({
  schema: buildSubgraphSchema([{ typeDefs: parse(readFileSync(here + 'schema.graphql', 'utf8')), resolvers }]),
});
const port = Number(process.env.PORT || 4002);
const { url } = await startStandaloneServer(server, { listen: { host: '127.0.0.1', port } });
console.log(`reviews subgraph ready at ${url}`);
EOF_JS
    gen_file "$DIR/reviews/package.json" << 'EOF_JSON'
{
  "name": "devdemo-reviews-subgraph",
  "private": true,
  "type": "module",
  "description": "The reviews subgraph of dev-demo's graphql/apollo-supergraph",
  "scripts": { "start": "node index.mjs" },
  "dependencies": {
    "@apollo/server": "^5",
    "@apollo/subgraph": "^2",
    "graphql": "^16"
  }
}
EOF_JSON
    gen_file "$DIR/reviews/reviews.json" << 'EOF_JSON'
[
  { "id": "1", "filmId": "/en/gladiator_2000", "rating": 5, "comment": "Still the arena film the others are measured against.", "author": "dev-demo", "createdAt": "2026-09-30T12:00:00Z" },
  { "id": "2", "filmId": "/en/gladiator_2000", "rating": 4, "comment": "Long, loud and worth it.", "author": "dev-demo", "createdAt": "2026-09-30T12:05:00Z" },
  { "id": "3", "filmId": "/en/harry_potter_and_the_goblet_of_fire_2005", "rating": 4, "comment": "The dragon task alone earns the stars.", "author": "dev-demo", "createdAt": "2026-09-30T12:10:00Z" },
  { "id": "4", "filmId": "/en/black_hawk_down", "rating": 3, "comment": "Relentless; hard to watch twice.", "author": "dev-demo", "createdAt": "2026-09-30T12:15:00Z" }
]
EOF_JSON
    gen_file "$DIR/supergraph.yaml" << 'EOF_YAML'
# The two subgraphs, for 'rover dev' and 'rover supergraph compose' (written by dev-demo).
# films is read by introspection (its _service SDL), so it must be running; reviews comes from its file.
subgraphs:
  films:
    routing_url: http://127.0.0.1:4001/graphql
    schema:
      subgraph_url: http://127.0.0.1:4001/graphql
  reviews:
    routing_url: http://127.0.0.1:4002/
    schema:
      file: ./reviews/schema.graphql
EOF_YAML
    gen_file "$DIR/router.yaml" << 'EOF_YAML'
# Apollo Router v2 configuration for graphql/apollo-supergraph (written by dev-demo). Used by the plain
# 'router' (compose item) and by 'rover dev' (dev item).
supergraph:
  # 127.0.0.1: this machine only. 0.0.0.0:4000 serves the LAN too (then add 4000 to LAN_DEV_PORTS).
  listen: 127.0.0.1:4000
  introspection: true
# Apollo Sandbox on http://127.0.0.1:4000 (it loads from Apollo's CDN, so it needs the internet).
sandbox:
  enabled: true
homepage:
  enabled: false
# Browser apps on this machine (any localhost port) and GraphOS Studio may call the router.
cors:
  policies:
    - origins:
        - https://studio.apollographql.com
      match_origins:
        - "^http://(localhost|127[.]0[.]0[.]1):[0-9]+$"
# A request with the header 'Apollo-Expose-Query-Plan: true' gets the query plan in extensions.apolloQueryPlan.
plugins:
  experimental.expose_query_plan: true
EOF_YAML
    gen_file "$DIR/mcp/mcp.yaml" << 'EOF_YAML'
# apollo-mcp-server configuration (written by dev-demo): the three operations in mcp/operations become MCP
# tools, run against the router on :4000. Paths are relative to the demo folder (the launcher runs it there).
endpoint: http://127.0.0.1:4000/
transport:
  type: streamable_http
  address: 127.0.0.1
  port: 8771
schema:
  source: local
  path: ./mcp/api.graphql
operations:
  source: local
  paths:
    - ./mcp/operations
# AddReview is a mutation: 'explicit' exposes the mutations in the operation files, and no others.
overrides:
  mutation_mode: explicit
introspection:
  introspect:
    enabled: true
EOF_YAML
    gen_file "$DIR/mcp/operations/SearchFilms.graphql" << 'EOF_GQL'
# Films whose name contains every word of search (newest first), with genres, directors and the average review rating.
query SearchFilms($search: String!, $first: Int) {
  films(search: $search, first: $first) {
    id
    name
    year
    genres
    directors
    averageRating
  }
}
EOF_GQL
    gen_file "$DIR/mcp/operations/FilmWithReviews.graphql" << 'EOF_GQL'
# One film by its id (from SearchFilms), with every review.
query FilmWithReviews($id: ID!) {
  film(id: $id) {
    id
    name
    year
    directors
    averageRating
    reviews {
      rating
      comment
      author
      createdAt
    }
  }
}
EOF_GQL
    gen_file "$DIR/mcp/operations/AddReview.graphql" << 'EOF_GQL'
# Add a review of a film (its id from SearchFilms): rating 1 to 5 and an optional comment.
mutation AddReview($filmId: ID!, $rating: Int!, $comment: String) {
  addReview(filmId: $filmId, rating: $rating, comment: $comment, author: "Claude") {
    id
    rating
    comment
    film {
      name
      averageRating
    }
  }
}
EOF_GQL
}

demo_graphql_run() {
    write_run << 'EOF'
demo_need rover install-graphql
demo_need router install-graphql
demo_need npm install-node
demo_need uv "the base install"
# Local only: an APOLLO_KEY in the environment would make the router report to GraphOS (dev-init's notes).
unset APOLLO_KEY APOLLO_GRAPH_REF
export APOLLO_TELEMETRY_DISABLED=true APOLLO_ELV2_LICENSE=accept
listening() { (exec 3<> "/dev/tcp/127.0.0.1/$1") 2> /dev/null; }
holder() { ss -ltnpH "sport = :$1" 2> /dev/null | grep -oE '"[^"]+",pid=[0-9]+' | head -n 1 | sed -E 's/"([^"]+)",pid=([0-9]+)/\1 (pid \2)/'; }
ours() { case "$(readlink -f "/proc/$1/cwd" 2> /dev/null)" in "$DEMO_DIR"|"$DEMO_DIR"/*) return 0 ;; esac; return 1; }
# port_free PORT WHAT: 0 when nothing listens on PORT; else says what does.
port_free() {
    listening "$1" || return 0
    local h; h=$(holder "$1")
    echo "Port $1 ($2) is in use by ${h:-another process}."
    echo "'$0 stop' stops this demo's own pieces; the Jekyll demo and drupal/drupal-graphql (local) also use 4000."
    return 1
}
# stop_ours PORT...: stop what this demo started on those ports (its process groups), nothing else.
stop_ours() {
    local p pid pg n=0
    for p in "$@"; do
        for pid in $(ss -ltnpH "sport = :$p" 2> /dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u); do
            ours "$pid" || continue
            pg=$(ps -o pgid= -p "$pid" | tr -d ' ')
            kill -TERM -- "-$pg" 2> /dev/null || kill -TERM "$pid" 2> /dev/null
            n=$((n + 1))
        done
    done
    echo "Stopped $n of this demo's servers."
}
# up PORT NAME SECONDS: wait for the server just started with demo_bg; stop waiting if it exits.
up() {
    local pid=${DEMO_PIDS[-1]} i
    printf 'Waiting for %s on :%s ' "$2" "$1"
    for ((i = 0; i < $3; i++)); do
        listening "$1" && { echo " up"; return 0; }
        kill -0 "$pid" 2> /dev/null || { echo " it stopped:"; tail -n 8 "$DEMO_LOGS/$2.log"; return 1; }
        [ $((i % 5)) -eq 0 ] && printf '.'
        sleep 1
    done
    echo " not up after $3s:"; tail -n 8 "$DEMO_LOGS/$2.log"; return 1
}
films_up() {
    listening 4001 && return 0
    demo_bg films uv run --no-project --with strawberry-graphql --with uvicorn \
        uvicorn films:app --app-dir films --host 127.0.0.1 --port 4001 --reload --reload-dir films
    up 4001 films 300   # the first run fetches Strawberry
}
reviews_up() {
    listening 4002 && return 0
    if [ ! -d reviews/node_modules ]; then
        demo_step "npm install in reviews/ (Apollo Server, @apollo/subgraph; first run only)"
        ( cd reviews && npm install --no-audit --no-fund --loglevel=error ) || return 1
    fi
    demo_bg reviews node --watch reviews/index.mjs
    up 4002 reviews 60
}
subgraphs_up() {
    films_up && reviews_up || return 1
    for _ in $(seq 1 40); do curl -fsS -o /dev/null -H 'Content-Type: application/json' --data '{"query":"{_service{sdl}}"}' http://127.0.0.1:4001/graphql 2> /dev/null && return 0; sleep 0.5; done
    echo "The films subgraph does not answer:"; tail -n 8 "$DEMO_LOGS/films.log"; return 1
}
compose() { rover supergraph compose --config supergraph.yaml > supergraph.graphql.new && mv supergraph.graphql.new supergraph.graphql; }
# router_up: a router on :4000 for the items that need one (left alone when one is already there).
router_up() {
    listening 4000 && return 0
    subgraphs_up && compose || return 1
    demo_bg router router --supergraph supergraph.graphql --config router.yaml
    up 4000 router 60
}
gql() {   # gql QUERY [HEADER]: POST to the router, pretty-printed
    python3 - "$1" "${2:-}" << 'PY'
import json, sys, urllib.error, urllib.request
q, h = sys.argv[1], sys.argv[2]
headers = {"Content-Type": "application/json"}
if h:
    k, v = h.split(":", 1); headers[k.strip()] = v.strip()
req = urllib.request.Request("http://127.0.0.1:4000/", json.dumps({"query": q}).encode(), headers)
try:
    r = json.load(urllib.request.urlopen(req, timeout=60))
except urllib.error.HTTPError as e:
    r = json.loads(e.read() or b"{}")
except urllib.error.URLError as e:
    sys.exit(f"The router on :4000 did not answer: {e.reason}")
plan = (r.get("extensions") or {}).pop("apolloQueryPlan", None)
if plan:
    print("Query plan (the router's fetches, in order):\n" + (plan.get("text") or json.dumps(plan.get("object"), indent=2)) + "\n")
print(json.dumps(r, indent=2, ensure_ascii=False))
PY
}
# A 'break' cut short by Ctrl-C leaves its backup: put the real schema back first.
[ -f reviews/schema.graphql.orig ] && mv -f reviews/schema.graphql.orig reviews/schema.graphql
PLAN_QUERY='query FilmsAndReviews {
  films(search: "harry potter", first: 3) { name year directors averageRating reviews { rating comment } }
  latestReviews(first: 3) { rating comment film { name year } }
}'

while demo_menu "Apollo supergraph: films (Python :4001) + reviews (Node :4002) behind the router (:4000)" \
        "dev: rover dev on :4000, recomposing as you edit films/films.py or reviews/schema.graphql; Ctrl-C stops" \
        "compose: rover supergraph compose, then the plain router with router.yaml, as in production; Ctrl-C stops" \
        "plan: one query across both subgraphs, with the router's query plan" \
        "break: a conflicting field in reviews/schema.graphql; composition refuses it, and the file is restored" \
        "mcp: apollo-mcp-server on :8771 over three operations, added to Claude Code as 'films-graphql'; Ctrl-C stops" \
        "remove: take 'films-graphql' out of Claude Code" \
        "stop: stop this demo's servers left running on 4000-4002 and 8771"; do
    case "$DEMO_CHOICE" in
        dev*)
            port_free 4000 "the router" || continue
            subgraphs_up || continue
            demo_note "Edit films/films.py or reviews/schema.graphql (+ index.mjs): the subgraph restarts and rover dev recomposes."
            demo_note "Apollo Sandbox: http://127.0.0.1:4000 (needs the internet). Try the 'plan' item from another terminal."
            demo_open_when_ready 4000 http://127.0.0.1:4000
            rover dev --supergraph-config supergraph.yaml --router-config router.yaml --supergraph-address 127.0.0.1 --supergraph-port 4000 ;;
        compose*)
            port_free 4000 "the router" || continue
            subgraphs_up || continue
            demo_step "rover supergraph compose --config supergraph.yaml > supergraph.graphql"
            compose || continue
            echo "supergraph.graphql: $(wc -l < supergraph.graphql) lines; subgraphs: $(grep -oE 'join__graph\(name: "[a-z]+"' supergraph.graphql | cut -d'"' -f2 | tr '\n' ' ')"
            demo_step "router --supergraph supergraph.graphql --config router.yaml"
            demo_note "CORS, introspection, Sandbox and query-plan output are in router.yaml. No key: the router runs as free Router Core."
            demo_open_when_ready 4000 http://127.0.0.1:4000
            router --supergraph supergraph.graphql --config router.yaml ;;
        plan*)
            router_up || continue
            demo_step "One query, two subgraphs (films finds the films, reviews adds ratings; and the other way round)"
            printf '%s\n\n' "$PLAN_QUERY"
            gql "$PLAN_QUERY" "Apollo-Expose-Query-Plan: true" ;;
        break*)
            subgraphs_up || continue
            cp reviews/schema.graphql reviews/schema.graphql.orig
            # films owns Film.name as a String; reviews now claims it as an Int.
            sed -i 's/^type Film @key(fields: "id") {$/&\n  name: Int/' reviews/schema.graphql
            demo_step "reviews/schema.graphql now declares Film.name: Int (films has name: String!)"
            grep -n -A3 '^type Film' reviews/schema.graphql
            demo_step "rover supergraph compose"
            rover supergraph compose --config supergraph.yaml > /dev/null && echo "(it composed; it should not have)"
            mv -f reviews/schema.graphql.orig reviews/schema.graphql
            demo_note "Restored reviews/schema.graphql. If 'dev' runs in another terminal, it showed the same error and has recomposed since." ;;
        mcp*)
            demo_need apollo-mcp-server install-graphql
            port_free 8771 "apollo-mcp-server" || continue
            router_up || continue
            demo_step "rover graph introspect http://127.0.0.1:4000/ > mcp/api.graphql (the router's API schema)"
            rover graph introspect http://127.0.0.1:4000/ > mcp/api.graphql || continue
            if command -v claude > /dev/null 2>&1; then
                claude mcp remove --scope user films-graphql > /dev/null 2>&1
                claude mcp add --scope user --transport http films-graphql http://127.0.0.1:8771/mcp \
                    && demo_note "Added to Claude Code as 'films-graphql' (user scope). While this runs, ask 'claude':"
                demo_note "  Find the Harry Potter films and their ratings, then give Goblet of Fire a 5-star review."
            else
                demo_note "Claude Code is not installed (install-node); any MCP client can use http://127.0.0.1:8771/mcp"
            fi
            demo_note "Tools: SearchFilms, FilmWithReviews, AddReview (mcp/operations) and introspect. Ctrl-C stops."
            apollo-mcp-server mcp/mcp.yaml ;;
        remove*)
            demo_need claude install-node; claude mcp remove --scope user films-graphql ;;
        stop*)
            stop_ours 4000 4001 4002 8771 ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
}

# v90: drupal/drupal-graphql: Drupal 11's Umami recipes and articles through the graphql module (5.x, 4.x as a
# fallback) and GraphQL Compose 2.x, which generates the schema from the content types. Two installs side by
# side: local (PHP's built-in server + SQLite on :8889) and ddev (DDEV project devdemo-drupal-graphql,
# MariaDB). Then the router federates each with the kitchen subgraph (Node, on the host), which adds
# timesCooked, rating and onShoppingList to NodeRecipe; apollo-mcp-server puts it in Claude Code.
#   local: router 4000, kitchen 4002, MCP 8771, Claude Code 'umami-graphql'
#   ddev:  router 4010, kitchen 4012, MCP 8772, Claude Code 'umami-graphql-ddev'
# Drupal is never changed for federation: its introspected schema gets @key(fields: "id", resolvable: false)
# on NodeRecipe, so the router never asks Drupal for a recipe by key. Composer, Drupal and the Node packages
# arrive on the first 'serve' of each site; dev-demo writes only the launcher's own files.
demo_drupal_graphql() {
    begin drupal drupal-graphql "Drupal Umami over GraphQL (graphql + GraphQL Compose), locally and in DDEV, federated by the Apollo Router, as MCP tools" \
        "https://www.drupal.org/project/graphql + https://www.drupal.org/project/graphql_compose (Apollo: https://www.apollographql.com/docs)" || return 0
    need php "the base install" || return 0
    need composer install-web || return 0
    need npm install-node || return 0
    php -m 2> /dev/null | grep -qi '^pdo_sqlite$' || apt_need php-sqlite3 || { fail "php-sqlite3 missing"; return 0; }
    FRESH=1
    mkdir -p "$DIR/tools"
    # tools/gq.py is the launcher's helper: rewritten on every run, unlike the files gen_file keeps.
    demo_drupal_graphql_files
    demo_drupal_graphql_run
    done_demo
}

demo_drupal_graphql_files() {
    cat > "$DIR/tools/gq.py" << 'EOF_PY'
"""gq.py: the GraphQL helper of dev-demo's drupal/drupal-graphql (standard library only).

GraphQL Compose generates the schema from the site's content types, so the sample queries are built from
that schema rather than written by hand: a field this site's version names differently is left out and
reported, never sent.

    gq.py introspect URL OUT.json          the schema, as JSON (introspection)
    gq.py check SCHEMA.json                does the schema have recipes? (exit 1 if not)
    gq.py queries SCHEMA.json DIR          the four sample queries -> DIR/*.graphql
    gq.py run URL FILE [VARS.json]         one query; prints the result and the time it took
    gq.py first-path URL FILE              the path of the first recipe the query returns
    gq.py compare DIR_A URL_A DIR_B URL_B  the sample queries against two sites, side by side
    gq.py federate IN.graphql OUT.graphql  Drupal's SDL + Federation 2 @link and @key on NodeRecipe
    gq.py seed URL SCHEMA.json DATA.json   the kitchen subgraph's data for this site's recipe ids
    gq.py ops SCHEMA.json DIR              MCP operations over the federated router's schema -> DIR
"""
import hashlib
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

INTROSPECTION = """
query IntrospectionQuery {
  __schema {
    queryType { name } mutationType { name }
    types { kind name
      fields(includeDeprecated: true) { name args { name type { ...T } } type { ...T } }
      inputFields { name type { ...T } }
      enumValues(includeDeprecated: true) { name }
      possibleTypes { name }
      interfaces { name }
    }
  }
}
fragment T on __Type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } }
"""

RECIPE_FIELDS = ["id", "title", "path", "created", "cookingTime", "preparationTime", "difficulty", "numberOfServings"]
ARTICLE_FIELDS = ["id", "title", "path", "created"]
KITCHEN_FIELDS = ["timesCooked", "rating", "onShoppingList"]
MISSING = []


def post(url, query, variables=None, timeout=60):
    body = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = urllib.request.Request(url, body, {"Content-Type": "application/json", "Accept": "application/json"})
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            out = json.load(r)
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            out = json.loads(raw)
        except ValueError:
            out = {"errors": [{"message": f"HTTP {e.code} from {url}: {' '.join(raw.split())[:200]}"}]}
    except (urllib.error.URLError, OSError) as e:
        sys.exit(f"{url} did not answer: {getattr(e, 'reason', e)}")
    except ValueError:
        sys.exit(f"{url} did not answer with JSON (is that the GraphQL endpoint?)")
    return out, (time.perf_counter() - t0) * 1000


class Schema:
    def __init__(self, path):
        s = json.loads(pathlib.Path(path).read_text())
        s = s.get("data", s).get("__schema", s)
        self.types = {t["name"]: t for t in s["types"]}
        self.query = self.types[s["queryType"]["name"]]
        self.mutation = self.types.get((s.get("mutationType") or {}).get("name") or "")

    @staticmethod
    def named(ref):
        while ref.get("ofType"):
            ref = ref["ofType"]
        return ref

    def field(self, type_name_or_type, name):
        t = self.types.get(type_name_or_type) if isinstance(type_name_or_type, str) else type_name_or_type
        return next((f for f in (t or {}).get("fields") or [] if f["name"] == name), None)

    def leaf(self, ref):
        return self.named(ref)["kind"] in ("SCALAR", "ENUM")

    def sel(self, type_name, wanted, depth=0):
        """A selection of the wanted fields that exist; objects get one scalar sub-field."""
        out = []
        for name in wanted:
            f = self.field(type_name, name)
            if not f:
                MISSING.append(f"{type_name}.{name}")
                continue
            if any(a["type"]["kind"] == "NON_NULL" for a in f.get("args") or []):
                continue
            n = self.named(f["type"])
            if n["kind"] in ("SCALAR", "ENUM"):
                out.append(name)
            elif n["kind"] in ("OBJECT", "INTERFACE") and depth == 0:
                sub = next((s for s in ("time", "value", "processed", "name", "title", "url", "alias")
                            if self.field(n["name"], s) and self.leaf(self.field(n["name"], s)["type"])), None)
                if sub:
                    out.append(f"{name} {{ {sub} }}")
        return " ".join(out)

    def list_field(self, root_field, node_type, fields, first=5, extra=""):
        """root_field(first: N[, sortKey: CREATED_AT, reverse: true]) { nodes { ... } } (or edges/node)."""
        f = self.field(self.query, root_field)
        if not f:
            MISSING.append(f"Query.{root_field}")
            return None
        args = {a["name"]: a for a in f.get("args") or []}
        a = [f"first: {first}"] if "first" in args else []
        if "sortKey" in args:
            sk = self.types.get(self.named(args["sortKey"]["type"])["name"], {})
            if any(v["name"] == "CREATED_AT" for v in sk.get("enumValues") or []):
                a.append("sortKey: CREATED_AT")
                if "reverse" in args:
                    a.append("reverse: true")
        conn = self.named(f["type"])["name"]
        inner = (self.sel(node_type, fields) + " " + extra).strip()
        if self.field(conn, "nodes"):
            body = f"nodes {{ {inner} }}"
        elif self.field(conn, "edges"):
            body = f"edges {{ node {{ {inner} }} }}"
        else:
            body = inner
        return f"{root_field}{'(' + ', '.join(a) + ')' if a else ''} {{ {body} }}"

    def tags(self, type_name):
        f = self.field(type_name, "tags")
        if not f:
            MISSING.append(f"{type_name}.tags")
            return ""
        n = self.types.get(self.named(f["type"])["name"], {})
        if n.get("kind") == "UNION":
            members = [p["name"] for p in n.get("possibleTypes") or []]
            m = "TermTags" if "TermTags" in members else next((x for x in members if self.field(x, "name")), None)
            return f"tags {{ ... on {m} {{ name }} }}" if m else ""
        return "tags { name }" if self.field(n.get("name"), "name") else ""

    def route(self, inner_fields):
        f = self.field(self.query, "route")
        if not f or not any(a["name"] == "path" for a in f.get("args") or []):
            MISSING.append("Query.route(path)")
            return None
        target = self.types.get(self.named(f["type"])["name"], {})
        candidates = [p["name"] for p in target.get("possibleTypes") or []] or [target.get("name")]
        internal = next((c for c in candidates if self.field(c, "entity")), None)
        if not internal:
            MISSING.append("RouteInternal.entity")
            return None
        ent = f"entity {{ __typename ... on NodeRecipe {{ {self.sel('NodeRecipe', inner_fields)} }} }}"
        body = f"__typename ... on {internal} {{ {ent} }}" if internal != target.get("name") else f"__typename {ent}"
        return f"route(path: $path) {{ {body} }}"

    def menu(self):
        f = self.field(self.query, "menu")
        if not f:
            MISSING.append("Query.menu")
            return None
        arg = next((a for a in f.get("args") or [] if a["name"] == "name"), None)
        if not arg:
            return None
        enum = self.types.get(self.named(arg["type"])["name"], {})
        val = "MAIN" if any(v["name"] == "MAIN" for v in enum.get("enumValues") or []) else '"main"'
        mt = self.named(f["type"])["name"]
        items = self.field(mt, "items")
        sub = self.sel(self.named(items["type"])["name"], ["title", "url"]) if items else ""
        return f"menu(name: {val}) {{ {self.sel(mt, ['name'])} {('items { ' + sub + ' }') if sub else ''} }}"


def write(path, text):
    path.write_text(text)
    print(f"  wrote {path}")


def cmd_queries(schema_path, outdir, kitchen=False):
    s = Schema(schema_path)
    d = pathlib.Path(outdir)
    d.mkdir(parents=True, exist_ok=True)
    extra = KITCHEN_FIELDS if kitchen else []
    q = s.list_field("nodeRecipes", "NodeRecipe", RECIPE_FIELDS + extra)
    if q:
        write(d / "1-NewestRecipes.graphql", f"# The newest recipes, with cooking time and difficulty.\nquery NewestRecipes {{\n  {q}\n}}\n")
    r = s.route(["id", "title", "cookingTime", "difficulty"] + extra)
    if r:
        write(d / "2-RecipeByPath.graphql", f"# One recipe by its URL path, through route().\nquery RecipeByPath($path: String!) {{\n  {r}\n}}\n")
    a = s.list_field("nodeArticles", "NodeArticle", ARTICLE_FIELDS, extra=s.tags("NodeArticle"))
    if a:
        write(d / "3-ArticlesWithTags.graphql", f"# Articles with their tags.\nquery ArticlesWithTags {{\n  {a}\n}}\n")
    m = s.menu()
    if m:
        write(d / "4-MainMenu.graphql", f"# The main menu.\nquery MainMenu {{\n  {m}\n}}\n")
    if MISSING:
        print("  not in this schema (left out): " + ", ".join(sorted(set(MISSING))))


def cmd_check(schema_path):
    s = Schema(schema_path)
    if "NodeRecipe" in s.types and s.field(s.query, "nodeRecipes"):
        print(f"NodeRecipe: {', '.join(f['name'] for f in s.types['NodeRecipe']['fields'])}")
        return 0
    print("This schema has no recipes (no NodeRecipe type or nodeRecipes query).")
    return 1


def first_path(url, file):
    out, _ = post(url, pathlib.Path(file).read_text())
    found = []

    def walk(x):
        if isinstance(x, dict):
            if isinstance(x.get("path"), str) and x["path"].startswith("/"):
                found.append(x["path"])
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    walk(out.get("data"))
    return found[0] if found else ""


def run(url, file, variables=None, quiet=False):
    text = pathlib.Path(file).read_text()
    out, ms = post(url, text, variables)
    if not quiet:
        print(json.dumps(out, indent=2, ensure_ascii=False)[:4000])
        print(f"({ms:.0f} ms)")
    return out, ms


def shape(x):
    if isinstance(x, dict):
        return {k: shape(v) for k, v in sorted(x.items())}
    if isinstance(x, list):
        return [shape(x[0])] if x else []
    return type(x).__name__


def ids(x, acc):
    if isinstance(x, dict):
        if "id" in x:
            acc.append(str(x["id"]))
        for v in x.values():
            ids(v, acc)
    elif isinstance(x, list):
        for v in x:
            ids(v, acc)
    return acc


def cmd_compare(dir_a, url_a, dir_b, url_b):
    rows = []
    for fa in sorted(pathlib.Path(dir_a).glob("*.graphql")):
        fb = pathlib.Path(dir_b) / fa.name
        if not fb.exists():
            rows.append((fa.stem, "-", "-", "only in local"))
            continue
        res = []
        for d, url, f in ((dir_a, url_a, fa), (dir_b, url_b, fb)):
            v = None
            if "$path" in f.read_text():
                p = first_path(url, pathlib.Path(d) / "1-NewestRecipes.graphql")
                v = {"path": p}
            times, out = [], None
            for _ in range(3):
                out, ms = post(url, f.read_text(), v)
                times.append(ms)
            res.append((out, sorted(times)[1]))
        (oa, ta), (ob, tb) = res
        same = "same shape" if shape(oa.get("data")) == shape(ob.get("data")) else "DIFFERENT shape"
        ia, ib = ids(oa.get("data"), []), ids(ob.get("data"), [])
        note = same + ("; ids differ" if ia and ib and ia[:1] != ib[:1] else "; same ids" if ia and ia == ib else "")
        if oa.get("errors") or ob.get("errors"):
            note += "; errors: " + "; ".join(e.get("message", "")[:60] for e in (oa.get("errors") or []) + (ob.get("errors") or []))
        rows.append((fa.stem, f"{ta:.0f} ms", f"{tb:.0f} ms", note))
    w = max([len(r[0]) for r in rows] + [5])
    print(f"{'query':<{w}}  {'local':>9}  {'ddev':>9}  result")
    for r in rows:
        print(f"{r[0]:<{w}}  {r[1]:>9}  {r[2]:>9}  {r[3]}")
    print("(median of 3 requests each; local = PHP's built-in server + SQLite, ddev = nginx + PHP-FPM + MariaDB)")


def cmd_federate(src, dst):
    sdl = pathlib.Path(src).read_text()
    m = re.search(r"^type NodeRecipe\b[^{]*\{", sdl, re.M)
    if not m:
        sys.exit("No 'type NodeRecipe' in Drupal's schema: GraphQL Compose has not exposed recipes (see the serve item).")
    body = sdl[m.end():sdl.index("}", m.end())]
    if not re.search(r"^\s*id: ID!", body, re.M):
        sys.exit("NodeRecipe has no 'id: ID!' field to federate on.")
    head = m.group(0)[:-1].rstrip()
    sdl = sdl[:m.start()] + head + ' @key(fields: "id", resolvable: false) {' + sdl[m.end():]
    link = 'extend schema @link(url: "https://specs.apollo.dev/federation/v2.7", import: ["@key"])\n\n'
    pathlib.Path(dst).write_text("# Drupal's schema as GraphQL Compose generates it (rover graph introspect), plus the two lines\n"
                                 "# dev-demo adds: the Federation 2 @link, and @key on NodeRecipe. resolvable: false = the router\n"
                                 "# never asks Drupal for a recipe by key, so Drupal needs no _entities resolver.\n" + link + sdl)
    print(f"  wrote {dst}: NodeRecipe @key(fields: \"id\", resolvable: false)")


def cmd_seed(url, schema_path, data_path):
    s = Schema(schema_path)
    # Umami has about ten recipes; a site may cap page sizes, so a refused size is retried smaller.
    for first in (100, 50, 20):
        q = s.list_field("nodeRecipes", "NodeRecipe", ["id", "title"], first=first)
        if not q:
            sys.exit("No nodeRecipes query in this schema.")
        out, _ = post(url, "{ " + q + " }")
        if out.get("data"):
            break
    if not out.get("data"):
        sys.exit("The site refused the recipe list: " + "; ".join(e.get("message", "") for e in out.get("errors") or [])[:300])
    found = []

    def walk(x):
        if isinstance(x, dict):
            if "id" in x and "title" in x:
                found.append((x["id"], x["title"]))
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    walk(out.get("data"))
    p = pathlib.Path(data_path)
    data = json.loads(p.read_text()) if p.exists() else {}
    added = 0
    for rid, title in found:
        if rid in data:
            continue
        h = int(hashlib.sha1(title.encode()).hexdigest(), 16)
        cooked = h % 4
        data[rid] = {"title": title, "timesCooked": cooked, "rating": (3 + h % 3) if cooked else None, "onShoppingList": h % 5 == 0}
        added += 1
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"  kitchen data {p.name}: {len(data)} recipes ({added} new)")


def cmd_ops(schema_path, outdir):
    s = Schema(schema_path)
    d = pathlib.Path(outdir)
    d.mkdir(parents=True, exist_ok=True)
    for old in d.glob("*.graphql"):
        old.unlink()
    q = s.list_field("nodeRecipes", "NodeRecipe", RECIPE_FIELDS + KITCHEN_FIELDS, first=20)
    if q:
        write(d / "ListRecipes.graphql", "# Umami's recipes, newest first: title, path, cooking time and difficulty from Drupal; how often\n"
              "# you cooked each, your rating and the shopping list from the kitchen subgraph.\n"
              f"query ListRecipes {{\n  {q}\n}}\n")
    r = s.route(["id", "title", "cookingTime", "preparationTime", "difficulty", "numberOfServings", "ingredients"] + KITCHEN_FIELDS)
    if r:
        write(d / "RecipeByPath.graphql", "# One recipe by its URL path (from ListRecipes, e.g. /en/recipes/...), with the kitchen's data.\n"
              f"query RecipeByPath($path: String!) {{\n  {r}\n}}\n")
    if s.mutation and s.field(s.mutation, "cooked"):
        write(d / "LogCook.graphql", "# Log that you cooked a recipe (its id from ListRecipes), with an optional rating 1 to 5.\n"
              "mutation LogCook($recipeId: ID!, $rating: Int) {\n  cooked(recipeId: $recipeId, rating: $rating) { recipeId title timesCooked rating }\n}\n")
    if MISSING:
        print("  not in this schema (left out): " + ", ".join(sorted(set(MISSING))))


def main(a):
    if len(a) < 2:
        sys.exit(__doc__)
    c = a[1]
    if c == "introspect":
        out, _ = post(a[2], INTROSPECTION)
        if not (out.get("data") or {}).get("__schema"):
            sys.exit("Introspection failed: " + json.dumps(out.get("errors") or out)[:400])
        pathlib.Path(a[3]).write_text(json.dumps(out))
        print(f"  schema: {len(out['data']['__schema']['types'])} types from {a[2]}")
    elif c == "check":
        return cmd_check(a[2])
    elif c == "queries":
        cmd_queries(a[2], a[3])
    elif c == "run":
        run(a[2], a[3], json.loads(pathlib.Path(a[4]).read_text()) if len(a) > 4 and a[4].endswith(".json")
            else ({"path": a[4]} if len(a) > 4 else None))
    elif c == "first-path":
        print(first_path(a[2], a[3]))
    elif c == "compare":
        cmd_compare(a[2], a[3], a[4], a[5])
    elif c == "federate":
        cmd_federate(a[2], a[3])
    elif c == "seed":
        cmd_seed(a[2], a[3], a[4])
    elif c == "ops":
        cmd_ops(a[2], a[3])
    else:
        sys.exit(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
EOF_PY
    gen_file "$DIR/configure.php" << 'EOF_PHP'
<?php

/**
 * @file
 * dev-demo drupal/drupal-graphql: exposes Umami through GraphQL Compose and lets visitors query it.
 *
 * Run by run-drupal-graphql.sh in each site ('drush php:script'). It turns on the recipe and article
 * content types (and what they reference: tags, recipe categories, image media, the main menu) with their
 * fields, makes sure a GraphQL server uses the GraphQL Compose schema, and grants anonymous and logged-in
 * visitors the right to run queries on that server only. Only keys the installed modules declare in their
 * config schema are written: anything else is reported with the admin page to use instead. The last lines
 * printed are SERVER=<id> and ENDPOINT=<path>, which the launcher reads.
 */

use Drupal\Core\Config\Schema\SchemaCheckTrait;

$typed = \Drupal::service('config.typed');
$etm = \Drupal::entityTypeManager();
$efm = \Drupal::service('entity_field.manager');
$problems = [];

/**
 * Wraps SchemaCheckTrait so the result can be read outside a class.
 */
final class DevDemoSchemaCheck {
  use SchemaCheckTrait;

  /**
   * TRUE, or a list of 'key' => 'error' for values the config schema does not declare.
   */
  public function check($typed, string $name, array $data) {
    return $this->checkConfigSchema($typed, $name, $data);
  }

}

// 1. GraphQL Compose: which entity types and bundles, and their fields.
$want = [
  'node' => ['recipe', 'article', 'page'],
  'taxonomy_term' => ['tags', 'recipe_category'],
  'media' => ['image'],
  'menu' => ['main'],
];
// Base fields worth having beside the configurable ones (title, dates, path alias, term names).
$base = ['title', 'created', 'changed', 'path', 'status', 'langcode', 'name', 'description', 'thumbnail'];

if (!\Drupal::moduleHandler()->moduleExists('graphql_compose')) {
  echo "graphql_compose is not enabled.\n";
  exit(1);
}
$settings = \Drupal::configFactory()->getEditable('graphql_compose.settings');
$data = $settings->getRawData();
foreach ($want as $type => $bundles) {
  if (!$etm->hasDefinition($type)) {
    continue;
  }
  foreach ($bundles as $bundle) {
    $data['entity_config'][$type][$bundle] = [
      'enabled' => TRUE,
      'query_load_enabled' => TRUE,
      'edges_enabled' => TRUE,
      'routes_enabled' => TRUE,
    ] + ($data['entity_config'][$type][$bundle] ?? []);
    if ($type === 'menu') {
      continue;
    }
    foreach ($efm->getFieldDefinitions($type, $bundle) as $name => $def) {
      $configurable = $def instanceof \Drupal\field\FieldConfigInterface;
      if ($configurable || in_array($name, $base, TRUE)) {
        $data['field_config'][$type][$bundle][$name]['enabled'] = TRUE;
      }
    }
  }
}
$check = (new DevDemoSchemaCheck())->check($typed, 'graphql_compose.settings', $data);
if ($check !== TRUE && $check !== FALSE) {
  foreach (array_slice((array) $check, 0, 8, TRUE) as $key => $error) {
    $problems[] = "graphql_compose.settings: $key: $error";
  }
  echo "GraphQL Compose's settings are not shaped the way this script expects (" . count((array) $check) . " keys).\n";
}
else {
  $settings->setData($data)->save();
  echo "GraphQL Compose: recipe, article, page, tags, recipe category, image media and the main menu, with their fields.\n";
}

// 2. A GraphQL server on the GraphQL Compose schema.
$storage = $etm->getStorage('graphql_server');
$server = NULL;
foreach ($storage->loadMultiple() as $candidate) {
  if ($candidate->get('schema') === 'graphql_compose') {
    $server = $candidate;
    break;
  }
}
if (!$server) {
  $server = $storage->create([
    'id' => 'graphql_compose_server',
    'label' => 'GraphQL Compose',
    'endpoint' => '/graphql',
    'schema' => 'graphql_compose',
    'schema_configuration' => ['graphql_compose' => []],
    'caching' => FALSE,
    'batching' => TRUE,
    'disable_introspection' => FALSE,
  ]);
  $server->save();
  echo "Created the GraphQL server 'graphql_compose_server' on /graphql.\n";
}
else {
  echo "GraphQL server '" . $server->id() . "' on " . $server->get('endpoint') . " uses the GraphQL Compose schema.\n";
}
$extensions = [];
if (\Drupal::hasService('plugin.manager.graphql.schema_extension')) {
  foreach (\Drupal::service('plugin.manager.graphql.schema_extension')->getDefinitions() as $ext_id => $definition) {
    if (($definition['schema'] ?? NULL) === 'graphql_compose') {
      $extensions[$ext_id] = $ext_id;
    }
  }
}
if ($extensions) {
  $configuration = $server->get('schema_configuration') ?: [];
  $before = $configuration['graphql_compose']['extensions'] ?? [];
  $configuration['graphql_compose']['extensions'] = array_filter($before) + $extensions;
  if ($configuration['graphql_compose']['extensions'] != $before) {
    $server->set('schema_configuration', $configuration)->save();
    echo "Schema extensions on: " . implode(', ', array_keys($extensions)) . "\n";
  }
}
if ($server->get('disable_introspection')) {
  // rover graph introspect (the federate item) needs introspection.
  $server->set('disable_introspection', FALSE)->save();
  echo "Turned introspection on for it.\n";
}

// 3. Visitors may run queries on this server (only this one).
$id = $server->id();
$all = \Drupal::service('user.permissions')->getPermissions();
$grant = array_values(array_filter(["execute $id arbitrary graphql requests"], fn ($p) => isset($all[$p])));
if ($grant) {
  foreach (['anonymous', 'authenticated'] as $role) {
    user_role_grant_permissions($role, $grant);
  }
  echo "Anonymous and logged-in visitors may: " . implode(', ', $grant) . "\n";
}
else {
  $problems[] = "No 'execute $id arbitrary graphql requests' permission in this version of the graphql module.";
}

if ($problems) {
  echo "\nTo finish in the admin UI (log in as admin / admin):\n";
  foreach ($problems as $p) {
    echo "  - $p\n";
  }
  echo "  GraphQL Compose schema: Configuration > Web services > GraphQL Compose: tick Recipe and Article, their fields,\n";
  echo "    Tags, Recipe category, Image media and the Main navigation menu.\n";
  echo "  GraphQL servers: Configuration > Web services > GraphQL (/admin/config/graphql).\n";
  echo "  Permissions: People > Permissions, 'execute ... arbitrary graphql requests' for Anonymous user.\n";
}
echo "SERVER=$id\n";
echo "ENDPOINT=" . $server->get('endpoint') . "\n";
EOF_PHP
    gen_file "$DIR/kitchen/schema.graphql" << 'EOF_GQL'
# The kitchen subgraph (dev-demo drupal/drupal-graphql): what you do with Umami's recipes, kept outside Drupal.
# NodeRecipe is Drupal's type; this subgraph adds three fields to it, keyed on Drupal's id. Drupal declares
# the same key with resolvable: false, so every recipe still comes from Drupal and the router asks kitchen
# only for these fields. Root fields return CookResult and KitchenStats, never NodeRecipe: kitchen cannot
# fetch a recipe's Drupal fields, so a NodeRecipe from here could not be completed.
extend schema @link(url: "https://specs.apollo.dev/federation/v2.7", import: ["@key"])

type NodeRecipe @key(fields: "id") {
  id: ID!
  "How many times you cooked it (the cooked mutation counts)."
  timesCooked: Int!
  "Your latest rating, 1 to 5, or null."
  rating: Int
  "Whether its ingredients are on your shopping list."
  onShoppingList: Boolean!
}

type CookResult {
  recipeId: ID!
  title: String
  timesCooked: Int!
  rating: Int
}

type KitchenStats {
  recipesKnown: Int!
  recipesCooked: Int!
  totalCooks: Int!
}

type Query {
  kitchenStats: KitchenStats!
}

type Mutation {
  "Log that you cooked a recipe (its id from Drupal), with an optional rating 1 to 5."
  cooked(recipeId: ID!, rating: Int): CookResult!
}
EOF_GQL
    gen_file "$DIR/kitchen/index.mjs" << 'EOF_JS'
// The kitchen subgraph (dev-demo drupal/drupal-graphql): Apollo Server with @apollo/subgraph.
// PORT (4002 local, 4012 ddev) and DATA (data-local.json / data-ddev.json: one per site, since each Umami
// install has its own recipe ids) come from the launcher, which seeds DATA from the site's recipes.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { ApolloServer } from '@apollo/server';
import { startStandaloneServer } from '@apollo/server/standalone';
import { buildSubgraphSchema } from '@apollo/subgraph';
import { GraphQLError, parse } from 'graphql';

const here = new URL('.', import.meta.url).pathname;
const DATA = process.env.DATA || here + 'data-local.json';
const load = () => (existsSync(DATA) ? JSON.parse(readFileSync(DATA, 'utf8')) : {});
const save = (d) => writeFileSync(DATA, JSON.stringify(d, null, 2) + '\n');
const view = (id, r) => ({ id, timesCooked: r?.timesCooked ?? 0, rating: r?.rating ?? null, onShoppingList: r?.onShoppingList ?? false });

const resolvers = {
  Query: {
    kitchenStats: () => {
      const all = Object.values(load());
      return { recipesKnown: all.length, recipesCooked: all.filter((r) => r.timesCooked > 0).length,
               totalCooks: all.reduce((s, r) => s + (r.timesCooked || 0), 0) };
    },
  },
  Mutation: {
    cooked: (_, { recipeId, rating }) => {
      if (rating != null && (rating < 1 || rating > 5)) throw new GraphQLError('rating must be 1 to 5');
      const d = load();
      const r = d[recipeId] || { title: null, timesCooked: 0, rating: null, onShoppingList: false };
      r.timesCooked += 1;
      if (rating != null) r.rating = rating;
      r.onShoppingList = false;
      d[recipeId] = r;
      save(d);
      return { recipeId, title: r.title, timesCooked: r.timesCooked, rating: r.rating };
    },
  },
  NodeRecipe: {
    __resolveReference: (ref) => view(ref.id, load()[ref.id]),
  },
};

const server = new ApolloServer({
  schema: buildSubgraphSchema([{ typeDefs: parse(readFileSync(here + 'schema.graphql', 'utf8')), resolvers }]),
});
const port = Number(process.env.PORT || 4002);
const { url } = await startStandaloneServer(server, { listen: { host: '127.0.0.1', port } });
console.log(`kitchen subgraph ready at ${url} (data: ${DATA})`);
EOF_JS
    gen_file "$DIR/kitchen/package.json" << 'EOF_JSON'
{
  "name": "devdemo-kitchen-subgraph",
  "private": true,
  "type": "module",
  "description": "The kitchen subgraph of dev-demo's drupal/drupal-graphql",
  "dependencies": {
    "@apollo/server": "^5",
    "@apollo/subgraph": "^2",
    "graphql": "^16"
  }
}
EOF_JSON
}

demo_drupal_graphql_run() {
    write_run << 'EOF'
demo_need php "the base install"
demo_need composer install-web
demo_need npm install-node
# Local only, except the connectors item: an APOLLO_KEY in the environment would make every router report to
# GraphOS (dev-init's notes). The connectors item passes the key from secrets.env to its own rover dev.
unset APOLLO_KEY APOLLO_GRAPH_REF
export APOLLO_TELEMETRY_DISABLED=true APOLLO_ELV2_LICENSE=accept COMPOSER_NO_INTERACTION=1
GQ=(python3 "$DEMO_DIR/tools/gq.py")
ITEM_GIVEN=${1:-}; RT_ARG=${2:-}
DDEV_NAME=devdemo-drupal-graphql
DDEV_HOST=$DDEV_NAME.ddev.site
listening() { (exec 3<> "/dev/tcp/127.0.0.1/$1") 2> /dev/null; }
holder() { ss -ltnpH "sport = :$1" 2> /dev/null | grep -oE '"[^"]+",pid=[0-9]+' | head -n 1 | sed -E 's/"([^"]+)",pid=([0-9]+)/\1 (pid \2)/'; }
ours() { case "$(readlink -f "/proc/$1/cwd" 2> /dev/null)" in "$DEMO_DIR"|"$DEMO_DIR"/*) return 0 ;; esac; return 1; }
port_free() {
    listening "$1" || return 0
    local h; h=$(holder "$1")
    echo "Port $1 ($2) is in use by ${h:-another process}. '$0 stop $RT' stops this demo's own pieces;"
    echo "graphql/apollo-supergraph and the Jekyll demo also use 4000, 4002 and 8771."
    return 1
}
stop_ours() {
    local p pid pg n=0
    for p in "$@"; do
        for pid in $(ss -ltnpH "sport = :$p" 2> /dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u); do
            ours "$pid" || continue
            pg=$(ps -o pgid= -p "$pid" | tr -d ' ')
            kill -TERM -- "-$pg" 2> /dev/null || kill -TERM "$pid" 2> /dev/null
            n=$((n + 1))
        done
    done
    echo "Stopped $n of this demo's servers on ports $*."
}
up() {   # up PORT NAME SECONDS: wait for what demo_bg just started; stop waiting if it exits
    local pid=${DEMO_PIDS[-1]} i
    printf 'Waiting for %s on :%s ' "$2" "$1"
    for ((i = 0; i < $3; i++)); do
        listening "$1" && { echo " up"; return 0; }
        kill -0 "$pid" 2> /dev/null || { echo " it stopped:"; tail -n 8 "$DEMO_LOGS/$2.log"; return 1; }
        [ $((i % 5)) -eq 0 ] && printf '.'
        sleep 1
    done
    echo " not up after $3s:"; tail -n 8 "$DEMO_LOGS/$2.log"; return 1
}

# rt [all]: the site to work on: the launcher's second argument, else a question, else local.
rt() {
    RT=$RT_ARG; RT_ARG=""
    if [ -z "$RT" ]; then
        if [ -n "$ITEM_GIVEN" ]; then
            RT=local
        else
            local opts=("local: PHP's built-in server + SQLite, http://127.0.0.1:8889" "ddev: DDEV (nginx, PHP-FPM, MariaDB), http://$DDEV_HOST")
            [ "${1:-}" = all ] && opts+=("all: both")
            demo_menu "Which site?" "${opts[@]}" || return 1
            RT=${DEMO_CHOICE%%:*}
        fi
    fi
    case "$RT" in
        local) BASE=http://127.0.0.1:8889; RPORT=4000; HPORT=8088; KPORT=4002; MPORT=8771; CNAME=umami-graphql ;;
        ddev)  BASE=http://$DDEV_HOST$(ddev_http_port); RPORT=4010; HPORT=8098; KPORT=4012; MPORT=8772; CNAME=umami-graphql-ddev ;;
        all)   [ "${1:-}" = all ] || { echo "'all' only goes with stop."; return 1; }; return 0 ;;
        *)     echo "Pick local or ddev (got '$RT')."; return 1 ;;
    esac
    EP=$(cat "$RT/.devdemo-endpoint" 2> /dev/null || echo /graphql)
    GQL=$BASE$EP
    mkdir -p "work/$RT"
}
dr() {   # drush in the current site
    if [ "$RT" = local ]; then ( cd local && php -d memory_limit=512M vendor/bin/drush "$@" ); else ( cd ddev && ddev drush "$@" ); fi
}
installed() {
    [ -f "$RT/composer.json" ] || return 1
    # ddev drush needs the project running; a stopped one is started (quick when it already runs).
    if [ "$RT" = ddev ]; then ( cd ddev && ddev start ) > /dev/null 2>&1 || return 1; fi
    dr status --field=bootstrap 2> /dev/null | grep -q Successful
}
php_mm() { php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;'; }
# ddev_http_port: ":PORT" when DDEV's router does not serve http on 80 (router_http_port), else nothing.
ddev_http_port() {
    local v
    v=$(sed -n 's/^router_http_port:[[:space:]]*"\{0,1\}\([0-9]*\)"\{0,1\}.*/\1/p' "$HOME/.ddev/global_config.yaml" 2> /dev/null | head -n 1)
    [ -n "$v" ] && [ "$v" != 80 ] && printf ':%s' "$v"
    return 0
}

# install_site: Composer project, Drupal with Umami, the GraphQL modules, configure.php. Safe to repeat.
install_site() {
    if [ "$RT" = local ]; then
        if [ ! -f local/composer.json ]; then
            demo_step "composer create-project drupal/recommended-project local (a few minutes)"
            composer create-project drupal/recommended-project local --no-progress || { rm -rf local; return 1; }
        fi
        cmp() { ( cd local && composer "$@" ); }
    else
        docker_ok
        demo_need ddev "the base install"
        mkdir -p ddev
        if [ ! -d ddev/.ddev ]; then
            # The PHP version matches this machine's, as the Laravel and Symfony DDEV items do.
            ( cd ddev && ddev config --project-type=drupal11 --docroot=web --project-name="$DDEV_NAME" --php-version="$(php_mm)" > /dev/null ) || return 1
        fi
        demo_note "Memory before DDEV starts: $(free -h | awk '/^Mem:/ {print $7 " available of " $2}')"
        ( cd ddev && ddev start ) || return 1
        if [ ! -f ddev/composer.json ]; then
            demo_step "ddev composer create-project drupal/recommended-project (a few minutes)"
            ( cd ddev && ddev composer create-project drupal/recommended-project ) || return 1
        fi
        cmp() { ( cd ddev && ddev composer "$@" ); }
    fi
    if ! cmp show drupal/graphql_compose > /dev/null 2>&1; then
        demo_step "composer require drush/drush drupal/graphql:^5 drupal/graphql_compose:^2"
        cmp require -W drush/drush 'drupal/graphql:^5' 'drupal/graphql_compose:^2' \
            || { demo_note "graphql 5 did not resolve here; trying the 4.x line"; cmp require -W drush/drush 'drupal/graphql:^4' 'drupal/graphql_compose:^2'; } \
            || return 1
    fi
    if ! dr status --field=bootstrap 2> /dev/null | grep -q Successful; then
        demo_step "Installing Drupal with Umami (admin / admin)"
        if [ "$RT" = local ]; then
            dr -y site:install demo_umami --db-url=sqlite://sites/default/files/.ht.sqlite --account-name=admin --account-pass=admin \
                --site-name="Umami GraphQL (local)" || return 1
        else
            dr -y site:install demo_umami --account-name=admin --account-pass=admin --site-name="Umami GraphQL (DDEV)" || return 1
        fi
    fi
    demo_step "GraphQL modules"
    local m
    for m in graphql graphql_compose graphql_compose_routes graphql_compose_menus graphql_compose_edges graphql_compose_image_style; do
        if dr -y pm:install "$m" > /dev/null 2>&1; then echo "  $m"; else echo "  $m: not in this version (fine)"; fi
    done
    demo_step "configure.php: GraphQL Compose schema, server and permissions"
    local out
    if [ "$RT" = local ]; then
        out=$(dr php:script ../configure.php)
    else
        mkdir -p ddev/.ddev/devdemo && cp configure.php ddev/.ddev/devdemo/configure.php
        out=$(dr php:script /var/www/html/.ddev/devdemo/configure.php)
    fi
    printf '%s\n' "$out" | grep -vE '^(SERVER|ENDPOINT)='
    printf '%s\n' "$out" | sed -n 's/^ENDPOINT=//p' | tail -n 1 > "$RT/.devdemo-endpoint"
    [ -s "$RT/.devdemo-endpoint" ] || echo /graphql > "$RT/.devdemo-endpoint"
    printf '%s\n' "$out" | sed -n 's/^SERVER=//p' | tail -n 1 > "$RT/.devdemo-server"
    dr cr > /dev/null 2>&1
    EP=$(cat "$RT/.devdemo-endpoint"); GQL=$BASE$EP
}

# site_up: the site answers GraphQL (local: PHP's built-in server in the background unless it already runs).
site_up() {
    installed || { echo "The $RT site is not installed yet: '$0 serve $RT' installs it (a few minutes)."; return 1; }
    if [ "$RT" = local ]; then
        if ! listening 8889; then
            # PHP_CLI_SERVER_WORKERS: the built-in server takes several requests at once (the router and a browser).
            demo_bg drupal-local bash -c 'cd local/web && PHP_CLI_SERVER_WORKERS=4 exec php -d memory_limit=512M -S 127.0.0.1:8889 .ht.router.php'
            up 8889 drupal-local 60 || return 1
        fi
    else
        ( cd ddev && ddev start ) > /dev/null || return 1
        if ! getent hosts "$DDEV_HOST" > /dev/null; then
            echo "$DDEV_HOST does not resolve (offline? *.ddev.site lives in public DNS). Add it to /etc/hosts:"
            echo "  ddev hostname $DDEV_HOST 127.0.0.1     (asks for sudo once)"
            return 1
        fi
    fi
    local i
    for i in $(seq 1 30); do
        curl -fsS -o /dev/null -H 'Content-Type: application/json' --data '{"query":"{ __typename }"}' "$GQL" 2> /dev/null && return 0
        sleep 1
    done
    echo "$GQL does not answer GraphQL. 'drush cr' (or '$0 serve $RT') usually fixes a fresh install."
    return 1
}
ready() { site_up && schema_check; }
schema_check() {   # the site's schema has recipes, else the pages to fix it
    "${GQ[@]}" introspect "$GQL" "work/$RT/schema.json" > /dev/null || return 1
    "${GQ[@]}" check "work/$RT/schema.json" > /dev/null && return 0
    echo "The $RT site's GraphQL schema has no recipes: GraphQL Compose has not exposed them."
    echo "Log in as admin ('$0 serve $RT' prints a link), then Configuration > Web services > GraphQL Compose:"
    echo "tick Recipe and Article with their fields (and Tags, Image media, Main navigation), save, and try again."
    return 1
}
login_link() {
    if [ "$RT" = local ]; then dr uli --no-browser --uri="$BASE" 2> /dev/null | tail -n 1; else dr uli --no-browser 2> /dev/null | tail -n 1; fi
}
kitchen_up() {
    listening "$KPORT" && return 0
    if [ ! -d kitchen/node_modules ]; then
        demo_step "npm install in kitchen/ (Apollo Server, @apollo/subgraph; first run only)"
        ( cd kitchen && npm install --no-audit --no-fund --loglevel=error ) || return 1
    fi
    "${GQ[@]}" seed "$GQL" "work/$RT/schema.json" "kitchen/data-$RT.json" || return 1
    demo_bg "kitchen-$RT" env PORT="$KPORT" DATA="$DEMO_DIR/kitchen/data-$RT.json" node kitchen/index.mjs
    up "$KPORT" "kitchen-$RT" 60
}
# fed_prep: Drupal's schema with the federation lines, and the supergraph + router configuration.
fed_prep() {
    demo_need rover install-graphql
    ready || return 1
    demo_step "rover graph introspect $GQL"
    rover graph introspect "$GQL" > "work/$RT/drupal.introspected.graphql" || return 1
    "${GQ[@]}" federate "work/$RT/drupal.introspected.graphql" "work/$RT/drupal.graphql" || return 1
    cat > "work/$RT/supergraph.yaml" << YAML
# Drupal ($RT) + kitchen, for 'rover dev' and 'rover supergraph compose' (written by run-drupal-graphql.sh).
subgraphs:
  drupal:
    routing_url: $GQL
    schema:
      file: ./drupal.graphql
  kitchen:
    routing_url: http://127.0.0.1:$KPORT/
    schema:
      file: ../../kitchen/schema.graphql
YAML
    cat > "work/$RT/router.yaml" << YAML
# Apollo Router v2 for drupal/drupal-graphql ($RT), written by run-drupal-graphql.sh.
supergraph:
  listen: 127.0.0.1:$RPORT     # 0.0.0.0:$RPORT serves the LAN too (then add $RPORT to LAN_DEV_PORTS)
  introspection: true
# Its own health port, so the local and DDEV routers can run at the same time.
health_check:
  enabled: true
  listen: 127.0.0.1:$HPORT
sandbox:
  enabled: true
homepage:
  enabled: false
cors:
  policies:
    - origins:
        - https://studio.apollographql.com
      match_origins:
        - "^http://(localhost|127[.]0[.]0[.]1):[0-9]+\$"
plugins:
  experimental.expose_query_plan: true
YAML
    kitchen_up
}
router_bg() {   # a router on RPORT for the mcp item, unless one is there already
    listening "$RPORT" && return 0
    fed_prep || return 1
    ( cd "work/$RT" && rover supergraph compose --config supergraph.yaml > supergraph.graphql ) || return 1
    demo_bg "router-$RT" router --supergraph "work/$RT/supergraph.graphql" --config "work/$RT/router.yaml"
    up "$RPORT" "router-$RT" 60
}
secret() { bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$HOME/.config/dev-init/secrets.env" "$1" 2> /dev/null; }

while demo_menu "Drupal Umami over GraphQL: local (:8889) and DDEV ($DDEV_HOST)" \
        "serve: install a site (first run: a few minutes) and start it; local runs here until Ctrl-C, ddev keeps running" \
        "query: four sample queries with curl: newest recipes, a recipe by path, articles with tags, the main menu" \
        "compare: the same queries against both running sites: shapes, ids and response times" \
        "federate: the router (rover dev) over Drupal + the kitchen subgraph; one query gets both; Ctrl-C stops" \
        "mcp: apollo-mcp-server over that router, added to Claude Code (umami-graphql / umami-graphql-ddev); Ctrl-C stops" \
        "connectors: Apollo Connectors fetch articles over Drupal's JSON:API (needs APOLLO_KEY + APOLLO_GRAPH_REF); Ctrl-C stops" \
        "stop: stop a site and its router, kitchen and MCP server (local, ddev or all)" \
        "reset: delete a site; the next serve reinstalls it"; do
    case "$DEMO_CHOICE" in
        serve*)
            rt || continue
            if ! installed; then install_site || { echo "The install stopped (above); '$0 serve $RT' carries on from there."; continue; }; fi
            if [ "$RT" = local ]; then
                port_free 8889 "the local Drupal site" || continue
                demo_note "GraphQL endpoint: $GQL   (explorer: $BASE/admin/config/graphql/servers/manage/$(cat local/.devdemo-server 2> /dev/null || echo graphql_compose_server)/explorer)"
                demo_note "Admin login: $(login_link)"
                demo_note "Other items need the site running: use a second terminal. Ctrl-C stops it."
                demo_open_when_ready 8889 "$BASE"
                ( cd local/web && PHP_CLI_SERVER_WORKERS=4 exec php -d memory_limit=512M -S 127.0.0.1:8889 .ht.router.php )
            else
                site_up || continue
                demo_note "GraphQL endpoint: $GQL   (the router uses plain http; the browser gets https)"
                demo_note "Explorer: https://$DDEV_HOST/admin/config/graphql/servers/manage/$(cat ddev/.devdemo-server 2> /dev/null || echo graphql_compose_server)/explorer"
                demo_note "Admin login: $(login_link)"
                ( cd ddev && ddev launch )
                demo_note "The DDEV site keeps running: '$0 stop ddev' stops it (and its router, kitchen and MCP server)."
            fi ;;
        query*)
            rt || continue
            ready || continue
            "${GQ[@]}" queries "work/$RT/schema.json" "work/$RT/queries" > /dev/null
            for f in "work/$RT/queries"/*.graphql; do
                [ -e "$f" ] || continue
                demo_step "$(basename "$f" .graphql)"
                sed '/^#/d' "$f"
                vars='{}'
                if grep -q '\$path' "$f"; then
                    p=$("${GQ[@]}" first-path "$GQL" "work/$RT/queries/1-NewestRecipes.graphql")
                    vars=$(printf '{"path": "%s"}' "${p:-/}")
                    echo "  variables: $vars"
                fi
                body=$(python3 -c 'import json, sys; print(json.dumps({"query": open(sys.argv[1]).read(), "variables": json.loads(sys.argv[2])}))' "$f" "$vars")
                echo "\$ curl -s -H 'Content-Type: application/json' --data '{\"query\": ...}' $GQL"
                curl -s -w '\n%{time_total}\n' -H 'Content-Type: application/json' --data "$body" "$GQL" \
                    | python3 -c '
import json, sys
*b, t = sys.stdin.read().strip().split("\n") or ["0"]
try:
    print(json.dumps(json.loads("\n".join(b)), indent=2, ensure_ascii=False)[:3000])
except ValueError:
    print("(not JSON:)", " ".join("\n".join(b).split())[:300] or "(no answer)")
print(f"({float(t or 0) * 1000:.0f} ms)")'
            done
            demo_note "The queries are in $DEMO_DIR/work/$RT/queries, built from this site's schema; the explorer page ('serve') runs them too." ;;
        compare*)
            RT_ARG=local; rt || continue
            ready || continue
            "${GQ[@]}" queries "work/local/schema.json" "work/local/queries" > /dev/null
            RT_ARG=ddev; rt || continue
            ready || continue
            "${GQ[@]}" queries "work/ddev/schema.json" "work/ddev/queries" > /dev/null
            demo_step "The same four queries against both sites"
            "${GQ[@]}" compare work/local/queries "http://127.0.0.1:8889$(cat local/.devdemo-endpoint 2> /dev/null || echo /graphql)" \
                work/ddev/queries "$GQL" ;;
        federate*)
            rt || continue
            port_free "$RPORT" "the $RT router" || continue
            fed_prep || continue
            "${GQ[@]}" queries "work/$RT/schema.json" "work/$RT/queries" > /dev/null
            python3 - "work/$RT/queries/1-NewestRecipes.graphql" "work/$RT/federated.graphql" << 'PY'
import re, sys
q = open(sys.argv[1]).read()
lines = q.split("\n")
i = next(n for n, line in enumerate(lines) if "nodeRecipes" in line)
tail = " }" * (3 if "edges {" in lines[i] else 2)   # the recipe's selection closes before these
lines[i] = lines[i][: -len(tail)] + " timesCooked rating onShoppingList" + tail
q = "\n".join(lines).replace("query NewestRecipes", "query RecipesAndKitchen")
open(sys.argv[2], "w").write(q.replace("# The newest recipes, with cooking time and difficulty.",
    "# Drupal's recipes (title, cooking time) next to the kitchen's timesCooked, rating and shopping list."))
PY
            demo_note "When the router is up, this query runs once (Drupal's fields and the kitchen's in one response):"
            sed '/^#/d' "work/$RT/federated.graphql"
            ( demo_wait_port "$RPORT" 180 quiet && sleep 3 && echo && "${GQ[@]}" run "http://127.0.0.1:$RPORT/" "work/$RT/federated.graphql" | head -n 70 \
                && echo && demo_note "Sandbox: http://127.0.0.1:$RPORT (needs the internet). Ctrl-C stops the router and kitchen." ) &
            DEMO_PIDS+=($!)
            ( cd "work/$RT" && rover dev --supergraph-config supergraph.yaml --router-config router.yaml --supergraph-address 127.0.0.1 --supergraph-port "$RPORT" ) ;;
        mcp*)
            rt || continue
            demo_need apollo-mcp-server install-graphql
            port_free "$MPORT" "apollo-mcp-server" || continue
            router_bg || continue
            mkdir -p "work/$RT/mcp"
            "${GQ[@]}" introspect "http://127.0.0.1:$RPORT/" "work/$RT/mcp/router.json" > /dev/null || continue
            rover graph introspect "http://127.0.0.1:$RPORT/" > "work/$RT/mcp/api.graphql" || continue
            "${GQ[@]}" ops "work/$RT/mcp/router.json" "work/$RT/mcp/operations"
            cat > "work/$RT/mcp/mcp.yaml" << YAML
# apollo-mcp-server for drupal/drupal-graphql ($RT), written by run-drupal-graphql.sh. Run from this folder.
endpoint: http://127.0.0.1:$RPORT/
transport:
  type: streamable_http
  address: 127.0.0.1
  port: $MPORT
schema:
  source: local
  path: ./api.graphql
operations:
  source: local
  paths:
    - ./operations
overrides:
  mutation_mode: explicit      # LogCook is a mutation: the ones in operations/ are exposed, no others
introspection:
  introspect:
    enabled: true
YAML
            if command -v claude > /dev/null 2>&1; then
                claude mcp remove --scope user "$CNAME" > /dev/null 2>&1
                claude mcp add --scope user --transport http "$CNAME" "http://127.0.0.1:$MPORT/mcp" \
                    && demo_note "Added to Claude Code as '$CNAME' (user scope). While this runs, ask 'claude':"
                demo_note "  Which Umami recipes have I cooked most, and how long do they take? Then log that I cooked the quiche, 5 stars."
                demo_note "  With both sites' servers running: compare the recipes on umami-graphql and umami-graphql-ddev."
            else
                demo_note "Claude Code is not installed (install-node); any MCP client can use http://127.0.0.1:$MPORT/mcp"
            fi
            demo_note "Ctrl-C stops the MCP server, the router and kitchen. Out of Claude Code: claude mcp remove --scope user $CNAME"
            ( cd "work/$RT/mcp" && apollo-mcp-server mcp.yaml ) ;;
        connectors*)
            rt || continue
            K=$(secret APOLLO_KEY); G=$(secret APOLLO_GRAPH_REF)
            if [ -z "$K" ] || [ -z "$G" ]; then
                echo "Apollo Connectors in 'rover dev' need a GraphOS key and graph: set APOLLO_KEY and APOLLO_GRAPH_REF in"
                echo "$HOME/.config/dev-init/secrets.env (both stay unexported; see dev-init), then try again."
                continue
            fi
            port_free "$RPORT" "the $RT router" || continue
            fed_prep || continue
            dr -y pm:install jsonapi > /dev/null 2>&1 && echo "  Drupal core's JSON:API is on (read-only, published content)."
            curl -fsS -o /dev/null "$BASE/jsonapi/node/article" || { echo "$BASE/jsonapi does not answer."; continue; }
            cat > "work/$RT/articles.graphql" << GQL
# Apollo Connectors (written by run-drupal-graphql.sh): the router itself fetches Drupal's articles over
# JSON:API (REST) and maps them to GraphQL; no subgraph server runs for this part.
extend schema
  @link(url: "https://specs.apollo.dev/federation/v2.11", import: ["@key"])
  @link(url: "https://specs.apollo.dev/connect/v0.2", import: ["@source", "@connect"])
  @source(name: "drupal", http: { baseURL: "$BASE/jsonapi" })

"An article as Drupal core's JSON:API serves it."
type JsonApiArticle {
  id: ID!
  title: String
  created: String
  drupalPath: String
}

type Query {
  "The newest articles, over JSON:API."
  jsonapiArticles: [JsonApiArticle!]!
    @connect(
      source: "drupal"
      http: { GET: "/node/article?sort=-created" }
      selection: """
      \$.data {
        id
        title: attributes.title
        created: attributes.created
        drupalPath: attributes.path.alias
      }
      """
    )
}
GQL
            { cat "work/$RT/supergraph.yaml"; printf '  articles:\n    routing_url: http://localhost/\n    schema:\n      file: ./articles.graphql\n'; } > "work/$RT/supergraph-connectors.yaml"
            printf '# Articles over JSON:API (Connectors) beside recipes over GraphQL (Drupal + kitchen).\nquery Both {\n  jsonapiArticles { title created drupalPath }\n}\n' > "work/$RT/connectors.graphql"
            demo_note "This rover dev gets APOLLO_KEY and APOLLO_GRAPH_REF ($G): while it runs, the router reports to GraphOS."
            ( demo_wait_port "$RPORT" 180 quiet && sleep 3 && echo && "${GQ[@]}" run "http://127.0.0.1:$RPORT/" "work/$RT/connectors.graphql" | head -n 30 ) &
            DEMO_PIDS+=($!)
            ( cd "work/$RT" && APOLLO_KEY="$K" APOLLO_GRAPH_REF="$G" rover dev --supergraph-config supergraph-connectors.yaml \
                --router-config router.yaml --supergraph-address 127.0.0.1 --supergraph-port "$RPORT" ) ;;
        stop*)
            rt all || continue
            if [ "$RT" = local ] || [ "$RT" = all ]; then stop_ours 8889 4000 8088 4002 8771; fi
            if [ "$RT" = ddev ] || [ "$RT" = all ]; then
                stop_ours 4010 8098 4012 8772
                [ -d ddev/.ddev ] && ( cd ddev && ddev stop )
            fi ;;
        reset*)
            rt || continue
            read -rp "Delete the $RT site (its files$([ "$RT" = ddev ] && echo ', DDEV project and database'))? The next serve reinstalls it. [y/N] " a
            [ "${a,,}" = y ] || continue
            if [ "$RT" = local ]; then
                stop_ours 8889 4000 8088 4002 8771
                chmod -R u+w local 2> /dev/null; rm -rf local
            else
                stop_ours 4010 8098 4012 8772
                ddev delete -Oy "$DDEV_NAME"
                rm -rf ddev
            fi
            rm -rf "work/$RT" "kitchen/data-$RT.json"
            command -v claude > /dev/null 2>&1 && claude mcp remove --scope user "$CNAME" > /dev/null 2>&1
            demo_note "The $RT site is gone. '$0 serve $RT' installs it again." ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
}

# =================================================================
# DEMOS: test tools (v91, install-testing = install-playwright, install-selenium, install-bdd, install-robot;
# install-cypress is opt-in)
# =================================================================

# v91: testing/e2e-bakeoff: one small links app (Python, standard library, :8795) and one Gherkin file,
# features/links.feature, run by every BDD runner installed here, each with its own step definitions:
# cucumber-js (Playwright's library), playwright-bdd, behave (Playwright for Python), Behat 4 (Mink's
# BrowserKit driver: HTTP and HTML, no browser) and Reqnroll (Playwright for .NET). The same two scenarios
# without Gherkin: Playwright Test, Selenium (pytest), Robot Framework (Browser library) and Cypress. Each run
# records its time and the lines of code it took; 'report' puts them side by side. The browser runs use the
# system Chrome (channel 'chrome') except Playwright Test, which uses Playwright's own builds. Packages arrive
# on each runner's first run (npm, uv, Composer, NuGet), so downloading the demo is quick.
# The Laravel and Symfony links apps are not targets: their pages differ from this app's (labels, list
# markup), and the step definitions are written against this one. BASE_URL points every runner elsewhere
# for a page with the same markup.
# links_app_source: the links app that testing/e2e-bakeoff, vue/vue-links and gitlab/ci-local share (v91).
links_app_source() {
cat << 'EOF_PY'
#!/usr/bin/env python3
"""links: the app the bake-off's runners test, and vue-links' back end (dev-demo v91). Standard library only.
GET / lists the links and has an add form; POST /add validates (a title, an http(s) URL) and redirects back,
or answers 422 with the error; GET /links.json is the list as JSON; POST /links.json takes {"title", "url"}
as JSON and answers the new list (201) or {"error"} (422); POST /reset restores the two starting links.
python3 links_app.py [--host 127.0.0.1] [--port 8795] [--port-file FILE]"""
import argparse, html, json, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

SEED = [{"title": "Debian", "url": "https://www.debian.org/"},
        {"title": "Playwright", "url": "https://playwright.dev/"}]
LINKS = [dict(x) for x in SEED]
LOCK = threading.Lock()

def problem(t, u):
    if not t: return "Title is required."
    if not u.startswith(("http://", "https://")): return "URL must start with http:// or https://."
    return ""

def page(error="", title="", url=""):
    items = "\n".join(f'    <li data-testid="link"><a href="{html.escape(l["url"])}">{html.escape(l["title"])}</a></li>'
                      for l in LINKS)
    err = f'  <p class="error" role="alert" data-testid="error">{html.escape(error)}</p>\n' if error else ""
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Links</title>
<style>body {{ font: 16px system-ui; max-width: 40rem; margin: 2rem auto }} .error {{ color: #b00 }}
label {{ display: block; margin-top: .5rem }} input {{ width: 100% }} button {{ margin-top: .75rem }}</style></head>
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
        raw = self.rfile.read(n).decode()
        path = self.path.split("?")[0]
        with LOCK:
            if path == "/reset":
                LINKS[:] = [dict(x) for x in SEED]
                self.send(200, "reset", "text/plain")
            elif path == "/links.json":
                try:
                    d = json.loads(raw or "{}")
                except ValueError:
                    d = {}
                t, u = str(d.get("title", "")).strip(), str(d.get("url", "")).strip()
                err = problem(t, u)
                if err:
                    self.send(422, json.dumps({"error": err}), "application/json")
                else:
                    LINKS.append({"title": t, "url": u})
                    self.send(201, json.dumps(LINKS), "application/json")
            elif path == "/add":
                form = {k: v[0] for k, v in parse_qs(raw).items()}
                t, u = form.get("title", "").strip(), form.get("url", "").strip()
                err = problem(t, u)
                if err:
                    self.send(422, page(err, t, u))
                else:
                    LINKS.append({"title": t, "url": u})
                    self.send(303, "", extra={"Location": "/"})
            else: self.send(404, "not found", "text/plain")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8795)
    ap.add_argument("--port-file")
    a = ap.parse_args()
    srv = ThreadingHTTPServer((a.host, a.port), H)
    if a.port_file:
        with open(a.port_file, "w") as f: f.write(str(srv.server_address[1]))
    print(f"links app on http://{a.host}:{srv.server_address[1]}/", flush=True)
    srv.serve_forever()
EOF_PY
}

demo_testing() {
    begin testing e2e-bakeoff "E2E bake-off: one Gherkin feature through cucumber-js, playwright-bdd, behave, Behat and Reqnroll; the same test in Playwright, Selenium, Robot and Cypress" \
        "generated by dev-demo; https://playwright.dev https://cucumber.io https://behat.org https://reqnroll.net https://robotframework.org https://www.selenium.dev https://www.cypress.io" || return 0
    need python3 "the base install" || return 0
    need uv "the base install" || return 0
    FRESH=1
    demo_testing_files
    demo_testing_run
    done_demo
}

demo_testing_files() {
    gen_file "$DIR/README.md" << 'EOF_TXT'
# E2E bake-off

One app, one Gherkin file, every test runner the bundle sets up.

- `app/links_app.py`: the app under test (a list of links, an add form that refuses a non-web address,
  `/links.json`, `POST /reset`), on http://127.0.0.1:8795. The launcher starts it.
- `features/links.feature`: the shared Gherkin. Edit it here; each BDD run copies it into its runner.
- One folder per runner, each with its own step definitions or test:

| Runner | Kind | Drives |
|---|---|---|
| cucumber-js | Gherkin | Playwright's library on the system Chrome |
| playwright-bdd | Gherkin | Playwright Test (system Chrome) |
| behave | Gherkin | Playwright for Python (system Chrome) |
| behat | Gherkin | Mink's BrowserKit driver: HTTP and HTML, no browser, no JavaScript |
| reqnroll | Gherkin | Playwright for .NET (system Chrome) |
| playwright | code | Playwright Test on Playwright's Chromium (all engines: the `engines` item) |
| selenium | code | Selenium 4 + pytest; chromedriver from Selenium Manager |
| robot | keywords | Robot Framework's Browser library (Playwright) |
| cypress | code | Cypress (Electron; install-cypress) |

`../run-e2e-bakeoff.sh` runs one runner, all of them, and the report (time and lines of code per runner),
plus Playwright's UI mode, codegen, trace viewer and test agents, Playwright MCP in Claude Code, and the
Selenium Grid with a browser you can watch.
EOF_TXT
    links_app_source | gen_file "$DIR/app/links_app.py"
    gen_file "$DIR/features/links.feature" << 'EOF_FEATURE'
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
EOF_FEATURE

    # --- Playwright Test (code)
    gen_file "$DIR/playwright/package.json" << 'EOF_JSON'
{ "name": "bakeoff-playwright", "private": true, "scripts": { "test": "playwright test" } }
EOF_JSON
    gen_file "$DIR/playwright/playwright.config.ts" << 'EOF_TS'
import { defineConfig, devices } from '@playwright/test'

// One worker: these Chromebooks give Linux ~6.4 GB. Traces for every test (npx playwright show-trace).
export default defineConfig({
  testDir: 'tests',
  workers: 1,
  reporter: [['line'], ['html', { open: 'never' }]],
  use: { baseURL: process.env.BASE_URL ?? 'http://127.0.0.1:8795', trace: 'on' },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    { name: 'chrome', use: { ...devices['Desktop Chrome'], channel: 'chrome' } },
  ],
})
EOF_TS
    gen_file "$DIR/playwright/tests/links.spec.ts" << 'EOF_TS'
import { test, expect } from '@playwright/test'

test.beforeEach(async ({ page, request }) => {
  await request.post('/reset')
  await page.goto('/')
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
EOF_TS

    # --- playwright-bdd (Gherkin)
    gen_file "$DIR/playwright-bdd/package.json" << 'EOF_JSON'
{ "name": "bakeoff-playwright-bdd", "private": true }
EOF_JSON
    gen_file "$DIR/playwright-bdd/playwright.config.ts" << 'EOF_TS'
import { defineConfig, devices } from '@playwright/test'
import { defineBddConfig } from 'playwright-bdd'

// playwright-bdd: 'npx bddgen' turns the Gherkin into Playwright tests (.features-gen), then Playwright runs them.
const testDir = defineBddConfig({ features: 'features/*.feature', steps: 'steps/*.ts' })

export default defineConfig({
  testDir,
  workers: 1,
  reporter: [['line']],
  use: { ...devices['Desktop Chrome'], channel: 'chrome', baseURL: process.env.BASE_URL ?? 'http://127.0.0.1:8795' },
})
EOF_TS
    gen_file "$DIR/playwright-bdd/steps/links.steps.ts" << 'EOF_TS'
import { expect } from '@playwright/test'
import { createBdd } from 'playwright-bdd'

const { Given, When, Then } = createBdd()

Given('the links app has its two starting links', async ({ page, request }) => {
  await request.post('/reset')
  await page.goto('/')
})

When('I add the link {string} with the URL {string}', async ({ page }, title: string, url: string) => {
  await page.getByLabel('Title').fill(title)
  await page.getByLabel('URL').fill(url)
  await page.getByRole('button', { name: 'Add link' }).click()
})

Then('I see {int} links', async ({ page }, n: number) => {
  await expect(page.getByTestId('link')).toHaveCount(n)
})

Then('I see a link named {string}', async ({ page }, name: string) => {
  await expect(page.getByRole('link', { name })).toBeVisible()
})

Then('I see the error {string}', async ({ page }, text: string) => {
  await expect(page.getByRole('alert')).toHaveText(text)
})
EOF_TS

    # --- cucumber-js (Gherkin)
    gen_file "$DIR/cucumber-js/package.json" << 'EOF_JSON'
{ "name": "bakeoff-cucumber-js", "private": true, "type": "module" }
EOF_JSON
    gen_file "$DIR/cucumber-js/steps/links.steps.mjs" << 'EOF_JS'
// cucumber-js step definitions: Playwright's library (playwright-core) on the system Chrome. HEADED=1 shows it.
import { Before, After, BeforeAll, AfterAll, Given, When, Then, setDefaultTimeout } from '@cucumber/cucumber'
import { chromium } from 'playwright-core'
import assert from 'node:assert/strict'

setDefaultTimeout(30_000)
const BASE = process.env.BASE_URL ?? 'http://127.0.0.1:8795'
let browser, page
BeforeAll(async () => { browser = await chromium.launch({ channel: 'chrome', headless: process.env.HEADED !== '1' }) })
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
  // A page that updates without a reload (vue/vue-links) needs a moment: wait for the count, then check it.
  await page.waitForFunction((n) => document.querySelectorAll('[data-testid=link]').length === n, n, { timeout: 5000 }).catch(() => {})
  assert.equal(await page.getByTestId('link').count(), n)
})
Then('I see a link named {string}', async (name) => {
  assert.ok(await page.getByRole('link', { name }).isVisible())
})
Then('I see the error {string}', async (text) => {
  await page.getByRole('alert').waitFor({ timeout: 5000 })
  assert.equal((await page.getByRole('alert').textContent()).trim(), text)
})
EOF_JS

    # --- behave (Gherkin)
    gen_file "$DIR/behave/features/environment.py" << 'EOF_PY'
# behave hooks: one Chrome (Playwright for Python, channel "chrome": the system Chrome) for the run, a new
# page per scenario. HEADED=1 shows the window.
import os
from playwright.sync_api import sync_playwright


def before_all(context):
    context.pw = sync_playwright().start()
    context.browser = context.pw.chromium.launch(channel="chrome", headless=os.environ.get("HEADED") != "1")
    context.base = os.environ.get("BASE_URL", "http://127.0.0.1:8795")


def before_scenario(context, scenario):
    context.page = context.browser.new_page(base_url=context.base)


def after_scenario(context, scenario):
    context.page.close()


def after_all(context):
    context.browser.close()
    context.pw.stop()
EOF_PY
    gen_file "$DIR/behave/features/steps/links_steps.py" << 'EOF_PY'
# behave step definitions for features/links.feature (the bake-off's shared Gherkin file).
from behave import given, then, when
from playwright.sync_api import expect


@given("the links app has its two starting links")
def start(context):
    context.page.request.post("/reset")
    context.page.goto("/")


@when('I add the link "{title}" with the URL "{url}"')
def add_link(context, title, url):
    context.page.get_by_label("Title").fill(title)
    context.page.get_by_label("URL").fill(url)
    context.page.get_by_role("button", name="Add link").click()


@then("I see {n:d} links")
def count_links(context, n):
    expect(context.page.get_by_test_id("link")).to_have_count(n)


@then('I see a link named "{name}"')
def named_link(context, name):
    expect(context.page.get_by_role("link", name=name)).to_be_visible()


@then('I see the error "{text}"')
def error_text(context, text):
    expect(context.page.get_by_role("alert")).to_have_text(text)
EOF_PY

    # --- Behat 4 (Gherkin, PHP)
    gen_file "$DIR/behat/composer.json" << 'EOF_JSON'
{
    "name": "devdemo/bakeoff-behat",
    "description": "Behat 4 with Mink's BrowserKit driver, used directly (no MinkExtension).",
    "require-dev": {
        "behat/behat": "^4.0",
        "behat/mink": "^1.11",
        "behat/mink-browserkit-driver": "^2.2",
        "symfony/http-client": "^7.0 || ^8.0",
        "symfony/mime": "^7.0 || ^8.0"
    },
    "config": { "sort-packages": true }
}
EOF_JSON
    gen_file "$DIR/behat/features/bootstrap/FeatureContext.php" << 'EOF_PHP'
<?php
// Behat 4: steps are PHP 8 attributes, and the default suite (features/, FeatureContext) needs no config file
// (Behat 4 reads behat.php only; YAML is gone). Mink's BrowserKit driver speaks HTTP and fills in HTML forms:
// no browser, so no JavaScript. drupal/drupal-behat shows Behat with a real browser (Selenium).
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
        $this->base = rtrim((string) (getenv('BASE_URL') ?: 'http://127.0.0.1:8795'), '/');
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
EOF_PHP

    # --- Reqnroll (Gherkin, C#): the project comes from 'dotnet new reqnroll-project' on the first run; these
    # step definitions replace its sample.
    gen_file "$DIR/reqnroll-src/LinksSteps.cs" << 'EOF_CS'
using System;
using System.Threading.Tasks;
using Microsoft.Playwright;
using Reqnroll;

namespace LinksBakeoff.StepDefinitions;

// Reqnroll step definitions with Playwright for .NET on the system Chrome (Channel = "chrome"). HEADED=1 shows it.
[Binding]
public class LinksSteps
{
    static IPlaywright? _playwright;
    static IBrowser? _browser;
    static readonly string Base = Environment.GetEnvironmentVariable("BASE_URL") ?? "http://127.0.0.1:8795";
    IPage _page = null!;

    [BeforeTestRun]
    public static async Task StartBrowser()
    {
        _playwright = await Playwright.CreateAsync();
        _browser = await _playwright.Chromium.LaunchAsync(new() { Channel = "chrome", Headless = Environment.GetEnvironmentVariable("HEADED") != "1" });
    }

    [AfterTestRun]
    public static async Task StopBrowser()
    {
        if (_browser != null) await _browser.CloseAsync();
        _playwright?.Dispose();
    }

    [BeforeScenario]
    public async Task NewPage() => _page = await _browser!.NewPageAsync();

    [AfterScenario]
    public async Task ClosePage() => await _page.CloseAsync();

    [Given("the links app has its two starting links")]
    public async Task Start()
    {
        await _page.APIRequest.PostAsync(Base + "/reset");
        await _page.GotoAsync(Base + "/");
    }

    [When("I add the link {string} with the URL {string}")]
    public async Task Add(string title, string url)
    {
        await _page.GetByLabel("Title").FillAsync(title);
        await _page.GetByLabel("URL").FillAsync(url);
        await _page.GetByRole(AriaRole.Button, new() { Name = "Add link" }).ClickAsync();
    }

    [Then("I see {int} links")]
    public async Task Count(int n) => await Assertions.Expect(_page.GetByTestId("link")).ToHaveCountAsync(n);

    [Then("I see a link named {string}")]
    public async Task Named(string name) => await Assertions.Expect(_page.GetByRole(AriaRole.Link, new() { Name = name })).ToBeVisibleAsync();

    [Then("I see the error {string}")]
    public async Task Error(string text) => await Assertions.Expect(_page.GetByRole(AriaRole.Alert)).ToHaveTextAsync(text);
}
EOF_CS

    # --- Selenium + pytest (code)
    gen_file "$DIR/selenium/test_links.py" << 'EOF_PY'
"""Selenium 4 + pytest. Local: this machine's Chrome, chromedriver from Selenium Manager (~/.cache/selenium).
GRID_URL=http://127.0.0.1:4444: the shared Selenium Grid (devsvc), headed, so noVNC shows it; APP_URL is then
where this script resets the app, BASE_URL where the Grid's browser finds it. SLOWMO=1 pauses between steps."""
import os
import time
import urllib.request

import pytest
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8795")
APP = os.environ.get("APP_URL", BASE)
PAUSE = float(os.environ.get("SLOWMO", "0"))


@pytest.fixture
def driver():
    urllib.request.urlopen(urllib.request.Request(APP + "/reset", data=b"", method="POST")).read()
    o = webdriver.ChromeOptions()
    if os.environ.get("GRID_URL"):
        d = webdriver.Remote(os.environ["GRID_URL"], options=o)
    else:
        o.binary_location = "/usr/bin/google-chrome-stable"
        if os.environ.get("HEADED") != "1":
            o.add_argument("--headless=new")
        d = webdriver.Chrome(options=o)
    d.get(BASE + "/")
    yield d
    d.quit()


def links(d):
    return d.find_elements(By.CSS_SELECTOR, "[data-testid=link]")


def add(d, title, url):
    for field, value in (("title", title), ("url", url)):
        d.find_element(By.ID, field).send_keys(value)
        time.sleep(PAUSE)
    d.find_element(By.ID, "add").click()
    time.sleep(PAUSE)


def test_add_a_link(driver):
    add(driver, "Behat", "https://behat.org/")
    WebDriverWait(driver, 10).until(lambda d: len(links(d)) == 3)
    assert driver.find_element(By.LINK_TEXT, "Behat").is_displayed()


def test_a_link_needs_a_web_address(driver):
    add(driver, "Broken", "ftp://example.org/")
    error = WebDriverWait(driver, 10).until(lambda d: d.find_element(By.CSS_SELECTOR, "[role=alert]"))
    assert error.text == "URL must start with http:// or https://."
    assert len(links(driver)) == 2
EOF_PY

    # --- Robot Framework (keywords)
    gen_file "$DIR/robot/links.robot" << 'EOF_ROBOT'
*** Settings ***
Documentation     The links app through Robot Framework's Browser library (Playwright) on the system Chrome.
...               robot --variable HEADLESS:False links.robot shows the window.
Library           Browser
Library           RequestsLibrary
Suite Setup       New Browser    chromium    headless=${HEADLESS}    channel=chrome
Suite Teardown    Close Browser    ALL
Test Setup        Start With Two Links

*** Variables ***
${BASE_URL}       http://127.0.0.1:8795
${HEADLESS}       True

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
EOF_ROBOT

    # --- Cypress (code; install-cypress)
    gen_file "$DIR/cypress/package.json" << 'EOF_JSON'
{ "name": "bakeoff-cypress", "private": true, "allowScripts": { "cypress": true } }
EOF_JSON
    gen_file "$DIR/cypress/cypress.config.js" << 'EOF_JS'
const { defineConfig } = require('cypress')

module.exports = defineConfig({
  e2e: { baseUrl: process.env.BASE_URL || 'http://127.0.0.1:8795', supportFile: false, video: false },
})
EOF_JS
    gen_file "$DIR/cypress/cypress/e2e/links.cy.js" << 'EOF_JS'
describe('links', () => {
  beforeEach(() => {
    cy.request('POST', '/reset')
    cy.visit('/')
  })

  it('adds a link', () => {
    cy.get('#title').type('Behat')
    cy.get('#url').type('https://behat.org/')
    cy.contains('button', 'Add link').click()
    cy.get('[data-testid=link]').should('have.length', 3)
    cy.contains('a', 'Behat').should('be.visible')
  })

  it('needs a web address', () => {
    cy.get('#title').type('Broken')
    cy.get('#url').type('ftp://example.org/')
    cy.contains('button', 'Add link').click()
    cy.get('[role=alert]').should('have.text', 'URL must start with http:// or https://.')
    cy.get('[data-testid=link]').should('have.length', 2)
  })
})
EOF_JS
}

demo_testing_run() {
    write_run << 'EOF'
PORT=8795
export BASE_URL="${BASE_URL:-http://127.0.0.1:$PORT}"
OWN_APP=0
[ "$BASE_URL" = "http://127.0.0.1:$PORT" ] && OWN_APP=1
# Each target keeps its own results (BASE_URL=http://127.0.0.1:5173 is vue/vue-links: results-127_0_0_1_5173).
RESULTS=results
[ "$OWN_APP" = 1 ] || RESULTS="results-$(printf '%s' "${BASE_URL#*://}" | tr -c 'A-Za-z0-9' '_')"
mkdir -p "$RESULTS"

app_up() {   # the links app on :8795, in the background until the launcher ends (unless BASE_URL is another app)
    [ "$OWN_APP" = 1 ] || return 0
    (exec 3<> "/dev/tcp/127.0.0.1/$PORT") 2> /dev/null && return 0
    demo_bg links-app python3 app/links_app.py --port "$PORT"
    demo_wait_port "$PORT" 15 quiet || { echo "The links app did not start:"; tail -n 5 "$DEMO_LOGS/links-app.log"; return 1; }
}
sync_feature() { mkdir -p "$1"; cp features/links.feature "$1/links.feature"; }
# The Playwright release setup installed the browsers for (npx's cache), so Playwright Test needs no download.
pw_version() { npx -y --prefer-offline playwright@latest --version 2> /dev/null | awk '{print $2}'; }
pw_install() {   # pw_install DIR PACKAGE...: npm install once, with @playwright/test at setup's release
    local d=$1 v; shift
    [ -d "$d/node_modules/@playwright/test" ] && return 0
    demo_need npm install-node
    v=$(pw_version); [ -n "$v" ] || { echo "No Playwright in npx's cache: dev-setup with install-playwright."; return 1; }
    demo_step "npm install in $d (@playwright/test@$v $*)"
    ( cd "$d" && npm install -D --no-audit --no-fund "@playwright/test@$v" "$@" )
}
loc() {   # loc FILE...: lines of code, without blank lines and comments
    cat "$@" 2> /dev/null | grep -vE '^[[:space:]]*($|//|#|\*|/\*|\.\.\.)' | wc -l
}
# record RUNNER KIND DRIVER RC SECONDS FILE...: one line of results/RUNNER.tsv for the report
record() {
    local r=$1 k=$2 drv=$3 rc=$4 s=$5; shift 5
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$r" "$k" "$drv" "$( [ "$rc" = 0 ] && echo pass || echo FAIL)" "$s" "$(loc "$@")" "$(date '+%F %H:%M')" > "$DEMO_DIR/$RESULTS/$r.tsv"
}
# timed RUNNER KIND DRIVER "FILES" CMD...: run the test command (after its setup), time it, record it
timed() {
    local r=$1 k=$2 drv=$3 files=$4 t0 rc s; shift 4
    demo_step "$r: $drv"
    t0=$(date +%s%N)
    "$@"; rc=$?
    s=$(awk -v a="$t0" -v b="$(date +%s%N)" 'BEGIN { printf "%.1f", (b - a) / 1e9 }')
    # shellcheck disable=SC2086   # FILES is a list
    record "$r" "$k" "$drv" "$rc" "$s" $files
    if [ "$rc" = 0 ]; then demo_note "$r passed in ${s}s"; else demo_note "$r FAILED (exit $rc) after ${s}s"; fi
    return $rc
}

run_playwright() {
    pw_install playwright || return 1
    ( cd playwright && timed playwright code "Playwright Test (Playwright's Chromium)" "tests/links.spec.ts playwright.config.ts" npx playwright test --project=chromium )
}
run_playwright_bdd() {
    pw_install playwright-bdd playwright-bdd || return 1
    sync_feature playwright-bdd/features
    ( cd playwright-bdd && npx bddgen && timed playwright-bdd gherkin "playwright-bdd (system Chrome)" "steps/links.steps.ts playwright.config.ts" npx playwright test )
}
run_cucumber_js() {
    demo_need npm install-node
    if [ ! -d cucumber-js/node_modules/@cucumber/cucumber ]; then
        demo_step "npm install @cucumber/cucumber playwright-core"
        ( cd cucumber-js && npm install -D --no-audit --no-fund @cucumber/cucumber playwright-core ) || return 1
    fi
    ( cd cucumber-js && timed cucumber-js gherkin "cucumber-js + Playwright's library (system Chrome)" "steps/links.steps.mjs" \
        npx cucumber-js ../features/links.feature --import 'steps/*.mjs' --format progress )
}
run_behave() {
    sync_feature behave/features
    ( cd behave && timed behave gherkin "behave + Playwright for Python (system Chrome)" "features/steps/links_steps.py features/environment.py" \
        uv run --no-project --quiet --with behave --with playwright behave --format progress )
}
run_behat() {
    demo_need composer install-web
    if [ ! -x behat/vendor/bin/behat ]; then
        demo_step "composer install (Behat 4, Mink, the BrowserKit driver)"
        ( cd behat && composer install --no-interaction --no-progress ) || return 1
    fi
    sync_feature behat/features
    ( cd behat && timed behat gherkin "Behat 4 + Mink BrowserKit (HTTP, no browser)" "features/bootstrap/FeatureContext.php" \
        vendor/bin/behat --format progress )
}
run_reqnroll() {
    demo_need dotnet install-dotnet
    if [ ! -f reqnroll/LinksBakeoff.csproj ]; then
        dotnet new list reqnroll-project > /dev/null 2>&1 || { echo "No Reqnroll templates: dev-setup with install-bdd."; return 1; }
        demo_step "dotnet new reqnroll-project, then Playwright for .NET (NuGet)"
        rm -rf reqnroll
        dotnet new reqnroll-project -t nunit -n LinksBakeoff -o reqnroll || return 1
        rm -f reqnroll/Features/*.feature reqnroll/StepDefinitions/*.cs
        ( cd reqnroll && dotnet add package Microsoft.Playwright ) || return 1
    fi
    mkdir -p reqnroll/StepDefinitions
    cp reqnroll-src/LinksSteps.cs reqnroll/StepDefinitions/LinksSteps.cs
    sync_feature reqnroll/Features
    ( cd reqnroll && { dotnet build --nologo -v q > "$DEMO_LOGS/reqnroll-build.log" 2>&1 || { tail -n 20 "$DEMO_LOGS/reqnroll-build.log"; exit 1; }; } && timed reqnroll gherkin "Reqnroll (NUnit) + Playwright for .NET (system Chrome)" "StepDefinitions/LinksSteps.cs" \
        dotnet test --no-build --nologo -v q )
}
run_selenium() {
    ( cd selenium && timed selenium code "Selenium 4 + pytest (system Chrome, Selenium Manager)" "test_links.py" \
        env SE_AVOID_STATS=true uv run --no-project --quiet --with pytest --with selenium pytest -q -p no:cacheprovider test_links.py )
}
run_robot() {
    demo_need robot install-robot
    ( cd robot && timed robot keywords "Robot Framework, Browser library (system Chrome)" "links.robot" \
        robot --outputdir out --variable "BASE_URL:$BASE_URL" links.robot ) && demo_note "Robot's log: $DEMO_DIR/robot/out/log.html"
}
run_cypress() {
    demo_need npm install-node
    if [ ! -d cypress/node_modules/cypress ]; then
        demo_step "npm install cypress (first time: its Electron build, ~250 MB, goes to ~/.cache/Cypress)"
        ( cd cypress && npm install -D --no-audit --no-fund cypress && npx cypress install ) || return 1
    fi
    ( cd cypress && timed cypress code "Cypress (Electron, headless)" "cypress/e2e/links.cy.js cypress.config.js" \
        env CYPRESS_CRASH_REPORTS=0 npx cypress run --browser electron )
}

# Which runners this machine can run. Cypress only after setup's install-cypress (its ~/.bashrc block): Playwright's
# --with-deps installs Xvfb too, so Xvfb alone says nothing.
RUNNERS=()
command -v npm > /dev/null 2>&1 && RUNNERS+=(cucumber-js playwright-bdd playwright)
RUNNERS+=(behave selenium)
command -v composer > /dev/null 2>&1 && RUNNERS+=(behat)
command -v dotnet > /dev/null 2>&1 && dotnet new list reqnroll-project > /dev/null 2>&1 && RUNNERS+=(reqnroll)
command -v robot > /dev/null 2>&1 && RUNNERS+=(robot)
command -v npm > /dev/null 2>&1 && grep -q '^# >>> dev-setup cypress >>>$' "$HOME/.bashrc" 2> /dev/null && RUNNERS+=(cypress)
run_one() { app_up || return 1; "run_${1//-/_}"; }

report() {
    local f
    compgen -G "$RESULTS/*.tsv" > /dev/null || { echo "No results yet for $BASE_URL: run a runner (or 'all') first."; return 0; }
    demo_step "Bake-off report: the same two scenarios, $BASE_URL"
    { printf 'RUNNER\tKIND\tDRIVER\tRESULT\tSECONDS\tLINES\tWHEN\n'; for f in "$RESULTS"/*.tsv; do cat "$f"; done | sort -t$'\t' -k5,5n; } \
        | python3 -c 'import sys
rows = [l.rstrip("\n").split("\t") for l in sys.stdin if l.strip()]
w = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
for r in rows: print("  ".join(c.ljust(w[i]) for i, c in enumerate(r)).rstrip())'
    echo
    echo "SECONDS: the test command alone (installs and builds excluded). LINES: the runner's own steps, test and config, without blank lines and comments."
    echo "Gherkin runners share features/links.feature; Behat drives no browser (HTTP and HTML only), the rest a real Chrome."
}

grid() {   # the Selenium test through the shared Grid, in a browser you can watch (noVNC)
    docker_ok
    demo_need devsvc install-selenium
    docker container inspect devsvc-selenium > /dev/null 2>&1 || { echo "No Selenium Grid here: dev-setup with install-selenium."; return 1; }
    local was ip gport
    was=$(docker inspect -f '{{.State.Running}}' devsvc-selenium 2> /dev/null)
    devsvc up selenium || return 1
    [ "$was" = true ] || demo_on_exit "devsvc down selenium"
    # The Grid's browser runs in a container: it reaches this machine as host.docker.internal, so a second copy
    # of the app listens on Docker's address (docker0) as well.
    ip=$(ip -4 -o addr show docker0 2> /dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)
    [ -n "$ip" ] || { echo "No docker0 address."; return 1; }
    gport=8796
    (exec 3<> "/dev/tcp/$ip/$gport") 2> /dev/null || demo_bg links-app-grid python3 app/links_app.py --host "$ip" --port "$gport"
    sleep 1
    demo_open "http://localhost:7900/?autoconnect=1&resize=scale"
    demo_note "noVNC shows the Grid's screen; the test waits a little between steps (SLOWMO) so you can follow it."
    sleep 4
    ( cd selenium && GRID_URL=http://127.0.0.1:4444 BASE_URL="http://host.docker.internal:$gport" APP_URL="http://$ip:$gport" SLOWMO="${SLOWMO:-1}" \
        SE_AVOID_STATS=true uv run --no-project --quiet --with pytest --with selenium pytest -q -p no:cacheprovider test_links.py )
}

demo_note "Runners here: ${RUNNERS[*]}. Each one installs its packages on its first run (npm, uv, Composer, NuGet)."
[ "$OWN_APP" = 1 ] || demo_note "BASE_URL=$BASE_URL: the runners test that app; it needs this app's markup (labels, data-testid=link, role=alert). Behat's BrowserKit runs no JavaScript, so it fails against a Vue page: that is the point of comparing."
ITEMS=("app: start the links app on http://127.0.0.1:$PORT and open it (it stays up until you leave this menu)")
for r in "${RUNNERS[@]}"; do ITEMS+=("$r: run the two scenarios with $r"); done
ITEMS+=("all: every runner here, one after another, then the report"
    "report: time and lines of code per runner, from the last runs"
    "engines: Playwright Test in Chromium, Firefox, WebKit and the system Chrome"
    "ui: Playwright's UI mode (watch, pick and rerun tests; a window opens)"
    "codegen: record a test by clicking through the app (Playwright's inspector)"
    "trace: open the last Chromium run's trace in Playwright's trace viewer"
    "agents: add Playwright's test agents (planner, generator, healer) for Claude Code to playwright/"
    "mcp: add Playwright MCP to Claude Code in this folder, so Claude can drive a browser"
    "grid: the Selenium test through the shared Selenium Grid, watched in noVNC (install-selenium)"
    "headed: one runner with a visible browser (HEADED=1)")
while demo_menu "E2E bake-off ($BASE_URL)" "${ITEMS[@]}"; do
    case "$DEMO_CHOICE" in
        app*)     app_up && demo_open "$BASE_URL/" && demo_hold "Press Enter to go back to the menu (the app keeps running until you leave)" ;;
        all*)     for r in "${RUNNERS[@]}"; do run_one "$r"; done; report ;;
        report*)  report ;;
        engines*) app_up && pw_install playwright && ( cd playwright && npx playwright test ) ;;
        ui*)      app_up && pw_install playwright && ( cd playwright && npx playwright test --ui --project=chromium ) ;;
        codegen*) app_up && pw_install playwright && ( cd playwright && npx playwright codegen "$BASE_URL/" ) ;;
        trace*)   t=$(find playwright/test-results -name trace.zip -path '*chromium*' -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -n 1 | cut -d' ' -f2)
                  if [ -n "$t" ]; then ( cd playwright && npx playwright show-trace "${t#playwright/}" ); else echo "No trace yet: run 'playwright' first."; fi ;;
        agents*)  pw_install playwright && ( cd playwright && npx playwright init-agents --loop=claude ) \
                  && demo_note "Agents are in playwright/.claude. Try: cd $DEMO_DIR/playwright && claude, then ask: use the planner agent to explore $BASE_URL and write a test plan" ;;
        mcp*)     demo_need claude install-node
                  claude mcp add playwright -- npx @playwright/mcp@latest 2> /dev/null || demo_note "(already added here)"
                  demo_note "In this folder, 'claude' now has Playwright's browser tools (system Chrome). Try: open $BASE_URL and add a link called MCP."
                  demo_note "Remove it again: cd $DEMO_DIR && claude mcp remove playwright" ;;
        grid*)    grid ;;
        headed*)  HEADED_RUNNERS=()
                  for r in cucumber-js behave reqnroll selenium robot; do [[ " ${RUNNERS[*]} " == *" $r "* ]] && HEADED_RUNNERS+=("$r"); done
                  if demo_menu "Which runner, with a visible browser?" "${HEADED_RUNNERS[@]}"; then
                      app_up || continue
                      case "$DEMO_CHOICE" in
                          robot) ( cd robot && robot --outputdir out --variable "BASE_URL:$BASE_URL" --variable HEADLESS:False links.robot ) ;;
                          *)     HEADED=1 run_one "$DEMO_CHOICE" ;;
                      esac
                  fi ;;
        *)        run_one "${DEMO_CHOICE%%:*}" ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
}

# v91: drupal/drupal-behat: Drupal 11's Umami in DDEV (project devdemo-drupal-behat), tested with Behat 3 and
# the Drupal Extension (6.x; Behat 4 is not supported by it yet): visitor scenarios over HTTP (the blackbox
# driver, Mink's BrowserKit), @api scenarios that make content and users through Drupal's own API (the drupal
# driver, inside DDEV's web container), and @javascript scenarios in Chrome from DDEV's Selenium add-on
# (ddev/ddev-selenium-standalone-chrome), which you can watch in noVNC. Optional: one of core's
# FunctionalJavascript tests and core's example Nightwatch test in the same browser. The site, Composer
# packages and the add-on arrive on the first 'serve'; dev-demo writes only the Behat files. The behat/ folder
# is the one to edit: each run copies it into the site.
demo_drupal_behat() {
    begin drupal drupal-behat "Behat on Drupal: Umami in DDEV with the Drupal Extension: visitor, API and JavaScript scenarios (Chrome in DDEV's Selenium add-on)" \
        "https://github.com/jhedstrom/drupalextension + https://github.com/ddev/ddev-selenium-standalone-chrome" || return 0
    need ddev "the base install" || return 0
    need docker "the base install" || return 0
    FRESH=1
    gen_file "$DIR/behat/behat.yml" << 'EOF_YML'
# drupal/drupal-behat (dev-demo): Behat 3 + the Drupal Extension, run inside DDEV's web container
# ('ddev exec vendor/bin/behat'), so http://web is the site and the drupal driver boots Drupal directly.
default:
  autoload: ['%paths.base%/tests/bootstrap']
  suites:
    default:
      paths: ['%paths.base%/tests/features']
      contexts:
        - FeatureContext
        - Drupal\DrupalExtension\Context\DrupalContext
        - Drupal\DrupalExtension\Context\MinkContext
        - Drupal\DrupalExtension\Context\MessageContext
  extensions:
    Drupal\MinkExtension:
      base_url: http://web
      browserkit_http: ~
      javascript_session: selenium2
      # Chrome in the selenium-chrome container (DDEV's add-on), not headless: noVNC (:7900) shows it.
      selenium2:
        wd_host: http://selenium-chrome:4444/wd/hub
        capabilities:
          browser: chrome
          extra_capabilities:
            'goog:chromeOptions':
              w3c: true
              args: ['--disable-gpu', '--no-sandbox', '--disable-dev-shm-usage', '--window-size=1280,900']
    Drupal\DrupalExtension:
      blackbox: ~
      api_driver: drupal
      drupal:
        drupal_root: '%paths.base%/web'
EOF_YML
    gen_file "$DIR/behat/tests/bootstrap/FeatureContext.php" << 'EOF_PHP'
<?php

use Behat\Step\Then;
use Drupal\DrupalExtension\Context\RawDrupalContext;

/**
 * drupal-behat's own step, next to the Drupal Extension's ('vendor/bin/behat -dl' lists them all).
 */
class FeatureContext extends RawDrupalContext {

  /**
   * Counts published nodes of a type through Drupal's entity API (an @api scenario: Drupal is booted).
   */
  #[Then('Drupal has at least :count published :type nodes')]
  public function publishedNodes(int $count, string $type): void {
    // getDriver() boots Drupal through the drupal driver when this is the scenario's first API call.
    $this->getDriver();
    $n = (int) \Drupal::entityQuery('node')
      ->accessCheck(FALSE)
      ->condition('type', $type)
      ->condition('status', 1)
      ->count()
      ->execute();
    if ($n < $count) {
      throw new \RuntimeException("Only $n published $type nodes, expected at least $count.");
    }
  }

}
EOF_PHP
    gen_file "$DIR/behat/tests/features/visitor.feature" << 'EOF_FEATURE'
Feature: Umami for visitors
  Umami is Drupal's demo site: a food magazine with recipes and articles, in English and Spanish.
  These scenarios use the blackbox driver: plain HTTP and HTML, as a visitor's browser without JavaScript.

  Scenario: The front page leads to the recipes
    Given I am an anonymous user
    When I visit "/en"
    Then I should get a 200 HTTP response
    And I should see the link "Recipes"

  Scenario: A recipe has its ingredients
    Given I am an anonymous user
    When I visit "/en/recipes/deep-mediterranean-quiche"
    Then I should see the heading "Deep mediterranean quiche"
    And I should see the text "Ingredients"

  Scenario: The admin pages are closed to visitors
    Given I am an anonymous user
    When I visit "/admin/content"
    Then I should get a 403 HTTP response
EOF_FEATURE
    gen_file "$DIR/behat/tests/features/editor.feature" << 'EOF_FEATURE'
@api
Feature: Content and users, through Drupal's API
  The drupal driver boots Drupal inside DDEV's web container: content and users are made with Drupal's own
  API, and the Drupal Extension deletes them again after each scenario.

  Scenario: Umami ships its recipes
    Then Drupal has at least 5 published "recipe" nodes

  Scenario: An article made through the API shows up for an administrator
    Given the following "article" content:
      | title          | status |
      | Behat was here | 1      |
    And I am logged in as a user with the "administrator" role
    When I visit "/admin/content"
    Then I should see the link "Behat was here"
EOF_FEATURE
    gen_file "$DIR/behat/tests/features/javascript.feature" << 'EOF_FEATURE'
@javascript
Feature: Umami in a real browser
  Chrome in DDEV's selenium-chrome container (the ddev-selenium-standalone-chrome add-on) runs these, with
  JavaScript on. 'run-drupal-behat.sh watch' opens noVNC first, so you can watch it.

  Scenario: The front page in Chrome
    Given I am an anonymous user
    When I visit "/en"
    Then I should see the link "Recipes"

  @api
  Scenario: Log in through the form and open the content page
    Given I am logged in as a user with the "administrator" role
    When I visit "/admin/content"
    Then I should see the link "Add content"
EOF_FEATURE
    write_run << 'EOF'
docker_ok
demo_need ddev "the base install"
NAME=devdemo-drupal-behat
SITE="$DEMO_DIR/site"
mkdir -p "$SITE"
d() { ( cd "$SITE" && ddev "$@" ); }
# behat ARGS: Behat inside the web container. BEHAT_PARAMS from the Selenium add-on is unset: it configures
# Behat's own MinkExtension, while behat.yml (copied in from behat/) configures the Drupal Extension's.
behat() {
    cp -a "$DEMO_DIR/behat/." "$SITE/"
    # ddev exec hands its arguments to bash -c in the container, so each is quoted here: unquoted, the '&&'
    # in a --tags filter would end the command there.
    d exec "env -u BEHAT_PARAMS vendor/bin/behat --colors $(printf '%q ' "$@")"
}
installed() {   # ddev drush needs the project running: a stopped one (after a Linux restart) is started first
    [ -f "$SITE/composer.json" ] || return 1
    d start > /dev/null 2>&1 || return 1
    d drush status --field=bootstrap 2> /dev/null | grep -q Successful
}
serve() {
    if [ ! -d "$SITE/.ddev" ]; then
        d config --project-type=drupal11 --docroot=web --project-name="$NAME" || return 1
    fi
    if [ ! -f "$SITE/.ddev/docker-compose.selenium-chrome.yaml" ]; then
        demo_step "ddev add-on get ddev/ddev-selenium-standalone-chrome (Chrome for the @javascript scenarios)"
        d add-on get ddev/ddev-selenium-standalone-chrome || return 1
        # A project that was already running picks the new service up only on a restart.
        d restart || return 1
    fi
    demo_note "Memory before DDEV starts: $(free -h | awk '/^Mem:/ {print $7 " available of " $2}') (DDEV ~1 GB, its Chrome ~1 GB)"
    if docker inspect -f '{{.State.Running}}' devsvc-selenium 2> /dev/null | grep -q true; then
        demo_note "The shared Selenium Grid (devsvc) runs too; 'devsvc down selenium' gives its memory back."
    fi
    d start || return 1
    if [ ! -f "$SITE/composer.json" ]; then
        demo_step "ddev composer create-project drupal/recommended-project (a few minutes)"
        d composer create-project drupal/recommended-project || return 1
    fi
    if ! d composer show drupal/drupal-extension > /dev/null 2>&1; then
        demo_step "composer require drush/drush, and drupal/drupal-extension (Behat 3, Mink, the drivers) for development"
        d composer require drush/drush || return 1
        d composer require --dev 'drupal/drupal-extension:^6 || ^5' || return 1
    fi
    if ! installed; then
        demo_step "Installing Drupal with Umami (admin / admin)"
        d drush -y site:install demo_umami --account-name=admin --account-pass=admin --site-name="Umami Behat" || return 1
    fi
    cp -a "$DEMO_DIR/behat/." "$SITE/"
    demo_note "Umami: $(d describe -j 2> /dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["raw"]["primary_url"])' 2> /dev/null || echo "https://$NAME.ddev.site")  (admin / admin)"
}
need_site() { installed || { echo "Umami is not installed yet: '$0 serve' installs it (a few minutes)."; return 1; }; }

while demo_menu "Behat on Drupal (Umami in DDEV, project $NAME)" \
    "serve: install Umami in DDEV with Behat and the Selenium add-on (first run: a few minutes), then open it" \
    "visitor: the visitor scenarios over HTTP (blackbox driver, no JavaScript)" \
    "api: the @api scenarios (content and users made through Drupal's API)" \
    "javascript: the @javascript scenarios in Chrome (the add-on's Selenium container)" \
    "watch: the @javascript scenarios, with noVNC open to watch Chrome" \
    "all: every scenario" \
    "steps: every step the contexts offer (behat -dl), to write your own scenarios" \
    "core-fjs: one of Drupal core's FunctionalJavascript tests in the same Chrome (adds drupal/core-dev first)" \
    "nightwatch: core's example Nightwatch test in the same Chrome (yarn install in web/core first)" \
    "stop: ddev stop (the site and its Chrome)" \
    "delete: remove the DDEV project and its database (the next serve reinstalls)"; do
    case "$DEMO_CHOICE" in
        serve*)      serve && d launch ;;
        visitor*)    need_site && behat --tags='~@api&&~@javascript' ;;
        api*)        need_site && behat --tags='@api&&~@javascript' ;;
        javascript*) need_site && behat --tags='@javascript' ;;
        watch*)      need_site || continue
                     demo_note "noVNC: Chrome's screen in the selenium-chrome container (no password)."
                     d launch :7900; sleep 4
                     behat --tags='@javascript' ;;
        all*)        need_site && behat ;;
        steps*)      need_site && behat -dl ;;
        core-fjs*)   need_site || continue
                     if ! d composer show drupal/core-dev > /dev/null 2>&1; then
                         demo_step "ddev composer require --dev drupal/core-dev (PHPUnit and core's test tools; a few minutes)"
                         d composer require --dev -W drupal/core-dev || continue
                     fi
                     demo_note "FrameworkTest installs a throwaway site of its own and drives it in the add-on's Chrome (a few minutes)."
                     d exec -d /var/www/html/web "../vendor/bin/phpunit -c ./core/phpunit.xml.dist ./core/modules/system/tests/src/FunctionalJavascript/FrameworkTest.php" ;;
        nightwatch*) need_site || continue
                     if ! d exec -d /var/www/html/web/core test -d node_modules; then
                         demo_step "yarn install in web/core (core's JavaScript test tools; a few minutes)"
                         d exec -d /var/www/html/web/core yarn install || continue
                         d exec -d /var/www/html/web/core touch .env
                     fi
                     d exec -d /var/www/html/web/core yarn test:nightwatch tests/Drupal/Nightwatch/Tests/exampleTest.js ;;
        stop*)       d stop ;;
        delete*)     read -rp "Delete the DDEV project $NAME and its database? The next serve reinstalls it. [y/N] " a
                     [ "${a,,}" = y ] || continue
                     d delete -Oy && rm -rf "$SITE" && demo_note "Gone. '$0 serve' installs it again." ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# =================================================================
# DEMOS: Vue.js and GitLab (v91, install-vue, install-gitlab)
# =================================================================

# v91: vue/vue-links: a Vue 3 single-page front end (Vite, Pinia, Vitest, Playwright, Vue DevTools) on the
# links app the e2e bake-off tests, with the same labels and markup, so the bake-off's Gherkin feature runs
# unchanged against it (BASE_URL=http://127.0.0.1:5173). Vite's dev server on :5173 proxies /links.json and
# /reset to the links app on :8795, which the launcher starts. JavaScript, not TypeScript, to keep the files
# short ('npm create vue@latest' makes the TypeScript version). Packages arrive on the first launch.
demo_vue() {
    begin vue vue-links "Vue 3 links app: Vite, Pinia, Vitest, Playwright and Vue DevTools, on the bake-off's API; the bake-off's Gherkin runs against it" \
        "generated by dev-demo; https://vuejs.org https://pinia.vuejs.org https://vitest.dev" || return 0
    need npm install-node || return 0
    need python3 "the base install" || return 0
    FRESH=1
    links_app_source | gen_file "$DIR/app/links_app.py"
    gen_file "$DIR/package.json" << 'EOF_JSON'
{
  "name": "devdemo-vue-links",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "e2e": "playwright test"
  },
  "dependencies": {
    "pinia": "^4.0.0",
    "vue": "^3.5.0"
  },
  "devDependencies": {
    "@playwright/test": "^1.56.0",
    "@vitejs/plugin-vue": "^6.0.0",
    "@vue/test-utils": "^2.5.0",
    "jsdom": "^30.0.0",
    "vite": "^8.0.0",
    "vite-plugin-vue-devtools": "^8.0.0",
    "vitest": "^4.0.0"
  }
}
EOF_JSON
    gen_file "$DIR/vite.config.js" << 'EOF_JS'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'

// The links app (the e2e bake-off's back end) answers /links.json and /reset; Vite passes them through.
const api = process.env.LINKS_API ?? 'http://127.0.0.1:8795'
const proxy = { '/links.json': api, '/reset': api }

export default defineConfig({
  // Vue DevTools: Alt+Shift+D in the page, or http://localhost:5173/__devtools__/ (not in tests).
  plugins: [vue(), ...(process.env.VITEST ? [] : [vueDevTools()])],
  server: { host: '127.0.0.1', port: 5173, strictPort: true, proxy },
  preview: { host: '127.0.0.1', port: 4173, strictPort: true, proxy },
  test: { environment: 'jsdom', include: ['src/**/*.test.js'] },
})
EOF_JS
    gen_file "$DIR/index.html" << 'EOF_HTML'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Links (Vue)</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.js"></script>
  </body>
</html>
EOF_HTML
    gen_file "$DIR/src/main.js" << 'EOF_JS'
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'

createApp(App).use(createPinia()).mount('#app')
EOF_JS
    gen_file "$DIR/src/stores/links.js" << 'EOF_JS'
import { defineStore } from 'pinia'
import { ref } from 'vue'

// The links and the last error, kept in a Pinia store; the links app's JSON API is the source of truth.
export const useLinks = defineStore('links', () => {
  const links = ref([])
  const error = ref('')

  async function load() {
    links.value = await (await fetch('/links.json')).json()
  }

  async function add(title, url) {
    const r = await fetch('/links.json', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, url }),
    })
    const body = await r.json()
    if (!r.ok) {
      error.value = body.error
      return false
    }
    error.value = ''
    links.value = body
    return true
  }

  return { links, error, load, add }
})
EOF_JS
    gen_file "$DIR/src/components/LinkList.vue" << 'EOF_VUE'
<script setup>
defineProps({ links: { type: Array, required: true } })
</script>

<template>
  <p data-testid="count">{{ links.length }} links</p>
  <ul id="links">
    <li v-for="link in links" :key="link.url" data-testid="link">
      <a :href="link.url">{{ link.title }}</a>
    </li>
  </ul>
</template>
EOF_VUE
    gen_file "$DIR/src/App.vue" << 'EOF_VUE'
<script setup>
import { onMounted, ref } from 'vue'
import LinkList from './components/LinkList.vue'
import { useLinks } from './stores/links'

// The same labels, test ids and alert as the server-rendered links app, so one set of tests fits both.
const store = useLinks()
const title = ref('')
const url = ref('')
onMounted(store.load)

async function submit() {
  if (await store.add(title.value, url.value)) {
    title.value = ''
    url.value = ''
  }
}
</script>

<template>
  <main>
    <h1>Links</h1>
    <LinkList :links="store.links" />
    <p v-if="store.error" class="error" role="alert" data-testid="error">{{ store.error }}</p>
    <form @submit.prevent="submit">
      <label for="title">Title</label> <input id="title" v-model="title">
      <label for="url">URL</label> <input id="url" v-model="url">
      <button id="add" type="submit">Add link</button>
    </form>
  </main>
</template>

<style>
body { font: 16px system-ui; max-width: 40rem; margin: 2rem auto }
.error { color: #b00 }
label { display: block; margin-top: .5rem }
input { width: 100% }
button { margin-top: .75rem }
</style>
EOF_VUE
    gen_file "$DIR/src/components/LinkList.test.js" << 'EOF_JS'
import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import LinkList from './LinkList.vue'

describe('LinkList', () => {
  it('shows every link with its count', () => {
    const w = mount(LinkList, { props: { links: [
      { title: 'Vue', url: 'https://vuejs.org/' },
      { title: 'Pinia', url: 'https://pinia.vuejs.org/' },
    ] } })
    expect(w.findAll('[data-testid=link]')).toHaveLength(2)
    expect(w.get('[data-testid=count]').text()).toBe('2 links')
    expect(w.get('a').attributes('href')).toBe('https://vuejs.org/')
  })
})
EOF_JS
    gen_file "$DIR/playwright.config.js" << 'EOF_JS'
import { defineConfig, devices } from '@playwright/test'

// The e2e test mocks the API (page.route), so it needs no back end: locally it runs on the system Chrome
// ('chrome'), in GitLab CI on the Playwright image's own Chromium ('ci').
export default defineConfig({
  testDir: 'e2e',
  workers: 1,
  reporter: [['line']],
  use: { baseURL: 'http://127.0.0.1:5174' },
  webServer: { command: 'npx vite --port 5174 --strictPort', url: 'http://127.0.0.1:5174', reuseExistingServer: !process.env.CI },
  projects: [
    { name: 'chrome', use: { ...devices['Desktop Chrome'], channel: 'chrome' } },
    { name: 'ci', use: { ...devices['Desktop Chrome'] } },
  ],
})
EOF_JS
    gen_file "$DIR/e2e/links.spec.js" << 'EOF_JS'
import { test, expect } from '@playwright/test'

// The API is mocked here, so this is the front end alone: the bake-off item tests it with the real back end.
test.beforeEach(async ({ page }) => {
  let links = [{ title: 'Debian', url: 'https://www.debian.org/' }]
  await page.route('**/links.json', async (route) => {
    if (route.request().method() === 'GET') return route.fulfill({ json: links })
    const { title, url } = route.request().postDataJSON()
    if (!/^https?:\/\//.test(url)) return route.fulfill({ status: 422, json: { error: 'URL must start with http:// or https://.' } })
    links = [...links, { title, url }]
    return route.fulfill({ status: 201, json: links })
  })
  await page.goto('/')
})

test('adds a link', async ({ page }) => {
  await page.getByLabel('Title').fill('Vue')
  await page.getByLabel('URL').fill('https://vuejs.org/')
  await page.getByRole('button', { name: 'Add link' }).click()
  await expect(page.getByTestId('link')).toHaveCount(2)
  await expect(page.getByLabel('Title')).toHaveValue('')
})

test('shows the API error', async ({ page }) => {
  await page.getByLabel('Title').fill('Broken')
  await page.getByLabel('URL').fill('ftp://example.org/')
  await page.getByRole('button', { name: 'Add link' }).click()
  await expect(page.getByRole('alert')).toHaveText('URL must start with http:// or https://.')
})
EOF_JS
    gen_file "$DIR/.gitlab-ci.yml" << 'EOF_YML'
# vue-links' pipeline: gitlab.com runs it on a push; gitlab/ci-local runs it here with gitlab-ci-local.
stages: [test, build, e2e]

default:
  image: node:24

variables:
  # The @playwright/test release in package-lock.json: dev-demo's gitlab/ci-local sets it before each run.
  PW_VERSION: "1.63.0"

.npm:
  before_script:
    - if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi

unit:
  stage: test
  extends: .npm
  script:
    - npx vitest run

build:
  stage: build
  extends: .npm
  script:
    - npx vite build
  artifacts:
    paths: [dist/]

e2e:
  stage: e2e
  needs: []
  image: mcr.microsoft.com/playwright:v${PW_VERSION}-noble
  extends: .npm
  script:
    - npx playwright test --project=ci
EOF_YML
    gen_file "$DIR/.gitignore" << 'EOF_TXT'
node_modules/
dist/
test-results/
playwright-report/
.gitlab-ci-local/
EOF_TXT
    write_run << 'EOF'
demo_need npm install-node
API_PORT=8795
deps() {
    [ -d node_modules/vue ] && return 0
    demo_step "npm install (Vue, Pinia, Vite, Vitest, Playwright's test runner; a minute or two the first time)"
    npm install --no-audit --no-fund
}
api_up() {   # the links app, the API this front end calls (stopped when the launcher ends)
    (exec 3<> "/dev/tcp/127.0.0.1/$API_PORT") 2> /dev/null && return 0
    demo_bg links-api python3 app/links_app.py --port "$API_PORT"
    demo_wait_port "$API_PORT" 15 quiet || { tail -n 5 "$DEMO_LOGS/links-api.log"; return 1; }
}
dev_up() {   # Vite's dev server on :5173 in the background
    (exec 3<> /dev/tcp/127.0.0.1/5173) 2> /dev/null && return 0
    demo_bg vue-links-dev npx vite
    demo_wait_port 5173 60 quiet || { tail -n 8 "$DEMO_LOGS/vue-links-dev.log"; return 1; }
}
while demo_menu "Vue links (front end :5173, API :$API_PORT)" \
    "dev: Vite's dev server with hot reload and Vue DevTools; edit src/App.vue and watch it change" \
    "test: Vitest, the component test (src/components/LinkList.test.js)" \
    "e2e: Playwright, the front end against a mocked API, on the system Chrome" \
    "build: a production build, served by 'vite preview' on :4173" \
    "bakeoff: the e2e bake-off's runners against this Vue version (BASE_URL=http://127.0.0.1:5173)" \
    "reset: put the API's links back to the two starting ones"; do
    case "$DEMO_CHOICE" in
        dev*)     deps && api_up || continue
                  demo_open_when_ready 5173 http://localhost:5173/
                  demo_note "Vue DevTools: Alt+Shift+D in the page. Ctrl-C stops."
                  npx vite ;;
        test*)    deps && npx vitest run ;;
        e2e*)     deps && npx playwright test --project=chrome ;;
        build*)   deps && api_up && npx vite build || continue
                  demo_open_when_ready 4173 http://localhost:4173/
                  npx vite preview ;;
        bakeoff*) [ -x "$HOME/dev-demo/testing/run-e2e-bakeoff.sh" ] || { echo "The bake-off is not downloaded: dev-demo with install-testing."; continue; }
                  deps && api_up && dev_up || continue
                  demo_note "Every runner, against this Vue page; Behat (no JavaScript) is expected to fail here."
                  BASE_URL=http://127.0.0.1:5173 "$HOME/dev-demo/testing/run-e2e-bakeoff.sh" all ;;
        reset*)   api_up && curl -fsS -X POST "http://127.0.0.1:$API_PORT/reset" && echo ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}


# v91: drupal/drupal-nuxt: Drupal 11's Umami as a headless back end (core's JSON:API, read-only, published
# content) and a Nuxt 4 front end that renders its recipes on the server. Drupal runs on PHP's built-in server
# + SQLite on :8891 (as drupal-graphql's local site does on :8889); Nuxt's dev server on :3020, its production
# build on :3021. Nuxt's server routes (server/api/) call Drupal, so the browser never needs Drupal's address
# except for images. Composer, Drupal and the Node packages arrive on the first 'serve'.
demo_drupal_nuxt() {
    begin drupal drupal-nuxt "Headless Drupal: Umami's recipes over core's JSON:API, rendered on the server by a Nuxt 4 front end" \
        "https://www.drupal.org/docs/core-modules-and-themes/core-modules/jsonapi-module + https://nuxt.com" || return 0
    need php "the base install" || return 0
    need composer install-web || return 0
    need npm install-node || return 0
    php -m 2> /dev/null | grep -qi '^pdo_sqlite$' || apt_need php-sqlite3 || { fail "php-sqlite3 missing"; return 0; }
    FRESH=1
    gen_file "$DIR/nuxt/package.json" << 'EOF_JSON'
{
  "name": "devdemo-umami-nuxt",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "nuxt dev",
    "build": "nuxt build",
    "preview": "nuxt preview",
    "postinstall": "nuxt prepare"
  },
  "dependencies": {
    "nuxt": "^4.0.0",
    "vue": "^3.5.0",
    "vue-router": "^5.0.0"
  }
}
EOF_JSON
    gen_file "$DIR/nuxt/nuxt.config.ts" << 'EOF_TS'
// Umami on Nuxt: Drupal's address is server-side config (NUXT_DRUPAL_URL overrides it).
export default defineNuxtConfig({
  compatibilityDate: '2026-09-01',
  devtools: { enabled: true },
  runtimeConfig: { drupalUrl: 'http://127.0.0.1:8891' },
  app: { head: { title: 'Umami on Nuxt', htmlAttrs: { lang: 'en' } } },
})
EOF_TS
    gen_file "$DIR/nuxt/server/utils/drupal.ts" << 'EOF_TS'
// jsonapi(path): one JSON:API request to Drupal, from Nuxt's server (never from the browser).
export async function jsonapi(path: string): Promise<any> {
  const { drupalUrl } = useRuntimeConfig()
  return await $fetch(`${drupalUrl}/jsonapi${path}`, { headers: { Accept: 'application/vnd.api+json' } })
}

export function imageUrl(doc: any, node: any): string | null {
  const mediaId = node.relationships?.field_media_image?.data?.id
  const media = (doc.included ?? []).find((i: any) => i.id === mediaId)
  const fileId = media?.relationships?.field_media_image?.data?.id
  const file = (doc.included ?? []).find((i: any) => i.id === fileId)
  const url = file?.attributes?.uri?.url
  return url ? `${useRuntimeConfig().drupalUrl}${url}` : null
}
EOF_TS
    gen_file "$DIR/nuxt/server/api/recipes.get.ts" << 'EOF_TS'
// GET /api/recipes: Umami's recipes, sorted by title, with the fields the list shows.
export default defineEventHandler(async () => {
  const fields = 'title,field_summary,field_difficulty,field_preparation_time,field_cooking_time,field_media_image'
  const doc = await jsonapi(`/node/recipe?sort=title&page[limit]=50&fields[node--recipe]=${fields}`
    + '&include=field_media_image.field_media_image&fields[media--image]=field_media_image&fields[file--file]=uri')
  return doc.data.map((n: any) => ({
    id: n.id,
    title: n.attributes.title,
    summary: n.attributes.field_summary?.processed ?? '',
    difficulty: n.attributes.field_difficulty,
    minutes: (n.attributes.field_preparation_time ?? 0) + (n.attributes.field_cooking_time ?? 0),
    image: imageUrl(doc, n),
  }))
})
EOF_TS
    gen_file "$DIR/nuxt/server/api/recipes/[id].get.ts" << 'EOF_TS'
// GET /api/recipes/:id: one recipe (its JSON:API UUID) with ingredients, instructions and its image.
export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id')
  const doc = await jsonapi(`/node/recipe/${id}?include=field_media_image.field_media_image`)
  const a = doc.data.attributes
  return {
    title: a.title,
    summary: a.field_summary?.processed ?? '',
    difficulty: a.field_difficulty,
    preparation: a.field_preparation_time,
    cooking: a.field_cooking_time,
    servings: a.field_number_of_servings,
    ingredients: a.field_ingredients ?? [],
    instructions: a.field_recipe_instruction?.processed ?? '',
    image: imageUrl(doc, doc.data),
  }
})
EOF_TS
    gen_file "$DIR/nuxt/app/app.vue" << 'EOF_VUE'
<template>
  <div class="site">
    <header><NuxtLink to="/">Umami on Nuxt</NuxtLink> <small>headless Drupal 11, rendered by Nuxt 4</small></header>
    <NuxtPage />
  </div>
</template>

<style>
body { font: 16px system-ui; margin: 0; color: #222 }
.site { max-width: 60rem; margin: 0 auto; padding: 1rem }
header { padding: .5rem 0 1rem; border-bottom: 1px solid #ddd; margin-bottom: 1rem }
header a { font-weight: 700; color: #b03a2e; text-decoration: none; margin-right: .5rem }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr)); gap: 1rem; list-style: none; padding: 0 }
.card img, .recipe img { width: 100%; height: auto; border-radius: .5rem }
.meta { color: #666; font-size: .9rem }
</style>
EOF_VUE
    gen_file "$DIR/nuxt/app/pages/index.vue" << 'EOF_VUE'
<script setup lang="ts">
// Fetched on the server during the first render (view the page source: the recipes are in the HTML).
const { data: recipes, error } = await useFetch('/api/recipes')
</script>

<template>
  <main>
    <h1>Recipes</h1>
    <p v-if="error" role="alert">Drupal did not answer: is it running on :8891? ({{ error.message }})</p>
    <ul class="grid">
      <li v-for="r in recipes" :key="r.id" class="card" data-testid="recipe">
        <NuxtLink :to="`/recipes/${r.id}`">
          <img v-if="r.image" :src="r.image" :alt="r.title" loading="lazy">
          <h2>{{ r.title }}</h2>
        </NuxtLink>
        <p class="meta">{{ r.difficulty }} · {{ r.minutes }} min</p>
      </li>
    </ul>
  </main>
</template>
EOF_VUE
    gen_file "$DIR/nuxt/app/pages/recipes/[id].vue" << 'EOF_VUE'
<script setup lang="ts">
const route = useRoute()
const { data: r } = await useFetch(`/api/recipes/${route.params.id}`)
useHead({ title: () => r.value?.title ?? 'Recipe' })
</script>

<template>
  <article v-if="r" class="recipe">
    <h1>{{ r.title }}</h1>
    <p class="meta">{{ r.difficulty }} · prep {{ r.preparation }} min · cook {{ r.cooking }} min · serves {{ r.servings }}</p>
    <img v-if="r.image" :src="r.image" :alt="r.title">
    <div v-html="r.summary" />
    <h2>Ingredients</h2>
    <ul><li v-for="i in r.ingredients" :key="i">{{ i }}</li></ul>
    <h2>Method</h2>
    <div v-html="r.instructions" />
  </article>
</template>
EOF_VUE
    write_run << 'EOF'
demo_need php "the base install"
demo_need composer install-web
demo_need npm install-node
DRUPAL=http://127.0.0.1:8891
dr() { ( cd drupal && php -d memory_limit=512M vendor/bin/drush "$@" ); }
listening() { (exec 3<> "/dev/tcp/127.0.0.1/$1") 2> /dev/null; }
installed() { [ -f drupal/composer.json ] && dr status --field=bootstrap 2> /dev/null | grep -q Successful; }
install_site() {   # Composer project, Drupal with Umami, JSON:API on. Safe to repeat.
    if [ ! -f drupal/composer.json ]; then
        demo_step "composer create-project drupal/recommended-project drupal (a few minutes)"
        composer create-project drupal/recommended-project drupal --no-progress || { rm -rf drupal; return 1; }
    fi
    ( cd drupal && composer show drush/drush > /dev/null 2>&1 ) || ( cd drupal && composer require drush/drush --no-progress ) || return 1
    if ! installed; then
        demo_step "Installing Drupal with Umami (admin / admin) on SQLite"
        dr -y site:install demo_umami --db-url=sqlite://sites/default/files/.ht.sqlite --account-name=admin --account-pass=admin \
            --site-name="Umami (headless)" || return 1
    fi
    dr -y pm:install jsonapi > /dev/null && echo "  JSON:API is on (read-only): $DRUPAL/jsonapi"
}
drupal_up() {
    installed || install_site || return 1
    if ! listening 8891; then
        demo_bg drupal-nuxt-drupal bash -c 'cd drupal/web && PHP_CLI_SERVER_WORKERS=4 exec php -d memory_limit=512M -S 127.0.0.1:8891 .ht.router.php'
        demo_wait_port 8891 60 quiet || { tail -n 5 "$DEMO_LOGS/drupal-nuxt-drupal.log"; return 1; }
    fi
}
nuxt_deps() {
    [ -d nuxt/node_modules/nuxt ] && return 0
    demo_step "npm install in nuxt/ (Nuxt 4; a minute or two the first time)"
    ( cd nuxt && npm install --no-audit --no-fund )
}
while demo_menu "Headless Drupal + Nuxt (Drupal :8891, Nuxt :3020)" \
    "serve: install Umami the first time, start Drupal and Nuxt's dev server, open the recipes" \
    "build: Nuxt's production build, served by its own Node server on :3021" \
    "api: one raw JSON:API request (a recipe's title and difficulty), the data Nuxt renders" \
    "source: show that the recipes are in the server-rendered HTML (no JavaScript needed to see them)" \
    "drupal: open Drupal itself (admin / admin)" \
    "stop: stop Drupal and Nuxt" \
    "reset: delete the Drupal site (the next serve reinstalls it)"; do
    case "$DEMO_CHOICE" in
        serve*)  drupal_up && nuxt_deps || continue
                 demo_open_when_ready 3020 http://localhost:3020/
                 demo_note "Nuxt DevTools: the button at the bottom of the page. Ctrl-C stops Nuxt (Drupal stops with this launcher)."
                 ( cd nuxt && NUXT_DRUPAL_URL=$DRUPAL npx nuxt dev --host 127.0.0.1 --port 3020 ) ;;
        build*)  drupal_up && nuxt_deps || continue
                 ( cd nuxt && npx nuxt build ) || continue
                 demo_open_when_ready 3021 http://localhost:3021/
                 ( cd nuxt && NUXT_DRUPAL_URL=$DRUPAL HOST=127.0.0.1 PORT=3021 node .output/server/index.mjs ) ;;
        api*)    drupal_up || continue
                 curl -fsS -H 'Accept: application/vnd.api+json' "$DRUPAL/jsonapi/node/recipe?page%5Blimit%5D=3&fields%5Bnode--recipe%5D=title,field_difficulty" \
                     | python3 -c 'import json, sys
for r in json.load(sys.stdin)["data"]:
    print(r["id"], " ", r["attributes"]["title"], "(" + str(r["attributes"]["field_difficulty"]) + ")")' ;;
        source*) listening 3020 || listening 3021 || { echo "Start Nuxt first: '$0 serve' (or build) in another terminal."; continue; }
                 p=3020; listening 3020 || p=3021
                 curl -fsS "http://127.0.0.1:$p/" | grep -o '<h2>[^<]*</h2>' | head -n 5
                 demo_note "Those titles came from Drupal, in the HTML Nuxt rendered on the server." ;;
        drupal*) drupal_up && demo_open "$DRUPAL/user/login" && demo_hold "Press Enter to stop Drupal" ;;
        stop*)   pkill -f "php -d memory_limit=512M -S 127.0.0.1:8891" 2> /dev/null; pkill -f "nuxt dev --host 127.0.0.1 --port 3020" 2> /dev/null; echo "Stopped." ;;
        reset*)  read -rp "Delete the Drupal site (its files and SQLite database)? The next serve reinstalls it. [y/N] " a
                 [ "${a,,}" = y ] || continue
                 chmod -R u+w drupal 2> /dev/null; rm -rf drupal && demo_note "Gone. '$0 serve' installs it again." ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}


# v91: gitlab/ci-local: GitLab CI pipelines run here with gitlab-ci-local, before (or instead of) a push.
#   vue     vue/vue-links' .gitlab-ci.yml (Vitest, a Vite build, Playwright in Playwright's own image), on a
#           committed copy of vue-links in work/vue-links (gitlab-ci-local only sees tracked files)
#   drupal  a small contrib-style module, devdemo_hello, with drupal.org's standard .gitlab-ci.yml: the
#           gitlab_templates pipeline (composer, phpcs, phpstan, phpunit...) fetched from git.drupalcode.org the
#           first time, one job at a time (--concurrency 1)
#   push    with glab logged in (GITLAB_TOKEN_ONCE): a private gitlab.com project for vue-links, a push, and the
#           real pipeline followed live. gitlab.com's shared runners want a verified account; a runner of your
#           own (install-gitlab-runner) registered to that project takes the jobs instead.
demo_gitlab() {
    begin gitlab ci-local "GitLab CI locally: vue-links' pipeline and a Drupal contrib module's drupal.org pipeline through gitlab-ci-local; push to gitlab.com with glab" \
        "generated by dev-demo; https://github.com/firecow/gitlab-ci-local https://git.drupalcode.org/project/gitlab_templates" || return 0
    need gitlab-ci-local install-gitlab || return 0
    need docker "the base install" || return 0
    FRESH=1
    gen_file "$DIR/drupal-module/devdemo_hello.info.yml" << 'EOF_YML'
name: 'Dev demo hello'
type: module
description: 'A tiny module for running drupal.org GitLab CI templates locally (dev-demo).'
core_version_requirement: ^10.3 || ^11
package: Development
EOF_YML
    gen_file "$DIR/drupal-module/composer.json" << 'EOF_JSON'
{
    "name": "drupal/devdemo_hello",
    "type": "drupal-module",
    "description": "A tiny module for running drupal.org GitLab CI templates locally (dev-demo).",
    "license": "GPL-2.0-or-later",
    "require": {}
}
EOF_JSON
    gen_file "$DIR/drupal-module/src/Greeter.php" << 'EOF_PHP'
<?php

declare(strict_types=1);

namespace Drupal\devdemo_hello;

/**
 * Greets people; the unit test checks it.
 */
final class Greeter {

  /**
   * Returns a greeting for a name.
   */
  public function greet(string $name): string {
    return 'Hello, ' . trim($name) . '!';
  }

}
EOF_PHP
    gen_file "$DIR/drupal-module/tests/src/Unit/GreeterTest.php" << 'EOF_PHP'
<?php

declare(strict_types=1);

namespace Drupal\Tests\devdemo_hello\Unit;

use Drupal\Tests\UnitTestCase;
use Drupal\devdemo_hello\Greeter;
use PHPUnit\Framework\Attributes\Group;

/**
 * Tests the greeter.
 */
#[Group('devdemo_hello')]
final class GreeterTest extends UnitTestCase {

  /**
   * Tests a greeting.
   */
  public function testGreet(): void {
    $this->assertSame('Hello, Drupal!', (new Greeter())->greet(' Drupal '));
  }

}
EOF_PHP
    gen_file "$DIR/drupal-module/.gitlab-ci.yml" << 'EOF_YML'
################
# drupal.org's standard GitLab CI file for a contrib project (as a new project gets it). The include points at
# the Drupal Association's templates: https://git.drupalcode.org/project/gitlab_templates
# On git.drupalcode.org, _GITLAB_TEMPLATES_REPO and _GITLAB_TEMPLATES_REF are instance variables; here they come
# from .gitlab-ci-local-variables.yml.
################
include:
  - project: $_GITLAB_TEMPLATES_REPO
    ref: $_GITLAB_TEMPLATES_REF
    file:
      - '/includes/include.drupalci.main.yml'
      - '/includes/include.drupalci.variables.yml'
      - '/includes/include.drupalci.workflows.yml'
EOF_YML
    gen_file "$DIR/drupal-module/.gitlab-ci-local-variables.yml" << 'EOF_YML'
# gitlab-ci-local only (not on drupal.org): the instance variables drupal.org sets, and the front-end linters
# skipped (this module has no JavaScript or CSS).
_GITLAB_TEMPLATES_REPO: project/gitlab_templates
_GITLAB_TEMPLATES_REF: default-ref
SKIP_ESLINT: "1"
SKIP_STYLELINT: "1"
SKIP_CSPELL: "1"
EOF_YML
    gen_file "$DIR/README.md" << 'EOF_TXT'
# GitLab CI, locally

`../run-ci-local.sh` runs two pipelines with gitlab-ci-local (jobs with an image in Docker):

- **vue**: vue/vue-links' `.gitlab-ci.yml`: Vitest, a Vite build, Playwright in Playwright's image. Runs on a
  committed copy in `work/vue-links`, since gitlab-ci-local only sees tracked files.
- **drupal**: `drupal-module/`, a contrib-style module with drupal.org's standard `.gitlab-ci.yml`. The Drupal
  Association's templates come from git.drupalcode.org the first time; jobs run one at a time.
- **push**: with glab logged in, a private gitlab.com project for vue-links, a push, and the pipeline live.

`.gitlab-ci-local/` in each project holds gitlab-ci-local's state (includes, artifacts, logs).
EOF_TXT
    write_run << 'EOF'
demo_need gitlab-ci-local install-gitlab
docker_ok
VUE_SRC="$HOME/dev-demo/vue/vue-links"
GCL=(gitlab-ci-local --concurrency 1 --timestamps)
commit_all() {   # commit_all DIR: gitlab-ci-local only sees tracked files, so each run commits what changed
    # A local identity and origin/HEAD, so gitlab-ci-local has no fallbacks to report.
    git -C "$1" config user.name > /dev/null || git -C "$1" config user.name dev-demo
    git -C "$1" config user.email > /dev/null || git -C "$1" config user.email dev-demo@localhost
    git -C "$1" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$(git -C "$1" symbolic-ref --short HEAD)" 2> /dev/null || true
    git -C "$1" add -A > /dev/null 2>&1
    git -C "$1" commit -qm "dev-demo $(date +%F_%T)" > /dev/null 2>&1 || true
}
vue_copy() {   # work/vue-links: vue-links' sources (no node_modules), a lockfile, PW_VERSION, a git repository
    [ -f "$VUE_SRC/package.json" ] || { echo "vue/vue-links is not downloaded: dev-demo with install-vue."; return 1; }
    mkdir -p work/vue-links
    rsync -a --delete --exclude node_modules --exclude dist --exclude test-results --exclude playwright-report \
        --exclude .gitlab-ci-local --exclude .git "$VUE_SRC/" work/vue-links/
    if [ ! -f work/vue-links/package-lock.json ]; then
        demo_step "npm install --package-lock-only (the pipeline installs from the lockfile)"
        ( cd work/vue-links && npm install --package-lock-only --no-audit --no-fund > /dev/null ) || return 1
    fi
    # The e2e job's image must be the Playwright release in the lockfile.
    local v
    v=$(node -p 'require("./work/vue-links/package-lock.json").packages["node_modules/@playwright/test"].version' 2> /dev/null)
    [ -n "$v" ] && sed -i "s/^  PW_VERSION: .*/  PW_VERSION: \"$v\"/" work/vue-links/.gitlab-ci.yml
    [ -d work/vue-links/.git ] || { git -C work/vue-links init -q -b main && git -C work/vue-links remote add origin https://gitlab.com/dev-demo/vue-links.git; }
    commit_all work/vue-links
}
drupal_repo() {   # drupal-module as a git repository whose origin is on git.drupalcode.org (where includes come from)
    [ -d drupal-module/.git ] || { git -C drupal-module init -q -b 1.0.x && git -C drupal-module remote add origin https://git.drupalcode.org/project/devdemo_hello.git; }
    commit_all drupal-module
}
mem_note() {
    demo_note "Memory now: $(free -h | awk '/^Mem:/ {print $7 " available of " $2}'). Jobs run one at a time; 'devsvc down all' gives the shared services' memory back."
}
while demo_menu "GitLab CI, locally (gitlab-ci-local)" \
    "vue: vue-links' whole pipeline (unit, build, e2e in Playwright's image)" \
    "vue-job: one job of vue-links' pipeline" \
    "vue-list: the jobs, stages and needs gitlab-ci-local sees" \
    "preview: vue-links' pipeline with every include, extends and anchor expanded" \
    "drupal-list: the drupal.org templates' jobs for the module (fetches the templates the first time)" \
    "drupal-phpcs: composer, then PHP_CodeSniffer with Drupal's coding standards" \
    "drupal-phpunit: composer, then PHPUnit (the module's unit test, in a whole Drupal)" \
    "drupal-all: every drupal.org job, one at a time (a long run)" \
    "push: create a private gitlab.com project for vue-links, push it, follow the pipeline (glab login needed)" \
    "runner: this machine's GitLab Runner (install-gitlab-runner): its registrations and status"; do
    case "$DEMO_CHOICE" in
        vue-job*)  vue_copy || continue
                   if demo_menu "Which job?" unit build e2e; then ( cd work/vue-links && "${GCL[@]}" --needs "$DEMO_CHOICE" ); fi ;;
        vue-list*) vue_copy && ( cd work/vue-links && gitlab-ci-local --list ) ;;
        vue*)      vue_copy || continue; mem_note; ( cd work/vue-links && "${GCL[@]}" ) ;;
        preview*)  vue_copy && ( cd work/vue-links && gitlab-ci-local --preview | less -R ) ;;
        drupal-list*)   drupal_repo && ( cd drupal-module && gitlab-ci-local --list ) ;;
        drupal-phpcs*)  drupal_repo; mem_note; ( cd drupal-module && "${GCL[@]}" --needs phpcs ) ;;
        drupal-phpunit*) drupal_repo; mem_note; ( cd drupal-module && "${GCL[@]}" --needs phpunit ) ;;
        drupal-all*)    drupal_repo; mem_note; ( cd drupal-module && "${GCL[@]}" ) ;;
        push*)     demo_need glab install-gitlab
                   glab auth status --hostname gitlab.com > /dev/null 2>&1 || { echo "glab is not logged in to gitlab.com: GITLAB_TOKEN_ONCE in secrets.env, then dev-init with install-gitlab."; continue; }
                   vue_copy || continue
                   user=$(glab api user 2> /dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin)["username"])')
                   [ -n "$user" ] || { echo "Could not read your gitlab.com user name."; continue; }
                   glab repo view "$user/devdemo-vue-links" > /dev/null 2>&1 \
                       || glab repo create devdemo-vue-links --private --defaultBranch main --description "dev-demo's vue-links" > /dev/null || continue
                   git -C work/vue-links remote set-url origin "git@gitlab.com:$user/devdemo-vue-links.git"
                   # gitlab.com's host key, so the first push does not stop at SSH's yes/no question.
                   ssh-keygen -F gitlab.com > /dev/null 2>&1 || ssh-keyscan -t ed25519 gitlab.com >> ~/.ssh/known_hosts 2> /dev/null
                   git -C work/vue-links push -u origin main || continue
                   demo_note "https://gitlab.com/$user/devdemo-vue-links/-/pipelines   (Ctrl-C stops following; the pipeline carries on)"
                   ( cd work/vue-links && glab ci status --live ) ;;
        runner*)   if command -v gitlab-runner > /dev/null 2>&1; then sudo gitlab-runner list; systemctl status gitlab-runner --no-pager | head -n 5
                   else echo "No GitLab Runner here: dev-setup with install-gitlab-runner."; fi ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# v91: the configuration management bake-off. The same small web server (nginx, one site file, one page) built by
# Ansible, Puppet (OpenVox) and Chef (Cinc), each in its own debian:trixie-slim container, then compared: idempotency,
# seconds and lines of code, one InSpec audit for all three, and dry runs. Each tool takes part when it is set up here.
demo_cm() {
    begin iac cm-bakeoff "Ansible, Puppet and Chef build the same nginx server in three containers (:8813, :8811, :8812); idempotency, timing, lines of code, one audit, dry runs" \
        "generated by dev-demo; https://voxpupuli.org/openvox/ https://cinc.sh" || return 0
    need docker "the base install" || return 0
    # --- the containers: one base, then each tool's agent or Python baked in (not timed by the report) ---
    gen_file "$DIR/images/base/Dockerfile" << 'EOF'
# The starting point for all three: Debian 13, plus what the audit and the health checks use (ps, curl).
FROM debian:trixie-slim
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends ca-certificates curl procps > /dev/null \
 && rm -rf /var/lib/apt/lists/*
CMD ["sleep", "infinity"]
EOF
    gen_file "$DIR/images/ansible/Dockerfile" << 'EOF'
# Ansible pushes over 'docker exec' (community.docker) and needs Python on the target; nothing else is installed.
FROM devdemo-cm-base
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends python3 python3-apt > /dev/null \
 && rm -rf /var/lib/apt/lists/*
EOF
    gen_file "$DIR/images/puppet/Dockerfile" << 'EOF'
# Puppet runs on the target: OpenVox's agent from Vox Pupuli's apt repository (OPENVOX_MAJOR 8 by default, as setup).
FROM devdemo-cm-base
ARG OPENVOX_MAJOR=8
RUN curl -fsSLo /tmp/openvox-release.deb "https://apt.voxpupuli.org/openvox${OPENVOX_MAJOR}-release-debian13.deb" \
 && apt-get install -y -qq /tmp/openvox-release.deb > /dev/null \
 && apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends openvox-agent > /dev/null \
 && rm -rf /tmp/openvox-release.deb /var/lib/apt/lists/*
ENV PATH=/opt/puppetlabs/bin:$PATH
EOF
    gen_file "$DIR/images/chef/Dockerfile" << 'EOF'
# Chef runs on the target: Cinc Client (the free build of Chef Infra Client) through Cinc's installer.
FROM devdemo-cm-base
RUN curl -fsSL https://omnitruck.cinc.sh/install.sh | bash -s -- -P cinc > /dev/null \
 && rm -rf /var/lib/apt/lists/*
ENV PATH=/opt/cinc/bin:$PATH
EOF
    # --- Ansible: a playbook with two templates, pushed from here ---
    gen_file "$DIR/ansible/ansible.cfg" << 'EOF'
[defaults]
inventory = inventory.yml
interpreter_python = auto_silent
EOF
    gen_file "$DIR/ansible/inventory.yml" << 'EOF'
---
# The target is a container: no SSH, Ansible reaches it through 'docker exec'.
all:
  hosts:
    devdemo-cm-ansible:
      ansible_connection: community.docker.docker
      ansible_python_interpreter: /usr/bin/python3
EOF
    gen_file "$DIR/ansible/site.yml" << 'EOF'
---
# The bake-off's web server, the Ansible way: tasks run top to bottom; a handler reloads nginx when its site
# changes. The Puppet and Chef versions build the same thing.
- name: Configure the web server
  hosts: all
  vars:
    tool: Ansible
    web_message: Configured by Ansible
  tasks:
    - name: Install nginx (the package lists are refreshed at most once an hour)
      ansible.builtin.apt:
        name: nginx
        state: present
        update_cache: true
        cache_valid_time: 3600

    - name: Drop Debian's default site
      ansible.builtin.file:
        path: /etc/nginx/sites-enabled/default
        state: absent

    - name: Make the site's folder
      ansible.builtin.file:
        path: /var/www/devdemo
        state: directory
        mode: "0755"

    - name: Publish the page
      ansible.builtin.template:
        src: templates/index.html.j2
        dest: /var/www/devdemo/index.html
        mode: "0644"

    - name: Write the site file
      ansible.builtin.template:
        src: templates/devdemo.conf.j2
        dest: /etc/nginx/conf.d/devdemo.conf
        mode: "0644"
      notify: Reload nginx

    - name: Start nginx (a container has no init system to do it)
      ansible.builtin.command: nginx
      args:
        creates: /run/nginx.pid

  handlers:
    - name: Reload nginx
      ansible.builtin.command: nginx -s reload
      changed_when: true
EOF
    gen_file "$DIR/ansible/templates/index.html.j2" << 'EOF'
<!doctype html>
<title>dev-demo: {{ tool }}</title>
<h1>{{ web_message }}</h1>
<p>{{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }} container, nginx configured by {{ tool }} ({{ ansible_version.full }}).</p>
EOF
    gen_file "$DIR/ansible/templates/devdemo.conf.j2" << 'EOF'
# Managed by {{ tool }}: the bake-off's one site.
server {
    listen 80 default_server;
    root /var/www/devdemo;
    index index.html;
    add_header X-Configured-By "{{ tool }}" always;
}
EOF
    # --- Puppet: a class with two EPP templates, applied on the target (masterless) ---
    gen_file "$DIR/puppet/manifests/site.pp" << 'EOF'
# 'puppet apply' compiles this on the target itself: no server.
include devdemo_web
EOF
    gen_file "$DIR/puppet/modules/devdemo_web/manifests/init.pp" << 'EOF'
# The bake-off's web server, the Puppet way: resources and the order between them (the arrows). The Ansible and
# Chef versions build the same thing. FACTER_devdemo_message (a fact from the environment) changes the headline.
class devdemo_web (
  String $tool = 'Puppet',
) {
  $message = $facts['devdemo_message'] ? {
    undef   => "Configured by ${tool}",
    default => $facts['devdemo_message'],
  }
  $path = ['/usr/local/sbin', '/usr/local/bin', '/usr/sbin', '/usr/bin', '/sbin', '/bin']

  # Puppet's apt provider does not refresh the package lists, so this does, at most once an hour.
  exec { 'apt-get update':
    command  => 'apt-get update -qq && mkdir -p /var/lib/apt/periodic && touch /var/lib/apt/periodic/update-success-stamp',
    unless   => 'test -n "$(find /var/lib/apt/periodic/update-success-stamp -mmin -60 2> /dev/null)"',
    path     => $path,
    provider => shell,
  }
  -> package { 'nginx':
    ensure => installed,
  }
  -> file { '/etc/nginx/sites-enabled/default':
    ensure => absent,
  }
  -> file { '/var/www/devdemo':
    ensure => directory,
    mode   => '0755',
  }
  -> file { '/var/www/devdemo/index.html':
    ensure  => file,
    mode    => '0644',
    content => epp('devdemo_web/index.html.epp', { 'message' => $message, 'tool' => $tool }),
  }
  -> file { '/etc/nginx/conf.d/devdemo.conf':
    ensure  => file,
    mode    => '0644',
    content => epp('devdemo_web/devdemo.conf.epp', { 'tool' => $tool }),
  }
  # A container has no init system: nginx is started once, and reloaded when its site file changes.
  -> exec { 'start nginx':
    command => 'nginx',
    creates => '/run/nginx.pid',
    path    => $path,
  }
  exec { 'reload nginx':
    command     => 'nginx -s reload',
    refreshonly => true,
    path        => $path,
    subscribe   => File['/etc/nginx/conf.d/devdemo.conf'],
    require     => Exec['start nginx'],
  }
}
EOF
    gen_file "$DIR/puppet/modules/devdemo_web/templates/index.html.epp" << 'EOF'
<%- | String $message, String $tool | -%>
<!doctype html>
<title>dev-demo: <%= $tool %></title>
<h1><%= $message %></h1>
<p><%= $facts['os']['name'] %> <%= $facts['os']['release']['full'] %> container, nginx configured by <%= $tool %> (OpenVox <%= $facts['puppetversion'] %>).</p>
EOF
    gen_file "$DIR/puppet/modules/devdemo_web/templates/devdemo.conf.epp" << 'EOF'
<%- | String $tool | -%>
# Managed by <%= $tool %>: the bake-off's one site.
server {
    listen 80 default_server;
    root /var/www/devdemo;
    index index.html;
    add_header X-Configured-By "<%= $tool %>" always;
}
EOF
    # --- Chef: a cookbook with two ERB templates, converged on the target in local mode ---
    gen_file "$DIR/chef/client.rb" << 'EOF'
# Local mode (cinc-client -z): an in-memory server, cookbooks from the mounted folder, state on the target.
chef_repo_path '/var/lib/devdemo-chef'
cookbook_path ['/etc/devdemo/chef/cookbooks']
file_cache_path '/var/cache/devdemo-chef'
EOF
    gen_file "$DIR/chef/cookbooks/devdemo_web/metadata.rb" << 'EOF'
name 'devdemo_web'
maintainer 'dev-demo'
maintainer_email 'dev-demo@localhost'
license 'MIT'
description "The configuration management bake-off's web server"
version '1.0.0'
chef_version '>= 18'
supports 'debian'
EOF
    gen_file "$DIR/chef/cookbooks/devdemo_web/attributes/default.rb" << 'EOF'
# DEVDEMO_MESSAGE in the environment changes the headline.
default['devdemo_web']['tool'] = 'Chef'
default['devdemo_web']['message'] = ENV.fetch('DEVDEMO_MESSAGE', 'Configured by Chef')
EOF
    gen_file "$DIR/chef/cookbooks/devdemo_web/recipes/default.rb" << 'EOF'
# The bake-off's web server, the Chef way: Ruby, resources run top to bottom; notifications reload nginx when
# its site changes. The Ansible and Puppet versions build the same thing.
tool = node['devdemo_web']['tool']

# The package lists are refreshed at most once an hour.
apt_update 'package lists' do
  frequency 3600
  action :periodic
end

package 'nginx'

link '/etc/nginx/sites-enabled/default' do
  action :delete
end

directory '/var/www/devdemo' do
  mode '0755'
end

template '/var/www/devdemo/index.html' do
  source 'index.html.erb'
  mode '0644'
  variables(message: node['devdemo_web']['message'], tool: tool)
end

template '/etc/nginx/conf.d/devdemo.conf' do
  source 'devdemo.conf.erb'
  mode '0644'
  variables(tool: tool)
  notifies :run, 'execute[reload nginx]', :delayed
end

# A container has no init system: nginx is started once, and reloaded when its site file changes.
execute 'start nginx' do
  command 'nginx'
  creates '/run/nginx.pid'
end

execute 'reload nginx' do
  command 'nginx -s reload'
  action :nothing
end
EOF
    gen_file "$DIR/chef/cookbooks/devdemo_web/templates/index.html.erb" << 'EOF'
<!doctype html>
<title>dev-demo: <%= @tool %></title>
<h1><%= @message %></h1>
<p><%= node['platform'].capitalize %> <%= node['platform_version'] %> container, nginx configured by <%= @tool %> (Cinc Client <%= Chef::VERSION %>).</p>
EOF
    gen_file "$DIR/chef/cookbooks/devdemo_web/templates/devdemo.conf.erb" << 'EOF'
# Managed by <%= @tool %>: the bake-off's one site.
server {
    listen 80 default_server;
    root /var/www/devdemo;
    index index.html;
    add_header X-Configured-By "<%= @tool %>" always;
}
EOF
    # --- one audit for all three: an InSpec profile run by cinc-auditor over Docker ---
    gen_file "$DIR/audit/inspec.yml" << 'EOF'
name: cm-bakeoff-audit
title: The bake-off's web server, checked the same way whichever tool built it
version: 1.0.0
license: MIT
supports:
  - platform-family: debian
inputs:
  - name: tool
    type: String
    value: Ansible
EOF
    gen_file "$DIR/audit/controls/web.rb" << 'EOF'
# The same checks for every container; --input tool=Puppet (or Chef, Ansible) names the tool that built it.
tool = input('tool')

control 'web-01' do
  impact 1.0
  title 'nginx is installed'
  describe package('nginx') do
    it { should be_installed }
  end
end

control 'web-02' do
  impact 1.0
  title "Debian's default site is gone and the bake-off's site is in place"
  describe file('/etc/nginx/sites-enabled/default') do
    it { should_not exist }
  end
  describe file('/etc/nginx/conf.d/devdemo.conf') do
    its('content') { should match %r{root /var/www/devdemo;} }
  end
  describe command('nginx -t') do
    its('exit_status') { should eq 0 }
  end
end

control 'web-03' do
  impact 1.0
  title "nginx runs and serves the tool's page"
  describe processes(/nginx: master/) do
    its('entries.length') { should eq 1 }
  end
  describe command('curl -fsS http://localhost/') do
    its('stdout') { should match(/configured by #{tool}/) }
  end
  describe command('curl -fsSI http://localhost/') do
    its('stdout') { should match(/X-Configured-By: #{tool}/i) }
  end
end
EOF
    gen_file "$DIR/README.md" << 'EOF'
# Configuration management bake-off

One small web server (nginx, one site file, one page) built three ways, each in its own Debian 13 container:

| Tool    | Folder    | How it reaches the container                        | Page                  |
|---------|-----------|-----------------------------------------------------|-----------------------|
| Ansible | ansible/  | pushes from here over `docker exec` (community.docker) | http://localhost:8813 |
| Puppet  | puppet/   | OpenVox's agent in the container, `puppet apply`    | http://localhost:8811 |
| Chef    | chef/     | Cinc Client in the container, `cinc-client -z`      | http://localhost:8812 |

`audit/` is one InSpec profile that `cinc-auditor` runs against all three. `images/` holds the containers'
Dockerfiles (Python for Ansible, the agents for Puppet and Chef); the report does not time building them.

Run `../run-cm-bakeoff.sh` for the menu, or name an item: `../run-cm-bakeoff.sh idempotency`.
`CM_MESSAGE='Hello DC' ../run-cm-bakeoff.sh all` changes every page's headline. `../run-cm-bakeoff.sh down`
removes the containers; `docker rmi devdemo-cm-ansible devdemo-cm-puppet devdemo-cm-chef devdemo-cm-base` the images.
EOF
    FRESH=1
    write_run << 'EOF'
docker_ok
PATH="$PATH:/opt/puppetlabs/bin:/opt/cinc-workstation/bin"
export CHEF_LICENSE=accept-no-persist   # Cinc needs no license; this keeps any Progress-built tool from asking
# The tools that take part: the ones set up here (their agents run in the containers either way).
TOOLS=()
command -v ansible-playbook > /dev/null 2>&1 && TOOLS+=(ansible)
[ -x /opt/puppetlabs/bin/puppet ] && TOOLS+=(puppet)
[ -x /opt/cinc-workstation/bin/cinc-client ] && TOOLS+=(chef)
if [ "${1:-}" = down ]; then docker rm -f devdemo-cm-ansible devdemo-cm-puppet devdemo-cm-chef 2> /dev/null; exit 0; fi
[ ${#TOOLS[@]} -gt 0 ] || { echo "No tool to compare: dev-setup with install-puppet, install-chef or install-iac (Ansible)."; exit 1; }
port()  { case $1 in puppet) echo 8811 ;; chef) echo 8812 ;; ansible) echo 8813 ;; esac; }
label() { case $1 in puppet) echo Puppet ;; chef) echo Chef ;; ansible) echo Ansible ;; esac; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "devdemo-cm-$1" 2> /dev/null)" = true ]; }

build() {   # build NAME [ARG...]: one image from images/NAME; quiet once it exists (Docker's cache)
    if docker image inspect "devdemo-cm-$1" > /dev/null 2>&1; then
        docker build -q -t "devdemo-cm-$1" "${@:2}" "images/$1" > /dev/null
    else
        demo_step "docker build devdemo-cm-$1 (once; later runs reuse it)"
        docker build -t "devdemo-cm-$1" "${@:2}" "images/$1"
    fi
}
image() {
    build base || return 1
    if [ "$1" = puppet ]; then build puppet --build-arg "OPENVOX_MAJOR=${OPENVOX_MAJOR:-8}"; else build "$1"; fi
}
up() {   # up TOOL [fresh]: the tool's container, running. A stopped one is replaced (nginx's pid file would be stale).
    local t=$1 mount=()
    image "$t" || { echo "The $t image did not build."; return 1; }
    if [ "${2:-}" = fresh ] || ! running "$t"; then
        docker rm -f "devdemo-cm-$t" > /dev/null 2>&1
        [ "$t" = ansible ] || mount=(-v "$DEMO_DIR/$t:/etc/devdemo/$t:ro")
        docker run -d --name "devdemo-cm-$t" -p "$(port "$t"):80" "${mount[@]}" "devdemo-cm-$t" > /dev/null || return 1
    fi
}
apply() {   # apply TOOL [EXTRA...]: one run of the tool; CM_MESSAGE (if set) changes the headline. Returns the tool's code.
    local t=$1 env=(); shift
    case $t in
        ansible)
            [ -n "${CM_MESSAGE:-}" ] && env=(-e "$(python3 -c 'import json, sys; print(json.dumps({"web_message": sys.argv[1]}))' "$CM_MESSAGE")")
            ( cd ansible && ansible-playbook site.yml "${env[@]}" "$@" ) ;;
        puppet)
            [ -n "${CM_MESSAGE:-}" ] && env=(-e "FACTER_devdemo_message=$CM_MESSAGE")
            docker exec "${env[@]}" devdemo-cm-puppet puppet apply --detailed-exitcodes \
                --modulepath /etc/devdemo/puppet/modules /etc/devdemo/puppet/manifests/site.pp "$@" ;;
        chef)
            [ -n "${CM_MESSAGE:-}" ] && env=(-e "DEVDEMO_MESSAGE=$CM_MESSAGE")
            docker exec "${env[@]}" devdemo-cm-chef cinc-client -z -c /etc/devdemo/chef/client.rb -o 'recipe[devdemo_web]' "$@" ;;
    esac
}
okrc() { [ "$2" -eq 0 ] || { [ "$1" = puppet ] && [ "$2" -eq 2 ]; }; }   # Puppet's --detailed-exitcodes: 2 = changes made
converge() {   # converge TOOL: container up, one run shown, the page opened
    local t=$1 rc
    up "$t" || return 1
    demo_step "$(label "$t") -> devdemo-cm-$t"
    apply "$t"; rc=$?
    okrc "$t" "$rc" || { echo "$(label "$t") failed (exit $rc)."; return 1; }
    demo_wait_port "$(port "$t")" 20 && demo_open "http://localhost:$(port "$t")"
}
idem() {   # idem TOOL: run until converged, then once more: the second run must change nothing
    local t=$1 out rc same=1
    up "$t" || return 1
    apply "$t" > /dev/null 2>&1; rc=$?
    okrc "$t" "$rc" || { echo "  $(label "$t"): the first run failed (exit $rc); the '$t' item shows why"; return 1; }
    out=$(apply "$t" 2>&1); rc=$?
    case $t in
        puppet)  [ "$rc" -eq 0 ] || same=0 ;;                                       # 0 = no changes, 2 = changes
        chef)    grep -qE ' 0/[0-9]+ resources updated' <<< "$out" || same=0 ;;
        ansible) grep -qE 'changed=0 ' <<< "$out" || same=0 ;;
    esac
    if [ "$same" = 1 ]; then
        printf '  %-8s second run changed nothing\n' "$(label "$t")"
    else
        printf '  %-8s the second run changed something:\n' "$(label "$t")"; tail -n 15 <<< "$out"; return 1
    fi
}
loc() { find "$1" -type f -print0 | xargs -0 cat | grep -cvE '^[[:space:]]*(#|$)'; }   # lines, less blanks and comments
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
report() {   # each tool on a fresh container: first run (installs nginx), second run (nothing to do), lines of code
    local t t0 t1 t2 rc rows=()
    for t in "${TOOLS[@]}"; do
        demo_step "$(label "$t"): a fresh container, then two runs"
        up "$t" fresh || continue
        t0=$(date +%s.%N); apply "$t" > /dev/null 2>&1; rc=$?; t1=$(date +%s.%N)
        okrc "$t" "$rc" || { echo "  the first run failed (exit $rc)"; continue; }
        apply "$t" > /dev/null 2>&1; t2=$(date +%s.%N)
        rows+=("$(printf '%-8s %10s %11s %8s %6s' "$(label "$t")" "$(secs "$t0" "$t1")" "$(secs "$t1" "$t2")" "$(loc "$t")" "$(find "$t" -type f | wc -l)")")
    done
    echo
    printf '%-8s %10s %11s %8s %6s\n' tool "1st run s" "2nd run s" "lines" files
    printf '%s\n' "${rows[@]}"
    demo_note "Lines leave out blanks and comments, and count each tool's whole folder (config, templates)."
    demo_note "The first run includes apt and nginx; Puppet and Chef also start their Ruby agent in the container."
}
audit() {
    local t
    for t in "${TOOLS[@]}"; do
        demo_step "cinc-auditor exec audit -t docker://devdemo-cm-$t --input tool=$(label "$t")"
        running "$t" || { echo "  devdemo-cm-$t is not running: the '$t' or 'all' item starts it"; continue; }
        cinc-auditor exec audit -t "docker://devdemo-cm-$t" --input "tool=$(label "$t")" --no-distinct-exit
    done
}
noop() {   # dry runs with a new headline: what each tool would change, changing nothing
    local t
    read -rp "A headline to try (Enter for 'Hello DC'): " CM_MESSAGE || return 1
    CM_MESSAGE=${CM_MESSAGE:-Hello DC}
    for t in "${TOOLS[@]}"; do
        up "$t" || continue
        # A container never converged would show every change; converge it first, quietly.
        docker exec "devdemo-cm-$t" test -f /var/www/devdemo/index.html 2> /dev/null || CM_MESSAGE="" apply "$t" > /dev/null 2>&1
        case $t in
            ansible) demo_step "Ansible: --check --diff"; apply ansible --check --diff ;;
            puppet)  demo_step "Puppet: --noop --show_diff"; apply puppet --noop --show_diff ;;
            chef)    demo_step "Chef: --why-run"; apply chef --why-run ;;
        esac
    done
    demo_note "Nothing changed. To apply it: CM_MESSAGE='$CM_MESSAGE' $0 all"
    CM_MESSAGE=""
}
lint() {
    local t
    for t in "${TOOLS[@]}"; do
        case $t in
            ansible) if command -v ansible-lint > /dev/null 2>&1; then
                         demo_step "ansible-lint"; ( cd ansible && ansible-lint --offline site.yml ) && echo "ansible-lint: no issues"
                     fi ;;
            puppet)  demo_step "puppet parser validate + puppet epp validate"
                     puppet parser validate puppet/manifests/site.pp puppet/modules/devdemo_web/manifests/init.pp \
                         && puppet epp validate puppet/modules/devdemo_web/templates/*.epp && echo "puppet: no syntax errors" ;;
            chef)    demo_step "cookstyle"; cookstyle chef ;;
        esac
    done
}
ITEMS=()
for t in "${TOOLS[@]}"; do ITEMS+=("$t: $(label "$t") builds its container's web server (page on :$(port "$t"))"); done
ITEMS+=("all: every tool, one after another"
        "idempotency: run each tool again; the second run must change nothing"
        "report: fresh containers, timed first and second runs, lines of code per tool")
[ -x /opt/cinc-workstation/bin/cinc-auditor ] && ITEMS+=("audit: one InSpec profile (cinc-auditor) checks all three the same way")
ITEMS+=("noop: dry runs with a new headline (--check, --noop, --why-run)"
        "lint: ansible-lint, puppet parser validate, cookstyle"
        "down: remove the three containers (the images stay)")
demo_note "Taking part: ${TOOLS[*]}. Puppet and Chef run in their containers, Ansible pushes from here."
while demo_menu "Configuration management bake-off" "${ITEMS[@]}"; do
    case "$DEMO_CHOICE" in
        ansible:*|puppet:*|chef:*) converge "${DEMO_CHOICE%%:*}" ;;
        all:*)         for t in "${TOOLS[@]}"; do converge "$t"; done ;;
        idempotency:*) for t in "${TOOLS[@]}"; do idem "$t"; done ;;
        report:*)      report ;;
        audit:*)       audit ;;
        noop:*)        noop ;;
        lint:*)        lint ;;
        down:*)        docker rm -f devdemo-cm-ansible devdemo-cm-puppet devdemo-cm-chef 2> /dev/null ;;
    esac
    [ -n "${1:-}" ] && break
done
EOF
    done_demo
}

# The base demo belongs to "no flags"; demo-clean with install-* flags leaves it alone.
if [ "$CLEAN" != 1 ] || ! [[ "$FLAGS" =~ " install-" ]]; then demo_base; fi
has install-rust      && demo_rust
has install-go        && demo_go
has install-cpp       && demo_cpp
has install-asm       && demo_asm
has install-asm-arm   && demo_asm_arm
has install-dotnet    && demo_dotnet
has install-pwsh      && demo_pwsh
has install-java      && demo_java
has install-ruby      && demo_ruby
has install-lazarus   && demo_lazarus
has install-web       && demo_web
has install-drupal    && demo_drupal
has install-ldap      && demo_ldap
has install-tanstack  && demo_tanstack
has install-godot     && demo_godot
{ has install-mobile || has install-flutter; } && demo_flutter
{ has install-mobile || has install-rn; }      && demo_rn
{ has install-mobile || has install-tauri; }   && demo_tauri
has install-android-native && demo_android
has install-gemma     && demo_gemma
has install-models    && demo_models
has install-agentic   && demo_agentic
has install-lakehouse && demo_lakehouse
{ has install-db || has install-db-extra; }    && demo_db
{ has install-db || has install-interbase; }   && demo_firebird
{ has install-mssql || has install-oracle; }   && demo_dbservers
has install-k8s       && demo_k8s
has install-iac       && demo_iac
{ has install-ansible-full || has install-ansible-core; } && demo_ansible
{ has install-aws || has install-azure || has install-gcp || has install-vercel; } && demo_cloud
has install-media     && demo_media
has install-lan       && demo_lan
has install-com       && demo_com
has install-retro     && demo_retro
has install-hermes    && demo_hermes
has install-openclaw  && demo_openclaw
has install-laravel   && demo_laravel
has install-symfony   && demo_symfony
{ has install-redis || has install-mongodb || has install-solr || has install-opensearch || has install-elasticsearch \
    || has install-meilisearch || has install-typesense; } && demo_services
has install-agentic   && demo_fastmcp
has install-cloudflare && demo_cloudflare
has install-graphql   && demo_graphql
{ has install-playwright || has install-selenium || has install-bdd || has install-robot || has install-cypress; } && demo_testing
has install-bdd       && demo_drupal_behat
has install-vue       && demo_vue
has install-vue       && demo_drupal_nuxt
has install-gitlab    && demo_gitlab
{ has install-puppet || has install-chef; } && demo_cm

# Flags with nothing to download: say why, so their absence is not a surprise.
has install-node        && note "install-node: Claude Code, Codex, Gemini CLI and aider need your keys; point them at any demo folder."
has install-ollama && ! has install-models && note "install-ollama: the server alone has no demo; add install-models (local-rag, compare) or install-gemma."
has install-jev         && note "install-jev: Jev is a hosted model (needs TYPESAFE_API_KEY); its SDKs are per project."
has install-antigravity && note "install-antigravity / install-vscode / install-cursor / install-windsurf: open ~/dev-demo/dev-demo.code-workspace."
{ has install-vscode || has install-cursor || has install-windsurf; } && ! has install-antigravity \
                        && note "Editors: open ~/dev-demo/dev-demo.code-workspace to browse every demo."
has install-drupal      && note "install-drupal: Terminus, acli and the Upsun CLI need platform tokens, so the demos are Drupal CMS and the Drupal RAG site in DDEV."
has install-drupal      && note "drupal/drupal-rag needs the models from install-models and Ollama opened to containers (install-ollama-containers); its launcher checks both."
has install-interbase && [ ! -x /opt/interbase/bin/isql ] && note "install-interbase: InterBase is not installed yet (put the download in ./assets and rerun dev-setup); db/firebird adds its menu item once it is."
has install-mssql && ! has install-db && ! has install-db-extra && note "install-mssql: Chinook on SQL Server lives in db/chinook, which comes with install-db or install-db-extra."
has install-ldap        && note "install-ldap: the directories themselves need no demo ('ldap status', 'ldap search', 'ldap ui'); drupal/drupal-ldap logs Drupal users in from them."
has install-godot-templates && note "install-godot-templates: export any Godot demo from its editor (Project > Export)."
# v89: flags whose demos live elsewhere, or that have none
has install-memcached   && note "install-memcached: web/drupal-umami's 'memcache' item puts Drupal's cache in it; 'devsvc cli memcached' talks to it directly."
{ has install-vector || has install-qdrant; } && note "install-vector: models/local-rag's 'store' item keeps its vectors in sqlite-vec or Qdrant (and Redis, Milvus Lite, Atlas Local)."
has install-milvus      && note "install-milvus: the server has no demo of its own (it asks for 8 GB); models/local-rag uses Milvus Lite, the same API in a file."
has install-mongodb-atlas-local && note "install-mongodb-atlas-local: models/local-rag's 'store' item uses its Vector Search; 'devsvc cli atlas-local' opens mongosh."
has install-cloudflared && ! has install-cloudflare && note "install-cloudflared: its quick-tunnel item is in cloud/cloudflare, which comes with install-cloudflare (install-cloud)."
# v91: the test tools
has install-selenium    && note "install-selenium: testing/e2e-bakeoff's 'grid' item runs its Selenium test through the shared Grid, watched in noVNC; drupal/drupal-behat uses DDEV's own Selenium add-on."
has install-gitlab-runner && note "install-gitlab-runner: gitlab/ci-local's 'runner' item shows the runner; register it with GITLAB_RUNNER_TOKEN_ONCE and dev-init."
has install-cypress     && note "install-cypress: Cypress joins testing/e2e-bakeoff (its first run downloads Cypress's ~250 MB Electron build)."
{ has install-puppet || has install-chef; } && ! has install-ansible-full && ! has install-ansible-core \
                        && note "install-puppet / install-chef: iac/cm-bakeoff compares Ansible too once it is here (install-iac or install-ansible-core)."
has install-lan-share  && note "install-lan-share: sharing needs no demo of its own ('lan share', 'lan scan' from another laptop); net/mcp-hello is the MCP part, and models/compare 'remote' runs on another laptop's Ollama."

# =================================================================
# SUMMARY
# =================================================================
write_index
echo
echo "================================================================="
if [ "$CLEAN" = 1 ]; then
    echo "Demo clean (Version $VERSION) complete."
else
    echo "Demo Version $VERSION complete: ${GRN}ready ${#READY[@]}${RST}   ${YEL}skipped ${#SKIPPED[@]}${RST}   ${RED}failed ${#FAILED[@]}${RST}"
    [ ${#SKIPPED[@]} -gt 0 ] && { echo; echo "Skipped (tool not installed):"; printf '  - %s\n' "${SKIPPED[@]}"; }
    [ ${#FAILED[@]} -gt 0 ]  && { echo; echo "Failed (network? rerun later; the log has details):"; printf '  - %s\n' "${FAILED[@]}"; }
    [ ${#NOTES[@]} -gt 0 ]   && { echo; echo "Notes:"; printf '  - %s\n' "${NOTES[@]}"; }
    echo
    echo "Start here: ~/dev-demo/README.md lists every demo and its launcher, e.g."
    echo "  ~/dev-demo/base/run-voting-app.sh"
    echo "Run one heavy demo at a time (Gemma, local models, the Drupal RAG site, Langfuse, SQL Server, Oracle, kind, Android/Tauri builds)."
fi
echo "Log: $LOG"
echo "================================================================="
[ ${#FAILED[@]} -eq 0 ]
