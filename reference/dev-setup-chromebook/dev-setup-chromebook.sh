#!/bin/bash
# dev-setup-chromebook - Version 93
# Version history: CHANGELOG.md, next to this script in the bundle
# (one section per script, newest version first).

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

# Exit script immediately on any error
set -e

# v65: everything these scripts write for you to keep or look at lives in ./assets next to the
# scripts, never loose in the home directory: assets/logs (test logs), assets/downloads (installer
# downloads that are worth resuming) and assets/gemma_client.py. Anchored on the script's own
# location, so running it from another directory does not scatter a second assets folder.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd || true)"
[ -n "$SCRIPT_DIR" ] || SCRIPT_DIR="$PWD"
export ASSETS="$SCRIPT_DIR/assets"
mkdir -p "$ASSETS/logs" "$ASSETS/downloads"

# v93: a connection timeout for every wget and curl this run starts, setup's own and those of the installers
# it runs (they inherit the environment): a dead address now fails in 20 seconds and the next address is
# tried, instead of hanging for minutes (Oct 4 2026: Chrome's download waited on one IPv6 address after
# another). Your own ~/.wgetrc and ~/.curlrc are copied in first, so their settings still apply. The files
# live in ~/.cache/dev-setup, rewritten each run, and only this run points at them; it covers the connect
# step only, so a slow large download is not cut off. 'sudo wget' and 'sudo curl' do not see them.
DEV_NET_DIR="$HOME/.cache/dev-setup"
mkdir -p "$DEV_NET_DIR/curl"
{ cat "$HOME/.wgetrc" 2> /dev/null || true; echo; echo "connect_timeout = 20"; } > "$DEV_NET_DIR/wgetrc"
{ cat "$HOME/.curlrc" 2> /dev/null || true; echo; echo "connect-timeout = 20"; } > "$DEV_NET_DIR/curl/.curlrc"
export WGETRC="$DEV_NET_DIR/wgetrc" CURL_HOME="$DEV_NET_DIR/curl"

# v62: Homebrew's default "ask mode" stops for [y/n] whenever a formula pulls in dependencies.
# This is an unattended installer, so turn it off for every brew call below. Exported here only,
# so brew run by hand in your own shell still asks. NO_ENV_HINTS drops the "Adjust how often
# this is run..." lines from the log.
export HOMEBREW_NO_ASK=1
export HOMEBREW_NO_ENV_HINTS=1

# =================================================================
# FLAG EXPANSION (STACK SWITCHES)
# =================================================================
FLAGS=" $* "

echo "Active Installation Flags: $FLAGS"

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

# v85: COM development under Wine (install-com) and DOS / Windows 3.x development (install-retro): both
# opt-in, in no group, NOT in install-all. install-retro's Win16 tests and the Delphi 1 quick route run
# on Wine, so it pulls in install-com.
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

echo "Starting comprehensive Chromebook Linux provisioning (Version 93)..."

# v93: prefer IPv4 when this network's IPv6 does not get out. On Oct 4 2026 a Chromebook's Linux got IPv6
# addresses for dl.google.com but no IPv6 route out, and wget hung on one address after another (the
# ChromeOS browser raced IPv4 and IPv6, so it worked). The fix that worked there, now automatic: one line
# in /etc/gai.conf makes every program try IPv4 addresses first (IPv6 stays on, and is used where IPv4 is
# missing), and apt is told to use IPv4. The check: dl.google.com over IPv6 does not connect within 6 s
# while IPv4 does. Applied once and kept; already there (by hand, as on Oct 4) = nothing to do.
# DEV_PREFER_IPV4=1 applies it without the check, DEV_PREFER_IPV4=0 skips it (default: auto).
DEV_GAI_LINE='precedence ::ffff:0:0/96  100'
DEV_APT_V4=/etc/apt/apt.conf.d/99force-ipv4
dev_tcp() { timeout 6 bash -c 'exec 3<> "/dev/tcp/$0/443"' "$1" 2> /dev/null; }   # dev_tcp ADDRESS: port 443 answers
if grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' /etc/gai.conf 2> /dev/null; then
    [ -f "$DEV_APT_V4" ] || echo 'Acquire::ForceIPv4 "true";' | sudo tee "$DEV_APT_V4" > /dev/null
    echo "Network: IPv4 is preferred already (/etc/gai.conf, $DEV_APT_V4)."
elif [ "${DEV_PREFER_IPV4:-auto}" = 0 ]; then
    echo "Network: DEV_PREFER_IPV4=0: the IPv6 check is skipped."
else
    DEV_V6=$(getent ahostsv6 dl.google.com 2> /dev/null | awk '$1 ~ /:/ && $1 !~ /^::ffff:/ { print $1; exit }')
    DEV_V4=$(getent ahostsv4 dl.google.com 2> /dev/null | awk '{ print $1; exit }')
    DEV_V6_WHY=""
    if [ "${DEV_PREFER_IPV4:-auto}" = 1 ]; then
        DEV_V6_WHY="DEV_PREFER_IPV4=1"
    elif [ -n "$DEV_V6" ] && ! dev_tcp "$DEV_V6"; then
        if [ -n "$DEV_V4" ] && dev_tcp "$DEV_V4"; then
            DEV_V6_WHY="dl.google.com does not answer over IPv6 ($DEV_V6) but does over IPv4"
        else
            DEV_V6_OFF=1
        fi
    fi
    if [ "${DEV_V6_OFF:-0}" = 1 ]; then
        echo "Network: dl.google.com answered over neither IPv6 nor IPv4 (offline?); the IPv6 check could not tell, nothing changed."
    elif [ -n "$DEV_V6_WHY" ]; then
        echo "$DEV_GAI_LINE" | sudo tee -a /etc/gai.conf > /dev/null
        echo 'Acquire::ForceIPv4 "true";' | sudo tee "$DEV_APT_V4" > /dev/null
        echo "Network: IPv4 preferred from now on ($DEV_V6_WHY): a line in /etc/gai.conf and $DEV_APT_V4."
        echo "         IPv6 stays on; delete both to undo once your network's IPv6 works."
    elif [ -n "$DEV_V6" ]; then
        echo "Network: IPv6 works here; nothing changed."
    fi
fi

# 1. System Setup, Base Packages & Headless Dependencies
echo "Updating system and installing base packages, Python tools, and Puppeteer dependencies..."
# Public release: 'passwd -d' leaves the Linux user with no password. It is here for ChromeOS's Linux,
# where sudo asks for none; on any other machine (DEV_BUNDLE_ANY_HOST=1) it would delete a real login
# password, so it runs on ChromeOS only (DEV_ON_CHROMEOS comes from the host guard above).
if [ "${DEV_ON_CHROMEOS:-0}" = 1 ]; then sudo passwd -d "$USER"; fi
sudo apt update && sudo apt upgrade -y

# Consolidated apt install (Debian Trixie Compatible - PEP 668 & no software-properties-common)
sudo apt install -y \
  apt-file apt-transport-https build-essential ca-certificates \
  dpkg git gnupg gnupg2 libnss3-tools lsb-release nano php-cli \
  tree wget zip unzip curl file libfuse2 \
  pipx python3-venv python3-pip ffmpeg libmagic1 x11-utils \
  fonts-liberation libappindicator3-1 libasound2 libatk-bridge2.0-0 \
  libatk1.0-0 libcups2 libdbus-1-3 libdrm2 libgbm1 libnspr4 libnss3 \
  libxcomposite1 libxdamage1 libxfixes3 libxkbcommon0 libxrandr2 xdg-utils \
  libx11-dev libxkbcommon-dev libwayland-dev libdbus-1-dev \
  libxcb-shape0-dev libxcb-xfixes0-dev libgtk-3-dev libwebkit2gtk-4.1-dev \
  librsvg2-dev \
  jq shellcheck direnv htop sqlite3 postgresql-client
# v58: jq (JSON from the shell), shellcheck (these scripts), direnv (per-project env), htop,
#      and the sqlite3/psql CLIs to go with the ODBC drivers and client libs in install-db*.
# v52: librsvg2-dev is a Tauri Linux prerequisite ('tauri build' icon/bundle generation);
#      'tauri info' reported it missing. libfuse2 resolves to libfuse2t64 on trixie via Provides.

# 2. Python Tooling Initialization
echo "Configuring Python tools (pipx & uv)..."
pipx ensurepath
export PATH="$HOME/.local/bin:$PATH"
pipx install uv || true

# v58: direnv loads a project's .envrc on cd (per-project env on top of the global secrets.env).
if ! grep -q 'direnv hook bash' ~/.bashrc; then
    echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
fi

# 3. SSH Key Generation (Modern Ed25519)
echo "Generating SSH key..."
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "$USER@chromebook" -N "" -f ~/.ssh/id_ed25519
else
    echo "SSH key already exists, skipping generation."
fi

# 4. Docker Installation
echo "Installing Docker..."
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
# v69: GPU access. Crostini hands the container a virgl GPU as /dev/dri/card0 (group video) and
# /dev/dri/renderD128 (group render, mode 0660). Windowed OpenGL clients open the RENDER node, and
# the default user is only in 'video', so without this they silently fall back to llvmpipe
# (software): Godot, Flutter desktop, Android Studio's previews, Chrome's WebGL. Group changes
# apply to new logins: shut Linux down (right-click Terminal > Shut down Linux) and reopen it.
for grp in video render; do
    if getent group "$grp" > /dev/null; then sudo usermod -aG "$grp" "$USER"; fi
done

# 5. Homebrew, DDEV, and GitHub CLI
echo "Installing Homebrew and brew packages..."
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    echo "Homebrew already installed, skipping installer."
else
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# v68: Homebrew AFTER the system directories. shellenv prepends linuxbrew/bin, which let formula
# dependencies (python3, sqlite3, as, ld, java...) shadow Debian's tools. The block below still
# evals shellenv for HOMEBREW_PREFIX, MANPATH and INFOPATH, then moves Homebrew's bin and sbin to
# the end of PATH. It replaces the bare eval line older versions wrote, and is rewritten on every
# run. 'brew doctor' will note that /usr/bin comes first: that is the intent.
# v74: written IN PLACE. v68-v73 deleted the block and appended it at the end of ~/.bashrc on every
# run, which moved it below lines added earlier that need Homebrew tools, e.g. the kubectl
# completion line, and a new terminal printed "kubectl: command not found". Now the block
# replaces itself (or the bare eval line older versions wrote) where it stands, and is only
# appended when neither exists. A block that an earlier version already moved below such lines
# is moved back up by the kubectl step, which also stops needing it (see install-k8s).
BREW_BLOCK_FILE=$(mktemp)
cat > "$BREW_BLOCK_FILE" << 'EOF'
# >>> dev-setup homebrew >>>
# Written by dev-setup; this block is replaced on each run. Homebrew's directories go to the END
# of PATH so Debian's python3, sqlite3, java, binutils... win over copies Homebrew pulls in as
# dependencies. Tools that exist only in Homebrew (gh, ddev, aws, az, terraform, kubectl...) are
# unaffected. To prefer a Homebrew copy of something, call it by full path or alias it.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    _dev_setup_path=
    _dev_setup_ifs=$IFS; IFS=:
    for _dev_setup_p in $PATH; do
        case "$_dev_setup_p" in
            /home/linuxbrew/.linuxbrew/bin|/home/linuxbrew/.linuxbrew/sbin|"") ;;
            *) _dev_setup_path="${_dev_setup_path:+$_dev_setup_path:}$_dev_setup_p" ;;
        esac
    done
    IFS=$_dev_setup_ifs
    PATH="$_dev_setup_path:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin"
    unset _dev_setup_path _dev_setup_p _dev_setup_ifs
fi
# <<< dev-setup homebrew <<<
EOF
awk -v blockfile="$BREW_BLOCK_FILE" '
    function emit() { if (!done) { while ((getline l < blockfile) > 0) print l; close(blockfile); done = 1 } }
    /^# >>> dev-setup homebrew >>>$/ { emit(); skip = 1; next }
    skip && /^# <<< dev-setup homebrew <<<$/ { skip = 0; next }
    skip { next }
    $0 == "eval \"$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\"" { emit(); next }
    { print }
    END { if (!done) { while ((getline l < blockfile) > 0) print l } }
' ~/.bashrc > ~/.bashrc.dev-setup.tmp && cat ~/.bashrc.dev-setup.tmp > ~/.bashrc
rm -f ~/.bashrc.dev-setup.tmp "$BREW_BLOCK_FILE"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew_after_system() {   # v68: move Homebrew's bin/sbin to the END of PATH (see the note in dev-setup)
    local p parts out=""
    IFS=: read -ra parts <<< "$PATH"
    for p in "${parts[@]}"; do
        case "$p" in /home/linuxbrew/.linuxbrew/bin|/home/linuxbrew/.linuxbrew/sbin|"") ;; *) out="${out:+$out:}$p" ;; esac
    done
    PATH="$out:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin"
}
brew_after_system

brew install gcc ddev/ddev/ddev gh mkcert
mkcert -install

# 6. Google Chrome (Unconditional)
echo "Installing Google Chrome..."
# v65: downloaded into assets/downloads, not the current directory. Always fetched fresh (-nc would
# reinstall a stale .deb left by an interrupted run).
rm -f "$ASSETS/downloads/google-chrome-stable_current_amd64.deb"
wget -P "$ASSETS/downloads" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y "$ASSETS/downloads/google-chrome-stable_current_amd64.deb"
rm -f "$ASSETS/downloads/google-chrome-stable_current_amd64.deb"

# =================================================================
# SHARED HELPERS
# =================================================================
# v93: a .tar.gz download that is checked before it is unpacked. On Oct 4 2026 dragonair's PowerShell
# download arrived as something that was not gzip (most likely an error page served as the file); tar
# failed and, under set -e, the run stopped, so Ruby, C/C++, assembly, .NET and Java were never installed.
# fetch_tgz downloads into assets/downloads, tests the file with gzip -t, and tries once more; on a second
# failure it says what arrived (size, type, first lines), keeps the file for a look, and returns 1, so the
# caller skips that one tool and the run goes on. DL_FAILED collects what was skipped for the summary.
DL_FAILED=()
fetch_tgz() {   # fetch_tgz URL FILE
    local url=$1 out=$2 try rc
    for try in 1 2; do
        rm -f "$out"
        wget -q --tries=3 -O "$out" "$url"; rc=$?
        if [ "$rc" = 0 ] && gzip -t "$out" 2> /dev/null; then return 0; fi
        if [ "$try" = 1 ]; then
            if [ "$rc" = 0 ]; then echo "$(basename "$out"): the download is not a valid .tar.gz; trying once more..."
            else echo "$(basename "$out"): the download failed (wget exit $rc); trying once more..."; fi
            sleep 5
        fi
    done
    echo "NOTICE: $(basename "$out") could not be downloaded from $url"
    if [ "$rc" != 0 ]; then
        echo "        wget exit $rc (4 = network failure, 5 = TLS, 8 = the server answered with an error)."
    fi
    if [ -s "$out" ]; then
        echo "        What arrived ($(stat -c %s "$out") bytes, $(file -b "$out" 2> /dev/null | cut -c1-60)), kept in $out; it begins:"
        head -c 400 "$out" | tr -c '[:print:]\n' ' ' | head -n 5 | sed 's/^/          | /'
    fi
    return 1
}
# v63: Microsoft's Debian "prod" feed serves both msodbcsql18 (install-db) and dotnet-sdk-10.0
# (install-dotnet). Use Microsoft's config package so the keyring and source list always match,
# and pick the repo for the Debian release actually running (12=bookworm, 13=trixie).
# Runs at most once per installer run.
MS_PROD_REPO_DONE=0
add_microsoft_prod_repo() {
    [ "$MS_PROD_REPO_DONE" = 1 ] && return 0
    echo "Adding Microsoft Debian package repository (packages-microsoft-prod)..."
    local debian_major
    debian_major=$(. /etc/os-release && echo "$VERSION_ID")
    sudo rm -f /etc/apt/sources.list.d/mssql-release.list   # clean up the broken list from earlier versions
    curl -fsSL "https://packages.microsoft.com/config/debian/${debian_major}/packages-microsoft-prod.deb" -o /tmp/packages-microsoft-prod.deb
    sudo dpkg -i /tmp/packages-microsoft-prod.deb
    rm -f /tmp/packages-microsoft-prod.deb
    sudo apt update
    MS_PROD_REPO_DONE=1
}

# v65: corepack provides pnpm/yarn shims that fetch the version a project pins in package.json;
# Node 25+ no longer bundles it, hence the npm fallback. install-web and install-tanstack both
# need it. Must run after the Node section (both flags pull in install-node). At most once per run.
COREPACK_DONE=0
enable_corepack() {
    [ "$COREPACK_DONE" = 1 ] && return 0
    command -v corepack > /dev/null 2>&1 || npm install -g corepack
    corepack enable
    if ! grep -q 'COREPACK_ENABLE_DOWNLOAD_PROMPT' ~/.bashrc; then
        echo 'export COREPACK_ENABLE_DOWNLOAD_PROMPT=0   # let the pnpm/yarn shims fetch without asking' >> ~/.bashrc
    fi
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    COREPACK_DONE=1
}

# v68: every venv is built from Debian's interpreter, whatever 'python3' on PATH happens to be.
# Reruns after the cloud CLIs were installed used to pick up Homebrew's python3 (3.14), which
# ties the venv to a keg Homebrew will remove when it moves to the next Python. A venv whose
# pyvenv.cfg does not name /usr/bin is rebuilt once with --clear; the caller's pip installs
# repopulate it (so that run re-downloads its packages, torch included).
make_venv() {   # make_venv DIR
    local dir="$1"
    if [ -f "$dir/pyvenv.cfg" ] && ! grep -q '^home = /usr/bin$' "$dir/pyvenv.cfg"; then
        echo "Rebuilding $dir: it was created from $(sed -n 's/^home = //p' "$dir/pyvenv.cfg"), not Debian's /usr/bin/python3."
        /usr/bin/python3 -m venv --clear "$dir"
    else
        /usr/bin/python3 -m venv "$dir"
    fi
}

# v64: Homebrew's openjdk arrives as a dependency of gradle and kotlin and, on Linux, links its
# java/javac/jar ahead of Debian's. Unlink it so PATH and JAVA_HOME name the same JDK. The keg
# stays installed (the formulas that depend on it find it under opt/), and Homebrew leaves an
# unlinked keg unlinked across 'brew upgrade'. Safe to call when openjdk is absent or already
# unlinked.
unlink_brew_openjdk() {
    if brew list --formula openjdk > /dev/null 2>&1; then
        brew unlink openjdk > /dev/null 2>&1 || true
    fi
    hash -r
    case "$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)" in
        /usr/lib/jvm/*|"") ;;
        *) echo "WARNING: 'java' on PATH is still not Debian's JDK: $(command -v java)" ;;
    esac
}

# v63: the JDK used to arrive only with the Android stacks. install-java needs the same JDK and the
# same JAVA_HOME line, so both call this. /usr/lib/jvm/default-java is Debian's stable symlink to
# whatever default-jdk installed (21 on trixie; trixie dropped openjdk-17), so it survives JDK
# upgrades; fall back to resolving javac if it's somehow missing. Runs at most once per run.
# v82: install-oracle calls it too (SQLcl runs on Java 17 or 21).
JDK_DONE=0
install_jdk_and_java_home() {
    [ "$JDK_DONE" = 1 ] && return 0
    sudo apt install -y default-jdk
    if [ -d /usr/lib/jvm/default-java ]; then
        JAVA_DIR=/usr/lib/jvm/default-java
    else
        JAVA_DIR=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
    fi
    if [ ! -x "$JAVA_DIR/bin/javac" ]; then
        echo "ERROR: could not resolve JAVA_HOME ('$JAVA_DIR')."
        exit 1
    fi
    export JAVA_HOME="$JAVA_DIR"
    if ! grep -q 'export JAVA_HOME' ~/.bashrc; then
        echo "export JAVA_HOME=\"$JAVA_DIR\"" >> ~/.bashrc
    fi
    JDK_DONE=1
}

# v92: how much disk a guard keeps free: min(CAP, 15% of the Linux disk), in whole GB. v91 kept a flat
# 10 GB, which on a 25 GB disk with 12 GB free refused SQL Server and Oracle without saying so where you
# would look. 15% of 25 GB is about 4 GB; on an 80 GB disk the cap (10) applies as before. The DEV_*_MIN_FREE_GB
# variables still override it.
disk_margin_gb() {   # disk_margin_gb CAP
    local total pct
    total=$(df -Pk / | awk 'NR == 2 {print int($2 / 1024 / 1024)}')
    pct=$(( ${total:-0} * 15 / 100 ))
    [ "$pct" -ge 1 ] || pct=1
    [ "$pct" -lt "$1" ] && echo "$pct" || echo "$1"
}
disk_free_gb() { df -Pk / | awk 'NR == 2 {print int($4 / 1024 / 1024)}'; }

# v77: shared by install-ollama, install-gemma and install-models. The systemd unit normally has the
# server up already (give a just-restarted one a few seconds); without systemd, start it in the
# background for the rest of this run.
ensure_ollama_server() {
    local _
    for _ in $(seq 1 10); do ollama list > /dev/null 2>&1 && return 0; sleep 1; done
    (ollama serve > /dev/null 2>&1 &)
    for _ in $(seq 1 15); do ollama list > /dev/null 2>&1 && return 0; sleep 1; done
    return 1
}

# =================================================================
# CONDITIONAL INSTALLATIONS
# =================================================================

# Rust Toolchain
if [[ "$FLAGS" =~ " install-rust " ]]; then
    echo "Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$HOME/.cargo/bin:$PATH"
    if ! grep -q 'export PATH="$HOME/.cargo/bin:$PATH"' ~/.bashrc; then
        echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    fi
    echo "Adding WebAssembly (WASM) build targets and wasm-pack..."
    rustup target add wasm32-unknown-unknown
    # v62: -f overwrites an existing ~/.cargo/bin/wasm-pack without the [y/N] prompt, so a rerun
    # still upgrades it but no longer waits for input.
    curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh -s -- -f
else
    echo "Skipping Rust toolchain. (Run with 'install-rust' flag to enable)"
fi

# Go (Golang) Toolchain
if [[ "$FLAGS" =~ " install-go " ]]; then
    echo "Installing Latest Go (Golang) Toolchain..."
    # v93: a failed lookup or download skips Go (a NOTICE, and the summary names it) instead of stopping the
    # run; the download is checked before the old /usr/local/go is removed, so a bad one leaves Go as it was.
    GO_LATEST_VERSION=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n 1 || true)
    if [[ ! "$GO_LATEST_VERSION" =~ ^go[0-9] ]]; then
        echo "NOTICE: could not read the latest Go version from go.dev (network?); Go skipped this run."
        DL_FAILED+=("Go (install-go)")
    else
        echo "Downloading ${GO_LATEST_VERSION}..."
        if fetch_tgz "https://go.dev/dl/${GO_LATEST_VERSION}.linux-amd64.tar.gz" "$ASSETS/downloads/go.tar.gz"; then
            sudo rm -rf /usr/local/go
            sudo tar -C /usr/local -xzf "$ASSETS/downloads/go.tar.gz"
            rm -f "$ASSETS/downloads/go.tar.gz"

            export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
            if ! grep -q 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"' ~/.bashrc; then
                echo 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"' >> ~/.bashrc
            fi
            echo "Go installed successfully! (Version: ${GO_LATEST_VERSION})"
        else
            echo "        Go skipped this run$( [ -x /usr/local/go/bin/go ] && echo "; the Go already in /usr/local/go is left as it was")."
            DL_FAILED+=("Go (install-go)")
        fi
    fi
else
    echo "Skipping Go toolchain. (Run with 'install-go' flag to enable)"
fi

# Node.js (via NVM) & AI Coding Agents
if [[ "$FLAGS" =~ " install-node " ]]; then
    echo "Installing NVM, Node.js, Claude Code, Codex, Gemini CLI, and aider..."
    # Alternatives deliberately not installed: fnm (a faster nvm drop-in) and bun (runtime +
    # package manager). Both would change the shell setup the test and init scripts reproduce.
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
    if [ -d "$HOME/.config/nvm" ]; then
        export NVM_DIR="$HOME/.config/nvm"
    else
        export NVM_DIR="$HOME/.nvm"
    fi
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    # v65: global npm packages live inside one Node version. When the LTS line moves, the install
    # below switches this run to the new Node while nvm's 'default' alias (set once, on the first
    # install) keeps new terminals on the old one: globals installed from here on would be
    # missing there, and the old globals missing here. So carry the globals over and point the
    # default alias at lts/*. All best-effort: a failure leaves the pre-v65 behaviour.
    PREV_NODE=$(nvm current 2>/dev/null || true)
    nvm install --lts
    NEW_NODE=$(nvm current 2>/dev/null || true)
    case "$PREV_NODE" in
        v*)
            if [ -n "$NEW_NODE" ] && [ "$PREV_NODE" != "$NEW_NODE" ]; then
                echo "Node moved $PREV_NODE -> $NEW_NODE: carrying global npm packages over..."
                ( set +e; nvm reinstall-packages "$PREV_NODE" ) || true
            fi
            ;;
    esac
    nvm alias default 'lts/*' > /dev/null 2>&1 || true
    # v86: 'nvm reinstall-packages' carries OpenClaw over without its allowed install scripts (npm 12
    # blocks them), which leaves it broken on the new Node; reinstall it the way install-openclaw does.
    # (With install-openclaw on this run, its own section below does it.)
    if [ -n "$NEW_NODE" ] && [ "$PREV_NODE" != "$NEW_NODE" ] && [[ ! "$FLAGS" =~ " install-openclaw " ]] \
        && npm ls -g --depth=0 openclaw > /dev/null 2>&1; then
        npm install -g --allow-scripts=openclaw,koffi,protobufjs openclaw@latest || echo "NOTICE: rerun setup with install-openclaw to repair OpenClaw on $NEW_NODE."
    fi
    # v58: Gemini CLI next to Codex (both npm). It signs in with a Google account on first run,
    # or uses the GEMINI_API_KEY that dev-init exports.
    # v62: npm 12 blocks dependency install scripts unless the package is allowed (npm 11.16+ only
    # warns), and 'npm approve-scripts' refuses global installs, so allow them on the command line.
    # node-pty and keytar are the native modules these CLIs build (terminal emulation, keychain).
    # The list is by name: if a later release adds another native dependency, npm's
    # "install-scripts" warning at the end of this step names it; add it here.
    npm install -g --allow-scripts=@github/keytar,node-pty @openai/codex @google/gemini-cli
    # v58: aider, a model-agnostic terminal coding agent. It reads ANTHROPIC_API_KEY / OPENAI_API_KEY /
    # GEMINI_API_KEY, or talks to local Ollama.
    # v59: aider's pipx route only supports Python 3.9-3.12 and trixie ships 3.13, so use the route
    # aider itself recommends: uv (installed via pipx in the base section) fetches a managed 3.12 and
    # puts 'aider' in ~/.local/bin, same place pipx would. No '|| true': the test script treats a
    # missing aider as FAIL, so the installer must fail loudly too.
    uv tool install --force --python 3.12 --with pip aider-chat@latest

    # v51: the npm package for Claude Code is deprecated (and now needs Node 22+). The native
    # installer needs no Node at all and self-updates; it lands in ~/.local/bin (already on PATH).
    # Remove any npm-global copy left by earlier script versions first, or 'claude' will warn
    # about multiple installations and may keep running the stale one.
    npm uninstall -g @anthropic-ai/claude-code > /dev/null 2>&1 || true
    echo "Installing Claude Code (native installer)..."
    curl -fsSL https://claude.ai/install.sh | bash

    # Puppeteer: use the system Google Chrome (installed unconditionally above) instead of
    # downloading a ~300MB Chromium into ~/.cache/puppeteer for every project.
    if ! grep -q 'PUPPETEER_EXECUTABLE_PATH' ~/.bashrc; then
        echo 'export PUPPETEER_SKIP_DOWNLOAD=true' >> ~/.bashrc
        echo 'export PUPPETEER_EXECUTABLE_PATH="/usr/bin/google-chrome-stable"' >> ~/.bashrc
    fi
    export PUPPETEER_SKIP_DOWNLOAD=true
    export PUPPETEER_EXECUTABLE_PATH="/usr/bin/google-chrome-stable"
else
    echo "Skipping Node.js & AI agents. (Run with 'install-node' flag to enable)"
fi

# Web tooling: Angular CLI, corepack (pnpm/yarn shims), Composer (added in v58)
if [[ "$FLAGS" =~ " install-web " ]]; then
    echo "Installing web tooling (Angular CLI, corepack, Composer)..."
    # Node is guaranteed by the dependency guard. v65: corepack is enable_corepack() (shared with
    # install-tanstack).
    enable_corepack
    npm install -g @angular/cli
    ng analytics disable --global > /dev/null 2>&1 || true
    # Composer for host-side Drupal/PHP work (ddev runs its own copy inside the web container).
    # Debian's package uses the php-cli installed in the base section.
    # v59: drupal/core requires ext-gd, ext-dom/xml, ext-mbstring and ext-pdo, so with php-cli alone
    # 'composer create-project drupal/recommended-project' fails its platform check on the host.
    # intl/curl/zip are what Composer itself and Drupal's recommended set want; the three pdo
    # drivers cover SQLite quick-starts and MariaDB/PostgreSQL projects.
    # v89: php-redis (phpredis) and php-memcached for the shared cache services (install-cache): Drupal's
    # redis and memcache modules, Laravel's default Redis client and Symfony's cache, lock and Messenger
    # adapters all use these two. Loaded by PHP whether or not a service runs; they only connect on use.
    sudo apt install -y composer php-gd php-xml php-mbstring php-curl php-zip php-intl \
        php-sqlite3 php-mysql php-pgsql php-redis php-memcached
    # v89: php-mongodb, the MongoDB driver (install-mongodb), on its own so a Debian without it only costs a
    # NOTICE. Laravel's mongodb/laravel-mongodb 5 and Doctrine's MongoDB ODM 2 accept ext-mongodb ^1.21 or 2.x;
    # Composer then picks the mongodb/mongodb library release that matches the extension (the newest 2.x
    # releases of that library want ext-mongodb 2.4+, which 'pecl install mongodb' would give).
    sudo apt install -y php-mongodb \
        || echo "NOTICE: could not install php-mongodb; PHP projects using MongoDB need it (pecl install mongodb works too)."
    echo "Angular CLI: $(ng version 2>/dev/null | grep -m1 'Angular CLI' || echo 'installed')"
    echo "Composer: $(composer --version 2>/dev/null | head -n 1)"
else
    echo "Skipping web tooling. (Run with 'install-web' flag to enable)"
fi

# TanStack CLI (added in v65)
if [[ "$FLAGS" =~ " install-tanstack " ]]; then
    echo "Installing the TanStack CLI (@tanstack/cli) and enabling corepack for pnpm..."
    # Node is guaranteed by the dependency guard. The CLI's dependency tree has no install scripts,
    # so unlike the agent CLIs it needs no --allow-scripts list under npm 12.
    # Everything else in a TanStack project is a per-project dependency chosen at scaffold time:
    #   tanstack create my-app                 Start app (SSR), interactive add-on picker
    #   tanstack create my-app --router-only   client-side SPA on TanStack Router
    #   tanstack add tanstack-query drizzle    add-ons to an existing project
    #   tanstack doc / tanstack search-docs    docs lookup (replaced the CLI's MCP server)
    # Bun stays out for the reason given in the Node section; the CLI scaffolds with pnpm.
    enable_corepack
    npm install -g @tanstack/cli
    echo "TanStack CLI: $(tanstack --version 2>/dev/null || echo 'installed')"
    echo "E2E: Playwright can use the installed Chrome (use: { channel: 'chrome' }) with no browser download."
else
    echo "Skipping TanStack CLI. (Run with 'install-tanstack' flag to enable)"
fi

# Drupal hosting CLIs: Pantheon (Terminus), Acquia (acli), Upsun; DDEV global settings (added in v68)
if [[ "$FLAGS" =~ " install-drupal " ]]; then
    echo "Installing Drupal hosting CLIs (Terminus, Acquia CLI, Upsun CLI)..."
    # One machine-level CLI per platform. Everything else Drupal (Drush, PHPStan + phpstan-drupal,
    # PHPCS + Coder, Rector, the ddev-drupal-contrib add-on) is a per-project Composer / DDEV
    # dependency. DDEV's web container already carries terminus, acli and the Upsun CLI for
    # 'ddev pull <provider>'; these host copies are for work outside a project (site and
    # environment management, scripting across clients). dev-init logs them in and puts the
    # platform tokens into DDEV's global config, which is what makes 'ddev pull' work.
    # Composer and Drupal's PHP extensions come from install-web (dependency guard).
    # rsync and a MariaDB client: both CLIs shell out to them for file and database pulls.
    sudo apt install -y rsync mariadb-client bash-completion
    mkdir -p ~/.local/bin ~/.local/share/bash-completion/completions

    # Release tags come from the releases/latest redirect, not the rate-limited GitHub API.
    drupal_cli_tag() {   # drupal_cli_tag OWNER/REPO
        curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/tag/||'
    }
    # Both phars need PHP >= 8.2 (php-cli from the base section: 8.4 on trixie). Downloaded to a temp
    # file and run once before it replaces the installed copy, so a bad download never lands on PATH.
    install_phar() {   # install_phar NAME OWNER/REPO ASSET
        local name="$1" repo="$2" asset="$3" tag tmp
        tag=$(drupal_cli_tag "$repo")
        if ! [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "ERROR: could not resolve the latest $name release (got '$tag'). Aborting."
            exit 1
        fi
        tmp=$(mktemp)
        curl -fsSL --retry 3 -o "$tmp" "https://github.com/$repo/releases/download/$tag/$asset"
        if ! timeout 120 php "$tmp" --version --no-interaction < /dev/null > /dev/null 2>&1; then
            echo "ERROR: the downloaded $asset ($tag) does not run under $(php -r 'echo PHP_VERSION;'). Aborting."
            rm -f "$tmp"
            exit 1
        fi
        install -m 755 "$tmp" "$HOME/.local/bin/$name"
        rm -f "$tmp"
        echo "$name $tag installed."
    }
    install_phar terminus pantheon-systems/terminus terminus.phar
    install_phar acli acquia/cli acli.phar
    # Every acli/terminus call below is non-interactive with stdin closed: on first run acli asks
    # about telemetry and would otherwise sit waiting for an answer.
    timeout 60 acli self:telemetry:disable --no-interaction < /dev/null > /dev/null 2>&1 || true

    # Upsun (formerly Platform.sh): a self-contained binary, verified against the release checksums.
    UPSUN_TAG=$(drupal_cli_tag upsun/cli)
    if ! [[ "$UPSUN_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: could not resolve the latest Upsun CLI release (got '$UPSUN_TAG'). Aborting."
        exit 1
    fi
    UPSUN_TGZ="upsun_${UPSUN_TAG#v}_linux_amd64.tar.gz"
    UPSUN_TMP=$(mktemp -d)
    curl -fsSL --retry 3 -o "$UPSUN_TMP/$UPSUN_TGZ" "https://github.com/upsun/cli/releases/download/$UPSUN_TAG/$UPSUN_TGZ"
    curl -fsSL -o "$UPSUN_TMP/checksums.txt" "https://github.com/upsun/cli/releases/download/$UPSUN_TAG/checksums.txt"
    ( cd "$UPSUN_TMP" && grep -F " $UPSUN_TGZ" checksums.txt | sha256sum -c - ) || {
        echo "ERROR: checksum mismatch for $UPSUN_TGZ. Aborting."
        rm -rf "$UPSUN_TMP"
        exit 1
    }
    tar -xzf "$UPSUN_TMP/$UPSUN_TGZ" -C "$UPSUN_TMP"
    install -m 755 "$UPSUN_TMP/upsun" "$HOME/.local/bin/upsun"
    [ -f "$UPSUN_TMP/completion/bash/upsun.bash" ] && cp "$UPSUN_TMP/completion/bash/upsun.bash" ~/.local/share/bash-completion/completions/upsun
    rm -rf "$UPSUN_TMP"
    echo "upsun $UPSUN_TAG installed."

    # Tab completion: Terminus and acli have hundreds of subcommands between them. bash-completion
    # loads files from this directory on demand, so nothing is added to ~/.bashrc.
    timeout 60 terminus completion bash < /dev/null > ~/.local/share/bash-completion/completions/terminus 2> /dev/null || rm -f ~/.local/share/bash-completion/completions/terminus
    timeout 60 acli completion bash < /dev/null > ~/.local/share/bash-completion/completions/acli 2> /dev/null || rm -f ~/.local/share/bash-completion/completions/acli

    # Terminus plugins (Composer packages, installed per user under ~/.terminus). 'self:plugin:install'
    # exits 0 even when it fails, so the result is read back from the plugin list.
    #   rsync : 'terminus rsync' between this machine and a Pantheon environment
    # v70: the secrets-manager plugin is gone from this list. Pantheon deprecated it when Terminus 4
    # absorbed it: 'terminus secret:site:set|list|delete' and 'secret:org:*' are built in.
    timeout 300 terminus self:plugin:install pantheon-systems/terminus-rsync-plugin --no-interaction < /dev/null > /dev/null 2>&1 || true
    TERMINUS_PLUGINS=$(timeout 60 terminus self:plugin:list --format=csv --fields=name --no-interaction < /dev/null 2>&1 || true)
    if echo "$TERMINUS_PLUGINS" | grep -q terminus-rsync-plugin; then
        echo "Terminus plugin terminus-rsync-plugin installed."
    else
        echo "NOTICE: the Terminus rsync plugin did not install. By hand: terminus self:plugin:install pantheon-systems/terminus-rsync-plugin"
    fi

    # DDEV: usage telemetry off, like npm / Angular / .NET / Vercel. Tokens for 'ddev pull' are dev-init's job.
    ddev config global --instrumentation-opt-in=false < /dev/null > /dev/null 2>&1 || true

    echo "terminus: $(timeout 60 terminus --version --no-interaction < /dev/null 2>/dev/null | tail -n 1)   acli: $(timeout 60 acli --version --no-interaction < /dev/null 2>/dev/null | tail -n 1)   upsun: $(timeout 60 upsun --version < /dev/null 2>/dev/null | tail -n 1)"
    echo "Log in with dev-init (install-drupal): platform tokens from secrets.env, SSH key upload, DDEV global config."
else
    echo "Skipping Drupal hosting CLIs. (Run with 'install-drupal' flag to enable)"
fi

# =================================================================
# install-laravel : Laravel (added in v87). In install-all; pulls in install-web (Composer and the
# PHP extensions) and, through it, install-node (Vite and @laravel/multiplex, which 'php artisan dev'
# runs). Laravel 13 needs PHP 8.3+: trixie's php-cli is 8.4, and install-web's extensions cover
# everything laravel/framework requires (ctype, filter, hash, mbstring, openssl, session, tokenizer)
# plus the curl, dom/xml and pdo drivers apps use. This section adds:
#   the Laravel installer ('laravel new'), a global Composer package in Composer's own global bin
#     directory (~/.config/composer/vendor/bin), which a marked ~/.bashrc block appends to PATH
#     (appended, so nothing Composer installs globally shadows a system command);
#   php-bcmath, which money and big-number packages (Cashier among them) expect.
# Deliberately not here: php.new / Herd Lite (Laravel's own installer brings a second, static PHP that
# would shadow Debian's), Herd (macOS and Windows only), and Pest, Pint, Sail, Boost and the AI SDK, which are
# Composer packages each project pins itself. DDEV (base) already has a 'laravel' project type, and
# Sail's containers run on the base Docker, though its MySQL + Redis stack is heavy for 8 GB.
# v89: a Redis server is no longer left out: install-cache (in install-all) runs one shared Redis and
# Memcached for every project (Laravel 11+ still defaults to the database for queue, cache and sessions;
# 'devsvc info redis' has the .env lines to switch).
# =================================================================
if [[ "$FLAGS" =~ " install-laravel " ]]; then
    echo "================================================================="
    echo "Installing Laravel tooling (the Laravel installer, php-bcmath)..."
    echo "================================================================="
    sudo DEBIAN_FRONTEND=noninteractive apt install -y php-bcmath
    PHP_OK=$(php -r 'echo PHP_VERSION_ID >= 80300 ? "yes" : "no";' 2> /dev/null || echo no)
    if [ "$PHP_OK" != yes ]; then
        echo "NOTICE: Laravel 13 needs PHP 8.3 or newer; php-cli here is $(php -r 'echo PHP_VERSION;' 2> /dev/null || echo missing)."
    elif ! command -v composer > /dev/null 2>&1; then
        echo "NOTICE: composer is missing (install-web installs it); rerun setup with install-laravel."
    else
        # Not fatal under set -e: Packagist being unreachable should not stop the rest of setup.
        if composer global require --no-interaction --no-progress laravel/installer; then
            COMPOSER_GLOBAL_BIN=$(composer global config bin-dir --absolute 2> /dev/null | tail -n 1 || true)
            [ -n "$COMPOSER_GLOBAL_BIN" ] || COMPOSER_GLOBAL_BIN="$HOME/.config/composer/vendor/bin"
            echo "Laravel installer: $("$COMPOSER_GLOBAL_BIN/laravel" --version 2> /dev/null | head -n 1)"
            # ~/.bashrc: Composer's global bin, a marked block rewritten on every run.
            sed -i '/^# >>> dev-setup laravel >>>$/,/^# <<< dev-setup laravel <<<$/d' ~/.bashrc
            cat >> ~/.bashrc << EOF
# >>> dev-setup laravel >>>
# Written by dev-setup (install-laravel); replaced on each run. Composer's global bin (laravel), at the end of PATH.
case ":\$PATH:" in *":$COMPOSER_GLOBAL_BIN:"*) ;; *) export PATH="\$PATH:$COMPOSER_GLOBAL_BIN" ;; esac
# <<< dev-setup laravel <<<
EOF
        else
            echo "NOTICE: 'composer global require laravel/installer' failed (is Packagist reachable?); rerun setup with install-laravel. 'composer create-project laravel/laravel <app>' works without it."
        fi
    fi
    echo "Laravel: 'laravel new <app>' (a new terminal has it on PATH), then 'cd <app> && composer run dev'. With DDEV:"
    echo "  'ddev config --project-type=laravel --docroot=public && ddev start'. dev-demo has a walkthrough (install-laravel)."
else
    echo "Skipping Laravel tooling. (Run with 'install-laravel' flag to enable)"
fi

# =================================================================
# install-symfony : Symfony (added in v88). In install-all; pulls in install-web (Composer and the PHP
# extensions). Symfony 8 needs PHP 8.4+, exactly trixie's php-cli, and ctype, iconv, pcre, session,
# simplexml and tokenizer, which Debian's PHP and install-web's php-xml already provide (7.4 LTS, for
# projects that pin it, needs 8.2+). This section adds the Symfony CLI ('symfony'): 'symfony new' (with
# --webapp for the full stack), a local web server with HTTP/2 and optional TLS ('symfony serve'),
# 'symfony check:requirements' and 'symfony check:security' (the project's packages against the
# FriendsOfPHP advisory database). It is the .deb from the CLI's GitHub releases, verified against the
# release's checksums.txt, rather than Symfony's Cloudsmith apt repository, so no third-party apt
# source is added; a rerun installs a newer release when there is one.
# Deliberately not here: 'symfony server:ca:install' (the CLI's own local CA, which changes the system
# and browser trust stores: run it yourself if you want https from 'symfony serve'; mkcert from the base
# section does the same job for other tools), and Doctrine, MakerBundle, API Platform, PHPUnit and
# PHPStan, which each project pins itself. DDEV (base) has a 'symfony' project type.
# 'symfony new' makes a git repository and a first commit unless given --no-git, so it wants git's
# user.name and user.email (dev-init sets them from secrets.env).
# =================================================================
if [[ "$FLAGS" =~ " install-symfony " ]]; then
    echo "================================================================="
    echo "Installing the Symfony CLI..."
    echo "================================================================="
    SF_ARCH=$(dpkg --print-architecture)
    # The release tag from the releases/latest redirect (not the rate-limited GitHub API).
    SF_TAG=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/symfony-cli/symfony-cli/releases/latest 2> /dev/null | sed 's|.*/tag/||' || true)
    SF_HAVE=$(dpkg-query -W -f='${Version}' symfony-cli 2> /dev/null || true)
    if ! [[ "$SF_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if [ -n "$SF_HAVE" ]; then
            echo "Could not resolve the latest Symfony CLI release; keeping $SF_HAVE."
        else
            echo "NOTICE: could not resolve the latest Symfony CLI release (offline?); rerun setup with install-symfony."
        fi
    elif [ "$SF_HAVE" = "${SF_TAG#v}" ]; then
        echo "Symfony CLI ${SF_TAG#v} is current."
    else
        SF_DEB="symfony-cli_${SF_TAG#v}_${SF_ARCH}.deb"
        SF_TMP=$(mktemp -d)
        SF_BASE="https://github.com/symfony-cli/symfony-cli/releases/download/$SF_TAG"
        # Not fatal under set -e: a failed download or checksum leaves the rest of setup running.
        if curl -fsSL --retry 3 -o "$SF_TMP/$SF_DEB" "$SF_BASE/$SF_DEB" \
            && curl -fsSL --retry 3 -o "$SF_TMP/checksums.txt" "$SF_BASE/checksums.txt" \
            && ( cd "$SF_TMP" && awk -v f="$SF_DEB" '$2 == f' checksums.txt | sha256sum -c - > /dev/null ); then
            sudo DEBIAN_FRONTEND=noninteractive apt install -y "$SF_TMP/$SF_DEB" \
                && echo "Symfony CLI ${SF_TAG#v} installed${SF_HAVE:+ (was $SF_HAVE)}." \
                || echo "NOTICE: apt could not install $SF_DEB; rerun setup with install-symfony."
        else
            echo "NOTICE: could not download or verify $SF_DEB from GitHub; rerun setup with install-symfony."
        fi
        rm -rf "$SF_TMP"
    fi
    if command -v symfony > /dev/null 2>&1; then
        symfony version --no-ansi 2> /dev/null | head -n 1
        symfony check:requirements --no-ansi > /dev/null 2>&1 \
            && echo "symfony check:requirements: OK" \
            || echo "NOTICE: 'symfony check:requirements' reports a problem; run it to see which."
    fi
    echo "Symfony: 'symfony new <app> --webapp', then 'cd <app> && symfony serve'. With DDEV:"
    echo "  'ddev config --project-type=symfony --docroot=public && ddev start'. dev-demo has a walkthrough (install-symfony)."
else
    echo "Skipping the Symfony CLI. (Run with 'install-symfony' flag to enable)"
fi

# =================================================================
# install-graphql : Apollo GraphQL tooling (added in v90). In install-all; no dependencies. Three
# standalone binaries in ~/.local/bin, each from its GitHub release:
#   rover              Apollo's CLI: 'rover dev' (a local router that recomposes as subgraphs change),
#                      'rover supergraph compose', 'rover graph introspect', 'rover config' (an optional
#                      GraphOS key, dev-init's job)
#   router             the Apollo Router, v2 only (v1 reached end of support on 31 March 2026), run directly:
#                      router --supergraph supergraph.graphql --config router.yaml. Without a key it runs as
#                      the free Router Core
#   apollo-mcp-server  turns GraphQL operation files into MCP tools over streamable HTTP:
#                      apollo-mcp-server mcp.yaml   (the config file is its only argument)
# Each release tag comes from the releases/latest redirect, or from the releases Atom feed when that
# redirect names another major line (the router repository still ships v1 patches), never from the
# rate-limited API. The x86-64 tarball (<name>-<tag>-x86_64-unknown-linux-gnu.tar.gz, the binary in dist/)
# is checked against the release's sha256sums.txt where the release has one (Rover and the router do);
# otherwise the new binary must answer --version before it replaces the installed copy. A copy already at
# that version is left alone, and a failed download is a NOTICE: the rest of setup carries on.
# Rover's plugins are fetched once into ~/.rover/bin, Rover's own place for them: the supergraph composer
# (supergraph@latest-2) and the router that 'rover dev' runs (router@latest). Then composition and dev-test
# work offline (APOLLO_ROVER_SKIP_UPDATE=1 tells Rover to use what is there).
# A marked ~/.bashrc block (dev-setup graphql), rewritten on every run:
#   APOLLO_TELEMETRY_DISABLED=true   Rover and the router send no anonymous usage data
#   APOLLO_ELV2_LICENSE=accept       the composition and router plugins are Elastic License v2: accepted
#                                    here once, so 'rover dev', composition and the demos never stop to ask
# Deliberately not here: Apollo's 'curl | sh' installers (they edit ~/.bashrc and PATH themselves), the
# Apollo Runtime container (router + MCP server in one image: the binaries do the same with less disk),
# a GraphOS login (APOLLO_KEY, optional, dev-init), and every library: Apollo Server, Apollo Client,
# @apollo/subgraph, Strawberry, GraphQL Codegen and the Drupal modules are per project.
# APOLLO_KEY is never exported by the bundle: with it in the environment every local router reports to
# GraphOS, where the Free plan caps self-hosted routers at 60 requests a minute.
# =================================================================
if [[ "$FLAGS" =~ " install-graphql " ]]; then
    echo "================================================================="
    echo "Installing Apollo GraphQL tooling (Rover, Router v2, Apollo MCP Server)..."
    echo "================================================================="
    mkdir -p ~/.local/bin
    export APOLLO_TELEMETRY_DISABLED=true APOLLO_ELV2_LICENSE=accept
    # apollo_tag OWNER/REPO REGEX: the newest release tag matching REGEX; empty when none can be found.
    apollo_tag() {
        local repo=$1 re=$2 tag
        tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest" 2> /dev/null | sed 's|.*/tag/||' || true)
        if ! [[ "$tag" =~ $re ]]; then
            tag=$(curl -fsSL --max-time 30 "https://github.com/$repo/releases.atom" 2> /dev/null \
                | grep -oE '/releases/tag/[^"<]+' | sed 's|.*/tag/||' | grep -E "$re" | sort -V | tail -n 1 || true)
        fi
        [[ "$tag" =~ $re ]] && printf '%s' "$tag"
        return 0
    }
    # apollo_install BINARY OWNER/REPO TAG: install BINARY from that release into ~/.local/bin unless the
    # installed copy already reports that version. Never fatal.
    apollo_install() {
        local bin=$1 repo=$2 tag=$3 have tgz base tmp how
        have=$("$HOME/.local/bin/$bin" --version 2> /dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
        if [ -z "$tag" ]; then
            echo "NOTICE: could not resolve the latest $bin release from github.com/$repo${have:+; keeping $have}. Rerun setup with install-graphql."
            return 0
        fi
        if [ "$have" = "${tag#v}" ]; then echo "$bin ${tag#v} is current."; return 0; fi
        tgz="$bin-$tag-x86_64-unknown-linux-gnu.tar.gz"
        base="https://github.com/$repo/releases/download/$tag"
        tmp=$(mktemp -d)
        if ! curl -fsSL --retry 3 -o "$tmp/$tgz" "$base/$tgz"; then
            echo "NOTICE: could not download $tgz${have:+; keeping $have}. Rerun setup with install-graphql."
            rm -rf "$tmp"; return 0
        fi
        how="its own --version"
        if curl -fsSL --retry 3 -o "$tmp/sha256sums.txt" "$base/sha256sums.txt" 2> /dev/null \
            && awk -v f="$tgz" '{ n = $2; sub(/^[*.\/]+/, "", n) } n == f { found = 1 } END { exit !found }' "$tmp/sha256sums.txt"; then
            if ( cd "$tmp" && awk -v f="$tgz" '{ n = $2; sub(/^[*.\/]+/, "", n) } n == f { print $1 "  " f }' sha256sums.txt | sha256sum -c - > /dev/null 2>&1 ); then
                how="sha256sums.txt and its own --version"
            else
                echo "NOTICE: $tgz does not match the release's sha256sums.txt; not installed${have:+, keeping $have}."
                rm -rf "$tmp"; return 0
            fi
        fi
        mkdir -p "$tmp/x"
        if tar -xzf "$tmp/$tgz" -C "$tmp/x" --strip-components 1 && [ -x "$tmp/x/$bin" ] && "$tmp/x/$bin" --version > /dev/null 2>&1; then
            install -m 755 "$tmp/x/$bin" "$HOME/.local/bin/$bin"
            echo "$bin ${tag#v} installed${have:+ (was $have)}, checked with $how."
        else
            echo "NOTICE: $tgz did not unpack to a working $bin; not installed${have:+, keeping $have}."
        fi
        rm -rf "$tmp"
    }
    apollo_install rover apollographql/rover "$(apollo_tag apollographql/rover '^v[0-9]+\.[0-9]+\.[0-9]+$')"
    apollo_install router apollographql/router "$(apollo_tag apollographql/router '^v2\.[0-9]+\.[0-9]+$')"
    apollo_install apollo-mcp-server apollographql/apollo-mcp-server "$(apollo_tag apollographql/apollo-mcp-server '^v[0-9]+\.[0-9]+\.[0-9]+$')"
    # A 'router' earlier on PATH than ~/.local/bin would shadow this one; 'router' is a generic name.
    case "$(command -v router 2> /dev/null)" in
        "$HOME/.local/bin/router"|"") ;;
        *) echo "NOTICE: 'router' on PATH is $(command -v router), not ~/.local/bin/router; call the Apollo Router by its full path." ;;
    esac

    # Rover's plugins, for 'rover supergraph compose' and 'rover dev'. Rover checks for newer ones on its own
    # when online; these make the first offline use work.
    if [ -x "$HOME/.local/bin/rover" ]; then
        for ROVER_PLUGIN in supergraph@latest-2 router@latest; do
            if "$HOME/.local/bin/rover" install --plugin "$ROVER_PLUGIN" --elv2-license accept --skip-update-check > /dev/null 2>&1; then
                echo "Rover plugin ${ROVER_PLUGIN%@*}: $(find "$HOME/.rover/bin" -maxdepth 1 -name "${ROVER_PLUGIN%@*}-v*" -printf '%f\n' 2> /dev/null | sort -V | tail -n 1)"
            else
                echo "NOTICE: 'rover install --plugin $ROVER_PLUGIN' failed (rover.apollo.dev unreachable?); rover fetches it on first use."
            fi
        done
    fi

    # ~/.bashrc: a marked block, rewritten on every run. Nothing in it runs a command at shell start.
    sed -i '/^# >>> dev-setup graphql >>>$/,/^# <<< dev-setup graphql <<<$/d' ~/.bashrc
    cat >> ~/.bashrc << 'EOF'
# >>> dev-setup graphql >>>
# Written by dev-setup (install-graphql); replaced on each run. Apollo's tools send no usage data, and
# Rover's composition and router plugins (Elastic License v2, accepted once by setup) never stop to ask.
# APOLLO_KEY stays out of here on purpose: dev-init keeps it in Rover's profile (see secrets.env).
export APOLLO_TELEMETRY_DISABLED=true
export APOLLO_ELV2_LICENSE=accept
# <<< dev-setup graphql <<<
EOF
    for APOLLO_BIN in rover router apollo-mcp-server; do
        [ -x "$HOME/.local/bin/$APOLLO_BIN" ] && echo "$APOLLO_BIN: $("$HOME/.local/bin/$APOLLO_BIN" --version 2> /dev/null | head -n 1)"
    done
    echo "Local federation needs no account. Try (in a new terminal):"
    echo "  rover supergraph compose --config supergraph.yaml > supergraph.graphql"
    echo "  rover dev --supergraph-config supergraph.yaml      (a router on :4000 that recomposes as you edit)"
    echo "  apollo-mcp-server mcp.yaml                         (GraphQL operations as MCP tools on /mcp)"
    echo "dev-demo has a supergraph walkthrough (graphql/apollo-supergraph) and Drupal in it (drupal/drupal-graphql)."
else
    echo "Skipping Apollo GraphQL tooling. (Run with 'install-graphql' flag to enable)"
fi

# PowerShell
if [[ "$FLAGS" =~ " install-pwsh " ]]; then
    echo "Installing PowerShell..."
    PWSH_DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/PowerShell/PowerShell/releases/latest | grep "browser_download_url.*linux-x64.tar.gz" | cut -d '"' -f 4 | head -n 1)
    if [ -z "$PWSH_DOWNLOAD_URL" ]; then
        # v67: the API allows 60 anonymous calls per hour per IP and then answers 403. The
        # releases/latest redirect is not rate-limited and the asset name follows the tag.
        echo "GitHub API gave no URL (rate-limited?); resolving the PowerShell release from the releases/latest redirect..."
        PWSH_TAG=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/PowerShell/PowerShell/releases/latest | sed 's|.*/tag/||' || true)
        if [[ "$PWSH_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            PWSH_DOWNLOAD_URL="https://github.com/PowerShell/PowerShell/releases/download/$PWSH_TAG/powershell-${PWSH_TAG#v}-linux-x64.tar.gz"
        fi
    fi
    # v93: a failed lookup or download skips PowerShell (a NOTICE, and the summary names it) instead of
    # stopping the run; the download is checked (fetch_tgz) before it is unpacked.
    if [ -z "$PWSH_DOWNLOAD_URL" ]; then
        echo "NOTICE: could not resolve the PowerShell download URL (GitHub API and releases/latest both failed; offline?); PowerShell skipped this run."
        DL_FAILED+=("PowerShell (install-pwsh)")
    elif fetch_tgz "$PWSH_DOWNLOAD_URL" "$ASSETS/downloads/powershell.tar.gz"; then
        sudo mkdir -p /opt/microsoft/powershell/7
        sudo tar zxf "$ASSETS/downloads/powershell.tar.gz" -C /opt/microsoft/powershell/7
        sudo chmod +x /opt/microsoft/powershell/7/pwsh
        sudo ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
        rm -f "$ASSETS/downloads/powershell.tar.gz"
    else
        echo "        PowerShell skipped this run; the rest of the run goes on."
        DL_FAILED+=("PowerShell (install-pwsh)")
    fi
    rm -f /tmp/powershell.tar.gz   # left by an interrupted v92 run
else
    echo "Skipping PowerShell. (Run with 'install-pwsh' flag to enable)"
fi

# C / C++ toolchain extras (added in v63)
if [[ "$FLAGS" =~ " install-cpp " ]]; then
    echo "Installing C/C++ tooling (gdb, valgrind, cmake, ninja, clang tools, lldb, ccache, meson)..."
    # gcc, g++, make and binutils are already there (build-essential, base section); this adds what
    # sits around the compiler. clang/cmake/ninja-build also appear under install-flutter; apt is
    # idempotent, so whichever flag runs first installs them. libc6-dbg is what lets valgrind's
    # memcheck start on Debian (it needs ld.so's debug symbols for its mandatory redirections).
    # Debian's gcc is the C/C++ compiler here: Homebrew's gcc formula only provides gcc-NN / g++-NN
    # names for brew's own builds and does not shadow /usr/bin/gcc.
    sudo apt install -y gdb valgrind libc6-dbg cmake ninja-build pkg-config \
        clang clangd clang-format clang-tidy lldb ccache meson
    echo "g++: $(g++ --version | head -n 1)   clang: $(clang --version | head -n 1)"
    echo "cmake: $(cmake --version | head -n 1)"
    echo "Editors: VS Code takes Microsoft's C/C++ extension; Cursor/Windsurf (Open VSX) use the clangd extension."
else
    echo "Skipping C/C++ tooling. (Run with 'install-cpp' flag to enable)"
fi

# Assembly (added in v63)
if [[ "$FLAGS" =~ " install-asm " ]]; then
    echo "Installing x86-64 assemblers (nasm, yasm)..."
    # GNU as and ld (AT&T or '.intel_syntax noprefix') are part of binutils via build-essential.
    # nasm is what most x86 books and tutorials assume; yasm reads the same syntax.
    sudo apt install -y nasm yasm
    echo "nasm: $(nasm -v)"
else
    echo "Skipping assemblers. (Run with 'install-asm' flag to enable)"
fi

# AArch64 assembly/C cross toolchain + user-mode emulation (added in v63; opt-in, NOT in install-all)
if [[ "$FLAGS" =~ " install-asm-arm " ]]; then
    echo "Installing AArch64 cross toolchain and qemu-user..."
    # The Chromebooks are all x86-64, so ARM code is cross-built (aarch64-linux-gnu-as/-ld/-gcc)
    # and run under qemu-aarch64. Static binaries run as-is; dynamically linked ones need
    # 'qemu-aarch64 -L /usr/aarch64-linux-gnu ./prog'.
    sudo apt install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu qemu-user
else
    echo "Skipping AArch64 cross toolchain. (Run with 'install-asm-arm' flag to enable; not part of install-all)"
fi

# .NET SDK: C# and VB.NET (added in v63)
if [[ "$FLAGS" =~ " install-dotnet " ]]; then
    echo "Installing the .NET 10 SDK (C#, VB.NET)..."
    # PowerShell (install-pwsh) bundles a private runtime and provides no 'dotnet' command, so this is
    # the only .NET SDK on the machine. Microsoft's Debian 13 feed carries dotnet-sdk-10.0 (LTS);
    # Debian itself does not package .NET, so there is no distro/Microsoft package mix to pin.
    # apt may print "W: Unknown TAR header type 120" while unpacking: a known cosmetic warning
    # with these .debs on trixie, not an error.
    # Works on Linux: console apps, libraries, ASP.NET Core, Avalonia GUIs. WinForms and WPF are
    # Windows-only, in both C# and VB.
    add_microsoft_prod_repo
    sudo apt install -y dotnet-sdk-10.0
    # Guarded line by line: dev-init can add the opt-out on its own, which must not suppress the rest.
    grep -q 'DOTNET_CLI_TELEMETRY_OPTOUT' ~/.bashrc || echo 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' >> ~/.bashrc
    grep -q 'DOTNET_NOLOGO' ~/.bashrc || echo 'export DOTNET_NOLOGO=1' >> ~/.bashrc
    grep -q '\.dotnet/tools' ~/.bashrc || echo 'export PATH="$PATH:$HOME/.dotnet/tools"   # dotnet global tools' >> ~/.bashrc
    export DOTNET_CLI_TELEMETRY_OPTOUT=1
    export DOTNET_NOLOGO=1
    export PATH="$PATH:$HOME/.dotnet/tools"
    echo ".NET SDK: $(dotnet --version)"
    echo "New projects: 'dotnet new console -o app' (C#) or 'dotnet new console -lang VB -o app' (VB.NET)."
    echo "Editors: VS Code takes the C# / C# Dev Kit extensions; Cursor/Windsurf (Open VSX) need an open C# extension instead."
else
    echo "Skipping .NET SDK. (Run with 'install-dotnet' flag to enable)"
fi

# Java: JDK, Maven, Gradle (added in v63)
if [[ "$FLAGS" =~ " install-java " ]]; then
    echo "Installing Java tooling (default-jdk, Maven, Gradle)..."
    # One JDK for everything: Debian's default-jdk, the same one the Android stacks use. Projects
    # pinned to another release (17, 25) would need SDKMAN or the Adoptium repo; deliberately not
    # installed, since that changes the PATH setup the test and init scripts reproduce.
    install_jdk_and_java_home
    # Maven from apt (3.9.x on trixie). Gradle from Homebrew: Debian's 'gradle' package is years
    # out of date and cannot build current projects. brew's gradle depends on brew's openjdk,
    # which on Linux links its own java/javac ahead of /usr/bin (v64: unlinked right after).
    # gradle's launcher honours an exported JAVA_HOME, so with the line above both build tools
    # run on the Debian JDK. Projects that ship ./gradlew keep using their own pinned Gradle.
    sudo apt install -y maven
    brew install gradle
    unlink_brew_openjdk
    echo "java: $(java -version 2>&1 | head -n 1)"
    echo "maven: $(mvn -version 2>/dev/null | head -n 1)"
    echo "gradle: $(gradle --version 2>/dev/null | grep -m1 '^Gradle')"
    echo "Editors: Red Hat's Java extension is on Open VSX too, so VS Code, Cursor and Windsurf all take it."
else
    echo "Skipping Java tooling. (Run with 'install-java' flag to enable)"
fi

# Ruby Toolchain & Jekyll Dependencies
if [[ "$FLAGS" =~ " install-ruby " ]]; then
    echo "Installing Ruby and Jekyll dependencies..."
    sudo apt install -y ruby-full ruby-dev zlib1g-dev libyaml-dev

    if ! grep -q 'export GEM_HOME="$HOME/.gems"' ~/.bashrc; then
        echo 'export GEM_HOME="$HOME/.gems"' >> ~/.bashrc
        echo 'export PATH="$HOME/.gems/bin:$PATH"' >> ~/.bashrc
    fi

    export GEM_HOME="$HOME/.gems"
    export PATH="$HOME/.gems/bin:$PATH"
    gem install jekyll bundler jekyll-feed jekyll-seo-tag
else
    echo "Skipping Ruby & Jekyll. (Run with 'install-ruby' flag to enable)"
fi

# Visual Studio Code
if [[ "$FLAGS" =~ " install-vscode " ]]; then
    echo "Installing VS Code..."
    KEY_TMP=$(mktemp)   # v65: was written to the current directory
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$KEY_TMP"
    sudo install -D -o root -g root -m 644 "$KEY_TMP" /etc/apt/keyrings/packages.microsoft.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
    rm -f "$KEY_TMP"
    sudo apt update
    sudo apt install -y code
else
    echo "Skipping VS Code. (Run with 'install-vscode' flag to enable)"
fi

# Cursor
if [[ "$FLAGS" =~ " install-cursor " ]]; then
    echo "Installing Cursor..."
    mkdir -p ~/.local/bin

    # v51: download.cursor.sh/linux/appImage/x64 has been dead since Cursor 0.46. The current
    # endpoint returns JSON with a downloadUrl; it 403s without a browser-ish User-Agent.
    CURSOR_URL=$(curl -fsSL -A "Mozilla/5.0 (X11; Linux x86_64)" \
        "https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable" \
        | python3 -c 'import sys, json; print(json.load(sys.stdin)["downloadUrl"])' 2>/dev/null || true)
    if [ -n "$CURSOR_URL" ]; then
        echo "Downloading Cursor AppImage..."
        # Download to a temp file so an interrupted transfer never leaves a truncated ~/.local/bin/cursor.
        if wget -qO /tmp/cursor.AppImage "$CURSOR_URL"; then
            mv /tmp/cursor.AppImage ~/.local/bin/cursor
        else
            rm -f /tmp/cursor.AppImage
        fi
    else
        echo "Warning: could not resolve the Cursor download URL from cursor.com."
    fi

    # Validate that the downloaded file is actually an executable/binary (prevent HTML error page saves)
    if [ -f ~/.local/bin/cursor ] && ! file ~/.local/bin/cursor | grep -qE "ELF|executable|AppImage"; then
        echo "Warning: Downloaded artifact is not a valid binary (likely an error page). Removing..."
        rm -f ~/.local/bin/cursor
    fi

    if [ -s ~/.local/bin/cursor ]; then
        chmod +x ~/.local/bin/cursor
        if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        fi
    elif CUR_LOCAL=$(ls "$ASSETS"/*ursor*.AppImage ./*ursor*.AppImage 2> /dev/null | head -n 1) && [ -n "$CUR_LOCAL" ]; then
        # v67: a hand-downloaded AppImage is looked for in ./assets first, then the current directory.
        echo "Found local Cursor AppImage ($CUR_LOCAL). Installing..."
        mv "$CUR_LOCAL" ~/.local/bin/cursor
        chmod +x ~/.local/bin/cursor
        if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        fi
    else
        echo "================================================================="
        echo "NOTICE: Cursor download failed and no local AppImage found."
        echo "Please download it manually from cursor.com/download,"
        echo "place it in $ASSETS"
        echo "and rerun with install-cursor."
        echo "================================================================="
    fi

    # v66: ChromeOS launcher entry. The app drawer lists what has a .desktop file under
    # /usr/share/applications or ~/.local/share/applications; an AppImage dropped into
    # ~/.local/bin has neither, which is why Cursor was missing. Exec is an absolute path because
    # the launcher starts apps without your ~/.bashrc PATH. The icon comes out of the AppImage
    # ('--appimage-extract' unpacks without FUSE); everything here is best effort, and Cursor
    # still gets an entry (with a generic icon) if no icon can be found.
    if [ -x "$HOME/.local/bin/cursor" ]; then
        mkdir -p ~/.local/share/applications ~/.local/share/icons
        CUR_TMP=$(mktemp -d)
        (
            cd "$CUR_TMP" || exit 0
            for pat in 'usr/share/icons/hicolor/512x512/apps/*.png' 'usr/share/icons/hicolor/256x256/apps/*.png' 'usr/share/pixmaps/*.png' '*.png'; do
                timeout 120 "$HOME/.local/bin/cursor" --appimage-extract "$pat" > /dev/null 2>&1 || true
            done
        ) || true
        # Largest PNG found = highest resolution.
        CUR_ICON=$(find "$CUR_TMP" -type f -name '*.png' -printf '%s %p\n' 2> /dev/null | sort -rn | head -n 1 | cut -d' ' -f2- || true)
        if [ -n "$CUR_ICON" ] && [ -s "$CUR_ICON" ]; then
            cp "$CUR_ICON" ~/.local/share/icons/cursor.png
        fi
        rm -rf "$CUR_TMP"
        CUR_ICON_LINE="Icon=text-editor"
        if [ -s ~/.local/share/icons/cursor.png ]; then CUR_ICON_LINE="Icon=$HOME/.local/share/icons/cursor.png"; fi
        cat > ~/.local/share/applications/cursor.desktop << EOF
[Desktop Entry]
Type=Application
Name=Cursor
Comment=AI code editor
Exec=$HOME/.local/bin/cursor %F
$CUR_ICON_LINE
Terminal=false
Categories=Development;IDE;TextEditor;
StartupWMClass=Cursor
MimeType=text/plain;inode/directory;
EOF
        echo "Added Cursor to the ChromeOS launcher (~/.local/share/applications/cursor.desktop). It can take a minute to appear."
    fi
else
    echo "Skipping Cursor. (Run with 'install-cursor' flag to enable)"
fi

# Windsurf
if [[ "$FLAGS" =~ " install-windsurf " ]]; then
    echo "Installing Windsurf..."
    KEY_TMP=$(mktemp)   # v65: was written to the current directory
    wget -qO- "https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/windsurf.gpg" | gpg --dearmor > "$KEY_TMP"
    sudo install -D -o root -g root -m 644 "$KEY_TMP" /etc/apt/keyrings/windsurf-stable.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/windsurf-stable.gpg] https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/apt stable main" | sudo tee /etc/apt/sources.list.d/windsurf.list > /dev/null
    rm -f "$KEY_TMP"
    sudo apt update
    sudo apt install -y windsurf
else
    echo "Skipping Windsurf. (Run with 'install-windsurf' flag to enable)"
fi

# Lazarus 4.8
if [[ "$FLAGS" =~ " install-lazarus " ]]; then
    echo "Downloading and installing Lazarus 4.8..."
    # v65: downloads go to assets/downloads instead of the current directory. 'wget -c' resumes a
    # partial file from an interrupted run (the old "already exists, skipping" test would have
    # handed apt a truncated .deb) and returns at once when the file is already complete.
    LAZ_URL="https://sourceforge.net/projects/lazarus/files/Lazarus%20Linux%20amd64%20DEB/Lazarus%204.8"
    for deb in fpc-laz_3.2.2-210709_amd64.deb fpc-src_3.2.2-210709_amd64.deb lazarus-project_4.8.0-0_amd64.deb; do
        wget -c -O "$ASSETS/downloads/$deb" "$LAZ_URL/$deb" || true
        # SourceForge publishes no checksum next to these, so ask dpkg whether the archive is whole.
        # A mirror that ignores the resume request appends a second copy; 'wget -c' would then
        # call that oversized file complete on every later run.
        if ! dpkg-deb --info "$ASSETS/downloads/$deb" > /dev/null 2>&1; then
            echo "$deb is incomplete or damaged; downloading it again from scratch..."
            rm -f "$ASSETS/downloads/$deb"
            wget -O "$ASSETS/downloads/$deb" "$LAZ_URL/$deb"
            if ! dpkg-deb --info "$ASSETS/downloads/$deb" > /dev/null 2>&1; then
                echo "ERROR: $deb is still not a valid .deb after a fresh download. Aborting."
                rm -f "$ASSETS/downloads/$deb"
                exit 1
            fi
        fi
    done

    echo "Installing Lazarus packages in strict order..."
    sudo apt install -y "$ASSETS"/downloads/fpc-laz_*.deb
    sudo apt install -y "$ASSETS"/downloads/fpc-src_*.deb
    sudo apt install -y "$ASSETS"/downloads/lazarus-project_*.deb

    echo "Cleaning up Lazarus installers..."
    rm -f "$ASSETS"/downloads/fpc-laz_*.deb "$ASSETS"/downloads/fpc-src_*.deb "$ASSETS"/downloads/lazarus-project_*.deb
else
    echo "Skipping Lazarus 4.8. (Run with 'install-lazarus' flag to enable)"
fi

# Godot game engine: standard (GDScript) and .NET (C#) editors, side by side (added in v66)
if [[ "$FLAGS" =~ " install-godot " ]] || [[ "$FLAGS" =~ " install-godot-templates " ]]; then
    echo "Installing Godot (standard + .NET editors)..."
    # Crostini's GPU acceleration is OpenGL through virgl; Vulkan is not exposed. Godot's Forward+
    # and Mobile renderers need Vulkan, its Compatibility renderer needs OpenGL 3.3 / GLES 3.0,
    # so on these machines Godot runs with the Compatibility renderer. The launchers below pass
    # '--rendering-driver opengl3' unless you pick a driver yourself (flag or GODOT_RENDERING_DRIVER).
    # New projects: choose "Compatibility" in the project manager's renderer box.
    #
    # The release tag comes from the redirect of releases/latest, not the GitHub API: the API is
    # rate-limited per IP for anonymous callers and answers 403 when the limit is spent.
    # Pin a version with GODOT_VERSION=4.7.2-stable ./dev-setup-... install-godot
    GODOT_TAG="${GODOT_VERSION:-}"
    if [ -z "$GODOT_TAG" ]; then
        GODOT_TAG=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/godotengine/godot/releases/latest | sed 's|.*/tag/||')
    fi
    if ! [[ "$GODOT_TAG" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?-stable$ ]]; then
        echo "ERROR: could not resolve the latest Godot release tag (got '$GODOT_TAG'). Pass GODOT_VERSION=<x.y.z>-stable."
        exit 1
    fi
    GODOT_URL="https://github.com/godotengine/godot/releases/download/$GODOT_TAG"
    GODOT_ROOT="$HOME/.local/opt/godot"
    GODOT_DIR="$GODOT_ROOT/$GODOT_TAG"
    GODOT_STD_ZIP="Godot_v${GODOT_TAG}_linux.x86_64.zip"
    GODOT_NET_ZIP="Godot_v${GODOT_TAG}_mono_linux_x86_64.zip"
    GODOT_DL="$ASSETS/downloads"

    # Runtime libraries the official binaries dlopen. Chrome and GTK already pull most of them in;
    # named here so a base-only machine gets them too.
    sudo apt install -y unzip libxcursor1 libxinerama1 libxrandr2 libxi6 libxkbcommon0 libgl1 libegl1 \
        libpulse0 libfontconfig1 libdbus-1-3 mesa-utils
    # mesa-utils (glxinfo, eglinfo): the test script uses them to tell WHERE software rendering
    # comes from when Godot reports llvmpipe: no GPU in the VM, or only the X11 path unaccelerated.

    # Both archives are checked against the release's SHA512-SUMS.txt before anything is unpacked.
    godot_fetch() {   # godot_fetch FILE : resumable download into assets/downloads + checksum
        wget -c -q --show-progress -O "$GODOT_DL/$1" "$GODOT_URL/$1"
        ( cd "$GODOT_DL" && grep -F " $1" SHA512-SUMS.txt | sha512sum -c - ) || {
            echo "ERROR: checksum mismatch for $1 (a partial download?). Deleting it; rerun to fetch again."
            rm -f "$GODOT_DL/$1"
            exit 1
        }
    }
    wget -q -O "$GODOT_DL/SHA512-SUMS.txt" "$GODOT_URL/SHA512-SUMS.txt"

    if [[ "$FLAGS" =~ " install-godot " ]]; then
        if [ -x "$GODOT_DIR/standard/godot.x86_64" ] && [ -x "$GODOT_DIR/mono/godot-mono.x86_64" ]; then
            echo "Godot $GODOT_TAG already installed in $GODOT_DIR."
        else
            godot_fetch "$GODOT_STD_ZIP"
            godot_fetch "$GODOT_NET_ZIP"
            rm -rf "$GODOT_DIR.partial"
            mkdir -p "$GODOT_DIR.partial/standard" "$GODOT_DIR.partial/unz"
            # Standard build: the zip holds one self-contained binary.
            unzip -q -o "$GODOT_DL/$GODOT_STD_ZIP" -d "$GODOT_DIR.partial/unz"
            mv "$GODOT_DIR.partial/unz/Godot_v${GODOT_TAG}_linux.x86_64" "$GODOT_DIR.partial/standard/godot.x86_64"
            # .NET build: a folder with the binary plus GodotSharp/, which must stay next to it.
            unzip -q -o "$GODOT_DL/$GODOT_NET_ZIP" -d "$GODOT_DIR.partial/unz"
            mv "$GODOT_DIR.partial/unz/Godot_v${GODOT_TAG}_mono_linux_x86_64" "$GODOT_DIR.partial/mono"
            mv "$GODOT_DIR.partial/mono/Godot_v${GODOT_TAG}_mono_linux.x86_64" "$GODOT_DIR.partial/mono/godot-mono.x86_64"
            rmdir "$GODOT_DIR.partial/unz"
            chmod +x "$GODOT_DIR.partial/standard/godot.x86_64" "$GODOT_DIR.partial/mono/godot-mono.x86_64"
            rm -rf "$GODOT_DIR"
            mv "$GODOT_DIR.partial" "$GODOT_DIR"
            rm -f "$GODOT_DL/$GODOT_STD_ZIP" "$GODOT_DL/$GODOT_NET_ZIP"
        fi
        # 'current' is what the launchers follow. Older versions are removed once the new one is in
        # place: projects opened in a newer editor are converted forward and do not go back.
        ln -sfn "$GODOT_TAG" "$GODOT_ROOT/current"
        for old in "$GODOT_ROOT"/*-stable; do
            if [ -d "$old" ] && [ "$old" != "$GODOT_DIR" ]; then rm -rf "$old"; fi
        done

        mkdir -p ~/.local/bin ~/.local/share/applications ~/.local/share/icons
        godot_launcher() {   # godot_launcher NAME BINARY
            cat > "$HOME/.local/bin/$1" << EOF
#!/bin/sh
# Written by dev-setup (install-godot); rewritten on every run.
# Crostini exposes OpenGL (virgl), not Vulkan, so default to the OpenGL driver / Compatibility
# renderer unless the caller chose one. GODOT_RENDERING_DRIVER=vulkan overrides the default.
BIN="\$HOME/.local/opt/godot/current/$2"
case " \$* " in
    *" --rendering-driver "*|*" --rendering-method "*|*" --headless "*|*" --version "*|*" --help "*) exec "\$BIN" "\$@" ;;
esac
# GODOT_DISPLAY_DRIVER=wayland picks Godot's native Wayland backend instead of X11 (Xwayland).
case " \$* " in
    *" --display-driver "*) exec "\$BIN" --rendering-driver "\${GODOT_RENDERING_DRIVER:-opengl3}" "\$@" ;;
esac
exec "\$BIN" --rendering-driver "\${GODOT_RENDERING_DRIVER:-opengl3}" \${GODOT_DISPLAY_DRIVER:+--display-driver "\$GODOT_DISPLAY_DRIVER"} "\$@"
EOF
            chmod +x "$HOME/.local/bin/$1"
        }
        godot_launcher godot standard/godot.x86_64
        godot_launcher godot-mono mono/godot-mono.x86_64

        # Launcher icon and ChromeOS app-drawer entries (best effort: the editors work without them).
        curl -fsSL "https://raw.githubusercontent.com/godotengine/godot/$GODOT_TAG/main/app_icon.png" -o ~/.local/share/icons/godot.png || true
        for entry in "godot|Godot Engine|godot" "godot-mono|Godot Engine (.NET)|godot-mono"; do
            IFS='|' read -r d_id d_name d_cmd <<< "$entry"
            cat > "$HOME/.local/share/applications/$d_id.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$d_name
Comment=2D and 3D game engine (OpenGL / Compatibility renderer on Crostini)
Exec=$HOME/.local/bin/$d_cmd --project-manager
Icon=$HOME/.local/share/icons/godot.png
Terminal=false
Categories=Development;IDE;Game;
StartupWMClass=Godot
EOF
        done
        echo "Godot: $("$HOME/.local/bin/godot" --version 2>/dev/null)   .NET: $("$HOME/.local/bin/godot-mono" --version 2>/dev/null)"
        echo "Run 'godot' or 'godot-mono' (or pick them from the ChromeOS launcher). C# projects use the .NET SDK from install-dotnet."
        echo "Exporting games needs the export templates (~2.5 GB): rerun with install-godot-templates."
    fi

    # Export templates: opt-in, NOT part of install-all (about 1.2 GB per flavour to download, more
    # unpacked). The editor looks for them in ~/.local/share/godot/export_templates/<version>/.
    if [[ "$FLAGS" =~ " install-godot-templates " ]]; then
        GODOT_TPL_ROOT="$HOME/.local/share/godot/export_templates"
        mkdir -p "$GODOT_TPL_ROOT"
        for tpz in "Godot_v${GODOT_TAG}_export_templates.tpz" "Godot_v${GODOT_TAG}_mono_export_templates.tpz"; do
            # version.txt inside the archive names the folder the editor expects (4.7.2.stable, 4.7.2.stable.mono).
            want="${GODOT_TAG/-/.}"; case "$tpz" in *_mono_*) want="$want.mono" ;; esac
            if [ -f "$GODOT_TPL_ROOT/$want/version.txt" ]; then
                echo "Export templates $want already installed."
                continue
            fi
            godot_fetch "$tpz"
            rm -rf "$GODOT_TPL_ROOT/_unpack"
            unzip -q -o "$GODOT_DL/$tpz" -d "$GODOT_TPL_ROOT/_unpack"
            tpl_ver=$(cat "$GODOT_TPL_ROOT/_unpack/templates/version.txt")
            rm -rf "${GODOT_TPL_ROOT:?}/$tpl_ver"
            mv "$GODOT_TPL_ROOT/_unpack/templates" "$GODOT_TPL_ROOT/$tpl_ver"
            rmdir "$GODOT_TPL_ROOT/_unpack"
            rm -f "$GODOT_DL/$tpz"
            echo "Installed export templates $tpl_ver"
        done
    fi
    rm -f "$GODOT_DL/SHA512-SUMS.txt"
else
    echo "Skipping Godot. (Run with 'install-godot' flag to enable; 'install-godot-templates' adds the export templates)"
fi

# Flatpak & Media Tools
if [[ "$FLAGS" =~ " install-media " ]]; then
    echo "Installing Flatpak, Handbrake, and KDiff3..."
    sudo apt install -y flatpak gnome-software-plugin-flatpak plasma-discover-backend-flatpak
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo flatpak install -y flathub fr.handbrake.ghb org.kde.kdiff3
else
    echo "Skipping Media Tools. (Run with 'install-media' flag to enable)"
fi

# Google Antigravity Platform
if [[ "$FLAGS" =~ " install-antigravity " ]]; then
    echo "Installing Google Antigravity Platform..."

    echo "Creating Python virtual environment for Antigravity SDK..."
    make_venv "$HOME/.antigravity-env"
    ~/.antigravity-env/bin/pip install google-antigravity

    curl -fsSL https://antigravity.google/cli/install.sh | bash

    # v73: install the graphical Antigravity from a tarball you downloaded into ./assets. Google ships the
    # current IDE (and the separate Antigravity 2.0 desktop app) only as tarballs on
    # antigravity.google/download, with no stable URL; its apt repository carries the legacy 1.x IDE.
    # Earlier versions just unpacked the file into ~/.local/antigravity and pointed at a "setup
    # launcher" current tarballs no longer contain, leaving no command and no app-drawer entry.
    # Now: detect which product the tarball holds, install it under /opt, make the Chromium
    # sandbox helper root-owned 4755 (Electron refuses to start with a user-owned one when it
    # needs the setuid sandbox), link the command into ~/.local/bin and add a launcher entry.
    # Rerunning with the same tarball is a no-op (checksum recorded); a newer tarball replaces
    # the install and keeps the previous one as <dir>.previous.
    install_ag_tarball() {   # install_ag_tarball TARBALL
        local tgz="$1" top kind dir bin name wmclass sum tmp icon
        top=$(tar -tzf "$tgz" 2> /dev/null | head -n 1 | cut -d/ -f1)
        case "$top" in
            "Antigravity IDE")  kind=ide; dir=/opt/antigravity-ide; bin=antigravity-ide; name="Antigravity IDE"; wmclass=antigravity-ide ;;
            Antigravity-x64)    kind=app; dir=/opt/antigravity;     bin=antigravity;     name="Antigravity";     wmclass=Antigravity ;;
            *) echo "NOTICE: $tgz is not a recognised Antigravity Linux x64 tarball (top folder '$top'); skipped."; return 0 ;;
        esac
        sum=$(sha256sum "$tgz" | cut -d' ' -f1)
        if [ -x "$dir/current/$bin" ] && [ "$(cat "$dir/.tarball-sha256" 2> /dev/null)" = "$sum" ]; then
            echo "$name from $(basename "$tgz") is already installed in $dir."
        else
            echo "Installing $name from $(basename "$tgz") into $dir..."
            tmp=$(mktemp -d)
            tar -xzf "$tgz" -C "$tmp"
            if [ ! -x "$tmp/$top/$bin" ]; then
                echo "NOTICE: $bin not found inside $(basename "$tgz"); skipped."; rm -rf "$tmp"; return 0
            fi
            sudo rm -rf "$dir.new"
            sudo mkdir -p "$dir.new"
            sudo cp -a "$tmp/$top" "$dir.new/current"
            rm -rf "$tmp"
            if [ -f "$dir.new/current/chrome-sandbox" ]; then
                sudo chown root:root "$dir.new/current/chrome-sandbox"
                sudo chmod 4755 "$dir.new/current/chrome-sandbox"
            fi
            echo "$sum" | sudo tee "$dir.new/.tarball-sha256" > /dev/null
            if [ -d "$dir" ]; then sudo rm -rf "$dir.previous"; sudo mv "$dir" "$dir.previous"; fi
            sudo mv "$dir.new" "$dir"
        fi
        mkdir -p ~/.local/bin ~/.local/share/applications ~/.local/share/icons
        ln -sfn "$dir/current/$bin" "$HOME/.local/bin/$bin"
        # Icon: the IDE ships a PNG; the desktop app keeps its icon inside resources/app.asar.
        icon="$HOME/.local/share/icons/$bin.png"
        if [ "$kind" = ide ] && [ -f "$dir/current/resources/app/resources/linux/code.png" ]; then
            cp "$dir/current/resources/app/resources/linux/code.png" "$icon"
        elif [ "$kind" = app ] && [ -f "$dir/current/resources/app.asar" ]; then
            python3 - "$dir/current/resources/app.asar" "$icon" << 'PY' || true
import json, struct, sys
from pathlib import Path
asar, out = Path(sys.argv[1]), Path(sys.argv[2])
with asar.open("rb") as f:
    f.read(4); header_size = struct.unpack("<I", f.read(4))[0]; f.read(4)
    json_size = struct.unpack("<I", f.read(4))[0]
    entry = json.loads(f.read(json_size).decode())["files"]["icon.png"]
    f.seek(8 + header_size + int(entry["offset"])); out.write_bytes(f.read(int(entry["size"])))
PY
        fi
        # Exec is absolute: the ChromeOS launcher starts apps without your ~/.bashrc PATH.
        cat > "$HOME/.local/share/applications/$bin.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=Google $name
Exec=$dir/current/$bin %U
Icon=$( [ -s "$icon" ] && echo "$icon" || echo text-editor )
Terminal=false
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=$wmclass
EOF
        echo "$name: run '$bin' or pick it from the ChromeOS launcher (it can take a minute to appear)."
    }

    # Every Antigravity tarball in ./assets (then the current directory) is installed: the IDE and
    # the desktop app can sit side by side. The tarballs stay in ./assets for later reruns.
    AG_FOUND=0
    while IFS= read -r tgz; do
        [ -n "$tgz" ] || continue
        AG_FOUND=1
        install_ag_tarball "$tgz"
    done < <(ls -t "$ASSETS"/*[Aa]ntigravity*.tar.gz ./*[Aa]ntigravity*.tar.gz 2> /dev/null || true)
    # Earlier versions unpacked into ~/.local/antigravity, which nothing used; remove it once /opt has an install.
    if [ -d ~/.local/antigravity ] && { [ -x /opt/antigravity-ide/current/antigravity-ide ] || [ -x /opt/antigravity/current/antigravity ]; }; then
        rm -rf ~/.local/antigravity
        echo "Removed the unused ~/.local/antigravity left by an older version of this installer."
    fi
    if [ "$AG_FOUND" = 0 ]; then
        echo "================================================================="
        echo "NOTICE: no Antigravity IDE / desktop-app tarball found."
        echo "Download the Linux x64 tarball of Antigravity IDE (and/or the Antigravity 2.0"
        echo "desktop app) from https://antigravity.google/download, put it in"
        echo "  $ASSETS"
        echo "and rerun with install-antigravity. The CLI (agy) and the SDK are installed already."
        echo "================================================================="
    fi

    echo "================================================================="
    echo "IMPORTANT: To run custom agentic scripts with Antigravity,"
    echo "you must activate the virtual environment first by running:"
    echo "  source ~/.antigravity-env/bin/activate"
    echo "================================================================="
else
    echo "Skipping Google Antigravity Platform. (Run with 'install-antigravity' flag to enable)"
fi

# Mobile App Development Frameworks
if [[ "$FLAGS" =~ " install-mobile " ]] || [[ "$FLAGS" =~ " install-tauri " ]] || [[ "$FLAGS" =~ " install-rn " ]] || [[ "$FLAGS" =~ " install-flutter " ]] || [[ "$FLAGS" =~ " install-android-native " ]]; then
    echo "================================================================="
    echo "Installing Base Android Dependencies & Command-Line Tools..."
    echo "================================================================="
    # v63: JDK + JAVA_HOME now come from install_jdk_and_java_home() (shared with install-java).
    install_jdk_and_java_home
    sudo apt install -y wget unzip

    mkdir -p $HOME/.android/sdk/cmdline-tools
    export ANDROID_HOME="$HOME/.android/sdk"

    echo "Downloading Android Command-Line Tools..."
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip -O /tmp/cmdline-tools.zip
    unzip -q /tmp/cmdline-tools.zip -d $HOME/.android/sdk/cmdline-tools
    rm -rf $HOME/.android/sdk/cmdline-tools/latest
    mv $HOME/.android/sdk/cmdline-tools/cmdline-tools $HOME/.android/sdk/cmdline-tools/latest
    rm /tmp/cmdline-tools.zip

    export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

    if ! grep -q 'export ANDROID_HOME' ~/.bashrc; then
        echo 'export ANDROID_HOME="$HOME/.android/sdk"' >> ~/.bashrc
        echo 'export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"' >> ~/.bashrc
    fi

    # -----------------------------------------------------------------
    # Install the actual SDK components (previous versions only fetched the
    # sdkmanager itself). Needed by native Kotlin apps, Flutter, and Tauri.
    # -----------------------------------------------------------------
    echo "Accepting Android SDK licenses and installing SDK components..."
    # 'yes 2>/dev/null' silences the harmless "Broken pipe" and keeps this safe
    # under a future 'set -o pipefail'.
    yes 2>/dev/null | sdkmanager --licenses > /dev/null 2>&1 || true
    # Pick the newest stable versions from sdkmanager's catalog, falling back to
    # known-good pins if the catalog can't be parsed for any reason.
    # v50: since API 37 platform packages carry a minor suffix (platforms;android-37.0).
    # The v49 regex truncated it to "android-37", which sdkmanager rejects and
    # set -e then aborted the run. Match the optional suffix and sort by version.
    SDK_LIST=$(sdkmanager --list 2>/dev/null || true)
    ANDROID_PLATFORM=$(echo "$SDK_LIST" | grep -oE 'platforms;android-[0-9]+(\.[0-9]+)?' | sort -uV | tail -1)
    ANDROID_BUILD_TOOLS=$(echo "$SDK_LIST" | grep -oE 'build-tools;[0-9]+\.[0-9]+\.[0-9]+' | sort -uV | tail -1)
    ANDROID_NDK=$(echo "$SDK_LIST" | grep -oE 'ndk;[0-9]+\.[0-9]+\.[0-9]+' | sort -uV | tail -1)
    : "${ANDROID_PLATFORM:=platforms;android-37.0}"
    : "${ANDROID_BUILD_TOOLS:=build-tools;36.0.0}"
    : "${ANDROID_NDK:=ndk;27.2.12479018}"
    echo "Installing platform-tools, $ANDROID_PLATFORM, $ANDROID_BUILD_TOOLS, $ANDROID_NDK ..."
    if ! sdkmanager "platform-tools" "$ANDROID_PLATFORM" "$ANDROID_BUILD_TOOLS" "$ANDROID_NDK"; then
        echo "ERROR: sdkmanager could not install one of: $ANDROID_PLATFORM $ANDROID_BUILD_TOOLS $ANDROID_NDK"
        echo "       Check names with: sdkmanager --list | grep -E 'platforms;android-3[6-9]|build-tools;|ndk;'"
        echo "       Override with e.g.: ANDROID_PLATFORM='platforms;android-37.0' $0 install-android-native"
        exit 1
    fi
    yes 2>/dev/null | sdkmanager --licenses > /dev/null 2>&1 || true
    # NOTE: sdkmanager is deprecated in favor of 'android sdk' (same cmdline-tools dir).
    # Still works today; migrate in a later version.

    # v51: Tauri's Android tooling requires NDK_HOME (and JAVA_HOME); neither was exported.
    NDK_DIR=$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1)
    # v63: JAVA_HOME was exported (and written to ~/.bashrc) by install_jdk_and_java_home above.
    if [ -z "$NDK_DIR" ]; then
        echo "ERROR: could not resolve NDK_HOME (no NDK under $ANDROID_HOME/ndk)."
        exit 1
    fi
    export NDK_HOME="$NDK_DIR"
    if ! grep -q 'export NDK_HOME' ~/.bashrc; then
        echo "export NDK_HOME=\"$NDK_DIR\"" >> ~/.bashrc
    fi

    if [[ "$FLAGS" =~ " install-mobile " ]] || [[ "$FLAGS" =~ " install-tauri " ]]; then
        echo "Setting up Tauri for Mobile..."
        # v51: prebuilt CLI via npm instead of 'cargo install tauri-cli', which compiles from
        # source for 20-30 min on an N305. Node is guaranteed here by the dependency guard.
        npm install -g @tauri-apps/cli
        rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
    fi

    if [[ "$FLAGS" =~ " install-mobile " ]] || [[ "$FLAGS" =~ " install-rn " ]]; then
        echo "Setting up React Native (Expo CLI)..."
        # v62: same npm 12 allow-list as install-node; these two are eas-cli's scripted dependencies.
        npm install -g --allow-scripts=dtrace-provider,protobufjs eas-cli
    fi

    if [[ "$FLAGS" =~ " install-mobile " ]] || [[ "$FLAGS" =~ " install-flutter " ]]; then
        echo "Setting up Flutter..."
        # v52: Linux desktop target toolchain ('flutter doctor' flagged these); harmless if unused.
        sudo apt install -y clang cmake ninja-build mesa-utils
        if [ -d "$HOME/.flutter/.git" ]; then
            echo "Flutter already present at ~/.flutter, updating instead of cloning..."
            git -C "$HOME/.flutter" pull --ff-only
        else
            git clone https://github.com/flutter/flutter.git -b stable "$HOME/.flutter"
        fi
        if ! grep -q '.flutter/bin' ~/.bashrc; then
            echo 'export PATH="$PATH:$HOME/.flutter/bin"' >> ~/.bashrc
        fi
        export PATH="$PATH:$HOME/.flutter/bin"
    fi
    echo "Mobile frameworks installed! Remember to run 'source ~/.bashrc' later."
    if [[ "$FLAGS" =~ " install-mobile " ]] || [[ "$FLAGS" =~ " install-tauri " ]]; then
        echo "Tauri CLI is the npm build: use 'tauri android init' (not 'cargo tauri ...')."
    fi
else
    echo "Skipping Mobile Frameworks. (Run with 'install-mobile', 'install-tauri', 'install-rn', or 'install-flutter' flag to enable)"
fi

# Native Android (Kotlin) development: Android Studio + Kotlin compiler
if [[ "$FLAGS" =~ " install-android-native " ]]; then
    echo "================================================================="
    echo "Installing Native Android (Kotlin) Development Tools..."
    echo "================================================================="
    # Android Studio for ChromeOS. v52: Google names the .deb by codename
    # (e.g. android-studio-quail4-patch1-cros.deb) under a separate build number (2026.1.4.8),
    # so the v51 version-only URL could never be constructed. Scrape the current link from the
    # download page instead; ANDROID_STUDIO_URL overrides it.
    ANDROID_STUDIO_URL="${ANDROID_STUDIO_URL:-$(curl -fsSL https://developer.android.com/studio \
        | grep -oE 'https://[^"]+-cros\.deb' | head -n 1)}"

    if [ -x /opt/android-studio/bin/studio.sh ] || [ -x /opt/android-studio/bin/studio ]; then
        echo "Android Studio already installed at /opt/android-studio, skipping download."
    elif [ -n "$ANDROID_STUDIO_URL" ] && curl -fsSIL "$ANDROID_STUDIO_URL" > /dev/null 2>&1; then
        echo "Downloading $(basename "$ANDROID_STUDIO_URL") for ChromeOS (about 1.2GB)..."
        # Resumable + retrying: a 1.2GB transfer can get a TCP reset mid-way. 'wget -c' picks up
        # where a partial file left off, on retry and on a rerun of this script alike, so the
        # partial is kept on failure rather than deleted.
        if wget -c --tries=10 --waitretry=5 --retry-connrefused --progress=bar:force \
                -O /tmp/android-studio.deb "$ANDROID_STUDIO_URL"; then
            sudo apt install -y /tmp/android-studio.deb
            rm -f /tmp/android-studio.deb
        else
            echo "ERROR: Android Studio download failed after retries; the partial file is kept."
            echo "       Rerun '$0 install-android-native' to resume it."
            exit 1
        fi
    else
        echo "WARNING: could not find the ChromeOS Android Studio .deb link on developer.android.com."
        echo "         Copy the ChromeOS link from https://developer.android.com/studio and rerun with:"
        echo "         ANDROID_STUDIO_URL=<link to ...-cros.deb> $0 install-android-native"
    fi

    # v70: keep Android Studio on the X11 toolkit. Its bundled JetBrains runtime now defaults to
    # native Wayland, and under ChromeOS's Wayland the IDE window dims while it has focus. XToolkit
    # (through sommelier) renders normally. Written to the install-wide file, which covers a
    # fresh install before the IDE has created its per-user config, and to every per-user file
    # that already exists ("Help > Edit Custom VM Options"), since a user file can take
    # precedence. An existing awt.toolkit.name line is replaced, not duplicated.
    # Undo: delete the line from both places (the install-wide file is restored by a reinstall).
    pin_xtoolkit() {   # pin_xtoolkit FILE [sudo]
        local f="$1" run="${2:-}"
        if [ -f "$f" ] && grep -q '^-Dawt\.toolkit\.name=' "$f"; then
            $run sed -i 's/^-Dawt\.toolkit\.name=.*/-Dawt.toolkit.name=XToolkit/' "$f"
        else
            echo '-Dawt.toolkit.name=XToolkit' | $run tee -a "$f" > /dev/null
        fi
    }
    if [ -d /opt/android-studio/bin ]; then
        pin_xtoolkit /opt/android-studio/bin/studio64.vmoptions sudo
        for uf in "$HOME"/.config/Google/AndroidStudio*/studio64.vmoptions; do
            [ -f "$uf" ] && pin_xtoolkit "$uf"
        done
        echo "Android Studio pinned to the X11 toolkit (avoids the focused-window dimming under Wayland on ChromeOS)."
    fi

    # Standalone Kotlin compiler for scripts/REPL use. Android projects don't need this
    # (the Gradle Kotlin plugin ships its own compiler), but it's handy for kotlinc/kts.
    echo "Installing standalone Kotlin compiler via Homebrew..."
    brew install kotlin
    unlink_brew_openjdk   # v64: kotlin depends on brew's openjdk too; kotlinc uses JAVA_HOME

    echo ""
    echo "Native Android setup complete. To run apps without an emulator (Crostini can't"
    echo "run the Android emulator), deploy directly to this Chromebook's Android runtime:"
    echo "  1. ChromeOS Settings -> About ChromeOS -> Linux development environment"
    echo "     -> Develop Android apps -> Enable ADB debugging (requires a restart)."
    echo "  2. From the Linux terminal: adb connect arc   (accept the 'Allow USB debugging?'"
    echo "     dialog on the ChromeOS side once). Then 'adb devices', Android Studio and"
    echo "     'flutter devices' all show the Chromebook as a connected device."
    echo "  3. Give the Linux VM more disk (ChromeOS Settings -> Linux -> Disk size);"
    echo "     Studio + SDK + Gradle caches need ~10GB, and close Ollama while building."
else
    echo "Skipping Native Android (Kotlin) tools. (Run with 'install-android-native' flag to enable)"
fi

# Database Connectivity & Extraction
if [[ "$FLAGS" =~ " install-db " ]]; then
    echo "================================================================="
    echo "Installing Database Connectivity & Extraction Tools..."
    echo "================================================================="

    sudo apt install -y unixodbc unixodbc-dev odbc-mdbtools

    # v63: the repo step is now add_microsoft_prod_repo() (shared with install-dotnet).
    add_microsoft_prod_repo

    sudo env ACCEPT_EULA=Y apt install -y msodbcsql18

    echo "Installing pxlib for Paradox data extraction..."
    sudo apt install -y pxlib1 pxlib-dev

    echo "Installing native Lazarus database client libraries..."
    sudo apt install -y libpq-dev       # PostgreSQL
    sudo apt install -y libmariadb-dev  # MariaDB / MySQL
    sudo apt install -y libsqlite3-dev  # SQLite

    # v80: Firebird 4 (Debian's firebird4.0): client library, tools and the embedded engine, so a
    # program or a Lazarus app opens a .fdb file directly with no server running. Firebird forked
    # from InterBase 6.0 in 2000; neither its client nor its engine opens a modern InterBase
    # database (that is install-interbase). Debian names Firebird's isql 'isql-fb', because
    # unixODBC (above) owns 'isql', and its gstat 'fbstat'; gbak, gfix and nbackup keep their
    # names. firebird-dev adds the unversioned libfbclient.so. No server package, so nothing
    # listens on port 3050; add firebird4.0-server by hand for a networked Firebird (it asks for a
    # SYSDBA password).
    # v81: firebird-utils is named too. Debian packages Firebird so several major versions can sit
    # side by side: the binaries live under /usr/lib/<triplet>/firebird/4.0/bin (firebird4.0-utils)
    # and firebird-utils holds the /usr/bin command names the test, init and demo scripts call.
    # Lazarus / Free Pascal: SQLdb's TIBConnection talks to Firebird. Give it a TSQLDBLibraryLoader
    # (ConnectionType 'Firebird', LibraryName 'libfbclient.so.2'): FPC's built-in list of client
    # library names does not always match what Debian ships, and with InterBase installed too the
    # loader is how a program says which of the two it means.
    echo "Installing Firebird 4 (client library, tools, embedded engine)..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y libfbclient2 firebird-dev firebird-utils firebird4.0-utils firebird4.0-server-core
    # Embedded access keeps lock files in a shared directory (/tmp/firebird unless told otherwise).
    # If another user or a server package created it first, every embedded open fails with "Can
    # not access lock files directory". Probe once with a throwaway database; if the default fails
    # and a private directory works, FIREBIRD_LOCK goes into a marked ~/.bashrc block. Every
    # program opening the same .fdb must use the same lock directory, so it is all or nothing.
    FB_ISQL=$(command -v isql-fb || ls /usr/lib/*/firebird/*/bin/isql 2> /dev/null | head -n 1 || true)
    fb_probe() {   # fb_probe: create, query and drop an embedded database; prints Firebird's error on failure
        local d out
        d=$(mktemp -d)
        out=$(printf "CREATE DATABASE '%s/probe.fdb';\nSELECT 'fb-ok' FROM RDB\$DATABASE;\nDROP DATABASE;\nQUIT;\n" "$d" \
            | ISC_USER=SYSDBA timeout 60 "$FB_ISQL" -q -b 2>&1)
        rm -rf "$d"
        echo "$out" | grep -q 'fb-ok' || { echo "$out" | tail -n 3; return 1; }
    }
    sed -i '/^# >>> dev-setup firebird >>>$/,/^# <<< dev-setup firebird <<<$/d' ~/.bashrc
    if [ -z "$FB_ISQL" ]; then
        echo "NOTICE: Firebird's isql was not found after the install; skipping the embedded-access probe."
    elif ( unset FIREBIRD_LOCK; fb_probe ) > /dev/null; then
        echo "Firebird embedded access works with the default lock directory."
    else
        mkdir -p "$HOME/.cache/firebird-lock"
        if FIREBIRD_LOCK="$HOME/.cache/firebird-lock" fb_probe; then
            cat >> ~/.bashrc << 'EOF'
# >>> dev-setup firebird >>>
# Written by dev-setup (install-db); rewritten on each run. Firebird's default lock directory was
# not writable for you, so embedded access (isql-fb, gbak, Lazarus apps) uses your own.
export FIREBIRD_LOCK="$HOME/.cache/firebird-lock"
# <<< dev-setup firebird <<<
EOF
            echo "Firebird: the default lock directory is not writable for $USER; FIREBIRD_LOCK=~/.cache/firebird-lock added to ~/.bashrc."
        else
            echo "NOTICE: Firebird embedded access failed even with a private lock directory; dev-test shows the error."
        fi
    fi
    [ -n "$FB_ISQL" ] && echo "Firebird: $("$FB_ISQL" -z < /dev/null 2>&1 | head -n 1)"
    echo "Try it: ISC_USER=SYSDBA isql-fb   then   CREATE DATABASE '/home/$USER/test.fdb';"
else
    echo "Skipping Database tools. (Run with 'install-db' flag to enable)"
fi

# Extra ODBC drivers: SQLite, PostgreSQL, MariaDB, and DuckDB (CSV/TSV/JSON/Parquet over SQL)
if [[ "$FLAGS" =~ " install-db-extra " ]]; then
    echo "================================================================="
    echo "Installing Extra ODBC Drivers (SQLite, PostgreSQL, MariaDB, DuckDB)..."
    echo "================================================================="
    # Each of these Debian packages registers its driver in /etc/odbcinst.ini on install:
    #   libsqliteodbc   -> [SQLite3]            (includes SQLite's csv virtual-table module)
    #   odbc-postgresql -> [PostgreSQL Unicode]  (and [PostgreSQL ANSI])
    #   odbc-mariadb    -> [MariaDB Unicode]     (works for MySQL too)
    sudo apt install -y unixodbc libsqliteodbc odbc-postgresql odbc-mariadb

    echo "Installing DuckDB ODBC driver (queries CSV/TSV/JSON/Parquet files directly with SQL)..."
    DUCKDB_ODBC_DIR="/opt/duckdb-odbc"
    DUCKDB_ODBC_URL="https://github.com/duckdb/duckdb-odbc/releases/latest/download/duckdb_odbc-linux-amd64.zip"
    curl -fsSL "$DUCKDB_ODBC_URL" -o /tmp/duckdb_odbc.zip
    sudo mkdir -p "$DUCKDB_ODBC_DIR"
    sudo unzip -o -q /tmp/duckdb_odbc.zip -d "$DUCKDB_ODBC_DIR"
    rm -f /tmp/duckdb_odbc.zip
    # Register the driver with odbcinst (merges into /etc/odbcinst.ini; idempotent on reruns).
    # We do this ourselves instead of running DuckDB's unixodbc_setup.sh, which also switches
    # on global ODBC tracing to /tmp/odbctrace.
    if ! odbcinst -q -d | grep -q '^\[DuckDB\]'; then
        cat << 'EOF_DUCK' > /tmp/duckdb_odbcinst.ini
[DuckDB]
Description = DuckDB ODBC driver
Driver      = /opt/duckdb-odbc/libduckdb_odbc.so
EOF_DUCK
        sudo odbcinst -i -d -f /tmp/duckdb_odbcinst.ini
        rm -f /tmp/duckdb_odbcinst.ini
    fi

    # A user DSN for querying flat files: an in-memory DuckDB, so any CSV/TSV/JSON/Parquet
    # path can be used as a table name, e.g.  SELECT * FROM '/home/user/data.csv' LIMIT 10;
    if ! grep -q '^\[CSV\]' ~/.odbc.ini 2>/dev/null; then
        cat << 'EOF_DSN' >> ~/.odbc.ini
[CSV]
Description = DuckDB in-memory DSN for querying CSV/TSV/JSON/Parquet files with SQL
Driver      = DuckDB
Database    = :memory:
EOF_DSN
    fi

    echo "Registered ODBC drivers:"
    odbcinst -q -d
    echo "Try it:  isql CSV   then   SELECT * FROM '$HOME/somefile.csv' LIMIT 5;"
else
    echo "Skipping Extra ODBC drivers. (Run with 'install-db-extra' flag to enable)"
fi

# =================================================================
# install-interbase : Embarcadero InterBase (added in v80). Opt-in, NOT in install-all; since v82 part
# of the install-db-server group (with install-mssql and install-oracle below). The installer is a
# registered download. Put what you downloaded from Embarcadero in ./assets:
# the InterBase zip, or the ib_install_linux_x86_64.bin / install_linux_x86_64.sh inside it, and a
# license slip file (*.slip, reg_*.txt) if you have one. The free Developer Edition allows local
# connections only (this machine), which is all a development box needs.
# The install is InterBase's own InstallAnywhere installer, run silently with a property file:
# Server install set, /opt/interbase, instance gds_db on TCP port 3050 (Firebird from install-db
# has no server, so the port is free). An unregistered Developer Edition server does not start:
# dev-init (install-interbase) runs InterBase's console License Manager and then starts it.
# Tools and library stay off the shared paths. InterBase's isql and gbak would shadow unixODBC's
# isql and Firebird's gbak, so ~/.bashrc gets ib-isql, ib-gbak and ib-mgr instead; and libgds.so
# is not linked into /usr/local/lib (the step InterBase's manual suggests), because Free Pascal's
# loader also tries 'libgds.so' and would then open InterBase where you meant Firebird. A Lazarus
# program names it: TSQLDBLibraryLoader, LibraryName '/opt/interbase/lib/libgds.so'.
# Default login SYSDBA / masterkey (INTERBASE_SYSDBA_PASSWORD in secrets.env once you change it).
# INTERBASE_REINSTALL=1 runs the installer again over an existing install.
# v81: a zip is unpacked into assets/downloads/interbase (not a temp folder that was deleted at once),
# so after a failed silent install the console-mode command printed below names a file that
# exists. That folder is removed once InterBase is installed; the zip itself stays in ./assets.
# =================================================================
if [[ "$FLAGS" =~ " install-interbase " ]]; then
    echo "================================================================="
    echo "Installing Embarcadero InterBase from ./assets..."
    echo "================================================================="
    IB_HOME=/opt/interbase
    IB_UNPACK="$ASSETS/downloads/interbase"
    if [ -x "$IB_HOME/bin/isql" ] && [ -e "$IB_HOME/lib/libgds.so" ] && [ "${INTERBASE_REINSTALL:-0}" != 1 ]; then
        echo "InterBase is already installed in $IB_HOME (INTERBASE_REINSTALL=1 runs the installer again)."
    else
        IB_TMP=$(mktemp -d)
        # A zip from the download page is unpacked first; the installer is looked for in ./assets (the
        # unpacked copy included).
        IB_ZIP=$(ls -t "$ASSETS"/*[Ii]nter[Bb]ase*.zip "$ASSETS"/downloads/*[Ii]nter[Bb]ase*.zip 2> /dev/null | head -n 1 || true)
        if [ -n "$IB_ZIP" ]; then
            echo "Unpacking $(basename "$IB_ZIP") into $IB_UNPACK..."
            rm -rf "$IB_UNPACK"
            unzip -q -o "$IB_ZIP" -d "$IB_UNPACK" || echo "NOTICE: could not unpack $IB_ZIP"
        fi
        IB_BIN=$(find "$ASSETS" -maxdepth 5 -type f -name 'ib_install_linux_x86_64.bin' 2> /dev/null | head -n 1 || true)
        IB_SH=$(find "$ASSETS" -maxdepth 5 -type f -name 'install_linux_x86_64.sh' 2> /dev/null | head -n 1 || true)
        IB_SLIP=$(find "$ASSETS" -maxdepth 5 -type f \( -name '*.slip' -o -name 'reg_*.txt' \) 2> /dev/null | head -n 1 || true)
        if [ -z "$IB_BIN$IB_SH" ]; then
            echo "================================================================="
            echo "NOTICE: no InterBase installer found. Download InterBase for Linux (the free Developer"
            echo "Edition: https://www.embarcadero.com/products/interbase/developer/free-download), put the"
            echo "zip (or the ib_install_linux_x86_64.bin inside it) and any license slip file in"
            echo "  $ASSETS"
            echo "and rerun with install-interbase. Keep the serial number from the download email for dev-init."
            echo "================================================================="
        else
            # InstallAnywhere property file: every answer the wizard would ask for.
            {
                echo "INSTALLER_UI=silent"
                echo "CHOSEN_INSTALL_SET=Server"
                echo "USER_INSTALL_DIR=$IB_HOME"
                echo "MULTI_INSTANCE=No"
                echo "INSTANCE_NAME=gds_db"
                echo "SERVER_TCP_PORT=3050"
                echo "REG=FALSE"
                if [ -n "$IB_SLIP" ]; then echo "SLIP_FILENAME=$IB_SLIP"; fi
            } > "$IB_TMP/values.txt"
            echo "Running the InterBase installer silently (Server, $IB_HOME, instance gds_db, port 3050)${IB_SLIP:+ with license file $(basename "$IB_SLIP")}..."
            if [ -n "$IB_BIN" ]; then
                chmod +x "$IB_BIN"
                ( cd "$(dirname "$IB_BIN")" && sudo "$IB_BIN" -i silent -f "$IB_TMP/values.txt" ) || echo "NOTICE: the InterBase installer exited with an error (details below)."
            else
                chmod +x "$IB_SH"
                ( cd "$(dirname "$IB_SH")" && sudo bash "$IB_SH" -i silent -f "$IB_TMP/values.txt" ) || echo "NOTICE: the InterBase installer exited with an error (details below)."
            fi
        fi
        rm -rf "$IB_TMP"
    fi

    if [ -x "$IB_HOME/bin/isql" ]; then
        # Installed: the unpacked copy of the zip is no longer needed (the zip stays for reinstalls).
        rm -rf "$IB_UNPACK"
        # v93: the installer leaves the linker cache stale (libgds.so was found only after install-oracle's
        # ldconfig, Oct 4 2026), so isql failed when install-interbase ran alone; refresh it here.
        sudo ldconfig
        # v93: the installer writes ibmgr (a small shell script) root-only, -rwxr--r--, so ib-server's check as
        # you saw no ibmgr and init reported a registered InterBase as "register it". Every tool in bin/ gets
        # the execute bit for everyone (they still run the server through sudo).
        sudo find "$IB_HOME/bin" -maxdepth 1 -type f -perm -u+x ! -perm -o+x -exec chmod a+rx {} + 2> /dev/null || true
        # InterBase is built for older distributions: report any shared library trixie does not provide.
        IB_MISSING=$(for f in "$IB_HOME"/bin/isql "$IB_HOME"/bin/gbak "$IB_HOME"/bin/ibserver "$IB_HOME"/lib/libgds.so; do
            [ -e "$f" ] && ldd "$f" 2> /dev/null | grep 'not found' | sed "s|^|  $(basename "$f"): |"
        done | sort -u || true)
        if [ -n "$IB_MISSING" ]; then
            echo "NOTICE: InterBase needs shared libraries this system lacks ('apt-file search <name>' finds the package):"
            echo "$IB_MISSING"
        fi
        # ~/.bashrc: INTERBASE and three wrappers, rewritten on every run. Nothing here runs at shell start.
        # v92: ib-mgr passes INTERBASE through sudo (sudo drops it), as InterBase's tools expect.
        sed -i '/^# >>> dev-setup interbase >>>$/,/^# <<< dev-setup interbase <<<$/d' ~/.bashrc
        cat >> ~/.bashrc << 'EOF'
# >>> dev-setup interbase >>>
# Written by dev-setup (install-interbase); replaced on each run. InterBase's tools are deliberately
# not on PATH: its isql and gbak would shadow unixODBC's isql and Firebird's gbak.
# 'ib-server start|stop|status' (in ~/.local/bin) starts the server safely; ib-mgr is ibmgr itself.
export INTERBASE=/opt/interbase
ib-isql() { /opt/interbase/bin/isql "$@"; }
ib-gbak() { /opt/interbase/bin/gbak "$@"; }
ib-mgr()  { sudo env INTERBASE=/opt/interbase /opt/interbase/bin/ibmgr "$@"; }
# <<< dev-setup interbase <<<
EOF
        # v92: ib-server. v91 started the server here while the Developer Edition was still unregistered:
        # ibguard (-forever) then restarted an ibserver that spun at 100% CPU without ever listening, and every
        # later 'ibmgr -start' (dev-init's, a manual one) stacked another ibguard on top that could not start
        # a server while that one existed. ib-server start: nothing to do when port 3050 answers; stray
        # ibguard/ibserver processes with nothing listening are stopped first; then ONE ibmgr start, a wait of
        # up to IB_WAIT seconds (default 20); and when the port still does not answer, ibmgr's output and the
        # tail of interbase.log are shown and what it started is stopped again, so nothing is left spinning.
        mkdir -p ~/.local/bin
        cat > ~/.local/bin/ib-server << 'IB_EOF'
#!/bin/bash
# ib-server - start, stop and inspect the InterBase server (dev-setup install-interbase, v92; v93).
# v93: ibmgr is checked through sudo too: the installer leaves it root-only, which v92 read as "not installed".
# Written by dev-setup and rewritten on every run: copy it before editing.
#   ib-server status   running (port 3050 answers), stuck (processes but no port), or stopped
#   ib-server start    start it once, safely (stops a stuck server first; stops it again if it never answers)
#   ib-server stop     stop every ibguard and ibserver
# The server does not start with Linux by itself: 'ib-server start' (or dev-init) after a restart.
# An unregistered Developer Edition cannot start: dev-init with install-interbase registers it first.
IB=/opt/interbase
WAIT=${IB_WAIT:-20}
listening() { (exec 3<> /dev/tcp/127.0.0.1/3050) 2> /dev/null; }
# By process name (-x), never by command line: a -f pattern also matches any shell whose command line
# mentions the path (pkill would then kill the terminal that ran it).
procs() { pgrep -x 'ibguard|ibserver' 2> /dev/null; }
describe() {
    local p
    for p in $(procs); do ps -o pid=,pcpu=,etime=,args= -p "$p" 2> /dev/null; done | sed 's/^/    /'
}
stop() {
    local i
    [ -n "$(procs)" ] || { echo "No InterBase processes."; return 0; }
    # ibguard first, so it does not restart the ibserver being stopped.
    sudo pkill -x ibguard 2> /dev/null; sudo pkill -x ibserver 2> /dev/null
    for ((i = 0; i < 10; i++)); do [ -n "$(procs)" ] || break; sleep 1; done
    if [ -n "$(procs)" ]; then sudo pkill -9 -x ibguard 2> /dev/null; sudo pkill -9 -x ibserver 2> /dev/null; sleep 1; fi
    if [ -n "$(procs)" ]; then echo "Some InterBase processes would not stop:"; describe; return 1; fi
    echo "InterBase stopped."
}
status() {
    if listening; then echo "InterBase is running (port 3050 answers)."; describe; return 0; fi
    if [ -n "$(procs)" ]; then
        echo "InterBase is STUCK: its processes run but nothing listens on port 3050 (most often a start before"
        echo "the Developer Edition was registered). 'ib-server stop', then 'ib-server start' (register first: dev-init)."
        describe; return 3
    fi
    echo "InterBase is stopped ('ib-server start')."; return 1
}
start() {
    local out i tmp
    if [ ! -x "$IB/bin/ibmgr" ]; then
        sudo test -x "$IB/bin/ibmgr" || { echo "InterBase is not installed in $IB (dev-setup with install-interbase)." >&2; return 1; }
        sudo chmod a+rx "$IB/bin/ibmgr" 2> /dev/null || true   # root-only from the installer; sudo runs it either way
    fi
    if listening; then echo "InterBase is already running (port 3050)."; return 0; fi
    if [ -n "$(procs)" ]; then echo "Stopping a stuck InterBase first (processes, no port):"; describe; stop || return 1; fi
    # To a file, not $(...): a command substitution would wait for the daemons ibmgr leaves holding its stdout.
    tmp=$(mktemp)
    # shellcheck disable=SC2024   # the file is ours on purpose
    sudo env INTERBASE="$IB" "$IB/bin/ibmgr" -start -forever > "$tmp" 2>&1 < /dev/null
    out=$(cat "$tmp"); rm -f "$tmp"
    for ((i = 0; i < WAIT; i++)); do
        listening && { echo "InterBase started (port 3050) after ${i}s."; return 0; }
        sleep 1
    done
    echo "InterBase did not answer on port 3050 within ${WAIT}s (IB_WAIT raises it). ibmgr said:"
    printf '%s\n' "${out:-(nothing)}" | sed 's/^/    /'
    if [ -r "$IB/interbase.log" ] || sudo test -r "$IB/interbase.log"; then
        echo "Last lines of $IB/interbase.log:"; sudo tail -n 8 "$IB/interbase.log" 2> /dev/null | sed 's/^/    /'
    fi
    echo "Stopping what this start left behind, so nothing keeps spinning. Unregistered? dev-init with install-interbase."
    stop > /dev/null
    return 1
}
case "${1:-status}" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    -h|--help|help) sed -n '2,/^IB=/{/^IB=/d;s/^# \{0,1\}//;p}' "$0" ;;
    *) echo "usage: ib-server start|stop|status" >&2; exit 2 ;;
esac
IB_EOF
        chmod +x ~/.local/bin/ib-server
        # v92: no start before registration. The License Manager (dev-init) writes the license into
        # /opt/interbase/license; until a license file other than the installer's own is there, setup
        # leaves the server stopped. With one (a slip file given to the installer, or a registration from
        # an earlier run) it starts it through ib-server, which never leaves a stuck server behind.
        # ibservice.sh is no longer used: as a boot service it started the unregistered server too.
        IB_LICENSED=0
        # Confirmed on a registered install (Oct 2 2026): the installer ships its own ibs15.slip (there before
        # any registration, so it does not count); the License Manager's Direct register writes a hidden
        # .<n>_<n>.slip; .cg_license and .cgb_license appear at the first server start, not at registration.
        # So a registration is any slip file other than the installer's ibs<NN>.slip (reg_*.txt kept too).
        if sudo find "$IB_HOME/license" -maxdepth 1 -type f \( \( -name '*.slip' ! -name 'ibs[0-9]*.slip' \) -o -name 'reg_*.txt' \) 2> /dev/null | grep -q .; then IB_LICENSED=1; fi
        if (exec 3<> /dev/tcp/127.0.0.1/3050) 2> /dev/null; then
            echo "InterBase server is running on port 3050."
        elif [ "$IB_LICENSED" = 1 ]; then
            "$HOME/.local/bin/ib-server" start \
                || echo "NOTICE: the InterBase server did not start (above). If it is not registered yet: dev-init with install-interbase."
        else
            "$HOME/.local/bin/ib-server" stop > /dev/null 2>&1 || true   # a stuck server left by v80-v91
            echo "InterBase is installed and NOT started: the Developer Edition must be registered first. dev-init with"
            echo "install-interbase runs the License Manager (serial number from the download email), then starts it."
        fi
        echo "InterBase: $($IB_HOME/bin/isql -z < /dev/null 2>&1 | head -n 1)"
        echo "Use it with ib-isql / ib-gbak (new terminals). Lazarus: TSQLDBLibraryLoader with LibraryName '$IB_HOME/lib/libgds.so'."
    elif [ -n "${IB_BIN:-}${IB_SH:-}" ]; then
        echo "NOTICE: InterBase did not end up in $IB_HOME. InstallAnywhere writes its log into the install"
        echo "        folder when it gets that far; rerun by hand in console mode to see the questions:"
        if [ -n "${IB_BIN:-}" ]; then
            echo "        sudo \"$IB_BIN\" -i console"
        else
            echo "        sudo bash \"$IB_SH\" -i console"
        fi
    fi
else
    echo "Skipping InterBase. (Run with 'install-interbase' or 'install-db-server' after putting the download in ./assets; not part of install-all)"
fi

# =================================================================
# install-db-server : database servers (added in v82). Opt-in, NOT in install-all. The group flag
# expands to install-mssql, install-oracle and install-interbase (above); each also works alone.
#   install-mssql   SQL Server 2025 in Docker (Developer edition: free for development and test),
#                   the Go sqlcmd, and ODBC Driver 18 (the one install-db installs too)
#   install-oracle  Oracle AI Database 26ai Free in Docker (the Lite image), SQLcl, and Oracle
#                   Instant Client with its ODBC driver
#   install-oracle-full  (v83, in no group) install-oracle on Oracle's full image
# Neither vendor packages its server for Debian 13 (SQL Server ships for Ubuntu and RHEL, Oracle Free
# for Oracle Linux and RHEL), so both run as their official Linux containers in the Docker from the
# base section. SQL Server's images are x86-64 only, which all four Chromebooks are.
# Memory: each engine holds about 2 GB while it runs (Oracle Free caps itself at 2 GB by license;
# SQL Server is capped at MSSQL_MEMORY_MB, default 2048 and no lower, in a container limited to 512 MB
# more), and Linux gets ~6.4 GB of an 8 GB Chromebook. So setup CREATES the containers but leaves them
# stopped, and ~/.local/bin gets two commands:
#   mssql  up | down | status | sql | logs | password     (127.0.0.1:1433, login sa)
#   oracle up | down | status | sql | logs | password     (127.0.0.1:1521, service FREEPDB1, login system)
# 'up' stops the other engine first (DEVDB_BOTH=1 keeps it running), and since v89 a running heavy
# engine of 'devsvc' (Solr, OpenSearch, Elasticsearch, Milvus, Atlas Local). Both publish on 127.0.0.1 only.
# Data lives in the named volumes devdb-mssql-data and devdb-oracle-data (devdb-oracle-full-data on
# the full image), which survive reruns, image updates and 'docker rm'. Start over: docker rm -f devdb-mssql && docker volume rm devdb-mssql-data,
# then rerun setup (the same for oracle).
# Passwords: MSSQL_SA_PASSWORD / ORACLE_PWD from the environment or secrets.env when set, otherwise
# generated here. They take effect when a data volume is first initialised; the container keeps the
# one it was created with, and 'mssql password' / 'oracle password' print it.
# Updates: a rerun pulls the image again. SQL Server's container is recreated on a newer image (the
# volume stays; SQL Server upgrades its databases on the next start). Oracle's is not recreated on its
# own, since a new release over an old data volume is a real upgrade: setup says what to do.
# DB_SERVER_RECREATE=1 recreates both. MSSQL_IMAGE / ORACLE_IMAGE pick other images, e.g.
# mcr.microsoft.com/mssql/server:2022-latest.
# v83: install-oracle-full runs Oracle's full image instead of the Lite one (~9.5 GB on disk against
# ~1.8 GB), with its own data volume, devdb-oracle-full-data; see the Oracle section below.
# One file lands outside /opt and your home directory: the libaio compatibility link (see below).
# =================================================================
if [[ "$FLAGS" =~ " install-mssql " ]] || [[ "$FLAGS" =~ " install-oracle " ]]; then
    echo "================================================================="
    echo "Installing database servers (Docker containers, clients, ODBC drivers)..."
    echo "================================================================="
    sudo apt install -y unixodbc unixodbc-dev unzip bzip2
    mkdir -p ~/.local/bin
    DB_MIN_FREE_GB="${DEV_DB_MIN_FREE_GB:-$(disk_margin_gb 10)}"
    # v92: why an engine's container was not created goes into ~/.config/devdb/<engine>.skipped (engine,
    # GB free, GB needed, the override), so the closing summary, dev-init and dev-test can quote it. v91
    # only printed a NOTICE in setup's scrolling output and its summary still said "created but stopped".
    # The file is removed once the container exists.
    mkdir -p "$HOME/.config/devdb"
    db_skipped() {   # db_skipped ENGINE REASON: record why ENGINE's container is missing
        printf '%s\n' "$2" > "$HOME/.config/devdb/$1.skipped"
    }
    # Every docker call here goes through sudo: the docker group from the base section only applies
    # to new logins, and this may be the run that added you to it.
    db_secret() {   # db_secret NAME: the environment's value, else secrets.env's (read in a subshell)
        local v="${!1:-}"
        if [ -z "$v" ] && [ -f "$HOME/.config/dev-init/secrets.env" ]; then
            v=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$HOME/.config/dev-init/secrets.env" "$1" || true)
        fi
        printf '%s' "$v"
    }
    db_container_env() {   # db_container_env CONTAINER NAME: a variable the container was created with
        sudo docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2> /dev/null | sed -n "s/^$2=//p" | head -n 1
    }
    # Letters, digits and '_', starting with a letter: both engines take it unquoted, and it meets SQL
    # Server's policy (three of upper case, lower case, digits and symbols).
    db_new_password() {
        printf 'Dev_%s_%s9' "$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)" "$(tr -dc 'A-Z' < /dev/urandom | head -c 1)"
    }
    db_pull() {   # db_pull IMAGE ESTIMATED_GB ENGINE: pull it, or check for an update; 1 = the image is not here
        local img=$1 est=$2 engine=$3 free_gb
        if sudo docker image inspect "$img" > /dev/null 2>&1; then
            echo "Checking $img for an update..."
        else
            free_gb=$(disk_free_gb)
            if [ "${free_gb:-0}" -lt $(( est + DB_MIN_FREE_GB )) ]; then
                echo "NOTICE: skipping $img (about $est GB on disk): ${free_gb:-0} GB free, and DEV_DB_MIN_FREE_GB=$DB_MIN_FREE_GB should stay free."
                echo "        Give Linux more disk (ChromeOS Settings > About ChromeOS > Linux development environment > Disk size), then rerun,"
                echo "        or keep less free: DEV_DB_MIN_FREE_GB=<n> ./$(basename "$0") install-$engine"
                db_skipped "$engine" "disk: ${free_gb:-0} GB free, $(( est + DB_MIN_FREE_GB )) GB needed ($img about $est GB + DEV_DB_MIN_FREE_GB=$DB_MIN_FREE_GB). Resize the Linux disk, or rerun with DEV_DB_MIN_FREE_GB=<n> install-$engine"
                return 1
            fi
            echo "Pulling $img (about $est GB on disk; a few minutes)..."
        fi
        if ! sudo docker pull -q "$img" > /dev/null 2>&1; then
            echo "NOTICE: 'docker pull $img' failed (network, or the registry is busy)."
            if ! sudo docker image inspect "$img" > /dev/null 2>&1; then
                db_skipped "$engine" "pull: 'docker pull $img' failed (network, or the registry is busy). Rerun setup with install-$engine"
                return 1
            fi
            echo "        Keeping the copy already on this machine."
        fi
        return 0
    }
fi

# SQL Server 2025 (install-mssql, part of install-db-server; added in v82)
if [[ "$FLAGS" =~ " install-mssql " ]]; then
    echo "--- SQL Server 2025 (install-mssql)"
    MSSQL_IMAGE="${MSSQL_IMAGE:-mcr.microsoft.com/mssql/server:2025-latest}"
    MSSQL_MEM_MB="${MSSQL_MEMORY_MB:-2048}"
    # SQL Server refuses to start with less than 2000 MB, so the cap never goes below 2048.
    if ! [[ "$MSSQL_MEM_MB" =~ ^[0-9]+$ ]] || [ "$MSSQL_MEM_MB" -lt 2048 ]; then MSSQL_MEM_MB=2048; fi
    # Clients: ODBC Driver 18 (install-db installs the same package; apt makes the second a no-op) and
    # the Go sqlcmd from GitHub, a single binary that needs no ODBC. Microsoft's ODBC-based sqlcmd
    # (mssql-tools18) ships inside the container at /opt/mssql-tools18/bin; the 'mssql' command uses
    # that one to tell when the server is ready, and falls back to it when the Go sqlcmd is missing.
    add_microsoft_prod_repo
    sudo env ACCEPT_EULA=Y apt install -y msodbcsql18
    SQLCMD_TMP=$(mktemp -d)
    SQLCMD_BIN=""
    if curl -fsSL --retry 3 -o "$SQLCMD_TMP/sqlcmd.tar.bz2" \
            https://github.com/microsoft/go-sqlcmd/releases/latest/download/sqlcmd-linux-amd64.tar.bz2 \
        && tar -xjf "$SQLCMD_TMP/sqlcmd.tar.bz2" -C "$SQLCMD_TMP"; then
        SQLCMD_BIN=$(find "$SQLCMD_TMP" -type f -name sqlcmd | head -n 1)
    fi
    if [ -n "$SQLCMD_BIN" ] && chmod +x "$SQLCMD_BIN" && "$SQLCMD_BIN" --version > /dev/null 2>&1; then
        install -m 755 "$SQLCMD_BIN" "$HOME/.local/bin/sqlcmd"
        echo "sqlcmd (Go): $("$HOME/.local/bin/sqlcmd" --version 2> /dev/null | head -n 1)"
    else
        echo "NOTICE: could not install the Go sqlcmd from GitHub; 'mssql sql' uses the one inside the container instead."
    fi
    rm -rf "$SQLCMD_TMP"

    if db_pull "$MSSQL_IMAGE" 3 mssql; then
        MSSQL_PW=$(db_secret MSSQL_SA_PASSWORD)
        MSSQL_HAVE_IMG=$(sudo docker inspect -f '{{.Image}}' devdb-mssql 2> /dev/null || true)
        MSSQL_NEW_IMG=$(sudo docker image inspect -f '{{.Id}}' "$MSSQL_IMAGE")
        MSSQL_WAS_RUNNING=false
        if [ -n "$MSSQL_HAVE_IMG" ] && { [ "$MSSQL_HAVE_IMG" != "$MSSQL_NEW_IMG" ] || [ "${DB_SERVER_RECREATE:-0}" = 1 ]; }; then
            [ -n "$MSSQL_PW" ] || MSSQL_PW=$(db_container_env devdb-mssql MSSQL_SA_PASSWORD)
            MSSQL_WAS_RUNNING=$(sudo docker inspect -f '{{.State.Running}}' devdb-mssql 2> /dev/null || echo false)
            if [ "$MSSQL_HAVE_IMG" != "$MSSQL_NEW_IMG" ]; then MSSQL_WHY="a newer image"; else MSSQL_WHY="DB_SERVER_RECREATE=1"; fi
            echo "Recreating devdb-mssql ($MSSQL_WHY); the data volume devdb-mssql-data stays."
            sudo docker rm -f devdb-mssql > /dev/null
            MSSQL_HAVE_IMG=""
        fi
        if [ -z "$MSSQL_HAVE_IMG" ]; then
            [ -n "$MSSQL_PW" ] || MSSQL_PW=$(db_new_password)
            sudo docker create --name devdb-mssql --hostname devdb-mssql \
                -e ACCEPT_EULA=Y -e "MSSQL_SA_PASSWORD=$MSSQL_PW" -e "MSSQL_MEMORY_LIMIT_MB=$MSSQL_MEM_MB" \
                --memory "$(( MSSQL_MEM_MB + 512 ))m" --restart no \
                -p 127.0.0.1:1433:1433 -v devdb-mssql-data:/var/opt/mssql \
                --label dev-setup=install-mssql "$MSSQL_IMAGE" > /dev/null
            echo "Created the devdb-mssql container on $MSSQL_IMAGE (stopped: 'mssql up' starts it)."
            if [ "$MSSQL_WAS_RUNNING" = true ] && sudo docker start devdb-mssql > /dev/null; then
                echo "Started it again, as it was running before."
            fi
        else
            echo "devdb-mssql is up to date on $MSSQL_IMAGE (DB_SERVER_RECREATE=1 recreates it; the data volume stays)."
        fi
    fi
    # v92: the recorded skip reason goes once the container exists.
    if sudo docker container inspect devdb-mssql > /dev/null 2>&1; then rm -f "$HOME/.config/devdb/mssql.skipped"; fi
else
    echo "Skipping SQL Server. (Run with 'install-mssql' or 'install-db-server'; not part of install-all)"
fi

# Oracle AI Database 26ai Free (install-oracle, part of install-db-server; added in v82)
if [[ "$FLAGS" =~ " install-oracle " ]]; then
    echo "--- Oracle AI Database 26ai Free (install-oracle)"
    # Both images have a database built in, so a first start takes a minute or two. Oracle Free's
    # limits: 2 CPU threads, 2 GB of RAM, 12 GB of user data, and one instance per machine (a second
    # one refuses to start with ORA-00442; dev-demo therefore uses this container too).
    # v83: two variants. Lite (the default; ~840 MB download, ~1.8 GB on disk) leaves out some optional
    # database components, which Oracle's registry page lists; the full image (~3.6 GB download,
    # ~9.5 GB on disk) has them all. install-oracle-full picks full. The choice is remembered in the
    # container's dev-setup.oracle-variant label, so later runs with plain install-oracle keep it and
    # never pull the other image. Optional components are installed when a database is created, so each
    # variant has its own data volume: devdb-oracle-data (Lite) and devdb-oracle-full-data (full).
    # Moving from Lite to full therefore starts an empty database and leaves the Lite one in its
    # volume. Back to Lite: docker rm -f devdb-oracle, then rerun setup with install-oracle (the full
    # volume stays until you remove it). ORACLE_IMAGE replaces the image of the variant in use, e.g. to
    # pin a release; the data volume follows the variant.
    ORA_LITE_IMAGE=container-registry.oracle.com/database/free:latest-lite
    ORA_FULL_IMAGE=container-registry.oracle.com/database/free:latest
    ORA_HAVE_VARIANT=""
    if sudo docker container inspect devdb-oracle > /dev/null 2>&1; then
        ORA_HAVE_VARIANT=$(sudo docker inspect -f '{{index .Config.Labels "dev-setup.oracle-variant"}}' devdb-oracle 2> /dev/null || true)
        [ "$ORA_HAVE_VARIANT" = full ] || ORA_HAVE_VARIANT=lite   # made by v82 (no label): Lite
    fi
    if [[ "$FLAGS" =~ " install-oracle-full " ]]; then
        ORA_VARIANT=full
    elif [ "$ORA_HAVE_VARIANT" = full ]; then
        ORA_VARIANT=full
        echo "devdb-oracle runs Oracle's full image, so it stays on full (install-oracle-full made it)."
    else
        ORA_VARIANT=lite
    fi
    # v83 review: the estimates count the image AND the copy of its built-in database that Docker makes
    # into a new data volume (named-volume copy-up), so the datafiles sit on disk twice. dev-test's disk
    # report measures the real figures.
    if [ "$ORA_VARIANT" = full ]; then
        ORACLE_IMAGE="${ORACLE_IMAGE:-$ORA_FULL_IMAGE}"; ORA_VOLUME=devdb-oracle-full-data; ORA_EST_GB=13
    else
        ORACLE_IMAGE="${ORACLE_IMAGE:-$ORA_LITE_IMAGE}"; ORA_VOLUME=devdb-oracle-data; ORA_EST_GB=4
    fi
    ORA_HOME=/opt/oracle
    ORA_DL="https://download.oracle.com/otn_software"
    ORA_TMP=$(mktemp -d)
    sudo mkdir -p "$ORA_HOME"

    # SQLcl: Oracle's command-line client (SQL*Plus-compatible, with completion, history, output
    # formats and Liquibase). A Java program that needs Java 17 or 21: the default-jdk the Java and
    # Android stacks use (21 on trixie). ~/.local/bin/sql links to it.
    install_jdk_and_java_home
    if curl -fsSL --retry 3 -o "$ORA_TMP/sqlcl.zip" "$ORA_DL/java/sqldeveloper/sqlcl-latest.zip" \
        && unzip -q -o "$ORA_TMP/sqlcl.zip" -d "$ORA_TMP" && [ -f "$ORA_TMP/sqlcl/bin/sql" ]; then
        sudo rm -rf "$ORA_HOME/sqlcl"
        sudo mv "$ORA_TMP/sqlcl" "$ORA_HOME/sqlcl"
        sudo chmod 755 "$ORA_HOME/sqlcl/bin/sql"
        ln -sfn "$ORA_HOME/sqlcl/bin/sql" "$HOME/.local/bin/sql"
        echo "SQLcl: $("$HOME/.local/bin/sql" -V 2> /dev/null | grep -m1 -i 'sqlcl' || echo installed)"
    else
        echo "NOTICE: could not download SQLcl from download.oracle.com; rerun setup to retry ('oracle sql' needs it)."
    fi

    # Instant Client (Basic Light + ODBC) from Oracle's permanent "latest" links: the C libraries that
    # ODBC, and anything else linking Oracle's client (PHP oci8, a Lazarus Oracle connection...), load.
    # python-oracledb (thin mode) and JDBC need none of it: both speak Oracle's protocol themselves.
    # It goes to /opt/oracle/instantclient_<release>, with /opt/oracle/instantclient pointing at the
    # current one; ldconfig learns that directory, and the ODBC driver is registered as [Oracle ODBC].
    # Instant Client is linked against libaio.so.1. Trixie's time_t transition renamed the library to
    # libaio.so.1t64 (the same ABI on 64-bit), so the usual compatibility link is added next to it, in
    # the system library directory: the one file this section puts outside /opt and your home.
    sudo apt install -y libaio1t64 || sudo apt install -y libaio1
    if [ ! -e /usr/lib/x86_64-linux-gnu/libaio.so.1 ] && [ -e /usr/lib/x86_64-linux-gnu/libaio.so.1t64 ]; then
        sudo ln -s libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1
        echo "Added /usr/lib/x86_64-linux-gnu/libaio.so.1 -> libaio.so.1t64 (for Instant Client)."
    fi
    IC_DIR=""
    if curl -fsSL --retry 3 -o "$ORA_TMP/ic-basic.zip" "$ORA_DL/linux/instantclient/instantclient-basiclite-linuxx64.zip" \
        && curl -fsSL --retry 3 -o "$ORA_TMP/ic-odbc.zip" "$ORA_DL/linux/instantclient/instantclient-odbc-linuxx64.zip" \
        && unzip -q -o "$ORA_TMP/ic-basic.zip" -d "$ORA_TMP/ic" && unzip -q -o "$ORA_TMP/ic-odbc.zip" -d "$ORA_TMP/ic"; then
        IC_DIR=$(ls -d "$ORA_TMP"/ic/instantclient_* 2> /dev/null | head -n 1 || true)
    fi
    if [ -n "$IC_DIR" ]; then
        IC_NAME=$(basename "$IC_DIR")
        sudo rm -rf "${ORA_HOME:?}/$IC_NAME"
        sudo mv "$IC_DIR" "$ORA_HOME/$IC_NAME"
        sudo ln -sfn "$IC_NAME" "$ORA_HOME/instantclient"
        for old in "$ORA_HOME"/instantclient_*; do
            if [ "$old" != "$ORA_HOME/$IC_NAME" ]; then sudo rm -rf "$old"; fi
        done
        # A stable name for the ODBC driver: the library file carries the release (libsqora.so.23.1).
        IC_SQORA=$(cd "$ORA_HOME/instantclient" && ls libsqora.so.* 2> /dev/null | head -n 1 || true)
        if [ -n "$IC_SQORA" ]; then sudo ln -sfn "$IC_SQORA" "$ORA_HOME/instantclient/libsqora.so"; fi
        echo "$ORA_HOME/instantclient" | sudo tee /etc/ld.so.conf.d/oracle-instantclient.conf > /dev/null
        sudo ldconfig
        # Registered once, under a fixed name, through the 'instantclient' link: an update needs no
        # re-registration.
        if [ -n "$IC_SQORA" ] && ! odbcinst -q -d | grep -q '^\[Oracle ODBC\]'; then
            printf '[Oracle ODBC]\nDescription = Oracle Instant Client ODBC driver\nDriver      = %s/instantclient/libsqora.so\n' "$ORA_HOME" > "$ORA_TMP/oracle_odbcinst.ini"
            sudo odbcinst -i -d -f "$ORA_TMP/oracle_odbcinst.ini"
        fi
        IC_MISSING=$(ldd "$ORA_HOME/instantclient/libsqora.so" "$ORA_HOME"/instantclient/libclntsh.so* 2> /dev/null | grep 'not found' | sort -u || true)
        if [ -n "$IC_MISSING" ]; then
            echo "NOTICE: Instant Client needs libraries this system lacks ('apt-file search <name>' finds the package):"
            echo "$IC_MISSING"
        fi
        echo "Instant Client: $IC_NAME in $ORA_HOME, ODBC driver [Oracle ODBC]"
    else
        echo "NOTICE: could not download Instant Client from download.oracle.com; rerun setup to retry (ODBC to Oracle needs it)."
    fi
    rm -rf "$ORA_TMP"

    if db_pull "$ORACLE_IMAGE" "$ORA_EST_GB" oracle; then
        ORA_PW=$(db_secret ORACLE_PWD)
        ORA_HAVE_IMG=$(sudo docker inspect -f '{{.Image}}' devdb-oracle 2> /dev/null || true)
        ORA_HAVE_REF=$(sudo docker inspect -f '{{.Config.Image}}' devdb-oracle 2> /dev/null || true)
        ORA_NEW_IMG=$(sudo docker image inspect -f '{{.Id}}' "$ORACLE_IMAGE")
        if [ -n "$ORA_HAVE_IMG" ] && [ "$ORA_HAVE_VARIANT" != "$ORA_VARIANT" ]; then
            # v83: Lite to full (the only switch setup makes by itself). The old password carries over.
            [ -n "$ORA_PW" ] || ORA_PW=$(db_container_env devdb-oracle ORACLE_PWD)
            echo "Moving devdb-oracle from the Lite image to the full one (install-oracle-full). The full image"
            echo "starts an empty database in the volume $ORA_VOLUME; the Lite database stays, untouched, in"
            echo "devdb-oracle-data. Once you no longer need it:"
            echo "    docker volume rm devdb-oracle-data && docker rmi $ORA_LITE_IMAGE"
            sudo docker stop -t 120 devdb-oracle > /dev/null 2>&1 || true
            sudo docker rm -f devdb-oracle > /dev/null
            ORA_HAVE_IMG=""
        elif [ -n "$ORA_HAVE_IMG" ] && [ "${DB_SERVER_RECREATE:-0}" = 1 ]; then
            [ -n "$ORA_PW" ] || ORA_PW=$(db_container_env devdb-oracle ORACLE_PWD)
            echo "Recreating devdb-oracle (DB_SERVER_RECREATE=1); the data volume $ORA_VOLUME stays."
            sudo docker stop -t 120 devdb-oracle > /dev/null 2>&1 || true
            sudo docker rm -f devdb-oracle > /dev/null
            ORA_HAVE_IMG=""
        elif [ -n "$ORA_HAVE_IMG" ] && [ "$ORA_HAVE_IMG" != "$ORA_NEW_IMG" ]; then
            if [ "$ORA_HAVE_REF" = "$ORACLE_IMAGE" ]; then
                echo "NOTICE: a newer $ORACLE_IMAGE is here, but devdb-oracle stays on its image: a new release over an"
                echo "        existing data volume is a database upgrade, so it is not done unasked. To start fresh (this"
                echo "        deletes the data): docker rm -f devdb-oracle && docker volume rm $ORA_VOLUME, then rerun"
                echo "        setup. To try the upgrade in place instead: rerun setup with DB_SERVER_RECREATE=1."
            else
                echo "NOTICE: devdb-oracle runs ${ORA_HAVE_REF:-another image}, not $ORACLE_IMAGE, and stays on it. To move it"
                echo "        (the data volume $ORA_VOLUME stays): rerun setup with DB_SERVER_RECREATE=1 and the same flags."
            fi
        fi
        if [ -z "$ORA_HAVE_IMG" ]; then
            [ -n "$ORA_PW" ] || ORA_PW=$(db_new_password)
            if ! sudo docker volume inspect "$ORA_VOLUME" > /dev/null 2>&1; then
                echo "Creating devdb-oracle: Docker first copies the image's built-in database into the new volume"
                echo "$ORA_VOLUME (a minute or two on the full image, with no output meanwhile)..."
            fi
            sudo docker create --name devdb-oracle --hostname devdb-oracle \
                -e "ORACLE_PWD=$ORA_PW" --restart no \
                -p 127.0.0.1:1521:1521 -v "$ORA_VOLUME:/opt/oracle/oradata" \
                --label dev-setup=install-oracle --label "dev-setup.oracle-variant=$ORA_VARIANT" \
                "$ORACLE_IMAGE" > /dev/null
            echo "Created the devdb-oracle container on $ORACLE_IMAGE ($ORA_VARIANT image, data in $ORA_VOLUME;"
            echo "stopped: 'oracle up' starts it)."
        elif [ "$ORA_HAVE_IMG" = "$ORA_NEW_IMG" ]; then
            echo "devdb-oracle is up to date on $ORACLE_IMAGE (DB_SERVER_RECREATE=1 recreates it; the data volume stays)."
        fi
    elif [ -n "$ORA_HAVE_VARIANT" ] && [ "$ORA_HAVE_VARIANT" != "$ORA_VARIANT" ]; then
        echo "devdb-oracle stays on the Lite image until the full one is here; rerun setup with install-oracle-full then."
    fi
    # v92: the recorded skip reason goes once the container runs the variant asked for (a Lite container kept
    # while the full image could not be pulled keeps the reason, so init and test can say why).
    ORA_NOW_VARIANT=$(sudo docker inspect -f '{{index .Config.Labels "dev-setup.oracle-variant"}}' devdb-oracle 2> /dev/null || true)
    if sudo docker container inspect devdb-oracle > /dev/null 2>&1 && { [ "${ORA_NOW_VARIANT:-lite}" = "$ORA_VARIANT" ] || [ "$ORA_VARIANT" = lite ]; }; then
        rm -f "$HOME/.config/devdb/oracle.skipped"
    fi
else
    echo "Skipping Oracle. (Run with 'install-oracle', 'install-oracle-full' or 'install-db-server'; not part of install-all)"
fi

# The 'mssql' and 'oracle' commands (v82): one script, ~/.local/bin/devdb, under two more names.
if [[ "$FLAGS" =~ " install-mssql " ]] || [[ "$FLAGS" =~ " install-oracle " ]]; then
    cat > "$HOME/.local/bin/devdb" << 'DEVDB_EOF'
#!/bin/bash
# devdb, mssql, oracle: start, stop and open the database servers of dev-setup's install-db-server
# (install-mssql, install-oracle). Written by dev-setup and rewritten on every run: copy it before editing.
#   mssql  up | down | status | sql [sqlcmd options] | logs [docker logs options] | password
#   oracle up | down | status | sql [SQLcl options]  | logs [docker logs options] | password
#   devdb mssql|oracle ...     the same, with the engine as the first argument
# 'up' starts the container, waits until the database answers, and prints how to connect. It stops the
# other engine first: each holds ~2 GB, and Linux gets ~6.4 GB of an 8 GB Chromebook (DEVDB_BOTH=1 keeps
# the other one running). DEVDB_WAIT (seconds, default 900) bounds the wait.
# The password: MSSQL_SA_PASSWORD / ORACLE_PWD from the environment or ~/.config/dev-init/secrets.env,
# else the one the container was created with.
# v93: Oracle's Lite image never applied ORACLE_PWD to its built-in database (ORA-01017 on Oct 4 2026; no
# password step in its first-start log), so the first 'oracle up' of a new data volume runs the image's own
# setPassword.sh with that password (SYS, SYSTEM and PDBADMIN) and leaves a marker in the volume
# (/opt/oracle/oradata/.devdb-password-set): later starts skip it, a new volume gets it again.
engine=${0##*/}
if [ "$engine" = devdb ]; then engine=${1:-}; [ $# -gt 0 ] && shift; fi
cmd=${1:-status}; [ $# -gt 0 ] && shift
case "$engine" in
    mssql)  C=devdb-mssql;  OTHER=devdb-oracle; PWVAR=MSSQL_SA_PASSWORD; PORT=1433; STOP_S=30
            WHAT="SQL Server 2025 (Developer edition)" ;;
    oracle) C=devdb-oracle; OTHER=devdb-mssql;  PWVAR=ORACLE_PWD;        PORT=1521; STOP_S=120
            WHAT="Oracle AI Database 26ai Free" ;;
    *) echo "usage: mssql|oracle up|down|status|sql|logs|password   (or: devdb mssql|oracle ...)" >&2; exit 2 ;;
esac
DOCKER=(docker)
docker info > /dev/null 2>&1 || DOCKER=(sudo -n docker)   # before the docker group is active in this login

exists()  { "${DOCKER[@]}" container inspect "$1" > /dev/null 2>&1; }
running() { [ "$("${DOCKER[@]}" inspect -f '{{.State.Running}}' "$1" 2> /dev/null)" = true ]; }
password() {
    local v="${!PWVAR:-}" f="$HOME/.config/dev-init/secrets.env"
    if [ -z "$v" ] && [ -r "$f" ]; then
        v=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$f" "$PWVAR")
    fi
    if [ -z "$v" ]; then
        v=$("${DOCKER[@]}" inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$C" 2> /dev/null | sed -n "s/^$PWVAR=//p" | head -n 1)
    fi
    printf '%s' "$v"
}
ready() {
    local since
    case "$engine" in
        mssql)
            "${DOCKER[@]}" exec -e "SQLCMDPASSWORD=$(password)" "$C" /opt/mssql-tools18/bin/sqlcmd \
                -S localhost -U sa -C -l 5 -b -Q 'SET NOCOUNT ON; SELECT 1' > /dev/null 2>&1 ;;
        oracle)
            [ "$("${DOCKER[@]}" inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$C" 2> /dev/null)" = healthy ] && return 0
            since=$("${DOCKER[@]}" inspect -f '{{.State.StartedAt}}' "$C" 2> /dev/null)
            "${DOCKER[@]}" logs --since "$since" "$C" 2>&1 | grep -q 'DATABASE IS READY TO USE' ;;
    esac
}
info() {
    echo "  $WHAT on 127.0.0.1:$PORT; the password: $engine password"
    case "$engine" in
        mssql)
            echo "  shell   mssql sql    (the Go sqlcmd; -Q \"...\" runs one statement, -i file.sql a script)"
            echo "  ODBC    DRIVER={ODBC Driver 18 for SQL Server};Server=127.0.0.1,1433;Uid=sa;Pwd=<password>;TrustServerCertificate=yes"
            echo "  JDBC    jdbc:sqlserver://localhost:1433;user=sa;encrypt=true;trustServerCertificate=true"
            echo "  .NET    Server=localhost,1433;User Id=sa;Password=<password>;TrustServerCertificate=True" ;;
        oracle)
            echo "  service FREEPDB1, the pluggable database to work in (FREE is the container database); users system, sys, pdbadmin"
            echo "  shell   oracle sql   (SQLcl; @file.sql runs a script)"
            echo "  ODBC    DRIVER={Oracle ODBC};DBQ=127.0.0.1:1521/FREEPDB1;UID=system;PWD=<password>"
            echo "  JDBC    jdbc:oracle:thin:@//localhost:1521/FREEPDB1"
            echo "  Python  oracledb.connect(user=\"system\", password=..., dsn=\"localhost:1521/FREEPDB1\")   (thin mode: no client libraries)" ;;
    esac
}
oracle_password_once() {   # v93: see the header. Oracle only; quiet when the volume has had it.
    local marker=/opt/oracle/oradata/.devdb-password-set pw
    [ "$engine" = oracle ] || return 0
    "${DOCKER[@]}" exec "$C" test -f "$marker" 2> /dev/null && return 0
    pw=$(password)
    [ -n "$pw" ] || { echo "Note: no Oracle password known ('oracle password' is empty); setPassword.sh not run."; return 0; }
    if "${DOCKER[@]}" exec "$C" bash -c 'cd "${ORACLE_BASE:-/opt/oracle}" 2> /dev/null; s=./setPassword.sh; [ -x "$s" ] || s=/opt/oracle/setPassword.sh; "$s" "$1"' _ "$pw" > /dev/null 2>&1; then
        "${DOCKER[@]}" exec "$C" touch "$marker" 2> /dev/null || true
        echo "First start of this data volume: the database's passwords (SYS, SYSTEM, PDBADMIN) set to 'oracle password' (setPassword.sh)."
    else
        echo "Note: setPassword.sh failed; if logins fail with ORA-01017: docker exec $C ./setPassword.sh \"\$(oracle password)\""
    fi
}
up() {
    local i wait=${DEVDB_WAIT:-900} avail
    exists "$C" || { echo "No $C container: run dev-setup with install-$engine (or install-db-server)." >&2; exit 1; }
    if running "$C" && ready; then echo "$WHAT is running."; oracle_password_once; info; return 0; fi
    if [ "${DEVDB_BOTH:-0}" != 1 ] && running "$OTHER"; then
        echo "Stopping $OTHER first: the two engines together want ~4 GB of the ~6.4 GB Linux gets (DEVDB_BOTH=1 keeps it)."
        "${DOCKER[@]}" stop -t 120 "$OTHER" > /dev/null
    fi
    # v89: the heavy engines of 'devsvc' (Solr, OpenSearch, Elasticsearch, Milvus, Atlas Local; v91: the
    # Selenium Grid) want 1-3 GB each: one of them or a database server, not both (DEVDB_BOTH=1 keeps them too).
    if [ "${DEVDB_BOTH:-0}" != 1 ]; then
        for j in devsvc-solr devsvc-opensearch devsvc-elasticsearch devsvc-milvus devsvc-atlas-local devsvc-selenium; do
            if running "$j"; then
                echo "Stopping $j first: a heavy devsvc engine and a database server do not fit together ('devsvc up ${j#devsvc-}' later)."
                "${DOCKER[@]}" stop -t 60 "$j" > /dev/null
            fi
        done
    fi
    avail=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)
    if [ "${avail:-0}" -lt 2600 ]; then
        echo "Note: $avail MB available. 'ollama ps' then 'ollama stop <model>', and closing Chrome tabs, give Linux memory back."
    fi
    "${DOCKER[@]}" start "$C" > /dev/null || exit 1
    printf 'Starting %s ' "$WHAT"
    for ((i = 0; i < wait; i += 3)); do
        if ready; then echo " ready after ${i}s"; oracle_password_once; info; return 0; fi
        if ! running "$C"; then
            echo; echo "$C stopped while starting. Its last log lines:"
            "${DOCKER[@]}" logs --tail 25 "$C" 2>&1
            exit 1
        fi
        [ $((i % 15)) -eq 0 ] && printf '.'
        sleep 3
    done
    echo; echo "$C did not answer within ${wait}s (DEVDB_WAIT raises the limit). Its last log lines:"
    "${DOCKER[@]}" logs --tail 25 "$C" 2>&1
    if [ "$engine" = mssql ]; then
        echo "\"Login failed for user 'sa'\" above means MSSQL_SA_PASSWORD in secrets.env is not the server's sa password."
    fi
    exit 1
}
down() {
    local vol
    if running "$C"; then
        # The volume the container really mounts (devdb-oracle-full-data on Oracle's full image).
        vol=$("${DOCKER[@]}" inspect -f '{{range .Mounts}}{{if .Name}}{{.Name}} {{end}}{{end}}' "$C" 2> /dev/null)
        vol=${vol%% *}
        "${DOCKER[@]}" stop -t "$STOP_S" "$C" > /dev/null && echo "$C stopped (its data stays in the volume ${vol:-$C-data})."
    else
        echo "$C is not running."
    fi
}
status() {
    exists "$C" || { echo "$C: no container (dev-setup with install-$engine)"; return 1; }
    "${DOCKER[@]}" ps -a --filter "name=^${C}\$" --format '{{.Names}}: {{.Status}}   (image {{.Image}})'
    if running "$C"; then info; else echo "  start it with: $engine up"; fi
}
sql_shell() {
    local a opts=() rest=()
    running "$C" || { echo "$C is not running: '$engine up' first." >&2; exit 1; }
    case "$engine" in
        mssql)
            if command -v sqlcmd > /dev/null 2>&1; then
                SQLCMDPASSWORD="$(password)" exec sqlcmd -S 127.0.0.1,1433 -U sa -C "$@"
            fi
            exec "${DOCKER[@]}" exec -it -e "SQLCMDPASSWORD=$(password)" "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C "$@" ;;
        oracle)
            command -v sql > /dev/null 2>&1 || { echo "SQLcl (sql) is missing: rerun dev-setup with install-oracle." >&2; exit 1; }
            # SQLcl takes its options before the logon and scripts (@file) after it.
            for a in "$@"; do case "$a" in -*) opts+=("$a") ;; *) rest+=("$a") ;; esac; done
            exec sql "${opts[@]}" "system/$(password)@//127.0.0.1:1521/FREEPDB1" "${rest[@]}" ;;
    esac
}
case "$cmd" in
    up|start) up ;;
    down|stop) down ;;
    status) status ;;
    sql) sql_shell "$@" ;;
    logs) exec "${DOCKER[@]}" logs --tail 100 "$@" "$C" ;;
    password) password; echo ;;
    *) echo "usage: $engine up|down|status|sql|logs|password" >&2; exit 2 ;;
esac
DEVDB_EOF
    chmod +x "$HOME/.local/bin/devdb"
    ln -sfn devdb "$HOME/.local/bin/mssql"
    ln -sfn devdb "$HOME/.local/bin/oracle"
    echo "Commands in ~/.local/bin:  mssql / oracle  up | down | status | sql | logs | password"
    echo "Nothing is running yet. One engine at a time: 'mssql up' or 'oracle up' (each holds ~2 GB of RAM)."
fi

# =================================================================
# install-ldap / install-ldap-full : an LDAP directory to log in against (added in v83)
# Opt-in, in no group, NOT in install-all. Both give a directory with the same base DN, the same people
# and groups, and one 'ldap' command. What connects an app is per project (for Drupal the contrib
# 'ldap' suite, or miniOrange's 'ldap_auth'), so dev-demo's drupal/drupal-ldap site shows that side.
#   install-ldap       LITE: lldap (github.com/lldap/lldap) in Docker, container devldap-lldap: LDAP on
#                      127.0.0.1:3890, web UI on 127.0.0.1:17170 (people, groups, passwords), data in
#                      the volume devldap-lldap-data. Tiny (~20 MB of RAM), so unlike the database
#                      servers it runs all the time (restart unless-stopped; 'ldap down' stops it for
#                      good). It speaks the part of LDAP that logins and group lookups use; no schema
#                      changes, and people and groups are managed in its web UI rather than with ldapadd.
#   install-ldap-full  FULL: OpenLDAP itself, Debian's slapd, a systemd service on port 389 with the
#                      whole protocol (ldapadd/ldapmodify, any schema, overlays, ACLs, cn=config),
#                      admin cn=admin,<base DN>. It includes install-ldap, so lldap runs next to it with
#                      the same people.
# Both: ldap-utils (ldapsearch, ldapwhoami, ldapadd, ldapmodify, ldapdelete) and php-ldap for PHP on
# this machine (symfony/ldap, so drupal/ldap, requires ext-ldap in Composer's platform check).
# Directory contents, created on both: ou=people and ou=groups under the base DN; alice and bob in the
# group drupal_editors and carol in drupal_admins (all with LDAP_SAMPLE_PASSWORD); and uid=drupal-bind,
# a read-only service account for apps to search with (LDAP_BIND_PASSWORD; in lldap it is a member of
# lldap_strict_readonly, which is what lets it see everyone). Reruns add what is missing and change
# nothing else.
# Values: LDAP_BASE_DN (default dc=example,dc=com), LLDAP_ADMIN_PASSWORD (8+ characters),
# OPENLDAP_ADMIN_PASSWORD, LDAP_BIND_PASSWORD and LDAP_SAMPLE_PASSWORD come from the environment or
# secrets.env the first time, otherwise are generated. They are kept in ~/.config/devldap/ldap.env
# (mode 600), which the 'ldap' command, dev-test, dev-init and dev-demo read, and from then on that file
# wins: it holds what the directories were created with. Start over (deletes the directories):
#   docker rm -f devldap-lldap && docker volume rm devldap-lldap-data
#   sudo apt purge -y slapd && sudo rm -rf /var/lib/ldap /etc/ldap/slapd.d     (full only)
#   rm ~/.config/devldap/ldap.env, then rerun setup with the same flags
# DDEV: Drupal in DDEV's web container reaches lldap as ldap://lldap:3890 (the container joins DDEV's
# ddev_default network under that name; 'ldap up' joins it again once DDEV has recreated the network)
# and slapd as ldap://host.docker.internal:389. slapd listens on every interface of this Linux
# container (Debian's default), which ChromeOS does not forward to your network.
# LLDAP_IMAGE picks another lldap image (default lldap/lldap:stable). A rerun recreates the container
# on a newer image; the volume stays.
# =================================================================
if [[ "$FLAGS" =~ " install-ldap " ]]; then
    LDAP_FULL=0
    [[ "$FLAGS" =~ " install-ldap-full " ]] && LDAP_FULL=1
    echo "================================================================="
    if [ "$LDAP_FULL" = 1 ]; then
        echo "Installing LDAP directories: OpenLDAP (slapd) and lldap (install-ldap-full)..."
    else
        echo "Installing an LDAP directory: lldap (install-ldap)..."
    fi
    echo "================================================================="
    sudo apt install -y ldap-utils php-ldap jq
    LDAP_CFG="$HOME/.config/devldap"
    LDAP_ENV_FILE="$LDAP_CFG/ldap.env"
    LDAP_BOOT="$LDAP_CFG/lldap-bootstrap"
    mkdir -p ~/.local/bin "$LDAP_BOOT/user-configs" "$LDAP_BOOT/group-configs"
    chmod 700 "$LDAP_CFG" "$LDAP_BOOT"

    # ldap_value NAME: what the directories were created with (ldap.env) first; for new ones, the
    # environment, then secrets.env. Each file is read in a subshell, so nothing else from it leaks in.
    ldap_value() {
        local v="" src
        for src in "$LDAP_ENV_FILE" ENV "$HOME/.config/dev-init/secrets.env"; do
            if [ "$src" = ENV ]; then
                v="${!1:-}"
            elif [ -f "$src" ]; then
                v=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$src" "$1" || true)
            fi
            [ -n "$v" ] && break
        done
        printf '%s' "$v"
    }
    ldap_random() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${1:-16}"; }
    # Letters, digits and '_', like the database passwords: safe unquoted everywhere, 8+ characters.
    ldap_new_password() { printf 'Dev_%s_%s9' "$(ldap_random 16)" "$(tr -dc 'A-Z' < /dev/urandom | head -c 1)"; }
    ldap_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

    LDAP_BASE_DN=$(ldap_value LDAP_BASE_DN)
    [ -n "$LDAP_BASE_DN" ] || LDAP_BASE_DN="dc=example,dc=com"
    for LDAP_VAR in LLDAP_ADMIN_PASSWORD OPENLDAP_ADMIN_PASSWORD LDAP_BIND_PASSWORD LDAP_SAMPLE_PASSWORD; do
        LDAP_VAL=$(ldap_value "$LDAP_VAR")
        [ -n "$LDAP_VAL" ] || LDAP_VAL=$(ldap_new_password)
        printf -v "$LDAP_VAR" '%s' "$LDAP_VAL"
    done
    for LDAP_VAR in LLDAP_JWT_SECRET LLDAP_KEY_SEED; do
        LDAP_VAL=$(ldap_value "$LDAP_VAR")
        [ -n "$LDAP_VAL" ] || LDAP_VAL=$(ldap_random 32)
        printf -v "$LDAP_VAR" '%s' "$LDAP_VAL"
    done
    (
        umask 077
        {
            echo "# ~/.config/devldap/ldap.env: written by dev-setup (install-ldap) and rewritten on every run with the"
            echo "# same values, which are what the LDAP directories were created with. The 'ldap' command, dev-test,"
            echo "# dev-init and dev-demo read it; ~/.bashrc does not. 'ldap passwords' prints them."
            echo "# LLDAP_KEY_SEED derives lldap's password hashes: changing it makes every lldap password invalid."
            for LDAP_VAR in LDAP_BASE_DN LLDAP_ADMIN_PASSWORD OPENLDAP_ADMIN_PASSWORD LDAP_BIND_PASSWORD \
                            LDAP_SAMPLE_PASSWORD LLDAP_JWT_SECRET LLDAP_KEY_SEED; do
                echo "$LDAP_VAR=$(ldap_quote "${!LDAP_VAR}")"
            done
        } > "$LDAP_ENV_FILE.new"
    )
    mv "$LDAP_ENV_FILE.new" "$LDAP_ENV_FILE"
    chmod 600 "$LDAP_ENV_FILE"

    LDAP_PEOPLE="ou=people,$LDAP_BASE_DN"
    LDAP_GROUPS="ou=groups,$LDAP_BASE_DN"
    LDAP_BIND_DN="uid=drupal-bind,$LDAP_PEOPLE"
    # The mail domain follows the base DN's dc= parts (dc=example,dc=com -> example.com).
    LDAP_DOMAIN=$(printf '%s' "$LDAP_BASE_DN" | tr ',' '\n' | sed -n 's/^[[:space:]]*[dD][cC]=//p' | paste -sd. -)
    LDAP_MAIL_DOMAIN="${LDAP_DOMAIN:-example.com}"
    # The sample people: uid|first name|last name|groups (comma-separated).
    LDAP_SAMPLE_USERS=("alice|Alice|Archer|drupal_editors" "bob|Bob|Baker|drupal_editors" "carol|Carol|Chen|drupal_admins")

    # --- lldap (install-ldap) ---
    # lldap's own bootstrap.sh (shipped in the image as /app/bootstrap.sh) creates the groups and people
    # from JSON files mounted at /bootstrap; it adds what is missing and resets the passwords named here.
    echo "--- lldap (install-ldap)"
    (
        umask 077
        for LDAP_G in drupal_editors drupal_admins lldap_strict_readonly; do
            jq -n --arg n "$LDAP_G" '{name: $n}'
        done > "$LDAP_BOOT/group-configs/dev-setup.json"
        {
            for LDAP_U in "${LDAP_SAMPLE_USERS[@]}"; do
                IFS='|' read -r LU_ID LU_FIRST LU_LAST LU_GROUPS <<< "$LDAP_U"
                jq -n --arg id "$LU_ID" --arg mail "$LU_ID@$LDAP_MAIL_DOMAIN" --arg pw "$LDAP_SAMPLE_PASSWORD" \
                      --arg f "$LU_FIRST" --arg l "$LU_LAST" --arg g "$LU_GROUPS" \
                    '{id: $id, email: $mail, password: $pw, displayName: ($f + " " + $l),
                      firstName: $f, lastName: $l, groups: ($g | split(","))}'
            done
            jq -n --arg mail "drupal-bind@$LDAP_MAIL_DOMAIN" --arg pw "$LDAP_BIND_PASSWORD" \
                '{id: "drupal-bind", email: $mail, password: $pw, displayName: "Drupal service account",
                  groups: ["lldap_strict_readonly"]}'
        } > "$LDAP_BOOT/user-configs/dev-setup.json"
    )
    LLDAP_IMAGE="${LLDAP_IMAGE:-lldap/lldap:stable}"
    if sudo docker image inspect "$LLDAP_IMAGE" > /dev/null 2>&1; then
        echo "Checking $LLDAP_IMAGE for an update..."
    else
        echo "Pulling $LLDAP_IMAGE (about 30 MB)..."
    fi
    sudo docker pull -q "$LLDAP_IMAGE" > /dev/null || echo "NOTICE: 'docker pull $LLDAP_IMAGE' failed (network, or the registry is busy)."
    if ! sudo docker image inspect "$LLDAP_IMAGE" > /dev/null 2>&1; then
        echo "NOTICE: no $LLDAP_IMAGE on this machine, so lldap is not set up; rerun setup with install-ldap."
    else
        LLDAP_HAVE_IMG=$(sudo docker inspect -f '{{.Image}}' devldap-lldap 2> /dev/null || true)
        LLDAP_NEW_IMG=$(sudo docker image inspect -f '{{.Id}}' "$LLDAP_IMAGE")
        if [ -n "$LLDAP_HAVE_IMG" ] && [ "$LLDAP_HAVE_IMG" != "$LLDAP_NEW_IMG" ]; then
            echo "Recreating devldap-lldap on the newer image; its data stays in the volume devldap-lldap-data."
            sudo docker rm -f devldap-lldap > /dev/null
            LLDAP_HAVE_IMG=""
        fi
        if [ -z "$LLDAP_HAVE_IMG" ]; then
            sudo docker create --name devldap-lldap --hostname devldap-lldap \
                -e "LLDAP_LDAP_BASE_DN=$LDAP_BASE_DN" -e "LLDAP_LDAP_USER_PASS=$LLDAP_ADMIN_PASSWORD" \
                -e "LLDAP_JWT_SECRET=$LLDAP_JWT_SECRET" -e "LLDAP_KEY_SEED=$LLDAP_KEY_SEED" \
                -e "TZ=$(cat /etc/timezone 2> /dev/null || echo UTC)" \
                --restart unless-stopped -p 127.0.0.1:3890:3890 -p 127.0.0.1:17170:17170 \
                -v devldap-lldap-data:/data -v "$LDAP_BOOT:/bootstrap:ro" \
                --label dev-setup=install-ldap "$LLDAP_IMAGE" > /dev/null
            echo "Created the devldap-lldap container on $LLDAP_IMAGE."
        fi
        sudo docker start devldap-lldap > /dev/null
        LLDAP_UP=0
        for _ in $(seq 1 60); do
            curl -fs -o /dev/null http://127.0.0.1:17170/ && { LLDAP_UP=1; break; }
            sleep 1
        done
        if [ "$LLDAP_UP" = 1 ]; then
            echo "Creating lldap's people and groups (its bootstrap.sh; log: assets/logs/ldap-bootstrap.log)..."
            # shellcheck disable=SC2024   # the log is written as you, on purpose
            if sudo docker exec -e "LLDAP_ADMIN_PASSWORD=$LLDAP_ADMIN_PASSWORD" devldap-lldap /app/bootstrap.sh \
                    > "$ASSETS/logs/ldap-bootstrap.log" 2>&1 \
                && ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3890 -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PASSWORD" \
                    -b "$LDAP_PEOPLE" '(uid=alice)' uid 2> /dev/null | grep -q '^uid: alice'; then
                echo "lldap: alice, bob, carol and the service account drupal-bind are in place."
            else
                echo "NOTICE: lldap's bootstrap did not finish; its last lines:"
                tail -n 5 "$ASSETS/logs/ldap-bootstrap.log" | sed 's/^/        /'
                echo "        The people can be added by hand in the web UI ('ldap ui'); rerunning setup retries."
            fi
        else
            echo "NOTICE: lldap did not answer on http://127.0.0.1:17170 within a minute: 'ldap logs' shows why."
        fi
        # DDEV's shared network exists once any DDEV project has started; 'ldap up' joins it later if not.
        if sudo docker network inspect ddev_default > /dev/null 2>&1; then
            sudo docker network connect --alias lldap ddev_default devldap-lldap > /dev/null 2>&1 || true
            echo "lldap is on DDEV's network: Drupal in DDEV reaches it as ldap://lldap:3890."
        else
            echo "DDEV's network does not exist yet (no DDEV project has run); 'ldap up' joins it once it does."
        fi
    fi

    # --- OpenLDAP (install-ldap-full) ---
    if [ "$LDAP_FULL" = 1 ]; then
        echo "--- OpenLDAP (install-ldap-full)"
        LDAP_RDN_COUNT=$(printf '%s' "$LDAP_BASE_DN" | tr ',' '\n' | grep -c .)
        LDAP_DC_COUNT=$(printf '%s' "$LDAP_BASE_DN" | tr ',' '\n' | grep -ci '^[[:space:]]*dc=' || true)
        if [ "$LDAP_RDN_COUNT" != "$LDAP_DC_COUNT" ]; then
            echo "NOTICE: Debian's slapd installer builds its suffix from a domain, so LDAP_BASE_DN must be dc=... parts only"
            echo "        (it is $LDAP_BASE_DN). OpenLDAP is not set up; lldap is."
        else
            ldap_suffixes() {
                sudo ldapsearch -Q -LLL -o ldif-wrap=no -Y EXTERNAL -H ldapi:/// -b cn=config '(olcSuffix=*)' olcSuffix 2> /dev/null \
                    | sed -n 's/^olcSuffix: //p'
            }
            # Debian's installer questions, answered up front. The passwords stay in debconf's root-only store.
            sudo debconf-set-selections << EOF
slapd slapd/no_configuration boolean false
slapd slapd/domain string $LDAP_DOMAIN
slapd shared/organization string dev-setup
slapd slapd/password1 password $OPENLDAP_ADMIN_PASSWORD
slapd slapd/password2 password $OPENLDAP_ADMIN_PASSWORD
slapd slapd/internal/adminpw password $OPENLDAP_ADMIN_PASSWORD
slapd slapd/internal/generated_adminpw password $OPENLDAP_ADMIN_PASSWORD
slapd slapd/backend select MDB
slapd slapd/purge_database boolean false
slapd slapd/move_old_database boolean true
EOF
            sudo DEBIAN_FRONTEND=noninteractive apt install -y slapd
            sudo systemctl enable slapd > /dev/null 2>&1 || true
            sudo systemctl start slapd || true
            if ! systemctl is-active --quiet slapd; then
                echo "NOTICE: slapd is installed but did not start: 'journalctl -u slapd' shows why. OpenLDAP is not seeded."
            else
                # A slapd that serves another suffix (installed before, or Debian took the domain from the
                # hostname) is reconfigured; Debian moves its old database to /var/backups first.
                if ! ldap_suffixes | grep -qixF "$LDAP_BASE_DN"; then
                    echo "slapd serves '$(ldap_suffixes | paste -sd' ' -)', not $LDAP_BASE_DN: reconfiguring it (the old database is moved to /var/backups)..."
                    sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive slapd
                    sudo systemctl restart slapd
                fi
                # The admin password: set it from ldap.env when a bind with it fails (an older install).
                if ! ldapwhoami -x -H ldap://127.0.0.1 -D "cn=admin,$LDAP_BASE_DN" -w "$OPENLDAP_ADMIN_PASSWORD" > /dev/null 2>&1; then
                    LDAP_DB_DN=$(sudo ldapsearch -Q -LLL -o ldif-wrap=no -Y EXTERNAL -H ldapi:/// -b cn=config \
                        "(olcSuffix=$LDAP_BASE_DN)" dn 2> /dev/null | sed -n 's/^dn: //p' | head -n 1)
                    if [ -n "$LDAP_DB_DN" ]; then
                        printf 'dn: %s\nchangetype: modify\nreplace: olcRootPW\nolcRootPW: %s\n' \
                            "$LDAP_DB_DN" "$(sudo slappasswd -s "$OPENLDAP_ADMIN_PASSWORD")" \
                            | sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// > /dev/null \
                            && echo "OpenLDAP: admin password set from ~/.config/devldap/ldap.env."
                    fi
                fi
                # People and groups: the same as lldap's. ldapadd -c skips entries that already exist.
                LDAP_SEED=$(mktemp)
                {
                    printf 'dn: %s\nobjectClass: organizationalUnit\nou: people\n\n' "$LDAP_PEOPLE"
                    printf 'dn: %s\nobjectClass: organizationalUnit\nou: groups\n\n' "$LDAP_GROUPS"
                    for LDAP_U in "${LDAP_SAMPLE_USERS[@]}" "drupal-bind|Drupal|Service Account|"; do
                        IFS='|' read -r LU_ID LU_FIRST LU_LAST LU_GROUPS <<< "$LDAP_U"
                        LU_PW=$LDAP_SAMPLE_PASSWORD
                        [ "$LU_ID" = drupal-bind ] && LU_PW=$LDAP_BIND_PASSWORD
                        printf 'dn: uid=%s,%s\nobjectClass: inetOrgPerson\nuid: %s\ncn: %s %s\ngivenName: %s\nsn: %s\n' \
                            "$LU_ID" "$LDAP_PEOPLE" "$LU_ID" "$LU_FIRST" "$LU_LAST" "$LU_FIRST" "$LU_LAST"
                        printf 'displayName: %s %s\nmail: %s@%s\nuserPassword: %s\n\n' \
                            "$LU_FIRST" "$LU_LAST" "$LU_ID" "$LDAP_MAIL_DOMAIN" "$(sudo slappasswd -s "$LU_PW")"
                    done
                    for LDAP_G in drupal_editors drupal_admins; do
                        printf 'dn: cn=%s,%s\nobjectClass: groupOfNames\ncn: %s\n' "$LDAP_G" "$LDAP_GROUPS" "$LDAP_G"
                        for LDAP_U in "${LDAP_SAMPLE_USERS[@]}"; do
                            IFS='|' read -r LU_ID LU_FIRST LU_LAST LU_GROUPS <<< "$LDAP_U"
                            if [[ ",$LU_GROUPS," == *",$LDAP_G,"* ]]; then printf 'member: uid=%s,%s\n' "$LU_ID" "$LDAP_PEOPLE"; fi
                        done
                        printf '\n'
                    done
                } > "$LDAP_SEED"
                ldapadd -x -c -H ldap://127.0.0.1 -D "cn=admin,$LDAP_BASE_DN" -w "$OPENLDAP_ADMIN_PASSWORD" -f "$LDAP_SEED" \
                    > "$ASSETS/logs/ldap-openldap-seed.log" 2>&1 || true
                rm -f "$LDAP_SEED"
                if ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1 -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PASSWORD" \
                        -b "$LDAP_PEOPLE" '(uid=alice)' uid 2> /dev/null | grep -q '^uid: alice'; then
                    echo "OpenLDAP: $LDAP_BASE_DN with alice, bob, carol, drupal-bind and the two groups is in place."
                else
                    echo "NOTICE: the OpenLDAP entries are not all there: see assets/logs/ldap-openldap-seed.log."
                fi
            fi
        fi
    fi

    # --- the 'ldap' command ---
    cat > "$HOME/.local/bin/ldap" << 'LDAP_EOF'
#!/bin/bash
# ldap: the LDAP directories of dev-setup's install-ldap (lldap, "lite") and install-ldap-full (OpenLDAP's
# slapd, "full"). Written by dev-setup and rewritten on every run: copy it before editing.
#   ldap status                                  both directories: state, addresses, DNs
#   ldap up | down                               start / stop them (lldap's container, the slapd service)
#   ldap search [lite|full] [FILTER [ATTR...]]   ldapsearch as the read-only service account
#   ldap login USER [lite|full]                  check USER's password with ldapwhoami (it asks for it)
#   ldap passwords                               what setup chose (~/.config/devldap/ldap.env)
#   ldap drupal [lite|full]                      the values for Drupal's LDAP server form
#   ldap ui                                      open lldap's web UI (people, groups, passwords)
#   ldap logs [docker logs options]              lldap's log
# lite is the default wherever lite or full can be named.
ENVF="$HOME/.config/devldap/ldap.env"
[ -r "$ENVF" ] || { echo "No $ENVF: run dev-setup with install-ldap (or install-ldap-full)." >&2; exit 1; }
# shellcheck disable=SC1090
. "$ENVF"
BASE=$LDAP_BASE_DN
PEOPLE="ou=people,$BASE"
BIND_DN="uid=drupal-bind,$PEOPLE"
C=devldap-lldap
DOCKER=(docker)
docker info > /dev/null 2>&1 || DOCKER=(sudo -n docker)   # before the docker group is active in this login

have_lite() { "${DOCKER[@]}" container inspect "$C" > /dev/null 2>&1; }
have_full() { [ -x /usr/sbin/slapd ]; }
lite_up()   { [ "$("${DOCKER[@]}" inspect -f '{{.State.Running}}' "$C" 2> /dev/null)" = true ]; }
full_up()   { systemctl is-active --quiet slapd 2> /dev/null; }
uri()       { if [ "$1" = full ]; then echo ldap://127.0.0.1:389; else echo ldap://127.0.0.1:3890; fi; }
pick() {   # pick [lite|full]: which directory to use
    case "${1:-}" in
        lite) have_lite || { echo "No lldap container: run dev-setup with install-ldap." >&2; return 1; }; echo lite ;;
        full) have_full || { echo "OpenLDAP is not installed: run dev-setup with install-ldap-full." >&2; return 1; }; echo full ;;
        "")   if have_lite; then echo lite; elif have_full; then echo full; else echo "No LDAP directory: run dev-setup with install-ldap." >&2; return 1; fi ;;
        *)    echo "Expected lite or full, not '$1'." >&2; return 1 ;;
    esac
}
# A password goes to the ldap tools in a mode-600 file (-y), not on the command line.
PWF=""
trap '[ -n "$PWF" ] && rm -f "$PWF"' EXIT
pwfile() { PWF=$(mktemp); printf '%s' "$1" > "$PWF"; }
in_ddev_net() {
    "${DOCKER[@]}" network inspect ddev_default -f '{{range .Containers}}{{.Name}} {{end}}' 2> /dev/null | grep -qw "$C"
}
join_ddev() {
    "${DOCKER[@]}" network inspect ddev_default > /dev/null 2>&1 || return 0
    in_ddev_net && return 0
    "${DOCKER[@]}" network connect --alias lldap ddev_default "$C" > /dev/null 2>&1 \
        && echo "lldap joined DDEV's network: ldap://lldap:3890 from DDEV's containers."
}
status() {
    echo "Base DN   $BASE   (people ou=people, groups ou=groups)"
    echo "Accounts  service (read-only) $BIND_DN; people alice, bob, carol; 'ldap passwords' shows the passwords"
    if have_lite; then
        echo "lite      lldap, $(lite_up && echo running || echo "stopped ('ldap up')"): ldap://127.0.0.1:3890, admin uid=admin,$PEOPLE, web UI http://localhost:17170"
        if in_ddev_net; then echo "          from DDEV: ldap://lldap:3890"; else echo "          from DDEV: not joined yet ('ldap up' after a DDEV project has started)"; fi
    fi
    if have_full; then
        echo "full      OpenLDAP (slapd), $(full_up && echo running || echo "stopped ('ldap up')"): ldap://127.0.0.1:389, admin cn=admin,$BASE"
        echo "          from DDEV: ldap://host.docker.internal:389"
    fi
    have_lite || have_full || echo "No directory: run dev-setup with install-ldap (lite) or install-ldap-full."
}
up() {
    local _
    if have_lite; then
        lite_up || "${DOCKER[@]}" start "$C" > /dev/null || exit 1
        join_ddev
        for _ in $(seq 1 30); do (exec 3<> /dev/tcp/127.0.0.1/3890) 2> /dev/null && break; sleep 1; done
    fi
    if have_full && ! full_up; then sudo systemctl start slapd || exit 1; fi
    status
}
down() {
    if have_lite && lite_up; then
        "${DOCKER[@]}" stop "$C" > /dev/null && echo "lldap stopped; it stays stopped across restarts until 'ldap up'."
    fi
    if have_full && full_up; then
        sudo systemctl stop slapd && echo "slapd stopped; it starts with Linux again ('sudo systemctl disable slapd' to stop that)."
    fi
}
search() {
    local t=""
    case "${1:-}" in lite|full) t=$1; shift ;; esac
    t=$(pick "$t") || exit 1
    pwfile "$LDAP_BIND_PASSWORD"
    ldapsearch -x -LLL -o ldif-wrap=no -H "$(uri "$t")" -D "$BIND_DN" -y "$PWF" -b "$BASE" "${1:-(objectClass=*)}" "${@:2}"
}
login() {
    local user=${1:-} t pw=${LDAP_PASSWORD:-}
    [ -n "$user" ] || { echo "usage: ldap login USER [lite|full]   (LDAP_PASSWORD=... skips the question)" >&2; exit 2; }
    t=$(pick "${2:-}") || exit 1
    [ -n "$pw" ] || { read -rsp "Password for $user ($t): " pw; echo; }
    pwfile "$pw"
    if ldapwhoami -x -H "$(uri "$t")" -D "uid=$user,$PEOPLE" -y "$PWF"; then
        echo "$t accepts $user's password."
    else
        exit 1
    fi
}
passwords() {
    echo "lldap admin (uid=admin, web UI)   $LLDAP_ADMIN_PASSWORD"
    have_full && echo "OpenLDAP admin (cn=admin)         $OPENLDAP_ADMIN_PASSWORD"
    echo "service account drupal-bind       $LDAP_BIND_PASSWORD"
    echo "alice, bob, carol                 $LDAP_SAMPLE_PASSWORD"
}
drupal() {
    local t host port class
    t=$(pick "${1:-}") || exit 1
    if [ "$t" = full ]; then host=host.docker.internal; port=389; else host=lldap; port=3890; fi
    class=$(search "$t" '(cn=drupal_editors)' objectClass 2> /dev/null | sed -n 's/^objectClass: //p' | grep -vix top | paste -sd/ -)
    cat << EOF
Drupal, contrib 'ldap' suite (drupal/ldap): Configuration > People > LDAP > Servers > Add server
  Server type         OpenLDAP$( [ "$t" = lite ] && echo " (lldap answers like one)")
  Host                $host   (from DDEV's web container; 127.0.0.1 from PHP on this machine)
  Port                $port
  Encryption          none (a local directory)
  Bind method         Service account
  Bind DN             $BIND_DN
  Password            $LDAP_BIND_PASSWORD
  Base DNs            $PEOPLE
  Auth name attribute uid          Email attribute  mail
  Persistent ID       entryuuid
  Groups              base ou=groups,$BASE, object class ${class:-groupOfNames},
                      membership attribute member, matched against the user's DN
  Test with           alice / $LDAP_SAMPLE_PASSWORD
miniOrange's LDAP / Active Directory Integration (drupal/ldap_auth): server ldap://$host:$port,
  bind account DN and password as above, search base $PEOPLE, username attribute uid.
EOF
}
ui() {
    local u=http://localhost:17170
    have_lite || { echo "No lldap container: run dev-setup with install-ldap." >&2; exit 1; }
    lite_up || { echo "lldap is stopped: 'ldap up' first." >&2; exit 1; }
    echo "$u   (log in as admin: 'ldap passwords')"
    if [ -x /opt/google/cros-containers/bin/garcon-url-handler ]; then
        /opt/google/cros-containers/bin/garcon-url-handler "$u" > /dev/null 2>&1 &
    elif command -v xdg-open > /dev/null 2>&1; then
        xdg-open "$u" > /dev/null 2>&1 &
    fi
}
cmd=${1:-status}; [ $# -gt 0 ] && shift
case "$cmd" in
    status) status ;;
    up|start) up ;;
    down|stop) down ;;
    search) search "$@" ;;
    login) login "$@" ;;
    passwords|password) passwords ;;
    drupal) drupal "$@" ;;
    ui) ui ;;
    logs) exec "${DOCKER[@]}" logs --tail 100 "$@" "$C" ;;
    *) echo "usage: ldap status|up|down|search|login|passwords|drupal|ui|logs" >&2; exit 2 ;;
esac
LDAP_EOF
    chmod +x "$HOME/.local/bin/ldap"
    echo "Command in ~/.local/bin:  ldap status | up | down | search | login | passwords | drupal | ui | logs"
    echo "Try: ldap search '(uid=alice)'   then   ldap login alice   ('ldap passwords' has hers)."
    echo "Drupal: 'ldap drupal' prints the server settings; dev-demo's drupal/drupal-ldap site wires them up."
else
    echo "Skipping LDAP. (Run with 'install-ldap' (lite: lldap) or 'install-ldap-full' (OpenLDAP + lldap); not part of install-all)"
fi

# =================================================================
# SHARED DEVELOPMENT SERVICES (added in v89): one 'devsvc' command for every service below, each in
# its own Docker container on the base section's Docker, published on 127.0.0.1 only.
#   install-cache      = install-redis + install-memcached (in install-all)
#   install-redis      Redis 8 (the official redis:8 image, with the search/vector, JSON, time series
#                      and probabilistic modules built in), redis-tools (redis-cli, redis-benchmark)
#                      from Debian, and the Redis Insight desktop app (a .deb, so it gets a launcher icon)
#   install-memcached  Memcached 1.6
#   install-search     = install-solr + install-opensearch + install-meilisearch + install-typesense (in
#                      install-all); install-elasticsearch is opt-in (in no group, not in install-all)
#   install-solr       Solr 9.10 in SolrCloud mode (one node, embedded ZooKeeper), basic auth (user solr),
#                      the modules search_api_solr's jump-start configset uses. Drupal's main search engine.
#   install-opensearch OpenSearch 3, one node, security plugin on (user admin), plain HTTP on 127.0.0.1
#   install-elasticsearch  Elasticsearch 9, one node, security on (user elastic), plain HTTP; host port 9201
#   install-meilisearch    Meilisearch 1.x (Community Edition, MIT), master key
#   install-typesense      Typesense 30, API key
#   install-vector     = install-qdrant + sqlite-vec (in install-all)
#   install-qdrant     Qdrant 1.x vector database (REST 6333, gRPC 6334); no login locally, QDRANT_API_KEY
#                      (secrets.env) adds one, needed before a LAN share
#   sqlite-vec         (install-vector) vector search inside SQLite: the loadable extension for Debian's
#                      sqlite3 in ~/.local/lib/sqlite-vec (.load ~/.local/lib/sqlite-vec/vec0)
#   install-milvus     Milvus 3 standalone, one container (embedded etcd, local storage, WebUI 9091). Opt-in,
#                      in no group: Milvus asks for 8 GB of RAM, more than this VM has. Milvus Lite (pip
#                      install pymilvus, per project) is the everyday route here; this is for trying the server.
#   install-mongodb    MongoDB 8 (the official mongo:8 image, WiredTiger cache 0.5 GB), mongosh, the MongoDB
#                      Database Tools (mongodump, mongorestore, mongoimport...), the Compass desktop app, and
#                      php-mongodb through install-web. No login by default, as the frameworks' defaults
#                      assume; MONGO_ROOT_PASSWORD (secrets.env) adds user root and turns authentication on.
#   install-mongodb-atlas-local  Atlas Local (mongodb/mongodb-atlas-local: mongod as a one-node replica set
#                      plus mongot, for Atlas Search and Vector Search) on 127.0.0.1:27018, and the Atlas CLI.
#                      Opt-in; no Atlas account needed. Wants ~2 GB of RAM.
#   install-selenium   (v91, part of install-testing) a Selenium Grid in one container (selenium/standalone-chrome:
#                      Grid 4, Chrome and its chromedriver, Xvfb): WebDriver on 127.0.0.1:4444, noVNC on
#                      127.0.0.1:7900 to watch the browser. A heavy engine (~1.6 GB), created stopped. No login,
#                      so never shared with your other laptops. See the testing section further down.
# MongoDB's apt repository is not used (it may not carry trixie): the servers are containers, and mongosh,
# the Database Tools, Compass and the Atlas CLI are MongoDB's own .deb downloads, each checked with dpkg
# (and with the SHA-256 MongoDB publishes, for the Database Tools) and reinstalled only for a newer release.
# The heavy engines (Solr, OpenSearch, Elasticsearch: 1-1.5 GB each; Milvus and Atlas Local: 2 GB and more;
# v91: the Selenium Grid, ~1.6 GB) run one at a time, and not next to SQL Server or Oracle (install-db-server): 'devsvc up solr' stops the
# others first, and 'mssql up' / 'oracle up' stop them too. OpenSearch and Elasticsearch run with discovery.type=single-node
# and node.store.allow_mmap=false: vm.max_map_count cannot be raised from inside ChromeOS's Linux
# container, and without mmap they do not need it. Their disk watermarks are off, so a nearly full disk
# does not make an index read-only. No Dashboards or Kibana. Solr's security.json goes into ZooKeeper on
# its first 'devsvc up' (setup leaves it stopped), so it is protected from its first answer on.
# Why shared services rather than DDEV add-ons: one Redis serves Drupal in DDEV, Laravel and Symfony on
# the host and Python or Node scripts alike, and costs its memory once. Drupal in DDEV reaches each
# service by its DDEV name (redis: devredis:6379, memcached: devmemcached:11211): the containers join
# DDEV's ddev_default network under those aliases, the way lldap does. The 'dev' prefix keeps clear of
# the ddev-redis add-on's 'redis' service name, so a project can still use the add-on instead.
#   devsvc status                   every service: running or stopped, port, RAM in use, DDEV name
#   devsvc up NAME... | down NAME... | down all
#   devsvc cli NAME                 redis-cli for redis; a small prompt for memcached's text protocol
#   devsvc info NAME                connection settings (host, DDEV, PHP frameworks, Python, Node)
#   devsvc password NAME | logs NAME | ddev (rejoin DDEV's network after DDEV recreated it)
# Containers devsvc-<name>, data volumes devsvc-<name>-data (Memcached keeps nothing, so it has none).
# Autostart: DEVSVC_AUTOSTART in secrets.env (default "redis memcached") gets restart unless-stopped;
# every other service is created stopped and started with 'devsvc up'. 'devsvc down' on an autostart
# service keeps it down across Linux restarts until 'devsvc up' (Docker's unless-stopped). Setup
# applies DEVSVC_AUTOSTART on every run and starts what it names.
# Memory guard: 'devsvc up' refuses a start that would take the services' estimates past DEVSVC_RAM_MB
# (default 3000; the Linux VM sees ~6.4 GB of 8) and names what to stop; DEVSVC_FORCE=1 overrides.
# Values live in ~/.config/devsvc/devsvc.env (mode 600), which devsvc, dev-test, dev-init and dev-demo
# read. Two kinds: "live" values, applied to the container on every setup run (REDIS_PASSWORD: the
# environment, then secrets.env, win; empty = no login, fine on 127.0.0.1, and required before a LAN
# share), and "kept" values: SOLR_PASSWORD, OPENSEARCH_ADMIN_PASSWORD, ELASTIC_PASSWORD, MEILI_MASTER_KEY
# and TYPESENSE_API_KEY. A kept value comes from secrets.env the first time (else it is generated) and
# from then on devsvc.env wins, because Solr's, OpenSearch's and Elasticsearch's are stored in their
# data. To change one: edit devsvc.env, then start the service over (below).
# Updates: a rerun pulls newer images and recreates a container on a newer image or changed settings;
# the data volume stays. REDIS_IMAGE, MEMCACHED_IMAGE, SOLR_IMAGE (e.g. solr:10.0), OPENSEARCH_IMAGE,
# ELASTICSEARCH_IMAGE, MEILISEARCH_IMAGE and TYPESENSE_IMAGE pick others. Elasticsearch, Meilisearch and
# Typesense have no moving major tag, so setup looks up the newest 9.x / 1.x / 30.x on Docker Hub (a pinned
# release when that fails). REDIS_MAXMEMORY (default 256mb) and
# REDIS_MAXMEMORY_POLICY (default allkeys-lru; noeviction for a project that queues jobs in Redis) and
# MEMCACHED_MB (default 64) size them. Start over: docker rm -f devsvc-redis && docker volume rm
# devsvc-redis-data, then rerun setup (the same for every service).
# =================================================================
DEVSVC_ANY=0
for DS_F in redis memcached solr opensearch elasticsearch meilisearch typesense qdrant milvus mongodb mongodb-atlas-local selenium; do
    [[ "$FLAGS" == *" install-$DS_F "* ]] && DEVSVC_ANY=1
done
if [ "$DEVSVC_ANY" = 1 ]; then
    echo "================================================================="
    echo "Installing shared development services (devsvc)..."
    echo "================================================================="
    mkdir -p ~/.local/bin ~/.config/devsvc
    chmod 700 ~/.config/devsvc
    DEVSVC_ENV="$HOME/.config/devsvc/devsvc.env"

    # devsvc_value NAME: the environment's value, else secrets.env's (read in a subshell).
    devsvc_value() {
        local v="${!1:-}"
        if [ -z "$v" ] && [ -f "$HOME/.config/dev-init/secrets.env" ]; then
            v=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$HOME/.config/dev-init/secrets.env" "$1" || true)
        fi
        printf '%s' "$v"
    }
    devsvc_file_value() {   # devsvc_file_value NAME: what devsvc.env holds
        [ -f "$DEVSVC_ENV" ] || return 0
        bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$DEVSVC_ENV" "$1" || true
    }
    devsvc_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
    # The values devsvc.env holds, NAME:kind:service. live = the environment/secrets.env win, empty
    # allowed; kept = devsvc.env wins once written, else the environment/secrets.env, else generated.
    # Only the services of this run are looked at; the others' lines are carried over unchanged.
    DEVSVC_KEYS=(REDIS_PASSWORD:live:redis SOLR_PASSWORD:kept:solr OPENSEARCH_ADMIN_PASSWORD:kept:opensearch
        ELASTIC_PASSWORD:kept:elasticsearch MEILI_MASTER_KEY:kept:meilisearch TYPESENSE_API_KEY:kept:typesense
        QDRANT_API_KEY:live:qdrant MONGO_ROOT_PASSWORD:live:mongodb)
    DEVSVC_DONE=()
    # MongoDB's root password is also stored in its data: remember the one it had, to change it there.
    MONGO_ROOT_PASSWORD_WAS=$(devsvc_file_value MONGO_ROOT_PASSWORD)
    for DS_KV in "${DEVSVC_KEYS[@]}"; do
        IFS=: read -r DS_K DS_KIND DS_S <<< "$DS_KV"
        [[ "$FLAGS" == *" install-$DS_S "* ]] || continue
        DEVSVC_DONE+=("$DS_K")
        if [ "$DS_KIND" = live ]; then
            DS_V=$(devsvc_value "$DS_K")
        else
            DS_V=$(devsvc_file_value "$DS_K")
            [ -n "$DS_V" ] || DS_V=$(devsvc_value "$DS_K")
            # Letters, digits and '_', upper and lower case and a digit: OpenSearch's password rules
            # (one of each, and a non-alphanumeric) and every URL and header take it as it is.
            [ -n "$DS_V" ] || DS_V="Dev_$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)9"
        fi
        printf -v "$DS_K" '%s' "$DS_V"
    done
    # Values of services not installed on this run are kept as they were.
    (
        umask 077
        {
            echo "# ~/.config/devsvc/devsvc.env: written by dev-setup (v89, the shared services) on every run. devsvc,"
            echo "# dev-test, dev-init and dev-demo read it; ~/.bashrc does not. 'devsvc password NAME' prints a value."
            echo "# REDIS_PASSWORD, QDRANT_API_KEY and MONGO_ROOT_PASSWORD come from secrets.env on each setup run"
            echo "# (empty: no login, fine on 127.0.0.1; set one before sharing that service with your other laptops)."
            echo "# The other values are kept: stored in the services' data, so changing one here needs a fresh start"
            echo "# of that service (docker rm -f devsvc-NAME && docker volume rm devsvc-NAME-data, then setup)."
            for DS_K in "${DEVSVC_DONE[@]}"; do
                echo "$DS_K=$(devsvc_quote "${!DS_K}")"
            done
            if [ -f "$DEVSVC_ENV" ]; then
                grep -E '^[A-Z_][A-Z0-9_]*=' "$DEVSVC_ENV" | while IFS= read -r DS_LINE; do
                    DS_K=${DS_LINE%%=*}
                    [[ " ${DEVSVC_DONE[*]} " == *" $DS_K "* ]] || printf '%s\n' "$DS_LINE"
                done
            fi
        } > "$DEVSVC_ENV.new"
    )
    mv "$DEVSVC_ENV.new" "$DEVSVC_ENV"
    chmod 600 "$DEVSVC_ENV"

    DEVSVC_AUTOSTART_LIST=$(devsvc_value DEVSVC_AUTOSTART)
    # An unset DEVSVC_AUTOSTART means the default; set to "" in secrets.env it still means the default,
    # so "none" is how to autostart nothing.
    [ -n "$DEVSVC_AUTOSTART_LIST" ] || DEVSVC_AUTOSTART_LIST="redis memcached"
    devsvc_autostarts() { [[ " $(echo "$DEVSVC_AUTOSTART_LIST" | tr ',;' '  ') " == *" $1 "* ]]; }

    # devsvc_pull IMAGE: pull it, or check for an update. 1 = no copy of the image on this machine.
    devsvc_pull() {
        local img=$1
        if sudo docker image inspect "$img" > /dev/null 2>&1; then
            echo "Checking $img for an update..."
        else
            echo "Pulling $img..."
        fi
        if ! sudo docker pull -q "$img" > /dev/null 2>&1; then
            echo "NOTICE: 'docker pull $img' failed (network, or the registry is busy)."
            sudo docker image inspect "$img" > /dev/null 2>&1 || return 1
            echo "        Keeping the copy already on this machine."
        fi
        return 0
    }
    # devsvc_container NAME IMAGE: create or update devsvc-NAME from the arrays DS_ARGS (docker create
    # options: ports, volume, limits) and DS_CMD (the command). The container is recreated when the image
    # is newer or DS_ARGS/DS_CMD changed (a fingerprint label records them); its volume stays, and a
    # container that was running is started again. Then the autostart policy is applied, an autostart
    # service is started, and a running one joins DDEV's network. 1 = no image, nothing done.
    devsvc_container() {
        local n=$1 img=$2 c="devsvc-$1" have_img new_img have_fp fp was_running=false policy=no alias=dev$1 flag=install-$1
        # The DDEV names and flags that are not simply dev<name> / install-<name> (devsvc's table has them all).
        case "$n" in
            elasticsearch) alias=develastic ;;
            meilisearch)   alias=devmeili ;;
            mongodb)       alias=devmongo ;;
            atlas-local)   alias=devmongo-atlas; flag=install-mongodb-atlas-local ;;
        esac
        devsvc_pull "$img" || { echo "NOTICE: no $img on this machine, so $c is not set up; rerun setup with $flag."; return 1; }
        new_img=$(sudo docker image inspect -f '{{.Id}}' "$img")
        fp=$(printf '%s\n' "$img" "${DS_ARGS[@]}" "${DS_CMD[@]}" | sha256sum | cut -c1-16)
        have_img=$(sudo docker inspect -f '{{.Image}}' "$c" 2> /dev/null || true)
        have_fp=$(sudo docker inspect -f '{{index .Config.Labels "dev-setup.devsvc-config"}}' "$c" 2> /dev/null || true)
        if [ -n "$have_img" ] && { [ "$have_img" != "$new_img" ] || [ "$have_fp" != "$fp" ]; }; then
            was_running=$(sudo docker inspect -f '{{.State.Running}}' "$c" 2> /dev/null || echo false)
            if [ "$have_img" != "$new_img" ]; then
                echo "Recreating $c on the newer $img; its data stays in its volume."
            else
                echo "Recreating $c with changed settings (a password, memory size or other option); its data stays in its volume."
            fi
            sudo docker rm -f "$c" > /dev/null
            have_img=""
        fi
        devsvc_autostarts "$n" && policy=unless-stopped
        if [ -z "$have_img" ]; then
            sudo docker create --name "$c" --hostname "$c" --restart "$policy" \
                --label "dev-setup=$flag" --label "dev-setup.devsvc=$n" --label "dev-setup.devsvc-config=$fp" \
                "${DS_ARGS[@]}" "$img" "${DS_CMD[@]}" > /dev/null
            echo "Created the $c container on $img."
        else
            sudo docker update --restart "$policy" "$c" > /dev/null
            echo "$c is up to date on $img."
        fi
        if [ "$policy" = unless-stopped ] || [ "$was_running" = true ]; then
            sudo docker start "$c" > /dev/null || true
        fi
        if [ "$(sudo docker inspect -f '{{.State.Running}}' "$c" 2> /dev/null)" = true ]; then
            if [ "$policy" = unless-stopped ]; then echo "$c is running and starts with Linux (DEVSVC_AUTOSTART)."
            else echo "$c is running now; it does not start with Linux (not in DEVSVC_AUTOSTART)."; fi
        else
            echo "$c is stopped until 'devsvc up $n' (not in DEVSVC_AUTOSTART)."
        fi
        if [ "$(sudo docker inspect -f '{{.State.Running}}' "$c" 2> /dev/null)" = true ] \
            && sudo docker network inspect ddev_default > /dev/null 2>&1; then
            if ! sudo docker inspect -f '{{json .NetworkSettings.Networks}}' "$c" | grep -q '"ddev_default"'; then
                sudo docker network connect --alias "$alias" ddev_default "$c" > /dev/null 2>&1 || true
            fi
            echo "$c is on DDEV's network: Drupal in DDEV reaches it as $alias."
        fi
        return 0
    }
fi

# Redis 8 (install-redis, part of install-cache; added in v89)
if [[ "$FLAGS" =~ " install-redis " ]]; then
    echo "--- Redis 8 (install-redis)"
    # redis-cli and redis-benchmark on the host (Debian's redis-tools: 8.0 on trixie, which talks to 8.x).
    sudo apt install -y redis-tools
    REDIS_IMAGE="${REDIS_IMAGE:-redis:8}"
    REDIS_MAXMEMORY="${REDIS_MAXMEMORY:-256mb}"
    REDIS_MAXMEMORY_POLICY="${REDIS_MAXMEMORY_POLICY:-allkeys-lru}"
    # The image's entrypoint adds the built-in modules (search and vector search, JSON, time series,
    # Bloom and friends) with --loadmodule when it runs redis-server, so the command below keeps them.
    # Data: RDB snapshots in the volume (after 60 s with a change, 300 s with 10), no AOF. protected-mode
    # off, because DDEV's containers connect over Docker's network; the host port is 127.0.0.1 only.
    # The container's memory cap: maxmemory plus 256 MB for Redis itself, forks for snapshots and clients.
    case "${REDIS_MAXMEMORY,,}" in
        *gb) REDIS_CAP_MB=$(( ${REDIS_MAXMEMORY//[!0-9]/} * 1024 + 256 )) ;;
        *mb) REDIS_CAP_MB=$(( ${REDIS_MAXMEMORY//[!0-9]/} + 256 )) ;;
        *)   REDIS_CAP_MB=512 ;;
    esac
    DS_ARGS=(-p 127.0.0.1:6379:6379 -v devsvc-redis-data:/data --memory "${REDIS_CAP_MB}m")
    DS_CMD=(redis-server --save 60 1 --save 300 10 --appendonly no --protected-mode no
        --maxmemory "$REDIS_MAXMEMORY" --maxmemory-policy "$REDIS_MAXMEMORY_POLICY")
    if [ -n "$REDIS_PASSWORD" ]; then DS_CMD+=(--requirepass "$REDIS_PASSWORD"); fi
    devsvc_container redis "$REDIS_IMAGE" || true

    # Redis Insight: Redis's desktop GUI (browser, profiler, vector search workbench), as a .deb so
    # ChromeOS lists it in the launcher. Source-available (Server Side Public License), free to use. From
    # the project's GitHub release; the release's latest-linux.yml carries the .deb's SHA-512, checked when
    # it is there. Only reinstalled when the release has a newer version. REDIS_INSIGHT=0 skips it.
    if [ "${REDIS_INSIGHT:-1}" = 1 ]; then
        RI_TAG=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/redis/RedisInsight/releases/latest 2> /dev/null | sed 's|.*/tag/||' || true)
        RI_HAVE=$(dpkg-query -W -f='${Version}' redisinsight 2> /dev/null || true)
        if ! [[ "$RI_TAG" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "NOTICE: could not resolve the latest Redis Insight release${RI_HAVE:+; keeping $RI_HAVE}. Rerun setup with install-redis."
        elif [ "$RI_HAVE" = "${RI_TAG#v}" ]; then
            echo "Redis Insight ${RI_TAG#v} is current."
        else
            RI_BASE="https://github.com/redis/RedisInsight/releases/download/$RI_TAG"
            RI_DEB="Redis-Insight-linux-amd64.deb"
            RI_TMP=$(mktemp -d)
            if curl -fsSL --retry 3 -o "$RI_TMP/$RI_DEB" "$RI_BASE/$RI_DEB" && dpkg-deb --info "$RI_TMP/$RI_DEB" > /dev/null 2>&1; then
                RI_OK=1
                if curl -fsSL --retry 3 -o "$RI_TMP/latest-linux.yml" "$RI_BASE/latest-linux.yml" 2> /dev/null; then
                    RI_WANT=$(awk -v f="$RI_DEB" '$0 ~ "url: *"f"$" {getline; sub(/^ *sha512: */, ""); print; exit}' "$RI_TMP/latest-linux.yml")
                    RI_GOT=$(openssl dgst -sha512 -binary "$RI_TMP/$RI_DEB" | base64 -w0)
                    if [ -z "$RI_WANT" ]; then
                        echo "NOTICE: latest-linux.yml does not list $RI_DEB; installing on dpkg's integrity check alone."
                    elif [ "$RI_WANT" != "$RI_GOT" ]; then
                        echo "NOTICE: $RI_DEB does not match the release's SHA-512; not installed. Rerun setup with install-redis."
                        RI_OK=0
                    fi
                fi
                if [ "$RI_OK" = 1 ]; then
                    sudo DEBIAN_FRONTEND=noninteractive apt install -y "$RI_TMP/$RI_DEB" \
                        && echo "Redis Insight ${RI_TAG#v} installed${RI_HAVE:+ (was $RI_HAVE)}: pick it from the ChromeOS launcher." \
                        || echo "NOTICE: apt could not install $RI_DEB; rerun setup with install-redis."
                fi
            else
                echo "NOTICE: could not download $RI_DEB ($RI_TAG) from GitHub; rerun setup with install-redis. Redis works without it."
            fi
            rm -rf "$RI_TMP"
        fi
    fi
    echo "Redis: redis://127.0.0.1:6379 here, redis://devredis:6379 from DDEV. 'devsvc cli redis', 'devsvc info redis'."
else
    echo "Skipping Redis. (Run with 'install-redis' or 'install-cache')"
fi

# Memcached 1.6 (install-memcached, part of install-cache; added in v89)
if [[ "$FLAGS" =~ " install-memcached " ]]; then
    echo "--- Memcached 1.6 (install-memcached)"
    MEMCACHED_IMAGE="${MEMCACHED_IMAGE:-memcached:1.6}"
    MEMCACHED_MB="${MEMCACHED_MB:-64}"
    [[ "$MEMCACHED_MB" =~ ^[0-9]+$ ]] || MEMCACHED_MB=64
    # No volume: Memcached keeps everything in memory by design. No login: it never leaves 127.0.0.1 and
    # the laptop-network share leaves it out.
    DS_ARGS=(-p 127.0.0.1:11211:11211 --memory "$(( MEMCACHED_MB + 64 ))m")
    DS_CMD=(memcached -m "$MEMCACHED_MB")
    devsvc_container memcached "$MEMCACHED_IMAGE" || true
    echo "Memcached: 127.0.0.1:11211 here, devmemcached:11211 from DDEV. 'devsvc cli memcached', 'devsvc info memcached'."
else
    echo "Skipping Memcached. (Run with 'install-memcached' or 'install-cache')"
fi

# --- search engines (install-search; install-elasticsearch opt-in; added in v89) ---
# devsvc_hub_tag REPO REGEX PINNED CONTAINER: the newest tag of a Docker Hub repository matching REGEX,
# for images with no moving major tag. When Docker Hub cannot be asked: the tag CONTAINER already runs
# (never a step back to an older release, which a data volume may not open), else PINNED.
devsvc_hub_tag() {
    local tag have
    tag=$(curl -fsS --max-time 20 "https://hub.docker.com/v2/repositories/$1/tags?page_size=100&ordering=last_updated" 2> /dev/null \
        | jq -r '.results[].name' 2> /dev/null | grep -E "$2" | sort -V | tail -n 1 || true)
    if [ -z "$tag" ]; then
        have=$(sudo docker inspect -f '{{.Config.Image}}' "$4" 2> /dev/null || true)
        case "$have" in "${1#library/}":*) tag=${have##*:} ;; esac
    fi
    printf '%s' "${tag:-$3}"
}

# Solr 9.10 (install-solr, part of install-search)
if [[ "$FLAGS" =~ " install-solr " ]]; then
    echo "--- Solr 9.10 (install-solr)"
    # solr:9.10 follows 9.10's bug-fix releases. search_api_solr calls Solr 10 experimental; to try it:
    # SOLR_IMAGE=solr:10.0 (a 9.x data volume is not guaranteed to open in 10: start that one over).
    SOLR_IMAGE="${SOLR_IMAGE:-solr:9.10}"
    # SolrCloud on one node with the embedded ZooKeeper (port 9983 inside the container), which is what
    # Drupal's "Solr Cloud with Basic Auth" connector and its configset upload expect, as with ddev-solr.
    # SOLR_MODULES: the modules search_api_solr's jump-start configset loads. solr.config.lib.enabled: the
    # configsets' <lib> directives, off by default since Solr 9.8. Heap 512 MB in a 1 GB container.
    DS_ARGS=(-p 127.0.0.1:8983:8983 -v devsvc-solr-data:/var/solr --memory 1g
        -e SOLR_HEAP=512m -e "SOLR_MODULES=analysis-extras,extraction,langid,ltr"
        -e "SOLR_OPTS=-Dsolr.config.lib.enabled=true")
    DS_CMD=(solr-foreground -c)
    devsvc_container solr "$SOLR_IMAGE" || true
    echo "Solr: http://127.0.0.1:8983 here, http://devsolr:8983 from DDEV, user solr ('devsvc password solr'). 'devsvc up solr' starts it."
else
    echo "Skipping Solr. (Run with 'install-solr' or 'install-search')"
fi

# OpenSearch 3 (install-opensearch, part of install-search)
if [[ "$FLAGS" =~ " install-opensearch " ]]; then
    echo "--- OpenSearch 3 (install-opensearch)"
    OPENSEARCH_IMAGE="${OPENSEARCH_IMAGE:-opensearchproject/opensearch:3}"
    # The security plugin stays on (user admin, OPENSEARCH_ADMIN_PASSWORD, which the image's demo setup
    # takes on the volume's first start) with TLS left on its transport layer and off on HTTP, so clients
    # use http://127.0.0.1:9200 with a login. The performance-analyzer agent is off to save memory.
    DS_ARGS=(-p 127.0.0.1:9200:9200 -v devsvc-opensearch-data:/usr/share/opensearch/data --memory 1280m
        -e discovery.type=single-node -e node.store.allow_mmap=false
        -e plugins.security.ssl.http.enabled=false -e cluster.routing.allocation.disk.threshold_enabled=false
        -e "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m" -e DISABLE_PERFORMANCE_ANALYZER_AGENT_CLI=true
        -e "OPENSEARCH_INITIAL_ADMIN_PASSWORD=$OPENSEARCH_ADMIN_PASSWORD")
    DS_CMD=()
    devsvc_container opensearch "$OPENSEARCH_IMAGE" || true
    echo "OpenSearch: http://127.0.0.1:9200 here, http://devopensearch:9200 from DDEV, user admin. 'devsvc up opensearch'."
else
    echo "Skipping OpenSearch. (Run with 'install-opensearch' or 'install-search')"
fi

# Elasticsearch 9 (install-elasticsearch: opt-in, in no group, not in install-all)
if [[ "$FLAGS" =~ " install-elasticsearch " ]]; then
    echo "--- Elasticsearch 9 (install-elasticsearch)"
    ELASTICSEARCH_IMAGE="${ELASTICSEARCH_IMAGE:-elasticsearch:$(devsvc_hub_tag library/elasticsearch '^9\.[0-9]+\.[0-9]+$' 9.5.4 devsvc-elasticsearch)}"
    # Host port 9201, so it never clashes with OpenSearch's 9200 (inside Docker's networks it is 9200).
    # Security on (user elastic, ELASTIC_PASSWORD) with plain HTTP; machine learning and the GeoIP
    # database download off, to save memory and network.
    DS_ARGS=(-p 127.0.0.1:9201:9200 -v devsvc-elasticsearch-data:/usr/share/elasticsearch/data --memory 1280m
        -e discovery.type=single-node -e node.store.allow_mmap=false
        -e xpack.security.enabled=true -e xpack.security.http.ssl.enabled=false -e xpack.ml.enabled=false
        -e ingest.geoip.downloader.enabled=false -e cluster.routing.allocation.disk.threshold_enabled=false
        -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" -e "ELASTIC_PASSWORD=$ELASTIC_PASSWORD")
    DS_CMD=()
    devsvc_container elasticsearch "$ELASTICSEARCH_IMAGE" || true
    echo "Elasticsearch: http://127.0.0.1:9201 here, http://develastic:9200 from DDEV, user elastic. 'devsvc up elasticsearch'."
else
    echo "Skipping Elasticsearch. (Run with 'install-elasticsearch'; opt-in, not part of install-all)"
fi

# Meilisearch 1.x (install-meilisearch, part of install-search)
if [[ "$FLAGS" =~ " install-meilisearch " ]]; then
    echo "--- Meilisearch (install-meilisearch)"
    MEILISEARCH_IMAGE="${MEILISEARCH_IMAGE:-getmeili/meilisearch:$(devsvc_hub_tag getmeili/meilisearch '^v1\.[0-9]+\.[0-9]+$' v1.54.0 devsvc-meilisearch)}"
    # The Community Edition (MIT). MEILI_ENV=development keeps the search preview page at
    # http://localhost:7700. A newer release opens the existing data itself (dumpless upgrade), so the
    # container can follow new releases. Indexing memory capped at 256 MB.
    DS_ARGS=(-p 127.0.0.1:7700:7700 -v devsvc-meilisearch-data:/meili_data --memory 1g
        -e "MEILI_MASTER_KEY=$MEILI_MASTER_KEY" -e MEILI_ENV=development -e MEILI_NO_ANALYTICS=true
        -e MEILI_EXPERIMENTAL_DUMPLESS_UPGRADE=true -e MEILI_MAX_INDEXING_MEMORY=256Mb)
    DS_CMD=()
    devsvc_container meilisearch "$MEILISEARCH_IMAGE" || true
    echo "Meilisearch: http://127.0.0.1:7700 here, http://devmeili:7700 from DDEV, master key 'devsvc password meilisearch'. 'devsvc up meilisearch'."
else
    echo "Skipping Meilisearch. (Run with 'install-meilisearch' or 'install-search')"
fi

# Typesense 30 (install-typesense, part of install-search)
if [[ "$FLAGS" =~ " install-typesense " ]]; then
    echo "--- Typesense (install-typesense)"
    TYPESENSE_IMAGE="${TYPESENSE_IMAGE:-typesense/typesense:$(devsvc_hub_tag typesense/typesense '^30\.[0-9]+$' 30.2 devsvc-typesense)}"
    # Typesense keeps its index in RAM (and on disk for restarts): small projects only on this machine.
    # Every request carries the API key, local ones included.
    DS_ARGS=(-p 127.0.0.1:8108:8108 -v devsvc-typesense-data:/data --memory 1g)
    DS_CMD=(--data-dir /data --api-key "$TYPESENSE_API_KEY" --enable-cors)
    devsvc_container typesense "$TYPESENSE_IMAGE" || true
    echo "Typesense: http://127.0.0.1:8108 here, http://devtypesense:8108 from DDEV, API key 'devsvc password typesense'. 'devsvc up typesense'."
else
    echo "Skipping Typesense. (Run with 'install-typesense' or 'install-search')"
fi

# --- vector stores and MongoDB (install-vector, install-mongodb; install-milvus and
# install-mongodb-atlas-local opt-in; added in v89) ---
# devsvc_deb PACKAGE VERSION URL [SHA256]: install a vendor .deb unless that version is installed. The file
# must pass the SHA-256 when one is given and dpkg's own integrity check. Never fatal: a NOTICE says why.
devsvc_deb() {
    local pkg=$1 ver=$2 url=$3 sha=${4:-} have tmp
    have=$(dpkg-query -W -f='${Version}' "$pkg" 2> /dev/null || true)
    if [ -n "$have" ] && [ "${have%%-*}" = "$ver" ]; then echo "$pkg $ver is current."; return 0; fi
    tmp=$(mktemp -d)
    if ! curl -fsSL --retry 3 -o "$tmp/$pkg.deb" "$url"; then
        echo "NOTICE: could not download $pkg $ver ($url)${have:+; keeping $have}."; rm -rf "$tmp"; return 0
    fi
    if [ -n "$sha" ] && ! echo "$sha  $tmp/$pkg.deb" | sha256sum -c - > /dev/null 2>&1; then
        echo "NOTICE: $pkg $ver does not match its published SHA-256; not installed."; rm -rf "$tmp"; return 0
    fi
    if ! dpkg-deb --info "$tmp/$pkg.deb" > /dev/null 2>&1; then
        echo "NOTICE: the $pkg download is not a valid .deb; not installed."; rm -rf "$tmp"; return 0
    fi
    sudo DEBIAN_FRONTEND=noninteractive apt install -y "$tmp/$pkg.deb" > /dev/null \
        && echo "$pkg $ver installed${have:+ (was $have)}." \
        || echo "NOTICE: apt could not install $pkg $ver."
    rm -rf "$tmp"
}
# gh_latest OWNER/REPO: the x.y.z of a GitHub repository's latest release (from the redirect, not the
# rate-limited API); empty when it cannot be resolved. Tags like v1.2.3 or atlascli/v1.2.3 both work.
gh_latest() {
    curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" 2> /dev/null \
        | sed 's|.*/tag/||; s|%2F|/|g' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$' || true
}

# Qdrant (install-qdrant, part of install-vector)
if [[ "$FLAGS" =~ " install-qdrant " ]]; then
    echo "--- Qdrant (install-qdrant)"
    QDRANT_IMAGE="${QDRANT_IMAGE:-qdrant/qdrant:$(devsvc_hub_tag qdrant/qdrant '^v1\.[0-9]+\.[0-9]+$' v1.19.0 devsvc-qdrant)}"
    DS_ARGS=(-p 127.0.0.1:6333:6333 -p 127.0.0.1:6334:6334 -v devsvc-qdrant-data:/qdrant/storage --memory 1g
        -e QDRANT__TELEMETRY_DISABLED=true)
    if [ -n "$QDRANT_API_KEY" ]; then DS_ARGS+=(-e "QDRANT__SERVICE__API_KEY=$QDRANT_API_KEY"); fi
    DS_CMD=()
    devsvc_container qdrant "$QDRANT_IMAGE" || true
    echo "Qdrant: http://127.0.0.1:6333 (dashboard: /dashboard), gRPC 6334; http://devqdrant:6333 from DDEV. 'devsvc up qdrant'."
else
    echo "Skipping Qdrant. (Run with 'install-qdrant' or 'install-vector')"
fi

# sqlite-vec (install-vector): vector search inside SQLite, as a loadable extension for Debian's sqlite3.
# Its Python and npm packages stay per project (pip install sqlite-vec, npm install sqlite-vec).
if [[ "$FLAGS" =~ " install-vector " ]]; then
    echo "--- sqlite-vec (install-vector)"
    SV_DIR="$HOME/.local/lib/sqlite-vec"
    SV_VER=$(gh_latest asg017/sqlite-vec)
    SV_HAVE=$(cat "$SV_DIR/VERSION" 2> /dev/null || true)
    if [ -z "$SV_VER" ]; then
        echo "NOTICE: could not resolve the latest sqlite-vec release${SV_HAVE:+; keeping $SV_HAVE}. Rerun setup with install-vector."
    elif [ "$SV_HAVE" = "$SV_VER" ] && [ -f "$SV_DIR/vec0.so" ]; then
        echo "sqlite-vec $SV_VER is current."
    else
        SV_TGZ="sqlite-vec-$SV_VER-loadable-linux-x86_64.tar.gz"
        SV_BASE="https://github.com/asg017/sqlite-vec/releases/download/v$SV_VER"
        SV_TMP=$(mktemp -d)
        # sqlite-vec's checksums.txt (written by sqlite-dist) is "FILENAME HASH", one space, not sha256sum's
        # "HASH  FILENAME": find the line by name in either column and rewrite it for sha256sum -c.
        if curl -fsSL --retry 3 -o "$SV_TMP/$SV_TGZ" "$SV_BASE/$SV_TGZ" \
            && curl -fsSL --retry 3 -o "$SV_TMP/checksums.txt" "$SV_BASE/checksums.txt" \
            && ( cd "$SV_TMP" && awk -v f="$SV_TGZ" '$1 == f { print $2 "  " f; n++ } $2 == f || $2 == "*" f { print $1 "  " f; n++ } END { exit !n }' checksums.txt \
                 | sha256sum -c - > /dev/null ) \
            && tar -xzf "$SV_TMP/$SV_TGZ" -C "$SV_TMP" && [ -f "$SV_TMP/vec0.so" ]; then
            mkdir -p "$SV_DIR"
            install -m 644 "$SV_TMP/vec0.so" "$SV_DIR/vec0.so"
            echo "$SV_VER" > "$SV_DIR/VERSION"
            echo "sqlite-vec $SV_VER installed in $SV_DIR${SV_HAVE:+ (was $SV_HAVE)}."
        else
            echo "NOTICE: could not download or verify $SV_TGZ from GitHub; rerun setup with install-vector."
        fi
        rm -rf "$SV_TMP"
    fi
    # SQLITE_VEC for scripts and notebooks: conn.load_extension(os.environ["SQLITE_VEC"]).
    sed -i '/^# >>> dev-setup sqlite-vec >>>$/,/^# <<< dev-setup sqlite-vec <<<$/d' ~/.bashrc
    cat >> ~/.bashrc << 'SVEOF'
# >>> dev-setup sqlite-vec >>>
# Written by dev-setup (install-vector); replaced on each run. In sqlite3: .load ~/.local/lib/sqlite-vec/vec0
export SQLITE_VEC="$HOME/.local/lib/sqlite-vec/vec0"
# <<< dev-setup sqlite-vec <<<
SVEOF
    case "$(readlink -f "$(command -v sqlite3 2> /dev/null)" 2> /dev/null)" in
        /usr/bin/sqlite3) ;;
        *) echo "NOTICE: 'sqlite3' on PATH is not Debian's ($(command -v sqlite3 2> /dev/null || echo missing)); the extension is built for any SQLite 3.41+, but dev-test checks Debian's." ;;
    esac
    echo "Try: sqlite3 :memory: '.load $SV_DIR/vec0' 'select vec_version();'"
else
    echo "Skipping sqlite-vec. (Run with 'install-vector')"
fi

# Milvus 3 standalone (install-milvus: opt-in, in no group, not in install-all)
if [[ "$FLAGS" =~ " install-milvus " ]]; then
    echo "--- Milvus standalone (install-milvus)"
    echo "NOTICE: Milvus asks for 8 GB of RAM; this Linux sees about 6.4 GB. It is created stopped, and 'devsvc up milvus'"
    echo "        stops the other heavy engines first. Milvus Lite (pip install pymilvus, per project) needs no server."
    MILVUS_IMAGE="${MILVUS_IMAGE:-milvusdb/milvus:$(devsvc_hub_tag milvusdb/milvus '^v3\.[0-9]+\.[0-9]+$' v3.0.2 devsvc-milvus)}"
    # The embedded mode of Milvus's own standalone_embed.sh: embedded etcd, local storage, Woodpecker WAL.
    mkdir -p ~/.config/devsvc/milvus
    cat > ~/.config/devsvc/milvus/embedEtcd.yaml << 'MVEOF'
# Written by dev-setup (install-milvus): Milvus's embedded etcd (as in Milvus's standalone_embed.sh).
listen-client-urls: http://0.0.0.0:2379
advertise-client-urls: http://0.0.0.0:2379
quota-backend-bytes: 4294967296
auto-compaction-mode: revision
auto-compaction-retention: '1000'
MVEOF
    [ -f ~/.config/devsvc/milvus/user.yaml ] || echo "# Your overrides of milvus.yaml (kept across setup runs); 'devsvc down milvus && devsvc up milvus' applies them." > ~/.config/devsvc/milvus/user.yaml
    DS_ARGS=(-p 127.0.0.1:19530:19530 -p 127.0.0.1:9091:9091 -v devsvc-milvus-data:/var/lib/milvus
        -v "$HOME/.config/devsvc/milvus/embedEtcd.yaml:/milvus/configs/embedEtcd.yaml:ro"
        -v "$HOME/.config/devsvc/milvus/user.yaml:/milvus/configs/user.yaml:ro"
        --security-opt seccomp:unconfined
        -e ETCD_USE_EMBED=true -e ETCD_DATA_DIR=/var/lib/milvus/etcd -e ETCD_CONFIG_PATH=/milvus/configs/embedEtcd.yaml
        -e COMMON_STORAGETYPE=local -e DEPLOY_MODE=STANDALONE)
    DS_CMD=(milvus run standalone)
    devsvc_container milvus "$MILVUS_IMAGE" || true
    echo "Milvus: 127.0.0.1:19530 (gRPC and REST), WebUI http://127.0.0.1:9091/webui; devmilvus:19530 from DDEV. 'devsvc up milvus'."
else
    echo "Skipping Milvus. (Run with 'install-milvus'; opt-in, not part of install-all)"
fi

# MongoDB 8 (install-mongodb; in install-all)
if [[ "$FLAGS" =~ " install-mongodb " ]]; then
    echo "--- MongoDB 8 (install-mongodb)"
    # Clients: mongosh (GitHub's latest release, MongoDB's .deb), the Database Tools (MongoDB's release feed,
    # with its SHA-256) and Compass (GitHub's latest release, MongoDB's .deb; a launcher icon like Cursor).
    MS_VER=$(gh_latest mongodb-js/mongosh)
    if [ -n "$MS_VER" ]; then
        devsvc_deb mongodb-mongosh "$MS_VER" "https://downloads.mongodb.com/compass/mongodb-mongosh_${MS_VER}_amd64.deb"
    else
        echo "NOTICE: could not resolve the latest mongosh release; rerun setup with install-mongodb ('devsvc cli mongodb' uses the container's)."
    fi
    # The Database Tools' feed lists every release with a package per distribution; the newest one for
    # Debian 13, else Debian 12 (they are Go programs and run on either).
    MT_JSON=$(curl -fsSL --max-time 30 https://downloads.mongodb.org/tools/db/release.json 2> /dev/null || true)
    MT_LINE=$(printf '%s' "$MT_JSON" | jq -r '
        [.versions[] | .version as $v | .downloads[]
         | select(.arch == "x86_64" and (.name == "debian13" or .name == "debian12") and .package.url != null)
         | {v: $v, n: .name, u: .package.url, s: (.package.sha256 // "")}]
        | sort_by((.v | split(".") | map(tonumber? // 0)), (.n == "debian13")) | last
        | "\(.v) \(.u) \(.s)"' 2> /dev/null || true)
    if [[ "$MT_LINE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\ https:// ]]; then
        read -r MT_VER MT_URL MT_SHA <<< "$MT_LINE"
        devsvc_deb mongodb-database-tools "$MT_VER" "$MT_URL" "$MT_SHA"
    else
        echo "NOTICE: could not read MongoDB's Database Tools feed; rerun setup with install-mongodb."
    fi
    if [ "${MONGODB_COMPASS:-1}" = 1 ]; then
        MC_VER=$(gh_latest mongodb-js/compass)
        if [ -n "$MC_VER" ]; then
            devsvc_deb mongodb-compass "$MC_VER" "https://downloads.mongodb.com/compass/mongodb-compass_${MC_VER}_amd64.deb"
        else
            echo "NOTICE: could not resolve the latest Compass release; rerun setup with install-mongodb (MONGODB_COMPASS=0 skips it)."
        fi
    fi

    MONGO_IMAGE="${MONGO_IMAGE:-mongo:8}"
    # A new MONGO_ROOT_PASSWORD (or a changed one) is written into the existing data first: the container
    # is started if needed, and user root is created, or its password changed, logging in with the old one.
    # An emptied MONGO_ROOT_PASSWORD turns authentication off again; the user stays.
    if [ -n "$MONGO_ROOT_PASSWORD" ] && [ "$MONGO_ROOT_PASSWORD" != "$MONGO_ROOT_PASSWORD_WAS" ] \
        && sudo docker container inspect devsvc-mongodb > /dev/null 2>&1; then
        MG_WAS=$(sudo docker inspect -f '{{.State.Running}}' devsvc-mongodb)
        [ "$MG_WAS" = true ] || sudo docker start devsvc-mongodb > /dev/null || true
        for _ in $(seq 1 60); do
            sudo docker exec devsvc-mongodb mongosh --quiet --eval 'db.runCommand({ping: 1}).ok' 2> /dev/null | grep -qx 1 && break
            sleep 1
        done
        # shellcheck disable=SC2016   # JavaScript for mongosh, not shell
        if sudo docker exec -e "NEWPW=$MONGO_ROOT_PASSWORD" -e "OLDPW=$MONGO_ROOT_PASSWORD_WAS" devsvc-mongodb sh -c \
            'if [ -n "$OLDPW" ]; then set -- -u root -p "$OLDPW" --authenticationDatabase admin; fi
             mongosh --quiet "$@" --eval "const a = db.getSiblingDB(\"admin\"); if (a.getUser(\"root\")) { a.changeUserPassword(\"root\", process.env.NEWPW); print(\"changed\") } else { a.createUser({user: \"root\", pwd: process.env.NEWPW, roles: [\"root\"]}); print(\"created\") }"' \
            > /dev/null 2>&1; then
            echo "MongoDB: user root now has MONGO_ROOT_PASSWORD."
        else
            echo "NOTICE: could not set user root's password in the existing MongoDB data (was the old password changed by hand?)."
            echo "        'devsvc cli mongodb' and dev-test log in with MONGO_ROOT_PASSWORD; start over if you no longer know the old one."
        fi
        [ "$MG_WAS" = true ] || sudo docker stop devsvc-mongodb > /dev/null || true
    fi
    DS_ARGS=(-p 127.0.0.1:27017:27017 -v devsvc-mongodb-data:/data/db -v devsvc-mongodb-config:/data/configdb --memory 1g)
    DS_CMD=(mongod --bind_ip_all --wiredTigerCacheSizeGB 0.5)
    # On a new data volume with a password, the first 'devsvc up mongodb' creates user root (MongoDB lets the
    # first user be created from inside the container while there is none).
    if [ -n "$MONGO_ROOT_PASSWORD" ]; then DS_CMD+=(--auth); fi
    devsvc_container mongodb "$MONGO_IMAGE" || true
    echo "MongoDB: mongodb://127.0.0.1:27017 here, mongodb://devmongo:27017 from DDEV$( [ -n "$MONGO_ROOT_PASSWORD" ] && echo ", user root"). 'devsvc up mongodb', 'devsvc cli mongodb'."
else
    echo "Skipping MongoDB. (Run with 'install-mongodb')"
fi

# MongoDB Atlas Local and the Atlas CLI (install-mongodb-atlas-local: opt-in, not in install-all)
if [[ "$FLAGS" =~ " install-mongodb-atlas-local " ]]; then
    echo "--- MongoDB Atlas Local (install-mongodb-atlas-local)"
    # The Atlas CLI: 'atlas' for Atlas accounts (optional; dev-init logs in when ATLAS_* keys are set) and its
    # 'atlas deployments' commands. The container below is run by devsvc, not by 'atlas deployments setup'.
    AC_VER=$(gh_latest mongodb/mongodb-atlas-cli)
    if [ -n "$AC_VER" ]; then
        devsvc_deb mongodb-atlas-cli "$AC_VER" "https://fastdl.mongodb.org/mongocli/mongodb-atlas-cli_${AC_VER}_linux_x86_64.deb"
    else
        echo "NOTICE: could not resolve the latest Atlas CLI release; rerun setup with install-mongodb-atlas-local."
    fi
    ATLAS_LOCAL_IMAGE="${ATLAS_LOCAL_IMAGE:-mongodb/mongodb-atlas-local:latest}"
    # A one-node replica set with mongot (Atlas Search, Vector Search) on host port 27018. No login locally.
    DS_ARGS=(-p 127.0.0.1:27018:27017 -v devsvc-atlas-local-data:/data/db -v devsvc-atlas-local-config:/data/configdb --memory 2560m)
    DS_CMD=()
    devsvc_container atlas-local "$ATLAS_LOCAL_IMAGE" || true
    echo "Atlas Local: mongodb://127.0.0.1:27018/?directConnection=true here, devmongo-atlas:27017 from DDEV. 'devsvc up atlas-local'."
else
    echo "Skipping MongoDB Atlas Local. (Run with 'install-mongodb-atlas-local'; opt-in, not part of install-all)"
fi

# Selenium Grid (install-selenium, part of install-testing; added in v91)
# One container, selenium/standalone-chrome: the Grid's router, distributor and one node with Chrome, its
# matching chromedriver and Xvfb, so RemoteWebDriver("http://127.0.0.1:4444") gets a real browser and noVNC on
# 7900 shows it working. The image has no moving 4.x tag, so setup looks up the newest dated 4.x release
# (4.N.N-YYYYMMDD) on Docker Hub, as for Elasticsearch; SELENIUM_IMAGE picks another (e.g.
# selenium/standalone-firefox:<tag>). --shm-size 2g as docker-selenium asks (Chrome crashes on Docker's 64 MB
# /dev/shm); one session at a time (SE_NODE_MAX_SESSIONS=1, the image's default, and what fits 8 GB).
# The browser in the container reaches this machine as host.docker.internal (--add-host ...:host-gateway):
# a dev server it should test must listen on 0.0.0.0 or Docker's address (172.17.0.1), not 127.0.0.1 only.
# noVNC has no password (SE_VNC_NO_PASSWORD) because the port is on 127.0.0.1 and the service is never shared.
# Drupal in DDEV reaches the Grid as devselenium:4444 once it has joined DDEV's network; per-project, the
# ddev/ddev-selenium-standalone-chrome add-on is the usual route for Drupal's own tests (dev-demo uses it).
if [[ "$FLAGS" =~ " install-selenium " ]]; then
    echo "--- Selenium Grid (install-selenium)"
    SELENIUM_IMAGE="${SELENIUM_IMAGE:-selenium/standalone-chrome:$(devsvc_hub_tag selenium/standalone-chrome '^4\.[0-9]+\.[0-9]+-[0-9]{8}$' 4.49.0-20260909 devsvc-selenium)}"
    DS_ARGS=(-p 127.0.0.1:4444:4444 -p 127.0.0.1:7900:7900 --shm-size 2g --memory 1536m
        --add-host host.docker.internal:host-gateway
        -e SE_VNC_NO_PASSWORD=true -e SE_NODE_MAX_SESSIONS=1 -e SE_NODE_SESSION_TIMEOUT=300
        -e SE_ENABLE_TRACING=false)
    DS_CMD=()
    devsvc_container selenium "$SELENIUM_IMAGE" || true
    echo "Selenium Grid: http://127.0.0.1:4444 (WebDriver), http://localhost:7900 (noVNC); devselenium:4444 from DDEV. 'devsvc up selenium'."
else
    echo "Skipping the Selenium Grid. (Run with 'install-selenium' or 'install-testing')"
fi

# The 'devsvc' command (v89): rewritten on every run with any of the service flags.
if [ "$DEVSVC_ANY" = 1 ]; then
    cat > "$HOME/.local/bin/devsvc" << 'DEVSVC_EOF'
#!/bin/bash
# devsvc: the shared development services of dev-setup (v89): Redis, Memcached, Solr, OpenSearch,
# Elasticsearch, Meilisearch, Typesense, Qdrant, Milvus, MongoDB, MongoDB Atlas Local and (v91) a Selenium
# Grid, each in a Docker container published on 127.0.0.1 and reachable from DDEV's containers by its DDEV name
# (devredis, devsolr, devmongo...). 'devsvc status' lists the ones installed here.
# Written by dev-setup and rewritten on every run: copy it before editing.
#   devsvc status                    every installed service: state, port, RAM in use, DDEV name
#   devsvc up NAME...                start services (the memory guard first), join DDEV's network
#   devsvc down NAME... | down all   stop them; the data stays
#   devsvc info NAME                 how to connect: host, DDEV, Drupal, Laravel, Symfony, Python, Node
#   devsvc cli NAME [ARGS]           redis-cli for redis; memcached's text protocol for memcached; mongosh
#                                    for mongodb and atlas-local; for an HTTP service (the search engines,
#                                    Qdrant, Milvus, Selenium), curl with its login: devsvc cli NAME [/PATH]
#                                    [curl options], e.g. devsvc cli opensearch /_cat/indices?v
#   devsvc password NAME             the service's password or key (empty when it has none)
#   devsvc logs NAME [docker logs options]
#   devsvc ddev                      rejoin every running service to DDEV's network (DDEV recreates it
#                                    after 'ddev poweroff')
#   devsvc fits NAME                 would 'up' pass the memory guard? (exit 0 yes, 3 no)
# Settings, from the environment or ~/.config/dev-init/secrets.env:
#   DEVSVC_RAM_MB     the services' memory budget in MB (default 3000; the Linux VM sees ~6.4 GB)
#   DEVSVC_FORCE=1    start anyway when the budget says no
#   DEVSVC_WAIT       seconds 'up' waits for an answer (default 60; 300 for the heavy engines)
#   DEVSVC_AUTOSTART  which services start with Linux (default "redis memcached"): applied by dev-setup
# Passwords and keys: ~/.config/devsvc/devsvc.env (written by dev-setup).
set -o pipefail
KEYS="$HOME/.config/devsvc/devsvc.env"
SECRETS="$HOME/.config/dev-init/secrets.env"
DOCKER=(docker)
docker info > /dev/null 2>&1 || DOCKER=(sudo -n docker)   # before the docker group is active in this login
if [ -t 1 ]; then G=$'\e[32m' Y=$'\e[33m' D=$'\e[2m' B=$'\e[1m' R=$'\e[0m'; else G=; Y=; D=; B=; R=; fi

# The services: NAME|TITLE|HOST PORT|DDEV NAME|RAM ESTIMATE MB|GROUP|PORT INSIDE DOCKER'S NETWORKS|FLAG
# The estimate is what the memory guard counts: the service's own cap plus overhead. GROUP heavy = one
# at a time, with each other and with SQL Server and Oracle (install-db-server).
SERVICES='redis|Redis 8|6379|devredis|300||6379|install-redis
memcached|Memcached 1.6|11211|devmemcached|80||11211|install-memcached
solr|Solr 9.10|8983|devsolr|1024|heavy|8983|install-solr
opensearch|OpenSearch 3|9200|devopensearch|1300|heavy|9200|install-opensearch
elasticsearch|Elasticsearch 9|9201|develastic|1300|heavy|9200|install-elasticsearch
meilisearch|Meilisearch|7700|devmeili|350||7700|install-meilisearch
typesense|Typesense|8108|devtypesense|300||8108|install-typesense
qdrant|Qdrant|6333|devqdrant|300||6333|install-qdrant
milvus|Milvus|19530|devmilvus|2400|heavy|19530|install-milvus
mongodb|MongoDB 8|27017|devmongo|800||27017|install-mongodb
atlas-local|MongoDB Atlas Local|27018|devmongo-atlas|2300|heavy|27017|install-mongodb-atlas-local
selenium|Selenium Grid (Chrome)|4444|devselenium|1600|heavy|4444|install-selenium'
# Other dev-setup containers the guard counts too: CONTAINER|RAM ESTIMATE MB|COMMAND THAT STOPS IT
OTHERS='devdb-mssql|2560|mssql down
devdb-oracle|2048|oracle down'

die() { echo "devsvc: $*" >&2; exit 1; }
row() { awk -F'|' -v n="$1" '$1 == n' <<< "$SERVICES"; }
field() { row "$1" | cut -d'|' -f"$2"; }
names() { cut -d'|' -f1 <<< "$SERVICES"; }
known() { [ -n "$(row "$1")" ]; }
cname() { echo "devsvc-$1"; }
exists() { "${DOCKER[@]}" container inspect "$(cname "$1")" > /dev/null 2>&1; }
running_c() { [ "$("${DOCKER[@]}" inspect -f '{{.State.Running}}' "$1" 2> /dev/null)" = true ]; }
running() { running_c "$(cname "$1")"; }
installed() { local n; for n in $(names); do exists "$n" && echo "$n"; done; }
need() { known "$1" || die "unknown service '$1' (known: $(names | xargs))"; exists "$1" || die "no $(cname "$1") container: run dev-setup with $(field "$1" 8)"; }
# cfg NAME [DEFAULT]: the environment's value, else secrets.env's, else DEFAULT
cfg() {
    local v="${!1:-}"
    if [ -z "$v" ] && [ -r "$SECRETS" ]; then v=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$SECRETS" "$1"); fi
    printf '%s' "${v:-${2:-}}"
}
key() {   # key NAME: from devsvc.env
    [ -r "$KEYS" ] || return 0
    bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$KEYS" "$1"
}
budget() { local b; b=$(cfg DEVSVC_RAM_MB 3000); [[ "$b" =~ ^[0-9]+$ ]] || b=3000; echo "$b"; }
ddev_net() { "${DOCKER[@]}" network inspect ddev_default > /dev/null 2>&1; }
on_ddev() { "${DOCKER[@]}" inspect -f '{{json .NetworkSettings.Networks}}' "$(cname "$1")" 2> /dev/null | grep -q '"ddev_default"'; }
join_ddev() {   # join_ddev NAME: 0 = joined now or already, 1 = no DDEV network yet
    ddev_net || return 1
    on_ddev "$1" && return 0
    "${DOCKER[@]}" network connect --alias "$(field "$1" 4)" ddev_default "$(cname "$1")" > /dev/null 2>&1
}

# plan_up NAME: the memory guard. Prints "stop CONTAINER" lines for the one-at-a-time group, and
# returns 3 (with a message) when the start would pass the budget.
plan_up() {
    local n=$1 grp total=0 est line o c m s over=()
    grp=$(field "$n" 6); est=$(field "$n" 5)
    for o in $(names); do
        [ "$o" = "$n" ] && continue
        running "$o" || continue
        if [ -n "$grp" ] && [ "$(field "$o" 6)" = "$grp" ]; then echo "stop $(cname "$o")|devsvc down $o"; continue; fi
        m=$(field "$o" 5); total=$((total + m)); over+=("$m|devsvc down $o|$o")
    done
    while IFS='|' read -r c m s; do
        { [ -n "$c" ] && running_c "$c"; } || continue
        if [ "$grp" = heavy ]; then echo "stop $c|$s"; continue; fi
        total=$((total + m)); over+=("$m|$s|${c#devdb-}")
    done <<< "$OTHERS"
    if [ $((total + est)) -gt "$(budget)" ]; then
        [ "${DEVSVC_FORCE:-0}" = 1 ] && return 3
        {
            echo "devsvc: starting $n (~$est MB) next to what runs (~$total MB) passes DEVSVC_RAM_MB=$(budget)."
            echo "        Stop something first (largest first):"
            printf '%s\n' "${over[@]}" | sort -t'|' -k1,1nr | while IFS='|' read -r m s o; do echo "          $s      (~$m MB)"; done
            echo "        or start it anyway: DEVSVC_FORCE=1 devsvc up $n"
        } >&2
        return 3
    fi
    return 0
}

# The search engines' logins, as a curl config (read from a file descriptor, so the password stays off
# the command line): auth_cfg NAME
auth_cfg() {
    case "$1" in
        solr)          printf 'user = "solr:%s"\n' "$(key SOLR_PASSWORD)" ;;
        opensearch)    printf 'user = "admin:%s"\n' "$(key OPENSEARCH_ADMIN_PASSWORD)" ;;
        elasticsearch) printf 'user = "elastic:%s"\n' "$(key ELASTIC_PASSWORD)" ;;
        meilisearch)   printf 'header = "Authorization: Bearer %s"\n' "$(key MEILI_MASTER_KEY)" ;;
        typesense)     printf 'header = "X-TYPESENSE-API-KEY: %s"\n' "$(key TYPESENSE_API_KEY)" ;;
        qdrant)        [ -z "$(key QDRANT_API_KEY)" ] || printf 'header = "api-key: %s"\n' "$(key QDRANT_API_KEY)" ;;
    esac
}
http() {   # http NAME PATH [curl options]: a request to an HTTP service on 127.0.0.1, with its login
    local n=$1 path=$2; shift 2
    curl -sS --max-time "${DEVSVC_HTTP_TIMEOUT:-60}" -K <(auth_cfg "$n") -H 'Content-Type: application/json' \
        "$@" "http://127.0.0.1:$(field "$n" 3)$path"
}
code() {   # code NAME PATH: the HTTP status of an unauthenticated GET ("000" = no answer)
    curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$(field "$1" 3)$2"
}
solr_secure() {   # Solr's basic auth: security.json into ZooKeeper, once, on the first start of a volume
    local pw i
    pw=$(key SOLR_PASSWORD)
    [ -n "$pw" ] || { echo "  ${Y}No SOLR_PASSWORD in devsvc.env, so Solr stays open: rerun dev-setup with install-solr.${R}"; return 0; }
    [ "$(code solr /solr/admin/info/system)" = 401 ] && return 0
    echo "  First start of this Solr: turning on basic auth (user solr), security.json into ZooKeeper..."
    # Solr's Sha256AuthenticationProvider stores base64(sha256(sha256(salt + password))) and the salt.
    python3 - "$pw" << 'PY' | "${DOCKER[@]}" exec -i "$(cname solr)" sh -c 'cat > /tmp/security.json' || return 1
import base64, hashlib, json, os, sys
salt = os.urandom(32)
h = hashlib.sha256(hashlib.sha256(salt + sys.argv[1].encode()).digest()).digest()
print(json.dumps({
    "authentication": {"class": "solr.BasicAuthPlugin", "blockUnknown": True, "forwardCredentials": False,
                       "credentials": {"solr": base64.b64encode(h).decode() + " " + base64.b64encode(salt).decode()}},
    "authorization": {"class": "solr.RuleBasedAuthorizationPlugin", "user-role": {"solr": "admin"},
                      "permissions": [{"name": "all", "role": "admin"}]}}, indent=1))
PY
    "${DOCKER[@]}" exec "$(cname solr)" solr zk cp file:/tmp/security.json zk:/security.json -z localhost:9983 > /dev/null 2>&1
    "${DOCKER[@]}" exec "$(cname solr)" rm -f /tmp/security.json
    for ((i = 0; i < 30; i++)); do
        [ "$(code solr /solr/admin/info/system)" = 401 ] && { echo "  Solr now requires its login ('devsvc password solr')."; return 0; }
        sleep 1
    done
    echo "  ${Y}Solr still answers without a login: 'devsvc logs solr' shows why; 'devsvc down solr && devsvc up solr' retries.${R}"
    return 1
}

mongo_secure() {   # MONGO_ROOT_PASSWORD on a new data volume: create user root (allowed while there is none)
    local pw c
    pw=$(key MONGO_ROOT_PASSWORD); c=$(cname mongodb)
    [ -n "$pw" ] || return 0
    # shellcheck disable=SC2016   # $PW expands in the container's shell
    "${DOCKER[@]}" exec -e "PW=$pw" "$c" sh -c 'mongosh --quiet -u root -p "$PW" --authenticationDatabase admin --eval "db.runCommand({connectionStatus: 1}).ok"' 2> /dev/null | grep -qx 1 && return 0
    # shellcheck disable=SC2016   # JavaScript for mongosh, not shell
    if "${DOCKER[@]}" exec -e "PW=$pw" "$c" mongosh --quiet --eval 'db.getSiblingDB("admin").createUser({user: "root", pwd: process.env.PW, roles: ["root"]}); print("ok")' 2> /dev/null | grep -q ok; then
        echo "  First start with MONGO_ROOT_PASSWORD: created user root ('devsvc password mongodb')."
    else
        echo "  ${Y}MongoDB does not take MONGO_ROOT_PASSWORD for user root: rerun dev-setup with install-mongodb (it changes the password in the data).${R}"
    fi
}

ready() {   # ready NAME: does the service answer?
    local pw c
    case "$1" in
        redis) pw=$(key REDIS_PASSWORD)
               "${DOCKER[@]}" exec ${pw:+-e "REDISCLI_AUTH=$pw"} "$(cname redis)" redis-cli ping 2> /dev/null | grep -q PONG ;;
        memcached) mc_send "version" 2> /dev/null | grep -q '^VERSION' ;;
        solr) c=$(code solr /solr/admin/info/system); [ "$c" = 200 ] || [ "$c" = 401 ] ;;
        opensearch|elasticsearch) DEVSVC_HTTP_TIMEOUT=5 http "$1" /_cluster/health 2> /dev/null | grep -Eq '"status" *: *"(green|yellow)"' ;;
        meilisearch) curl -s --max-time 5 http://127.0.0.1:7700/health | grep -q available ;;
        typesense) curl -s --max-time 5 http://127.0.0.1:8108/health | grep -q '"ok" *: *true' ;;
        qdrant) curl -s --max-time 5 http://127.0.0.1:6333/healthz | grep -qi 'passed' ;;
        milvus) curl -s --max-time 5 http://127.0.0.1:9091/healthz | grep -qx 'OK' ;;
        mongodb) "${DOCKER[@]}" exec "$(cname mongodb)" mongosh --quiet --eval 'db.runCommand({ping: 1}).ok' 2> /dev/null | grep -qx 1 ;;
        atlas-local) [ "$("${DOCKER[@]}" inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$(cname atlas-local)" 2> /dev/null)" = healthy ] ;;
        selenium) curl -s --max-time 5 http://127.0.0.1:4444/status | grep -Eq '"ready" *: *true' ;;
        *) return 1 ;;
    esac
}
mc_send() {   # mc_send LINE...: send memcached text-protocol lines to 127.0.0.1:11211, print the reply
    local l
    exec 3<> /dev/tcp/127.0.0.1/11211 || return 1
    for l in "$@"; do printf '%s\r\n' "$l" >&3; done
    printf 'quit\r\n' >&3
    timeout 5 cat <&3 | tr -d '\r'
    exec 3<&-
}

info() {
    local n=$1 pw port
    port=$(field "$n" 3)
    echo "  ${B}$(field "$n" 2)${R} on 127.0.0.1:$port; from DDEV's containers: $(field "$n" 4):$(field "$n" 7)"
    case "$n" in
        redis)
            pw=$(key REDIS_PASSWORD)
            if [ -n "$pw" ]; then echo "  password: 'devsvc password redis'"; else echo "  no password (127.0.0.1 only; set REDIS_PASSWORD in secrets.env before sharing it)"; fi
            echo "  shell    devsvc cli redis          (redis-cli; 'devsvc cli redis MODULE LIST' runs one command)"
            echo "  URL      redis://${pw:+:<password>@}127.0.0.1:6379/0      from DDEV: redis://${pw:+:<password>@}devredis:6379/0"
            echo "  Drupal   (redis module, in DDEV) settings.php:  \$settings['redis.connection']['interface'] = 'PhpRedis';"
            echo "           \$settings['redis.connection']['host'] = 'devredis';  \$settings['cache']['default'] = 'cache.backend.redis';"
            echo "  Laravel  .env: REDIS_CLIENT=phpredis REDIS_HOST=127.0.0.1 (devredis in DDEV), CACHE_STORE=redis, QUEUE_CONNECTION=redis"
            echo "           (a queue wants REDIS_MAXMEMORY_POLICY=noeviction: setup's default, allkeys-lru, may evict jobs)"
            echo "  Symfony  REDIS_URL=redis://127.0.0.1:6379  (cache.adapter.redis, lock, Messenger)"
            echo "  Python   uv run --with redis python -c 'import redis; print(redis.Redis().ping())'"
            echo "  Node     npm install redis   ->   createClient({ url: 'redis://127.0.0.1:6379' })"
            echo "  GUI      Redis Insight (ChromeOS launcher): add database 127.0.0.1:6379" ;;
        memcached)
            echo "  no login (Memcached never leaves this machine)"
            echo "  shell    devsvc cli memcached      (the text protocol: stats, get KEY, set KEY 0 60 5 + a data line)"
            echo "  Drupal   (memcache module, in DDEV) settings.php:  \$settings['memcache']['servers'] = ['devmemcached:11211' => 'default'];"
            echo "           \$settings['cache']['default'] = 'cache.backend.memcache';"
            echo "  Laravel  .env: CACHE_STORE=memcached MEMCACHED_HOST=127.0.0.1 (devmemcached in DDEV)"
            echo "  Symfony  MEMCACHED_URL=memcached://127.0.0.1:11211  (cache.adapter.memcached)"
            echo "  Python   uv run --with pymemcache python -c 'from pymemcache.client.base import Client; print(Client((\"127.0.0.1\", 11211)).version())'" ;;
        solr)
            echo "  login    user solr, password: 'devsvc password solr'  (SolrCloud, one node; configsets live in ZooKeeper)"
            echo "  shell    devsvc cli solr /solr/admin/collections?action=LIST    (curl with the login)"
            echo "  admin UI http://localhost:8983/solr/"
            echo "  Drupal   search_api_solr: server connector 'Solr Cloud with Basic Auth', HTTP, host devsolr, port 8983,"
            echo "           path /, collection named for the site, user solr. Upload the configset from the server's page"
            echo "           ('Upload Configset'), then create the collection there. From the host: 127.0.0.1:8983."
            echo "  PHP      Solarium (per project): endpoint 127.0.0.1:8983, path /, username solr" ;;
        opensearch|elasticsearch)
            if [ "$n" = opensearch ]; then pw="admin:<'devsvc password opensearch'>"; else pw="elastic:<'devsvc password elasticsearch'>"; fi
            echo "  login    ${pw}   plain HTTP (no TLS), one node"
            echo "  shell    devsvc cli $n /_cat/indices?v      devsvc cli $n /idx/_doc/1 -X PUT -d '{\"a\":1}'"
            if [ "$n" = opensearch ]; then
                echo "  Drupal   search_api_opensearch: URL http://devopensearch:9200, basic auth admin; host: http://127.0.0.1:9200"
                echo "  Python   uv run --with opensearch-py: OpenSearch(\"http://127.0.0.1:9200\", http_auth=(\"admin\", pw))"
            else
                echo "  Drupal   elasticsearch_connector: URL http://develastic:9200 (inside DDEV), basic auth elastic; host: http://127.0.0.1:9201"
                echo "  Python   uv run --with elasticsearch: Elasticsearch(\"http://127.0.0.1:9201\", basic_auth=(\"elastic\", pw))"
            fi ;;
        meilisearch)
            echo "  key      master key: 'devsvc password meilisearch' (create search-only keys with /keys for front ends)"
            echo "  shell    devsvc cli meilisearch /indexes"
            echo "  preview  http://localhost:7700 (development mode: a search page for your indexes)"
            echo "  Drupal   search_api_meilisearch: host http://devmeili:7700, the master key"
            echo "  Laravel  Scout: SCOUT_DRIVER=meilisearch MEILISEARCH_HOST=http://127.0.0.1:7700 MEILISEARCH_KEY=<master key>" ;;
        typesense)
            echo "  key      API key (every request, local ones too): 'devsvc password typesense'"
            echo "  shell    devsvc cli typesense /collections"
            echo "  Drupal   search_api_typesense: host devtypesense, port 8108, protocol http, the API key"
            echo "  Laravel  Scout: SCOUT_DRIVER=typesense TYPESENSE_HOST=127.0.0.1 TYPESENSE_PORT=8108 TYPESENSE_API_KEY=<key>" ;;
        qdrant)
            if [ -n "$(key QDRANT_API_KEY)" ]; then echo "  key      header api-key: 'devsvc password qdrant'"; else echo "  no API key (127.0.0.1 only; set QDRANT_API_KEY in secrets.env before sharing it)"; fi
            echo "  REST     http://127.0.0.1:6333    gRPC 127.0.0.1:6334    dashboard http://localhost:6333/dashboard"
            echo "  shell    devsvc cli qdrant /collections"
            echo "  Python   uv run --with qdrant-client: QdrantClient(url=\"http://127.0.0.1:6333\")"
            echo "  Node     npm install @qdrant/js-client-rest -> new QdrantClient({ url: 'http://127.0.0.1:6333' })"
            echo "  Drupal   ai_vdb_provider_qdrant (the AI module's vector DB provider): host devqdrant, port 6333" ;;
        milvus)
            echo "  no login locally    gRPC and REST on 127.0.0.1:19530, WebUI http://localhost:9091/webui"
            echo "  shell    devsvc cli milvus /v2/vectordb/collections/list -X POST -d '{}'"
            echo "  Python   uv run --with pymilvus: MilvusClient(\"http://127.0.0.1:19530\")   (MilvusClient(\"demo.db\") is Milvus Lite: no server)"
            echo "  Drupal   ai_vdb_provider_milvus: host http://devmilvus, port 19530"
            echo "  memory   Milvus asks for 8 GB; here it runs alone ('devsvc down milvus' when done)" ;;
        mongodb)
            if [ -n "$(key MONGO_ROOT_PASSWORD)" ]; then
                echo "  login    user root, 'devsvc password mongodb'   URL mongodb://root:<password>@127.0.0.1:27017/?authSource=admin"
            else
                echo "  no login (127.0.0.1 only; set MONGO_ROOT_PASSWORD in secrets.env before sharing it)   URL mongodb://127.0.0.1:27017"
            fi
            echo "  shell    devsvc cli mongodb   (mongosh)     tools: mongodump, mongorestore, mongoimport, mongoexport"
            echo "  GUI      MongoDB Compass (ChromeOS launcher) with the URL above"
            echo "  DDEV     mongodb://devmongo:27017"
            echo "  Laravel  mongodb/laravel-mongodb: DB_CONNECTION=mongodb MONGODB_URI=mongodb://127.0.0.1:27017 MONGODB_DATABASE=app"
            echo "  Symfony  doctrine/mongodb-odm-bundle: MONGODB_URL=mongodb://127.0.0.1:27017 MONGODB_DB=app"
            echo "  Python   uv run --with pymongo: MongoClient(\"mongodb://127.0.0.1:27017\")" ;;
        atlas-local)
            echo "  no login locally    URL mongodb://127.0.0.1:27018/?directConnection=true   (a one-node replica set)"
            echo "  shell    devsvc cli atlas-local   (mongosh)"
            echo "  search   Atlas Search and Vector Search indexes: db.coll.createSearchIndex(...), \$search / \$vectorSearch"
            echo "  DDEV     mongodb://devmongo-atlas:27017/?directConnection=true"
            echo "  Atlas    'atlas' is the Atlas CLI for cloud accounts; this container runs without one" ;;
        selenium)
            echo "  no login (127.0.0.1 only, never shared)   WebDriver http://127.0.0.1:4444   one session at a time"
            echo "  watch    http://localhost:7900/?autoconnect=1&resize=scale   (noVNC: the Grid's screen, no password)"
            echo "  Grid UI  http://localhost:4444/ui        shell: devsvc cli selenium   (the /status JSON)"
            echo "  reach    the browser sees this machine as host.docker.internal: serve on 0.0.0.0 (or 172.17.0.1),"
            echo "           e.g. php -S 0.0.0.0:8000, python3 -m http.server --bind 0.0.0.0, vite --host"
            echo "  DDEV     inside DDEV: http://devselenium:4444. For *.ddev.site pages add the Chrome argument"
            echo "           --host-resolver-rules=\"MAP *.ddev.site ddev-router\" (otherwise they resolve to the Grid itself);"
            echo "           for Drupal's own tests the ddev/ddev-selenium-standalone-chrome add-on is simpler"
            echo "  Python   uv run --with selenium: webdriver.Remote(\"http://127.0.0.1:4444\", options=webdriver.ChromeOptions())"
            echo "  Node     npm install selenium-webdriver -> new Builder().forBrowser('chrome').usingServer('http://127.0.0.1:4444').build()"
            echo "  Robot    SeleniumLibrary: Open Browser  URL  chrome  remote_url=http://127.0.0.1:4444"
            echo "  Behat    Mink's Selenium2/WebDriver driver: wd_host http://127.0.0.1:4444/wd/hub (Grid 4 takes both paths)"
            echo "  local    without the Grid, Selenium Manager drives this machine's Chrome directly (no container)" ;;
    esac
}

up() {
    local n c line wait i rc avail
    [ $# -gt 0 ] || die "usage: devsvc up NAME...   (installed: $(installed | xargs))"
    for n in "$@"; do
        need "$n"; c=$(cname "$n")
        if running "$n"; then
            join_ddev "$n"
            echo "$(field "$n" 2) is running."; info "$n"; continue
        fi
        line=$(plan_up "$n"); rc=$?
        # 3 = over budget; anything else non-zero (the guard itself failed, e.g. its output pipe closed)
        # never counts as a go-ahead.
        if [ "$rc" != 0 ] && { [ "$rc" != 3 ] || [ "${DEVSVC_FORCE:-0}" != 1 ]; }; then exit "$rc"; fi
        [ "$rc" = 3 ] && echo "${Y}DEVSVC_FORCE=1: starting $n past the memory budget.${R}"
        while IFS='|' read -r what how; do
            [ -n "$what" ] || continue
            echo "Stopping ${what#stop } first: one heavy engine (Java search, Milvus, Atlas Local, Selenium Grid) or database server at a time (later: ${how/down/up})."
            "${DOCKER[@]}" stop -t 60 "${what#stop }" > /dev/null
        done <<< "$line"
        # The budget counts devsvc's own caps; Ollama models and Chrome tabs use the same memory, so say so
        # when little is free (as devdb does).
        avail=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)
        if [ "${avail:-0}" -lt 2600 ]; then
            echo "Note: $avail MB available. 'ollama ps' then 'ollama stop <model>', and closing Chrome tabs, give Linux memory back."
        fi
        "${DOCKER[@]}" start "$c" > /dev/null || exit 1
        wait=${DEVSVC_WAIT:-60}; [ "$(field "$n" 6)" = heavy ] && wait=${DEVSVC_WAIT:-300}
        [ "$n" = milvus ] && echo "${Y}Milvus asks for 8 GB of RAM and this Linux has ~6.4 GB: expect a slow start, and stop it when done.${R}"
        printf 'Starting %s' "$(field "$n" 2)"
        for ((i = 0; i < wait; i++)); do
            if ready "$n"; then
                echo "... ready after ${i}s"
                [ "$n" = solr ] && solr_secure
                [ "$n" = mongodb ] && mongo_secure
                join_ddev "$n" || echo "  ${D}(DDEV's network does not exist yet; 'devsvc ddev' joins it once a DDEV project has run)${R}"
                info "$n"; continue 2
            fi
            running "$n" || break
            sleep 1
            [ $((i % 15)) -eq 14 ] && printf '.'
        done
        if running "$n"; then echo; echo "$c did not answer within ${wait}s (DEVSVC_WAIT raises the limit). Its last log lines:"
        else echo; echo "$c stopped while starting. Its last log lines:"; fi
        "${DOCKER[@]}" logs --tail 20 "$c" 2>&1
        exit 1
    done
}
down() {
    local n list=()
    [ $# -gt 0 ] || die "usage: devsvc down NAME... | down all"
    if [ "$1" = all ]; then mapfile -t list < <(installed); else list=("$@"); fi
    for n in "${list[@]}"; do
        need "$n"
        if running "$n"; then
            "${DOCKER[@]}" stop -t 30 "$(cname "$n")" > /dev/null && echo "$(cname "$n") stopped$(case "$n" in memcached|selenium) ;; *) echo " (its data stays in devsvc-$n-data)" ;; esac)."
        else
            echo "$(cname "$n") is not running."
        fi
    done
}
status() {
    local n c st ram est tot=0 dd auto stats policy p
    [ -n "$(installed)" ] || { echo "No shared services yet: dev-setup with install-cache (Redis, Memcached) or install-search."; return 1; }
    stats=$("${DOCKER[@]}" stats --no-stream --format '{{.Name}} {{.MemUsage}}' 2> /dev/null | awk '$1 ~ /^devsvc-/ {print $1, $2}')
    printf '%s%-13s %-9s %-16s %-11s %-14s %s%s\n' "$B" SERVICE STATE PORT RAM DDEV START "$R"
    for n in $(installed); do
        c=$(cname "$n"); est=$(field "$n" 5)
        policy=$("${DOCKER[@]}" inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c" 2> /dev/null)
        [ "$policy" = unless-stopped ] && auto="with Linux" || auto="devsvc up"
        if running "$n"; then
            printf -v p '%-9s' running; st="$G$p$R"; ram=$(awk -v c="$c" '$1 == c {print $2}' <<< "$stats"); tot=$((tot + est))
            if ! ddev_net; then printf -v p '%-14s' "no DDEV yet"; dd="$D$p$R"
            elif on_ddev "$n"; then printf -v p '%-14s' "$(field "$n" 4)"; dd=$p
            else printf -v p '%-14s' "devsvc ddev"; dd="$Y$p$R"; fi
        else
            printf -v p '%-9s' stopped; st="$D$p$R"; ram="-"; printf -v p '%-14s' "$(field "$n" 4)"; dd="$D$p$R"
        fi
        printf '%-13s %s %-16s %-11s %s %s\n' "$n" "$st" "127.0.0.1:$(field "$n" 3)" "${ram:--}" "$dd" "$auto"
    done
    echo "${D}Running services' estimates: ~$tot MB of DEVSVC_RAM_MB=$(budget). 'devsvc info NAME' shows how to connect.${R}"
}
cli() {
    local n=${1:-} pw line
    [ -n "$n" ] || die "usage: devsvc cli NAME [ARGS]"
    shift; need "$n"
    running "$n" || die "$n is not running: 'devsvc up $n' first"
    case "$n" in
        redis)
            pw=$(key REDIS_PASSWORD)
            # REDISCLI_AUTH only when there is a password: set but empty, redis-cli still sends AUTH.
            if command -v redis-cli > /dev/null 2>&1; then
                [ -n "$pw" ] && export REDISCLI_AUTH="$pw"
                exec redis-cli -h 127.0.0.1 -p 6379 "$@"
            fi
            if [ -t 0 ]; then exec "${DOCKER[@]}" exec -it ${pw:+-e "REDISCLI_AUTH=$pw"} "$(cname redis)" redis-cli "$@"; fi
            exec "${DOCKER[@]}" exec -i ${pw:+-e "REDISCLI_AUTH=$pw"} "$(cname redis)" redis-cli "$@" ;;
        memcached)
            if [ $# -gt 0 ]; then mc_send "$*"; exit; fi
            echo "Memcached's text protocol; one command per line (stats, get k, delete k, flush_all). 'set k 0 60 5' asks for"
            echo "the data line next. Ctrl-D or 'quit' ends."
            while read -rep 'memcached> ' line; do
                [ "$line" = quit ] && break
                [ -n "$line" ] || continue
                case "$line" in
                    set\ *|add\ *|replace\ *|append\ *|prepend\ *) read -rep '     data> ' data; mc_send "$line" "$data" ;;
                    *) mc_send "$line" ;;
                esac
            done ;;
        mongodb|atlas-local)
            local url=mongodb://127.0.0.1:27017 auth=()
            [ "$n" = atlas-local ] && url="mongodb://127.0.0.1:27018/?directConnection=true"
            pw=""; [ "$n" = mongodb ] && pw=$(key MONGO_ROOT_PASSWORD)
            if [ -n "$pw" ]; then auth=(-u root -p "$pw" --authenticationDatabase admin); fi
            if command -v mongosh > /dev/null 2>&1; then exec mongosh "$url" "${auth[@]}" "$@"; fi
            url=${url/27018/27017}   # inside the container every mongod listens on 27017
            if [ -t 0 ]; then exec "${DOCKER[@]}" exec -it "$(cname "$n")" mongosh "$url" "${auth[@]}" "$@"; fi
            exec "${DOCKER[@]}" exec -i "$(cname "$n")" mongosh "$url" "${auth[@]}" "$@" ;;
        *)
            local path
            case "${1:-}" in
                /*) path=$1; shift ;;
                *) case "$n" in
                       solr) path=/solr/admin/info/system ;; meilisearch) path=/version ;; typesense) path=/debug ;;
                       qdrant) path=/collections ;; milvus) path=/v2/vectordb/collections/list; set -- -X POST -d '{}' "$@" ;;
                       selenium) path=/status ;; *) path=/ ;;
                   esac ;;
            esac
            http "$n" "$path" "$@"; echo ;;
    esac
}
password() {
    local n=${1:-}
    [ -n "$n" ] || die "usage: devsvc password NAME"
    known "$n" || die "unknown service '$n'"
    case "$n" in
        redis) key REDIS_PASSWORD; echo
               [ -n "$(key REDIS_PASSWORD)" ] || echo "(none: Redis has no password here; REDIS_PASSWORD in secrets.env and a setup run add one)" >&2 ;;
        memcached) echo; echo "(none: Memcached has no login)" >&2 ;;
        solr) key SOLR_PASSWORD; echo; echo "(user solr)" >&2 ;;
        opensearch) key OPENSEARCH_ADMIN_PASSWORD; echo; echo "(user admin)" >&2 ;;
        elasticsearch) key ELASTIC_PASSWORD; echo; echo "(user elastic)" >&2 ;;
        meilisearch) key MEILI_MASTER_KEY; echo; echo "(the master key)" >&2 ;;
        typesense) key TYPESENSE_API_KEY; echo; echo "(the API key)" >&2 ;;
        qdrant) key QDRANT_API_KEY; echo
                [ -n "$(key QDRANT_API_KEY)" ] || echo "(none: Qdrant has no API key here; QDRANT_API_KEY in secrets.env and a setup run add one)" >&2 ;;
        mongodb) key MONGO_ROOT_PASSWORD; echo
                 if [ -n "$(key MONGO_ROOT_PASSWORD)" ]; then echo "(user root)" >&2; else echo "(none: MongoDB has no login here; MONGO_ROOT_PASSWORD in secrets.env and a setup run add one)" >&2; fi ;;
        milvus|atlas-local|selenium) echo; echo "(none: no login locally)" >&2 ;;
    esac
}
ddev() {
    local n any=0
    ddev_net || { echo "DDEV's network (ddev_default) does not exist yet: start a DDEV project, then 'devsvc ddev'."; return 0; }
    for n in $(installed); do
        running "$n" || continue
        any=1
        if on_ddev "$n"; then echo "$n: on DDEV's network as $(field "$n" 4)"
        elif join_ddev "$n"; then echo "$n: joined DDEV's network as $(field "$n" 4)"
        else echo "$n: could not join DDEV's network"; fi
    done
    [ "$any" = 1 ] || echo "No service is running: 'devsvc up NAME' joins it on start."
}

cmd=${1:-status}; [ $# -gt 0 ] && shift
case "$cmd" in
    status|ls) status ;;
    up|start) up "$@" ;;
    down|stop) down "$@" ;;
    info) [ -n "${1:-}" ] || die "usage: devsvc info NAME"; known "$1" || die "unknown service '$1'"; info "$1" ;;
    cli) cli "$@" ;;
    password) password "$@" ;;
    logs) [ -n "${1:-}" ] || die "usage: devsvc logs NAME"; n=$1; shift; need "$n"; exec "${DOCKER[@]}" logs --tail 100 "$@" "$(cname "$n")" ;;
    ddev) ddev ;;
    fits) [ -n "${1:-}" ] || die "usage: devsvc fits NAME"; known "$1" || die "unknown service '$1'"; plan_up "$1" > /dev/null ;;
    help|-h|--help) sed -n '2,/^set -o pipefail$/{/^set -o/d;s/^# \{0,1\}//;p}' "$0" ;;
    *) die "unknown command '$cmd' ('devsvc help')" ;;
esac
DEVSVC_EOF
    chmod +x "$HOME/.local/bin/devsvc"
    echo "Command in ~/.local/bin:  devsvc status | up | down | info | cli | password | logs | ddev"
    "$HOME/.local/bin/devsvc" status 2> /dev/null || true
fi

# =================================================================
# install-testing : test tools (added in v91). In install-all = install-playwright install-selenium install-bdd
# install-robot; install-cypress is opt-in (in no group, not in install-all). What is machine-level here is
# browsers, drivers, system libraries and CLIs; the test libraries themselves (@playwright/test, cucumber-js,
# playwright-bdd, selenium-webdriver, Behat, behave, pytest-playwright, Reqnroll's NuGet packages, cucumber-jvm,
# Cypress) are per project, as everywhere in this bundle. Gherkin (Given/When/Then .feature files) is the
# language the BDD runners share, not something to install.
#   install-playwright  Playwright's own Chromium, Firefox and WebKit in ~/.cache/ms-playwright, with their
#                       system libraries (playwright install --with-deps: Debian 13 is a supported platform),
#                       from the newest Playwright; a project pinned to another release fetches its own with
#                       'npx playwright install'. channel: 'chrome' runs tests on the system Chrome instead.
#                       Playwright MCP (@playwright/mcp) is warmed in npx's cache so 'claude mcp add' starts fast.
#                       No global @playwright/test: it belongs in each project's package.json.
#   install-selenium    the Selenium Grid (devsvc service 'selenium', above) and Selenium Manager's cache:
#                       Selenium 4's bindings find and download the chromedriver matching the installed Chrome
#                       themselves (~/.cache/selenium); setup runs it once so the first test works offline.
#                       No chromedriver on PATH: Chrome's apt updates would leave a fixed copy behind.
#   install-bdd         Reqnroll (SpecFlow's successor; SpecFlow ended on 31 Dec 2024) project templates for
#                       'dotnet new' when the .NET SDK is here. Cucumber (JS, JVM, Ruby), Behat (PHP: 4.x for
#                       Symfony 8 apps, 3.x for Drupal's Drupal Extension) and behave (Python) are per project.
#   install-robot       Robot Framework as a uv tool (robot, rebot, libdoc, rfbrowser in ~/.local/bin) with the
#                       Browser (Playwright-based), SeleniumLibrary and RequestsLibrary libraries, on Debian's
#                       Python. 'rfbrowser init --skip-browsers' installs the Browser library's Node side only:
#                       tests use the system Chrome (New Browser  chromium  channel=chrome) or the Playwright
#                       browsers above. npm 12 skips that Node side's one install script (protobufjs's version
#                       check), which the library does not need.
#   install-cypress     Cypress's system libraries (Debian 13's t64 names, Xvfb) and a marked ~/.bashrc block
#                       (dev-setup cypress): no crash reports, no Cloud upsell in run logs. No Cypress binary:
#                       each project's 'npm install cypress' fetches the Electron build for its version into
#                       ~/.cache/Cypress. npm 12 blocks its postinstall: projects add "allowScripts":
#                       {"cypress": true} to package.json (or run 'npx cypress install' once).
# A marked ~/.bashrc block (dev-setup selenium) turns off Selenium Manager's anonymous usage statistics.
# =================================================================
TESTING_ANY=0
for T_F in playwright selenium bdd robot cypress; do
    [[ "$FLAGS" == *" install-$T_F "* ]] && TESTING_ANY=1
done
if [ "$TESTING_ANY" = 1 ]; then
    echo "================================================================="
    echo "Installing test tools (Playwright, Selenium, Gherkin runners, Robot Framework, Cypress)..."
    echo "================================================================="
fi

# Playwright (install-playwright, part of install-testing)
if [[ "$FLAGS" =~ " install-playwright " ]]; then
    echo "--- Playwright browsers (install-playwright)"
    # --with-deps installs the browsers' system libraries through sudo apt-get (Playwright's own list for
    # Debian 13). Chromium also brings chromium-headless-shell, the slim build headless runs use.
    if npx -y playwright@latest install --with-deps chromium firefox webkit; then
        echo "Playwright $(npx -y playwright@latest --version 2> /dev/null | awk '{print $2}'): $(find "$HOME/.cache/ms-playwright" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2> /dev/null)"
    else
        echo "NOTICE: 'playwright install --with-deps' failed (cdn.playwright.dev or apt unreachable?); rerun setup with install-playwright."
        echo "        Tests can still use the system Chrome: use: { channel: 'chrome' } in playwright.config."
    fi
    # Old browser builds from earlier Playwright releases stay until 'npx playwright uninstall' (no --all:
    # that would also remove the builds other projects pinned). The disk report in dev-test lists them.
    if npx -y @playwright/mcp@latest --help > /dev/null 2>&1; then
        echo "Playwright MCP is in npx's cache: 'claude mcp add playwright -- npx @playwright/mcp@latest' (it drives the system Chrome)."
    else
        echo "NOTICE: could not fetch @playwright/mcp (npm registry unreachable?); npx fetches it on first use."
    fi
else
    echo "Skipping Playwright. (Run with 'install-playwright' or 'install-testing')"
fi

# Selenium Manager (install-selenium, part of install-testing); the Grid itself is the devsvc service above.
if [[ "$FLAGS" =~ " install-selenium " ]]; then
    echo "--- Selenium Manager (install-selenium)"
    sed -i '/^# >>> dev-setup selenium >>>$/,/^# <<< dev-setup selenium <<<$/d' ~/.bashrc
    cat >> ~/.bashrc << 'EOF'
# >>> dev-setup selenium >>>
# Written by dev-setup (install-selenium); replaced on each run. Selenium Manager (inside every Selenium 4
# binding) sends no anonymous usage statistics.
export SE_AVOID_STATS=true
# <<< dev-setup selenium <<<
EOF
    export SE_AVOID_STATS=true
    # The newest Selenium's Selenium Manager fetches the chromedriver for the installed Chrome into
    # ~/.cache/selenium (a project on an older binding reuses it when the Chrome version matches).
    if SM_OUT=$(uv run --no-project --quiet --python /usr/bin/python3 --with selenium python3 - 2>&1 << 'PY'
from selenium.webdriver.common.selenium_manager import SeleniumManager
p = SeleniumManager().binary_paths(["--browser", "chrome", "--browser-path", "/usr/bin/google-chrome-stable",
                                    "--avoid-browser-download"])
print(p["driver_path"])
PY
    ); then
        echo "Selenium Manager: chromedriver for Chrome $(google-chrome-stable --version 2> /dev/null | awk '{print $NF}') at $(echo "$SM_OUT" | tail -n 1)"
    else
        echo "NOTICE: Selenium Manager could not fetch chromedriver (googlechromelabs.github.io unreachable?):"
        echo "$SM_OUT" | tail -n 3 | sed 's/^/        /'
        echo "        The first Selenium test fetches it instead; or rerun setup with install-selenium."
    fi
else
    echo "Skipping Selenium Manager. (Run with 'install-selenium' or 'install-testing')"
fi

# Gherkin runners (install-bdd, part of install-testing)
if [[ "$FLAGS" =~ " install-bdd " ]]; then
    echo "--- Gherkin / BDD runners (install-bdd)"
    if command -v dotnet > /dev/null 2>&1; then
        if dotnet new list reqnroll-project > /dev/null 2>&1; then
            dotnet new update > /dev/null 2>&1 || echo "NOTICE: 'dotnet new update' failed (nuget.org unreachable?); the installed Reqnroll templates stay."
        elif ! dotnet new install Reqnroll.Templates.DotNet > /dev/null 2>&1; then
            echo "NOTICE: 'dotnet new install Reqnroll.Templates.DotNet' failed (nuget.org unreachable?); rerun setup with install-bdd."
        fi
        dotnet new list reqnroll-project > /dev/null 2>&1 && echo "Reqnroll: 'dotnet new reqnroll-project -t nunit' (or mstest, xunit, tunit); 'dotnet new reqnroll-feature -n Name'."
    else
        echo "No .NET SDK (install-dotnet), so no Reqnroll templates."
    fi
    echo "Per project, nothing to install here: cucumber-js or playwright-bdd (npm), Behat (Composer: behat/behat ^4 for"
    echo "Symfony 8, ^3 with drupal/drupal-extension), behave (uv add behave), cucumber-jvm (Maven), cucumber (gem)."
    echo "Editors: the official Cucumber extension (CucumberOpen.cucumber-official, on Open VSX too) knows .feature files."
else
    echo "Skipping the Gherkin runners. (Run with 'install-bdd' or 'install-testing')"
fi

# Robot Framework (install-robot, part of install-testing)
if [[ "$FLAGS" =~ " install-robot " ]]; then
    echo "--- Robot Framework (install-robot)"
    # On Debian's Python (as the bundle's venvs are), so a Homebrew Python on PATH never becomes its home.
    # --with-executables-from puts rfbrowser on PATH next to robot, rebot and libdoc.
    if uv tool install --force --quiet --python /usr/bin/python3 robotframework \
        --with robotframework-browser --with robotframework-seleniumlibrary --with robotframework-requests \
        --with-executables-from robotframework-browser; then
        # The Browser library's Node side (a gRPC wrapper around Playwright) goes into its own package
        # directory; it is rebuilt for each new robotframework-browser, so this runs every time.
        if "$HOME/.local/bin/rfbrowser" init --skip-browsers > /dev/null 2>&1; then
            echo "Robot Framework: $("$HOME/.local/bin/robot" --version 2>&1 | head -n 1)"
            echo "Browser library: New Browser  chromium  headless=True  channel=chrome   (the system Chrome)"
        else
            echo "NOTICE: 'rfbrowser init --skip-browsers' failed (npm registry unreachable?): the Browser library will not load"
            echo "        until it runs; rerun setup with install-robot. SeleniumLibrary and RequestsLibrary work already."
        fi
    else
        echo "NOTICE: 'uv tool install robotframework' failed (is PyPI reachable?); rerun setup with install-robot."
    fi
else
    echo "Skipping Robot Framework. (Run with 'install-robot' or 'install-testing')"
fi

# Cypress's system libraries (install-cypress: opt-in, in no group, not in install-all)
if [[ "$FLAGS" =~ " install-cypress " ]]; then
    echo "--- Cypress system libraries (install-cypress)"
    # Cypress's own list for Debian 13 (the t64 package names). Xvfb is what headless 'cypress run' draws into.
    sudo apt install -y libgtk-3-0t64 libgbm-dev libnotify-dev libnss3 libxss1 libasound2t64 libxtst6 xauth xvfb
    sed -i '/^# >>> dev-setup cypress >>>$/,/^# <<< dev-setup cypress <<<$/d' ~/.bashrc
    cat >> ~/.bashrc << 'EOF'
# >>> dev-setup cypress >>>
# Written by dev-setup (install-cypress); replaced on each run. Cypress sends no crash reports and its run
# logs carry no Cypress Cloud recommendations. The binary cache stays in ~/.cache/Cypress (one Electron
# build per Cypress version: 'npx cypress cache prune' keeps only the current one).
export CYPRESS_CRASH_REPORTS=0
export CYPRESS_COMMERCIAL_RECOMMENDATIONS=0
# If Cypress's Electron browser draws a blank window on this GPU, uncomment:
# export ELECTRON_EXTRA_LAUNCH_ARGS=--disable-gpu
# <<< dev-setup cypress <<<
EOF
    echo "Cypress: 'npm install -D cypress' per project (allow its install script: \"allowScripts\": {\"cypress\": true} in"
    echo "package.json for npm 12), then 'npx cypress open' or 'npx cypress run --browser chrome'."
else
    echo "Skipping Cypress's system libraries. (Run with 'install-cypress'; opt-in, not part of install-all)"
fi

# =================================================================
# install-gitlab / install-gitlab-runner / install-vue (added in v91)
#   install-gitlab         glab, GitLab's CLI (Homebrew, like gh: Debian 13's own glab is years behind), with
#                          bash completion; gitlab-ci-local (a global npm package) runs a project's .gitlab-ci.yml
#                          here, jobs with an image in Docker and the rest in the shell, so a pipeline can be
#                          tried before it is pushed. It needs rsync and git. In install-all; pulls in install-node.
#                          No login here: GITLAB_TOKEN_ONCE in secrets.env (dev-init) logs glab in, and a second host,
#                          git.drupalcode.org (drupal.org's GitLab), can be added the same way.
#   install-gitlab-runner  GitLab Runner from GitLab's apt repository (Debian 13 is supported), as the
#                          gitlab-runner service, with the gitlab-runner user in the docker group so the Docker
#                          executor works. Left unregistered: GITLAB_RUNNER_TOKEN_ONCE (a glrt- token from a project's
#                          Settings > CI/CD > Runners) and dev-init register it. Opt-in, in no group.
#                          The repository is added with its own keyring here; when apt refuses that source (a
#                          signing-key change), GitLab's own script.deb.sh is downloaded to assets/downloads and
#                          run instead.
#   install-vue            create-vue and create-nuxt warmed in npx's cache, and Nuxt's minimal template in
#                          giget's cache (~/.cache/giget), so 'npm create vue@latest' and
#                          'npm create nuxt@latest -- --preferOffline' start without the network. Nothing global:
#                          Vue, Pinia, Vue Router, Vitest and Nuxt belong in each project. In install-all; pulls in
#                          install-node.
# Not here: GitLab itself. GitLab documents 8 GB of RAM as its floor and this Linux sees ~6.4 GB; use gitlab.com
# or git.drupalcode.org.
# =================================================================
if [[ "$FLAGS" =~ " install-gitlab " ]]; then
    echo "================================================================="
    echo "Installing GitLab tooling (glab, gitlab-ci-local)..."
    echo "================================================================="
    # 'brew install' also upgrades an outdated glab.
    if brew install glab; then
        mkdir -p ~/.local/share/bash-completion/completions
        GLAB_BIN=$(brew --prefix)/bin/glab
        timeout 60 "$GLAB_BIN" completion -s bash < /dev/null > ~/.local/share/bash-completion/completions/glab 2> /dev/null \
            || rm -f ~/.local/share/bash-completion/completions/glab
        echo "glab: $("$GLAB_BIN" version 2> /dev/null | head -n 1)"
    else
        echo "NOTICE: 'brew install glab' failed; rerun setup with install-gitlab."
    fi
    sudo apt install -y rsync git
    if npm install -g gitlab-ci-local@latest; then
        echo "gitlab-ci-local: $(gitlab-ci-local --version 2> /dev/null)"
    else
        echo "NOTICE: 'npm install -g gitlab-ci-local' failed (npm registry unreachable?); rerun setup with install-gitlab."
    fi
    echo "Try: gitlab-ci-local --list (in a project with a .gitlab-ci.yml); glab auth status once dev-init has run."
else
    echo "Skipping GitLab tooling. (Run with 'install-gitlab' flag to enable)"
fi

if [[ "$FLAGS" =~ " install-gitlab-runner " ]]; then
    echo "--- GitLab Runner (install-gitlab-runner)"
    GLR_CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-trixie}")
    GLR_KEYRING=/usr/share/keyrings/runner_gitlab-runner-archive-keyring.gpg
    GLR_LIST=/etc/apt/sources.list.d/runner_gitlab-runner.list
    # glr_apt_update: refresh only GitLab's source; 1 when apt refuses it (no key, a bad signature).
    glr_apt_update() {
        sudo apt-get update -o Dir::Etc::sourcelist="$GLR_LIST" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 2>&1 \
            | tee /dev/stderr | grep -qE '^(E:|W: GPG error|Err:)' && return 1
        return 0
    }
    if [ ! -f "$GLR_LIST" ] || ! glr_apt_update > /dev/null 2>&1; then
        if curl -fsSL https://packages.gitlab.com/runner/gitlab-runner/gpgkey | sudo gpg --dearmor --yes -o "$GLR_KEYRING"; then
            echo "deb [signed-by=$GLR_KEYRING] https://packages.gitlab.com/runner/gitlab-runner/debian/ $GLR_CODENAME main" | sudo tee "$GLR_LIST" > /dev/null
        fi
        if ! glr_apt_update; then
            echo "NOTICE: apt refused GitLab's runner repository with the key above; running GitLab's own script.deb.sh instead."
            if curl -fsSL https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh -o "$ASSETS/downloads/gitlab-runner-script.deb.sh"; then
                sudo env os=debian dist="$GLR_CODENAME" bash "$ASSETS/downloads/gitlab-runner-script.deb.sh" || true
            fi
        fi
    fi
    if sudo apt install -y gitlab-runner; then
        # The Docker executor runs jobs in containers: the service's user needs the docker group.
        getent group docker > /dev/null && sudo usermod -aG docker gitlab-runner
        sudo systemctl restart gitlab-runner > /dev/null 2>&1 || true
        echo "gitlab-runner: $(gitlab-runner --version 2> /dev/null | sed -n 's/^Version: *//p')"
        if sudo test -s /etc/gitlab-runner/config.toml && sudo grep -q '^\[\[runners\]\]' /etc/gitlab-runner/config.toml; then
            echo "Registered runners: $(sudo grep -c '^\[\[runners\]\]' /etc/gitlab-runner/config.toml) ('sudo gitlab-runner list')."
        else
            echo "Not registered yet: put GITLAB_RUNNER_TOKEN_ONCE in secrets.env and run dev-init with install-gitlab-runner."
        fi
    else
        echo "NOTICE: 'apt install gitlab-runner' failed; rerun setup with install-gitlab-runner."
    fi
else
    echo "Skipping GitLab Runner. (Run with 'install-gitlab-runner'; opt-in, not part of install-all)"
fi

if [[ "$FLAGS" =~ " install-vue " ]]; then
    echo "================================================================="
    echo "Preparing Vue.js scaffolding (create-vue, create-nuxt)..."
    echo "================================================================="
    VUE_WARM=$(mktemp -d)
    if npx -y create-vue@latest --help > /dev/null 2>&1; then
        echo "create-vue is in npx's cache: npm create vue@latest my-app (TypeScript, Router, Pinia, Vitest, Playwright...)"
    else
        echo "NOTICE: could not fetch create-vue (npm registry unreachable?); 'npm create vue@latest' fetches it on first use."
    fi
    # A throwaway scaffold also puts Nuxt's minimal template in giget's cache.
    if ( cd "$VUE_WARM" && npx -y create-nuxt@latest warm --template minimal --packageManager npm --gitInit=false --no-install > /dev/null 2>&1 ); then
        echo "create-nuxt and its minimal template are cached: npm create nuxt@latest my-site -- --preferOffline"
    else
        echo "NOTICE: could not fetch create-nuxt or its template; 'npm create nuxt@latest' fetches them on first use."
    fi
    rm -rf "$VUE_WARM"
    echo "Editors: the Vue - Official extension (Vue.volar, on Open VSX too) gives .vue files types and completion."
else
    echo "Skipping Vue.js scaffolding. (Run with 'install-vue' flag to enable)"
fi

# =================================================================
# install-puppet / install-chef / install-config-mgmt (added in v91): Puppet and Chef as their community
# builds. Perforce stopped publishing free Puppet binaries in 2025 (Puppet Core needs an account) and Progress
# made Chef Workstation downloads license-gated (Chef Infra Client 19 wants a license key), so the bundle
# installs the free rebuilds, which keep the commands existing code expects:
#   install-puppet       OpenVox, Vox Pupuli's fork of Puppet: openvox-agent (puppet, facter; in /opt/puppetlabs,
#                        bin/ added to the END of PATH by a marked ~/.bashrc block) and OpenBolt (bolt), from
#                        apt.voxpupuli.org's release package for this Debian. OpenVox 8 (stable); OPENVOX_MAJOR=9
#                        picks the next line. Masterless: the agent service is disabled, 'puppet apply' and Bolt
#                        need no server. No PDK (Perforce gates it): puppet-lint, rspec-puppet and puppet-strings
#                        go in each module's Gemfile. OpenVox cannot sit next to Perforce's or Debian's
#                        puppet-agent: an existing one is left alone with a NOTICE.
#   install-chef         Cinc Workstation (cinc-client, knife, Test Kitchen with kitchen-dokken, Cookstyle,
#                        ChefSpec, Berkshelf, cinc-auditor = InSpec) in /opt/cinc-workstation, its bin/ added to
#                        the END of PATH (Cinc also installs the upstream names, chef-client and the rest, as
#                        wrappers). The .deb comes from Cinc's omnitruck metadata (URL and SHA-256 for this Debian)
#                        and is checked before it is installed; the same version already installed is left
#                        alone. CINC_WORKSTATION_MAJOR (default 26) pins the major line. No license key.
#   install-config-mgmt  = install-puppet + install-chef. Opt-in, in no group.
# Not here: an OpenVox or Cinc server (Java / Erlang services wanting 2-4 GB; development runs masterless).
# =================================================================
if [[ "$FLAGS" =~ " install-puppet " ]]; then
    echo "================================================================="
    echo "Installing OpenVox (Puppet) and OpenBolt..."
    echo "================================================================="
    OVX_MAJOR="${OPENVOX_MAJOR:-8}"
    [[ "$OVX_MAJOR" =~ ^[0-9]+$ ]] || OVX_MAJOR=8
    OVX_DIST="debian$(. /etc/os-release && echo "${VERSION_ID%%.*}")"
    OVX_OTHER=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' puppet-agent puppet 2> /dev/null | awk '$1 ~ /^ii/ {print $2}' | xargs)
    if [ -n "$OVX_OTHER" ]; then
        echo "NOTICE: $OVX_OTHER is installed (Perforce's or Debian's Puppet); OpenVox cannot be installed next to it."
        echo "        Remove it first ('sudo apt purge $OVX_OTHER', after backing up /etc/puppetlabs), then rerun setup with install-puppet."
    else
        # The release packages add the repository and its keyring; one major line at a time.
        for OVX_REL in "openvox${OVX_MAJOR}-release" tools-release; do
            OVX_DEB="$ASSETS/downloads/$OVX_REL-$OVX_DIST.deb"
            if curl -fsSL "https://apt.voxpupuli.org/$OVX_REL-$OVX_DIST.deb" -o "$OVX_DEB.part"; then
                mv "$OVX_DEB.part" "$OVX_DEB"
                sudo apt install -y "$OVX_DEB" > /dev/null || echo "NOTICE: could not install $OVX_REL."
            else
                rm -f "$OVX_DEB.part"
                [ "$OVX_REL" = tools-release ] || echo "NOTICE: could not download $OVX_REL-$OVX_DIST.deb from apt.voxpupuli.org."
            fi
        done
        for OVX_REL in openvox7-release openvox8-release openvox9-release; do
            [ "$OVX_REL" = "openvox${OVX_MAJOR}-release" ] && continue
            dpkg -s "$OVX_REL" > /dev/null 2>&1 && sudo apt purge -y "$OVX_REL" > /dev/null
        done
        sudo apt update
        if sudo apt install -y openvox-agent; then
            # Masterless: no agent daemon polling a server that does not exist.
            sudo systemctl disable --now puppet > /dev/null 2>&1 || true
            echo "OpenVox: puppet $(/opt/puppetlabs/bin/puppet --version 2> /dev/null), facter $(/opt/puppetlabs/bin/facter --version 2> /dev/null)"
        else
            echo "NOTICE: 'apt install openvox-agent' failed; rerun setup with install-puppet."
        fi
        if sudo apt install -y openbolt; then
            echo "OpenBolt: $(/opt/puppetlabs/bin/bolt --version 2> /dev/null || bolt --version 2> /dev/null)"
        else
            echo "NOTICE: 'apt install openbolt' failed (not in the repositories for $OVX_DIST?); 'gem install openbolt' is the other route."
        fi
        sed -i '/^# >>> dev-setup puppet >>>$/,/^# <<< dev-setup puppet <<<$/d' ~/.bashrc
        cat >> ~/.bashrc << 'EOF'
# >>> dev-setup puppet >>>
# Written by dev-setup (install-puppet); replaced on each run. OpenVox's puppet, facter and bolt, at the end of
# PATH so nothing in /opt/puppetlabs shadows a system command.
case ":$PATH:" in *":/opt/puppetlabs/bin:"*) ;; *) export PATH="$PATH:/opt/puppetlabs/bin" ;; esac
# <<< dev-setup puppet <<<
EOF
        echo "Try (new terminal): puppet apply -e 'notify { \"hello from OpenVox\": }'   bolt command run 'uname -a' --targets localhost"
    fi
else
    echo "Skipping OpenVox (Puppet). (Run with 'install-puppet' or 'install-config-mgmt'; opt-in)"
fi

if [[ "$FLAGS" =~ " install-chef " ]]; then
    echo "================================================================="
    echo "Installing Cinc Workstation (Chef)..."
    echo "================================================================="
    CINC_MAJOR="${CINC_WORKSTATION_MAJOR:-26}"
    CINC_PV=$(. /etc/os-release && echo "${VERSION_ID%%.*}")
    CINC_META=$(curl -fsSL "https://omnitruck.cinc.sh/stable/cinc-workstation/metadata?p=debian&pv=$CINC_PV&m=$(uname -m)&v=$CINC_MAJOR" 2> /dev/null || true)
    CINC_URL=$(printf '%s\n' "$CINC_META" | awk '$1 == "url" {print $2}')
    CINC_SHA=$(printf '%s\n' "$CINC_META" | awk '$1 == "sha256" {print $2}')
    CINC_VER=$(printf '%s\n' "$CINC_META" | awk '$1 == "version" {print $2}')
    CINC_HAVE=$(dpkg-query -W -f='${Version}' cinc-workstation 2> /dev/null || true)
    if [ -z "$CINC_URL" ] || [ -z "$CINC_SHA" ]; then
        echo "NOTICE: Cinc's omnitruck did not answer for Debian $CINC_PV${CINC_HAVE:+; keeping cinc-workstation $CINC_HAVE}. Rerun setup with install-chef."
    elif [ "${CINC_HAVE%-*}" = "$CINC_VER" ]; then
        echo "Cinc Workstation $CINC_VER is already installed."
    else
        CINC_DEB="$ASSETS/downloads/$(basename "$CINC_URL")"
        if curl -fL --retry 3 -C - -o "$CINC_DEB" "$CINC_URL" && echo "$CINC_SHA  $CINC_DEB" | sha256sum -c --quiet; then
            sudo apt install -y "$CINC_DEB" && rm -f "$CINC_DEB"
            echo "Cinc Workstation $CINC_VER installed${CINC_HAVE:+ (was $CINC_HAVE)}."
        else
            echo "NOTICE: the Cinc Workstation download failed or did not match its SHA-256; rerun setup with install-chef."
            rm -f "$CINC_DEB"
        fi
    fi
    sed -i '/^# >>> dev-setup chef >>>$/,/^# <<< dev-setup chef <<<$/d' ~/.bashrc
    cat >> ~/.bashrc << 'EOF'
# >>> dev-setup chef >>>
# Written by dev-setup (install-chef); replaced on each run. Cinc Workstation's commands at the end of PATH (its
# embedded Ruby stays out of PATH, so Debian's ruby is still 'ruby'). Cinc needs no license; CHEF_LICENSE only
# quiets tools that ask anyway.
case ":$PATH:" in *":/opt/cinc-workstation/bin:"*) ;; *) export PATH="$PATH:/opt/cinc-workstation/bin" ;; esac
export CHEF_LICENSE=accept-no-persist
# <<< dev-setup chef <<<
EOF
    # Progress's own Chef Workstation next to Cinc: say which one 'knife' and 'kitchen' are.
    CINC_KNIFE=$(readlink -f "$(command -v knife 2> /dev/null)" 2> /dev/null || true)
    case "$CINC_KNIFE" in
        /opt/cinc-workstation/*|"") ;;
        *) echo "NOTICE: 'knife' on PATH is $CINC_KNIFE, not Cinc's (Progress's Chef Workstation?). Cinc's are in /opt/cinc-workstation/bin." ;;
    esac
    [ -x /opt/cinc-workstation/bin/cinc-client ] && echo "Cinc: $(/opt/cinc-workstation/bin/cinc-client --version 2> /dev/null | head -n 1); Test Kitchen $(/opt/cinc-workstation/bin/kitchen --version 2> /dev/null)"
    echo "Try (new terminal): cinc-client --local-mode --runlist 'recipe[my_cookbook]'   kitchen list   cookstyle"
else
    echo "Skipping Cinc Workstation (Chef). (Run with 'install-chef' or 'install-config-mgmt'; opt-in)"
fi

# Local lakehouse stack: DuckDB + Iceberg/DuckLake/Delta + dbt (Fusion v2 and classic Core v1)
if [[ "$FLAGS" =~ " install-lakehouse " ]]; then
    echo "================================================================="
    echo "Installing Local Lakehouse Stack (DuckDB, Iceberg, DuckLake, Delta Lake, dbt)..."
    echo "================================================================="
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    # --- DuckDB CLI (latest release, single static binary) ---
    echo "Installing DuckDB CLI..."
    curl -fsSL "https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip" -o /tmp/duckdb_cli.zip
    unzip -o -q /tmp/duckdb_cli.zip -d /tmp/duckdb_cli
    install -m 755 /tmp/duckdb_cli/duckdb "$HOME/.local/bin/duckdb"
    rm -rf /tmp/duckdb_cli.zip /tmp/duckdb_cli
    echo "DuckDB CLI: $(duckdb --version)"

    # Pre-install the lakehouse extensions so first use works offline.
    # v79: delta reads Delta Lake tables (delta_scan, or ATTACH ... (TYPE delta)) and appends to them.
    duckdb -c "INSTALL iceberg; INSTALL ducklake; INSTALL delta; INSTALL httpfs; INSTALL sqlite; INSTALL postgres;"

    # --- Python environment: DuckDB bindings + classic dbt Core v1 with the dbt-duckdb adapter ---
    # Kept in its own venv (like ~/.gemma-env) so its 'dbt' doesn't collide with Fusion's.
    echo "Creating Python virtual environment for the lakehouse stack..."
    make_venv "$HOME/.lakehouse-env"
    "$HOME/.lakehouse-env/bin/pip" install -U pip
    # v79: deltalake is delta-rs, the Rust Delta Lake library (no Spark, no JVM): it creates Delta
    # tables and does the writes DuckDB cannot yet (UPDATE, DELETE, MERGE, OPTIMIZE, VACUUM).
    "$HOME/.lakehouse-env/bin/pip" install -U duckdb dbt-core dbt-duckdb pyarrow pandas deltalake
    "$HOME/.lakehouse-env/bin/python" -c "import duckdb; c=duckdb.connect(); [c.install_extension(e) for e in ('iceberg','ducklake','delta','httpfs')]"
    if ! grep -q 'alias dbt1=' ~/.bashrc; then
        echo "alias dbt1='$HOME/.lakehouse-env/bin/dbt'   # classic dbt Core v1 + dbt-duckdb" >> ~/.bashrc
    fi

    # --- dbt v2 (Fusion engine): Rust binary at ~/.local/bin/dbt, also aliased as dbtf ---
    # Fusion is what supports Iceberg/DuckLake catalogs.yml for DuckDB; Core v1 above supports DuckLake only.
    echo "Installing dbt v2 (Fusion engine)..."
    curl -fsSL https://public.cdn.getdbt.com/fs/install/install.sh | sh -s -- --update

    # Sensible defaults for an 8GB machine: cap DuckDB's memory so it spills to disk instead
    # of OOMing the VM. Edit ~/.duckdbrc to raise the limit on a bigger machine.
    mkdir -p "$HOME/.duckdb/tmp"
    if [ ! -f "$HOME/.duckdbrc" ]; then
        cat << EOF_RC > "$HOME/.duckdbrc"
-- Loaded by the DuckDB CLI on startup. Keep memory bounded on small machines.
SET memory_limit = '3GB';
SET temp_directory = '$HOME/.duckdb/tmp';
EOF_RC
    fi

    mkdir -p "$HOME/lakehouse"
    echo ""
    echo "Lakehouse stack installed. Quick start (after 'source ~/.bashrc'):"
    echo "  duckdb ~/lakehouse/dev.duckdb                      # CLI; extensions are pre-installed"
    echo "  ATTACH 'ducklake:~/lakehouse/catalog.ducklake' AS lake (DATA_PATH '~/lakehouse/data/');"
    echo "  Delta Lake: SELECT * FROM delta_scan('/path/to/table');  or  ATTACH '/path/to/table' AS t (TYPE delta);"
    echo "              new tables and UPDATE/DELETE/MERGE from Python: ~/.lakehouse-env (deltalake: write_deltalake, DeltaTable)"
    echo "  dbt --version   (Fusion v2)      dbt1 --version   (classic Core v1 + dbt-duckdb)"
    echo "  Start a project: cd ~/lakehouse && dbt init my_lake   (choose the duckdb adapter)"
    echo "  Close Ollama (ollama stop <model>) before large loads; RAM is shared."
else
    echo "Skipping Local Lakehouse stack. (Run with 'install-lakehouse' flag to enable)"
fi

# =================================================================
# install-ollama : the Ollama server (added in v77; v50-v76 installed it inside install-gemma)
# Pulled in by install-gemma, install-models and install-ollama-containers. It runs any model in the
# Ollama library, not only Gemma:   ollama pull deepseek-r1:1.5b && ollama run deepseek-r1:1.5b
# In Crostini inference is CPU-only: Ollama accelerates through CUDA, ROCm or Vulkan, and the
# container gets OpenGL through virgl and nothing else. Comfortable on these 8 GB Chromebooks (the
# VM sees ~6.4 GB): model files up to ~3.5 GB (the 1-4B class). A 7B (~4.7 GB) loads only with
# nothing else running; 8B and up is for a bigger machine ('ollama-remote') or a :cloud model.
# =================================================================
if [[ "$FLAGS" =~ " install-ollama " ]]; then
    echo "================================================================="
    echo "Installing the Ollama server..."
    echo "================================================================="
    # Ollama's installer downloads the whole Linux bundle (CUDA libraries included) on every run, so
    # it only runs when Ollama is missing or older than the latest release. OLLAMA_REINSTALL=1 forces
    # it. If the release lookup fails, the installer runs as before.
    OLLAMA_LATEST=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/ollama/ollama/releases/latest 2> /dev/null | sed 's|.*/tag/v||' || true)
    [[ "$OLLAMA_LATEST" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || OLLAMA_LATEST=""
    OLLAMA_HAVE=$(ollama --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | tail -n 1 || true)
    if [ "${OLLAMA_REINSTALL:-0}" != 1 ] && [ -n "$OLLAMA_HAVE" ] && [ "$OLLAMA_HAVE" = "$OLLAMA_LATEST" ]; then
        echo "Ollama $OLLAMA_HAVE is the latest release; skipping the download (OLLAMA_REINSTALL=1 forces it)."
    else
        echo "Installing Ollama ${OLLAMA_LATEST:-(latest)}${OLLAMA_HAVE:+ over $OLLAMA_HAVE} for Linux..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi

    # Server settings go into a systemd drop-in, so Ollama's own unit file stays untouched and its
    # installer can rewrite it freely. This file is rewritten on every run. To change a value, do
    # not edit it: 'sudo systemctl edit ollama' writes override.conf, which is read after it and wins.
    #   OLLAMA_LOAD_TIMEOUT=15m     v70: ChromeOS's memory balloon hands VM memory back slowly, so a
    #                                cold 4 GB load can outlast Ollama's default 5 minutes
    #   OLLAMA_MAX_LOADED_MODELS=2  the CPU default is 3. Two lets a RAG loop keep its embedding model
    #                                (qwen3-embedding:0.6b) next to its chat model instead of swapping
    #                                them on every question. Ollama co-loads a model only when it fits
    #                                in available memory at that moment, otherwise it unloads an idle
    #                                one first. Loaded models stay for the 5-minute keep-alive, so
    #                                before kind or a Gradle build free the RAM: 'ollama stop <model>'.
    #                                Set 1 with 'sudo systemctl edit ollama' for strictly one at a time.
    #   OLLAMA_NUM_PARALLEL=1       KV-cache memory scales with parallel requests x context length
    #   OLLAMA_CONTEXT_LENGTH=8192  the default is 4096. With the next two settings an 8K cache costs
    #   OLLAMA_FLASH_ATTENTION=1     about what the 4K f16 one did: q8_0 halves the KV cache, and
    #   OLLAMA_KV_CACHE_TYPE=q8_0    Ollama only quantizes it with flash attention on. Ollama notes
    #                                Qwen-style models feel q8_0 a little more; if long answers degrade,
    #                                set it back to f16 with 'sudo systemctl edit ollama'. dev-test
    #                                reports from Ollama's log which cache type was actually used.
    OLLAMA_DEV_ENV=(OLLAMA_LOAD_TIMEOUT=15m OLLAMA_MAX_LOADED_MODELS=2 OLLAMA_NUM_PARALLEL=1
        OLLAMA_CONTEXT_LENGTH=8192 OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0)
    export "${OLLAMA_DEV_ENV[@]}"   # for the 'ollama serve' fallback in ensure_ollama_server
    # v80: install-ollama-containers (opt-in, in no group) makes the server listen on every interface,
    # so Docker containers reach it at http://host.docker.internal:11434: DDEV's web container (a
    # Drupal AI site), a Langfuse or LangGraph container, any 'docker run --add-host=host.docker.internal:host-gateway'.
    # A container's request arrives over the Docker bridge, not over loopback, so the default
    # 127.0.0.1 binding refuses it. Local clients are unaffected (0.0.0.0 includes 127.0.0.1). The
    # Crostini container sits behind ChromeOS, which forwards its ports to ChromeOS itself only, so
    # this does not expose Ollama to your network. It is its own drop-in, written only when the flag
    # is given and left in place by runs without it, so a later 'install-all' does not undo it.
    # To undo:  sudo rm /etc/systemd/system/ollama.service.d/dev-setup-containers.conf
    #           sudo systemctl daemon-reload && sudo systemctl restart ollama
    OLLAMA_CONTAINERS_CONF=/etc/systemd/system/ollama.service.d/dev-setup-containers.conf
    if systemctl list-unit-files ollama.service 2> /dev/null | grep -q '^ollama\.service'; then
        sudo mkdir -p /etc/systemd/system/ollama.service.d
        {
            echo '# Written by dev-setup (install-ollama); rewritten on every run.'
            echo '# To change a value: sudo systemctl edit ollama   (override.conf is read after this file)'
            echo '[Service]'
            for kv in "${OLLAMA_DEV_ENV[@]}"; do echo "Environment=\"$kv\""; done
        } | sudo tee /etc/systemd/system/ollama.service.d/dev-setup.conf > /dev/null
        if [[ "$FLAGS" =~ " install-ollama-containers " ]]; then
            {
                echo '# Written by dev-setup (install-ollama-containers). Runs without that flag keep this file.'
                echo '# Lets Docker containers reach Ollama at http://host.docker.internal:11434.'
                echo '# Undo: sudo rm this file, then: sudo systemctl daemon-reload && sudo systemctl restart ollama'
                echo '[Service]'
                echo 'Environment="OLLAMA_HOST=0.0.0.0:11434"'
            } | sudo tee "$OLLAMA_CONTAINERS_CONF" > /dev/null
        fi
        sudo systemctl daemon-reload
        sudo systemctl enable ollama > /dev/null 2>&1 || true
        sudo systemctl restart ollama || true
    elif [[ "$FLAGS" =~ " install-ollama-containers " ]]; then
        echo "NOTICE: no systemd unit for Ollama, so install-ollama-containers cannot configure it. Start it as"
        echo "        OLLAMA_HOST=0.0.0.0:11434 ollama serve   for containers to reach it."
    fi
    ensure_ollama_server || echo "NOTICE: the Ollama server is not answering; start it with 'sudo systemctl start ollama'."

    # Client side, in a marked ~/.bashrc block rewritten on every run. Nothing in it runs a command at
    # shell start (v74's lesson), so where it sits in the file does not matter.
    #   OLLAMA_API_BASE  where aider (through LiteLLM) finds Ollama: aider --model ollama_chat/qwen3.5:4b
    #   ollama-remote    the ollama CLI against another machine's server, e.g. the 32 GB Windows
    #                    laptop, for models too big for this one. It reads OLLAMA_REMOTE (optional,
    #                    in dev-init's secrets.env). Deliberately not a global OLLAMA_HOST: that
    #                    would point the plain 'ollama' command, and every client, away from this
    #                    machine's server.
    sed -i '/^# >>> dev-setup ollama >>>$/,/^# <<< dev-setup ollama <<<$/d' ~/.bashrc
    cat >> ~/.bashrc << 'EOF'
# >>> dev-setup ollama >>>
# Written by dev-setup (install-ollama); this block is replaced on each run.
# aider finds the local Ollama server here:  aider --model ollama_chat/qwen3.5:4b
export OLLAMA_API_BASE="http://127.0.0.1:11434"
# 'ollama-remote' = the ollama CLI against another machine's Ollama (OLLAMA_REMOTE in
# ~/.config/dev-init/secrets.env, e.g. http://192.168.1.50:11434, or with install-lan a laptop's name
# such as winlaptop; the port defaults to 11434). Plain 'ollama' stays local.
ollama-remote() {
    if [ -z "${OLLAMA_REMOTE:-}" ]; then
        echo "ollama-remote: set OLLAMA_REMOTE in ~/.config/dev-init/secrets.env, then open a new terminal" >&2
        return 1
    fi
    OLLAMA_HOST="$OLLAMA_REMOTE" ollama "$@"
}
# <<< dev-setup ollama <<<
EOF
    export OLLAMA_API_BASE="http://127.0.0.1:11434"

    echo "Ollama: $(ollama --version 2> /dev/null | tail -n 1)"
    echo "Server settings: /etc/systemd/system/ollama.service.d/dev-setup.conf (at most two models loaded, 8K context, q8_0 KV cache)."
    if [ -f "$OLLAMA_CONTAINERS_CONF" ]; then
        echo "Containers reach Ollama at http://host.docker.internal:11434 ($OLLAMA_CONTAINERS_CONF; the comment in it says how to undo it)."
    fi
    echo "CPU-only in Crostini. Any library model runs:  ollama run deepseek-r1:1.5b"
    echo "Curated models for this machine: rerun with install-models. A bigger machine's Ollama: OLLAMA_REMOTE in"
    echo "secrets.env, then 'ollama-remote run <model>'. Cloud models (pay per token, e.g. deepseek-v4.1-flash:cloud):"
    echo "'ollama signin' once, then 'ollama run <model>:cloud'."
else
    echo "Skipping the Ollama server. (Run with 'install-ollama'; install-gemma, install-models and install-ollama-containers include it)"
fi

# Google Gemma 4 Developer Setup
if [[ "$FLAGS" =~ " install-gemma " ]]; then
    echo "================================================================="
    echo "Installing Google Gemma 4 Developer & Hybrid Setup..."
    echo "================================================================="
    # v77: Ollama itself is install-ollama now: this flag pulls it in and it was installed just above.

    # Pull the lightweight Gemma 4 model so gemma_client.py works out of the box.
    # e2b = effective-2B; the -qat build is ~4.3GB instead of ~7.2GB, which matters on 8GB RAM.
    GEMMA_MODEL="gemma4:e2b-it-qat"
    echo "Ensuring the Ollama server is running..."
    ensure_ollama_server || echo "NOTICE: the Ollama server is not answering; the pull below will say why."
    if ollama list 2>/dev/null | grep -q "^${GEMMA_MODEL}"; then
        echo "Model ${GEMMA_MODEL} already downloaded, skipping pull."
    else
        echo "Pulling ${GEMMA_MODEL} (about 4.3GB, this will take a few minutes)..."
        ollama pull "${GEMMA_MODEL}"
    fi

    echo "Creating Python virtual environment for Gemma..."
    make_venv "$HOME/.gemma-env"

    echo "Installing Python dependencies (transformers, torch, accelerate, ollama, google-genai)..."
    # CPU-only torch: avoids ~3GB of CUDA libraries that are useless on a Chromebook
    ~/.gemma-env/bin/pip install -U torch --index-url https://download.pytorch.org/whl/cpu
    ~/.gemma-env/bin/pip install -U transformers accelerate ollama google-genai

    echo "Creating gemma_client.py hybrid script..."
    # v65: written to ./assets, not the home directory.
    cat << 'EOF' > "$ASSETS/gemma_client.py.new"
import argparse
import os
import socket
import sys

import ollama
from google import genai

# Gemma 4 small variants are tagged by *effective* size (e2b/e4b); the -qat build is ~4.3GB
# instead of ~7.2GB, which is what makes it usable on an 8GB Chromebook.
# v77: -m/--model picks any local Ollama model (and stays local); --think / --no-think steer a
# thinking model (deepseek-r1, qwen3.5, gemma4); its reasoning is shown dimmed and kept out of the
# conversation history.
LOCAL_MODEL = os.environ.get("GEMMA_LOCAL_MODEL", "gemma4:e2b-it-qat")
CLOUD_MODEL = os.environ.get("GEMMA_CLOUD_MODEL", "gemini-2.5-flash")
LOCAL_ONLY = False
THINK = None  # None = the model's default; True / False = ask for (no) reasoning first
DIM, RESET = ("\033[2m", "\033[0m") if sys.stdout.isatty() else ("", "")


def parse_args():
    p = argparse.ArgumentParser(
        prog="gemma",
        description="Hybrid terminal chat: Gemini when online with GEMINI_API_KEY set, local Ollama otherwise.",
    )
    p.add_argument("-m", "--model", help="local Ollama model to chat with, e.g. deepseek-r1:1.5b (implies --local)")
    p.add_argument("--local", action="store_true", help="never use the cloud route")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--think", dest="think", action="store_true", default=None,
                   help="ask a thinking model to reason before answering (shown dimmed)")
    g.add_argument("--no-think", dest="think", action="store_false",
                   help="ask a thinking model to answer directly")
    return p.parse_args()


def is_online() -> bool:
    """Quick connectivity check (does not prove the Gemini API is reachable)."""
    try:
        socket.create_connection(("8.8.8.8", 53), timeout=2)
        return True
    except OSError:
        return False


def to_genai_contents(history):
    """Convert the shared history into the google-genai contents format."""
    role_map = {"user": "user", "assistant": "model"}
    return [
        {"role": role_map[m["role"]], "parts": [{"text": m["content"]}]}
        for m in history
    ]


def start_reply(label: str):
    """Print the reply label plus a waiting indicator; returns a function that clears it."""
    waiting = f"{label}: ⏳ waiting for first token (model may be loading)..."
    print(waiting, end="", flush=True)

    def clear():
        # overwrite the waiting text with the bare label so streamed tokens follow it
        print("\r" + " " * len(waiting) + "\r" + f"{label}: ", end="", flush=True)

    return clear


def stream_cloud(history) -> str | None:
    """Stream a reply from Gemini. Returns the full text, or None if anything failed."""
    try:
        client = genai.Client()  # reads GEMINI_API_KEY from the environment
        stream = client.models.generate_content_stream(
            model=CLOUD_MODEL,
            contents=to_genai_contents(history),
        )
        clear = start_reply(CLOUD_MODEL)
        full = ""
        for chunk in stream:
            text = chunk.text or ""  # some chunks carry no text
            if clear:
                clear()
                clear = None
            print(text, end="", flush=True)
            full += text
        if clear:  # stream ended without a single chunk
            clear()
        print()
        return full
    except Exception as e:  # APIError, httpx transport errors, auth problems, etc.
        print(f"\n⚠️ Cloud request failed ({type(e).__name__}: {e}). Falling back to local Ollama...")
        return None


def stream_local(history) -> str | None:
    """Stream a reply from local Ollama. Returns the full text (reasoning excluded), or None if it failed."""
    try:
        kwargs = {"model": LOCAL_MODEL, "messages": history, "stream": True}
        if THINK is not None:
            kwargs["think"] = THINK
        stream = ollama.chat(**kwargs)
        clear = start_reply(LOCAL_MODEL)
        full = ""
        in_thinking = False
        for chunk in stream:
            msg = chunk["message"]
            thinking = getattr(msg, "thinking", None) or ""
            content = msg["content"] or ""
            if clear and (thinking or content):
                clear()
                clear = None
            if thinking:
                print(DIM + thinking + RESET, end="", flush=True)
                in_thinking = True
            if content:
                if in_thinking:
                    print("\n", flush=True)
                    in_thinking = False
                print(content, end="", flush=True)
                full += content
        if clear:
            clear()
        print()
        return full
    except Exception as e:
        print(f"\n❌ Local execution failed: {e}")
        print(f"Make sure 'ollama serve' is running and 'ollama pull {LOCAL_MODEL}' has completed.")
        return None


def chat():
    print("=========================================================")
    print("🤖 Gemma 4 Hybrid Terminal Chat Client (Streaming)")
    if LOCAL_ONLY:
        print(f"   local only: {LOCAL_MODEL}")
    else:
        print(f"   cloud: {CLOUD_MODEL}   local: {LOCAL_MODEL}")
    print("Type 'exit' or 'quit' to end the session.")
    print("Type at the 'You:' prompt only. The first local reply can take up to a")
    print("minute while Ollama loads the model; later turns are much faster.")
    print("=========================================================\n")

    history = []  # one shared transcript, used by both the cloud and local paths

    while True:
        try:
            user_input = input("\nYou: ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nSession interrupted. Exiting.")
            break

        if not user_input:
            continue
        if user_input.lower() in ("exit", "quit"):
            print("Exiting chat session. Goodbye!")
            break

        history.append({"role": "user", "content": user_input})
        reply = None

        if not LOCAL_ONLY and is_online() and os.environ.get("GEMINI_API_KEY"):
            print("☁️ [Online] Streaming from Google AI Studio...\n")
            reply = stream_cloud(history)

        if reply is None:
            print(f"💻 [Local] Streaming from Ollama...\n")
            reply = stream_local(history)

        if reply is None:
            history.pop()  # roll back the user turn so history never has two user messages in a row
        else:
            history.append({"role": "assistant", "content": reply})


if __name__ == "__main__":
    args = parse_args()
    if args.model:
        LOCAL_MODEL = args.model
    LOCAL_ONLY = bool(args.model or args.local)
    THINK = args.think
    chat()
EOF
    # An older version of this installer left ~/gemma_client.py (and py_compile in the test script
    # left ~/__pycache__). Remove the home copy if it is what we would write anyway; keep it next
    # to the new one if you edited it.
    if [ -f "$HOME/gemma_client.py" ]; then
        if cmp -s "$HOME/gemma_client.py" "$ASSETS/gemma_client.py.new"; then
            rm -f "$HOME/gemma_client.py"
        else
            mv "$HOME/gemma_client.py" "$ASSETS/gemma_client.from-home.py"
            echo "Your edited ~/gemma_client.py was moved to $ASSETS/gemma_client.from-home.py"
        fi
    fi
    rm -f "$HOME"/__pycache__/gemma_client.*.pyc
    rmdir "$HOME/__pycache__" 2> /dev/null || true
    mv "$ASSETS/gemma_client.py.new" "$ASSETS/gemma_client.py"
    echo "Saved $ASSETS/gemma_client.py"

    # v65: 'gemma' launcher. Calls the venv's python directly, so there is no activate/deactivate
    # to leak into your shell if the script is interrupted, and passes arguments through. The
    # block sits between markers and is replaced on every run, so it keeps pointing at this
    # bundle folder if you move it and rerun install-gemma.
    sed -i '/^# >>> dev-setup gemma launcher >>>$/,/^# <<< dev-setup gemma launcher <<<$/d' ~/.bashrc
    case "$ASSETS" in
        *[\"\$\`\\]*)
            echo "Skipping the 'gemma' launcher: $ASSETS contains characters that are unsafe to embed in ~/.bashrc."
            ;;
        *)
            {
                echo '# >>> dev-setup gemma launcher >>>'
                echo '# Gemma hybrid AI client (written by dev-setup; this block is replaced on each run)'
                echo "gemma() { \"\$HOME/.gemma-env/bin/python\" \"$ASSETS/gemma_client.py\" \"\$@\"; }"
                echo '# <<< dev-setup gemma launcher <<<'
            } >> ~/.bashrc
            echo "Added the 'gemma' command to ~/.bashrc (new terminals, or 'source ~/.bashrc')."
            ;;
    esac

    echo "Authenticating with Hugging Face..."
    # v68: setup never stops to ask. The token comes from the environment or, failing that, from
    # the secrets file dev-init wrote (setup used to ignore that file, so a filled-in HF_TOKEN
    # still produced a login prompt here). Read in a subshell so nothing else from the file
    # leaks into this run. No token anywhere: dev-init does the login (token or interactive).
    if [ -z "$HF_TOKEN" ] && [ -f "$HOME/.config/dev-init/secrets.env" ]; then
        HF_TOKEN=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "$HF_TOKEN"' _ "$HOME/.config/dev-init/secrets.env" || true)
        [ -n "$HF_TOKEN" ] && echo "Using HF_TOKEN from ~/.config/dev-init/secrets.env."
    fi
    if [ -n "$HF_TOKEN" ]; then
        echo "Logging in to Hugging Face non-interactively..."
        ~/.gemma-env/bin/hf auth login --token "$HF_TOKEN" || echo "NOTICE: Hugging Face rejected HF_TOKEN; dev-init will report it. Ollama needs no login."
    else
        echo "No HF_TOKEN in the environment or in secrets.env: leaving the Hugging Face login to dev-init."
    fi

    echo "================================================================="
    echo "Gemma 4 Setup Complete!"
    echo "The lightweight ${GEMMA_MODEL} model has been pulled into Ollama"
    echo "(chosen for 8GB RAM; larger variants like gemma4:e4b may freeze this Chromebook)."
    echo "Remember to export your GEMINI_API_KEY into your ~/.bashrc"
    echo "so the Python script can route to the cloud API when online."
    echo ""
    echo "Run it with:  gemma      (after 'source ~/.bashrc' or in a new terminal)"
    echo "Any local model:  gemma -m deepseek-r1:1.5b   (local route only; 'gemma --help' lists the options)"
    echo "Or by hand: activate the virtual environment first by typing:"
    echo "  source ~/.gemma-env/bin/activate"
    echo "Then run: python3 \"$ASSETS/gemma_client.py\""
    echo "================================================================="
else
    echo "Skipping Google Gemma 4 Developer Setup. (Run with 'install-gemma' flag to enable)"
fi

# =================================================================
# install-models : curated local models for an 8 GB Chromebook (added in v77). Opt-in, NOT part of
# install-all (about 5 GB of downloads). Pulls in install-ollama.
#   deepseek-r1:1.5b      1.1 GB  DeepSeek-R1 distilled into Qwen 1.5B: the DeepSeek that fits here.
#                                 A reasoning model; '--think=false' (CLI) or "think": false (API)
#                                 makes it answer directly. DeepSeek's current V4 models (~760B) are
#                                 cloud-only: deepseek-v4.1-flash:cloud after 'ollama signin'.
#   qwen3.5:4b            3.4 GB  general model with vision, tool calling and thinking; the best small
#                                 fit here for LangGraph tool calls
#   qwen3-embedding:0.6b  639 MB  text embeddings for local RAG
# OLLAMA_EXTRA_MODELS="deepseek-r1:7b ..." adds more (a 7B needs everything else closed). The models
# of this flag that are present afterwards are listed in assets/ollama-models.txt, which dev-test
# checks and dev-demo uses.
# Disk guard: a pull is skipped (NOTICE, setup carries on) when it would leave less than
# DEV_MODELS_MIN_FREE_GB (default min(10, 15% of the Linux disk), v92) free where Ollama keeps its models. The size comes from the
# registry manifest; when that lookup fails, only the margin is checked.
# =================================================================
if [[ "$FLAGS" =~ " install-models " ]]; then
    echo "================================================================="
    echo "Pulling local models (install-models)..."
    echo "================================================================="
    MODELS_DEFAULT=(deepseek-r1:1.5b qwen3.5:4b qwen3-embedding:0.6b)
    read -ra MODELS_EXTRA <<< "${OLLAMA_EXTRA_MODELS:-}"
    # A server that will not come up skips the pulls instead of aborting the rest of the run.
    OLLAMA_UP=1
    if ! ensure_ollama_server; then
        OLLAMA_UP=0
        echo "NOTICE: the Ollama server is not answering, so no models are pulled. Try 'sudo systemctl restart ollama', then rerun with install-models."
        MODELS_DEFAULT=(); MODELS_EXTRA=()
    fi
    # v92: the margin scales with the disk like the database servers' (min(10, 15% of the Linux disk)).
    MIN_FREE_GB="${DEV_MODELS_MIN_FREE_GB:-$(disk_margin_gb 10)}"
    # The systemd service keeps its models under /usr/share/ollama; without it they go to ~/.ollama.
    MODEL_STORE=/usr/share/ollama
    [ -d "$MODEL_STORE" ] || MODEL_STORE="$HOME"

    # model_bytes NAME[:TAG]: download size in bytes from the registry manifest; empty when unknown.
    model_bytes() {
        local ref=$1 name tag repo
        name=${ref%%:*}; tag=latest
        [[ "$ref" == *:* ]] && tag=${ref#*:}
        case "$name" in */*) repo=$name ;; *) repo=library/$name ;; esac
        curl -fsSL --max-time 20 -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
            "https://registry.ollama.ai/v2/$repo/manifests/$tag" 2> /dev/null \
            | jq -r '[.config.size // 0, (.layers[]?.size // 0)] | add' 2> /dev/null || true
    }
    # have_model NAME[:TAG]: exact match in 'ollama list' (a bare name means :latest)
    have_model() {
        local want=$1
        [[ "$want" == *:* ]] || want="$want:latest"
        ollama list 2> /dev/null | awk 'NR > 1 {print $1}' | grep -qxF "$want"
    }

    PULLED=(); PRESENT=(); SKIPPED_MODELS=()
    for m in "${MODELS_DEFAULT[@]}" "${MODELS_EXTRA[@]}"; do
        [ -n "$m" ] || continue
        case "$m" in
            *:cloud|*-cloud)
                echo "NOTICE: $m is a cloud model, so there is nothing to download. Run 'ollama signin' once, then 'ollama run $m'."
                SKIPPED_MODELS+=("$m (cloud)")
                continue ;;
        esac
        if have_model "$m"; then
            echo "Model $m already downloaded."
            PRESENT+=("$m")
            continue
        fi
        free_kb=$(df -Pk "$MODEL_STORE" | awk 'NR == 2 {print $4}')
        need_b=$(model_bytes "$m")
        [[ "$need_b" =~ ^[0-9]+$ ]] || need_b=0
        left_gb=$(( (free_kb * 1024 - need_b) / 1024 / 1024 / 1024 ))
        if [ "$need_b" -gt 0 ]; then size_txt="$(( need_b / 1024 / 1024 )) MB"; else size_txt="size unknown"; fi
        if [ "$left_gb" -lt "$MIN_FREE_GB" ]; then
            echo "NOTICE: skipping $m ($size_txt): it would leave ${left_gb} GB free, under DEV_MODELS_MIN_FREE_GB=$MIN_FREE_GB."
            echo "        Give Linux more disk (ChromeOS Settings > About ChromeOS > Linux development environment > Disk size),"
            echo "        remove a model you no longer use ('ollama rm <model>'), or rerun with DEV_MODELS_MIN_FREE_GB=<lower>."
            SKIPPED_MODELS+=("$m (disk)")
            continue
        fi
        echo "Pulling $m ($size_txt)..."
        if ollama pull "$m"; then
            PULLED+=("$m")
        else
            echo "NOTICE: 'ollama pull $m' failed (misspelled tag, or network); skipped."
            SKIPPED_MODELS+=("$m (pull failed)")
        fi
    done

    # What dev-test checks and dev-demo uses: every model of this flag that is present now. Left as it
    # was when the server was down, so one bad run does not erase the record.
    if [ "$OLLAMA_UP" = 1 ]; then
        : > "$ASSETS/ollama-models.txt"
        for m in "${MODELS_DEFAULT[@]}" "${MODELS_EXTRA[@]}"; do
            if [ -n "$m" ] && have_model "$m"; then echo "$m" >> "$ASSETS/ollama-models.txt"; fi
        done
    fi
    touch "$ASSETS/ollama-models.txt"

    echo "Models: ${#PULLED[@]} pulled, ${#PRESENT[@]} already present, ${#SKIPPED_MODELS[@]} skipped${SKIPPED_MODELS[*]:+: ${SKIPPED_MODELS[*]}}"
    echo "Recorded in $ASSETS/ollama-models.txt:"
    sed 's/^/  /' "$ASSETS/ollama-models.txt"
    echo "Try:  ollama run deepseek-r1:1.5b                (reasoning model; add --think=false for a direct answer)"
    echo "      gemma -m qwen3.5:4b                        (the hybrid client on any local model; install-gemma)"
    echo "      aider --model ollama_chat/qwen3.5:4b       (works, but a 4B model makes a basic coding agent)"
    echo "Up to two models stay loaded when they fit: 'ollama ps' shows them, 'ollama stop <model>' gives the RAM back."
else
    echo "Skipping the curated local models. (Run with 'install-models' to enable; not part of install-all)"
fi

# =================================================================
# install-agentic : Temporal + LangGraph + Pydantic + Langfuse workbench
# (added in v50). Requires only the base section (python3-venv, Homebrew,
# Docker). Idempotent: safe to re-run; every step checks before it installs.
# =================================================================
if [[ "$FLAGS" =~ " install-agentic " ]]; then
    echo "================================================================="
    echo "Installing Agentic Workflow Stack (Temporal, LangGraph, Pydantic, Langfuse)..."
    echo "================================================================="

    AGENTIC_ENV="$HOME/.agentic-env"
    AGENTIC_HOME="$HOME/agentic"

    # --- Temporal CLI: bundles the dev server (SQLite persistence) + Web UI ---
    # Same channel as ddev/gh/mkcert, so it lands on PATH via brew shellenv.
    if brew list --formula temporal &>/dev/null; then
        echo "Temporal CLI already installed; upgrading if needed..."
        brew upgrade temporal || true
    else
        echo "Installing Temporal CLI..."
        brew install temporal
    fi
    TEMPORAL_BIN="$(brew --prefix)/bin/temporal"
    echo "Temporal CLI: $("$TEMPORAL_BIN" --version 2>/dev/null || echo 'installed (version check skipped)')"

    # --- Python venv (same pattern as ~/.gemma-env and ~/.lakehouse-env) ----
    echo "Creating (or reusing) the Python virtual environment for the agentic stack..."
    make_venv "$AGENTIC_ENV"
    "$AGENTIC_ENV/bin/pip" install -U pip
    # temporalio            : SDK; temporalio.contrib.pydantic gives the Pydantic data converter
    # langgraph + sqlite    : graph runtime + SqliteSaver checkpointer for local interrupt/resume
    # langfuse              : v4 SDK (@observe decorator, langfuse.langchain.CallbackHandler);
    #                         reads LANGFUSE_BASE_URL. v51: langfuse.langchain imports the full
    #                         'langchain' package, not just langchain-core, so it is listed too.
    # langchain-ollama      : local Gemma via install-gemma; -anthropic/-google-genai for hosted
    # pytest-asyncio        : Temporal's WorkflowEnvironment tests are async
    "$AGENTIC_ENV/bin/pip" install -U \
        temporalio \
        langgraph langchain langchain-core langgraph-checkpoint-sqlite \
        pydantic pydantic-settings \
        langfuse \
        langchain-ollama langchain-anthropic langchain-google-genai \
        python-dotenv rich pytest pytest-asyncio

    # Smoke test: fail here, with a readable message, rather than on first 'python worker.py'
    echo "Verifying agentic stack imports..."
    "$AGENTIC_ENV/bin/python" - << 'EOF_PY'
import importlib, sys
from importlib.metadata import version
mods = ["temporalio", "temporalio.contrib.pydantic", "langgraph",
        "langgraph.checkpoint.sqlite", "pydantic", "langfuse", "langfuse.langchain"]
bad = []
for m in mods:
    try:
        importlib.import_module(m)
    except Exception as e:
        bad.append(f"{m}: {e}")
if bad:
    print("Agentic stack import check FAILED:\n  " + "\n  ".join(bad))
    sys.exit(1)
# v51: read versions from package metadata; langgraph does not expose __version__.
print("  " + "  ".join(f"{p} {version(p)}" for p in ("temporalio", "langgraph", "langfuse", "pydantic")))
EOF_PY

    if ! grep -q 'alias agentic=' ~/.bashrc; then
        echo "alias agentic='source $AGENTIC_ENV/bin/activate'" >> ~/.bashrc
    fi

    # --- Project home + Langfuse self-host compose (fetched, NOT started) ---
    # Only the compose file is needed; cloning the whole langfuse repo was ~400MB for nothing.
    # Self-host = web + worker + Postgres + ClickHouse + Redis + MinIO (~3GB RAM). On the
    # 8GB Chromebooks use Langfuse Cloud (free Hobby tier) or run this compose on a bigger box.
    mkdir -p "$AGENTIC_HOME/langfuse"
    echo "Fetching Langfuse docker-compose.yml (not started)..."
    if ! curl -fsSL --retry 3 --retry-delay 2 \
            https://raw.githubusercontent.com/langfuse/langfuse/main/docker-compose.yml \
            -o "$AGENTIC_HOME/langfuse/docker-compose.yml"; then
        echo "WARNING: could not fetch Langfuse docker-compose.yml; continuing (re-run later or use Langfuse Cloud)."
    fi

    if [ ! -f "$AGENTIC_HOME/.env.example" ]; then
        cat << 'EOF_ENV' > "$AGENTIC_HOME/.env.example"
# Langfuse: cloud.langfuse.com project keys, or http://localhost:3000 if self-hosted
LANGFUSE_PUBLIC_KEY=pk-lf-...
LANGFUSE_SECRET_KEY=sk-lf-...
LANGFUSE_BASE_URL=https://cloud.langfuse.com
LANGFUSE_HOST=https://cloud.langfuse.com   # legacy name (v2 SDK); keep in sync with BASE_URL
# Temporal dev server default
TEMPORAL_ADDRESS=localhost:7233
TEMPORAL_NAMESPACE=default
TEMPORAL_TASK_QUEUE=placement
# Local model via Ollama (install-gemma) or a hosted key
OLLAMA_MODEL=gemma4:e2b-it-qat
ANTHROPIC_API_KEY=
GOOGLE_API_KEY=
EOF_ENV
    fi

    # Temporal dev server with a persistent DB so workflows survive restarts.
    if ! grep -q 'alias tsdb=' ~/.bashrc; then
        echo "alias tsdb='temporal server start-dev --db-filename $AGENTIC_HOME/temporal.db'" >> ~/.bashrc
    fi

    # --- v89: MCP tooling. FastMCP's CLI as a uv tool, in its own environment on a uv-managed Python
    # (not ~/.agentic-env: projects add fastmcp as a library themselves):
    #   fastmcp run server.py [--transport http]   serve a server        fastmcp list / call server.py ...
    #   fastmcp dev inspector server.py            the server in the MCP Inspector (UI on :6274)
    #   fastmcp inspect server.py                  its tools, resources and prompts
    #   fastmcp install claude-code server.py      register it with Claude Code (also: claude mcp add)
    # The 'fastmcp' command now ships in the fastmcp-slim package (fastmcp itself has no executables, and
    # 'uv tool install fastmcp' refuses it), so the tool is fastmcp-slim with the full fastmcp alongside.
    # A 'fastmcp' tool left by an older manual install owns the same command: it is replaced.
    # Not fatal under set -e: PyPI being unreachable leaves the rest of setup running.
    if uv tool list 2> /dev/null | grep -q '^fastmcp '; then uv tool uninstall fastmcp > /dev/null 2>&1 || true; fi
    if uv tool install --force --quiet fastmcp-slim@latest --with fastmcp; then
        echo "fastmcp: $(fastmcp version 2> /dev/null | sed -n 's/^FastMCP version: *//p' | head -n 1)"
    else
        echo "NOTICE: 'uv tool install fastmcp-slim --with fastmcp' failed (is PyPI reachable?); rerun setup with install-agentic."
    fi
    # The MCP Inspector (Node): installed globally as 'mcp-inspector' and left in npm's cache, so 'npx
    # @modelcontextprotocol/inspector' and 'fastmcp dev inspector' start without downloading it first. It
    # needs Node: with install-node (install-all has it), otherwise a NOTICE.
    if command -v npm > /dev/null 2>&1; then
        if npm install -g --allow-scripts=esbuild @modelcontextprotocol/inspector@latest > /dev/null 2>&1; then
            # npx keeps its own copy per package: run it once (a no-op command) so that copy is complete.
            timeout 300 npx --yes --package=@modelcontextprotocol/inspector@latest -c true > /dev/null 2>&1 || true
            echo "MCP Inspector: $(npm ls -g --depth=0 @modelcontextprotocol/inspector 2> /dev/null | grep -o 'inspector@[0-9.]*' || echo installed) (mcp-inspector; npx cache warm)"
        else
            echo "NOTICE: 'npm install -g @modelcontextprotocol/inspector' failed (is the npm registry reachable?); rerun setup with install-agentic."
        fi
    else
        echo "NOTICE: no npm, so no MCP Inspector (it is a Node app): rerun setup with install-agentic install-node."
    fi

    echo ""
    echo "Agentic stack installed. Quick start (after 'source ~/.bashrc'):"
    echo "  Terminal 1:  tsdb                                        # Temporal server :7233, UI at http://localhost:8233"
    echo "  Terminal 2:  cd ~/agentic && agentic && python worker.py  # Temporal worker (LangGraph runs inside activities)"
    echo "  Terminal 3:  cd ~/agentic && agentic && python starter.py # kicks off a PlacementWorkflow"
    echo "  Human step:  send the workflow a Signal from the Temporal UI (Workflow > Signal) or 'temporal workflow signal'"
    echo "  Gotcha:      keep @workflow.defn classes in their own module (workflows.py); the sandbox re-imports"
    echo "               that module, so a bare asyncio.run() next to a workflow definition fails on first run."
    echo "  Langfuse:    cp ~/agentic/.env.example ~/agentic/.env and add Cloud keys, or on a >=16GB box:"
    echo "               cd ~/agentic/langfuse && docker compose up -d      # UI at http://localhost:3000"
    echo "  RAM note:    Ollama (~3.5GB) + Temporal + worker fit in 8GB; add self-hosted Langfuse and it won't."
    echo "  MCP:         fastmcp run server.py | fastmcp dev inspector server.py | mcp-inspector --cli <server command> --method tools/list"
else
    echo "Skipping Agentic Workflow stack. (Run with 'install-agentic' flag to enable)"
fi

# =================================================================
# install-cloud : AWS / Azure / Google Cloud CLIs (added in v57)
# CLIs only. Logins (aws configure sso, az login, gcloud auth login) are
# per-account and interactive, so dev-init-chromebook owns them. Cloud SDKs
# (boto3, azure-identity, google-cloud-*) are per-project dependencies and
# stay out of this script entirely.
# =================================================================

# AWS CLI v2
if [[ "$FLAGS" =~ " install-aws " ]]; then
    echo "Installing AWS CLI v2..."
    # Homebrew ships a bottled v2 for x86_64 Linux and upgrades it with 'brew upgrade';
    # Debian's apt package lags releases and AWS's zip installer has no upgrade path.
    brew install awscli
    echo "AWS CLI: $(aws --version)"
    echo "Log in with dev-init (install-aws): 'aws configure sso', or static keys from secrets.env."
else
    echo "Skipping AWS CLI. (Run with 'install-aws' or 'install-cloud' flag to enable)"
fi

# Azure CLI
if [[ "$FLAGS" =~ " install-azure " ]]; then
    echo "Installing Azure CLI..."
    # Homebrew rather than Microsoft's apt repo: aka.ms/InstallAzureCLIDeb keys the source list
    # to $(lsb_release -cs), and a suite missing for trixie would abort the run under set -e.
    # ('pipx install azure-cli' is the lighter alternative if brew's Python bottle is unwanted.)
    brew install azure-cli
    echo "Azure CLI: $(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo 'installed (version check skipped)')"
    echo "Log in with dev-init (install-azure): 'az login --use-device-code', or a service principal from secrets.env."
else
    echo "Skipping Azure CLI. (Run with 'install-azure' or 'install-cloud' flag to enable)"
fi

# Google Cloud CLI
if [[ "$FLAGS" =~ " install-gcp " ]]; then
    echo "Installing Google Cloud CLI..."
    # Google's apt repo (the Homebrew cask is macOS-only), same signed-by keyring pattern as
    # Docker and VS Code above. Uses the system python3; trixie's 3.13 is within gcloud's range.
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg --yes
    echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null
    sudo apt update
    sudo apt install -y google-cloud-cli
    echo "gcloud: $(gcloud --version 2>/dev/null | head -n 1)"
    echo "Log in with dev-init (install-gcp): 'gcloud auth login' + application-default login, or a service-account key from secrets.env."
else
    echo "Skipping Google Cloud CLI. (Run with 'install-gcp' or 'install-cloud' flag to enable)"
fi

# Vercel CLI (added in v67; part of install-cloud)
if [[ "$FLAGS" =~ " install-vercel " ]]; then
    echo "Installing the Vercel CLI..."
    # Same rule as aws/az/gcloud: the CLI is machine-level (deploy, 'vercel link', 'vercel env pull'
    # to sync a project's variables into .env.local, 'vercel dev'); the AI SDK and AI Gateway
    # client stay per project. esbuild is the one dependency with an install script, allowed by
    # name for npm 12 (see the note in the Node section).
    npm install -g --allow-scripts=esbuild vercel
    vercel telemetry disable > /dev/null 2>&1 || true
    echo "vercel: $(vercel --version 2>/dev/null | tail -n 1)"
    echo "Log in with dev-init (install-vercel): 'vercel login', or VERCEL_TOKEN from secrets.env."
else
    echo "Skipping Vercel CLI. (Run with 'install-vercel' or 'install-cloud' flag to enable)"
fi

# Cloudflare's wrangler (added in v89; part of install-cloud)
if [[ "$FLAGS" =~ " install-cloudflare " ]]; then
    echo "Installing Cloudflare's wrangler..."
    # Global, on nvm's Node, next to the Vercel CLI: for 'wrangler login', 'wrangler whoami' and one-off
    # commands (d1, kv, r2, tail). Projects pin their own wrangler in package.json, and
    # @cloudflare/workers-types is per project too. 'wrangler dev' runs Workers locally in workerd with no
    # account; deploying needs CLOUDFLARE_API_TOKEN (and CLOUDFLARE_ACCOUNT_ID) or 'wrangler login'.
    # esbuild and workerd fetch their platform binaries in install scripts, allowed by name for npm 12.
    # Not fatal under set -e: the npm registry being unreachable leaves the rest of setup running.
    if npm install -g --allow-scripts=esbuild,workerd,sharp wrangler@latest; then
        wrangler telemetry disable > /dev/null 2>&1 || true
        echo "wrangler: $(wrangler --version 2> /dev/null | tail -n 1)"
    else
        echo "NOTICE: 'npm install -g wrangler' failed; rerun setup with install-cloudflare."
    fi
    echo "Log in with dev-init (install-cloudflare): CLOUDFLARE_API_TOKEN from secrets.env, or 'wrangler login'."
else
    echo "Skipping wrangler. (Run with 'install-cloudflare' or 'install-cloud' flag to enable)"
fi

# =================================================================
# install-cloudflared : Cloudflare Tunnel's connector (added in v89). Opt-in, in no group, NOT in install-all:
# a tunnel puts a local service on the public internet, and nothing here should do that unasked. Setup
# installs the command and never creates a tunnel. From Cloudflare's apt repository, keyed with the
# signing key Cloudflare rolled in October 2025 (the old key stopped working in April 2026); the suite is
# 'trixie' when the repository has it, else 'any', which Cloudflare's own instructions use.
#   cloudflared tunnel --url http://localhost:8080     a quick tunnel: a random trycloudflare.com URL, no
#                                                      account; anyone with the URL reaches the service
#   cloudflared tunnel login                           named tunnels on your own domain (an account)
# =================================================================
if [[ "$FLAGS" =~ " install-cloudflared " ]]; then
    echo "Installing cloudflared (Cloudflare Tunnel) from Cloudflare's apt repository..."
    CFD_SUITE=any
    curl -fsSI --max-time 20 https://pkg.cloudflare.com/cloudflared/dists/trixie/Release > /dev/null 2>&1 && CFD_SUITE=trixie
    CFD_KEY=$(mktemp)
    if curl -fsSL --retry 3 -o "$CFD_KEY" https://pkg.cloudflare.com/cloudflare-main.gpg; then
        sudo install -D -o root -g root -m 644 "$CFD_KEY" /usr/share/keyrings/cloudflare-main.gpg
        echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $CFD_SUITE main" \
            | sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
        if sudo apt update && sudo apt install -y cloudflared; then
            echo "cloudflared: $(cloudflared --version 2> /dev/null | head -n 1) (suite $CFD_SUITE)"
            echo "Quick tunnel: cloudflared tunnel --url http://localhost:<port>  (the URL it prints is public; Ctrl-C closes it)"
        else
            # Take the source out again: a repository apt cannot read would fail every later 'apt update'.
            sudo rm -f /etc/apt/sources.list.d/cloudflared.list
            echo "NOTICE: apt could not install cloudflared from pkg.cloudflare.com ($CFD_SUITE); rerun setup with install-cloudflared."
        fi
    else
        echo "NOTICE: could not download Cloudflare's signing key; rerun setup with install-cloudflared."
    fi
    rm -f "$CFD_KEY"
else
    echo "Skipping cloudflared. (Run with 'install-cloudflared'; opt-in, not part of install-all)"
fi

# Jev, TypeSafe AI's decision model (added in v67)
if [[ "$FLAGS" =~ " install-jev " ]]; then
    echo "Setting up for Jev (TypeSafe AI)..."
    # Jev is a hosted API: there is nothing to install on the machine. The SDKs are per-project
    # dependencies, like every other SDK in this bundle:
    #   Python 3.10+:  uv add typesafe-sdk        (pure-Python wheel; fine on the container's 3.14)
    #   Node 20+:      pnpm add @typesafe-ai/sdk
    #   via Vercel AI Gateway: pnpm add ai@latest  (AI SDK 7.0.105+, experimental_evaluate,
    #                  model 'typesafe-ai/jev', key in AI_GATEWAY_API_KEY)
    # Both TypeSafe SDKs read TYPESAFE_API_KEY. dev-init adds both key slots to secrets.env.
    # The one machine-level piece is TypeSafe's agent skill for Claude Code, which teaches the
    # agent the Choice / Score / Noul API and points it at the current docs and cookbooks.
    # Best effort: it needs 'claude' (install-node) and network access to GitHub.
    if command -v claude > /dev/null 2>&1; then
        if claude plugin marketplace add typesafe-ai/skills < /dev/null && claude plugin install typesafe@typesafe-ai < /dev/null; then
            echo "Installed the TypeSafe skill for Claude Code (invoke it with /typesafe:typesafe-ai)."
        else
            echo "NOTICE: could not install the TypeSafe Claude Code plugin. By hand:"
            echo "  claude plugin marketplace add typesafe-ai/skills && claude plugin install typesafe@typesafe-ai"
        fi
    else
        echo "NOTICE: 'claude' not found; skipping the TypeSafe Claude Code plugin."
    fi
    echo "Other agents (Codex, Gemini CLI, Cursor): run 'npx skills add typesafe-ai/skills --skill typesafe-ai' inside a project."
    echo "Keys: console.typesafe.ai (early access is waitlisted) or Vercel AI Gateway. Put them in secrets.env and run dev-init."
else
    echo "Skipping Jev setup. (Run with 'install-jev' flag to enable)"
fi

# =================================================================
# install-iac : Terraform + tflint, and Bicep when the Azure CLI is present
# (added in v57). Independent of install-cloud; ordered after it so an
# install-all run has 'az' available for the Bicep step.
# =================================================================
if [[ "$FLAGS" =~ " install-iac " ]]; then
    echo "Installing Infrastructure-as-Code tools..."
    # Terraform comes from HashiCorp's tap: homebrew-core froze 'terraform' at 1.5.7 after the
    # BSL license change. Substitute 'brew install opentofu' (drop-in 'tofu' command) for
    # clients that require an OSI-approved license.
    brew tap hashicorp/tap
    brew install hashicorp/tap/terraform
    # v61: tflint is no longer in homebrew-core and upstream's own tap is macOS-only, so on Linux
    # install the release binary and verify it against the published checksums. 'latest' means a
    # rerun upgrades in place. dpkg's arch names (amd64 / arm64) match the release asset names.
    TFLINT_ARCH="$(dpkg --print-architecture)"
    TFLINT_TMP="$(mktemp -d)"
    TFLINT_URL="https://github.com/terraform-linters/tflint/releases/latest/download"
    curl -fsSL -o "$TFLINT_TMP/tflint_linux_${TFLINT_ARCH}.zip" "$TFLINT_URL/tflint_linux_${TFLINT_ARCH}.zip"
    curl -fsSL -o "$TFLINT_TMP/checksums.txt" "$TFLINT_URL/checksums.txt"
    (cd "$TFLINT_TMP" && sha256sum --ignore-missing -c checksums.txt)
    unzip -oq "$TFLINT_TMP/tflint_linux_${TFLINT_ARCH}.zip" -d "$TFLINT_TMP"
    sudo install -m 0755 "$TFLINT_TMP/tflint" /usr/local/bin/tflint
    rm -rf "$TFLINT_TMP"
    echo "Terraform: $(terraform version | head -n 1)"
    echo "tflint: $(tflint --version | head -n 1)"
    if command -v az > /dev/null 2>&1; then
        echo "Azure CLI detected; installing Bicep (into ~/.azure/bin, used via 'az bicep')..."
        az bicep install
    else
        echo "Azure CLI not present; skipping Bicep. (Add 'install-azure' to get it.)"
    fi
else
    echo "Skipping IaC tools. (Run with 'install-iac' flag to enable)"
fi

# =================================================================
# install-ansible-full / install-ansible-core : Ansible (added in v76)
# install-ansible-full comes with install-iac (so install-all); install-ansible-core is the lean,
# standalone option. One pipx venv named 'ansible-core' on Debian's Python (same rule as
# make_venv), holding:
#   both : ansible-core (ansible, ansible-playbook, ansible-galaxy, ansible-vault...),
#          ansible-lint, molecule, and the Docker SDK for Python, which brings the 'requests'
#          library community.docker's modules need (Molecule's create/destroy playbooks)
#   core : + community.docker from Galaxy into ~/.ansible/collections (~85 MB venv in all)
#   full : + the 'ansible' community package injected: ~100 collections bundled, including
#          community.docker and kubernetes.core, and 'ansible-community' (~520 MB venv in all)
# Full includes core, so a core-only run on a machine that has full keeps it; go lean by hand
# with 'pipx uninject ansible-core ansible'. Collections in ~/.ansible/collections take precedence
# over the bundled copies. Update by rerunning setup, not 'pipx upgrade-all': that upgrades
# ansible-core alone, past the version the 'ansible' package pins (dev-test's 'pip check' flags it).
# This container is the control node; targets are Docker containers
# (community.docker.docker connection, nothing to set up), kind clusters (kubernetes.core, full)
# and SSH hosts, reached with the base section's ~/.ssh/id_ed25519.
# =================================================================
if [[ "$FLAGS" =~ " install-ansible-full " ]] || [[ "$FLAGS" =~ " install-ansible-core " ]]; then
    ANSIBLE_MODE=core
    [[ "$FLAGS" =~ " install-ansible-full " ]] && ANSIBLE_MODE=full
    echo "Installing Ansible ($ANSIBLE_MODE)..."
    # A venv named 'ansible' (the manual 'pipx install --include-deps ansible' route) owns the same
    # commands, so pipx would refuse to link them from this venv. Replace it.
    if pipx list --short 2> /dev/null | grep -q '^ansible '; then
        echo "NOTICE: replacing the pipx venv 'ansible' (a manual install) with the bundle's 'ansible-core' venv."
        pipx uninstall ansible
    fi
    ANSIBLE_PKGS=(ansible-core ansible-lint molecule docker)
    if pipx list --short 2> /dev/null | grep -q '^ansible-core '; then
        # Rerun: upgrade everything already in the venv in ONE resolve, the full package included
        # when present, so ansible-core never moves past what the 'ansible' package pins.
        pipx runpip ansible-core show ansible > /dev/null 2>&1 && ANSIBLE_PKGS+=(ansible)
        pipx runpip ansible-core install -q --upgrade "${ANSIBLE_PKGS[@]}"
    else
        pipx install --python /usr/bin/python3 ansible-core
    fi
    pipx inject --include-apps ansible-core ansible-lint molecule
    pipx inject ansible-core docker     # a library with no commands: --include-apps would refuse it
    if [ "$ANSIBLE_MODE" = full ]; then
        pipx inject --include-apps ansible-core ansible
        # A community.docker left in ~/.ansible/collections by an earlier core install shadows the
        # bundled copy, so keep it current too (best effort: Galaxy being down must not stop setup).
        if [ -d ~/.ansible/collections/ansible_collections/community/docker ]; then
            ansible-galaxy collection install --upgrade community.docker \
                || echo "NOTICE: could not refresh ~/.ansible/collections' community.docker from Galaxy; it shadows the bundled copy."
        fi
    elif pipx runpip ansible-core show ansible > /dev/null 2>&1; then
        echo "The full Ansible package is already in the venv (install-iac): keeping it, it includes core."
    else
        ansible-galaxy collection install --upgrade community.docker
    fi
    # Captured whole: 'ansible --version | head -n 1' makes Ansible print a BrokenPipe traceback.
    ANSIBLE_VERSION_TEXT=$(ansible --version 2>&1) || true
    echo "ansible: ${ANSIBLE_VERSION_TEXT%%$'\n'*}"
    [ "$ANSIBLE_MODE" = full ] && echo "$(ansible-community --version)"
    echo "Docker containers need no setup as targets; for SSH hosts: ssh-copy-id -i ~/.ssh/id_ed25519.pub user@host"
else
    echo "Skipping Ansible. (install-ansible-full comes with install-iac; install-ansible-core is the lean, standalone option)"
fi

# =================================================================
# install-k8s : kubectl, helm, kind, k9s (added in v58)
# kind runs its cluster in the Docker from the base section, so the docker group from
# there is what makes 'kind create cluster' work in a fresh terminal. Cluster credentials
# are per cluster (kind writes ~/.kube/config; EKS/AKS/GKE via the install-cloud CLIs).
# v60: kind VERIFIED inside Crostini (Docker 29.8.1, kind v0.33.0, kindest/node v1.37.0): the
#      test script's cluster round-trip passed on an 8GB Chromebook in 50s including the ~1GB
#      node-image pull, control-plane Ready after 17s, with 1.8GiB 'available' beforehand.
#      RAM note for every '8GB' figure in this script: the Linux VM only sees ~6.4GB of it, and
#      'free' reports crosvm's memory balloon as 'used', so judge headroom by the 'available'
#      column, not 'free' or 'used'.
# =================================================================
if [[ "$FLAGS" =~ " install-k8s " ]]; then
    echo "Installing Kubernetes tooling (kubectl, helm, kind, k9s)..."
    brew install kubectl helm kind k9s
    # v74: completion is generated once into bash-completion's per-user directory (loaded on demand,
    # like terminus and acli) instead of 'source <(kubectl completion bash)' in ~/.bashrc, which runs
    # kubectl in every new shell and printed "kubectl: command not found" once the Homebrew block
    # sat below it. The 'k' alias gets its own copy that also registers 'k'. Old lines are removed.
    mkdir -p ~/.local/share/bash-completion/completions
    KUBECTL_BIN=$(command -v kubectl || echo /home/linuxbrew/.linuxbrew/bin/kubectl)
    if "$KUBECTL_BIN" completion bash > ~/.local/share/bash-completion/completions/kubectl 2> /dev/null; then
        { cat ~/.local/share/bash-completion/completions/kubectl; echo 'complete -o default -F __start_kubectl k'; } > ~/.local/share/bash-completion/completions/k
    else
        rm -f ~/.local/share/bash-completion/completions/kubectl
    fi
    sed -i '\|^source <(kubectl completion bash)$|d; \|^alias k=kubectl && complete -o default -F __start_kubectl k$|d' ~/.bashrc
    grep -qx 'alias k=kubectl' ~/.bashrc || echo 'alias k=kubectl' >> ~/.bashrc
    echo "kubectl: $(kubectl version --client 2>/dev/null | head -n 1)"
    echo "helm: $(helm version --short 2>/dev/null)   kind: $(kind version 2>/dev/null)"
    echo "A kind cluster takes ~2GB RAM: stop Ollama models ('ollama stop <model>') before 'kind create cluster'."
else
    echo "Skipping Kubernetes tooling. (Run with 'install-k8s' flag to enable)"
fi

# =================================================================
# install-lan / install-lan-share : your laptops on the home network (added in v84)
# Opt-in, in no group, NOT in install-all: nothing opens up unless you ask for it.
# Every service this bundle installs listens on 127.0.0.1 inside this Linux, and ChromeOS forwards
# nothing from your network into it on its own. These two flags cover both directions:
#   install-lan        USING the other laptops. An address book, LAN_HOSTS in dev-init's secrets.env
#                      ("tigerlake=192.168.1.21 winlaptop=192.168.1.33 ..."), written into a marked
#                      block of /etc/hosts, so every tool takes the names: sqlcmd -S winlaptop,
#                      OLLAMA_REMOTE=winlaptop, curl http://joxer:11434. This machine's own name
#                      (LAN_SELF, default MACHINE_LABEL) maps to 127.0.0.1, so one list serves every
#                      laptop. Plus the 'lan' command in ~/.local/bin: lan hosts / scan / url / ollama
#                      / mcp / site / share ('lan help'). Give each laptop a fixed address first: a
#                      DHCP reservation per laptop on your router.
#   install-lan-share  SERVING the others, and includes install-lan. LAN_SHARE in secrets.env picks
#                      what this machine shares, from: ollama mssql oracle ldap ddev dev mcp, and since
#                      v89 the shared services redis solr opensearch elasticsearch meilisearch typesense
#                      qdrant mongodb (empty = nothing). A relay, dev-lan-relay.service (Python standard library, running as
#                      you), listens on this Linux's own network address and passes connections on to
#                      127.0.0.1, so the services themselves never change (no container is recreated,
#                      no database moves) and 'lan share off' closes every relayed port at once.
#                      Ports on the network, the same on every laptop and all above 1024:
#                        ollama 11434  mssql 1433  oracle 1521  ldap: lldap 3890 + web UI 17170 and
#                        OpenLDAP 1389 (-> 389)  ddev: 8080 and 8443 (-> DDEV's router on 80 / 443)
#                        v89: redis 6379  solr 8983  opensearch 9200  elasticsearch 9201  meilisearch
#                        7700  typesense 8108  qdrant 6333 + 6334  mongodb 27017. Only with a login: redis
#                        needs REDIS_PASSWORD, qdrant QDRANT_API_KEY and mongodb MONGO_ROOT_PASSWORD (set
#                        in secrets.env and applied by a setup run); the search engines always have one.
#                        Memcached, Milvus, Atlas Local and (v91) the Selenium Grid have no login and are
#                        never shared.
#                      dev and mcp are not relayed: Vite, Angular, Next and the MCP SDK refuse requests
#                      addressed to anything but localhost while they listen on 127.0.0.1, so those
#                      servers listen on the network themselves (vite --host, ng serve --host 0.0.0.0,
#                      next dev -H 0.0.0.0, MCPServer.run(host="0.0.0.0")); LAN_DEV_PORTS (default
#                      3000 4200 5173) and LAN_MCP_PORTS (default 8770; v89: 8000 is
#                      left to php artisan serve and symfony serve) list their ports.
#                      One step stays manual on each Chromebook, because it lives outside Linux:
#                      ChromeOS Settings > Advanced > Developers > Linux > Port forwarding, one entry
#                      per port. 'lan share ports' lists them, and dev-init keeps each relayed port on
#                      its to-do list until a connection from another laptop has come through it.
# No login on Ollama, the demo sites' admin/admin: anyone on the same Wi-Fi reaches a forwarded port.
# Fine at home; elsewhere 'lan share off' (or switch the forwards off in ChromeOS).
# A guest network or a router with client isolation keeps laptops apart whatever these scripts do;
# 'lan scan' from another laptop shows it.
# The Windows laptops' side (WSL mirrored networking, firewall rules) belongs to the Windows bundle.
# v93: over Tailscale. Since ChromeOS 147, new Linux installs on these Chromebooks run as a full VM (Debian
# trixie, "Baguette") with no Linux port forwarding in ChromeOS, so the v84 relay + forwards cannot work
# there (found Oct 5 2026). install-lan now also installs Tailscale from Tailscale's own apt repository
# for this Debian (the same keyring and list its install.sh writes) and sets normal mode,
# FLAGS="--tun=tailscale0" in /etc/default/tailscaled: in this VM tailscaled chose userspace networking by
# itself, where no tailscale0 exists and Linux tools cannot reach the 100.x addresses. Setup never joins the
# tailnet (that is a login): dev-init with install-lan runs 'sudo tailscale up --operator=$USER
# --hostname=NAME' (TAILSCALE_AUTHKEY in secrets.env joins without a browser). LAN_HOSTS then holds the
# 100.x addresses; install-lan-share publishes LAN_SHARE with 'tailscale serve' and stops the relay; the
# 'lan' command adds NAME.internal names (Ollama refuses a plain laptop name as Host) and 'lan probe' /
# 'lan path'. Only laptops on your tailnet reach the shared ports. LAN_TAILSCALE=0 in secrets.env keeps
# the v84 relay and ChromeOS forwards, and installs no Tailscale.
# =================================================================
if [[ "$FLAGS" =~ " install-lan " ]]; then
    echo "================================================================="
    echo "Setting up the laptop network (install-lan$([[ "$FLAGS" =~ " install-lan-share " ]] && echo " + install-lan-share"))..."
    echo "================================================================="
    # iproute2 (ip, ss) is part of a standard Debian install; named so a trimmed container gets it back.
    sudo apt install -y iproute2
    mkdir -p "$HOME/.local/bin"
    # v93: Tailscale in normal mode (see above). A failure is a NOTICE: the address book and the relay mode
    # work without it.
    LAN_TS=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${LAN_TAILSCALE:-1}"' _ "$HOME/.config/dev-init/secrets.env" 2> /dev/null || echo 1)
    LAN_TS=${LAN_TAILSCALE:-${LAN_TS:-1}}
    if [ "$LAN_TS" = 0 ]; then
        echo "LAN_TAILSCALE=0: no Tailscale; the laptops use the v84 relay and ChromeOS port forwarding."
    else
        if ! command -v tailscale > /dev/null 2>&1; then
            TS_CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-trixie}")
            echo "Installing Tailscale from pkgs.tailscale.com (debian/$TS_CODENAME)..."
            if curl -fsSL --max-time 60 "https://pkgs.tailscale.com/stable/debian/$TS_CODENAME.noarmor.gpg" -o /tmp/tailscale-keyring.gpg \
                && curl -fsSL --max-time 60 "https://pkgs.tailscale.com/stable/debian/$TS_CODENAME.tailscale-keyring.list" -o /tmp/tailscale.list; then
                sudo install -m 644 /tmp/tailscale-keyring.gpg /usr/share/keyrings/tailscale-archive-keyring.gpg
                sudo install -m 644 /tmp/tailscale.list /etc/apt/sources.list.d/tailscale.list
                sudo apt update > /dev/null 2>&1 || true
                sudo DEBIAN_FRONTEND=noninteractive apt install -y tailscale \
                    || echo "NOTICE: apt could not install tailscale; 'curl -fsSL https://tailscale.com/install.sh | sh' is Tailscale's own route."
            else
                echo "NOTICE: pkgs.tailscale.com did not answer; rerun setup with install-lan to install Tailscale."
            fi
            rm -f /tmp/tailscale-keyring.gpg /tmp/tailscale.list
        fi
        if command -v tailscale > /dev/null 2>&1; then
            # Normal mode: the tailscale0 interface, so every Linux tool reaches the other laptops' 100.x addresses.
            TS_DEFAULTS=/etc/default/tailscaled
            if ! grep -q '^FLAGS=.*--tun=tailscale0' "$TS_DEFAULTS" 2> /dev/null; then
                if grep -q '^FLAGS=' "$TS_DEFAULTS" 2> /dev/null; then
                    sudo sed -i 's/^FLAGS=.*/FLAGS="--tun=tailscale0"/' "$TS_DEFAULTS"
                else
                    echo 'FLAGS="--tun=tailscale0"' | sudo tee -a "$TS_DEFAULTS" > /dev/null
                fi
                echo "Tailscale: normal mode set (FLAGS=\"--tun=tailscale0\" in $TS_DEFAULTS); restarting tailscaled."
                sudo systemctl restart tailscaled 2> /dev/null || true
                sleep 2
            fi
            sudo systemctl enable --now tailscaled > /dev/null 2>&1 || true
            if ip link show tailscale0 > /dev/null 2>&1; then
                echo "Tailscale $(tailscale version 2> /dev/null | head -n 1): tailscale0 is up; $(tailscale status --json 2> /dev/null | jq -r '.BackendState // "?"' 2> /dev/null || echo '?')."
            else
                echo "NOTICE: no tailscale0 interface yet ('journalctl -u tailscaled' says why); /dev/net/tun: $(ls -l /dev/net/tun 2>&1 | cut -c1-40)."
            fi
            echo "Joining your tailnet is dev-init's step (install-lan): it runs 'sudo tailscale up --operator=\$USER --hostname=<this laptop>'."
        fi
    fi
    cat > "$HOME/.local/bin/lan" << 'EOF_DEV_LAN'
#!/bin/bash
# lan - your laptops on the home network. Written by dev-setup (install-lan, v84; v93: over Tailscale);
# rewritten on each run.
#
#   lan                          this machine: its name, address book, what it shares
#   lan hosts                    the address book (LAN_HOSTS) and whether /etc/hosts has it
#   lan hosts apply              write the address book into /etc/hosts, so every tool takes the names
#                                (v93: each laptop also as NAME.internal, the name Ollama accepts)
#   lan ip NAME                  a laptop's address
#   lan scan [NAME...]           which service ports accept a connection on each laptop (default: every other)
#   lan probe NAME [PORT...]     v93: whether each service there really answers, in its own protocol: a port
#                                that accepts while its service is stopped ('tailscale serve' does that) shows
#                                as down, and Ollama refusing a Host name as forbidden
#   lan path [NAME...]           v93: whether Tailscale reaches each laptop directly or through a DERP relay
#   lan url NAME [SERVICE]       how to reach a service there: ollama mssql oracle ldap ddev dev mcp,
#                                and the devsvc services (redis solr opensearch elasticsearch meilisearch
#                                typesense qdrant mongodb)
#   lan ollama NAME ARGS...      the ollama CLI against NAME's server:  lan ollama winlaptop list
#   lan mcp NAME [PORT] [ID]     add NAME's MCP server (http://NAME:PORT/mcp) to Claude Code
#   lan site NAME SITE           reach NAME's DDEV site SITE from here (/etc/hosts); 'lan site' lists them,
#                                'lan site --remove SITE' drops one
#   lan share [status]           what this machine shares, and whether each service is up
#   lan share ports              the ports this machine publishes (over Tailscale), or, in relay mode,
#                                the ones to add in ChromeOS port forwarding
#   lan share apply              reread LAN_SHARE & co from secrets.env and publish them ('tailscale serve';
#                                in relay mode: restart the relay)
#   lan share on | off           start or stop sharing (off closes every shared port at once)
#
# v93: the transport. Linux on these Chromebooks now runs as a full VM with no ChromeOS port forwarding, so
# the laptops reach each other over Tailscale (normal mode, the tailscale0 interface; dev-setup installs it
# and dev-init joins the laptop to your tailnet). LAN_HOSTS then holds the 100.x Tailscale addresses, and
# 'lan share apply' publishes each shared port with 'tailscale serve --bg --tcp=PORT tcp://localhost:PORT';
# the v84 relay is stopped. LAN_TAILSCALE=0 in secrets.env keeps the v84 way (the relay plus ChromeOS port
# forwards), for a ChromeOS that still forwards ports. Ports you publish by hand with 'tailscale serve' are
# left alone: 'lan' only removes ports it published itself (~/.config/dev-lan/served.tsv).
#
# Settings live in ~/.config/dev-init/secrets.env (not exported; this command reads the file):
#   LAN_HOSTS="tigerlake=192.168.1.21 winlaptop=192.168.1.33 ..."   the same list on every laptop
#   LAN_SELF   this machine's name in LAN_HOSTS (default MACHINE_LABEL); it maps to 127.0.0.1 here
#   LAN_SHARE  what this machine shares (install-lan-share): ollama mssql oracle ldap ddev dev mcp
#              redis solr opensearch elasticsearch meilisearch typesense qdrant mongodb
#   LAN_DEV_PORTS (default "3000 4200 5173"), LAN_MCP_PORTS (default "8770"; 8000 is php artisan serve's and symfony serve's),
#   LAN_EXTRA  more ports to share, as LANPORT or LANPORT:LOCALPORT
#   LAN_TAILSCALE  1 (default: share and connect over Tailscale when it is installed) or 0 (the v84 relay)
# A value in the environment wins over the file, e.g.  LAN_SHARE="ollama" lan share plan
# Host names: Ollama listening on 127.0.0.1 refuses a request whose Host is a plain laptop name (403 with
# an empty body) but accepts an address or a name ending in .internal, so other laptops use
# http://NAME.internal:11434 (or the address). DDEV routes by site name: 'lan site NAME SITE' maps it.
#
# Ports on the network, the same on every laptop so 'lan scan' knows what it finds. All are above 1024,
# away from the ports ChromeOS treats as privileged:
#   ollama 11434   mssql 1433   oracle 1521   ldap: lldap 3890 + web UI 17170, OpenLDAP 1389 (-> 389)
#   ddev 8080 (-> DDEV's router, 80) and 8443 (-> 443)   dev: LAN_DEV_PORTS   mcp: LAN_MCP_PORTS
#   redis 6379   solr 8983   opensearch 9200   elasticsearch 9201   meilisearch 7700   typesense 8108
#   qdrant 6333 (REST) + 6334 (gRPC)   mongodb 27017
# A devsvc service is shared only with a login: redis needs REDIS_PASSWORD, qdrant QDRANT_API_KEY and
# mongodb MONGO_ROOT_PASSWORD in secrets.env, applied by a dev-setup run (devsvc.env then holds them);
# the search engines always have one. memcached, milvus, atlas-local and (v91) selenium have none and are
# never shared.
# ollama mssql oracle ldap ddev, the devsvc services and LAN_EXTRA go through the relay (dev-lan-relay.service): the service
# keeps listening on 127.0.0.1 and the relay passes connections through from this Linux's network
# address. dev and mcp servers must listen on the network themselves (vite --host, ng serve --host
# 0.0.0.0, next dev -H 0.0.0.0, FastMCP(host="0.0.0.0")): they refuse requests addressed to anything
# but localhost when they run on 127.0.0.1, which a pass-through cannot fix.

set -o pipefail
SECRETS="$HOME/.config/dev-init/secrets.env"
RELAY_TSV="$HOME/.config/dev-lan/relay.tsv"
SERVED_TSV="$HOME/.config/dev-lan/served.tsv"      # v93: the ports 'lan' published with 'tailscale serve'
SHARE_OFF="$HOME/.config/dev-lan/sharing-off"      # v93: 'lan share off' in Tailscale mode
STATE_DIR="$HOME/.local/state/dev-lan"
RELAY_PY="$HOME/.local/lib/dev-lan/lan-relay.py"
UNIT=dev-lan-relay.service
if [ -t 1 ]; then G=$'\e[32m' Y=$'\e[33m' D=$'\e[2m' B=$'\e[1m' R=$'\e[0m'; else G=; Y=; D=; B=; R=; fi

die() { echo "lan: $*" >&2; exit 1; }

# The settings, read once from secrets.env in a subshell (nothing else from the file comes along).
LAN_KEYS="LAN_HOSTS LAN_SELF LAN_SHARE LAN_DEV_PORTS LAN_MCP_PORTS LAN_EXTRA LAN_TAILSCALE MACHINE_LABEL"
if [ -r "$SECRETS" ]; then
    eval "$(bash -c '. "$1" > /dev/null 2>&1; for k in $2; do printf "_F_%s=%q\n" "$k" "${!k:-}"; done' _ "$SECRETS" "$LAN_KEYS" 2> /dev/null)"
fi
# cfg NAME [DEFAULT]: the environment's value, else secrets.env's, else DEFAULT
cfg() {
    local f="_F_$1" v="${!1:-}"
    v=${v:-${!f:-}}
    printf '%s' "${v:-${2:-}}"
}

# The address book, parsed once: HOST_LIST holds "name ip" lines, HOST_BAD the entries skipped.
HOST_LIST=""; HOST_BAD=""
for _e in $(printf '%s' "${LAN_HOSTS:-${_F_LAN_HOSTS:-}}" | tr ',;' '  '); do
    _n=${_e%%=*}; _i=${_e#*=}
    if [ "$_n" = "$_e" ] || ! [[ "$_n" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || ! [[ "$_i" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        HOST_BAD+="$_e "; continue
    fi
    HOST_LIST+="$_n $_i"$'\n'
done
unset _e _n _i
hosts() { printf '%s' "$HOST_LIST"; }
bad_hosts_note() { [ -z "$HOST_BAD" ] || echo "${Y}LAN_HOSTS entries skipped (want name=address):${R} $HOST_BAD" >&2; }
self_name() { cfg LAN_SELF "$(cfg MACHINE_LABEL)"; }

# ip_of NAME: the address to use from here (this machine's own name is 127.0.0.1)
ip_of() {
    local n=$1 line
    [[ "$n" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && { echo "$n"; return 0; }
    [ -n "$(self_name)" ] && [ "$n" = "$(self_name)" ] && { echo 127.0.0.1; return 0; }
    line=$(hosts 2> /dev/null | awk -v n="$n" '$1 == n { print $2; exit }')
    [ -n "$line" ] && { echo "$line"; return 0; }
    line=$(getent ahostsv4 "$n" 2> /dev/null | awk '{ print $1; exit }')
    [ -n "$line" ] && { echo "$line"; return 0; }
    return 1
}
need_ip() { ip_of "$1" || die "'$1' is not in LAN_HOSTS ($SECRETS) and does not resolve"; }

# this Linux's own network addresses (what ChromeOS port forwarding delivers to), bridges left out
linux_addrs() {
    ip -4 -o addr show 2> /dev/null | awk '$2 !~ /^(lo|docker|br-|veth|virbr|cni|flannel|kube|tailscale|wg)/ { split($4, a, "/"); print a[1] }'
}

port_open() { timeout 2 bash -c 'exec 3<> "/dev/tcp/$0/$1"' "$1" "$2" 2> /dev/null; }   # port_open IP PORT

# --- v93: Tailscale ---------------------------------------------------------------------------------
ts_mode() { [ "$(cfg LAN_TAILSCALE 1)" != 0 ] && command -v tailscale > /dev/null 2>&1; }
ts_json() { timeout 10 tailscale status --json 2> /dev/null; }
ts_state() { ts_json | jq -r '.BackendState // "unknown"' 2> /dev/null || echo unknown; }   # Running, NeedsLogin, Stopped...
ts_ip() { timeout 10 tailscale ip -4 2> /dev/null | head -n 1; }
ts_tun() { ip -4 -o addr show dev tailscale0 2> /dev/null | awk '{ split($4, a, "/"); print a[1]; exit }'; }   # empty: userspace mode
# 'tailscale serve' changes: as the operator dev-init set (tailscale up --operator=$USER), else through sudo.
ts_admin() { timeout 30 tailscale "$@" > /dev/null 2>&1 || timeout 30 sudo tailscale "$@" > /dev/null 2>&1; }
ts_served() { timeout 10 tailscale serve status --json 2> /dev/null | jq -r '.TCP // {} | keys[]' 2> /dev/null | sort -n; }   # TCP ports published now
ts_target() { timeout 10 tailscale serve status --json 2> /dev/null | jq -r --arg p "$1" '.TCP[$p] // {} | .TCPForward // empty' 2> /dev/null; }
ts_off() { ts_admin serve --bg --tcp="$1" "tcp://localhost:$2" off || ts_admin serve --tcp="$1" "tcp://localhost:$2" off; }   # ts_off LAN_PORT LOCAL_PORT

words() { tr ',;' '  ' <<< "$1"; }
dev_ports() { words "$(cfg LAN_DEV_PORTS "3000 4200 5173")"; }
mcp_ports() { words "$(cfg LAN_MCP_PORTS 8770)"; }

ddev_router_port() {   # ddev_router_port http|https: DDEV's router port on this machine (80 / 443 unless changed)
    local v
    v=$(sed -n "s/^router_$1_port:[[:space:]]*\"\{0,1\}\([0-9]*\)\"\{0,1\}.*/\1/p" "$HOME/.ddev/global_config.yaml" 2> /dev/null | head -n 1)
    if [ -n "$v" ]; then echo "$v"; elif [ "$1" = http ]; then echo 80; else echo 443; fi
}

# plan: the relay's config for this machine, as TSV "LAN_PORT LOCAL_PORT LABEL" (stdout); notes on stderr
plan() {
    local s p lan lp
    for s in $(words "$(cfg LAN_SHARE)"); do
        case "$s" in
            ollama) printf '11434\t11434\tOllama\n' ;;
            mssql)  printf '1433\t1433\tSQL Server\n' ;;
            oracle) printf '1521\t1521\tOracle (FREEPDB1)\n' ;;
            ldap)   printf '3890\t3890\tlldap (LDAP)\n17170\t17170\tlldap web UI\n'
                    if [ -x /usr/sbin/slapd ]; then printf '1389\t389\tOpenLDAP (slapd)\n'
                    else echo "lan: ldap: OpenLDAP (install-ldap-full) is not installed; sharing lldap only" >&2; fi ;;
            ddev)   printf '8080\t%s\tDDEV sites (http)\n8443\t%s\tDDEV sites (https)\n' "$(ddev_router_port http)" "$(ddev_router_port https)" ;;
            dev|mcp) ;;   # not relayed: those servers listen on the network themselves
            # v89: the shared services of devsvc. The search engines always require their login.
            redis)  needs_login redis REDIS_PASSWORD 6379 "Redis (password)" ;;
            qdrant) needs_login qdrant QDRANT_API_KEY "6333 6334" "Qdrant (API key)" ;;
            mongodb) needs_login mongodb MONGO_ROOT_PASSWORD 27017 "MongoDB (user root)" ;;
            solr)        printf '8983\t8983\tSolr (user solr)\n' ;;
            opensearch)  printf '9200\t9200\tOpenSearch (user admin)\n' ;;
            elasticsearch) printf '9201\t9201\tElasticsearch (user elastic)\n' ;;
            meilisearch) printf '7700\t7700\tMeilisearch (master key)\n' ;;
            typesense)   printf '8108\t8108\tTypesense (API key)\n' ;;
            memcached|milvus|atlas-local|selenium)
                    echo "lan: $s is never shared: it has no login, so anyone on the Wi-Fi could use it" >&2 ;;
            *) echo "lan: unknown service '$s' in LAN_SHARE (known: $KNOWN)" >&2 ;;
        esac
    done
    for p in $(words "$(cfg LAN_EXTRA)"); do
        lan=${p%%:*}; lp=${p#*:}
        [[ "$lan" =~ ^[0-9]+$ && "$lp" =~ ^[0-9]+$ ]] || { echo "lan: ignoring '$p' in LAN_EXTRA (want LANPORT or LANPORT:LOCALPORT)" >&2; continue; }
        [ "$lan" -ge 1024 ] || echo "lan: LAN_EXTRA port $lan is below 1024; ChromeOS may not forward it" >&2
        printf '%s\t%s\tLAN_EXTRA\n' "$lan" "$lp"
    done
}
shares() { [[ " $(words "$(cfg LAN_SHARE)") " == *" $1 "* ]]; }
KNOWN="ollama mssql oracle ldap ddev dev mcp redis solr opensearch elasticsearch meilisearch typesense qdrant mongodb"
# svc_key NAME: a login of the shared services (v89), from ~/.config/devsvc/devsvc.env, which dev-setup writes
svc_key() {
    [ -r "$HOME/.config/devsvc/devsvc.env" ] || return 0
    bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$HOME/.config/devsvc/devsvc.env" "$1"
}
# needs_login NAME KEY PORTS LABEL: share a devsvc service only when it has its login (TSV lines on stdout)
needs_login() {
    local n=$1 k=$2 ports=$3 label=$4 pt
    if [ -z "$(svc_key "$k")" ]; then
        echo "lan: $n: not shared, because it has no login: set $k in secrets.env, rerun dev-setup with install-$n, then 'lan share apply'" >&2
        return 0
    fi
    for pt in $ports; do printf '%s\t%s\t%s\n' "$pt" "$pt" "$label"; done
}

# direct_ports: "PORT LABEL" for the dev and mcp servers this machine shares
direct_ports() {
    local p
    if shares dev; then for p in $(dev_ports); do echo "$p dev-server"; done; fi
    if shares mcp; then for p in $(mcp_ports); do echo "$p MCP-server"; done; fi
}

# listen_scope PORT: where a local server on PORT listens: network | local | none
listen_scope() {
    local l
    l=$(ss -Htln "sport = :$1" 2> /dev/null | awk '{ print $4 }')
    [ -n "$l" ] || { echo none; return; }
    if grep -qE '^(0\.0\.0\.0|\*|\[::\]|::):' <<< "$l"; then echo network
    elif grep -qvE '^(127\.|\[::1\]|::1:|\[::ffff:127\.)' <<< "$l"; then echo network
    else echo local; fi
}

# scan_ports: "PORT SERVICE" pairs to probe on another laptop
scan_ports() {
    printf '%s\n' "11434 ollama" "1433 mssql" "1521 oracle" "3890 lldap" "17170 lldap-ui" "1389 openldap" "8080 ddev-http" "8443 ddev-https" \
        "6379 redis" "8983 solr" "9200 opensearch" "9201 elasticsearch" "7700 meilisearch" "8108 typesense" "6333 qdrant" "27017 mongodb"
    local p
    for p in $(dev_ports); do echo "$p dev:$p"; done
    for p in $(mcp_ports); do echo "$p mcp:$p"; done
    for p in $(words "$(cfg LAN_EXTRA)"); do [[ "${p%%:*}" =~ ^[0-9]+$ ]] && echo "${p%%:*} extra:${p%%:*}"; done
}

cmd_scan() {
    local names=() n ip tmp found port svc brief=0 any=0
    [ "${1:-}" = --brief ] && { brief=1; shift; }
    if [ $# -gt 0 ]; then names=("$@")
    else
        bad_hosts_note
        while read -r n _; do [ "$n" = "$(self_name)" ] || names+=("$n"); done < <(hosts)
        [ ${#names[@]} -gt 0 ] || die "no other laptops in LAN_HOSTS ($SECRETS)"
    fi
    tmp=$(mktemp -d)
    for n in "${names[@]}"; do
        ip=$(ip_of "$n") || { echo "$n: not in LAN_HOSTS and does not resolve"; continue; }
        mkdir -p "$tmp/$n"
        while read -r port svc; do
            ( port_open "$ip" "$port" && echo "$svc" > "$tmp/$n/$port" ) &
        done < <(scan_ports)
    done
    wait
    for n in "${names[@]}"; do
        [ -d "$tmp/$n" ] || continue
        ip=$(ip_of "$n")
        found=$(cat "$tmp/$n"/* 2> /dev/null | sort | tr '\n' ' ')
        if [ -n "$found" ]; then
            any=1
            printf '%s%-14s%s %-15s %s\n' "$G" "$n" "$R" "$ip" "$found"
        else
            printf '%s%-14s%s %-15s %s\n' "$Y" "$n" "$R" "$ip" "${D}nothing answering (off, asleep, sharing nothing, not on your tailnet, or a Wi-Fi that keeps laptops apart)${R}"
        fi
    done
    rm -rf "$tmp"
    [ "$brief" = 1 ] || echo "${D}Checked: $(scan_ports | awk '{ print $2 }' | tr '\n' ' ')${R}"
    [ "$any" = 1 ]
}

cmd_hosts() {
    local want have self n ip
    self=$(self_name)
    want=$(hosts_block)
    if [ "${1:-}" = apply ]; then
        [ -n "$(hosts)" ] || { echo "LAN_HOSTS is empty in $SECRETS: nothing to write."; want=""; }
        write_etc_hosts "dev-lan hosts" "$want"
        [ -n "$want" ] && echo "/etc/hosts now has the address book ($(hosts | wc -l) laptops)."
        return 0
    fi
    if [ "${1:-}" = check ]; then   # exit 0 when /etc/hosts matches LAN_HOSTS
        have=$(sed -n '/^# >>> dev-lan hosts >>>$/,/^# <<< dev-lan hosts <<<$/p' /etc/hosts | sed '1d;$d' | grep -v '^#')
        [ "$have" = "$(grep -v '^#' <<< "$want")" ]
        return
    fi
    bad_hosts_note
    [ -n "$(hosts)" ] || { echo "The address book is empty: set LAN_HOSTS in $SECRETS (name=address ...), then 'lan hosts apply'."; return 1; }
    while read -r n ip; do
        if [ "$n" = "$self" ]; then printf '%-14s %-15s %s\n' "$n" "$ip" "${D}this machine (127.0.0.1 from here)${R}"
        else printf '%-14s %-15s\n' "$n" "$ip"; fi
    done < <(hosts)
    if cmd_hosts check; then echo "${D}/etc/hosts has these names.${R}"
    else echo "${Y}/etc/hosts does not match LAN_HOSTS yet: 'lan hosts apply' (or rerun dev-init with install-lan).${R}"; fi
    [ -n "$self" ] && ! hosts | awk -v s="$self" '$1 == s { f = 1 } END { exit !f }' \
        && echo "${D}This machine ($self) is not in the list; other laptops will not know its address.${R}"
    return 0
}
hosts_block() {
    local self n ip
    self=$(self_name)
    # v93: NAME.internal beside each name: Ollama accepts that Host name, not a plain laptop name.
    while read -r n ip; do
        if [ "$n" = "$self" ]; then printf '127.0.0.1\t%s %s.internal\t# this machine (LAN_SELF); others use %s\n' "$n" "$n" "$ip"
        else printf '%s\t%s %s.internal\n' "$ip" "$n" "$n"; fi
    done < <(hosts 2> /dev/null)
}
# write_etc_hosts NAME CONTENT: replace the marked block NAME in /etc/hosts (removed when CONTENT is empty)
write_etc_hosts() {
    local name=$1 content=$2 tmp
    tmp=$(mktemp)
    awk -v b="# >>> $name >>>" -v e="# <<< $name <<<" '$0 == b { skip = 1; next } skip && $0 == e { skip = 0; next } !skip' /etc/hosts > "$tmp"
    if [ -n "$content" ]; then
        { echo "# >>> $name >>>"; echo "# Written by the 'lan' command (dev-setup install-lan); replaced on each run."; echo "$content"; echo "# <<< $name <<<"; } >> "$tmp"
    fi
    if ! cmp -s "$tmp" /etc/hosts; then
        sudo cp "$tmp" /etc/hosts.dev-lan.new && sudo chmod 644 /etc/hosts.dev-lan.new && sudo sh -c 'cat /etc/hosts.dev-lan.new > /etc/hosts' && sudo rm -f /etc/hosts.dev-lan.new \
            || { rm -f "$tmp"; die "could not write /etc/hosts (sudo)"; }
    fi
    rm -f "$tmp"
}

cmd_url() {
    local n=$1 s=${2:-all} ip p
    ip=$(need_ip "$n") || exit 1
    [ "$ip" != 127.0.0.1 ] || echo "${D}($n is this machine: from DDEV's containers use the DDEV names 'devsvc info' and 'ldap drupal' print, not the addresses below)${R}"
    case "$s" in all|ollama)
        echo "${B}Ollama${R}   http://$n.internal:11434   (or http://$ip:11434; a plain 'http://$n:11434' gets 403 from Ollama)"
        echo "         lan ollama $n list  |  OLLAMA_HOST=http://$n.internal:11434 ollama run <model>  |  OLLAMA_REMOTE=$n.internal in secrets.env" ;; esac
    case "$s" in all|mssql)
        echo "${B}SQL Server${R}  sqlcmd -S $n,1433 -U sa -C   (the password: 'mssql password' on $n)"
        echo "         ODBC  DRIVER={ODBC Driver 18 for SQL Server};Server=$ip,1433;Uid=sa;Pwd=<password>;TrustServerCertificate=yes" ;; esac
    case "$s" in all|oracle)
        echo "${B}Oracle${R}   sql system@//$n:1521/FREEPDB1   (the password: 'oracle password' on $n)"
        echo "         ODBC  DRIVER={Oracle ODBC};DBQ=$ip:1521/FREEPDB1;UID=system;PWD=<password>" ;; esac
    case "$s" in all|ldap)
        echo "${B}LDAP${R}     lldap ldap://$n:3890 (web UI http://$n:17170)   OpenLDAP ldap://$n:1389"
        echo "         the values for Drupal: 'ldap drupal' on $n (use $ip as the host inside DDEV)" ;; esac
    case "$s" in all|ddev)
        echo "${B}DDEV${R}     lan site $n <site>, then https://<site>.ddev.site:8443 or http://<site>.ddev.site:8080"
        echo "         (the certificate is $n's own mkcert one, so the browser warns over https)" ;; esac
    case "$s" in all|dev)
        for p in $(dev_ports); do echo "${B}dev${R}      http://$ip:$p   (Vite and Angular accept an address, not a name, unless allowedHosts says so)"; done ;; esac
    case "$s" in all|mcp)
        for p in $(mcp_ports); do echo "${B}MCP${R}      http://$n:$p/mcp   (streamable HTTP)  ->  lan mcp $n $p"; done ;; esac
    # v89: the shared services (devsvc). The logins are the ones on $n: 'devsvc password NAME' there.
    case "$s" in all|redis)
        echo "${B}Redis${R}    redis-cli -h $n -p 6379 --askpass   URL redis://:<password>@$n:6379/0   (DDEV: $ip)" ;; esac
    case "$s" in all|solr)
        echo "${B}Solr${R}     http://$n:8983/solr/   user solr   (Drupal in DDEV: host $ip, port 8983, Solr Cloud with Basic Auth)" ;; esac
    case "$s" in all|opensearch)
        echo "${B}OpenSearch${R} http://$n:9200   user admin   (curl -u admin http://$n:9200/_cat/indices)" ;; esac
    case "$s" in all|elasticsearch)
        echo "${B}Elasticsearch${R} http://$n:9201   user elastic" ;; esac
    case "$s" in all|meilisearch)
        echo "${B}Meilisearch${R} http://$n:7700   header 'Authorization: Bearer <master key>'" ;; esac
    case "$s" in all|typesense)
        echo "${B}Typesense${R} http://$n:8108   header 'X-TYPESENSE-API-KEY: <key>'" ;; esac
    case "$s" in all|qdrant)
        echo "${B}Qdrant${R}   http://$n:6333 (gRPC $n:6334)   header 'api-key: <key>'   QdrantClient(url=\"http://$n:6333\", api_key=...)" ;; esac
    case "$s" in all|mongodb)
        echo "${B}MongoDB${R}  mongosh \"mongodb://root@$n:27017/?authSource=admin\"   (from DDEV: $ip)" ;; esac
    case " $KNOWN all " in *" $s "*) ;; *) die "unknown service '$s' ($KNOWN)" ;; esac
}

cmd_mcp() {
    local n=${1:?usage: lan mcp NAME [PORT] [ID]} port=${2:-} id=${3:-} url
    need_ip "$n" > /dev/null
    [ -n "$port" ] || port=$(mcp_ports | awk '{ print $1 }')
    [ -n "$id" ] || id="$n-mcp"
    url="http://$n:$port/mcp"
    port_open "$(ip_of "$n")" "$port" || echo "${Y}Note:${R} nothing answers on $n:$port right now (start the server there first). Adding it anyway."
    if command -v claude > /dev/null 2>&1; then
        claude mcp remove --scope user "$id" > /dev/null 2>&1 || true
        claude mcp add --scope user --transport http "$id" "$url" && echo "Claude Code (every project): '$id' -> $url. Check it with: claude mcp list"
    else
        echo "Claude Code is not installed (install-node). Other MCP clients take:"
    fi
    printf '{ "mcpServers": { "%s": { "type": "http", "url": "%s" } } }\n' "$id" "$url"
}

cmd_site() {
    local cur n site ip
    cur=$(sed -n '/^# >>> dev-lan sites >>>$/,/^# <<< dev-lan sites <<<$/p' /etc/hosts | sed '1,2d;$d')
    if [ $# -eq 0 ]; then
        [ -n "$cur" ] && echo "$cur" || echo "No remote DDEV sites mapped. 'lan site NAME SITE' adds one."
        return 0
    fi
    if [ "$1" = --remove ]; then
        site=${2:?usage: lan site --remove SITE}; site=${site%.ddev.site}.ddev.site
        write_etc_hosts "dev-lan sites" "$(awk -v s="$site" '$2 != s' <<< "$cur")"
        echo "Removed $site: it resolves to this machine again."
        return 0
    fi
    n=$1; site=${2:?usage: lan site NAME SITE}; site=${site%.ddev.site}.ddev.site
    ip=$(need_ip "$n") || exit 1
    [ "$ip" != 127.0.0.1 ] || die "$n is this machine"
    write_etc_hosts "dev-lan sites" "$( { awk -v s="$site" 'NF && $2 != s' <<< "$cur"; printf '%s\t%s\t# on %s\n' "$ip" "$site" "$n"; } )"
    echo "$site now points at $n ($ip) on this machine (a local DDEV project of the same name is hidden until 'lan site --remove ${site%.ddev.site}')."
    echo "  https://$site:8443   (the certificate is $n's own mkcert one: expect a warning)"
    echo "  http://$site:8080"
    port_open "$ip" 8443 || echo "${Y}Note:${R} $n does not answer on 8443: is 'ddev' in LAN_SHARE there ('lan share' on $n)?"
}

relay_state() { local s; s=$(systemctl is-active "$UNIT" 2> /dev/null); echo "${s:-not running}"; }

# --- v93: lan probe: does the service behind a port answer, in its own protocol? -------------------------
# A plain connect proves little over Tailscale: 'tailscale serve' accepts a connection even when the service
# behind it is stopped, then closes it. Each known port gets a short exchange in its own protocol (no login
# needed): HTTP with the Host name a client would send (NAME.internal for Ollama), a TLS handshake for 8443,
# a TDS pre-login for SQL Server, a TNS connect for Oracle, an anonymous LDAP bind, a Redis PING, a MongoDB
# hello, an HTTP/2 preface for Qdrant's gRPC. Exit codes: 0 up, 1 accepted but nothing behind it, 2 not
# reachable (refused or timed out), 3 forbidden (Ollama's 403 for a Host name it does not accept).
probe_kind() {   # probe_kind PORT: the protocol to speak
    case "$1" in
        11434) echo ollama ;; 1433) echo tds ;; 1521) echo tns ;; 3890|1389) echo ldap ;; 8443) echo tls ;;
        6379) echo redis ;; 27017) echo mongo ;; 6334) echo h2 ;;
        8080|17170|8983|9200|9201|7700|8108|6333) echo http ;;
        *) if [[ " $(dev_ports) " == *" $1 "* ]]; then echo http
           elif [[ " $(mcp_ports) " == *" $1 "* ]]; then echo mcp
           else echo raw; fi ;;
    esac
}
probe_one() {   # probe_one NAME IP PORT: one line, "up|down|refused|forbidden: detail"; exit as above
    python3 - "$1" "$2" "$3" "$(probe_kind "$3")" << 'PROBE_PY'
import socket, ssl, struct, sys
name, ip, port, kind = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
def say(state, detail, code):
    print(f"{state}: {detail}"); sys.exit(code)
try:
    s = socket.create_connection((ip, port), timeout=5)
except (ConnectionRefusedError, ConnectionResetError):
    say("refused", "nothing accepts connections on this port", 2)
except OSError as e:
    say("refused", f"not reachable ({e.strerror or e})", 2)
s.settimeout(8)
def http(path, host):
    s.sendall(f"GET {path} HTTP/1.1\r\nHost: {host}\r\nUser-Agent: lan-probe\r\nConnection: close\r\n\r\n".encode())
def recv(n=4096):
    try:
        return s.recv(n)
    except socket.timeout:
        return None
    except OSError:
        return b""
try:
    if kind == "tls":
        ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
        try:
            t = ctx.wrap_socket(s, server_hostname=f"{name}.ddev.site")
            say("up", f"TLS handshake ({t.version()})", 0)
        except (ssl.SSLError, OSError) as e:
            say("down", f"accepted, but no TLS server answered ({e.__class__.__name__})", 1)
    if kind == "ollama":
        http("/api/version", f"{name}.internal:{port}")
    elif kind in ("http", "mcp"):
        http("/mcp" if kind == "mcp" else "/", f"{name}:{port}")
    elif kind == "tds":   # TDS PRELOGIN: VERSION and ENCRYPTION options
        opts = bytes([0x00, 0x00, 0x0B, 0x00, 0x06, 0x01, 0x00, 0x11, 0x00, 0x01, 0xFF]) + bytes([0x10, 0, 0, 0, 0, 0]) + bytes([0x02])
        s.sendall(struct.pack(">BBHHBB", 0x12, 0x01, 8 + len(opts), 0, 0, 0) + opts)
    elif kind == "tns":   # a TNS CONNECT for a service that does not exist: any listener answers (REFUSE)
        data = b"(DESCRIPTION=(CONNECT_DATA=(SERVICE_NAME=lan-probe))(ADDRESS=(PROTOCOL=TCP)(HOST=x)(PORT=1521)))"
        hdr = struct.pack(">HHBBH", 58 + len(data), 0, 1, 0, 0)
        body = struct.pack(">HHHHHHHHHH", 0x013A, 0x012C, 0, 0x0800, 0x7FFF, 0x7F08, 0, 1, len(data), 58) + bytes(16)
        s.sendall(hdr + body + data)
    elif kind == "ldap":  # anonymous simple bind
        s.sendall(bytes.fromhex("300c020101600702010304008000"))
    elif kind == "redis":
        s.sendall(b"PING\r\n")
    elif kind == "mongo":  # OP_MSG { hello: 1, $db: "admin" }
        doc = b"\x10hello\x00" + struct.pack("<i", 1) + b"\x02$db\x00" + struct.pack("<i", 6) + b"admin\x00"
        doc = struct.pack("<i", len(doc) + 5) + doc + b"\x00"
        msg = struct.pack("<I", 0) + b"\x00" + doc
        s.sendall(struct.pack("<iiii", 16 + len(msg), 1, 0, 2013) + msg)
    elif kind == "h2":
        s.sendall(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" + bytes.fromhex("000000040000000000"))
    else:
        s.sendall(b"\r\n")
    r = recv()
except OSError as e:
    say("down", f"accepted, then the connection broke ({e.strerror or e})", 1)
if r == b"":
    say("down", "accepted, then closed with nothing behind it (the service is stopped, or 'tailscale serve' points at nothing)", 1)
if r is None:
    if kind == "raw":
        say("up", "accepted and kept open (no reply to a blank line; LAN_EXTRA ports are not probed further)", 0)
    say("down", "accepted, but no answer within 8 s", 1)
if kind in ("ollama", "http", "mcp"):
    # the rest of the answer (headers and body can arrive in separate packets; Connection: close ends it)
    while len(r) < 16384:
        more = recv()
        if not more:
            break
        r += more
    line = r.split(b"\r\n", 1)[0].decode("latin-1", "replace")
    if not line.startswith("HTTP/"):
        say("down", f"accepted, but not an HTTP answer ({line[:40]!r})", 1)
    code = line.split()[1] if len(line.split()) > 1 else "?"
    if kind == "ollama":
        if code == "403":
            say("forbidden", f"HTTP 403 for Host {name}.internal: Ollama refuses the name (use the address, or check the /etc/hosts block)", 3)
        body = r.split(b"\r\n\r\n", 1)[-1].decode("latin-1", "replace")
        ver = body[body.find('"version"'):].split('"')[3] if '"version"' in body else "?"
        say("up" if code == "200" else "down", f"HTTP {code}, Ollama {ver}", 0 if code == "200" else 1)
    if code in ("502", "503", "504"):
        say("down", f"HTTP {code} (a proxy answers, the service behind it does not)", 1)
    say("up", f"HTTP {code}", 0)
if kind == "tds":
    say("up" if r[:1] == b"\x04" else "down", "SQL Server pre-login answered" if r[:1] == b"\x04" else "not a TDS answer", 0 if r[:1] == b"\x04" else 1)
if kind == "tns":
    t = r[4] if len(r) > 4 else 0
    ok = t in (2, 4, 5, 11)
    say("up" if ok else "down", f"the Oracle listener answered (TNS packet type {t})" if ok else "not a TNS answer", 0 if ok else 1)
if kind == "ldap":
    ok = r[:1] == b"\x30"
    say("up" if ok else "down", "the LDAP server answered a bind" if ok else "not an LDAP answer", 0 if ok else 1)
if kind == "redis":
    ok = r[:1] in (b"+", b"-")
    say("up" if ok else "down", "Redis answered: " + r.split(b"\r\n")[0].decode("latin-1", "replace")[:40] if ok else "not a Redis answer", 0 if ok else 1)
if kind == "mongo":
    ok = len(r) >= 16 and struct.unpack("<i", r[12:16])[0] == 2013
    say("up" if ok else "down", "MongoDB answered hello" if ok else "not a MongoDB answer", 0 if ok else 1)
if kind == "h2":
    ok = len(r) >= 9
    say("up" if ok else "down", "an HTTP/2 (gRPC) server answered" if ok else "no HTTP/2 answer", 0 if ok else 1)
say("up", f"answered ({len(r)} bytes)", 0)
PROBE_PY
}
cmd_probe() {   # lan probe [--tsv] NAME [PORT...]
    local tsv=0 n ip port svc out rc any=1 c ports=()
    [ "${1:-}" = --tsv ] && { tsv=1; shift; }
    n=${1:?usage: lan probe NAME [PORT...]}; shift
    ip=$(need_ip "$n") || exit 1
    if [ $# -gt 0 ]; then ports=("$@")
    else
        # Every known port at once with a short connect (an offline laptop would otherwise cost a timeout per
        # port), then the protocol exchange only on the ports that accepted.
        local tmp; tmp=$(mktemp -d)
        while read -r port _; do ( port_open "$ip" "$port" && : > "$tmp/$port" ) & done < <(scan_ports)
        wait
        while read -r port _; do [ -e "$tmp/$port" ] && ports+=("$port"); done < <(scan_ports)
        rm -rf "$tmp"
        [ ${#ports[@]} -gt 0 ] || return 1
    fi
    for port in "${ports[@]}"; do
        svc=$(scan_ports | awk -v p="$port" '$1 == p { print $2; exit }'); svc=${svc:-port$port}
        out=$(probe_one "$n" "$ip" "$port"); rc=$?
        # without a port list, a port that refuses after all is not listed (that laptop does not share it)
        [ $# -eq 0 ] && [ "$rc" = 2 ] && continue
        [ "$rc" = 0 ] && any=0
        if [ "$tsv" = 1 ]; then printf '%s\t%s\t%s\t%s\n' "$port" "$svc" "${out%%:*}" "${out#*: }"
        else
            case "$rc" in 0) c=$G ;; 2) c=$D ;; *) c=$Y ;; esac
            printf '  %-6s %-15s %s%s%s\n' "$port" "$svc" "$c" "$out" "$R"
        fi
    done
    [ $# -eq 1 ] && return "$rc"
    return $any
}
cmd_path() {   # lan path [NAME...]: how Tailscale reaches each laptop
    local names=() n ip out
    command -v tailscale > /dev/null 2>&1 || die "Tailscale is not installed (dev-setup with install-lan)"
    if [ $# -gt 0 ]; then names=("$@"); else while read -r n _; do [ "$n" = "$(self_name)" ] || names+=("$n"); done < <(hosts); fi
    for n in "${names[@]}"; do
        ip=$(ip_of "$n") || { echo "$n: not in LAN_HOSTS"; continue; }
        out=$(timeout 20 tailscale ping -c 3 --timeout 5s "$ip" 2>&1 | grep -m1 -E 'pong|timed out|no reply|not found|unknown'; true)
        [ -n "$out" ] || out="no answer"
        case "$out" in
            *"via DERP"*) printf '%-14s %-15s %s\n' "$n" "$ip" "${Y}relayed:${R} ${out#*via }  (works; slower for big transfers: 'tailscale netcheck' on both laptops says why)" ;;
            *pong*)       printf '%-14s %-15s %s\n' "$n" "$ip" "${G}direct:${R} ${out#*via }" ;;
            *)            printf '%-14s %-15s %s\n' "$n" "$ip" "${D}$out (off, asleep, or not on your tailnet)${R}" ;;
        esac
    done
}

cmd_share() {
    local sub=${1:-status}
    case "$sub" in
        plan) plan ;;
        apply)
            ts_mode || [ -f "$RELAY_PY" ] || die "the relay is not installed: rerun dev-setup with install-lan-share"
            mkdir -p "$(dirname "$RELAY_TSV")"
            { echo "# LAN_PORT<TAB>LOCAL_PORT<TAB>LABEL  - written by 'lan share apply' from LAN_SHARE / LAN_EXTRA in"
              echo "# $SECRETS; edit those and rerun 'lan share apply', not this file."
              plan; } > "$RELAY_TSV.new"
            local dups; dups=$(grep -v '^#' "$RELAY_TSV.new" | cut -f1 | sort | uniq -d | tr '\n' ' ')
            [ -z "$dups" ] || { rm -f "$RELAY_TSV.new"; die "LAN port(s) listed twice: $dups(check LAN_EXTRA)"; }
            mv "$RELAY_TSV.new" "$RELAY_TSV"
            if ts_mode; then share_ts_apply; return; fi
            if systemctl is-enabled "$UNIT" > /dev/null 2>&1; then
                sudo systemctl restart "$UNIT" && sleep 1
                echo "Sharing: $(words "$(cfg LAN_SHARE)" | xargs)${D}  (relay restarted; 'lan share' shows it)${R}"
            else
                echo "Relay config written. Sharing is off: 'lan share on' starts it."
            fi ;;
        on)  if ts_mode; then rm -f "$SHARE_OFF"; cmd_share apply; return; fi
             [ -f "$RELAY_PY" ] || die "the relay is not installed: rerun dev-setup with install-lan-share"
             [ -f "$RELAY_TSV" ] || cmd_share apply > /dev/null
             sudo systemctl enable --now "$UNIT" > /dev/null 2>&1 && sudo systemctl restart "$UNIT" && sleep 1 && echo "Sharing is on." && cmd_share status ;;
        off) if ts_mode; then
                 mkdir -p "$(dirname "$SHARE_OFF")"; : > "$SHARE_OFF"
                 share_ts_unpublish all
                 echo "Sharing is off: every port 'lan' published over Tailscale is closed ('lan share on' reopens them)."
                 return 0
             fi
             sudo systemctl disable --now "$UNIT" > /dev/null 2>&1; echo "Sharing is off: every relayed port is closed ('lan share on' reopens them)."
             [ -n "$(direct_ports)" ] && echo "Dev and MCP servers you started with --host / 0.0.0.0 still listen until you stop them."
             return 0 ;;
        ports)
            if ts_mode; then
                echo "Over Tailscale: no ChromeOS port forwards. 'lan share apply' publishes these on this laptop's Tailscale"
                echo "address with 'tailscale serve' (other laptops on your tailnet reach them; nobody else on the Wi-Fi does):"
                local lan lp label
                while IFS=$'\t' read -r lan lp label; do printf '  %-6s TCP   %s\n' "$lan" "$label"; done < <(plan 2> /dev/null)
                while read -r lan label; do printf '  %-6s TCP   %s (listens on the network itself: start it with --host / 0.0.0.0)\n' "$lan" "$label"; done < <(direct_ports)
                [ -n "$(plan 2> /dev/null)$(direct_ports)" ] || echo "  (nothing: LAN_SHARE is empty in $SECRETS)"
                plan 2>&1 > /dev/null | sed "s/^lan: /  ${Y}note:${R} /"
                return 0
            fi
            echo "Add each of these once in ChromeOS: Settings > Advanced > Developers > Linux > Port forwarding > Add"
            echo "(if your ChromeOS files it elsewhere, search Settings for 'port forwarding'). Type TCP; the label is"
            echo "only for you. Other laptops reach a port only while this Chromebook is awake with Linux running."
            local lan lp label
            while IFS=$'\t' read -r lan lp label; do printf '  %-6s TCP   %s\n' "$lan" "$label"; done < <(plan 2> /dev/null)
            while read -r lan label; do printf '  %-6s TCP   %s (start it with --host / 0.0.0.0)\n' "$lan" "$label"; done < <(direct_ports)
            [ -n "$(plan 2> /dev/null)$(direct_ports)" ] || echo "  (nothing: LAN_SHARE is empty in $SECRETS)"
            plan 2>&1 > /dev/null | sed "s/^lan: /  ${Y}note:${R} /" ;;
        seen)   # LAN_PORT PEER TIME for every port a connection from outside this machine has come through
            [ -r "$STATE_DIR/seen.json" ] && jq -r 'to_entries[] | "\(.key) \(.value.peer) \(.value.time)"' "$STATE_DIR/seen.json" 2> /dev/null
            return 0 ;;
        status)
            local st lan lp label s seen p scope s1 c f
            if ts_mode; then share_ts_status; return; fi
            st=$(relay_state)
            echo "${B}Sharing from $(self_name || true)${R}  LAN_SHARE: $(words "$(cfg LAN_SHARE)" | xargs)"
            echo "Linux address: $(linux_addrs | xargs)   relay: ${st:-not installed}"
            [ -f "$RELAY_PY" ] || { echo "The relay is not installed: rerun dev-setup with install-lan-share."; return 1; }
            while IFS=$'\t' read -r lan lp label; do
                s=$(jq -r --arg p "$lan" '.ports[$p] | if . == null then "-" else "\(.status) \(.connections) \(.target_failures)" end' "$STATE_DIR/relay-status.json" 2> /dev/null)
                seen=$(jq -r --arg p "$lan" '.[$p] | if . == null then "" else "\(.peer) \(.time)" end' "$STATE_DIR/seen.json" 2> /dev/null)
                if [ "$st" != active ]; then s="${Y}relay stopped${R}"
                else
                    read -r s1 c f <<< "$s"
                    case "$s1" in
                        relaying) s="${G}relaying${R} ${c:-0} conn." ;;
                        direct)   s="${G}direct${R} (listens on every interface itself)" ;;
                        error)    s="${Y}cannot listen${R} ('journalctl -u $UNIT')" ;;
                        *)        s="${Y}not in the running relay${R} ('lan share apply')" ;;
                    esac
                fi
                if port_open 127.0.0.1 "$lp" || port_open ::1 "$lp"; then lp="${G}up${R}"; else lp="${D}not running${R}"; fi
                printf '  %-6s %-22s %-30s service %-12s %s\n' "$lan" "$label" "$s" "$lp" "$(if [ -n "$seen" ]; then echo "${G}reached from $seen${R}"; else echo "${D}not reached from the network yet${R}"; fi)"
            done < <(plan 2> /dev/null)
            while read -r p label; do
                scope=$(listen_scope "$p")
                case "$scope" in
                    network) s="${G}listening on the network${R}" ;;
                    local)   s="${Y}only on this machine: restart it with --host / 0.0.0.0${R}" ;;
                    *)       s="${D}not running${R}" ;;
                esac
                printf '  %-6s %-22s %s\n' "$p" "$label" "$s"
            done < <(direct_ports)
            [ -n "$(plan 2> /dev/null)$(direct_ports)" ] || echo "  Nothing shared: set LAN_SHARE in $SECRETS ($KNOWN), then 'lan share apply'."
            plan 2>&1 > /dev/null | sed "s/^lan: /  ${Y}note:${R} /"
            echo "${D}'Reached from the network' appears once another laptop has connected through that port; until then check"
            echo "the ChromeOS forward ('lan share ports'). Anyone on the same Wi-Fi can reach these ports: 'lan share off' elsewhere.${R}" ;;
        *) die "unknown: lan share $sub (status ports apply on off)" ;;
    esac
}

# --- v93: sharing over Tailscale ------------------------------------------------------------------
share_ts_unpublish() {   # share_ts_unpublish all|stale: remove ports 'lan' published (all, or those no longer planned)
    local lan lp _l keep
    [ -f "$SERVED_TSV" ] || return 0
    while IFS=$'\t' read -r lan lp _l; do
        case "$lan" in ''|\#*) continue ;; esac
        if [ "$1" = stale ]; then
            keep=$(grep -v '^#' "$RELAY_TSV" 2> /dev/null | awk -F'\t' -v p="$lan" -v l="$lp" '$1 == p && $2 == l { print "y"; exit }')
            [ -n "$keep" ] && continue
        fi
        ts_off "$lan" "$lp" && echo "  unpublished $lan (localhost:$lp)"
    done < "$SERVED_TSV"
    if [ "$1" = all ]; then rm -f "$SERVED_TSV"; fi
    return 0
}
share_ts_apply() {   # publish relay.tsv's ports with 'tailscale serve'; stop the v84 relay
    local lan lp label have bad="" n=0 st
    st=$(ts_state)
    if systemctl is-enabled "$UNIT" > /dev/null 2>&1 || systemctl is-active "$UNIT" > /dev/null 2>&1; then
        sudo systemctl disable --now "$UNIT" > /dev/null 2>&1 && echo "The v84 relay is stopped: over Tailscale, 'tailscale serve' publishes the ports instead."
    fi
    if [ -f "$SHARE_OFF" ]; then
        echo "Port list written. Sharing is off ('lan share off' earlier): 'lan share on' publishes it."; return 0
    fi
    if [ "$st" != Running ]; then
        echo "Port list written, but Tailscale is not connected ($st): dev-init with install-lan joins this laptop, then 'lan share apply'."
        return 1
    fi
    share_ts_unpublish stale
    while IFS=$'\t' read -r lan lp label; do
        case "$lan" in ''|\#*) continue ;; esac
        have=$(ts_target "$lan")
        if [ -n "$have" ] && [ "${have#tcp://}" = "localhost:$lp" ]; then n=$((n + 1)); continue; fi
        if [ -n "$have" ]; then ts_off "$lan" "${have##*:}"; fi
        if ts_admin serve --bg --tcp="$lan" "tcp://localhost:$lp"; then n=$((n + 1)); else bad+="$lan "; fi
    done < "$RELAY_TSV"
    cp "$RELAY_TSV" "$SERVED_TSV"
    echo "Sharing over Tailscale: $(words "$(cfg LAN_SHARE)" | xargs) ($n port(s) published with 'tailscale serve'; 'lan share' shows them)"
    [ -z "$bad" ] || { echo "lan: 'tailscale serve' refused port(s) $bad(is this user Tailscale's operator? dev-init sets it: sudo tailscale set --operator=\$USER)" >&2; return 1; }
    return 0
}
share_ts_status() {
    local lan lp label served pub up self ip extra
    self=$(self_name || true); ip=$(ts_tun)
    echo "${B}Sharing from ${self:-this laptop} over Tailscale${R}  LAN_SHARE: $(words "$(cfg LAN_SHARE)" | xargs)"
    echo "Tailscale: $(ts_state), tailscale0 ${ip:-${Y}missing (userspace mode? FLAGS=\"--tun=tailscale0\" in /etc/default/tailscaled)${R}}${self:+   others reach this laptop as $self / $self.internal}"
    [ -f "$SHARE_OFF" ] && echo "${Y}Sharing is off ('lan share on' publishes the ports again).${R}"
    served=" $(ts_served | xargs) "
    while IFS=$'\t' read -r lan lp label; do
        if [[ "$served" == *" $lan "* ]]; then pub="${G}published${R}"; else pub="${Y}not published${R} ('lan share apply')"; fi
        if port_open 127.0.0.1 "$lp" || port_open ::1 "$lp"; then up="${G}up${R}"; else up="${D}not running${R}"; fi
        printf '  %-6s %-22s %-32s service %s\n' "$lan" "$label" "$pub" "$up"
        [ "$lan" = 11434 ] && [ -n "$self" ] && echo "         ${D}clients: http://$self.internal:11434 (a plain http://$self:11434 gets 403 from Ollama)${R}"
        [ "$lan" = 8080 ] && echo "         ${D}DDEV routes by site name: on the other laptop 'lan site ${self:-NAME} SITE', then http://SITE.ddev.site:8080${R}"
    done < <(plan 2> /dev/null)
    while read -r lan label; do
        case "$(listen_scope "$lan")" in
            network) s="${G}listening on the network${R}" ;;
            local)   s="${Y}only on this machine: restart it with --host / 0.0.0.0${R}" ;;
            *)       s="${D}not running${R}" ;;
        esac
        printf '  %-6s %-22s %s\n' "$lan" "$label" "$s"
    done < <(direct_ports)
    extra=$(for lan in $served; do grep -v '^#' "$RELAY_TSV" 2> /dev/null | cut -f1 | grep -qx "$lan" || echo "$lan"; done | xargs)
    [ -z "$extra" ] || echo "  ${D}also published by hand with 'tailscale serve' (lan leaves them alone): $extra${R}"
    [ -n "$(plan 2> /dev/null)$(direct_ports)" ] || echo "  Nothing shared: set LAN_SHARE in $SECRETS ($KNOWN), then 'lan share apply'."
    plan 2>&1 > /dev/null | sed "s/^lan: /  ${Y}note:${R} /"
    echo "${D}Only laptops on your tailnet reach these ports. 'lan probe ${self:-NAME}' on another laptop checks each service end to end.${R}"
}

cmd_status() {
    local self n
    bad_hosts_note
    self=$(self_name)
    if ts_mode; then
        echo "${B}This machine${R}: ${self:-${Y}unnamed${R} (set LAN_SELF or MACHINE_LABEL in $SECRETS)}   Tailscale: $(ts_state), $(ts_tun || true)"
    else
        echo "${B}This machine${R}: ${self:-${Y}unnamed${R} (set LAN_SELF or MACHINE_LABEL in $SECRETS)}   Linux address: $(linux_addrs | xargs)"
    fi
    n=$(hosts 2> /dev/null | wc -l)
    echo "Address book: $n laptop(s) in LAN_HOSTS$( [ "$n" -gt 0 ] && { cmd_hosts check && echo ", in /etc/hosts" || echo ", ${Y}not in /etc/hosts yet ('lan hosts apply')${R}"; } )"
    if ts_mode && [ -f "$RELAY_TSV" ]; then
        echo "Sharing: $(words "$(cfg LAN_SHARE)" | xargs)$( [ -n "$(cfg LAN_SHARE)" ] || echo "nothing (LAN_SHARE is empty)")   over Tailscale$( [ -f "$SHARE_OFF" ] && echo " (switched off)")   (lan share)"
    elif [ -f "$RELAY_PY" ]; then
        echo "Sharing: $(words "$(cfg LAN_SHARE)" | xargs)$( [ -n "$(cfg LAN_SHARE)" ] || echo "nothing (LAN_SHARE is empty)")   relay: $(relay_state)   (lan share)"
    else
        echo "Sharing: not installed on this machine (install-lan-share)"
    fi
    echo "${D}lan scan / lan probe NAME: what the other laptops share.  lan help: every command.${R}"
}

case "${1:-status}" in
    status)   cmd_status ;;
    hosts)    shift; cmd_hosts "$@" ;;
    ip)       need_ip "${2:?usage: lan ip NAME}" ;;
    scan)     shift; cmd_scan "$@" ;;
    probe)    shift; cmd_probe "$@" ;;
    path)     shift; cmd_path "$@" ;;
    url)      shift; cmd_url "${1:?usage: lan url NAME [SERVICE]}" "${2:-all}" ;;
    ollama)   shift; n=${1:?usage: lan ollama NAME ARGS...}; shift
              ip=$(need_ip "$n") || exit 1
              OLLAMA_HOST="http://$ip:11434" exec ollama "$@" ;;
    mcp)      shift; cmd_mcp "$@" ;;
    site)     shift; cmd_site "$@" ;;
    share)    shift; cmd_share "$@" ;;
    help|-h|--help) sed -n '2,/^$/{s/^# \{0,1\}//;p}' "$0" ;;
    *)        die "unknown command '$1' ('lan help')" ;;
esac
EOF_DEV_LAN
    chmod 755 "$HOME/.local/bin/lan"

    if [[ "$FLAGS" =~ " install-lan-share " ]]; then
        mkdir -p "$HOME/.local/lib/dev-lan" "$HOME/.config/dev-lan" "$HOME/.local/state/dev-lan"
        cat > "$HOME/.local/lib/dev-lan/lan-relay.py" << 'EOF_DEV_LAN_RELAY'
#!/usr/bin/python3
"""dev-lan relay: lets your other laptops reach services that listen on 127.0.0.1 in this Linux.

Written by dev-setup (install-lan-share) and run by the dev-lan-relay systemd service; the 'lan share'
command configures it. Standard library only.

Every service the bundle installs listens on 127.0.0.1, which nothing outside this Linux can reach.
Instead of reopening each service on every interface, the relay listens on this container's own
network address (eth0, the address ChromeOS port forwarding delivers to) and passes each connection
through to 127.0.0.1 (or ::1) on the same machine. The services themselves are never changed, and
stopping the relay ('lan share off') closes every shared port at once.

    lan-relay.py CONFIG STATE_DIR

CONFIG is a tab-separated file, one port per line:  LAN_PORT  LOCAL_PORT  LABEL   ('#' = comment).
STATE_DIR receives relay-status.json (what is listening, connection counts) and seen.json: per port,
the last connection that came from outside this machine, which is how 'lan share status' and dev-init
know a ChromeOS port forward works. Connections from this machine itself (dev-test's checks) do not
count.

A port whose number is already taken on every interface (for example Ollama opened to containers
with install-ollama-containers, which listens on 0.0.0.0:11434) needs no relay: it is reported as
'direct'. When this machine's address changes, the relay exits and systemd starts it again on the
new one.
"""

import asyncio
import ipaddress
import json
import os
import signal
import socket
import subprocess
import sys
import time

BUFSIZE = 65536
CONNECT_TIMEOUT = 5
WATCH_SECONDS = 30
# Interfaces that are not the way in from the network: Docker's and kind's bridges and their veths.
SKIP_PREFIXES = ("lo", "docker", "br-", "veth", "virbr", "cni", "flannel", "kube", "tailscale", "wg")


def log(msg):
    print(msg, flush=True)


def read_config(path):
    ports = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            try:
                lan, local = int(parts[0]), int(parts[1])
            except (IndexError, ValueError):
                log(f"config line {n} ignored (want LAN_PORT<TAB>LOCAL_PORT<TAB>LABEL): {line!r}")
                continue
            label = parts[2] if len(parts) > 2 and parts[2] else f"port {local}"
            if not (1 <= lan <= 65535 and 1 <= local <= 65535):
                log(f"config line {n} ignored (port out of range): {line!r}")
                continue
            if any(p[0] == lan for p in ports):
                log(f"config line {n} ignored (LAN port {lan} listed twice)")
                continue
            ports.append((lan, local, label))
    return ports


def interfaces():
    """[(ifname, ip_interface)] for every IPv4 address, from 'ip -j addr' (iproute2)."""
    out = []
    try:
        data = json.loads(subprocess.run(["ip", "-j", "-4", "addr", "show"], capture_output=True,
                                         text=True, timeout=10, check=True).stdout or "[]")
    except (OSError, subprocess.SubprocessError, ValueError):
        data = []
    for itf in data:
        for a in itf.get("addr_info", []):
            if a.get("family") == "inet" and a.get("local"):
                out.append((itf.get("ifname", ""), ipaddress.ip_interface(f"{a['local']}/{a.get('prefixlen', 32)}")))
    return out


def lan_addresses(itfs):
    """The addresses to listen on: every IPv4 address of an up interface that is not a bridge."""
    return sorted({str(i.ip) for name, i in itfs if not name.startswith(SKIP_PREFIXES)})


def wildcard_listener(port):
    """True when something listens on 0.0.0.0:PORT or [::]:PORT (then it is reachable already)."""
    for path, wild in (("/proc/net/tcp", "00000000"), ("/proc/net/tcp6", "00000000000000000000000000000000")):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    cols = line.split()
                    addr, hexport = cols[1].split(":")
                    if cols[3] == "0A" and addr == wild and int(hexport, 16) == port:
                        return True
        except OSError:
            pass
    return False


class Relay:
    def __init__(self, config, state_dir):
        self.config = config
        self.state_dir = state_dir
        os.makedirs(state_dir, exist_ok=True)
        self.status_file = os.path.join(state_dir, "relay-status.json")
        self.seen_file = os.path.join(state_dir, "seen.json")
        self.ports = {}
        self.servers = []
        self.addresses = []
        self.self_ips = set()
        self.local_nets = []
        self.dirty = True
        try:
            with open(self.seen_file) as f:
                self.seen = json.load(f)
        except (OSError, ValueError):
            self.seen = {}

    def refresh_networks(self, itfs):
        self.self_ips = {i.ip for _, i in itfs}
        self.local_nets = [ipaddress.ip_network("127.0.0.0/8")]
        self.local_nets += [i.network for name, i in itfs if name.startswith(SKIP_PREFIXES) and name != "lo"]

    def is_remote(self, peer_ip):
        try:
            ip = ipaddress.ip_address(peer_ip)
        except ValueError:
            return False
        if ip.version == 6 and ip.ipv4_mapped:
            ip = ip.ipv4_mapped
        if ip.is_loopback or ip in self.self_ips:
            return False
        return not any(ip in net for net in self.local_nets)

    def write_status(self, final=False):
        doc = {
            "pid": os.getpid(), "updated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "running": not final, "addresses": self.addresses,
            "ports": {str(k): v for k, v in sorted(self.ports.items())},
        }
        tmp = self.status_file + ".tmp"
        with open(tmp, "w") as f:
            json.dump(doc, f, indent=1)
        os.replace(tmp, self.status_file)
        self.dirty = False

    def mark_seen(self, lan, peer):
        self.seen[str(lan)] = {"peer": peer, "time": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
        tmp = self.seen_file + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.seen, f, indent=1, sort_keys=True)
        os.replace(tmp, self.seen_file)

    async def pipe(self, reader, writer):
        try:
            while True:
                data = await reader.read(BUFSIZE)
                if not data:
                    break
                writer.write(data)
                await writer.drain()
            if writer.can_write_eof():
                writer.write_eof()
        except (ConnectionError, OSError, asyncio.CancelledError):
            pass

    async def connect_target(self, local):
        # 127.0.0.1 first; ::1 for servers that bound 'localhost' as IPv6 only (Node can do that).
        errors = []
        for host in ("127.0.0.1", "::1"):
            try:
                return await asyncio.wait_for(asyncio.open_connection(host, local), CONNECT_TIMEOUT)
            except asyncio.TimeoutError:
                errors.append(f"{host}: timed out")
            except OSError as e:
                errors.append(f"{host}: {e.strerror or e}")
        raise ConnectionError("; ".join(errors))

    def handler(self, lan, local):
        async def handle(creader, cwriter):
            st = self.ports[lan]
            peer = (cwriter.get_extra_info("peername") or ("?",))[0]
            st["connections"] += 1
            st["active"] += 1
            st["last_peer"] = peer
            st["last_time"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            self.dirty = True
            if self.is_remote(peer):
                if str(lan) not in self.seen:
                    log(f"first connection from the network on {lan} ({st['label']}): {peer}")
                self.mark_seen(lan, peer)
            try:
                treader, twriter = await self.connect_target(local)
            except ConnectionError as e:
                st["target_failures"] += 1
                st["active"] -= 1
                self.dirty = True
                log(f"{lan} ({st['label']}): nothing answers on port {local} here ({e})")
                cwriter.close()
                return
            try:
                await asyncio.gather(self.pipe(creader, twriter), self.pipe(treader, cwriter))
            finally:
                for w in (twriter, cwriter):
                    try:
                        w.close()
                    except OSError:
                        pass
                st["active"] -= 1
                self.dirty = True
        return handle

    async def start(self):
        itfs = interfaces()
        self.addresses = lan_addresses(itfs)
        waited = 0
        while not self.addresses and waited < 120:   # at boot the network may come up after us
            await asyncio.sleep(2)
            waited += 2
            itfs = interfaces()
            self.addresses = lan_addresses(itfs)
        if not self.addresses:
            log("no network address found (only loopback and bridges); nothing to listen on")
            return False
        self.refresh_networks(itfs)
        log(f"listening on {', '.join(self.addresses)}")
        for lan, local, label in self.config:
            st = {"local": local, "label": label, "status": "", "detail": "", "listen": [],
                  "connections": 0, "active": 0, "target_failures": 0, "last_peer": None, "last_time": None}
            self.ports[lan] = st
            errors = []
            for addr in self.addresses:
                try:
                    srv = await asyncio.start_server(self.handler(lan, local), host=addr, port=lan,
                                                     reuse_address=True, family=socket.AF_INET)
                    self.servers.append(srv)
                    st["listen"].append(f"{addr}:{lan}")
                except OSError as e:
                    errors.append(f"{addr}: {e.strerror or e}")
            if st["listen"]:
                st["status"] = "relaying"
                st["detail"] = f"-> 127.0.0.1:{local}"
                log(f"{lan} ({label}): relaying {', '.join(st['listen'])} -> 127.0.0.1:{local}"
                    + (f"  (not on: {'; '.join(errors)})" if errors else ""))
            elif lan == local and wildcard_listener(lan):
                st["status"] = "direct"
                st["detail"] = "the service itself listens on every interface; no relay needed"
                log(f"{lan} ({label}): direct, the service already listens on every interface")
            else:
                st["status"] = "error"
                st["detail"] = "; ".join(errors)
                log(f"{lan} ({label}): could not listen: {st['detail']}")
        self.write_status()
        return True

    async def watch(self, stop):
        tick = 0
        while not stop.is_set():
            try:
                await asyncio.wait_for(stop.wait(), 1)
            except asyncio.TimeoutError:
                pass
            if self.dirty:
                self.write_status()
            tick += 1
            if tick % WATCH_SECONDS == 0:
                now = lan_addresses(interfaces())
                if now and now != self.addresses:
                    log(f"address changed ({', '.join(self.addresses)} -> {', '.join(now)}); restarting")
                    return 75
        return 0


async def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    config_path, state_dir = sys.argv[1], sys.argv[2]
    try:
        config = read_config(config_path)
    except OSError as e:
        sys.exit(f"cannot read {config_path}: {e}")
    relay = Relay(config, state_dir)
    if not config:
        log(f"nothing to share ({config_path} lists no ports); set LAN_SHARE in secrets.env, then 'lan share apply'")
    if not await relay.start():
        relay.write_status(final=True)
        return 1
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    rc = await relay.watch(stop)
    for srv in relay.servers:
        srv.close()
    relay.write_status(final=True)
    return rc


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
EOF_DEV_LAN_RELAY
        chmod 755 "$HOME/.local/lib/dev-lan/lan-relay.py"
        # A system unit that runs as you: it starts with Linux, without a login session, and writes its
        # state under your home. A unit that already existed keeps its on/off state ('lan share off'
        # before a trip stays off across a setup rerun); a new one is switched on.
        LAN_UNIT=/etc/systemd/system/dev-lan-relay.service
        LAN_UNIT_NEW=0; [ -f "$LAN_UNIT" ] || LAN_UNIT_NEW=1
        sudo tee "$LAN_UNIT" > /dev/null << EOF_DEV_LAN_UNIT
# Written by dev-setup (install-lan-share); rewritten on every run. Configure it with the 'lan share'
# command (LAN_SHARE in ~/.config/dev-init/secrets.env, then 'lan share apply'), not here.
[Unit]
Description=dev-lan relay: shares this machine's services with your other laptops ('lan share')
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
ExecStart=/usr/bin/python3 $HOME/.local/lib/dev-lan/lan-relay.py $HOME/.config/dev-lan/relay.tsv $HOME/.local/state/dev-lan
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_DEV_LAN_UNIT
        sudo systemctl daemon-reload
        # v93: over Tailscale the relay stays off ('tailscale serve' publishes the ports); it is written anyway,
        # for LAN_TAILSCALE=0.
        if [ "$LAN_UNIT_NEW" = 1 ] && { [ "${LAN_TS:-1}" = 0 ] || ! command -v tailscale > /dev/null 2>&1; }; then
            sudo systemctl enable dev-lan-relay.service > /dev/null 2>&1 || true
        fi
        # Writes relay.tsv from LAN_SHARE, then publishes it: over Tailscale with 'tailscale serve' (v93; the
        # relay is stopped), otherwise by (re)starting the relay when it is switched on.
        "$HOME/.local/bin/lan" share apply || true
        sleep 2
        if [ "${LAN_TS:-1}" != 0 ] && command -v tailscale > /dev/null 2>&1; then
            echo "Sharing over Tailscale ('lan share' shows each port; the relay is not used)."
        else
            echo "Relay: $(systemctl is-active dev-lan-relay.service 2> /dev/null || true), $(systemctl is-enabled dev-lan-relay.service 2> /dev/null || true)."
        fi
        "$HOME/.local/bin/lan" share ports || true
    fi

    # The address book is config, not a secret: written now when LAN_HOSTS is filled in, and again by
    # every dev-init run with install-lan (which also reports what answers).
    "$HOME/.local/bin/lan" hosts apply || true
    echo ""
    echo "Laptop network ready. 'lan' shows this machine, 'lan scan' / 'lan probe NAME' the others, 'lan help' every command."
    echo "Fill in LAN_HOSTS (the 100.x Tailscale addresses: 'tailscale status' lists them once joined) and LAN_SHARE"
    echo "in ~/.config/dev-init/secrets.env; dev-init applies them (and joins Tailscale). Ollama on another laptop:"
    echo "http://NAME.internal:11434."
else
    echo "Skipping the laptop network. (Run with 'install-lan' to use the other laptops, 'install-lan-share' to serve them too)"
fi

# =================================================================
# install-com : COM development under Wine (added in v85). Opt-in, in no group, NOT in install-all.
# COM, DCOM and ActiveX are Windows runtime technologies (the registry, the COM service control manager,
# OLE, DLL loading), so Linux runs them through Wine, which implements ole32, oleaut32, rpcss and the
# registry well enough to register and activate real COM servers. This flag installs:
#   Wine, 64-bit AND 32-bit (i386 multiarch): most legacy COM and ActiveX components are 32-bit.
#     The test and demo scripts run Wine with an explicit WINEPREFIX every time; Debian's wine 10
#     in trixie fails to start with the default prefix on some machines (kernel32 status c0000135)
#     and works with one named, so the bundle never relies on ~/.wine.
#   mingw-w64 (gcc, g++, windres for i686 and x86_64): cross-compiles Windows COM DLLs and EXEs
#     from Linux; its headers carry objbase.h, oleauto.h and the rest of the COM API.
#   widl (mingw-w64-tools), Wine's stand-in for MIDL: compiles .idl files into C headers, IIDs,
#     proxy/stub code and type libraries. It needs the system .idl files (unknwn.idl, oaidl.idl...)
#     from libwine-dev and stdole2.tlb from libwine; setup finds both and records them in ~/.bashrc
#     as DEV_COM_IDL_INC, DEV_COM_TLB32 and DEV_COM_TLB64, so builds never guess the paths.
#   winetricks + cabextract: add vcrun, mfc42, dotnet48 and other redistributables into a prefix.
#   A dedicated prefix, ~/.local/share/wine/com (64-bit with a 32-bit side: WoW64), initialized here
#     so a first COM build has somewhere to register into. 'WINEPREFIX=~/.local/share/wine/com' is
#     exported from the marked ~/.bashrc block as DEV_COM_PREFIX, not as WINEPREFIX itself, so other
#     Wine work keeps its own prefix.
# What does NOT work: ATL/MFC (MSVC only; the clang-cl + xwin route needs Microsoft's license and
# is per project), ActiveX in a browser (dead everywhere), Wine as a DCOM server across machines,
# and .NET COM interop at runtime (build here, run on Windows). Wine's own 16-bit support is part of
# wine32 and needs no extra package; install-retro adds the tools to build 16-bit programs.
# =================================================================
if [[ "$FLAGS" =~ " install-com " ]]; then
    echo "================================================================="
    echo "Installing COM development tools: Wine (64 + 32), mingw-w64, widl, winetricks..."
    echo "================================================================="
    if ! dpkg --print-foreign-architectures | grep -qx i386; then
        sudo dpkg --add-architecture i386
        # Not fatal under set -e: one third-party repository failing to refresh should not stop the
        # run when Debian's own i386 lists came in; if they did not, the install below says so.
        sudo apt update || echo "NOTICE: apt update reported errors after adding i386; the Wine install below may fail."
    fi
    # wine32:i386 pulls in libwine:i386 and a few hundred i386 runtime libraries (about 1.3 GB in all,
    # with the 64-bit side). cabextract is what winetricks unpacks Microsoft's .cab redistributables with.
    sudo DEBIAN_FRONTEND=noninteractive apt install -y wine wine64 wine32:i386 libwine-dev \
        gcc-mingw-w64 g++-mingw-w64 mingw-w64-tools cabextract
    # winetricks lives in Debian's contrib section, which a Crostini container does not enable. The
    # script itself is one file: take the current one from its GitHub repository into ~/.local/bin
    # (it updates itself with 'winetricks --self-update').
    mkdir -p ~/.local/bin
    if curl -fsSL --retry 3 -o /tmp/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
        && head -n 1 /tmp/winetricks | grep -q '^#!'; then
        install -m 755 /tmp/winetricks ~/.local/bin/winetricks
        echo "winetricks: $(~/.local/bin/winetricks --version 2> /dev/null | head -n 1)"
    else
        echo "NOTICE: could not download winetricks from GitHub; rerun setup with install-com to retry (Wine works without it)."
    fi
    rm -f /tmp/winetricks

    # Where widl finds the system IDL files and stdole2.tlb: discovered, never assumed, because Debian
    # and Ubuntu put them in different places (/usr/include/wine/windows vs /usr/include/wine/wine/windows).
    # _com_dir_of prints the folder holding the first match, or nothing (never "."), so an empty value
    # reaches ~/.bashrc and the test and demo scripts fall back to their own defaults.
    _com_dir_of() { local f; f=$(find "$@" 2> /dev/null | head -n 1 || true); [ -n "$f" ] && dirname "$f" || true; }
    COM_IDL_INC=$(_com_dir_of /usr/include/wine -name unknwn.idl)
    COM_TLB64=$(_com_dir_of /usr/lib/x86_64-linux-gnu/wine /usr/lib/wine -path '*x86_64-windows/stdole2.tlb')
    COM_TLB32=$(_com_dir_of /usr/lib/i386-linux-gnu/wine /usr/lib/wine -path '*i386-windows/stdole2.tlb')
    [ -n "$COM_IDL_INC" ] || echo "NOTICE: unknwn.idl not found under /usr/include/wine (libwine-dev); widl builds that import oaidl.idl will not find it."
    [ -n "$COM_TLB64" ] || echo "NOTICE: stdole2.tlb (64-bit) not found; 64-bit type libraries that importlib stdole2.tlb will not build."
    [ -n "$COM_TLB32" ] || echo "NOTICE: stdole2.tlb (32-bit) not found (wine32:i386); 32-bit type libraries will not build."

    # The COM prefix: 64-bit with the 32-bit side (Wine's WoW64), so both bitnesses register into it.
    # wineboot takes 10-20 s the first time and creates about 1.2 GB of DLL copies and symlinks.
    COM_PREFIX="$HOME/.local/share/wine/com"
    mkdir -p "$(dirname "$COM_PREFIX")"
    # WINEDLLOVERRIDES keeps wineboot from offering the Mono and Gecko downloads, a dialog that would
    # wait for a click, on the update as well as the first run. 'wineserver -w' then waits until the
    # prefix's registry is written to disk, so the check below and the next steps see the finished prefix.
    if [ ! -f "$COM_PREFIX/system.reg" ]; then
        echo "Creating the COM Wine prefix in $COM_PREFIX (a minute; mscoree/mshtml downloads are turned off)..."
        WINEPREFIX="$COM_PREFIX" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -i > /dev/null 2>&1 || true
        WINEPREFIX="$COM_PREFIX" timeout 120 wineserver -w 2> /dev/null || true
        if [ -f "$COM_PREFIX/system.reg" ]; then
            echo "COM Wine prefix created."
        else
            echo "NOTICE: wineboot did not finish; 'WINEPREFIX=$COM_PREFIX wineboot -i' by hand shows why (dev-init retries)."
        fi
    else
        WINEPREFIX="$COM_PREFIX" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u > /dev/null 2>&1 || true
        WINEPREFIX="$COM_PREFIX" timeout 120 wineserver -w 2> /dev/null || true
        echo "COM Wine prefix $COM_PREFIX already exists (updated)."
    fi

    # ~/.bashrc: a marked block, rewritten on every run. Nothing in it runs a command at shell start.
    sed -i '/^# >>> dev-setup com >>>$/,/^# <<< dev-setup com <<<$/d' ~/.bashrc
    cat >> ~/.bashrc << EOF
# >>> dev-setup com >>>
# Written by dev-setup (install-com); replaced on each run. COM development under Wine.
export DEV_COM_PREFIX="\$HOME/.local/share/wine/com"   # WINEPREFIX for COM work (64-bit + WoW64)
export DEV_COM_IDL_INC="$COM_IDL_INC"                  # widl -I: the system .idl files (libwine-dev)
export DEV_COM_TLB64="$COM_TLB64"                      # widl -L: stdole2.tlb for -m64
export DEV_COM_TLB32="$COM_TLB32"                      # widl -L: stdole2.tlb for -m32
# wine-com: wine inside the COM prefix, quietly.   wine-com regsvr32 my.dll  |  wine-com my_client.exe
wine-com() { WINEPREFIX="\$DEV_COM_PREFIX" WINEDEBUG=-all wine "\$@"; }
# <<< dev-setup com <<<
EOF
    echo "wine: $(wine --version 2> /dev/null)   widl: $(x86_64-w64-mingw32-widl -V 2> /dev/null | head -n 1)"
    echo "mingw: $(x86_64-w64-mingw32-gcc --version | head -n 1)"
    echo "COM prefix: $COM_PREFIX ('wine-com <exe>' runs in it; new terminals have the DEV_COM_* variables)."
    echo "Build a COM server: widl (-m32/-m64, -I \$DEV_COM_IDL_INC, -L \$DEV_COM_TLB64) -> mingw gcc -shared ... -lole32 -loleaut32 -luuid;"
    echo "register it: wine-com regsvr32 server.dll (32 and 64-bit alike); dev-test builds and runs one, dev-demo has a walkthrough."
    echo "DCOM is cross-machine: build and register the server on a Windows laptop (the Windows bundle's job) and reach it from here."
else
    echo "Skipping COM development tools. (Run with 'install-com'; not part of install-all)"
fi

# =================================================================
# install-retro : DOS and Windows 3.x development (added in v85). Opt-in, in no group, NOT in install-all.
#   DOSBox-X (Debian's package): runs DOS programs, and installs and runs Windows 3.1x from your own
#     media. Chosen over DOSBox Staging for its Windows 3.x/9x support. Headless runs (dev-test) use
#     SDL's dummy video driver.
#   Open Watcom v2 (the community continuation of Watcom C/C++, github.com/open-watcom/open-watcom-v2,
#     Sybase Open Watcom Public License): ONE toolchain that builds 16-bit DOS (wcl -bt=dos), 32-bit
#     DOS/4GW (wcl386 -bt=dos -l=dos4g), 16-bit Windows (wcl -bt=windows) and 32-bit Windows
#     (wcl386 -bt=nt) programs, all from Linux. About 150 MB to download, 520 MB installed under
#     /opt/watcom (OW_VERSION pins a release tag; the default is the rolling Current-build snapshot).
#     Its 64-bit Linux binaries (binl64, then binl) go at the END of PATH: binl64 has its own 'vi' and
#     'wrc', which must not shadow the system vi and Wine's wrc. INCLUDE is $WATCOM/h: that covers DOS, and
#     -bt=nt adds h/nt by itself; a 16-bit Windows build must ADD h/win and must not see h/nt:
#         INCLUDE="$WATCOM/h:$WATCOM/h/win" wcl -bt=windows -zw -ml -l=windows app.c
#     dos4gw.exe (the DOS/4GW extender a 32-bit DOS program needs next to it) sits in $WATCOM/binw.
#   A Windows 3.1x workspace, ~/win31: drive_c (the C: drive), install/windows (your Windows 3.1/3.11
#     setup files: loose files from the disks, or .img/.ima disk images), install/apps (Delphi 1 and
#     other installers), and dosbox-x.conf tuned for Windows 3.1x (16 MB RAM, S3 SVGA, C: mounted
#     from drive_c). The 'win31' command starts DOSBox-X on it: 'win31 setup' the first time (mounts
#     the Windows install files as A: or D: and runs SETUP), then 'win31' boots into Windows once
#     C:\WINDOWS exists. Nothing is downloaded for Windows itself: you need your own media.
# Which engine runs what, measured on this bundle's test programs (dev-test's matrix):
#   DOS 16-bit and DOS/4GW 32-bit  -> DOSBox-X. Wine refuses them ("you need to install DOSBox").
#   Windows 16-bit (Win16 NE)      -> Wine's 32-bit side runs them directly (winevdm), no Windows 3.1
#                                     needed; Delphi 1 is a Win16 application, so 'wine' is the quick
#                                     route to try it, DOSBox-X + Windows 3.11 the faithful one.
#   Windows 32-bit and 64-bit      -> Wine.
# install-retro needs Wine, so it pulls in install-com (the flag guard above).
# v92: three engines, five guests, one helper. DOSBox-X keeps DOS and Windows 3.1x (win31) and takes
# Windows 95 (win95, FAT32 on OSR2); QEMU (Debian's qemu-system-x86, qemu-system-gui, qemu-utils) is added
# for Windows NT 4.0 (winnt40) and 2000 (win2000), which DOSBox-X cannot boot; Wine keeps single Windows
# programs and gains a dedicated 32-bit prefix for Delphi 1 (delphi1), the route worked out by hand on
# Oct 2 2026. One helper, ~/.local/lib/dev-retro/dev-retro, holds the logic; win31, win95, winnt40, win2000,
# delphi1 and the umbrella 'retro' in ~/.local/bin are one-line wrappers. Each guest has a launcher icon.
# mtools and dosfstools make and fill the 512 MB FAT16 exchange disk (D: in win95, winnt40 and win2000).
# Nothing is downloaded for any operating system: the media and product keys are yours, in each
# ~/<guest>/install folder (Delphi 1 in ~/win31/install/apps). No disk image is created here: '<cmd> setup'
# creates its disk after a free-space check (min(10 GB, 15% of the Linux disk) must stay free; RETRO_MIN_FREE_GB
# overrides it). QEMU uses KVM where /dev/kvm exists (you are added to the group that owns it) and software
# emulation otherwise. '<guest> fonts' puts the TrueType core fonts and Tahoma from the Wine prefixes on a
# guest, with a README on installing them and on font smoothing (none of these Windows has ClearType); DOS
# programs draw their text screens in a TrueType font (DOSBox-X output=ttf, ~/.config/dev-retro/dos.conf);
# delphi1 sets Integrated debugging off and the editor font in DELPHI.INI. 'retro help' lists every subcommand.
# v93: getting the guests ready for Delphi 3, 4, 5, 6 and 7. Program CDs (.iso) go in ~/<guest>/install/apps and
# are F: in every guest ('<guest> cd FILE|eject|list'; winnt40 and win2000 swap it while running, on a second
# CD drive of its own, and 'cd --windows' swaps the Windows CD). Two sizes are settings, read when a disk is
# created and never before: RETRO_EXCHANGE_MB (the exchange disk, default 1024, 64-2047; '<guest> exchange
# info | recreate') and RETRO_WIN95_DISK_MB (win95's hdd.img, default 2048, 512-8192), in secrets.env or on
# the command line for one run. 'win95 snapshot save | restore | list | delete' keeps undo points of hdd.img
# (sparse copies, guest off). A seventh command, 'delphi N' (N = 3, 4, 5, 6, 7), runs each Delphi under Wine in a
# 32-bit prefix of its own (~/.local/share/wine/delphiN) from ~/delphi/install/N, the CD as D:. libarchive-tools
# (bsdtar) unpacks a Delphi CD's .iso. 'retro sizes' shows the sizes in effect.
# =================================================================
if [[ "$FLAGS" =~ " install-retro " ]]; then
    echo "================================================================="
    echo "Installing retro development tools: DOSBox-X, QEMU, Open Watcom v2, the retro guests (win31, win95, winnt40, win2000, delphi1)..."
    echo "================================================================="
    # dosbox-x is in Debian 13 (trixie); an older container may not have it, which should not stop the
    # rest of setup (set -e), so a failure is a NOTICE and Open Watcom still installs.
    sudo DEBIAN_FRONTEND=noninteractive apt install -y xz-utils
    sudo DEBIAN_FRONTEND=noninteractive apt install -y dosbox-x \
        || echo "NOTICE: apt could not install dosbox-x (it is in Debian 13 'trixie'); DOS programs, 'win31' and 'win95' need it."
    # v92: QEMU for Windows NT 4.0 and 2000 (qemu-system-gui: the GTK window), mtools and dosfstools for the
    # exchange disk, x11-utils (xdpyinfo, xmessage; also in the base list) for the helper.
    sudo DEBIAN_FRONTEND=noninteractive apt install -y qemu-system-x86 qemu-system-gui qemu-utils mtools dosfstools x11-utils \
        || echo "NOTICE: apt could not install QEMU or mtools; 'winnt40', 'win2000' and the exchange disk need them."
    # v93: bsdtar unpacks a Delphi CD's .iso for 'delphi N setup' (Wine has no CD image support of its own).
    sudo DEBIAN_FRONTEND=noninteractive apt install -y libarchive-tools \
        || echo "NOTICE: apt could not install libarchive-tools; 'delphi N setup' then needs the CD's files, not an .iso."
    if [ -e /dev/kvm ]; then
        # The group that owns /dev/kvm (kvm on Debian); nothing to add when it is root or open to everyone.
        KVM_GROUP=$(stat -c %G /dev/kvm 2> /dev/null || echo kvm)
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            echo "KVM: /dev/kvm is usable already: winnt40 and win2000 run at close to native speed."
        elif [ "$KVM_GROUP" != root ] && getent group "$KVM_GROUP" > /dev/null; then
            sudo usermod -aG "$KVM_GROUP" "$USER"
            echo "KVM: added you to the $KVM_GROUP group, which owns /dev/kvm (it applies after Linux is shut down and reopened)."
        else
            echo "NOTICE: /dev/kvm is here but owned by group '$KVM_GROUP' and not usable by you; QEMU will use software emulation."
        fi
    else
        echo "KVM: no /dev/kvm on this Chromebook: NT 4.0 and 2000 will run in QEMU's software emulation (slower)."
    fi
    mkdir -p ~/.local/bin

    # --- Open Watcom v2 ---
    OW_TAG="${OW_VERSION:-Current-build}"
    OW_URL="https://github.com/open-watcom/open-watcom-v2/releases/download/$OW_TAG/ow-snapshot.tar.xz"
    OW_HOME=/opt/watcom
    OW_DL="$ASSETS/downloads/ow-snapshot-$OW_TAG.tar.xz"
    # The Current-build asset is replaced in place upstream, so a rerun compares its size with the
    # copy already installed (recorded in /opt/watcom/.dev-setup-size) before downloading 150 MB again.
    # '|| true': under set -e and pipefail, a GitHub that does not answer must not end the run here.
    OW_REMOTE_SIZE=$(curl -fsSIL --max-time 30 "$OW_URL" 2> /dev/null | grep -i '^content-length:' | tail -n 1 | tr -dc '0-9' || true)
    if [ -x "$OW_HOME/binl64/wcl" ] && [ -n "$OW_REMOTE_SIZE" ] && [ "$(cat "$OW_HOME/.dev-setup-size" 2> /dev/null)" = "$OW_REMOTE_SIZE" ]; then
        echo "Open Watcom in $OW_HOME is the current $OW_TAG snapshot; skipping the download."
    elif [ -x "$OW_HOME/binl64/wcl" ] && [ -z "$OW_REMOTE_SIZE" ]; then
        echo "Open Watcom is installed and GitHub did not answer; keeping it."
    else
        # A partial file left by an interrupted run is resumed (wget -c) only while it is smaller than
        # the asset on GitHub; Current-build is replaced in place, so anything else starts over.
        if [ -f "$OW_DL" ] && { [ -z "$OW_REMOTE_SIZE" ] || [ "$(stat -c %s "$OW_DL")" -ge "$OW_REMOTE_SIZE" ]; }; then
            rm -f "$OW_DL"
        fi
        echo "Downloading Open Watcom v2 ($OW_TAG, about 150 MB)..."
        if wget -c -q --show-progress -O "$OW_DL" "$OW_URL"; then
            # Unpacked straight into /opt (about 520 MB), not /tmp: /tmp is a RAM-backed tmpfs on trixie,
            # and a move from it to /opt would copy everything a second time. One pass of tar both checks
            # the archive and unpacks it; a damaged download fails here and is deleted.
            sudo rm -rf "$OW_HOME.new"
            sudo mkdir -p "$OW_HOME.new"
            if sudo tar -xJf "$OW_DL" -C "$OW_HOME.new" --no-same-owner && [ -x "$OW_HOME.new/binl64/wcl" ]; then
                sudo chmod -R a+rX "$OW_HOME.new"
                sudo rm -rf "$OW_HOME"
                sudo mv "$OW_HOME.new" "$OW_HOME"
                echo "${OW_REMOTE_SIZE:-$(stat -c %s "$OW_DL")}" | sudo tee "$OW_HOME/.dev-setup-size" > /dev/null
                echo "Open Watcom installed in $OW_HOME."
            else
                sudo rm -rf "$OW_HOME.new"
                echo "NOTICE: the Open Watcom archive was damaged or lacked binl64/wcl; not installed (rerun setup to retry)."
            fi
            rm -f "$OW_DL"
        else
            echo "NOTICE: could not download Open Watcom from GitHub; rerun setup with install-retro to resume (DOSBox-X works without it)."
        fi
    fi

    # --- ~/win31: the Windows 3.1x workspace and the 'win31' launcher ---
    WIN31="$HOME/win31"
    mkdir -p "$WIN31/drive_c" "$WIN31/install/windows" "$WIN31/install/apps"
    if [ ! -f "$WIN31/dosbox-x.conf" ]; then
        cat > "$WIN31/dosbox-x.conf" << 'EOF_DBX'
# ~/win31/dosbox-x.conf - written by dev-setup (install-retro) once; edit it freely, setup leaves it alone.
# A Windows 3.1x machine: 16 MB, S3 SVGA (Windows can use the S3 driver for more than 640x480x16),
# Sound Blaster 16, C: mounted from ~/win31/drive_c. The 'win31' command adds the mounts.
[sdl]
autolock=true
output=opengl
[dosbox]
title=Windows 3.1x (dev-setup)
machine=svga_s3
memsize=16
[cpu]
core=auto
cputype=pentium
cycles=max
[sblaster]
sbtype=sb16
[dos]
xms=true
ems=true
umb=true
# Leave 32-bit disk access OFF in Windows setup: it does not work on folder-mounted drives.
EOF_DBX
    fi
    # --- v92: the retro helper and its six commands ---
    # Written to a new file and moved into place, so a guest that is running keeps its copy (a new inode).
    mkdir -p ~/.local/lib/dev-retro
    cat > ~/.local/lib/dev-retro/dev-retro.new << 'DEVRETRO_EOF'
#!/bin/bash
# shellcheck disable=SC2015,SC1003   # A && B || C is meant as written; the backslash patterns are literal
# dev-retro - the shared helper behind win31, win95, winnt40, win2000, delphi1, delphi and retro
# (dev-setup install-retro, v92; v93). Written by dev-setup into ~/.local/lib/dev-retro and rewritten on
# every run: copy it before editing. The seven commands in ~/.local/bin are one-line wrappers that call it
# with their name.
#
# Three engines, each for what it runs best on these Chromebooks:
#   win31    Windows 3.1x    DOSBox-X   ~/win31/install/windows   ~/win31/drive_c (a folder)
#   win95    Windows 95      DOSBox-X   ~/win95/install           ~/win95/hdd.img (FAT32 with OSR2)
#   winnt40  Windows NT 4.0  QEMU       ~/winnt40/install         ~/winnt40/disk.qcow2
#   win2000  Windows 2000    QEMU       ~/win2000/install         ~/win2000/disk.qcow2
#   delphi1  Delphi 1 alone  Wine       ~/win31/install/apps      ~/.local/share/wine/delphi1 (32-bit prefix)
#   delphi N Delphi 3-7      Wine       ~/delphi/install/N        ~/.local/share/wine/delphiN (32-bit prefix)
# Your media and product keys go in each install/ folder; nothing is downloaded for any operating system.
# Program CDs (.iso) for a guest go in ~/<guest>/install/apps: the app CD is F: in every guest.
#
# Settings, read when a disk is created (nothing is created before): a line in
# ~/.config/dev-init/secrets.env, or the same name on the command line for one run, which wins:
#   RETRO_EXCHANGE_MB=1024     the exchange disk, 64-2047 MB (FAT16); 512 for the v92 size
#   RETRO_WIN95_DISK_MB=2048   Windows 95's hdd.img, 512-8192 MB (FAT32)
#   e.g.  RETRO_EXCHANGE_MB=512 win2000 setup
# A disk that exists is never resized: '<guest> exchange recreate' rebuilds the exchange disk at the new
# size; win95's disk keeps its size ('retro sizes' shows what is in effect and what each disk has).
#
# Every guest command:
#   <cmd>                    boot the installed guest (or say how to install it)
#   <cmd> setup              first install from your media; creates the disk after a free-space check;
#                            run again, it resumes a half-done install
#   <cmd> run FILE           put FILE where the guest can reach it, then boot
#   <cmd> where | status | launcher | help
# win31, win95, winnt40, win2000:
#   <cmd> fonts              the TrueType core fonts and Tahoma (from the Wine prefixes) with a README.TXT
#                            on installing them and turning on font smoothing: C:\FONTS for win31, D:\FONTS
#                            (the exchange disk) for the others. ClearType began with Windows XP: these guests
#                            get grayscale smoothing at most (95 with Plus!, NT 4.0, 2000), 3.1 none
# win31, win95, winnt40, win2000 (v93):
#   <cmd> cd FILE.iso | eject | list          the app CD (F:) from ~/<guest>/install/apps; the choice is
#                                             kept in ~/<guest>/apps-cd. win31 and win95 take it at the next
#                                             start (DOSBox-X cannot swap it from outside); winnt40 and
#                                             win2000 swap it while running too
# win95, winnt40, win2000:
#   <cmd> put FILE... / get [NAME]   copy into / out of the exchange disk (D: in the guest) while it is off
#   <cmd> exchange info              its size, layout and free space
#   <cmd> exchange recreate [--yes]  rebuild it empty at RETRO_EXCHANGE_MB ('get' saves its files first)
# winnt40, win2000 (QEMU):
#   <cmd> cd --windows ISO|eject              swap the Windows CD (E:) while running
#   <cmd> floppy IMG|eject                    swap the floppy while running
#   <cmd> keys ctrl-alt-del                   keys ChromeOS keeps for itself (the NT login needs this one)
#   <cmd> snapshot save NAME | restore NAME | list | delete NAME      undo points on the qcow2 disk
# win95 (v93):
#   win95 snapshot save NAME | restore NAME [--yes] | list | delete NAME
#                            undo points: sparse copies of hdd.img in ~/win95/snapshots, guest off only
# delphi (v93; Delphi 3, 4, 5, 6 and 7 under Wine, one 32-bit prefix each):
#   delphi                   which versions are set up, and where each one's media goes
#   delphi N setup [FILE]    create the prefix, run the installer from ~/delphi/install/N (an .iso or the
#                            CD's files), then apply the settings below; FILE picks another installer
#   delphi N                 start the IDE in a virtual desktop sized to the screen
#   delphi N run FILE        another program in the same desktop
#   delphi N launcher        point Delphi's own launcher entries at 'delphi N'
#   delphi N ini save        keep the IDE's options (HKCU\Software\Borland in the prefix's registry) in
#                            ~/.config/dev-retro/delphiN.reg; 'delphi N setup' restores them
#   Settings per prefix: the Windows version Wine reports (3: win95, 4: win98, 5: win2k, 6: win2k, 7: winxp), black
#   desktop, TEMP=C:\TEMP, MS Sans Serif -> Tahoma, corefonts + tahoma, fontsmooth=rgb. The integrated
#   debugger stays on: 'delphi N help' notes what was found with each version.
# retro:
#   retro                    the guests: installed or not, running or stopped (Delphi 3-7 once set up)
#   retro sizes              the disk sizes in effect (RETRO_EXCHANGE_MB, RETRO_WIN95_DISK_MB) and each disk's
#   retro run [--in win31|win95|winnt40|win2000|wine|dos] FILE
#                            run one program; without --in the engine is picked from the file's header:
#                            DOS (MZ, LE) -> DOSBox-X, Win16 (NE) -> Wine's delphi1 prefix, Win32/64 (PE) -> Wine's COM prefix
#   retro which FILE         what 'retro run' would pick, and why
# DOS programs run with ~/.config/dev-retro/dos.conf (written once): output=ttf draws DOS text screens in a
# TrueType font smoothed by Linux; graphics screens switch to the normal output by themselves.
# delphi1: 'delphi1 setup' and every IDE start set IntegratedDebugging=0 in DELPHI.INI (C:\WINDOWS; Wine has
# no Win16 debugger), and the editor font Courier New 10 where none is set; 'delphi1 ini save' keeps the rest.
set -o pipefail
SELF=$(readlink -f "$0")
STATE="$HOME/.local/state/dev-retro"
mkdir -p "$STATE"
export MTOOLS_SKIP_CHECK=1
EXCH_OFF=32256                     # the exchange disk's partition starts at sector 63
SECRETS="$HOME/.config/dev-init/secrets.env"
DELPHI_VERSIONS="3 4 5 6 7"
DELPHI_PREFIX="$HOME/.local/share/wine/delphi1"
COM_PREFIX="${DEV_COM_PREFIX:-$HOME/.local/share/wine/com}"
# Delphi's own 16-bit OLE2 (copied into C:\WINDOWS\SYSTEM by its setup) instead of Wine 10's built-in
# compobj.dll16, which hands Delphi's startup code no allocator. The .dll16 suffix is required.
DELPHI_OLE="compobj.dll16,ole2.dll16,ole2disp.dll16,ole2nls.dll16,storage.dll16,typelib.dll16=n"

die()  { echo "$*" >&2; exit 1; }
# A launcher icon starts this with no terminal (its entry sets DEV_RETRO_LAUNCHER=1): output then goes to a
# log, and messages also to a window. Scripts calling it (dev-test, dev-demo) keep their output.
INTERACTIVE=1
if [ "${DEV_RETRO_LAUNCHER:-0}" = 1 ] && [ ! -t 1 ]; then
    INTERACTIVE=0
    exec >> "$STATE/launcher.log" 2>&1
    echo "--- $(date '+%F %T') $(basename "$0") $*"
fi
tell() {   # tell TEXT: print it, and show it in a window when started from a launcher icon
    echo "$*"
    if [ "$INTERACTIVE" = 0 ] && command -v xmessage > /dev/null 2>&1; then
        xmessage -center -title "dev-retro" "$*" > /dev/null 2>&1 &
    fi
}
free_gb()   { df -Pk "${1:-$HOME}" | awk 'NR == 2 {print int($4 / 1024 / 1024)}'; }
margin_gb() {   # min(CAP, 15% of the Linux disk), as dev-setup's disk guards
    local total pct
    total=$(df -Pk / | awk 'NR == 2 {print int($2 / 1024 / 1024)}')
    pct=$(( ${total:-0} * 15 / 100 )); [ "$pct" -ge 1 ] || pct=1
    [ "$pct" -lt "$1" ] && echo "$pct" || echo "$1"
}
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
# v93: get_setting NAME DEFAULT MIN MAX: sets SET_VAL and SET_SRC (command line, secrets.env or default).
# The value in the environment wins (RETRO_EXCHANGE_MB=512 win2000 setup); secrets.env is read in a subshell,
# so nothing else from it comes along. A value out of range stops the command before anything is created.
get_setting() {
    local v="${!1:-}" f=""
    [ -r "$SECRETS" ] && f=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$SECRETS" "$1" 2> /dev/null)
    SET_SRC="command line"
    # The same value as the file's (a shell that sourced secrets.env exports it) counts as secrets.env's.
    if [ -z "$v" ] || [ "$v" = "$f" ]; then v=$f; SET_SRC=secrets.env; fi
    [ -n "$v" ] || { v=$2; SET_SRC=default; }
    if ! [[ "$v" =~ ^[0-9]+$ ]] || [ "$v" -lt "$3" ] || [ "$v" -gt "$4" ]; then
        die "$1=$v ($SET_SRC) is not a size from $3 to $4 MB: fix it (secrets.env: $SECRETS) and run the command again."
    fi
    SET_VAL=$v
}
exch_setting()  { get_setting RETRO_EXCHANGE_MB 1024 64 2047; }      # FAT16 ends at 2 GB
win95_setting() { get_setting RETRO_WIN95_DISK_MB 2048 512 8192; }
yes_no() {   # yes_no QUESTION: 0 on y; refuses (1) without a terminal to ask on
    local a
    [ "$INTERACTIVE" = 1 ] && [ -t 0 ] || return 1
    read -rp "$1 [y/N] " a
    [ "$(lc "$a")" = y ]
}
screen_size() { xdpyinfo 2> /dev/null | awk '/dimensions:/ {print $2; exit}' | grep -E '^[0-9]+x[0-9]+$' || echo 1366x768; }

# --- the guests ---------------------------------------------------------------------------------
guest_info() {   # sets WS ENGINE TITLE for GUEST
    case "$1" in
        win31)   WS="$HOME/win31";   ENGINE=dosbox-x; TITLE="Windows 3.1" ;;
        win95)   WS="$HOME/win95";   ENGINE=dosbox-x; TITLE="Windows 95" ;;
        winnt40) WS="$HOME/winnt40"; ENGINE=qemu;     TITLE="Windows NT 4.0" ;;
        win2000) WS="$HOME/win2000"; ENGINE=qemu;     TITLE="Windows 2000" ;;
        delphi1) WS="$DELPHI_PREFIX"; ENGINE=wine;    TITLE="Delphi 1" ;;
        delphi3|delphi4|delphi5|delphi6|delphi7) dn_info "${1#delphi}"; WS="$DN_PREFIX"; ENGINE=wine; TITLE="$DN_TITLE" ;;
        *) return 1 ;;
    esac
}
GUESTS="win31 win95 winnt40 win2000 delphi1"

running() {   # running GUEST: its engine is up (pid file written at start)
    local pid
    guest_info "$1" || return 1
    pid=$(cat "$WS/.pid" 2> /dev/null) || return 1
    [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null
}
mark_running() { echo "$1" > "$WS/.pid"; }
need_stopped() { running "$1" && die "$TITLE is running: shut it down from its Start menu first (or close the window)."; return 0; }

# installed GUEST: prints how far it got; 0 = installed (or a disk exists)
installed() {
    guest_info "$1" || return 1
    case "$1" in
        win31)
            [ -f "$WS/drive_c/WINDOWS/WIN.COM" ] || [ -f "$WS/drive_c/windows/win.com" ] || [ -n "$(find "$WS/drive_c" -maxdepth 2 -iname win.com 2> /dev/null | head -n 1)" ] ;;
        win95)
            [ -f "$WS/hdd.img" ] && mdir -i "$WS/hdd.img@@$(part_offset "$WS/hdd.img")" ::/WINDOWS/WIN.COM > /dev/null 2>&1 ;;
        winnt40|win2000)
            [ -f "$WS/disk.qcow2" ] || [ -f "$WS/disk.img" ] ;;
        delphi1)
            [ -n "$(find "$WS/drive_c" -maxdepth 3 -ipath '*/delphi/bin/delphi.exe' 2> /dev/null | head -n 1)" ] ;;
        delphi3|delphi4|delphi5|delphi6|delphi7) dn_installed ;;
    esac
}
part_offset() {   # byte offset of the first partition of a disk image (63 sectors when unreadable)
    python3 - "$1" << 'PY' 2> /dev/null || echo 32256
import struct, sys
with open(sys.argv[1], 'rb') as f:
    mbr = f.read(512)
start = struct.unpack('<I', mbr[454:458])[0] if mbr[510:512] == b'\x55\xaa' else 0
print((start or 63) * 512)
PY
}

# --- the exchange disk (win95, winnt40, win2000) ------------------------------------------------
# One FAT16 partition (type 06) at sector 63, geometry 16 heads x 63 sectors: every guest here reads it
# (NT 4.0 included), DOSBox-X mounts it, and mtools reaches it from Linux while the guest is off.
# v93: the size is RETRO_EXCHANGE_MB (default 1024; v92 made 512 MB disks), read when the disk is created.
# Above 504 MB the cylinder count passes the BIOS's 1024 (512 MB is 1040, 1 GB 2080): DOSBox-X's imgmount
# gets the true count and the guests read the disk by LBA. RETRO_EXCHANGE_HEADS=255 makes a new disk with
# 255 heads instead (fewer cylinders), the fallback should a guest misread a big 16-head disk. A disk that
# exists keeps its size and layout: they are read back from the image itself.
exch_geom() {   # exch_geom IMG: "MB HEADS SECTORS CYLINDERS" of an existing exchange disk
    python3 - "$1" << 'PY' 2> /dev/null || echo "0 16 63 0"
import os, struct, sys
p = sys.argv[1]
with open(p, 'rb') as f:
    f.seek(63 * 512); bs = f.read(512)
spt, heads = struct.unpack('<HH', bs[0x18:0x1C]) if len(bs) == 512 and bs[510:512] == b'\x55\xaa' else (0, 0)
if not (1 <= spt <= 63 and 1 <= heads <= 255):
    spt, heads = 63, 16
size = os.path.getsize(p)
print((size + 1048575) // 1048576, heads, spt, size // (heads * spt * 512))   # MB rounded up: cylinders cut a little off
PY
}
size_differs() { [ $(( $1 - $2 )) -ge 2 ] || [ $(( $2 - $1 )) -ge 2 ]; }   # MB values, rounding aside
exch_create() {   # exch_create WS
    local img="$1/exchange.img" total mb heads have
    if [ -f "$img" ]; then
        # An existing disk is never resized; a different setting is pointed out (once per command).
        ( exch_setting ) > /dev/null 2>&1 || return 0
        exch_setting
        read -r have _ <<< "$(exch_geom "$img")"
        if [ "${have:-0}" -gt 0 ] && size_differs "$have" "$SET_VAL" && [ -z "${EXCH_NOTED:-}" ]; then
            echo "Note: the exchange disk is $have MB; RETRO_EXCHANGE_MB is $SET_VAL ($SET_SRC). '$GUEST exchange recreate' rebuilds it at $SET_VAL MB (empty)." >&2
            EXCH_NOTED=1
        fi
        return 0
    fi
    command -v mkfs.fat > /dev/null && command -v mcopy > /dev/null || die "mtools and dosfstools are missing: rerun dev-setup with install-retro."
    exch_setting; mb=$SET_VAL
    heads=${RETRO_EXCHANGE_HEADS:-16}
    case "$heads" in 16|255) ;; *) die "RETRO_EXCHANGE_HEADS=$heads: 16 (the default) or 255." ;; esac
    [ "$(free_gb "$1")" -gt $(( mb / 1024 + 1 )) ] || die "not enough free disk for a $mb MB exchange disk (RETRO_EXCHANGE_MB=512 makes a smaller one)."
    total=$(python3 - "$img" "$mb" "$heads" << 'PY'
import struct, sys
path, mb, H = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
S = 63
cyl = mb * 1024 * 1024 // (H * S * 512)
total = cyl * H * S
start, count = S, total - S
def chs(lba):
    c = lba // (H * S); h = (lba // S) % H; s = lba % S + 1
    if c > 1023: c, h, s = 1023, H - 1, S
    return bytes([h, ((c >> 2) & 0xC0) | s, c & 0xFF])
mbr = bytearray(512)
mbr[446:462] = bytes([0x00]) + chs(start) + bytes([0x06]) + chs(start + count - 1) + struct.pack('<II', start, count)
mbr[510:512] = b'\x55\xaa'
with open(path, 'wb') as f:
    f.write(mbr)
    f.truncate(total * 512)
print(total)
PY
    ) || die "could not create $img"
    mkfs.fat -F 16 -n EXCHANGE --offset 63 -h 63 -g "$heads/63" "$img" $(( (total - 63) / 2 )) > /dev/null || { rm -f "$img"; die "mkfs.fat failed on $img"; }
    echo "Created the exchange disk $img ($mb MB, FAT16; RETRO_EXCHANGE_MB from $SET_SRC): D: in the guest."
}
exch_mount_size() {   # the -size value DOSBox-X's imgmount needs for the exchange disk of WS
    local mb h s c
    read -r mb h s c <<< "$(exch_geom "$1/exchange.img")"
    echo "512,$s,$h,$c"
}
exch_free() {   # free bytes on the exchange disk image IMG, from mtools
    mdir -i "$1@@$EXCH_OFF" :: 2> /dev/null | sed -n 's/^ *\([0-9 ]*\) bytes free.*/\1/p' | tr -d ' '
}
exch_cmd() {   # exch_cmd GUEST info|recreate [--yes]
    local img="$WS/exchange.img" mb h s c free yes=0 a
    for a in "${@:3}"; do [ "$a" = --yes ] && yes=1; done
    case "${2:-info}" in
        info)
            exch_setting
            if [ ! -f "$img" ]; then
                echo "No exchange disk yet: the first '$1 put', '$1 fonts' or '$1 setup' makes one of $SET_VAL MB (RETRO_EXCHANGE_MB, $SET_SRC)."
                return 0
            fi
            read -r mb h s c <<< "$(exch_geom "$img")"
            free=$(exch_free "$img")
            echo "$img: $mb MB, FAT16, $c cylinders x $h heads x $s sectors; $(numfmt --to=iec --suffix=B "${free:-0}" 2> /dev/null || echo "${free:-?} bytes") free"
            if size_differs "$mb" "$SET_VAL"; then
                echo "D: in $TITLE. RETRO_EXCHANGE_MB is $SET_VAL ($SET_SRC): '$1 exchange recreate' rebuilds the disk at that size."
            else
                echo "D: in $TITLE. RETRO_EXCHANGE_MB is $SET_VAL ($SET_SRC)."
            fi
            mdir -i "$img@@$EXCH_OFF" -w :: 2> /dev/null | sed -n '1,25p' ;;
        recreate)
            need_stopped "$1"
            exch_setting
            if [ -f "$img" ]; then
                read -r mb _ <<< "$(exch_geom "$img")"
                if [ -n "$(mdir -i "$img@@$EXCH_OFF" -b :: 2> /dev/null | head -n 1)" ]; then
                    echo "The exchange disk ($mb MB) holds files:"; mdir -i "$img@@$EXCH_OFF" -w :: 2> /dev/null | sed -n '1,12p'
                    if [ "$yes" = 1 ] || yes_no "Copy them to $WS/from-guest first (as '$1 get' does)?"; then
                        ( exch_get "$1" > /dev/null ) && echo "Copied to $WS/from-guest."
                    fi
                fi
                if [ "$yes" != 1 ] && ! yes_no "Rebuild $img empty at $SET_VAL MB (it is $mb MB now)?"; then
                    echo "Left as it is ('$1 exchange recreate --yes' skips the questions and saves the files first)."; return 1
                fi
                rm -f "$img"
            fi
            exch_create "$WS" ;;
        *) die "usage: $1 exchange info | recreate [--yes]" ;;
    esac
}
exch_put() {   # exch_put GUEST PATH...: copy files or folders into the exchange disk's root
    local p
    guest_info "$1"; shift
    need_stopped "$GUEST"
    exch_create "$WS"
    [ $# -gt 0 ] || die "usage: $GUEST put FILE|FOLDER..."
    for p in "$@"; do
        [ -e "$p" ] || die "no such file: $p"
        mcopy -i "$WS/exchange.img@@$EXCH_OFF" -s -o -Q "$p" :: || die "could not copy $p (is the exchange disk full? '$GUEST get' lists it)"
        echo "put $(basename "$p") -> D:\\$(basename "$p")"
    done
}
exch_get() {   # exch_get GUEST [NAME]: copy NAME (or everything) out into WS/from-guest
    local out
    guest_info "$1"; shift
    need_stopped "$GUEST"
    [ -f "$WS/exchange.img" ] || die "no exchange disk yet: '$GUEST put FILE' or '$GUEST setup' makes it."
    out="$WS/from-guest"; mkdir -p "$out"
    if [ -z "${1:-}" ]; then
        mdir -i "$WS/exchange.img@@$EXCH_OFF" -/ :: 2> /dev/null | sed -n '1,40p'
        mcopy -i "$WS/exchange.img@@$EXCH_OFF" -s -n -Q '::*' "$out/" 2> /dev/null || true
    else
        mcopy -i "$WS/exchange.img@@$EXCH_OFF" -s -n -Q "::$1" "$out/" || die "no $1 on the exchange disk ('$GUEST get' lists it)"
    fi
    echo "Copied to $out"
}

# --- media ----------------------------------------------------------------------------------------
bootable_iso() { dd if="$1" bs=2048 skip=17 count=1 2> /dev/null | grep -aq 'EL TORITO'; }
find_isos() { find "$WS/install" -maxdepth 1 -type f -iname '*.iso' 2> /dev/null | sort; }
install_iso() {   # the first bootable ISO in install/ (the Windows CD); else the first ISO
    local i first=""
    while IFS= read -r i; do
        [ -n "$first" ] || first=$i
        bootable_iso "$i" && { echo "$i"; return 0; }
    done < <(find_isos)
    [ -n "$first" ] && echo "$first"
}
floppies() { find "$WS/install" -maxdepth 1 -type f \( -iname '*.img' -o -iname '*.ima' -o -iname '*.vfd' \) 2> /dev/null | sort; }

# --- app CDs (v93) ---------------------------------------------------------------------------------
# Program CDs (.iso: Delphi, Office, a compiler) go in ~/<guest>/install/apps, apart from the Windows CD in
# install/. The app CD is F: in every guest: win31 (DOSBox-X's own CD support, beside D: = install/apps
# itself), win95 (IDE secondary slave, beside the Windows CD as E:), winnt40 and win2000 (the second IDE
# CD drive, ide1-cd1; E: is the Windows CD). Which one: the last '<cmd> cd FILE' chose (kept in
# ~/<guest>/apps-cd), else the first .iso in install/apps; '<cmd> cd eject' records none.
app_isos() { find "$WS/install/apps" -maxdepth 1 -type f -iname '*.iso' 2> /dev/null | sort; }
app_cd() {   # the app CD for the next start (empty: none)
    local c
    if [ -f "$WS/apps-cd" ]; then
        c=$(cat "$WS/apps-cd")
        [ "$c" = none ] && return 0
        [ -f "$c" ] && { echo "$c"; return 0; }
        echo "Note: the app CD chosen earlier ($c) is gone; using the first in $WS/install/apps." >&2
    fi
    app_isos | head -n 1
}
app_resolve() {   # app_resolve ARG: an .iso path, or a name in install/apps (with or without .iso)
    local f
    if [ -f "$1" ]; then readlink -f "$1"; return 0; fi
    f=$(find "$WS/install/apps" -maxdepth 1 -type f \( -iname "$1" -o -iname "$1.iso" \) 2> /dev/null | sort | head -n 1)
    [ -n "$f" ] && echo "$f"
}
cd_cmd() {   # cd_cmd GUEST [--windows] FILE.iso|eject|list
    local g=$1 win=0 a f cur dev
    shift
    [ "${1:-}" = --windows ] && { win=1; shift; }
    a=${1:-list}
    if [ "$win" = 1 ]; then
        case "$g" in winnt40|win2000) ;; *) die "$g takes its Windows CD from $WS/install when it starts ('cd --windows' is for winnt40 and win2000)." ;; esac
        running "$g" || die "$TITLE is not running: its Windows CD is the first bootable .iso in $WS/install at the next start."
        if [ "$a" = eject ]; then hmp "eject -f ide1-cd0" && echo "Windows CD (E:) ejected."
        else f=$(readlink -f "$a" 2> /dev/null); [ -f "$f" ] || die "no such file: $a"; hmp "change ide1-cd0 \"$f\"" && echo "$(basename "$f") is in E:."; fi
        return
    fi
    case "$a" in
        list)
            cur=$(app_cd 2> /dev/null)
            echo "App CDs in $WS/install/apps (F: in $TITLE):"
            if [ -z "$(app_isos)" ]; then echo "  none: copy program CDs there as .iso files"; fi
            while IFS= read -r f; do
                [ -n "$f" ] || continue
                if [ "$f" = "$cur" ]; then echo "  * $(basename "$f")   (the next start's F:)"; else echo "    $(basename "$f")"; fi
            done < <(app_isos)
            [ -n "$cur" ] && [ "$(dirname "$cur")" != "$WS/install/apps" ] && echo "  * $cur   (chosen with '$g cd', outside install/apps)"
            [ -z "$cur" ] && [ -n "$(app_isos)" ] && echo "  (none chosen: '$g cd eject' was the last choice; '$g cd NAME' picks one)"
            return 0 ;;
        eject)
            echo none > "$WS/apps-cd"
            if running "$g" && [ "$ENGINE" = qemu ]; then hmp "eject -f ide1-cd1" && echo "App CD (F:) ejected."
            else echo "No app CD at the next start of $TITLE."; fi ;;
        *)
            f=$(app_resolve "$a") || true
            [ -n "$f" ] || die "no such .iso: $a ('$g cd list' shows $WS/install/apps)"
            echo "$f" > "$WS/apps-cd"
            if running "$g" && [ "$ENGINE" = qemu ]; then
                hmp "change ide1-cd1 \"$f\"" && echo "$(basename "$f") is in F:."
            elif running "$g"; then
                echo "$(basename "$f") will be F: at the next start: DOSBox-X cannot swap that CD from outside while $TITLE runs."
            else
                echo "$(basename "$f") will be F: when $TITLE starts."
            fi ;;
    esac
}

# --- disk guard -------------------------------------------------------------------------------------
disk_guard() {   # disk_guard GUEST NEED_GB: refuse (recording why) when the disk would get too full
    local need=$2 free margin why
    free=$(free_gb "$WS"); margin=${RETRO_MIN_FREE_GB:-$(margin_gb 10)}
    if [ "${RETRO_FORCE:-0}" != 1 ] && [ "$free" -lt $(( need + margin )) ]; then
        why="disk: $free GB free, $(( need + margin )) GB needed ($TITLE's $need GB disk + RETRO_MIN_FREE_GB=$margin). Resize the Linux disk (ChromeOS Settings > About ChromeOS > Linux development environment > Disk size), or rerun with RETRO_MIN_FREE_GB=<n> (RETRO_FORCE=1 skips the check)"
        echo "$why" > "$WS/setup.skipped"
        tell "$TITLE: not creating its disk. $why"
        exit 1
    fi
    rm -f "$WS/setup.skipped"
}

# =================================================================================================
# win31 (DOSBox-X, a folder as C:) - the v85 behaviour, plus 'run' starting Windows programs in Windows
# =================================================================================================
win31_cmd() {
    local mode=${1:-boot} conf="$WS/dosbox-x.conf" args f imgs kind app
    [ -f "$conf" ] || die "no $conf: rerun dev-setup with install-retro."
    need_stopped win31
    args=(-conf "$conf" -c "mount c \"$WS/drive_c\"")
    [ -d "$WS/install/apps" ] && args+=(-c "mount d \"$WS/install/apps\"")
    # v93: an app CD (.iso in install/apps) as F:, through DOSBox-X's CD-ROM support (MSCDEX).
    app=$(app_cd)
    [ -n "$app" ] && { args+=(-c "imgmount f \"$app\" -t iso"); echo "App CD: $(basename "$app") as F:."; }
    case "$mode" in
        boot)
            if installed win31; then
                args+=(-c "c:" -c "cd \\windows" -c "win")
            else
                tell "Windows 3.1 is not installed in $WS/drive_c yet: 'win31 setup' installs it from $WS/install/windows."
                [ "$INTERACTIVE" = 1 ] || exit 1
                args+=(-c "c:")
            fi ;;
        setup)
            # Every image on one imgmount, each path quoted: DOSBox-X swaps to the next with DOS > Swap floppy.
            imgs=$(find "$WS/install/windows" -maxdepth 1 -type f \( -iname '*.img' -o -iname '*.ima' \) 2> /dev/null | sort | sed 's/.*/"&"/' | tr '\n' ' ')
            if [ -n "$imgs" ]; then
                args+=(-c "imgmount a $imgs -t floppy" -c "a:" -c "setup")
            elif [ -n "$(find "$WS/install/windows" -maxdepth 1 -type f -iname setup.exe 2> /dev/null)" ]; then
                args+=(-c "mount a \"$WS/install/windows\"" -c "a:" -c "setup")
            else
                tell "No Windows 3.1 setup files in $WS/install/windows: copy the loose files from the disks (setup.exe with them), or the .img/.ima images."
                exit 1
            fi ;;
        dos) args+=(-c "c:") ;;
        run)
            f=$(readlink -f "${2:?usage: win31 run FILE}") || exit 1
            [ -f "$f" ] || die "no such file: $2"
            kind=$(exe_kind "$f")
            args+=(-c "mount e \"$(dirname "$f")\"")
            if [ "$kind" = win16 ] && installed win31; then
                args+=(-c "c:" -c "cd \\windows" -c "win e:\\$(basename "$f")")
            elif [ "$kind" = win16 ]; then
                die "$(basename "$f") is a Windows 3.x program, and Windows 3.1 is not installed yet ('win31 setup')."
            else
                args+=(-c "e:" -c "$(basename "$f")")
            fi ;;
        *) die "usage: win31 [boot|setup|dos|run FILE|where|status|launcher|help]" ;;
    esac
    mark_running $$
    dosbox-x "${args[@]}"; local rc=$?
    rm -f "$WS/.pid"; return $rc
}

# =================================================================================================
# win95 (DOSBox-X booting a FAT32 disk image; DOSBox-X's own Windows 95 guide)
# =================================================================================================
# v93: hdd.img's size is RETRO_WIN95_DISK_MB (default 2048; v92 made 1024 MB), read when it is created.
win95_confs() {   # write setup.conf and boot.conf once (edit them freely; setup leaves them alone)
    local base
    base='[sdl]
autolock=true
output=opengl
[dosbox]
machine=svga_s3trio64
memsize=64
[video]
vmemsize=8
vesa modelist width limit=0
vesa modelist height limit=0
[render]
scaler=none
[dos]
# 7.1: what DOSBox-X needs to create and mount a FAT32 disk (OSR2 reads FAT32)
ver=7.1
hard drive data rate limit=0
floppy drive data rate limit=0
[cpu]
cputype=pentium_mmx
cycles=max
[sblaster]
sbtype=sb16vibra
[fdc, primary]
int13fakev86io=true
[ide, primary]
int13fakeio=true
int13fakev86io=true
[ide, secondary]
int13fakeio=true
int13fakev86io=true
cd-rom insertion delay=4000'
    [ -f "$WS/setup.conf" ] || printf '%s\n' "# ~/win95/setup.conf - written by dev-setup (install-retro) once; edit freely." \
        "# Installing: the normal core, as DOSBox-X's Windows 95 guide requires." "$base" | sed 's/^cputype=pentium_mmx$/cputype=pentium_mmx\ncore=normal/; s/^\[dosbox\]$/[dosbox]\ntitle=Windows 95 setup (dev-retro)/' > "$WS/setup.conf"
    [ -f "$WS/boot.conf" ] || printf '%s\n' "# ~/win95/boot.conf - written by dev-setup (install-retro) once; edit freely." \
        "# Running: the faster dynamic core ('win95 --core normal' for a DOS prompt window inside Windows 95)." \
        "# Networking (NE2000 through slirp) is off; to turn it on, add:  [ne2000] ne2000=true backend=slirp" "$base" \
        | sed 's/^cputype=pentium_mmx$/cputype=pentium_mmx\ncore=dynamic_x86/; s/^\[dosbox\]$/[dosbox]\ntitle=Windows 95 (dev-retro)/' > "$WS/boot.conf"
}
win95_cmd() {
    local mode=boot core="" iso args conf f app dmb
    while [ $# -gt 0 ]; do
        case "$1" in
            --core) core=${2:?--core normal|dynamic_x86}; shift 2 ;;
            --core=*) core=${1#--core=}; shift ;;
            *) break ;;
        esac
    done
    mode=${1:-boot}
    need_stopped win95
    win95_confs
    iso=$(install_iso)
    case "$mode" in
        boot|run)
            installed win95 || { tell "Windows 95 is not installed yet: put your CD's .iso in $WS/install, then 'win95 setup'."; exit 1; }
            if [ "$mode" = run ]; then
                f=${2:?usage: win95 run FILE}
                exch_put win95 "$f" > /dev/null || exit 1
                echo "$(basename "$f") is on the exchange disk: D:\\$(basename "$f") inside Windows 95."
            fi
            conf="$WS/boot.conf" ;;
        setup)
            if ! installed win95 && [ -z "$iso" ]; then
                tell "No Windows 95 CD image in $WS/install: put the .iso of your CD there (OSR2 for FAT32), then 'win95 setup'."
                exit 1
            fi
            conf="$WS/setup.conf" ;;
        *) die "usage: win95 [--core normal] [boot|setup|run FILE|put FILE|get [NAME]|cd FILE.iso|eject|list|exchange info|recreate|snapshot save|restore|list|delete NAME|fonts|where|status|launcher|help]" ;;
    esac
    exch_create "$WS" > /dev/null
    args=(-conf "$conf" -c "mount x \"$WS\"")
    if [ "$mode" = setup ] && [ ! -f "$WS/hdd.img" ]; then
        win95_setting; dmb=$SET_VAL
        disk_guard win95 $(( (dmb + 1023) / 1024 ))
        echo "Creating hdd.img: $dmb MB (RETRO_WIN95_DISK_MB, $SET_SRC), FAT32, partitioned and formatted by DOSBox-X's IMGMAKE..."
        # v93: in a short DOSBox-X run of its own, with no window: in the same session as the mounts, a second
        # CD drive on the secondary channel (the app CD) left DOSBox-X 2024.03 stuck after IMGMAKE.
        SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 300 dosbox-x -conf "$WS/setup.conf" -c "mount x \"$WS\"" -c "x:" \
            -c "imgmake hdd.img -t hd -size $dmb -fat 32" -c "exit" > "$STATE/imgmake.log" 2>&1
        [ -f "$WS/hdd.img" ] || die "DOSBox-X's IMGMAKE did not create $WS/hdd.img ($STATE/imgmake.log says why)."
    elif [ "$mode" = setup ]; then
        ( win95_setting ) > /dev/null 2>&1 && win95_setting && size_differs "$(( $(stat -c %s "$WS/hdd.img") / 1048576 ))" "$SET_VAL" \
            && echo "Note: hdd.img is $(( $(stat -c %s "$WS/hdd.img") / 1048576 )) MB and keeps that size (RETRO_WIN95_DISK_MB=$SET_VAL applies to a new disk: move hdd.img away, then 'win95 setup')."
    fi
    args+=(-c "imgmount c \"$WS/hdd.img\" -ide 1m"
           -c "imgmount d \"$WS/exchange.img\" -size $(exch_mount_size "$WS") -ide 1s")
    [ -n "$iso" ] && args+=(-c "imgmount e \"$iso\" -t iso -ide 2m")
    # v93: the app CD as the second CD drive (secondary slave), F: beside the Windows CD's E:.
    app=$(app_cd)
    [ -n "$app" ] && { args+=(-c "imgmount f \"$app\" -t iso -ide 2s"); echo "App CD: $(basename "$app") as F: ('win95 cd' picks another for the next start)."; }
    [ -n "$core" ] && args+=(-set "cpu core=$core")
    if [ "$mode" = setup ] && ! installed win95; then
        [ -n "$iso" ] || die "no CD image in $WS/install"
        # Setup runs from C:\WIN95, so Windows never asks for the CD again later.
        # DOSBox-X's shell has COPY but (in some builds) no XCOPY; the CD's WIN95 folder holds no subfolders.
        args+=(-c "c:" -c "if not exist c:\\win95\\nul md c:\\win95"
               -c "if not exist c:\\win95\\setup.exe copy e:\\win95\\*.* c:\\win95"
               -c "cd \\win95" -c "if not exist c:\\windows\\win.com setup"
               -c "if exist c:\\windows\\win.com echo Windows 95's files are on C:. Type EXIT, then run 'win95 setup' again.")
        echo "Windows 95 setup: when it reboots and you are back at the Z:\\ prompt, type EXIT."
        echo "Then 'win95 setup' again finishes setup's second part on the safe core; after the desktop appears, use 'win95'."
        echo "OSR2 wants the OEM product key (xxxxx-OEM-xxxxxxx-xxxxx) from your certificate or disc sleeve."
    else
        args+=(-c "boot c:")
        [ "$mode" = setup ] && echo "Windows is on the disk: booting it on the safe core with the CD in E:, so setup can finish (or repair)."
    fi
    mark_running $$
    dosbox-x "${args[@]}"; local rc=$?
    rm -f "$WS/.pid"; return $rc
}

# v93: undo points for win95. hdd.img is a raw image, so a snapshot is a sparse copy of it (only the space
# Windows has used), taken and put back only while Windows 95 is shut down. The exchange disk is not part of it.
win95_snapshot() {   # win95_snapshot save|restore|list|delete [NAME] [--yes]
    local op=${1:-list} name="" yes=0 a dir="$WS/snapshots" f used free margin
    shift || true
    for a in "$@"; do case "$a" in --yes) yes=1 ;; *) [ -n "$name" ] || name=$a ;; esac; done
    case "$op" in
        list)
            if [ -z "$(find "$dir" -maxdepth 1 -name '*.img' 2> /dev/null)" ]; then
                echo "No win95 snapshots yet ('win95 snapshot save NAME' with Windows 95 shut down)."; return 0
            fi
            printf '%-24s %-17s %s\n' NAME SAVED "ON DISK"
            for f in "$dir"/*.img; do printf '%-24s %-17s %s\n' "$(basename "$f" .img)" "$(date -r "$f" '+%F %R')" "$(du -h "$f" | cut -f1)"; done
            return 0 ;;
        save|restore|delete)
            [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "usage: win95 snapshot $op NAME (letters, digits, '.', '_', '-')"
            need_stopped win95 ;;
        *) die "usage: win95 snapshot save NAME | restore NAME [--yes] | list | delete NAME" ;;
    esac
    f="$dir/$name.img"
    case "$op" in
        save)
            [ -f "$WS/hdd.img" ] || die "no $WS/hdd.img yet ('win95 setup' creates it)."
            [ -e "$f" ] && die "a snapshot named '$name' exists: 'win95 snapshot delete $name' first, or pick another name."
            used=$(( ($(du -B1 "$WS/hdd.img" | cut -f1) + 1073741823) / 1073741824 ))
            free=$(free_gb "$WS"); margin=${RETRO_MIN_FREE_GB:-$(margin_gb 10)}
            if [ "${RETRO_FORCE:-0}" != 1 ] && [ "$free" -lt $(( used + margin )) ]; then
                die "not enough disk for the snapshot: $free GB free, $(( used + margin )) GB needed (the copy's $used GB + RETRO_MIN_FREE_GB=$margin; RETRO_FORCE=1 skips the check)."
            fi
            mkdir -p "$dir"
            cp --sparse=always "$WS/hdd.img" "$f.part" && mv -f "$f.part" "$f" || { rm -f "$f.part"; die "could not copy hdd.img to $f"; }
            echo "saved '$name' ($(du -h "$f" | cut -f1) on disk). 'win95 snapshot restore $name' goes back to it." ;;
        restore)
            [ -f "$f" ] || die "no snapshot '$name' ('win95 snapshot list')."
            if [ "$yes" != 1 ] && ! yes_no "Put hdd.img back to '$name' (saved $(date -r "$f" '+%F %R'))? Changes since then are lost."; then
                echo "Not restored ('win95 snapshot restore $name --yes' skips the question)."; return 1
            fi
            used=$(( ($(du -B1 "$f" | cut -f1) + 1073741823) / 1073741824 ))
            [ "${RETRO_FORCE:-0}" = 1 ] || [ "$(free_gb "$WS")" -gt "$used" ] || die "not enough disk to copy the snapshot back ($used GB; RETRO_FORCE=1 tries anyway)."
            cp --sparse=always "$f" "$WS/hdd.img.part" && mv -f "$WS/hdd.img.part" "$WS/hdd.img" || { rm -f "$WS/hdd.img.part"; die "could not restore $f"; }
            echo "restored '$name'." ;;
        delete)
            [ -f "$f" ] || die "no snapshot '$name' ('win95 snapshot list')."
            rm -f "$f" && echo "deleted '$name'." ;;
    esac
}

# =================================================================================================
# winnt40, win2000 (QEMU)
# =================================================================================================
qemu_config() {   # qemu_config [GUEST]: defaults, then the guest's config file (written once by dev-setup; edit freely)
    case "${1:-$GUEST}" in
        winnt40) MEM=128; HPET=off; DISK_GB=4; SOUND=sb16; MOUSE=ps2 ;;
        win2000) MEM=256; HPET=on;  DISK_GB=8; SOUND=AC97; MOUSE=tablet ;;
    esac
    CPU=pentium3; MACHINE=pc; DISK_FORMAT=qcow2; VIDEO=cirrus; NIC=pcnet; ACCEL=auto; DISPLAY_OPTS="gtk,zoom-to-fit=on"; EXTRA_ARGS=""
    # shellcheck disable=SC1091
    [ -f "$WS/config" ] && . "$WS/config"
    DISK="$WS/disk.qcow2"; [ "$DISK_FORMAT" = raw ] && DISK="$WS/disk.img"
    # A raw disk made by 'setup --raw' wins over the config's default.
    [ -f "$WS/disk.img" ] && [ ! -f "$WS/disk.qcow2" ] && { DISK="$WS/disk.img"; DISK_FORMAT=raw; }
    return 0
}
pick_accel() {   # sets ACCEL_ARGS and ACCEL_NOTE
    local want=${ACCEL:-auto}
    if [ "$want" != tcg ] && [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        ACCEL_ARGS=(-accel kvm); ACCEL_NOTE="KVM (close to native speed)"
    else
        if [ "$want" = kvm ]; then echo "NOTE: ACCEL=kvm, but /dev/kvm is missing or not usable (the kvm group needs a new login): using software emulation." >&2; fi
        if [ -c /dev/kvm ] && [ "$want" != tcg ]; then
            ACCEL_NOTE="software emulation (TCG): /dev/kvm is here but not usable by you yet (group $(stat -c %G /dev/kvm 2> /dev/null): shut Linux down and reopen it, or rerun dev-setup with install-retro)"
        else
            ACCEL_NOTE="software emulation (TCG; no /dev/kvm on this Chromebook: slower)"
        fi
        # shellcheck disable=SC2054   # one -accel value, commas included
        ACCEL_ARGS=(-accel tcg,thread=multi)
    fi
}
audio_args() {   # the sound card on PulseAudio (PipeWire's pulse server too), found by its socket; else silent
    case "$SOUND" in none|"") return 0 ;; esac
    if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pulse/native" ] || { command -v pactl > /dev/null 2>&1 && pactl info > /dev/null 2>&1; }; then
        echo "-audiodev pa,id=snd0 -device $SOUND,audiodev=snd0"
    else
        echo "No PulseAudio socket here: the guest's $SOUND card is silent." >&2
        echo "-audiodev none,id=snd0 -device $SOUND,audiodev=snd0"
    fi
}
qmp() {   # qmp JSON: one command on the guest's QMP socket; prints the result, exit 1 on an error
    local sock="$WS/.qmp.sock"
    [ -S "$sock" ] || die "$TITLE is not running (no monitor socket)."
    python3 - "$sock" "$1" << 'PY'
import json, socket, sys
s = socket.socket(socket.AF_UNIX)
s.settimeout(30)
s.connect(sys.argv[1])
f = s.makefile('rw')
json.loads(f.readline())
def ask(cmd):
    f.write(json.dumps(cmd) + '\n'); f.flush()
    while True:
        r = json.loads(f.readline())
        if 'event' in r:
            continue
        return r
ask({"execute": "qmp_capabilities"})
r = ask(json.loads(sys.argv[2]))
if 'error' in r:
    print(r['error'].get('desc', r['error']), file=sys.stderr); sys.exit(1)
ret = r.get('return')
if isinstance(ret, str):
    print(ret, end='')
    sys.exit(1 if ret.strip().lower().startswith(('error', 'could not', 'device', 'unknown')) else 0)
PY
}
hmp() { qmp "$(python3 -c 'import json,sys; print(json.dumps({"execute": "human-monitor-command", "arguments": {"command-line": sys.argv[1]}}))' "$1")"; }

qq() { printf '%s' "${1//,/,,}"; }   # a path inside a QEMU option value: commas doubled ("NT 4.0, SP6.iso")
qemu_launch() {   # qemu_launch BOOT(c|d|a) [CD] [FLOPPY]
    local boot=$1 cd=${2:-} fd=${3:-} sp args app
    args=(-name "$TITLE (dev-retro)" -machine "$MACHINE,hpet=$HPET" -cpu "$CPU" -m "$MEM" -smp 1
          -rtc base=localtime -vga "$VIDEO" -display "$DISPLAY_OPTS"
          -qmp "unix:$(qq "$WS/.qmp.sock"),server=on,wait=off" -pidfile "$WS/.pid"
          -drive "file=$(qq "$DISK"),format=$DISK_FORMAT,if=ide,index=0,media=disk"
          -drive "file=$(qq "$WS/exchange.img"),format=raw,if=ide,index=1,media=disk")
    if [ -n "$cd" ]; then args+=(-drive "file=$(qq "$cd"),if=ide,index=2,media=cdrom,readonly=on"); else args+=(-drive "if=ide,index=2,media=cdrom"); fi
    # v93: the second CD drive (ide1-cd1, F:) holds the app CD from install/apps ('<cmd> cd' picks it, and
    # swaps it while running). With no app CD, another ISO in install/ (a service pack) rides there as in v92;
    # with neither, the drive is there empty, so '<cmd> cd FILE' can fill it later.
    app=$(app_cd)
    if [ -z "$app" ]; then
        while IFS= read -r sp; do [ "$sp" = "$cd" ] && continue; app=$sp; break; done < <(find_isos)
    fi
    if [ -n "$app" ]; then
        args+=(-drive "file=$(qq "$app"),if=ide,index=3,media=cdrom,readonly=on")
        echo "F: $(basename "$app")"
    else
        args+=(-drive "if=ide,index=3,media=cdrom")
    fi
    [ -n "$fd" ] && args+=(-drive "file=$(qq "$fd"),if=floppy,index=0,format=raw")
    case "$NIC" in none|"") args+=(-nic none) ;; *) args+=(-nic "user,model=$NIC") ;; esac
    [ "$MOUSE" = tablet ] && args+=(-usb -device usb-tablet)
    case "$boot" in d|a) args+=(-boot "once=$boot") ;; *) args+=(-boot c) ;; esac
    pick_accel
    args+=("${ACCEL_ARGS[@]}")
    # shellcheck disable=SC2207
    args+=($(audio_args))
    # shellcheck disable=SC2206
    [ -n "$EXTRA_ARGS" ] && args+=($EXTRA_ARGS)
    echo "$TITLE on QEMU: $ACCEL_NOTE; $MEM MB, CPU $CPU, ${DISK##*/}."
    [ "$MOUSE" = ps2 ] && echo "The mouse is captured on click: Ctrl+Alt+G releases it."
    echo "Ctrl+Alt+Del for the login: '$GUEST keys ctrl-alt-del' (ChromeOS keeps the real one)."
    rm -f "$WS/.qmp.sock"
    qemu-system-i386 "${args[@]}"; local rc=$?
    rm -f "$WS/.pid" "$WS/.qmp.sock"; return $rc
}

nt_cmd() {
    local mode=${1:-boot} raw=0 fromcd=0 iso fd f a
    qemu_config
    case "$mode" in
        boot)
            installed "$GUEST" || { tell "$TITLE is not installed yet: put your CD's .iso in $WS/install, then '$GUEST setup'."; exit 1; }
            need_stopped "$GUEST"; exch_create "$WS" > /dev/null
            qemu_launch c "$(install_iso)" ;;
        run)
            f=${2:?usage: $GUEST run FILE}
            installed "$GUEST" || die "$TITLE is not installed yet ('$GUEST setup')."
            exch_put "$GUEST" "$f" > /dev/null || exit 1
            echo "$(basename "$f") is on the exchange disk: D:\\$(basename "$f") inside $TITLE."
            qemu_launch c "$(install_iso)" ;;
        setup)
            shift
            for a in "$@"; do case "$a" in --raw) raw=1 ;; --from-cd) fromcd=1 ;; *) die "usage: $GUEST setup [--raw] [--from-cd]" ;; esac; done
            need_stopped "$GUEST"
            iso=$(install_iso); fd=$(floppies | head -n 1)
            [ -n "$iso$fd" ] || { tell "No $TITLE media in $WS/install: put the CD's .iso there (and the boot floppies' .img files for NT 4.0, if your CD does not boot)."; exit 1; }
            exch_create "$WS" > /dev/null
            if [ "$raw" = 1 ] && [ -f "$WS/disk.qcow2" ]; then
                die "$WS/disk.qcow2 exists. For a raw disk instead (NT 4.0's qcow2 boot bug), remove it first: rm $WS/disk.qcow2"
            fi
            [ "$raw" = 1 ] && { DISK="$WS/disk.img"; DISK_FORMAT=raw; }
            if [ ! -f "$DISK" ]; then
                disk_guard "$GUEST" "$DISK_GB"
                if [ "$DISK_FORMAT" = raw ]; then
                    truncate -s "${DISK_GB}G" "$DISK"
                else
                    qemu-img create -q -f qcow2 "$DISK" "${DISK_GB}G" || die "qemu-img could not create $DISK"
                fi
                echo "Created $DISK ($DISK_GB GB, $DISK_FORMAT; it grows only as used)."
                [ "$GUEST" = winnt40 ] && echo "NT 4.0 setup: keep the system partition at 4 GB or less (the disk is exactly that). Skip the display 'Test' button."
                fromcd=1
            fi
            if [ "$fromcd" = 1 ]; then
                if [ -n "$fd" ] && { [ -z "$iso" ] || ! bootable_iso "$iso"; }; then
                    echo "Booting the first floppy ($(basename "$fd")); '$GUEST floppy NEXT.img' swaps disks while it runs."
                    qemu_launch a "$iso" "$fd"
                else
                    echo "Booting the CD ($(basename "$iso")); setup's reboots continue from the disk."
                    qemu_launch d "$iso"
                fi
            else
                echo "$DISK exists: booting it with the CD in, so setup can finish ('$GUEST setup --from-cd' starts over from the CD)."
                qemu_launch c "$iso"
            fi ;;
        floppy)
            running "$GUEST" || die "$TITLE is not running."
            a=${2:?usage: $GUEST $mode IMAGE|eject}
            local dev=floppy0
            if [ "$a" = eject ]; then hmp "eject -f $dev" && echo "ejected"
            else f=$(readlink -f "$a"); [ -f "$f" ] || die "no such file: $a"; hmp "change $dev \"$f\"" && echo "$(basename "$f") is in."; fi ;;
        keys)
            running "$GUEST" || die "$TITLE is not running."
            a=$(lc "${2:-ctrl-alt-del}"); a=${a/%-del/-delete}
            hmp "sendkey $a" && echo "sent $a" ;;
        snapshot)
            snapshot_cmd "${2:-list}" "${3:-}" ;;
        *) die "usage: $GUEST [boot|setup [--raw] [--from-cd]|run FILE|put FILE|get [NAME]|cd [--windows] ISO|eject|list|floppy IMG|keys ctrl-alt-del|snapshot save|restore|list|delete NAME|exchange info|recreate|fonts|where|status|launcher|help]" ;;
    esac
}
snapshot_cmd() {   # disk snapshots: qemu-img while off; a live, crash-consistent one through QMP while running
    local op=$1 name=$2
    [ "$DISK_FORMAT" = qcow2 ] && [ -f "$DISK" ] || die "snapshots need the qcow2 disk ($DISK is ${DISK_FORMAT})."
    case "$op" in
        list) qemu-img snapshot -U -l "$DISK" ;;
        save)
            [ -n "$name" ] || die "usage: $GUEST snapshot save NAME"
            if running "$GUEST"; then
                qmp "$(python3 -c 'import json,sys; print(json.dumps({"execute": "blockdev-snapshot-internal-sync", "arguments": {"device": "ide0-hd0", "name": sys.argv[1]}}))' "$name")" \
                    && echo "saved '$name' while running (like pulling the plug: take undo points with the guest shut down when you can)."
            else
                qemu-img snapshot -c "$name" "$DISK" && echo "saved '$name'."
            fi ;;
        restore)
            [ -n "$name" ] || die "usage: $GUEST snapshot restore NAME"
            need_stopped "$GUEST"
            qemu-img snapshot -a "$name" "$DISK" && echo "restored '$name'."
            ;;
        delete)
            [ -n "$name" ] || die "usage: $GUEST snapshot delete NAME"
            need_stopped "$GUEST"
            qemu-img snapshot -d "$name" "$DISK" && echo "deleted '$name'." ;;
        *) die "usage: $GUEST snapshot save NAME | restore NAME | list | delete NAME" ;;
    esac
}

# =================================================================================================
# delphi1 (Wine, a dedicated 32-bit prefix: the recipe worked out by hand on Oct 2 2026)
# =================================================================================================
delphi_wine() {   # wine in the delphi1 prefix with the native 16-bit OLE2 and no menu writes
    WINEPREFIX="$DELPHI_PREFIX" WINEARCH=win32 WINEDLLOVERRIDES="$DELPHI_OLE;winemenubuilder.exe=d;mscoree,mshtml=" "$@"
}
delphi_bin() { find "$DELPHI_PREFIX/drive_c" -maxdepth 3 -ipath '*/delphi/bin' -type d 2> /dev/null | head -n 1; }
delphi_desktop() {   # delphi_desktop PROGRAM ARGS...: run in a virtual desktop sized to the X screen
    local bin
    bin=$(delphi_bin)
    [ -n "$bin" ] && cd "$bin" || cd "$DELPHI_PREFIX/drive_c" || exit 1
    [ "$INTERACTIVE" = 1 ] || export WINEDEBUG="${WINEDEBUG:-err+all}"
    mark_running $$
    delphi_wine wine explorer "/desktop=Delphi1,$(screen_size)" "$@"; local rc=$?
    WINEPREFIX="$DELPHI_PREFIX" timeout 30 wineserver -w 2> /dev/null
    rm -f "$WS/.pid"; return $rc
}
delphi_unescape() {   # the arguments ChromeOS hands a launcher entry, rejoined into one Windows path
    # ChromeOS undoes only the outer level of .desktop escaping: "...\\Start\ Menu\\..." arrives split at the
    # space in "Start Menu", with doubled backslashes. Rejoin, then '\ ' -> ' ' and '\\' -> '\'.
    local joined="$*"
    joined=${joined//\\ / }
    while [[ "$joined" == *'\\'* ]]; do joined=${joined//\\\\/\\}; done
    printf '%s' "$joined"
}
delphi_media() {   # the Delphi 1 SETUP.EXE in ~/win31/install/apps (a folder named for Delphi first)
    local apps="$HOME/win31/install/apps" s
    s=$(find "$apps" -maxdepth 4 -type f -iname setup.exe -ipath '*delphi*' 2> /dev/null | sort | head -n 1)
    [ -n "$s" ] || s=$(find "$apps" -maxdepth 4 -type f -iname setup.exe 2> /dev/null | sort | head -n 1)
    printf '%s' "$s"
}
delphi_reg() { delphi_wine wine reg add "$@" /f > /dev/null 2>&1; }
delphi_setup() {
    local setup_exe="${1:-$(delphi_media)}" sys ok=1
    [ -n "$setup_exe" ] && [ -f "$setup_exe" ] || { tell "No Delphi 1 setup in ~/win31/install/apps: copy the Delphi 1 disks or CD there (SETUP.EXE with its files), then 'delphi1 setup'."; exit 1; }
    command -v wine > /dev/null || die "Wine is missing: rerun dev-setup with install-retro (it pulls in install-com)."
    if [ ! -f "$DELPHI_PREFIX/system.reg" ]; then
        echo "Creating the 32-bit Wine prefix $DELPHI_PREFIX (no Wine menu entries from wineboot)..."
        mkdir -p "$(dirname "$DELPHI_PREFIX")"
        WINEPREFIX="$DELPHI_PREFIX" WINEARCH=win32 WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree,mshtml=" wineboot -i > /dev/null 2>&1
        WINEPREFIX="$DELPHI_PREFIX" timeout 120 wineserver -w 2> /dev/null
        [ -f "$DELPHI_PREFIX/system.reg" ] || die "wineboot did not create the prefix: 'WINEPREFIX=$DELPHI_PREFIX WINEARCH=win32 wineboot -i' shows why."
    fi
    if installed delphi1; then
        echo "Delphi 1 is already installed in the prefix ($(delphi_bin)); applying the settings again."
    else
        echo "Running Delphi's setup ($setup_exe) in a virtual desktop. Install into C:\\DELPHI (the default)."
        # Without winemenubuilder=d here: Delphi's setup makes its program group, and Wine turns it into
        # launcher entries with the right icons, which 'delphi1 launcher' then points at this command.
        (cd "$(dirname "$setup_exe")" && WINEPREFIX="$DELPHI_PREFIX" WINEARCH=win32 WINEDLLOVERRIDES="mscoree,mshtml=" \
            wine explorer "/desktop=Delphi1Setup,$(screen_size)" "$(basename "$setup_exe")")
        # Until every Wine process of the prefix has ended: the installer can still be open (no time limit).
        WINEPREFIX="$DELPHI_PREFIX" wineserver -w 2> /dev/null
        installed delphi1 || { tell "Delphi 1 did not end up in $DELPHI_PREFIX/drive_c/DELPHI: run 'delphi1 setup' again."; exit 1; }
    fi
    sys=$(find "$DELPHI_PREFIX/drive_c/windows" -maxdepth 1 -iname system -type d | head -n 1)
    [ -n "$(find "$sys" -maxdepth 1 -iname compobj.dll 2> /dev/null)" ] || { echo "NOTE: no COMPOBJ.DLL in C:\\WINDOWS\\SYSTEM: Delphi's setup normally copies its 16-bit OLE2 there; the IDE will crash without it."; ok=0; }
    echo "Applying the settings: black desktop, a short TEMP, MS Sans Serif -> Tahoma, ClearType-style fonts..."
    delphi_reg 'HKCU\Control Panel\Colors' /v Background /t REG_SZ /d '0 0 0'
    mkdir -p "$DELPHI_PREFIX/drive_c/TEMP"
    delphi_reg 'HKCU\Environment' /v TEMP /t REG_EXPAND_SZ /d 'C:\TEMP'
    delphi_reg 'HKCU\Environment' /v TMP /t REG_EXPAND_SZ /d 'C:\TEMP'
    delphi_reg 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' /v 'MS Sans Serif' /t REG_SZ /d 'Tahoma'
    if command -v winetricks > /dev/null 2>&1; then
        WINEPREFIX="$DELPHI_PREFIX" winetricks -q fontsmooth=rgb > /dev/null 2>&1 || echo "NOTE: winetricks fontsmooth=rgb failed."
        WINEPREFIX="$DELPHI_PREFIX" winetricks -q corefonts tahoma > /dev/null 2>&1 || echo "NOTE: 'winetricks corefonts tahoma' failed (it downloads the fonts; offline?). Rerun 'delphi1 setup' later."
    else
        echo "NOTE: winetricks is missing (install-com installs it): fonts left as Wine's."
    fi
    # The IDE options: a DELPHI.INI you saved ('delphi1 ini save') first, then the keys Wine needs.
    if [ -f "$HOME/.config/dev-retro/DELPHI.INI" ]; then
        cp "$HOME/.config/dev-retro/DELPHI.INI" "$(delphi_ini_path)" && echo "DELPHI.INI restored from ~/.config/dev-retro (your saved options)."
    fi
    delphi_ini_apply verbose
    WINEPREFIX="$DELPHI_PREFIX" timeout 120 wineserver -w 2> /dev/null
    delphi_launcher
    delphi_offer_com_cleanup
    [ "$ok" = 1 ] && echo "Done: 'delphi1' starts the IDE (or its launcher icon). Limits of this route: 'delphi1 help'."
}
# DELPHI.INI (C:\WINDOWS): IntegratedDebugging=0 always (Wine has no Win16 debug hooks: Run fails with
# "Internal Windows error (15)" otherwise); the editor font Courier New 10 only where the file sets none.
# Every other line, and the file's CRLF line ends, stay as they are; a missing file gets just these keys
# (Delphi writes the rest when the IDE closes).
delphi_ini_apply() {   # delphi_ini_apply [verbose]
    local out
    out=$(python3 - "$(delphi_ini_path)" << 'PY'
import os, sys
path = sys.argv[1]
want = [("Debugging", "IntegratedDebugging", "0", True),
        ("Editor", "FontName", "Courier New", False),
        ("Editor", "FontSize", "10", False)]
lines = open(path, 'rb').read().decode('latin-1').splitlines() if os.path.exists(path) else []
changed = []
def section(name):
    for i, line in enumerate(lines):
        if line.strip().lower() == '[%s]' % name.lower():
            return i
    return -1
for sec, key, val, force in want:
    s = section(sec)
    if s < 0:
        lines += ['[%s]' % sec, '%s=%s' % (key, val)]
        changed.append('%s=%s' % (key, val))
        continue
    e = s + 1
    while e < len(lines) and not lines[e].lstrip().startswith('['):
        e += 1
    for i in range(s + 1, e):
        k, sep, v = lines[i].partition('=')
        if sep and k.strip().lower() == key.lower():
            if force and v.strip() != val:
                lines[i] = '%s=%s' % (key, val)
                changed.append('%s=%s' % (key, val))
            break
    else:
        j = e
        while j > s + 1 and not lines[j - 1].strip():
            j -= 1
        lines.insert(j, '%s=%s' % (key, val))
        changed.append('%s=%s' % (key, val))
if changed:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(('\r\n'.join(lines) + '\r\n').encode('latin-1'))
print(', '.join(changed))
PY
    ) || { echo "NOTE: could not update $(delphi_ini_path)." >&2; return 0; }
    if [ -n "$out" ]; then
        echo "DELPHI.INI: set $out."
    elif [ "${1:-}" = verbose ]; then
        echo "DELPHI.INI: Integrated debugging is off, and the editor font is set."
    fi
    return 0
}
delphi_ini_path() {
    local p
    p=$(find "$DELPHI_PREFIX/drive_c/windows" -maxdepth 1 -iname delphi.ini 2> /dev/null | head -n 1)
    printf '%s' "${p:-$DELPHI_PREFIX/drive_c/windows/DELPHI.INI}"
}
delphi_offer_com_cleanup() {   # the crashed v85-v91 install in the COM prefix: offered, never automatic
    local d=() p
    for p in "$COM_PREFIX/drive_c/DELPHI" "$COM_PREFIX/drive_c/IDAPI"; do [ -d "$p" ] && d+=("$p"); done
    [ ${#d[@]} -gt 0 ] || return 0
    echo "An earlier Delphi 1 install sits in the COM prefix (it crashes there): ${d[*]}"
    if [ "$INTERACTIVE" = 1 ] && [ -t 0 ]; then
        read -rp "Remove it (the delphi1 prefix replaces it)? [y/N] " p
        if [ "$(lc "$p")" = y ]; then rm -rf "${d[@]}" && echo "Removed."; return 0; fi
    fi
    echo "Left in place. To remove it later: rm -rf ${d[*]}"
}
delphi_launcher() {   # point the Wine menu entries of Delphi's group at 'delphi1'; write an IDE entry if none
    local apps="$HOME/.local/share/applications" f list=() ide=0
    mkdir -p "$apps"
    while IFS= read -r -d '' f; do
        list+=("$f")
    done < <(find "$apps/wine" -type f -name '*.desktop' -print0 2> /dev/null \
        | xargs -0 -r grep -lZ -e "WINEPREFIX=\"$DELPHI_PREFIX\"" -e "WINEPREFIX=\"$COM_PREFIX\".*[Dd][Ee][Ll][Pp][Hh][Ii]" -e "/.local/bin/delphi1" 2> /dev/null)
    if [ ${#list[@]} -gt 0 ]; then
        echo "Launcher entries pointed at delphi1:"
        for f in "${list[@]}"; do
            echo "  ${f#"$apps"/}"
            case "$(lc "$(basename "$f")")" in
                database\ desktop*)
                    # Database Desktop crashes under Wine (its temp-file name): it is a DOSBox-X tool.
                    sed -i -E "s|^Exec=.*|Exec=env DEV_RETRO_LAUNCHER=1 $HOME/.local/bin/win31|; /^Name=.*\\(Windows 3\\.1\\)$/!s|^Name=(.*)|Name=\\1 (Windows 3.1)|; /^Path=/d" "$f" ;;
                *)
                    sed -i -E "s|^Exec=env WINEPREFIX=\"[^\"]*\" wine[^ ]* |Exec=env DEV_RETRO_LAUNCHER=1 $HOME/.local/bin/delphi1 |; s|^Exec=$HOME/.local/bin/delphi1( \|$)|Exec=env DEV_RETRO_LAUNCHER=1 $HOME/.local/bin/delphi1\\1|; /^Path=/d" "$f" ;;
            esac
            grep -qi '^Name=delphi$\|delphi\.lnk' "$f" && ide=1
        done
    fi
    # An IDE entry made by hand before v92 (~/.local/share/applications/delphi1.desktop) is kept and updated.
    if [ -f "$apps/delphi1.desktop" ] && grep -q '/.local/bin/delphi1' "$apps/delphi1.desktop"; then
        sed -i -E "s|^Exec=.*|Exec=env DEV_RETRO_LAUNCHER=1 $HOME/.local/bin/delphi1|" "$apps/delphi1.desktop"
        echo "  delphi1.desktop (yours, kept; it starts the IDE)"
        ide=1
    fi
    if [ "$ide" = 0 ]; then
        cat > "$apps/dev-retro-delphi1.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Delphi 1
Comment=Delphi 1 under Wine (dev-retro); its limits: delphi1 help
Exec=env DEV_RETRO_LAUNCHER=1 $HOME/.local/bin/delphi1
Icon=$(retro_icon wine)
Terminal=false
Categories=Development;IDE;
EOF
        echo "Wrote dev-retro-delphi1.desktop (no Wine entry for the IDE)."
    else
        rm -f "$apps/dev-retro-delphi1.desktop"
    fi
}
delphi_cmd() {
    local a
    case "${1:-}" in
        "") installed delphi1 || { tell "Delphi 1 is not installed yet: copy its setup into ~/win31/install/apps, then 'delphi1 setup'."; exit 1; }
            delphi_ini_apply
            delphi_desktop DELPHI.EXE ;;
        setup) shift; delphi_setup "${1:-}" ;;
        run) shift; [ -f "${1:-}" ] || die "usage: delphi1 run PROGRAM.EXE"; delphi_desktop "$(readlink -f "$1")" "${@:2}" ;;
        launcher) delphi_launcher ;;
        ini)
            case "${2:-}" in
                save) mkdir -p "$HOME/.config/dev-retro"; cp "$(delphi_ini_path)" "$HOME/.config/dev-retro/DELPHI.INI" && echo "Saved $(delphi_ini_path) to ~/.config/dev-retro/DELPHI.INI: 'delphi1 setup' restores it." ;;
                show) cat "$(delphi_ini_path)" ;;
                *) die "usage: delphi1 ini save|show" ;;
            esac ;;
        *)  # a launcher entry's own command (a .lnk path, split by ChromeOS), or a program path
            a=$(delphi_unescape "$@")
            installed delphi1 || { tell "Delphi 1 is not installed yet ('delphi1 setup')."; exit 1; }
            case "$(lc "$a")" in
                *.lnk) delphi_desktop start.exe /wait "$a" ;;
                *) if [ -f "$a" ]; then delphi_desktop "$(readlink -f "$a")"; else delphi_desktop "$a"; fi ;;
            esac ;;
    esac
}

# =================================================================================================
# delphi N (v93): Delphi 3, 4, 5, 6 and 7 under Wine, one 32-bit prefix each. The delphi1 recipe without its
# 16-bit pieces (these are 32-bit programs, so no native OLE2): a virtual desktop sized to the screen, the
# Windows version of the Delphi's own era, black desktop, TEMP=C:\TEMP, MS Sans Serif -> Tahoma, smoothed
# core fonts. The CD (an .iso unpacked once, or its files) is drive D: in the prefix, typed as a CD-ROM,
# so the installer and later add-ons find it. Each version's own fixes are worked out on the real discs, as
# Delphi 1's were; the integrated debugger is left on. Real Windows guests for each version: STEPS-delphi.md
# in dev-demo's retro/matrix (3 and 4 in win95 or winnt40; 5, 6 and 7 in win2000).
# =================================================================================================
dn_info() {   # dn_info N: sets DN DN_PREFIX DN_MEDIA DN_WINVER DN_TITLE
    case "$1" in
        3) DN_WINVER=win95 ;;
        4) DN_WINVER=win98 ;;
        5) DN_WINVER=win2k ;;   # Delphi 5 (1999): Windows 2000's era, as Delphi 6
        6) DN_WINVER=win2k ;;
        7) DN_WINVER=winxp ;;
        *) die "delphi: the versions are $DELPHI_VERSIONS ('delphi1' is Delphi 1's own command)." ;;
    esac
    DN=$1; DN_PREFIX="$HOME/.local/share/wine/delphi$1"; DN_MEDIA="$HOME/delphi/install/$1"; DN_TITLE="Delphi $1"
}
dn_wine() { WINEPREFIX="$DN_PREFIX" WINEARCH=win32 WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree,mshtml=" "$@"; }
dn_reg() { dn_wine wine reg add "$@" /f > /dev/null 2>&1; }
dn_ide() { find "$DN_PREFIX/drive_c" -maxdepth 6 -type f -iname delphi32.exe 2> /dev/null | sort | head -n 1; }
dn_installed() { [ -n "$(dn_ide)" ]; }
dn_cdroot() {   # the folder holding the CD's files: an .iso in the media folder is unpacked once into ~/delphi/.cd/N
    local iso out="$HOME/delphi/.cd/$DN" stamp auto
    iso=$(find "$DN_MEDIA" -maxdepth 1 -type f -iname '*.iso' 2> /dev/null | sort | head -n 1)
    if [ -n "$iso" ]; then
        stamp=$(stat -c '%n %s %Y' "$iso")
        if [ "$(cat "$out/.dev-retro-from" 2> /dev/null)" != "$stamp" ]; then
            echo "Unpacking $(basename "$iso") into $out (once; it is drive D: in the prefix)..." >&2
            rm -rf "$out.part"; mkdir -p "$out.part"
            if command -v bsdtar > /dev/null 2>&1; then bsdtar -xf "$iso" -C "$out.part"
            elif command -v 7z > /dev/null 2>&1; then 7z x -y -o"$out.part" "$iso" > /dev/null
            else die "nothing here unpacks an .iso: rerun dev-setup with install-retro (it installs libarchive-tools), or copy the CD's files into $DN_MEDIA"
            fi || { rm -rf "$out.part"; die "could not unpack $iso"; }
            chmod -R u+w "$out.part"
            rm -rf "$out"; mv "$out.part" "$out"
            echo "$stamp" > "$out/.dev-retro-from"
        fi
        echo "$out"; return 0
    fi
    # Loose files: the CD's root is where autorun.inf is (the shallowest), else the media folder itself.
    auto=$(find "$DN_MEDIA" -maxdepth 3 -type f -iname autorun.inf 2> /dev/null | awk -F/ '{print NF "\t" $0}' | sort -n | head -n 1 | cut -f2-)
    if [ -n "$auto" ]; then dirname "$auto"; return 0; fi
    [ -n "$(find "$DN_MEDIA" -mindepth 1 -maxdepth 1 ! -name '.*' 2> /dev/null | head -n 1)" ] && { echo "$DN_MEDIA"; return 0; }
    return 1
}
dn_installer() {   # dn_installer CDROOT: autorun.inf's open= program, else INSTALL.EXE / SETUP.EXE, else the shallowest setup.exe
    local root=$1 a f n
    a=$(find "$root" -maxdepth 1 -type f -iname autorun.inf 2> /dev/null | head -n 1)
    if [ -n "$a" ]; then
        f=$(tr -d '\r' < "$a" | sed -n 's/^[[:space:]]*[Oo][Pp][Ee][Nn][[:space:]]*=[[:space:]]*//p' | head -n 1 | awk '{print $1}')
        f=${f//\\//}
        if [ -n "$f" ]; then
            f=$(find "$root" -maxdepth 4 -type f -ipath "$root/$f" 2> /dev/null | head -n 1)
            [ -n "$f" ] && { echo "$f"; return 0; }
        fi
    fi
    for n in install.exe setup.exe; do
        f=$(find "$root" -maxdepth 1 -type f -iname "$n" 2> /dev/null | head -n 1)
        [ -n "$f" ] && { echo "$f"; return 0; }
    done
    find "$root" -maxdepth 3 -type f -iname setup.exe 2> /dev/null | awk -F/ '{print NF "\t" $0}' | sort -n | head -n 1 | cut -f2-
}
dn_desktop() {   # dn_desktop PROGRAM ARGS...: run in the version's virtual desktop
    local ide
    ide=$(dn_ide)
    [ -n "$ide" ] && cd "$(dirname "$ide")" || cd "$DN_PREFIX/drive_c" || exit 1
    [ "$INTERACTIVE" = 1 ] || export WINEDEBUG="${WINEDEBUG:-err+all}"
    mark_running $$
    dn_wine wine explorer "/desktop=Delphi$DN,$(screen_size)" "$@"; local rc=$?
    WINEPREFIX="$DN_PREFIX" timeout 30 wineserver -w 2> /dev/null
    rm -f "$WS/.pid"; return $rc
}
dn_prefix() {   # create the 32-bit prefix once, and report the Windows version of the Delphi's era
    if [ ! -f "$DN_PREFIX/system.reg" ]; then
        echo "Creating the 32-bit Wine prefix $DN_PREFIX (no Wine menu entries from wineboot)..."
        mkdir -p "$(dirname "$DN_PREFIX")"
        WINEPREFIX="$DN_PREFIX" WINEARCH=win32 WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree,mshtml=" wineboot -i > /dev/null 2>&1
        WINEPREFIX="$DN_PREFIX" timeout 120 wineserver -w 2> /dev/null
        [ -f "$DN_PREFIX/system.reg" ] || die "wineboot did not create the prefix: 'WINEPREFIX=$DN_PREFIX WINEARCH=win32 wineboot -i' shows why."
    fi
    WINEDEBUG=-all dn_wine wine winecfg -v "$DN_WINVER" > /dev/null 2>&1 || echo "NOTE: 'winecfg -v $DN_WINVER' failed; Wine reports its default Windows version."
}
dn_settings() {
    echo "Applying the settings: Windows version $DN_WINVER, black desktop, a short TEMP, MS Sans Serif -> Tahoma, smoothed fonts..."
    dn_reg 'HKCU\Control Panel\Colors' /v Background /t REG_SZ /d '0 0 0'
    mkdir -p "$DN_PREFIX/drive_c/TEMP"
    dn_reg 'HKCU\Environment' /v TEMP /t REG_EXPAND_SZ /d 'C:\TEMP'
    dn_reg 'HKCU\Environment' /v TMP /t REG_EXPAND_SZ /d 'C:\TEMP'
    dn_reg 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' /v 'MS Sans Serif' /t REG_SZ /d 'Tahoma'
    if command -v winetricks > /dev/null 2>&1; then
        WINEPREFIX="$DN_PREFIX" winetricks -q fontsmooth=rgb > /dev/null 2>&1 || echo "NOTE: winetricks fontsmooth=rgb failed."
        WINEPREFIX="$DN_PREFIX" winetricks -q corefonts tahoma > /dev/null 2>&1 || echo "NOTE: 'winetricks corefonts tahoma' failed (it downloads the fonts; offline?). Rerun 'delphi $DN setup' later."
    else
        echo "NOTE: winetricks is missing (install-com installs it): fonts left as Wine's."
    fi
    # reg.exe, not regedit: regedit answers a problem with a dialog box, which would wait for a click.
    if [ -f "$HOME/.config/dev-retro/delphi$DN.reg" ]; then
        dn_wine wine reg import "$(dn_wine winepath -w "$HOME/.config/dev-retro/delphi$DN.reg" 2> /dev/null)" > /dev/null 2>&1 \
            && echo "IDE options restored from ~/.config/dev-retro/delphi$DN.reg ('delphi $DN ini save')."
    fi
    WINEPREFIX="$DN_PREFIX" timeout 120 wineserver -w 2> /dev/null
}
dn_setup() {   # dn_setup [INSTALLER]
    local inst=${1:-} root rel
    command -v wine > /dev/null || die "Wine is missing: rerun dev-setup with install-retro (it pulls in install-com)."
    if [ -n "$inst" ]; then
        [ -f "$inst" ] || die "no such file: $inst"
        inst=$(readlink -f "$inst"); root=$(dirname "$inst")
    elif ! dn_installed; then
        root=$(dn_cdroot) || { tell "No $DN_TITLE media in $DN_MEDIA: put the CD's .iso there (or copy the CD's files), then 'delphi $DN setup'."; exit 1; }
        inst=$(dn_installer "$root")
        [ -n "$inst" ] || die "no installer in $root (autorun.inf, INSTALL.EXE or SETUP.EXE): 'delphi $DN setup PATH/TO/SETUP.EXE' names it."
    fi
    dn_prefix
    if [ -z "$inst" ]; then
        echo "$DN_TITLE is already installed ($(dn_ide)); applying the settings again."
    else
        # The CD as D:, a CD-ROM drive to Windows (installers and Delphi's later add-ons look for it).
        ln -sfn "$root" "$DN_PREFIX/dosdevices/d:"
        dn_reg 'HKLM\Software\Wine\Drives' /v 'd:' /t REG_SZ /d cdrom
        # Wine's mount manager reads the drive types when the prefix starts: let it stop, so the installer's
        # start sees D: as a CD-ROM.
        WINEPREFIX="$DN_PREFIX" timeout 60 wineserver -w 2> /dev/null
        rel=${inst#"$root"/}; rel=${rel//\//\\}; rel="D:\\$rel"
        echo "Running $DN_TITLE's installer ($rel, from $root) in a virtual desktop. Keep the default folders."
        # Without winemenubuilder=d here: the installer's Start menu group becomes launcher entries, which
        # 'delphi $DN launcher' then points at this command.
        (cd "$root" && WINEPREFIX="$DN_PREFIX" WINEARCH=win32 WINEDLLOVERRIDES="mscoree,mshtml=" \
            wine explorer "/desktop=Delphi${DN}Setup,$(screen_size)" "$rel")
        WINEPREFIX="$DN_PREFIX" wineserver -w 2> /dev/null
        dn_installed || { tell "$DN_TITLE did not end up in $DN_PREFIX (no delphi32.exe under C:\Program Files): run 'delphi $DN setup' again, or name the installer: 'delphi $DN setup FILE'."; exit 1; }
    fi
    dn_settings
    dn_launcher
    echo "Done: 'delphi $DN' starts the IDE (or its launcher icon). If Run stops with a debugger error, turn off"
    echo "Tools > Debugger Options > Integrated debugging and debug in a real Windows guest (STEPS-delphi.md)."
}
dn_launcher() {   # point the version's Wine menu entries at 'delphi N'; write an IDE entry when none is there
    local apps="$HOME/.local/share/applications" f list=() ide=0
    mkdir -p "$apps"
    while IFS= read -r -d '' f; do
        list+=("$f")
    done < <(find "$apps/wine" -type f -name '*.desktop' -print0 2> /dev/null \
        | xargs -0 -r grep -lZ -e "WINEPREFIX=\"$DN_PREFIX\"" -e "/.local/bin/delphi $DN\( \|$\)" 2> /dev/null)
    if [ ${#list[@]} -gt 0 ]; then
        echo "Launcher entries pointed at 'delphi $DN':"
        for f in "${list[@]}"; do
            echo "  ${f#"$apps"/}"
            sed -i -E "s|^Exec=env WINEPREFIX=\"[^\"]*\" wine[^ ]* |Exec=env DEV_RETRO_LAUNCHER=1 $HOME/.local/bin/delphi $DN |; /^Path=/d" "$f"
            grep -qiE "^Name=Delphi ?$DN(\.0)?$" "$f" && ide=1
        done
    fi
    if [ "$ide" = 0 ] && dn_installed; then
        cat > "$apps/dev-retro-delphi$DN.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$DN_TITLE
Comment=$DN_TITLE under Wine (dev-retro): delphi help
Exec=env DEV_RETRO_LAUNCHER=1 $HOME/.local/bin/delphi $DN
Icon=$(retro_icon wine)
Terminal=false
Categories=Development;IDE;
EOF
        echo "Wrote dev-retro-delphi$DN.desktop (no Wine entry for the IDE)."
    elif [ "$ide" = 1 ]; then
        rm -f "$apps/dev-retro-delphi$DN.desktop"
    fi
}
dn_list() {   # 'delphi' alone: every version's state
    local n media
    printf '%-9s %-15s %-14s %s\n' VERSION WINDOWS STATE "MEDIA (~/delphi/install/N)"
    for n in $DELPHI_VERSIONS; do
        dn_info "$n"
        if dn_installed; then media=installed
        elif [ -d "$DN_PREFIX" ]; then media="prefix only"
        else media="not set up"; fi
        printf '%-9s %-15s %-14s %s\n' "delphi $n" "$DN_WINVER" "$media" \
            "$(f=$(find "$DN_MEDIA" -mindepth 1 -maxdepth 1 ! -name '.*' 2> /dev/null | head -n 1); [ -n "$f" ] && basename "$f" || echo "empty: the CD's .iso or files go there")"
    done
    echo "'delphi N setup' installs one, 'delphi N' starts it; Delphi 1: 'delphi1'. Real Windows guests: STEPS-delphi.md (dev-demo retro/matrix)."
}
delphi_n_cmd() {   # delphi [N [setup|run|launcher|ini|where|status|help] ...]
    local a
    case "${1:-}" in
        ""|list) dn_list; return ;;
        help|-h|--help) help_cmd; return ;;
        1) die "Delphi 1 has its own command: delphi1" ;;
    esac
    guest_info "delphi$1" || dn_info "$1"
    shift
    case "${1:-}" in
        "") dn_installed || { tell "$DN_TITLE is not installed yet: its CD (.iso or files) in $DN_MEDIA, then 'delphi $DN setup'."; exit 1; }
            dn_desktop "$(basename "$(dn_ide)")" ;;
        setup) shift; dn_setup "${1:-}" ;;
        run) shift; [ -f "${1:-}" ] || die "usage: delphi $DN run PROGRAM.EXE"; dn_desktop "$(readlink -f "$1")" "${@:2}" ;;
        launcher) dn_launcher ;;
        where) where_cmd "delphi$DN" ;;
        status) status_cmd "delphi$DN" ;;
        help|-h|--help) help_cmd ;;
        ini|settings)
            case "${2:-}" in
                save) [ -f "$DN_PREFIX/user.reg" ] || die "no prefix yet ('delphi $DN setup')."
                      dn_wine wine reg query 'HKCU\Software\Borland' > /dev/null 2>&1 \
                          || die "nothing to save: no HKEY_CURRENT_USER\Software\Borland in the prefix yet (start the IDE once, set your options, close it)."
                      mkdir -p "$HOME/.config/dev-retro"
                      dn_wine wine reg export 'HKCU\Software\Borland' "$(dn_wine winepath -w "$HOME/.config/dev-retro/delphi$DN.reg" 2> /dev/null)" /y > /dev/null 2>&1
                      [ -s "$HOME/.config/dev-retro/delphi$DN.reg" ] || die "reg export wrote nothing to ~/.config/dev-retro/delphi$DN.reg."
                      echo "Saved the IDE's options (HKCU\Software\Borland) to ~/.config/dev-retro/delphi$DN.reg: 'delphi $DN setup' restores them." ;;
                show) cat "$HOME/.config/dev-retro/delphi$DN.reg" 2> /dev/null || echo "nothing saved yet ('delphi $DN ini save')." ;;
                *) die "usage: delphi $DN ini save|show" ;;
            esac ;;
        *)  # a launcher entry's own command (a .lnk path, split by ChromeOS), or a program path
            a=$(delphi_unescape "$@")
            dn_installed || { tell "$DN_TITLE is not installed yet ('delphi $DN setup')."; exit 1; }
            case "$(lc "$a")" in
                *.lnk) dn_desktop start.exe /wait "$a" ;;
                *) if [ -f "$a" ]; then dn_desktop "$(readlink -f "$a")"; else dn_desktop "$a"; fi ;;
            esac ;;
    esac
}

# =================================================================================================
# fonts (win31, win95, winnt40, win2000)
# =================================================================================================
# The TrueType core fonts and Tahoma, under their 8.3 names: what 'winetricks corefonts tahoma' puts in a
# Wine prefix ('delphi1 setup' runs it), else unpacked from winetricks' download cache with cabextract.
FONT_FILES="andalemo arial arialbd arialbi ariali ariblk comic comicbd cour courbd courbi couri georgia georgiab
georgiai georgiaz impact times timesbd timesbi timesi trebuc trebucbd trebucbi trebucit verdana verdanab
verdanai verdanaz webdings tahoma tahomabd"
fonts_take() {   # fonts_take SRCDIR OUTDIR: the fonts of FONT_FILES found in SRCDIR and not yet in OUTDIR
    local n f
    for n in $FONT_FILES; do
        [ -f "$2/${n^^}.TTF" ] && continue
        f=$(find "$1" -maxdepth 1 -type f -iname "$n.ttf" 2> /dev/null | head -n 1)
        [ -n "$f" ] && cp "$f" "$2/${n^^}.TTF"
    done
    return 0
}
fonts_collect() {   # fonts_collect DIR: every font found, into DIR as NAME.TTF
    local out=$1 d f cache="${XDG_CACHE_HOME:-$HOME/.cache}/winetricks" tmp
    mkdir -p "$out"
    for d in "$DELPHI_PREFIX/drive_c/windows/Fonts" "$COM_PREFIX/drive_c/windows/Fonts"; do
        [ -d "$d" ] && fonts_take "$d" "$out"
    done
    if command -v cabextract > /dev/null 2>&1 && [ -d "$cache" ]; then
        tmp=$(mktemp -d)
        for f in "$cache"/corefonts/*.[Ee][Xx][Ee] "$cache"/tahoma/*.[Cc][Aa][Bb]; do
            [ -f "$f" ] && cabextract -q -L -F '*.ttf' -d "$tmp" "$f" > /dev/null 2>&1
        done
        fonts_take "$tmp" "$out"; rm -rf "$tmp"
    fi
    return 0
}
fonts_readme() {   # fonts_readme GUEST: README.TXT for the guest (LF here; CRLF when written)
    cat << EOF
Fonts from dev-retro ('$1 fonts' on Linux)

The TrueType core fonts (Andale Mono, Arial, Comic Sans MS, Courier New, Georgia, Impact,
Times New Roman, Trebuchet MS, Verdana, Webdings) and Tahoma, copied from the Wine prefixes
on Linux. Fonts Windows already has are skipped when you install.

INSTALL THE FONTS
EOF
    case "$1" in
        win31) cat << 'EOF'
  Main > Control Panel > Fonts > Add...
  Drives: c:   Directories: c:\fonts   then Select All, keep "Copy Fonts to Windows
  Directory" ticked, OK. Windows 3.1 lists only the files its TrueType engine reads;
  install the ones it lists.

FONT SMOOTHING
  Windows 3.1 has none. TrueType text is crisp at the screen's own size; for bigger
  text use a higher resolution with Large Fonts (Main > Windows Setup > Options >
  Change System Settings > Display).
EOF
            ;;
        *) cat << 'EOF'
  Start > Settings > Control Panel > Fonts, then File > Install New Font...
  Drives: d:   Folders: d:\fonts   then Select All, keep "Copy fonts to Fonts folder"
  ticked, OK.

FONT SMOOTHING
  ClearType began with Windows XP; this Windows has grayscale smoothing at most, and it
  needs 16-bit colour or more (Display Properties > Settings).
EOF
            ;;
    esac
    case "$1" in
        win95) cat << 'EOF'
  Windows 95 smooths fonts only with Microsoft Plus! for Windows 95 installed: then
  right-click the desktop > Properties > Plus! > "Smooth edges of screen fonts".
EOF
            ;;
        winnt40) cat << 'EOF'
  Pick 65536 colors on the Settings tab first (Test, then OK). Then right-click the
  desktop > Properties > Plus! > "Smooth edges of screen fonts", OK, log off and on.
EOF
            ;;
        win2000) cat << 'EOF'
  Colors: High Color (16 bit) or True Color on the Settings tab. Then right-click the
  desktop > Properties > Effects > "Smooth edges of screen fonts", OK.
EOF
            ;;
    esac
    case "$1" in
        winnt40|win2000) cat << EOF

SHARPER PICTURE ON LINUX
  QEMU scales the guest's screen to its window (zoom-to-fit). For one screen pixel per
  guest pixel, untick View > Zoom To Fit in QEMU's window, or set
  DISPLAY_OPTS="gtk,zoom-to-fit=off" in ~/$1/config.
EOF
            ;;
    esac
}
fonts_cmd() {   # fonts_cmd GUEST
    local tmp n where
    tmp=$(mktemp -d)
    # shellcheck disable=SC2064   # the path is fixed now
    trap "rm -rf '$tmp'" EXIT
    mkdir -p "$tmp/FONTS"
    fonts_collect "$tmp/FONTS"
    n=$(find "$tmp/FONTS" -maxdepth 1 -name '*.TTF' | wc -l)
    [ "$n" -gt 0 ] || die "No fonts found: 'delphi1 setup' installs them into the delphi1 prefix (winetricks corefonts tahoma), or run 'winetricks corefonts tahoma' once."
    fonts_readme "$1" | sed 's/$/\r/' > "$tmp/FONTS/README.TXT"
    case "$1" in
        win31)
            mkdir -p "$WS/drive_c/FONTS" && cp "$tmp"/FONTS/* "$WS/drive_c/FONTS/" || die "could not copy into $WS/drive_c/FONTS"
            where='C:\FONTS'
            running win31 && echo "Windows 3.1 is running: DOSBox-X shows the new folder after the guest is restarted." ;;
        *)
            exch_put "$1" "$tmp/FONTS" > /dev/null || exit 1
            where='D:\FONTS' ;;
    esac
    echo "$n fonts and README.TXT in $where for $TITLE. Inside the guest:"
    sed -n '/^INSTALL THE FONTS/,$p' "$tmp/FONTS/README.TXT" | tr -d '\r' | sed '1d'
}

# =================================================================================================
# common subcommands
# =================================================================================================
retro_icon() {   # an icon file for the engine, generic when none is found
    local f
    for f in $(case "$1" in
            dosbox-x) echo /usr/share/icons/hicolor/scalable/apps/dosbox-x.svg /usr/share/pixmaps/dosbox-x.png /usr/share/icons/hicolor/*/apps/dosbox-x.png ;;
            qemu) echo /usr/share/icons/hicolor/scalable/apps/qemu.svg /usr/share/icons/hicolor/*/apps/qemu.png ;;
            wine) echo /usr/share/icons/hicolor/scalable/apps/wine.svg /usr/share/pixmaps/wine.png /usr/share/icons/hicolor/*/apps/wine.png ;;
        esac); do
        [ -f "$f" ] && { echo "$f"; return 0; }
    done
    echo application-x-executable
}
write_launcher() {   # the ChromeOS app-drawer entry for GUEST (Exec is absolute: no ~/.bashrc PATH there)
    local apps="$HOME/.local/share/applications"
    guest_info "$1"; mkdir -p "$apps"
    [ "$1" = delphi1 ] && { delphi_launcher; return 0; }
    cat > "$apps/dev-retro-$1.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$TITLE
Comment=$TITLE in $ENGINE (dev-retro): '$1 setup' installs it from $WS/install
Exec=env DEV_RETRO_LAUNCHER=1 $HOME/.local/bin/$1
Icon=$(retro_icon "$ENGINE")
Terminal=false
Categories=System;Emulator;
EOF
    echo "Launcher entry: $apps/dev-retro-$1.desktop"
}
where_cmd() {
    guest_info "$1"
    echo "$TITLE ($ENGINE)"
    case "$1" in
        win31)  echo "  C: drive       $WS/drive_c"; echo "  Windows media  $WS/install/windows (loose files or .img/.ima)"
                echo "  installers     $WS/install/apps (D:); an .iso there is the app CD (F:)"; echo "  config         $WS/dosbox-x.conf" ;;
        win95)  echo "  media          $WS/install (the CD's .iso)"; echo "  disk           $WS/hdd.img (C:)"
                echo "  exchange disk  $WS/exchange.img (D:; '$1 put' / '$1 get')"; echo "  app CDs        $WS/install/apps (.iso; F:, '$1 cd')"
                echo "  snapshots      $WS/snapshots ('$1 snapshot')"; echo "  configs        $WS/setup.conf, $WS/boot.conf" ;;
        winnt40|win2000)
                qemu_config "$1"
                echo "  media          $WS/install (the CD's .iso; a service-pack .iso rides in the second CD drive when no app CD is there)"
                [ "$1" = winnt40 ] && echo "                 boot floppies (.img) there too when the CD does not boot"
                echo "  app CDs        $WS/install/apps (.iso; F:, '$1 cd')"
                echo "  disk           $DISK (C:)"; echo "  exchange disk  $WS/exchange.img (D:)"; echo "  config         $WS/config" ;;
        delphi3|delphi4|delphi5|delphi6|delphi7)
                echo "  prefix         $DN_PREFIX (32-bit; Windows version $DN_WINVER)"; echo "  media          $DN_MEDIA (the CD's .iso, or its files)"
                echo "  CD as D:       $HOME/delphi/.cd/$DN (an .iso unpacked once)"; echo "  IDE            $(dn_ide)"
                echo "  saved options  $HOME/.config/dev-retro/delphi$DN.reg ('delphi $DN ini save')" ;;
        delphi1) echo "  prefix         $DELPHI_PREFIX"; echo "  media          $HOME/win31/install/apps (Delphi's SETUP.EXE)"
                echo "  IDE            $(delphi_bin)"; echo "  log            $STATE/launcher.log (launcher starts)" ;;
    esac
}
status_cmd() {   # one line: installed? running? sizes
    local inst run size=""
    guest_info "$1"
    if installed "$1"; then inst=installed; else inst="not installed"; fi
    if running "$1"; then run=running; else run=stopped; fi
    case "$1" in
        win95) [ -f "$WS/hdd.img" ] && size=$(du -h "$WS/hdd.img" | cut -f1) ;;
        winnt40|win2000) qemu_config "$1"; [ -f "$DISK" ] && size=$(du -h "$DISK" | cut -f1); [ "$inst" = installed ] && inst="disk created" ;;
        win31) [ -d "$WS/drive_c" ] && size=$(du -sh "$WS/drive_c" 2> /dev/null | cut -f1) ;;
        delphi1) [ -d "$DELPHI_PREFIX" ] && size=$(du -sh "$DELPHI_PREFIX" 2> /dev/null | cut -f1) ;;
        delphi3|delphi4|delphi5|delphi6|delphi7) [ -d "$WS" ] && size=$(du -sh "$WS" 2> /dev/null | cut -f1) ;;
    esac
    printf '%-8s %-15s %-9s %-14s %-8s %s\n' "$1" "$TITLE" "$ENGINE" "$inst" "$run" "${size:+$size used}"
    [ -f "$WS/setup.skipped" ] && echo "         last setup refused: $(cat "$WS/setup.skipped")"
    return 0
}
help_cmd() { sed -n '2,/^set -o pipefail$/{/^set -o/d;s/^# \{0,1\}//;p}' "$SELF"; }
sizes_cmd() {   # v93: the disk sizes in effect, and what each existing disk has
    local g mb
    exch_setting
    echo "Exchange disk (D: in win95, winnt40, win2000): RETRO_EXCHANGE_MB=$SET_VAL ($SET_SRC), for a disk created from now on"
    for g in win95 winnt40 win2000; do
        if [ -f "$HOME/$g/exchange.img" ]; then
            read -r mb _ <<< "$(exch_geom "$HOME/$g/exchange.img")"
            echo "  $g: $mb MB$(size_differs "$mb" "$SET_VAL" && echo "  ('$g exchange recreate' rebuilds it at $SET_VAL MB)")"
        else
            echo "  $g: none yet"
        fi
    done
    win95_setting
    echo "Windows 95's hdd.img: RETRO_WIN95_DISK_MB=$SET_VAL ($SET_SRC), for a disk created from now on"
    if [ -f "$HOME/win95/hdd.img" ]; then echo "  win95: $(( $(stat -c %s "$HOME/win95/hdd.img") / 1048576 )) MB (kept)"; else echo "  win95: none yet"; fi
    echo "Set them in $SECRETS (or on the command line for one run: RETRO_EXCHANGE_MB=512 win2000 setup)."
}

# =================================================================================================
# retro: the umbrella command
# =================================================================================================
exe_kind() {   # dos | win16 | win32 | win64 | unknown, from the file's header
    python3 - "$1" << 'PY' 2> /dev/null || echo unknown
import struct, sys
p = sys.argv[1]
with open(p, 'rb') as f:
    h = f.read(4096)
low = p.lower()
if h[:2] not in (b'MZ', b'ZM'):
    print('dos' if low.endswith(('.com', '.bat')) else 'unknown'); sys.exit()
lfanew = struct.unpack('<I', h[0x3c:0x40])[0] if len(h) >= 0x40 else 0
sig = b''
if 0x40 <= lfanew < 1 << 20:
    with open(p, 'rb') as f:
        f.seek(lfanew); sig = f.read(26)
if sig[:2] == b'NE':
    print('win16')
elif sig[:4] == b'PE\0\0':
    machine = struct.unpack('<H', sig[4:6])[0]
    print('win64' if machine in (0x8664, 0xaa64) else 'win32')
else:
    print('dos')   # plain MZ, or LE/LX (DOS/4GW and other extenders)
PY
}
retro_pick() {   # retro_pick FILE: sets PICK (engine) and WHY
    local k; k=$(exe_kind "$1")
    case "$k" in
        dos)   PICK=dos;  WHY="a DOS program (MZ, or a DOS extender's LE/LX): DOSBox-X; Wine refuses DOS programs" ;;
        win16) if installed delphi1; then PICK=delphi1; WHY="a Windows 3.x program (NE): Wine's 32-bit delphi1 prefix runs it directly"
               else PICK=com; WHY="a Windows 3.x program (NE): Wine (the COM prefix; the delphi1 prefix is not set up)"; fi ;;
        win32) PICK=com;  WHY="a 32-bit Windows program (PE): Wine, in the COM prefix" ;;
        win64) PICK=com;  WHY="a 64-bit Windows program (PE32+): Wine, in the COM prefix" ;;
        *)     PICK="";   WHY="not a DOS or Windows executable (no MZ header, not .com or .bat)" ;;
    esac
    KIND=$k
}
dos_conf() {   # ~/.config/dev-retro/dos.conf for DOS programs, written once (edit freely); prints its path
    local c="$HOME/.config/dev-retro/dos.conf"
    if [ ! -f "$c" ]; then
        mkdir -p "${c%/*}"
        cat > "$c" << 'EOF'
# ~/.config/dev-retro/dos.conf - DOSBox-X settings for DOS programs ('retro run', dev-demo's matrix).
# Written once by dev-retro (install-retro, v92); edit freely.
# output=ttf draws DOS text screens with a TrueType font, smoothed by Linux (DOSBox-X's built-in
# font by default; font= takes a .ttf path). A graphics screen switches to outputswitch's
# renderer by itself, and back. For the original pixel look: output=opengl.
[sdl]
output=ttf
[ttf]
font=
lins=25
cols=80
outputswitch=auto
EOF
    fi
    printf '%s' "$c"
}
retro_cmd() {
    local cmd=${1:-list} in="" f g
    case "$cmd" in
        list|status|"")
            printf '%-8s %-15s %-9s %-14s %-8s %s\n' GUEST SYSTEM ENGINE INSTALLED STATE DISK
            for g in $GUESTS; do status_cmd "$g"; done
            for g in $DELPHI_VERSIONS; do [ -d "$HOME/.local/share/wine/delphi$g" ] && status_cmd "delphi$g"; done
            if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then echo "QEMU: KVM available."; else echo "QEMU: no usable /dev/kvm here: NT 4.0 and 2000 run in software emulation."; fi ;;
        which)
            f=${2:?usage: retro which FILE}; [ -f "$f" ] || die "no such file: $f"
            retro_pick "$f"; echo "$(basename "$f"): $KIND -> ${PICK:-nothing}. $WHY." ;;
        run)
            shift
            while [ $# -gt 0 ]; do case "$1" in --in) in=${2:?--in GUEST}; shift 2 ;; --in=*) in=${1#--in=}; shift ;; *) break ;; esac; done
            f=${1:?usage: retro run [--in win31|win95|winnt40|win2000|wine|dos] FILE}
            [ -f "$f" ] || die "no such file: $f"
            retro_pick "$f"
            case "${in:-$PICK}" in
                dos)
                    f=$(readlink -f "$f")
                    echo "DOSBox-X, the file's folder as C: ($(basename "$f")); settings: $(dos_conf)."
                    exec dosbox-x -conf "$(dos_conf)" -c "mount c \"$(dirname "$f")\"" -c "c:" -c "$(basename "$f")" ;;
                delphi1) exec "$SELF" delphi1 run "$f" "${@:2}" ;;
                com)     echo "Wine (COM prefix $COM_PREFIX)."; f=$(readlink -f "$f"); cd "$(dirname "$f")" || exit 1
                         WINEPREFIX="$COM_PREFIX" WINEDEBUG=-all exec wine "$f" "${@:2}" ;;
                wine)    case "$PICK" in delphi1) exec "$SELF" delphi1 run "$f" "${@:2}" ;; com) WINEPREFIX="$COM_PREFIX" WINEDEBUG=-all exec wine "$f" "${@:2}" ;;
                             *) die "$(basename "$f"): $WHY; Wine cannot run it." ;; esac ;;
                win31|win95|winnt40|win2000) exec "$SELF" "$in" run "$f" ;;
                "") die "$(basename "$f"): $WHY." ;;
                *) die "--in takes win31, win95, winnt40, win2000, wine or dos" ;;
            esac ;;
        sizes) sizes_cmd ;;
        help|-h|--help) help_cmd ;;
        *) die "usage: retro [list] | retro run [--in GUEST] FILE | retro which FILE | retro sizes | retro help" ;;
    esac
}

# =================================================================================================
# The whole run is one function, called on the last line: bash has then read the entire file before
# anything runs, so dev-setup rewriting this file while a guest is up cannot break the running copy.
main() {
    GUEST=${1:-}; [ $# -gt 0 ] && shift
    case "$GUEST" in
        retro) retro_cmd "$@"; exit ;;
        delphi) delphi_n_cmd "$@"; exit ;;
        win31|win95|winnt40|win2000) guest_info "$GUEST"; mkdir -p "$WS/install/apps" ;;
        delphi1) guest_info "$GUEST" ;;
        *) die "dev-retro: called as '$GUEST'; the commands are win31, win95, winnt40, win2000, delphi1, delphi and retro." ;;
    esac
    case "${1:-}" in
        where) where_cmd "$GUEST"; exit ;;
        status) status_cmd "$GUEST"; exit ;;
        help|-h|--help) help_cmd; exit ;;
        launcher) write_launcher "$GUEST"; exit ;;
        fonts) [ "$GUEST" = delphi1 ] && die "delphi1 has them already ('delphi1 setup': winetricks corefonts tahoma, fontsmooth=rgb)."; fonts_cmd "$GUEST"; exit ;;
        put) [ "$GUEST" = win31 ] || [ "$GUEST" = delphi1 ] && die "$GUEST reaches your files directly: '$GUEST run FILE'."; shift; exch_put "$GUEST" "$@"; exit ;;
        get) [ "$GUEST" = win31 ] || [ "$GUEST" = delphi1 ] && die "$GUEST has no exchange disk."; shift; exch_get "$GUEST" "$@"; exit ;;
        # v93: the app CD, the exchange disk's size, win95's undo points
        cd) [ "$GUEST" = delphi1 ] && die "delphi1 reads its media from ~/win31/install/apps ('delphi1 setup')."; shift; cd_cmd "$GUEST" "$@"; exit ;;
        exchange) case "$GUEST" in win95|winnt40|win2000) ;; *) die "$GUEST has no exchange disk." ;; esac
                  exch_cmd "$GUEST" "${2:-info}" "${@:3}"; exit ;;
        snapshot) if [ "$GUEST" = win95 ]; then shift; win95_snapshot "$@"; exit; fi ;;
    esac
    case "$GUEST" in
        win31) win31_cmd "$@" ;;
        win95) win95_cmd "$@" ;;
        winnt40|win2000) nt_cmd "$@" ;;
        delphi1) delphi_cmd "$@" ;;
    esac
}
main "$@"; exit $?
DEVRETRO_EOF
    chmod +x ~/.local/lib/dev-retro/dev-retro.new
    mv -f ~/.local/lib/dev-retro/dev-retro.new ~/.local/lib/dev-retro/dev-retro
    for RETRO_CMD in win31 win95 winnt40 win2000 delphi1 delphi retro; do
        # shellcheck disable=SC2016   # $HOME is for the wrapper to expand
        printf '#!/bin/sh\n# %s - written by dev-setup (install-retro); the logic is in ~/.local/lib/dev-retro/dev-retro.\nexec "$HOME/.local/lib/dev-retro/dev-retro" %s "$@"\n' \
            "$RETRO_CMD" "$RETRO_CMD" > ~/.local/bin/"$RETRO_CMD.new"
        chmod +x ~/.local/bin/"$RETRO_CMD.new"
        mv -f ~/.local/bin/"$RETRO_CMD.new" ~/.local/bin/"$RETRO_CMD"
    done
    # Workspaces (no disk images: '<cmd> setup' makes those) and the QEMU guests' settings, written once.
    # v93: install/apps in each guest for program CDs, and ~/delphi/install/N for Delphi 3, 4, 5, 6 and 7.
    mkdir -p ~/win95/install/apps ~/winnt40/install/apps ~/win2000/install/apps ~/delphi/install/3 ~/delphi/install/4 ~/delphi/install/5 ~/delphi/install/6 ~/delphi/install/7
    for RETRO_G in winnt40 win2000; do
        [ -f ~/"$RETRO_G"/config ] && continue
        if [ "$RETRO_G" = winnt40 ]; then
            R_MEM=128; R_HPET=off; R_DISK=4; R_SOUND=sb16; R_MOUSE=ps2
        else
            R_MEM=256; R_HPET=on; R_DISK=8; R_SOUND=AC97; R_MOUSE=tablet
        fi
        cat > ~/"$RETRO_G"/config << EOF_RCFG
# ~/$RETRO_G/config - written by dev-setup (install-retro) once; edit freely, setup leaves it alone.
# Read by '$RETRO_G' each time it starts QEMU.
MEM=$R_MEM                # MB
CPU=pentium3            # pentium if setup blue-screens on this model
MACHINE=pc
HPET=$R_HPET               # on cuts Windows 2000's idle CPU use
DISK_GB=$R_DISK              # the size '$RETRO_G setup' creates (NT 4.0 setup cannot format over 4 GB)
DISK_FORMAT=qcow2       # qcow2 (snapshots), or raw: '$RETRO_G setup --raw' (NT 4.0's old qcow2 boot bug)
VIDEO=cirrus            # both ship a Cirrus driver; skip NT 4.0's display "Test" button, which can hang
NIC=pcnet               # AMD PCnet, user-mode networking; none turns it off
SOUND=$R_SOUND             # sb16, AC97 or none (drivers on the install CDs)
MOUSE=$R_MOUSE             # ps2 (captured; Ctrl+Alt+G releases it) or tablet (USB: Windows 2000)
ACCEL=auto              # auto (KVM when /dev/kvm is usable), kvm or tcg
DISPLAY_OPTS=gtk,zoom-to-fit=on
EXTRA_ARGS=""           # more QEMU options, e.g. "-smp 2"
EOF_RCFG
    done
    # Launcher icons (ChromeOS app drawer): one per guest. A guest not installed yet opens a window saying
    # '<cmd> setup' and where its media goes. delphi1's also points Delphi's own Wine entries at 'delphi1'.
    for RETRO_G in win31 win95 winnt40 win2000 delphi1; do
        "$HOME/.local/bin/$RETRO_G" launcher > /dev/null 2>&1 || echo "NOTICE: could not write the $RETRO_G launcher entry ('$RETRO_G launcher' retries)."
    done

    # ~/.bashrc: the Open Watcom environment, a marked block rewritten on every run. PATH gains
    # binl64 (the 64-bit Linux tools) with binl behind it, both appended so Open Watcom's own vi and wrc
    # never shadow the system ones. Nothing here runs a command at shell start.
    sed -i '/^# >>> dev-setup retro >>>$/,/^# <<< dev-setup retro <<<$/d' ~/.bashrc
    cat >> ~/.bashrc << 'EOF'
# >>> dev-setup retro >>>
# Written by dev-setup (install-retro); replaced on each run. Open Watcom v2 in /opt/watcom.
if [ -d /opt/watcom ]; then
    export WATCOM=/opt/watcom
    export INCLUDE="$WATCOM/h"          # DOS and (with -bt=nt) Win32; Win16 adds $WATCOM/h/win
    export EDPATH="$WATCOM/eddat"
    export WIPFC="$WATCOM/wipfc"
    export PATH="$PATH:$WATCOM/binl64:$WATCOM/binl"
fi
# <<< dev-setup retro <<<
EOF
    if [ -x "$OW_HOME/binl64/wcl" ]; then
        echo "Open Watcom: $("$OW_HOME/binl64/wcl" 2> /dev/null | head -n 1 | sed 's/^ *//')"
    fi
    echo "DOSBox-X: $(dosbox-x --version 2>&1 | grep -m1 -i "dosbox-x version" || echo "not installed")"
    echo "QEMU: $(qemu-system-i386 --version 2> /dev/null | head -n 1 || echo "not installed")"
    # v92: one line per guest: where its media goes and whether it is there.
    echo "Retro guests (your own media; 'retro' lists them, '<cmd> help' explains each):"
    retro_media() {   # retro_media CMD DIR PATTERN...: one summary line
        local cmd=$1 dir=$2 found; shift 2
        found=$(for pat in "$@"; do find "$dir" -maxdepth 4 -type f -iname "$pat" 2> /dev/null; done | head -n 1)
        if [ -n "$found" ]; then echo "  $cmd: media found ($(basename "$found")): '$cmd setup'"
        else echo "  $cmd: put your media in $dir, then '$cmd setup'"; fi
    }
    retro_media win31 "$HOME/win31/install/windows" setup.exe '*.img' '*.ima'
    retro_media win95 "$HOME/win95/install" '*.iso'
    retro_media winnt40 "$HOME/winnt40/install" '*.iso' '*.img'
    retro_media win2000 "$HOME/win2000/install" '*.iso'
    retro_media delphi1 "$HOME/win31/install/apps" setup.exe
    for RETRO_N in 3 4 5 6 7; do
        if [ -n "$(find "$HOME/delphi/install/$RETRO_N" -mindepth 1 -maxdepth 1 ! -name '.*' 2> /dev/null | head -n 1)" ]; then
            echo "  delphi $RETRO_N: media found: 'delphi $RETRO_N setup'"
        fi
    done
    echo "  delphi 3 / 4 / 5 / 6 / 7 (Wine): each one's CD (.iso or files) in ~/delphi/install/N, then 'delphi N setup'; 'delphi' lists them."
    echo "  Program CDs for a guest: .iso files in ~/<guest>/install/apps, F: in the guest ('<guest> cd list')."
    echo "  Delphi 1 under Wine has no integrated debugger, Database Desktop or BDE table access: 'delphi1 help'; win31 has all three."
    echo "  Fonts for a guest: '<guest> fonts' puts the core fonts and Tahoma on it, with a README on installing them and font smoothing."
    # v93: the disk sizes in effect, so they can be checked (and changed in secrets.env) before a disk exists.
    "$HOME/.local/bin/retro" sizes 2> /dev/null | sed 's/^/  /' || true
else
    echo "Skipping retro development tools. (Run with 'install-retro'; not part of install-all)"
fi

# =================================================================
# install-hermes / install-openclaw : personal agents (added in v86). Both opt-in, in no group,
# NOT in install-all. A personal agent is a long-running assistant with memory, skills and a gateway
# you can message from Telegram, Discord, Slack and others; it is not a coding agent (Claude Code,
# Codex, Gemini CLI and aider come with install-node) and not a framework (install-agentic).
#   install-hermes: Hermes Agent by Nous Research (github.com/NousResearch/hermes-agent, MIT). Its own
#     installer, taken from the GitHub repository (scripts/install.sh; the project's quick start pipes
#     the same installer from hermes-agent.nousresearch.com), clones the code into ~/.hermes/hermes-agent,
#     fetches uv and a managed Python 3.14, and puts 'hermes' in ~/.local/bin; your data stays in
#     ~/.hermes (config.yaml, .env, sessions, memories, skills). Run with --non-interactive, so its
#     setup wizard and gateway service are skipped, --skip-computer-use (no desktop-control driver)
#     and, unless HERMES_BROWSER=1, --skip-browser (no agent-browser + Chromium, about 300 MB). Hermes
#     remembers both choices across updates, so HERMES_BROWSER=1 on a later run also installs the
#     browser tools explicitly ('hermes pm install agent-browser'). A rerun updates the checkout.
#   install-openclaw: OpenClaw (github.com/openclaw/openclaw, MIT), the npm package 'openclaw' on
#     nvm's Node (it needs Node 24.16+ or 26.1+; nvm's LTS is 24 and moves to 26 in October 2026),
#     about 900 MB of node_modules. Not its curl installer, which can bring its own Node. The
#     gateway service is NOT installed ('openclaw gateway install' does it later). Its anonymous
#     feature statistics are off by default, and setup records that choice ('openclaw telemetry
#     off') so no wizard asks; the daily update check stays on, since OpenClaw ships security fixes
#     often ('openclaw config set update.checkOnStart false' stops it).
# What both need, and what setup does not do: a model with at least a 64K-token context (Hermes
# refuses less). An 8 GB Chromebook cannot hold that locally, so dev-init points them at a cloud key
# (AGENT_ANTHROPIC_API_KEY, OPENROUTER_API_KEY) or at a bigger machine's Ollama (OLLAMA_REMOTE) from
# secrets.env; Nous Portal signs Hermes in through a browser ('hermes portal'). Messaging channels,
# the gateway services and ClawHub skills stay manual: an agent runs as you, can read your files
# (secrets.env included) and runs commands, and the Crostini user has passwordless sudo. Hermes asks
# before a risky command; OpenClaw runs commands without asking by default, so dev-init sets its
# tools.exec.mode to ask. Connect throwaway bot accounts and install only skills you have read. The
# Linux container stops when the Chromebook sleeps, so an agent here is not reachable around the clock.
# =================================================================
if [[ "$FLAGS" =~ " install-hermes " ]]; then
    echo "================================================================="
    echo "Installing Hermes Agent (Nous Research)..."
    echo "================================================================="
    HERMES_INSTALLER="$ASSETS/downloads/hermes-install.sh"
    if curl -fsSL --retry 3 -o "$HERMES_INSTALLER" https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
        && head -n 1 "$HERMES_INSTALLER" | grep -q '^#!'; then
        HERMES_ARGS=(--non-interactive --skip-computer-use)
        [ "${HERMES_BROWSER:-0}" = 1 ] || HERMES_ARGS+=(--skip-browser)
        # Not fatal under set -e: a failed Hermes install should not stop the rest of setup.
        if bash "$HERMES_INSTALLER" "${HERMES_ARGS[@]}"; then
            echo "Hermes Agent installed: $(~/.local/bin/hermes --version 2> /dev/null | head -n 1)"
            # --skip-browser is remembered, so asking for the browser later needs an explicit install.
            if [ "${HERMES_BROWSER:-0}" = 1 ]; then
                ~/.local/bin/hermes pm install agent-browser || echo "NOTICE: 'hermes pm install agent-browser' failed; rerun it by hand."
            fi
        else
            echo "NOTICE: the Hermes installer failed (its log: ~/.hermes/logs/install.log); rerun setup with install-hermes, or 'hermes pm doctor'."
        fi
    else
        echo "NOTICE: could not download the Hermes installer from GitHub; rerun setup with install-hermes to retry."
    fi
    rm -f "$HERMES_INSTALLER"
    if [ -x ~/.local/bin/hermes ]; then
        # Hermes borrows Claude Code's and Codex's logins when it has none of its own, and their
        # single-use refresh tokens then log one program out of the other. Claude Code is part of
        # install-node, so Hermes keeps to its own credentials (dev-init gives it a key).
        ~/.local/bin/hermes config set auth.adopt_external_logins false > /dev/null 2>&1 \
            || echo "NOTICE: could not set auth.adopt_external_logins=false; run 'hermes config set auth.adopt_external_logins false'."
    fi
else
    echo "Skipping Hermes Agent. (Run with 'install-hermes'; not part of install-all)"
fi

if [[ "$FLAGS" =~ " install-openclaw " ]]; then
    echo "================================================================="
    echo "Installing OpenClaw..."
    echo "================================================================="
    if [ -d "$HOME/.config/nvm" ]; then export NVM_DIR="$HOME/.config/nvm"; else export NVM_DIR="$HOME/.nvm"; fi
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    OC_NODE=$(node --version 2> /dev/null || true)
    # OpenClaw's engines field: >=24.16.0 <25, or >=26.1.0.
    if node -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit((a===24&&b>=16)||(a===26&&b>=1)||a>26?0:1)' 2> /dev/null; then
        # npm 12 blocks dependency install scripts unless allowed by name (see install-node): openclaw's
        # own postinstall sets up its bundled plugins, koffi picks its prebuilt native library,
        # protobufjs checks its version.
        if npm install -g --allow-scripts=openclaw,koffi,protobufjs openclaw@latest; then
            # Feature statistics are off by default; record the choice (in ~/.openclaw/openclaw.json,
            # which dev-init's onboarding keeps) so no wizard asks for it.
            openclaw telemetry off > /dev/null 2>&1 || echo "NOTICE: could not switch OpenClaw telemetry off; run 'openclaw telemetry off'."
            echo "OpenClaw installed: $(openclaw --version 2> /dev/null | head -n 1) on Node $OC_NODE"
            echo "(If you installed its gateway service, 'openclaw gateway restart' puts the new version in place.)"
        else
            echo "NOTICE: npm could not install openclaw; rerun setup with install-openclaw."
        fi
    else
        echo "NOTICE: OpenClaw needs Node 24.16+ or 26.1+ and nvm's default is ${OC_NODE:-missing}; rerun setup with install-node install-openclaw."
    fi
else
    echo "Skipping OpenClaw. (Run with 'install-openclaw'; not part of install-all)"
fi

# v65: last look at the JDK on PATH. gradle and kotlin unlink brew's openjdk right after their own
# install, but any later formula can depend on it too and link it again.
unlink_brew_openjdk

# Final Cleanup
echo "Cleaning up system packages..."
sudo apt autoremove -y

echo "================================================================="
echo "Setup Version 93 complete! 🎉"
echo "NEXT, in this order:"
echo "  a. source ~/.bashrc                      (or open a new terminal)"
echo "  b. ./dev-init-chromebook.sh <flags>  applies ~/.config/dev-init/secrets.env: GitHub, Hugging Face,"
echo "                                           cloud and Vercel logins, keys into ~/.bashrc, SSH key upload"
echo "  c. ./dev-test-chromebook.sh <flags>  verifies the install AND the logins"
echo "  d. (optional) ./dev-demo-chromebook.sh <flags>  downloads hands-on demos into ~/dev-demo"
echo "Setup itself never reads your tokens except HF_TOKEN for the Gemma login (and a database or LDAP"
echo "password you chose for install-db-server / install-ldap, and the LAN_* settings); until step b the test script reports"
echo "every login as a WARN, even with secrets.env filled in."
echo "IMPORTANT:"
echo "1. Restart your terminal or run 'newgrp docker' for Docker permissions. For GPU acceleration (render group),"
echo "   shut Linux down once: right-click the Terminal icon > Shut down Linux, then reopen Terminal."
# v92: the list names only what this run's flags set up (v91 listed every stack whatever the flags).
PATH_NOTES=(pipx)
path_note() { local f; for f in "${@:2}"; do if [[ "$FLAGS" == *" $f "* ]]; then PATH_NOTES+=("$1"); return; fi; done; }
path_note "Rust" install-rust
path_note "Go" install-go
path_note "Ruby" install-ruby
path_note "Claude Code and the Node agents" install-node
path_note "Flutter" install-mobile install-flutter
path_note "Android/NDK" install-mobile install-tauri install-rn install-flutter install-android-native
path_note "JAVA_HOME" install-java install-mobile install-tauri install-rn install-flutter install-android-native install-oracle
path_note "Cursor" install-cursor
path_note "DuckDB and dbt" install-lakehouse
path_note "Temporal" install-agentic
path_note "the cloud CLIs" install-aws install-azure install-gcp install-vercel install-cloudflare
path_note "Ansible" install-ansible-full install-ansible-core
path_note "corepack/Angular/TanStack" install-web install-tanstack
path_note "kubectl" install-k8s
path_note ".NET" install-dotnet
path_note "Godot" install-godot
path_note "the Drupal CLIs" install-drupal
path_note "Composer's global bin (laravel)" install-laravel
path_note "Apollo's settings" install-graphql
path_note "the Ollama client settings" install-ollama
path_note "Firebird's lock directory" install-db
path_note "InterBase's ib-* commands" install-interbase
path_note "SQLITE_VEC" install-vector
path_note "Selenium and Cypress settings" install-selenium install-cypress
path_note "OpenVox and Cinc" install-puppet install-chef
path_note "the COM variables (wine-com)" install-com
path_note "Open Watcom" install-retro
PATH_LIST=$(printf '%s, ' "${PATH_NOTES[@]}"); PATH_LIST=${PATH_LIST%, }
echo "2. Run 'source ~/.bashrc' so the new PATH and settings from this run apply ($PATH_LIST)."
if [[ "$FLAGS" =~ " install-pwsh " ]] && [ -x /usr/local/bin/pwsh ]; then
    echo "3. Run 'pwsh' to start PowerShell."
fi
# v93: what a failed download skipped (fetch_tgz says why above); the rest of the run went on without it.
if [ ${#DL_FAILED[@]} -gt 0 ]; then
    DL_LIST=$(printf '%s, ' "${DL_FAILED[@]}"); DL_LIST=${DL_LIST%, }
    DL_RERUN=$(printf '%s\n' "${DL_FAILED[@]}" | sed -n 's/.*(\(install-[a-z]*\)).*/\1/p' | xargs)
    echo "-  Not installed this run, its download failed: $DL_LIST. Rerun with just: $DL_RERUN"
fi
if [[ "$FLAGS" =~ " install-interbase " ]] && [ -x /opt/interbase/bin/isql ] && ! (exec 3<> /dev/tcp/127.0.0.1/3050) 2> /dev/null; then
    echo "-  InterBase is installed but its server is not running: dev-init with install-interbase registers it and starts it."
fi
if [[ "$FLAGS" =~ " install-mssql " ]] || [[ "$FLAGS" =~ " install-oracle " ]]; then
    # v92: say which containers really exist; a missing one names the recorded reason and the fix.
    DB_MADE=(); DB_MISSING=0
    for DB_E in mssql oracle; do
        [[ "$FLAGS" == *" install-$DB_E "* ]] || continue
        if sudo docker container inspect "devdb-$DB_E" > /dev/null 2>&1; then
            DB_MADE+=("$DB_E")
            [ -f "$HOME/.config/devdb/$DB_E.skipped" ] && echo "-  devdb-$DB_E stays as it was: $(cat "$HOME/.config/devdb/$DB_E.skipped")"
        else
            DB_MISSING=1
            echo "-  devdb-$DB_E NOT created: $(cat "$HOME/.config/devdb/$DB_E.skipped" 2> /dev/null || echo "see the NOTICE above in this log")"
        fi
    done
    if [ "${#DB_MADE[@]}" -gt 0 ]; then
        echo "-  Database servers created but stopped (${DB_MADE[*]}). One at a time (each holds ~2 GB): 'mssql up' / 'oracle up',"
        echo "   then 'mssql sql' / 'oracle sql'; 'mssql down' / 'oracle down' gives the memory back."
    fi
    [ "$DB_MISSING" = 1 ] && echo "   Disk: ChromeOS Settings > About ChromeOS > Linux development environment > Disk size."
fi
if [ -x "$HOME/.local/bin/devsvc" ]; then
    echo "-  Shared services: 'devsvc status' lists them. Those in DEVSVC_AUTOSTART (default Redis, Memcached) run;"
    echo "   the rest start with 'devsvc up NAME' and 'devsvc down NAME' gives the memory back. 'devsvc info NAME' has the address and login."
fi
if [[ "$FLAGS" =~ " install-ldap " ]]; then
    echo "-  LDAP is running: 'ldap status' shows the directories, 'ldap passwords' the passwords setup chose,"
    echo "   'ldap drupal' the values for Drupal. The ldap command is in ~/.local/bin (a new terminal has it on PATH)."
fi
if [[ "$FLAGS" =~ " install-lan " ]]; then
    echo "-  Laptop network: fill in LAN_HOSTS (every laptop, name=address) in secrets.env and run dev-init;"
    echo "   'lan scan' then shows what the other laptops share."
fi
if [[ "$FLAGS" =~ " install-laravel " ]]; then
    echo "-  Laravel: 'laravel new <app>' in a new terminal (Composer's global bin joins PATH); 'composer run dev' serves it."
fi
if [[ "$FLAGS" =~ " install-symfony " ]]; then
    echo "-  Symfony: 'symfony new <app> --webapp', then 'symfony serve' in it; 'symfony server:ca:install' is optional (https)."
fi
if [[ "$FLAGS" =~ " install-graphql " ]]; then
    echo "-  GraphQL: rover, router and apollo-mcp-server are in ~/.local/bin. Local federation needs no account;"
    echo "   an optional GraphOS key goes in secrets.env (APOLLO_KEY, left unexported) and dev-init hands it to Rover."
fi
if [ "$TESTING_ANY" = 1 ]; then
    echo "-  Testing: Playwright's browsers are in ~/.cache/ms-playwright, 'robot' and 'rfbrowser' in ~/.local/bin; the Selenium"
    echo "   Grid starts with 'devsvc up selenium' (watch it at http://localhost:7900). Test libraries go in each project;"
    echo "   dev-demo's testing/e2e-bakeoff runs one Gherkin feature through every runner (install-testing)."
fi
if [[ "$FLAGS" =~ " install-gitlab " ]]; then
    echo "-  GitLab: GITLAB_TOKEN_ONCE in secrets.env and dev-init log glab in (git.drupalcode.org too, with its own token);"
    echo "   'gitlab-ci-local' runs a project's pipeline here.$([[ "$FLAGS" =~ " install-gitlab-runner " ]] && echo " The runner registers once GITLAB_RUNNER_TOKEN_ONCE is set.")"
fi
if [[ "$FLAGS" =~ " install-vue " ]]; then
    echo "-  Vue: 'npm create vue@latest' or 'npm create nuxt@latest' in a new terminal; dev-demo has vue/vue-links and drupal/drupal-nuxt."
fi
if [[ "$FLAGS" =~ " install-puppet " ]] || [[ "$FLAGS" =~ " install-chef " ]]; then
    echo "-  Configuration management: puppet, facter and bolt (OpenVox) and Cinc's cinc-client, knife, kitchen and cookstyle"
    echo "   are on PATH in a new terminal; dev-demo's iac/cm-bakeoff configures the same server with Ansible, Puppet and Chef."
fi
if [[ "$FLAGS" =~ " install-com " ]]; then
    echo "-  COM: 'wine-com' runs programs in the COM prefix (~/.local/share/wine/com); dev-test builds a COM server"
    echo "   with widl + mingw and calls it in-process and out-of-process; dev-demo has the walkthrough (install-com)."
fi
if [[ "$FLAGS" =~ " install-retro " ]]; then
    echo "-  Retro: 'retro' lists the guests: win31 and win95 (DOSBox-X), winnt40 and win2000 (QEMU), delphi1 (Wine). Your media goes"
    echo "   in ~/<guest>/install (Delphi 1: ~/win31/install/apps), then '<cmd> setup'; each has a launcher icon. 'retro run FILE'"
    echo "   runs one program on the engine its header calls for. Open Watcom (wcl, wcl386) is on PATH in a new terminal."
    if [ -e /dev/kvm ] && ! { [ -r /dev/kvm ] && [ -w /dev/kvm ]; }; then
        echo "   QEMU uses KVM after Linux is shut down and reopened once (group $(stat -c %G /dev/kvm 2> /dev/null))."
    fi
fi
if [[ "$FLAGS" =~ " install-hermes " ]] || [[ "$FLAGS" =~ " install-openclaw " ]]; then
    echo "-  Personal agents: dev-init gives Hermes / OpenClaw a model from secrets.env (AGENT_ANTHROPIC_API_KEY, OPENROUTER_API_KEY or OLLAMA_REMOTE:"
    echo "   they need a 64K-token context, more than an 8 GB Chromebook holds). Then 'hermes' or 'openclaw chat'."
    echo "   Channels and gateway services stay manual; connect throwaway bot accounts, not your own."
fi
if [[ "$FLAGS" =~ " install-lan-share " ]]; then
    echo "-  Sharing: LAN_SHARE in secrets.env picks what this machine serves ('lan share apply' after a change)."
    echo "   Add each port in ChromeOS once: Settings > Advanced > Developers > Linux > Port forwarding"
    echo "   ('lan share ports' lists them). 'lan share off' on any Wi-Fi that is not yours."
fi
echo "================================================================="
