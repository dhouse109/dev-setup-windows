#!/bin/bash
# dev-init-chromebook - Version 93
# Version history: CHANGELOG.md, next to this script in the bundle
# (one section per script, newest version first).
#
# Third script in the set: setup installs, test verifies, init (this one) applies logins, keys and config.
# Run order: init (writes the secrets template)  ->  setup  ->  init (applies secrets.env)  ->  test.
# Takes the SAME flags with the SAME expansion, and only initializes what those flags installed.
#
#   ./dev-init-chromebook.sh install-all
#   ./dev-init-chromebook.sh install-node install-gemma install-agentic
#
# Init-only flag:
#   noninteractive   never prompt; steps that need a login you didn't supply a token for are skipped
#
# SECRETS: this script never contains keys. They live in  ~/.config/dev-init/secrets.env  (mode 600).
#   1. Run once: it writes the template and exits.
#   2. Fill in the keys you have (leave the rest empty).
#   3. Run again: it applies them. Rerun any time; every step is idempotent.
# ~/.bashrc sources that file, so 'export'ed keys are in every new shell. Values named *_ONCE are
# consumed by this script (a one-time login) and deliberately not exported.

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

# =================================================================
# FLAG EXPANSION (STACK SWITCHES)  -- copied verbatim from the installer
# =================================================================
FLAGS=" $* "

echo "Active Init Flags: $FLAGS"

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

# v85: install-retro pulls in install-com (its Win16 tests run on Wine); matches the installer.
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
INTERACTIVE=1; has noninteractive && INTERACTIVE=0

# Same environment the test script rebuilds (brew, nvm, PATH additions), without sourcing ~/.bashrc.
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
export ANDROID_HOME="$HOME/.android/sdk"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1   # v63
export PATH="$PATH:$HOME/.dotnet/tools"

# =================================================================
# SECRETS FILE
# =================================================================
SECRETS_DIR="$HOME/.config/dev-init"
SECRETS="$SECRETS_DIR/secrets.env"

NEW_SECRETS=0
if [ ! -f "$SECRETS" ]; then
    mkdir -p "$SECRETS_DIR"
    NEW_SECRETS=1
    cat << 'EOF' > "$SECRETS"
# ~/.config/dev-init/secrets.env  --  read by dev-init-chromebook and sourced by ~/.bashrc.
# Fill in what you have; leave the rest empty. Keep this file out of any repo (it is mode 600).
#
# 'export'ed values become environment variables in every new shell.
# '*_ONCE' values are used by dev-init for a one-time login and are NOT exported.

# --- Identity (git) ---------------------------------------------------------
GIT_NAME=""
GIT_EMAIL=""

# --- GitHub (base: gh, SSH key upload) ---------------------------------------
# A classic PAT with 'repo', 'read:org', 'admin:public_key' scopes, or a fine-grained token
# with equivalent access. Empty = dev-init runs the interactive 'gh auth login' instead.
# Not exported on purpose: an exported GITHUB_TOKEN overrides gh's stored login.
GH_TOKEN_ONCE=""

# --- AI coding agents (install-node) ------------------------------------------
# Claude Code: leave empty if you use a Claude subscription (run 'claude' once to log in);
# set it to bill API usage instead. Also read by aider (install-node) and langchain-anthropic (install-agentic).
export ANTHROPIC_API_KEY=""
# Codex CLI: leave empty to log in with ChatGPT ('codex login'), or set to use the API.
export OPENAI_API_KEY=""

# --- Google AI (install-node, install-gemma, install-agentic) --------------
# One key from https://aistudio.google.com/apikey. gemma_client.py, Gemini CLI and aider read GEMINI_API_KEY;
# langchain-google-genai reads GOOGLE_API_KEY; dev-init exports both from this value.
export GEMINI_API_KEY=""

# --- Hugging Face (install-gemma: gated Gemma weights for the Transformers path) -------------
# A 'read' token from https://huggingface.co/settings/tokens
export HF_TOKEN=""

# --- Langfuse (install-agentic) ----------------------------------------------
# Project keys from cloud.langfuse.com (free Hobby tier) or your self-hosted instance.
export LANGFUSE_PUBLIC_KEY=""
export LANGFUSE_SECRET_KEY=""
export LANGFUSE_BASE_URL="https://cloud.langfuse.com"

# --- Expo / EAS (install-rn) -------------------------------------------------
# Personal access token from https://expo.dev/settings/access-tokens. Empty = 'eas login' prompts.
export EXPO_TOKEN=""
EOF
fi

# v57: cloud + IaC keys. Appended when missing, so a secrets.env from v53-v56 gains them too.
if ! grep -q '^# --- AWS (install-aws)' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- AWS (install-aws) --------------------------------------------------------
# Preferred: leave the keys commented out and let dev-init run 'aws configure sso' (IAM Identity
# Center), then uncomment AWS_PROFILE with the profile name it created so every shell and boto3 use it.
# Static keys are a fallback only. Lines stay COMMENTED until used: botocore treats an exported
# empty AWS_PROFILE as a profile named "" and fails, rather than ignoring it.
export AWS_DEFAULT_REGION="us-east-1"
#export AWS_PROFILE=""
#export AWS_ACCESS_KEY_ID=""
#export AWS_SECRET_ACCESS_KEY=""

# --- Azure (install-azure) ----------------------------------------------------
# Commented out = interactive 'az login --use-device-code'. For a service principal uncomment and
# set all three; these AZURE_* names are also what azure-identity's EnvironmentCredential reads.
#export AZURE_TENANT_ID=""
#export AZURE_CLIENT_ID=""
#export AZURE_CLIENT_SECRET=""
# Subscription name or id to make the default after login (not exported).
AZURE_SUBSCRIPTION_ONCE=""

# --- Google Cloud (install-gcp) -----------------------------------------------
# Commented out = interactive 'gcloud auth login' + 'gcloud auth application-default login'.
# For headless use, uncomment with the path to a service-account JSON key; the google-cloud-*
# SDKs read it (google-auth errors on an exported empty value, so it stays commented until set).
#export GOOGLE_APPLICATION_CREDENTIALS=""
# Project id to make the default (gcloud config set project); not exported.
GCP_PROJECT_ONCE=""
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added AWS / Azure / Google Cloud sections to $SECRETS (v57); fill in as needed."
fi

# v68: Drupal hosting tokens + a machine label. Appended when missing.
if ! grep -q '^# --- Drupal hosting (install-drupal)' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- This machine ----------------------------------------------------------------
# A short name for THIS Chromebook (e.g. joxer). Used to label the SSH key uploaded to GitHub,
# Pantheon and Acquia, so one machine's access can be revoked without touching the others.
# Give the tokens below the same label where the platform lets you name them.
MACHINE_LABEL=""

# --- Drupal hosting (install-drupal) ---------------------------------------------
# These tokens reach every site your account can, client production included. dev-init uses them
# to log the CLIs in and copies them into DDEV's global config (mode 600) for 'ddev pull'.
# Pantheon: dashboard.pantheon.io > Account > Machine tokens > Create token.
TERMINUS_MACHINE_TOKEN_ONCE=""
# Acquia: cloud.acquia.com > profile menu > Account settings > API Tokens > Create token (key + secret).
ACQUIA_API_KEY_ONCE=""
ACQUIA_API_SECRET_ONCE=""
# Upsun (formerly Platform.sh), optional: console.upsun.com > My profile > API tokens. The CLI reads
# this from the environment, so it is exported; leave it commented unless you use Upsun.
#export UPSUN_CLI_TOKEN=""
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added machine label and Drupal hosting sections to $SECRETS (v68); fill in as needed."
fi

# v67: Vercel + Jev keys. Appended when missing, so an older secrets.env gains them too.
if ! grep -q '^# --- Vercel (install-vercel)' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Vercel (install-vercel) ---------------------------------------------------
# Commented out = interactive 'vercel login'. A token from https://vercel.com/account/tokens makes
# the CLI non-interactive, but an exported VERCEL_TOKEN OVERRIDES the saved login in every shell,
# so leave it commented unless you want that.
#export VERCEL_TOKEN=""

# --- Jev / TypeSafe AI (install-jev) -------------------------------------------
# Direct access: a key from https://console.typesafe.ai/settings/keys (early access is waitlisted).
# Read by both TypeSafe SDKs (typesafe-sdk, @typesafe-ai/sdk).
export TYPESAFE_API_KEY=""
# Through Vercel AI Gateway instead (model 'typesafe-ai/jev' with the AI SDK): a key from the
# AI Gateway tab of the Vercel dashboard. Also serves every other model behind the gateway.
export AI_GATEWAY_API_KEY=""
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added Vercel and Jev sections to $SECRETS (v67); fill in as needed."
fi

# v76: Ansible. Appended when missing.
if ! grep -q '^# --- Ansible (install-ansible' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Ansible (install-ansible-full via install-iac, or install-ansible-core) --------------
# Optional. A file holding your vault password (one line, mode 600) lets ansible-playbook and
# ansible-vault open vault-encrypted files without --ask-vault-pass. Keep it outside any repo.
# Leave the line commented until the file exists: Ansible stops on a vault password file it
# cannot find, even in projects that use no vault.
#export ANSIBLE_VAULT_PASSWORD_FILE="$HOME/.config/dev-init/ansible-vault-pass"
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added an Ansible section to $SECRETS (v76); optional."
fi

# v77: local and cloud models. Appended when missing. All three stay commented until used.
if ! grep -q '^# --- Local models (install-ollama' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Local models (install-ollama, install-gemma, install-models) --------------------------
# All optional. Uncomment a line only when you have its value.
# Another machine's Ollama, for models too big for this one (e.g. the 32 GB Windows laptop, with
# OLLAMA_HOST=0.0.0.0:11434 set there and its firewall open to your private network). Only the
# 'ollama-remote' command uses it; plain 'ollama' and every client stay on this machine.
#export OLLAMA_REMOTE="http://192.168.1.50:11434"
# ollama.com API key (https://ollama.com/settings/keys) for calling cloud models over its API
# directly. The local CLI does not need it: it uses 'ollama signin' for :cloud models.
#export OLLAMA_API_KEY=""
# DeepSeek's own API (https://platform.deepseek.com/api_keys), OpenAI-compatible. aider reads it
# (aider --model deepseek/deepseek-chat), as does langchain-deepseek.
#export DEEPSEEK_API_KEY=""
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a local-models section to $SECRETS (v77); optional."
fi

# v80: InterBase. Appended when missing. Stays commented until you change SYSDBA's password.
if ! grep -q '^# --- InterBase (install-interbase)' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- InterBase (install-interbase) -----------------------------------------------------------
# Optional. InterBase installs with SYSDBA / masterkey. Once you change it (dev-init prints the
# command), put the new password here so dev-test and dev-demo can still log in.
# The serial number is NOT kept here: InterBase's License Manager asks for it once, at registration.
#export INTERBASE_SYSDBA_PASSWORD="masterkey"
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added an InterBase section to $SECRETS (v80); optional."
fi

# v82: SQL Server and Oracle passwords. Appended when missing. Both stay commented: setup generates them.
if ! grep -q '^# --- Database servers (install-db-server' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Database servers (install-db-server: install-mssql, install-oracle) -----------------------
# Optional. Setup generates a password for each container, and 'mssql password' / 'oracle password'
# print it. To pick your own, uncomment a line BEFORE the first setup run with that flag: a password
# only takes effect when the database is first created. Letters, digits and _ are safe for both;
# SQL Server wants 8+ characters from three of: upper case, lower case, digits, symbols.
# Changed it later inside the database (ALTER LOGIN sa / ALTER USER system)? Put the new one here, so
# the mssql and oracle commands, dev-test and dev-demo still log in.
#export MSSQL_SA_PASSWORD=""
#export ORACLE_PWD=""
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a database-servers section to $SECRETS (v82); optional."
fi

# v83: LDAP. Appended when missing. Every line stays commented: setup generates the values.
if ! grep -q '^# --- LDAP directory (install-ldap' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- LDAP directory (install-ldap, install-ldap-full) ---------------------------------------------
# Optional. Setup generates these and keeps them in ~/.config/devldap/ldap.env ('ldap passwords' prints
# them). To choose your own, uncomment a line BEFORE the first setup run with install-ldap: the
# directories are created with them, and from then on ldap.env holds what they were created with.
# Not exported: only setup reads them. The base DN must be dc=... parts only for OpenLDAP (full).
#LDAP_BASE_DN="dc=example,dc=com"
#LLDAP_ADMIN_PASSWORD=""        # lldap's admin (uid=admin), 8+ characters
#OPENLDAP_ADMIN_PASSWORD=""     # OpenLDAP's admin (cn=admin), install-ldap-full
#LDAP_BIND_PASSWORD=""          # the read-only service account uid=drupal-bind that apps search with
#LDAP_SAMPLE_PASSWORD=""        # alice, bob and carol
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added an LDAP section to $SECRETS (v83); optional."
fi

# v84: the laptop network. Appended when missing. Not exported: the 'lan' command reads this file.
if ! grep -q '^# --- Laptop network (install-lan' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Laptop network (install-lan, install-lan-share) ---------------------------------------------
# Optional. Not exported: the 'lan' command, dev-init, dev-test and dev-demo read them from here.
# LAN_HOSTS is your address book: every laptop as name=address, separated by spaces. Put the SAME list
# on every laptop (this machine's own entry maps to 127.0.0.1 here). Give each laptop a fixed address
# first, a DHCP reservation on your router, or the list goes stale. A Chromebook's address: ChromeOS
# Settings > Network > your Wi-Fi network (IP address). A Windows laptop's: 'ipconfig' (IPv4 Address).
# v93: over Tailscale (the next section) the Chromebooks' entries are their 100.x Tailscale addresses.
LAN_HOSTS=""
#  e.g. LAN_HOSTS="tigerlake=192.168.1.21 yaviks=192.168.1.22 joxer=192.168.1.23 dragonair=192.168.1.24 winlaptop=192.168.1.33"
# This machine's name in LAN_HOSTS, when it is not MACHINE_LABEL (above).
LAN_SELF=""
# What THIS machine shares with the others (install-lan-share), any of:
#   ollama mssql oracle ldap ddev dev mcp
#   redis solr opensearch elasticsearch meilisearch typesense qdrant mongodb   (v89, the devsvc services;
#   redis, qdrant and mongodb only once REDIS_PASSWORD / QDRANT_API_KEY / MONGO_ROOT_PASSWORD are set;
#   memcached, milvus, atlas-local and the Selenium Grid have no login and are never shared)
# Empty = nothing. After a change: rerun dev-init, or 'lan share apply'. Over Tailscale (v93) that publishes
# the ports; with LAN_TAILSCALE=0 each port also needs a ChromeOS port forward ('lan share ports').
LAN_SHARE=""
# Ports of the dev servers and MCP servers you share (dev, mcp above). Those servers must listen on the
# network themselves: vite --host, ng serve --host 0.0.0.0, next dev -H 0.0.0.0, host="0.0.0.0".
#LAN_DEV_PORTS="3000 4200 5173"
#LAN_MCP_PORTS="8770"         # not 8000: php artisan serve and symfony serve use it
# More local services to share through the relay, as LANPORT or LANPORT:LOCALPORT, e.g. "8233" for
# Temporal's web UI. Keep LAN ports above 1024.
#LAN_EXTRA=""
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a laptop-network section to $SECRETS (v84); optional."
fi

# v86: the personal agents. Appended when missing. Optional; the keys stay commented until used.
if ! grep -q '^# --- Personal agents (install-hermes' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Personal agents (install-hermes, install-openclaw) ---------------------------------------------
# Optional. dev-init gives Hermes Agent and OpenClaw a model from these. Both need a model with at least
# a 64K-token context window (Hermes refuses less), more than an 8 GB Chromebook can hold, so use a
# cloud key or a bigger machine's Ollama. AGENT_PROVIDER:
#   auto           the first that is set: AGENT_ANTHROPIC_API_KEY (or ANTHROPIC_API_KEY, above),
#                  OPENROUTER_API_KEY, OLLAMA_REMOTE with AGENT_MODEL
#   anthropic | openrouter | ollama-remote     that one
#   skip           leave both agents' models alone
# Init only changes a model it set itself; one you pick with 'hermes model' or 'openclaw models set' stays.
AGENT_PROVIDER="auto"
# The model. Empty = claude-sonnet-5-5 (anthropic) or anthropic/claude-sonnet-5.5 (openrouter).
# Required for ollama-remote: a model pulled on that machine, e.g. qwen3.5:9b, whose Ollama is started
# with OLLAMA_CONTEXT_LENGTH=65536 (on Windows: a user environment variable, then restart Ollama).
AGENT_MODEL=""
# An Anthropic API key for the agents only (https://console.anthropic.com/settings/keys). Not exported:
# ANTHROPIC_API_KEY above works too, but it is exported to every shell, where Claude Code then bills
# the API instead of your Claude subscription. dev-init hands this one to the agents and no one else.
AGENT_ANTHROPIC_API_KEY=""
# OpenRouter (https://openrouter.ai/keys): one key, many providers' models, a per-key spending limit.
#export OPENROUTER_API_KEY=""
# Nous Portal (Nous Research's subscription) signs Hermes in through a browser instead: 'hermes portal'.
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a personal-agents section to $SECRETS (v86); optional."
fi

# v89: Cloudflare. Appended when missing. Optional: wrangler runs Workers locally without an account.
if ! grep -q '^# --- Cloudflare (install-cloudflare' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Cloudflare (install-cloudflare, install-cloudflared) ----------------------------------------------
# Optional. 'wrangler dev' needs no account; deploying ('wrangler deploy', d1/kv/r2 in the cloud) does.
# An API token from https://dash.cloudflare.com/profile/api-tokens (template "Edit Cloudflare Workers"),
# and the account ID from the dashboard's Workers & Pages overview. Exported, because wrangler reads them
# from the environment; with the token set, wrangler ignores a saved 'wrangler login'.
#export CLOUDFLARE_API_TOKEN=""
#export CLOUDFLARE_ACCOUNT_ID=""
# cloudflared: quick tunnels need nothing; named tunnels on your own domain use 'cloudflared tunnel login'.
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a Cloudflare section to $SECRETS (v89); optional."
fi

# v89: the shared development services (devsvc). Appended when missing. Optional; nothing here is a login.
if ! grep -q '^# --- Shared services (install-cache' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Shared services (install-cache, install-search, install-vector, install-mongodb; 'devsvc') -------
# Optional. Not exported: dev-setup and devsvc read them from here. Services in DEVSVC_AUTOSTART start
# with Linux; the rest wait for 'devsvc up NAME'. "none" autostarts nothing. Rerun dev-setup after a change.
#DEVSVC_AUTOSTART="redis memcached"
# The memory budget 'devsvc up' keeps the services under, in MB (the Linux VM sees ~6.4 GB of 8).
#DEVSVC_RAM_MB="3000"
# Redis has no password by default (it listens on 127.0.0.1 only). Set one before sharing Redis with your
# other laptops; the next dev-setup run applies it (a password change recreates the container, the data stays).
#REDIS_PASSWORD=""
# The same for Qdrant's API key and MongoDB's user root (a new or changed MONGO_ROOT_PASSWORD is written
# into MongoDB's data by the next setup run, which then turns authentication on; emptied, it turns it off).
#QDRANT_API_KEY=""
#MONGO_ROOT_PASSWORD=""
# Optional: an Atlas organization API key for the Atlas CLI (install-mongodb-atlas-local), exported so
# 'atlas' uses it in every shell. Atlas Local itself needs no account.
#export MONGODB_ATLAS_PUBLIC_API_KEY=""
#export MONGODB_ATLAS_PRIVATE_API_KEY=""
# The search engines' logins. Setup generates each on its first run with that service and keeps it in
# ~/.config/devsvc/devsvc.env ('devsvc password NAME'); from then on that file wins, because Solr,
# OpenSearch and Elasticsearch store theirs in their data. To choose your own, uncomment a line BEFORE the
# first setup run with that flag. Letters, digits and _ are safe; OpenSearch wants 8+ characters with an
# upper-case letter, a lower-case letter, a digit and a symbol (_ counts).
#SOLR_PASSWORD=""               # user solr (install-solr)
#OPENSEARCH_ADMIN_PASSWORD=""   # user admin (install-opensearch)
#ELASTIC_PASSWORD=""            # user elastic (install-elasticsearch)
#MEILI_MASTER_KEY=""            # 16+ characters (install-meilisearch)
#TYPESENSE_API_KEY=""           # (install-typesense)
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a shared-services section to $SECRETS (v89); optional."
fi

# v90: Apollo GraphOS. Appended when missing. Optional: Rover, the router and the MCP server work locally
# without an account.
if ! grep -q '^# --- Apollo GraphOS (install-graphql' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Apollo GraphOS (install-graphql) ------------------------------------------------------------------
# Optional. Local federation ('rover dev', 'rover supergraph compose'), the router and apollo-mcp-server need
# no account. A key unlocks GraphOS: schema checks and publishing, Studio, and Apollo Connectors in
# 'rover dev' (dev-demo's drupal-graphql connectors item). A personal API key from GraphOS Studio (your
# user settings, API keys) or a graph API key; the graph ref is graph-id@variant (e.g. my-graph@current).
# NOT exported, on purpose: in the environment, APOLLO_KEY makes every local router and MCP server report
# to GraphOS, where the Free plan allows self-hosted routers 60 requests a minute. dev-init writes the key
# into Rover's own profile instead (~/.config/rover/profiles/default), and the demo item that needs it
# passes it to that one command.
#APOLLO_KEY=""
#APOLLO_GRAPH_REF=""
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added an Apollo GraphOS section to $SECRETS (v90); optional."
fi

# v91: the test tools. Appended when missing. Optional: Playwright, Selenium, the Gherkin runners, Robot
# Framework and Cypress all run locally without an account.
if ! grep -q '^# --- Test tools (install-testing' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Test tools (install-testing, install-cypress) -----------------------------------------------------
# Optional. Nothing here is needed to run tests locally. Cypress Cloud records runs ('cypress run --record',
# with the projectId in the project's cypress.config) using this key, from the project's settings in Cypress
# Cloud. Exported, because Cypress reads it from the environment; only --record runs use it.
#export CYPRESS_RECORD_KEY=""
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a test tools section to $SECRETS (v91); optional."
fi

# v91: GitLab. Appended when missing. Optional: glab, gitlab-ci-local and the runner install without an account.
if ! grep -q '^# --- GitLab (install-gitlab' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- GitLab (install-gitlab, install-gitlab-runner) ----------------------------------------------------
# Optional. gitlab-ci-local runs pipelines here with no account. The *_ONCE values are used by dev-init once and
# never exported (an exported GITLAB_TOKEN would override glab's stored login).
# gitlab.com: a personal access token (Preferences > Access tokens; scopes api and write_repository). dev-init logs
# glab in with it and uploads ~/.ssh/id_ed25519.pub.
#GITLAB_TOKEN_ONCE=""
# git.drupalcode.org (drupal.org's GitLab): a personal access token from your git.drupalcode.org preferences, if
# your account can create one. glab then works there too (merge requests on issue forks). Git's SSH keys for
# drupal.org stay on your drupal.org profile.
#DRUPALCODE_TOKEN_ONCE=""
# GitLab Runner (install-gitlab-runner): a runner authentication token (glrt-...) from a project or group's
# Settings > CI/CD > Runners > New runner. dev-init registers this machine's runner once, with the Docker executor.
#GITLAB_RUNNER_TOKEN_ONCE=""
# GitLab's MCP server (beta, Free tier) in Claude Code: "1" adds it for your user; its first use opens GitLab's
# OAuth login. The top-level group (gitlab.com) must allow MCP access.
#GITLAB_MCP=""
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a GitLab section to $SECRETS (v91); optional."
fi

# v91: Puppet and Chef. Appended when missing. Optional: puppet apply, Bolt, cinc-client -z (local mode), Test
# Kitchen and InSpec all run here with no server or account.
if ! grep -q '^# --- Chef server (install-chef' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Chef server (install-chef) ------------------------------------------------------------------------
# Optional. Only for a Chef Infra Server or Cinc Server you already use: dev-init writes knife's default profile
# (credentials, in Cinc's knife folder) from these three, once, and never replaces a profile that is there.
# The server's URL with the organization, e.g. https://chef.example.com/organizations/myorg
#KNIFE_CHEF_SERVER_URL=""
# Your user (client) name on that server
#KNIFE_NODE_NAME=""
# The path to your user's private key (.pem), downloaded from the server when the user or key was made
#KNIFE_CLIENT_KEY=""
# Puppet (install-puppet) needs nothing here: OpenVox runs masterless (puppet apply, Bolt).
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a Chef server section to $SECRETS (v91); optional."
fi

# v93: the laptop network over Tailscale. Appended when missing (an existing laptop-network section keeps
# its v84 text; these lines add to it).
if ! grep -q '^# --- Laptop network over Tailscale (install-lan' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Laptop network over Tailscale (install-lan, v93) ----------------------------------------------
# Linux on these Chromebooks runs as a full VM with no ChromeOS port forwarding, so the laptops reach each
# other over Tailscale: dev-setup installs it (normal mode, tailscale0), dev-init joins this laptop to your
# tailnet as MACHINE_LABEL (or LAN_SELF), interactively unless TAILSCALE_AUTHKEY is set. LAN_HOSTS above then
# holds the 100.x addresses 'tailscale status' lists (a laptop not on Tailscale, such as a Windows one, keeps
# its home address), and LAN_SHARE is published with 'tailscale serve', to your tailnet only. No ChromeOS
# port forwards. Ollama on another laptop: http://NAME.internal:11434 (a plain NAME gets 403 from Ollama).
# 0 keeps the v84 way instead (the relay and ChromeOS port forwards) and installs no Tailscale.
#LAN_TAILSCALE=1
# An auth key from the Tailscale admin console (Settings > Keys), for joining without a browser; one-off
# keys are fine. Not needed once joined. In the admin console, turn off key expiry for each laptop.
#TAILSCALE_AUTHKEY=""
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a Tailscale part to the laptop-network settings in $SECRETS (v93); optional."
fi

# v93: the retro disk sizes, read by the retro commands when a disk is created (never before).
if ! grep -q '^# --- Retro guests (install-retro' "$SECRETS"; then
    cat << 'EOF' >> "$SECRETS"

# --- Retro guests (install-retro) -----------------------------------------------------------------
# Optional. Not exported: the retro commands read them when they create a disk, and never resize one that
# exists ('<guest> exchange recreate' rebuilds the exchange disk; 'retro sizes' shows what is in effect).
# The same name on the command line wins for one run:  RETRO_EXCHANGE_MB=512 win2000 setup
# The exchange disk (D: in win95, winnt40, win2000; FAT16, 64-2047 MB; default 1024, v92 made 512):
#RETRO_EXCHANGE_MB=1024
# Windows 95's hdd.img (FAT32, 512-8192 MB; default 2048, v92 made 1024):
#RETRO_WIN95_DISK_MB=2048
EOF
    [ "$NEW_SECRETS" = 1 ] || echo "Added a retro section to $SECRETS (v93); optional."
fi

if [ "$NEW_SECRETS" = 1 ]; then
    chmod 600 "$SECRETS"
    echo
    echo "================================================================="
    echo "Created the secrets template:  $SECRETS"
    echo "Fill in the keys you have (empty ones are skipped), then rerun:"
    echo "  $0 $*"
    echo "================================================================="
    exit 0
fi

chmod 600 "$SECRETS"
# v90: whether APOLLO_KEY was already in the environment before the secrets file is read (set -a below
# exports everything in it, for this script's own use).
APOLLO_KEY_INHERITED=$(printenv APOLLO_KEY 2> /dev/null || true)
# shellcheck disable=SC1090
set -a; . "$SECRETS"; set +a
# Derive GOOGLE_API_KEY from GEMINI_API_KEY so both SDK families see the same key.
[ -n "$GEMINI_API_KEY" ] && [ -z "$GOOGLE_API_KEY" ] && export GOOGLE_API_KEY="$GEMINI_API_KEY"

# =================================================================
# HELPERS
# =================================================================
if [ -t 1 ]; then GRN=$'\e[32m' YEL=$'\e[33m' DIM=$'\e[2m' RST=$'\e[0m'; else GRN=; YEL=; DIM=; RST=; fi
TODO=()
section() { echo; echo "== $* =="; }
ok()      { echo "  ${GRN}done${RST}  $*"; }
already() { echo "  ${DIM}ok${RST}    $* (already)"; }
skip()    { echo "  ${YEL}skip${RST}  $*"; }
todo()    { echo "  ${YEL}todo${RST}  $*"; TODO+=("$*"); }
# add a line to ~/.bashrc once, matched on a fixed substring
bashrc_once() { grep -qF -- "$1" ~/.bashrc || echo "$2" >> ~/.bashrc; }
# set a KEY=value line in a dotenv-style file (replace if present, append if not)
set_env_line() {  # file key value
    local f="$1" k="$2" v="$3"
    touch "$f"
    if grep -q "^${k}=" "$f"; then
        sed -i "s|^${k}=.*|${k}=${v}|" "$f"
    else
        echo "${k}=${v}" >> "$f"
    fi
}

# =================================================================
# BASE (always)
# =================================================================
section "Shell: source the secrets file from ~/.bashrc"
if grep -qF 'dev-init/secrets.env' ~/.bashrc; then
    already "~/.bashrc sources $SECRETS"
else
    printf '\n# dev-init: API keys and tokens\n[ -f "%s" ] && . "%s"\n' "$SECRETS" "$SECRETS" >> ~/.bashrc
    ok "~/.bashrc now sources $SECRETS"
fi

section "Git identity"
if [ -n "$GIT_NAME" ] && [ "$(git config --global user.name)" != "$GIT_NAME" ]; then
    git config --global user.name "$GIT_NAME"; ok "user.name = $GIT_NAME"
elif [ -n "$(git config --global user.name)" ]; then already "user.name = $(git config --global user.name)"
else todo "set GIT_NAME in $SECRETS (git config --global user.name)"; fi
if [ -n "$GIT_EMAIL" ] && [ "$(git config --global user.email)" != "$GIT_EMAIL" ]; then
    git config --global user.email "$GIT_EMAIL"; ok "user.email = $GIT_EMAIL"
elif [ -n "$(git config --global user.email)" ]; then already "user.email = $(git config --global user.email)"
else todo "set GIT_EMAIL in $SECRETS (git config --global user.email)"; fi
if [ -z "$(git config --global init.defaultBranch)" ]; then
    git config --global init.defaultBranch main; ok "init.defaultBranch = main"
else already "init.defaultBranch = $(git config --global init.defaultBranch)"; fi

section "GitHub CLI login + SSH key"
if gh auth status > /dev/null 2>&1; then
    already "gh is logged in as $(gh api user -q .login 2>/dev/null)"
elif [ -n "$GH_TOKEN_ONCE" ]; then
    if printf '%s' "$GH_TOKEN_ONCE" | gh auth login --with-token; then ok "gh logged in with token"; else todo "gh token login failed; check the token's scopes"; fi
elif [ "$INTERACTIVE" = 1 ]; then
    echo "  no GH_TOKEN_ONCE set; starting interactive 'gh auth login'..."
    gh auth login && ok "gh logged in" || todo "gh auth login"
else
    todo "gh auth login (no GH_TOKEN_ONCE and running noninteractive)"
fi
if gh auth status > /dev/null 2>&1; then
    # let git use gh's credentials for https remotes
    if git config --global --get-all credential.helper 2>/dev/null | grep -q 'gh auth git-credential'; then
        already "git credential helper = gh"
    else
        gh auth setup-git > /dev/null 2>&1 && ok "git credential helper = gh"
    fi
fi
# v92: the SSH key. GitHub itself is asked first (ssh -T, as the drupal.org check does), so a key added
# in the web UI counts as done; when port 22 does not answer (some networks block it), GitHub's SSH on port
# 443 (ssh.github.com) is tried. Only then gh: 'gh ssh-key list' and 'add' need the read:public_key /
# admin:public_key scope, which an interactive 'gh auth login' does not grant; v91 read that failure as
# "not uploaded" and reported a todo on every run. A missing scope now names its fix, and a GitHub that
# cannot be reached at all is a skip, not a todo.
if [ -f ~/.ssh/id_ed25519.pub ]; then
    gh_ssh() {   # gh_ssh [-p 443 ssh.github.com]: GitHub's answer to the key, or the connection error
        local host=git@github.com port=()
        [ "${1:-}" = 443 ] && { host=git@ssh.github.com; port=(-p 443); }
        timeout 25 ssh -T "${port[@]}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
            -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes "$host" < /dev/null 2>&1 || true
    }
    GH_SSH_OUT=$(gh_ssh)
    if ! echo "$GH_SSH_OUT" | grep -qi -e 'successfully authenticated' -e 'permission denied'; then
        GH_SSH_OUT=$(gh_ssh 443)
    fi
    GH_SSH_LINE=$(echo "$GH_SSH_OUT" | grep -v '^Warning: Permanently added' | head -n 1)
    if echo "$GH_SSH_OUT" | grep -qi 'successfully authenticated'; then
        already "SSH key ~/.ssh/id_ed25519.pub is on GitHub ($(echo "$GH_SSH_OUT" | sed -n 's/^Hi \([^!]*\)!.*/\1/p' | head -n 1))"
    else
        GH_SCOPE_OK=0
        if gh auth status > /dev/null 2>&1; then
            GH_SCOPES=$(gh auth status 2>&1 | sed -n "s/.*Token scopes: *//p" | head -n 1)
            # none/empty: a fine-grained token or GH_TOKEN; try it and let GitHub say no.
            case "$GH_SCOPES" in *public_key*|""|none|*none*) GH_SCOPE_OK=1 ;; esac
        fi
        KEY_PART=$(cut -d' ' -f2 ~/.ssh/id_ed25519.pub)
        if [ "$GH_SCOPE_OK" = 1 ] && gh ssh-key list 2> /dev/null | grep -qF "$KEY_PART"; then
            already "SSH key ~/.ssh/id_ed25519.pub is on GitHub (gh lists it; GitHub's SSH did not confirm it: ${GH_SSH_LINE:-no answer})"
        elif ! echo "$GH_SSH_OUT" | grep -qi 'permission denied'; then
            skip "GitHub's SSH did not answer on port 22 or 443 (${GH_SSH_LINE:-no answer}); rerun init online to check the key"
        elif [ "$GH_SCOPE_OK" = 1 ] && gh ssh-key add ~/.ssh/id_ed25519.pub --title "${MACHINE_LABEL:-$(hostname)}-$(date +%Y%m%d)" > /dev/null 2>&1; then
            ok "SSH key uploaded to GitHub"
        elif [ "$GH_SCOPE_OK" = 1 ]; then
            todo "add ~/.ssh/id_ed25519.pub to GitHub at https://github.com/settings/keys ('gh ssh-key add' was refused)"
        elif gh auth status > /dev/null 2>&1; then
            todo "add ~/.ssh/id_ed25519.pub to GitHub: at https://github.com/settings/keys, or 'gh auth refresh -h github.com -s admin:public_key' (gh's token lacks that scope) and rerun init"
        else
            todo "add ~/.ssh/id_ed25519.pub to GitHub at https://github.com/settings/keys (or log gh in and rerun init)"
        fi
    fi
fi

section "Docker"
if id -nG | grep -qw docker; then already "you are in the docker group in this shell"
elif getent group docker | grep -qw "$USER"; then todo "docker group not active in this shell: run 'newgrp docker' or log out/in"
else todo "add yourself to the docker group: sudo usermod -aG docker \$USER"; fi
# v69: GPU. Windowed OpenGL needs the render node, which is group 'render' (see dev-setup).
if id -nG | tr ' ' '\n' | grep -qx render; then already "render group active (GPU acceleration for windowed apps)"
elif getent group render | grep -qw "$USER"; then todo "render group not active yet: shut Linux down (right-click Terminal > Shut down Linux) and reopen it, for GPU acceleration"
elif getent group render > /dev/null; then todo "GPU: sudo usermod -aG video,render \$USER, then shut Linux down and reopen it"; fi

# =================================================================
# CONDITIONAL
# =================================================================
if has install-node; then
    section "Claude Code + Codex (install-node)"
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        already "ANTHROPIC_API_KEY exported (Claude Code will bill the API; unset it to use your subscription)"
    elif [ -s ~/.claude.json ] && grep -q '"oauthAccount"' ~/.claude.json 2>/dev/null; then
        already "Claude Code is logged in with a subscription"
    else
        todo "run 'claude' once and log in (subscription), or set ANTHROPIC_API_KEY in $SECRETS"
    fi
    if [ -n "$OPENAI_API_KEY" ]; then
        already "OPENAI_API_KEY exported (Codex will use the API)"
    elif [ -s ~/.codex/auth.json ]; then
        already "Codex is logged in"
    elif [ "$INTERACTIVE" = 1 ]; then
        echo "  starting 'codex login' (opens a browser link)..."
        codex login && ok "Codex logged in" || todo "codex login"
    else
        todo "codex login (or set OPENAI_API_KEY in $SECRETS)"
    fi
    # v58: Gemini CLI signs in with a Google account on first run (creds in ~/.gemini), or uses the key.
    if [ -n "$GEMINI_API_KEY" ]; then
        already "GEMINI_API_KEY exported (Gemini CLI and aider will use it)"
    elif [ -s ~/.gemini/oauth_creds.json ]; then
        already "Gemini CLI is signed in with a Google account"
    else
        todo "run 'gemini' once and sign in with Google, or set GEMINI_API_KEY in $SECRETS"
    fi
    # aider has no login of its own: it uses whichever provider key is exported, or local Ollama.
    if [ -n "$ANTHROPIC_API_KEY" ] || [ -n "$OPENAI_API_KEY" ] || [ -n "$GEMINI_API_KEY" ]; then
        already "aider has a provider key (ANTHROPIC / OPENAI / GEMINI_API_KEY)"
    else
        todo "aider: set one of ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY in $SECRETS, or run it locally: aider --model ollama_chat/gemma4:e2b-it-qat"
    fi
fi

if has install-ollama; then
    section "Ollama: service, containers, remote server, cloud keys (install-ollama)"
    # Ollama's installer registers a systemd unit; make sure it starts on boot so the hybrid
    # client (and the agentic stack's langchain-ollama) never has to be told 'ollama serve'.
    if systemctl is-enabled ollama > /dev/null 2>&1; then
        already "ollama systemd service enabled"
    elif systemctl list-unit-files 2>/dev/null | grep -q '^ollama.service'; then
        sudo systemctl enable --now ollama > /dev/null 2>&1 && ok "ollama service enabled + started" || todo "sudo systemctl enable --now ollama"
    else
        todo "no ollama systemd unit found; start it with 'ollama serve' (or rerun dev-setup with install-ollama)"
    fi
    # v80: whether Docker containers (DDEV's web container, for a Drupal AI site) can reach the server.
    # Opening it is setup's job (install-ollama-containers); init only reports, since it is a choice.
    if systemctl show ollama -p Environment --value 2> /dev/null | tr ' ' '\n' | grep -qx 'OLLAMA_HOST=0.0.0.0:11434'; then
        already "containers reach Ollama at http://host.docker.internal:11434 (install-ollama-containers)"
    elif has install-ollama-containers; then
        todo "install-ollama-containers is set but the service still listens on 127.0.0.1 only: rerun dev-setup with install-ollama-containers"
    else
        skip "containers cannot reach Ollama (127.0.0.1 only). For DDEV / a Drupal AI site: rerun dev-setup with install-ollama-containers"
    fi
    # OLLAMA_REMOTE: a machine that may simply be asleep, so an unanswered address is a 'skip' with the
    # likely causes, not a todo.
    if [ -n "${OLLAMA_REMOTE:-}" ]; then
        OR_URL=$OLLAMA_REMOTE
        case "$OR_URL" in http://*|https://*) ;; *) OR_URL="http://$OR_URL" ;; esac
        # v84: a bare name or address means Ollama's own default port, as the ollama CLI reads it
        OR_HP=${OR_URL#*://}; OR_HP=${OR_HP%%/*}
        case "$OR_HP" in *:*) ;; *) OR_URL="${OR_URL%%://*}://$OR_HP:11434" ;; esac
        if OR_VER=$(curl -fsS --max-time 10 "$OR_URL/api/version" 2> /dev/null); then
            already "OLLAMA_REMOTE answers: $OR_URL ($(echo "$OR_VER" | jq -r .version 2> /dev/null)); use it with 'ollama-remote list' / 'ollama-remote run <model>'"
        else
            skip "OLLAMA_REMOTE ($OR_URL) is not answering right now: is that machine awake and sharing Ollama (a Chromebook: LAN_SHARE=ollama there, over Tailscale, with OLLAMA_REMOTE=NAME.internal or its 100.x address, as Ollama answers a plain laptop name with 403; Windows: OLLAMA_HOST=0.0.0.0:11434 and its firewall open)?"
        fi
    else
        skip "no remote Ollama (optional: OLLAMA_REMOTE in $SECRETS, for a bigger machine's models; with install-lan a laptop's name works, e.g. winlaptop)"
    fi
    if [ -n "${OLLAMA_API_KEY:-}" ]; then
        already "OLLAMA_API_KEY exported (direct calls to https://ollama.com/api with a Bearer header)"
    else
        skip "no OLLAMA_API_KEY (optional: only for calling ollama.com's cloud API directly)"
    fi
    # The local CLI reaches :cloud models once this machine's Ollama key is linked to an account.
    # That link is made in a browser, so init only points at it.
    skip "cloud models through the local CLI (optional, pay per token, e.g. deepseek-v4.1-flash:cloud): run 'ollama signin' once, then 'ollama run <model>:cloud'"
    if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
        if curl -fsS --max-time 15 -H "Authorization: Bearer $DEEPSEEK_API_KEY" https://api.deepseek.com/models > /dev/null 2>&1; then
            already "DEEPSEEK_API_KEY works (aider --model deepseek/deepseek-chat)"
        else
            todo "DEEPSEEK_API_KEY in $SECRETS was rejected by api.deepseek.com (or it is unreachable): check the key"
        fi
    else
        skip "no DEEPSEEK_API_KEY (optional: DeepSeek's own API, for aider or langchain-deepseek)"
    fi
fi

if has install-models; then
    section "Local models (install-models)"
    already "local models need no account; 'ollama list' shows them, and assets/ollama-models.txt holds the curated list"
fi

if has install-gemma; then
    section "Gemma + Gemini (install-gemma)"
    # v77: the Ollama service step is in the install-ollama section above (this flag pulls it in).
    if [ -n "$GEMINI_API_KEY" ]; then already "GEMINI_API_KEY exported (gemma_client.py routes to Gemini when online)"
    else todo "set GEMINI_API_KEY in $SECRETS for the cloud route (local Ollama works without it)"; fi
    if ~/.gemma-env/bin/hf auth whoami > /dev/null 2>&1; then
        already "Hugging Face logged in as $(~/.gemma-env/bin/hf auth whoami 2>/dev/null | sed -n 's/.*user: *//p' | head -1)"
    elif [ -n "$HF_TOKEN" ]; then
        ~/.gemma-env/bin/hf auth login --token "$HF_TOKEN" > /dev/null 2>&1 && ok "Hugging Face logged in" || todo "hf auth login failed; check HF_TOKEN"
    elif [ "$INTERACTIVE" = 1 ]; then
        ~/.gemma-env/bin/hf auth login && ok "Hugging Face logged in" || todo "hf auth login"
    else
        todo "hf auth login (or set HF_TOKEN in $SECRETS)"
    fi
fi

if has install-agentic; then
    section "Agentic stack: ~/agentic/.env (install-agentic)"
    ENV_FILE="$HOME/agentic/.env"
    if [ ! -f "$ENV_FILE" ] && [ -f "$HOME/agentic/.env.example" ]; then
        cp "$HOME/agentic/.env.example" "$ENV_FILE"; ok "created ~/agentic/.env from .env.example"
    fi
    if [ -f "$ENV_FILE" ]; then
        chmod 600 "$ENV_FILE"
        FILLED=0
        for k in LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY LANGFUSE_BASE_URL ANTHROPIC_API_KEY GOOGLE_API_KEY; do
            v="${!k}"
            [ -n "$v" ] && { set_env_line "$ENV_FILE" "$k" "$v"; FILLED=$((FILLED + 1)); }
        done
        # keep the legacy LANGFUSE_HOST in step with LANGFUSE_BASE_URL
        [ -n "$LANGFUSE_BASE_URL" ] && set_env_line "$ENV_FILE" "LANGFUSE_HOST" "$LANGFUSE_BASE_URL"
        ok "wrote $FILLED key(s) into ~/agentic/.env"
        grep -q '^LANGFUSE_SECRET_KEY=sk-lf-' "$ENV_FILE" || todo "add Langfuse project keys to $SECRETS (cloud.langfuse.com -> project settings -> API keys)"
    else
        todo "~/agentic/.env.example missing; rerun the installer with install-agentic"
    fi
fi

if has install-mobile || has install-tauri || has install-rn || has install-flutter || has install-android-native; then
    section "Android (mobile base)"
    # v56: connect to the Android runtime explicitly; the first connect triggers an
    # "Allow USB debugging?" dialog on the ChromeOS side that must be accepted once.
    adb connect arc > /dev/null 2>&1 || adb connect 100.115.92.2:5555 > /dev/null 2>&1
    if adb devices 2>/dev/null | tail -n +2 | grep -qE '\bdevice$'; then
        already "adb sees the Chromebook's Android runtime"
    elif adb devices 2>/dev/null | grep -q unauthorized; then
        todo "accept the 'Allow USB debugging?' dialog on the ChromeOS screen (tick 'Always allow'), then rerun"
    else
        todo "enable ADB debugging: ChromeOS Settings -> About ChromeOS -> Linux development environment -> Develop Android apps (needs a restart), then rerun"
    fi
    if has install-mobile || has install-flutter; then
        flutter config --no-analytics > /dev/null 2>&1 && ok "flutter analytics disabled"
        yes 2>/dev/null | flutter doctor --android-licenses > /dev/null 2>&1 && ok "flutter: Android licenses accepted"
    fi
    if has install-mobile || has install-rn; then
        if eas whoami > /dev/null 2>&1; then
            already "EAS logged in as $(eas whoami 2>/dev/null | tail -1)"
        elif [ -n "$EXPO_TOKEN" ]; then
            already "EXPO_TOKEN exported (eas uses it directly)"
        elif [ "$INTERACTIVE" = 1 ]; then
            eas login && ok "EAS logged in" || todo "eas login"
        else
            todo "eas login (or set EXPO_TOKEN in $SECRETS)"
        fi
    fi
    if has install-android-native; then
        if [ -d ~/.config/Google ] && ls -d ~/.config/Google/AndroidStudio* > /dev/null 2>&1; then
            already "Android Studio has been launched before"
        else
            todo "launch Android Studio once (/opt/android-studio/bin/studio.sh) to finish its first-run wizard; point it at \$ANDROID_HOME ($ANDROID_HOME)"
        fi
    fi
fi

if has install-antigravity; then
    section "Google Antigravity (install-antigravity)"
    if [ -x ~/.local/bin/agy ]; then
        already "agy CLI installed ($(agy --version 2>/dev/null | head -1)); 'agy --help' shows its login command"
    else
        todo "agy CLI missing from ~/.local/bin; rerun the installer with install-antigravity"
    fi
    # v81: the graphical app lives under /opt since setup v73 (installed from a tarball you put in ./assets).
    # Signing in is a Google account flow inside the app on first launch, so there is nothing to do here.
    AG_APPS=""
    [ -x /opt/antigravity-ide/current/antigravity-ide ] && AG_APPS="antigravity-ide"
    [ -x /opt/antigravity/current/antigravity ] && AG_APPS="${AG_APPS:+$AG_APPS, }antigravity"
    if [ -n "$AG_APPS" ]; then
        skip "Antigravity ($AG_APPS) signs in with your Google account on first launch: open it from the ChromeOS launcher"
    else
        skip "no Antigravity IDE or desktop app installed (optional: put its Linux tarball in the bundle's ./assets and rerun dev-setup with install-antigravity)"
    fi
fi

if has install-lakehouse; then
    section "Lakehouse (install-lakehouse)"
    already "nothing to initialize; 'dbt init' per project, no accounts needed"
    already "Delta Lake tables on disk need no account; one in S3, Azure or GCS reads with a DuckDB secret (CREATE SECRET ... TYPE s3 / azure / gcs) from the cloud logins above"
fi

if has install-db; then
    section "Databases: ODBC drivers, Firebird (install-db)"
    already "ODBC drivers and client libraries need no accounts; connection strings are per project"
    # v80: embedded Firebird has no server and no password check: programs connect as SYSDBA (ISC_USER).
    if grep -q '^export FIREBIRD_LOCK=' ~/.bashrc 2> /dev/null; then
        # v81: the line holds a literal $HOME; show the real path.
        FB_LOCK_DIR=$(sed -n 's/^export FIREBIRD_LOCK=//p' ~/.bashrc | tail -n 1 | tr -d '"')
        FB_LOCK_DIR=${FB_LOCK_DIR/#\$HOME/$HOME}
        already "Firebird embedded uses your own lock directory ($FB_LOCK_DIR)"
    elif command -v isql-fb > /dev/null 2>&1; then
        already "Firebird embedded needs no account: ISC_USER=SYSDBA isql-fb opens any .fdb file you can write; no password is checked without a server"
    else
        todo "isql-fb not found: rerun dev-setup with install-db (v80 adds Firebird)"
    fi
fi

if has install-interbase; then
    section "InterBase (install-interbase)"
    IB_HOME=/opt/interbase
    ib_up() { (exec 3<> /dev/tcp/127.0.0.1/3050) 2> /dev/null; }
    if [ ! -x "$IB_HOME/bin/isql" ]; then
        skip "InterBase is not installed: put the download from Embarcadero (zip or ib_install_linux_x86_64.bin) in the bundle's ./assets and rerun dev-setup with install-interbase"
    else
        # v92: through setup's ib-server (one start, stuck processes stopped first, a 20 s wait, its log on
        # failure, nothing left spinning); without it (setup older than v92) the same steps inline.
        IB_SRV="$HOME/.local/bin/ib-server"
        # v93: the installer leaves ibmgr root-only (-rwxr--r--); v92's ib-server then said "not installed"
        # and init asked to register an InterBase that was registered. Give it the execute bit for everyone.
        if [ ! -x "$IB_HOME/bin/ibmgr" ] && sudo test -x "$IB_HOME/bin/ibmgr" 2> /dev/null; then
            sudo chmod a+rx "$IB_HOME/bin/ibmgr" && ok "made $IB_HOME/bin/ibmgr executable for you (the installer leaves it root-only)"
        fi
        ib_start() {
            if [ -x "$IB_SRV" ]; then "$IB_SRV" start | sed 's/^/        /'; return "${PIPESTATUS[0]}"; fi
            local i
            sudo pkill -x ibguard 2> /dev/null; sudo pkill -x ibserver 2> /dev/null; sleep 2
            sudo env INTERBASE="$IB_HOME" "$IB_HOME/bin/ibmgr" -start -forever > /dev/null 2>&1 < /dev/null || true
            for ((i = 0; i < 20; i++)); do ib_up && return 0; sleep 1; done
            sudo tail -n 8 "$IB_HOME/interbase.log" 2> /dev/null | sed 's/^/        | /'
            sudo pkill -x ibguard 2> /dev/null; sudo pkill -x ibserver 2> /dev/null
            return 1
        }
        if ib_up; then
            already "InterBase server is running (port 3050)"
        else
            # An unregistered Developer Edition refuses to start. Registration is Embarcadero's own console
            # flow: it asks for the serial number from the download email and your Embarcadero login.
            # v92: the keystrokes first (on Oct 2 the serial went in at the main menu prompt by mistake).
            if [ "$INTERACTIVE" = 1 ] && [ -x "$IB_HOME/bin/LicenseManagerLauncher" ]; then
                echo "  InterBase's License Manager, in console mode. At its menus type:"
                echo "      2  (Direct register)  ->  the serial number from the download email  ->  Y"
                echo "      ->  your Embarcadero login and password"
                echo "      then 4 (Save) and 5 (Exit). Afterwards option 1 lists what is licensed: the Server product should be there."
                sudo env INTERBASE="$IB_HOME" "$IB_HOME/bin/LicenseManagerLauncher" -i Console || true
            fi
            if ib_start; then
                ok "InterBase server started (port 3050). It does not start with Linux by itself: 'ib-server start' (or rerun init) after a restart"
                skip "to confirm the license: sudo $IB_HOME/bin/LicenseManagerLauncher -i Console, option 1 (the Server product should show as licensed)"
            elif [ "$INTERACTIVE" = 1 ]; then
                todo "InterBase server did not start (output above): register it (sudo $IB_HOME/bin/LicenseManagerLauncher -i Console: 2, serial, Y, login, 4, 5), then 'ib-server start'"
            else
                todo "register InterBase (interactive): sudo $IB_HOME/bin/LicenseManagerLauncher -i Console (2, serial, Y, Embarcadero login, 4 Save, 5 Exit), then 'ib-server start'"
            fi
        fi
        if [ "${INTERBASE_SYSDBA_PASSWORD:-masterkey}" = masterkey ]; then
            skip "SYSDBA still has the documented default password (fine for the local-only Developer Edition). To change it: $IB_HOME/bin/gsec -user SYSDBA -password masterkey -modify SYSDBA -pw <new>, then set INTERBASE_SYSDBA_PASSWORD in $SECRETS"
        else
            already "INTERBASE_SYSDBA_PASSWORD is set (dev-test and dev-demo log in with it)"
        fi
    fi
fi

# v82: SQL Server and Oracle in Docker (install-db-server). There is no account to log in to: the
# containers carry their own passwords. Init reports what setup created, where each password comes
# from, and whether a password in secrets.env still matches the one the container was created with.
# It never starts a database (each holds ~2 GB of RAM).
if has install-mssql || has install-oracle; then
    section "Database servers in Docker (install-mssql / install-oracle)"
    DEVDB_DOCKER=(docker); docker info > /dev/null 2>&1 || DEVDB_DOCKER=(sudo -n docker)
    for DB_E in mssql oracle; do
        has "install-$DB_E" || continue
        DB_C="devdb-$DB_E"
        case "$DB_E" in
            mssql)  DB_PWVAR=MSSQL_SA_PASSWORD; DB_NAME="SQL Server 2025 ($DB_C, 127.0.0.1:1433, login sa)" ;;
            oracle) DB_PWVAR=ORACLE_PWD;        DB_NAME="Oracle 26ai Free ($DB_C, 127.0.0.1:1521/FREEPDB1, login system)" ;;
        esac
        if ! "${DEVDB_DOCKER[@]}" container inspect "$DB_C" > /dev/null 2>&1; then
            # v92: setup records why it skipped an engine (~/.config/devdb/<engine>.skipped); quote it.
            DB_WHY=$(cat "$HOME/.config/devdb/$DB_E.skipped" 2> /dev/null || true)
            case "$DB_WHY" in
                disk:*) todo "no $DB_C container: ${DB_WHY#disk: }. Rerun: DEV_DB_MIN_FREE_GB=<n> ./dev-setup-chromebook.sh install-$DB_E, then the test" ;;
                pull:*) todo "no $DB_C container: ${DB_WHY#pull: }. Rerun: ./dev-setup-chromebook.sh install-$DB_E" ;;
                *)      todo "no $DB_C container: rerun ./dev-setup-chromebook.sh install-$DB_E (or install-db-server); its log says why it skipped (disk space, network)" ;;
            esac
            continue
        fi
        DB_STATE=$("${DEVDB_DOCKER[@]}" inspect -f '{{.State.Status}}' "$DB_C" 2> /dev/null)
        if [ "$DB_E" = oracle ]; then
            # v83: which image it runs (install-oracle-full); a devdb-oracle made by v82 has no label: Lite
            DB_VARIANT=$("${DEVDB_DOCKER[@]}" inspect -f '{{index .Config.Labels "dev-setup.oracle-variant"}}' "$DB_C" 2> /dev/null)
            [ "$DB_VARIANT" = full ] || DB_VARIANT=Lite
            DB_NAME="Oracle 26ai Free, $DB_VARIANT image ($DB_C, 127.0.0.1:1521/FREEPDB1, login system)"
            if has install-oracle-full && [ "$DB_VARIANT" != full ]; then
                DB_WHY=$(cat "$HOME/.config/devdb/oracle.skipped" 2> /dev/null || true)
                todo "$DB_C still runs the Lite image: ${DB_WHY:-most often disk space, as the full image needs about 13 GB}. Rerun: ./dev-setup-chromebook.sh install-oracle-full"
            fi
        fi
        DB_CREATED_PW=$("${DEVDB_DOCKER[@]}" inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$DB_C" 2> /dev/null | sed -n "s/^$DB_PWVAR=//p" | head -n 1)
        if [ -z "${!DB_PWVAR:-}" ]; then
            already "$DB_NAME is $DB_STATE; its password was generated by setup ('$DB_E password' prints it)"
        elif [ "${!DB_PWVAR}" = "$DB_CREATED_PW" ]; then
            already "$DB_NAME is $DB_STATE; its password is $DB_PWVAR from secrets.env"
        else
            skip "$DB_PWVAR in secrets.env is not the password $DB_C was created with. Fine if you changed it inside the database; if you did not, comment the line out and '$DB_E' uses the container's"
        fi
    done
    already "each engine holds ~2 GB while it runs, so setup leaves them stopped: 'mssql up' / 'oracle up' (one at a time), 'mssql down' / 'oracle down'"
fi

# v83: LDAP (install-ldap / install-ldap-full). Nothing to log in to: init reports each directory and
# whether a value in secrets.env still matches what the directories were created with (ldap.env).
# It starts nothing: lldap runs all the time, and slapd is a service that starts with Linux.
if has install-ldap; then
    section "LDAP directories (install-ldap / install-ldap-full)"
    LDAP_ENVF="$HOME/.config/devldap/ldap.env"
    if [ ! -f "$LDAP_ENVF" ]; then
        todo "no ~/.config/devldap/ldap.env: rerun dev-setup with install-ldap$(has install-ldap-full && echo ' install-ldap-full')"
    else
        ldap_mine() { bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$LDAP_ENVF" "$1"; }
        LDAP_BASE=$(ldap_mine LDAP_BASE_DN)
        LDAP_DOCKER=(docker); docker info > /dev/null 2>&1 || LDAP_DOCKER=(sudo -n docker)
        LL_STATE=$("${LDAP_DOCKER[@]}" inspect -f '{{.State.Status}}' devldap-lldap 2> /dev/null)
        if [ -z "$LL_STATE" ]; then
            todo "no devldap-lldap container: rerun dev-setup with install-ldap (its log says why: network, or Docker)"
        elif [ "$LL_STATE" = running ]; then
            already "lldap is running: ldap://127.0.0.1:3890, web UI http://localhost:17170, base DN $LDAP_BASE"
        else
            skip "lldap is $LL_STATE: 'ldap up' starts it (and it then starts with Linux again)"
        fi
        if has install-ldap-full; then
            if systemctl is-active --quiet slapd 2> /dev/null; then
                already "OpenLDAP (slapd) is running: ldap://127.0.0.1:389, admin cn=admin,$LDAP_BASE"
            elif dpkg -s slapd > /dev/null 2>&1; then
                todo "slapd is installed but not running: sudo systemctl enable --now slapd ('journalctl -u slapd' says why it stopped)"
            else
                todo "slapd is not installed: rerun dev-setup with install-ldap-full (its log says why)"
            fi
        fi
        for LDAP_K in LDAP_BASE_DN LLDAP_ADMIN_PASSWORD OPENLDAP_ADMIN_PASSWORD LDAP_BIND_PASSWORD LDAP_SAMPLE_PASSWORD; do
            if [ -n "${!LDAP_K:-}" ] && [ "${!LDAP_K}" != "$(ldap_mine "$LDAP_K")" ]; then
                skip "$LDAP_K in secrets.env is not what the directories were created with (~/.config/devldap/ldap.env), and setup keeps ldap.env's. To start over with yours, see the install-ldap notes in dev-setup"
            fi
        done
        already "nothing to log in to: 'ldap status' shows the directories, 'ldap passwords' the passwords, 'ldap drupal' the values for Drupal"
    fi
fi

# v89: the shared services (install-cache, install-search, install-elasticsearch). Nothing to log in to:
# init reports each service, where its values are kept, and whether secrets.env asks for something setup
# has not applied yet. It starts nothing: DEVSVC_AUTOSTART services start with Linux, the rest on 'devsvc up'.
SVC_INIT=""
for SVC in redis memcached solr opensearch elasticsearch meilisearch typesense qdrant milvus mongodb selenium; do has "install-$SVC" && SVC_INIT+=" $SVC"; done
has install-mongodb-atlas-local && SVC_INIT+=" atlas-local"
if [ -n "$SVC_INIT" ]; then
    section "Shared services (devsvc):$SVC_INIT"
    if ! command -v devsvc > /dev/null 2>&1; then
        todo "the devsvc command is missing: rerun dev-setup with install-cache"
    else
        SVC_DOCKER=(docker); docker info > /dev/null 2>&1 || SVC_DOCKER=(sudo -n docker)
        SVC_AUTO=$(echo "${DEVSVC_AUTOSTART:-redis memcached}" | tr ',;' '  ')
        for SVC in $SVC_INIT; do
            SVC_STATE=$("${SVC_DOCKER[@]}" inspect -f '{{.State.Status}} {{.HostConfig.RestartPolicy.Name}}' "devsvc-$SVC" 2> /dev/null)
            SVC_WANT=no; [[ " $SVC_AUTO " == *" $SVC "* ]] && SVC_WANT=unless-stopped
            SVC_FLAG=install-$SVC; [ "$SVC" = atlas-local ] && SVC_FLAG=install-mongodb-atlas-local
            if [ -z "$SVC_STATE" ]; then
                todo "no devsvc-$SVC container: rerun dev-setup with $SVC_FLAG (its log says why: network, or Docker)"
            elif [ "${SVC_STATE#* }" != "$SVC_WANT" ]; then
                skip "devsvc-$SVC: DEVSVC_AUTOSTART changed since setup ran ($( [ "$SVC_WANT" = no ] && echo "no longer starts with Linux" || echo "should start with Linux")); rerun dev-setup with $SVC_FLAG to apply it"
            elif [ "${SVC_STATE%% *}" = running ]; then
                already "$SVC is running: 'devsvc info $SVC' shows how to connect"
            else
                skip "$SVC is stopped: 'devsvc up $SVC' starts it (not needed until you use it)"
            fi
        done
        if has install-redis; then
            SVC_RPW=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${REDIS_PASSWORD:-}"' _ "$HOME/.config/devsvc/devsvc.env" 2> /dev/null)
            if [ "${REDIS_PASSWORD:-}" != "$SVC_RPW" ]; then
                skip "REDIS_PASSWORD in secrets.env differs from what Redis runs with: rerun dev-setup with install-redis to apply it"
            elif [ -z "$SVC_RPW" ]; then
                skip "Redis has no password (fine on 127.0.0.1; optional): set REDIS_PASSWORD in secrets.env before sharing Redis with your other laptops"
            else
                already "Redis requires REDIS_PASSWORD (kept in ~/.config/devsvc/devsvc.env; 'devsvc password redis')"
            fi
        fi
        # Qdrant's and MongoDB's logins are live, like Redis's: secrets.env decides on the next setup run.
        for SVC_KV in qdrant:QDRANT_API_KEY mongodb:MONGO_ROOT_PASSWORD; do
            SVC=${SVC_KV%%:*}; SVC_K=${SVC_KV#*:}
            has "install-$SVC" || continue
            SVC_HAVE=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$HOME/.config/devsvc/devsvc.env" "$SVC_K" 2> /dev/null)
            if [ "${!SVC_K:-}" != "$SVC_HAVE" ]; then
                skip "$SVC_K in secrets.env differs from what $SVC runs with: rerun dev-setup with install-$SVC to apply it"
            elif [ -z "$SVC_HAVE" ]; then
                skip "$SVC has no login (fine on 127.0.0.1; optional): set $SVC_K in secrets.env before sharing it with your other laptops"
            fi
        done
        if has install-vector; then
            if [ -f "$HOME/.local/lib/sqlite-vec/vec0.so" ]; then
                SVC_V=$(cat "$HOME/.local/lib/sqlite-vec/VERSION" 2> /dev/null || true)
                already "sqlite-vec${SVC_V:+ $SVC_V} for sqlite3: .load ~/.local/lib/sqlite-vec/vec0"
            else
                todo "sqlite-vec is missing: rerun dev-setup with install-vector (its log says why)"
            fi
        fi
        if has install-mongodb-atlas-local; then
            if ! command -v atlas > /dev/null 2>&1; then
                skip "the Atlas CLI is missing (optional; Atlas Local works without it): rerun dev-setup with install-mongodb-atlas-local"
            elif [ -z "${MONGODB_ATLAS_PUBLIC_API_KEY:-}" ] || [ -z "${MONGODB_ATLAS_PRIVATE_API_KEY:-}" ]; then
                skip "no Atlas account for the Atlas CLI (optional): MONGODB_ATLAS_PUBLIC_API_KEY / _PRIVATE_API_KEY in secrets.env, or 'atlas auth login'"
            elif timeout 60 atlas projects list -o json < /dev/null > /dev/null 2>&1; then
                already "the Atlas CLI reaches your Atlas organization with the API key from secrets.env"
            else
                todo "Atlas rejects MONGODB_ATLAS_PUBLIC_API_KEY / _PRIVATE_API_KEY (or its access list excludes this address): 'atlas projects list' shows why"
            fi
        fi
        # The search engines' kept logins: a value in secrets.env that differs from devsvc.env is not used.
        for SVC_KV in solr:SOLR_PASSWORD opensearch:OPENSEARCH_ADMIN_PASSWORD elasticsearch:ELASTIC_PASSWORD \
                      meilisearch:MEILI_MASTER_KEY typesense:TYPESENSE_API_KEY; do
            SVC=${SVC_KV%%:*}; SVC_K=${SVC_KV#*:}
            has "install-$SVC" || continue
            SVC_HAVE=$(bash -c '. "$1" > /dev/null 2>&1; printf %s "${!2:-}"' _ "$HOME/.config/devsvc/devsvc.env" "$SVC_K" 2> /dev/null)
            if [ -z "$SVC_HAVE" ]; then
                todo "no $SVC_K in ~/.config/devsvc/devsvc.env: rerun dev-setup with install-$SVC"
            elif [ -n "${!SVC_K:-}" ] && [ "${!SVC_K}" != "$SVC_HAVE" ]; then
                skip "$SVC_K in secrets.env is not the one $SVC was created with (devsvc.env wins). To use yours, start $SVC over: see the shared-services notes in dev-setup"
            fi
        done
        already "nothing to log in to: 'devsvc status' shows the services, 'devsvc info NAME' how to connect, 'devsvc password NAME' the logins"
    fi
fi

# v84: the laptop network (install-lan / install-lan-share). The address book and what this machine
# shares live in secrets.env, so init is where they are applied: /etc/hosts and the relay's config.
# The one manual step, a ChromeOS port forward per shared port, cannot be seen from inside Linux. A
# relayed port counts as done once the relay has had a connection from another laptop through it
# (running 'lan scan' on another laptop is enough); until then it stays on the to-do list.
if has install-lan; then
    # v93: Tailscale first: the address book holds its 100.x addresses and sharing publishes through it.
    if [ "${LAN_TAILSCALE:-1}" != 0 ]; then
        section "Laptop network: Tailscale (install-lan)"
        TS_NAME="${LAN_SELF:-${MACHINE_LABEL:-}}"
        if ! command -v tailscale > /dev/null 2>&1; then
            todo "Tailscale is not installed: rerun dev-setup with install-lan (v93), or set LAN_TAILSCALE=0 in $SECRETS for the v84 relay"
        else
            ts_state() { timeout 10 tailscale status --json 2> /dev/null | jq -r '.BackendState // "unknown"' 2> /dev/null || echo unknown; }
            grep -q '^FLAGS=.*--tun=tailscale0' /etc/default/tailscaled 2> /dev/null \
                || todo "Tailscale is not in normal mode: rerun dev-setup with install-lan (it sets FLAGS=\"--tun=tailscale0\" in /etc/default/tailscaled)"
            TS_STATE=$(ts_state)
            if [ "$TS_STATE" = Running ]; then
                already "Tailscale is connected: $(tailscale ip -4 2> /dev/null | head -n 1) as $(tailscale status --json 2> /dev/null | jq -r '.Self.HostName // "?"')"
            elif [ -z "$TS_NAME" ]; then
                todo "set MACHINE_LABEL (or LAN_SELF) in $SECRETS to this laptop's name, then rerun init: it joins Tailscale under that name"
            elif [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
                # The key reaches tailscale through a file, never the command line ('ps' shows a command line).
                TS_KEYFILE=$(mktemp); printf '%s' "$TAILSCALE_AUTHKEY" > "$TS_KEYFILE"
                if sudo tailscale up --auth-key="file:$TS_KEYFILE" --hostname="$TS_NAME" --operator="$USER" > /dev/null 2>&1; then
                    ok "joined your tailnet as $TS_NAME with TAILSCALE_AUTHKEY ($(tailscale ip -4 2> /dev/null | head -n 1))"
                else
                    todo "TAILSCALE_AUTHKEY did not join (expired or used up?): make a new key, or remove it and rerun init to log in with the browser"
                fi
                rm -f "$TS_KEYFILE"
            elif [ "$INTERACTIVE" = 1 ]; then
                echo "  Joining Tailscale as $TS_NAME: open the link it prints, log in, then come back here."
                if sudo tailscale up --hostname="$TS_NAME" --operator="$USER"; then
                    ok "joined your tailnet as $TS_NAME ($(tailscale ip -4 2> /dev/null | head -n 1))"
                else
                    todo "join Tailscale: sudo tailscale up --hostname=$TS_NAME --operator=\$USER"
                fi
            else
                todo "join Tailscale (interactive, a browser login): sudo tailscale up --hostname=$TS_NAME --operator=\$USER (or TAILSCALE_AUTHKEY in $SECRETS)"
            fi
            # Operator: 'lan share apply' changes 'tailscale serve' as you, without sudo.
            if [ "$(ts_state)" = Running ] && ! timeout 10 tailscale serve status > /dev/null 2>&1; then
                sudo tailscale set --operator="$USER" > /dev/null 2>&1 && ok "you are Tailscale's operator now (tailscale serve without sudo)"
            fi
            if [ "$(ts_state)" = Running ]; then
                skip "in the Tailscale admin console, turn off key expiry for ${TS_NAME:-this laptop} (Machines > ... > Disable key expiry), or it drops off the tailnet in 180 days"
                TS_MY_IP=$(tailscale ip -4 2> /dev/null | head -n 1)
                if [ -n "$TS_NAME" ] && [ -n "$TS_MY_IP" ] && ! echo "${LAN_HOSTS:-}" | tr ',; ' '\n\n\n' | grep -qx "$TS_NAME=$TS_MY_IP"; then
                    todo "put $TS_NAME=$TS_MY_IP in LAN_HOSTS (in $SECRETS on every laptop): it is this laptop's Tailscale address"
                fi
            fi
        fi
    fi
    section "Laptop network: address book (install-lan)"
    if ! command -v lan > /dev/null 2>&1; then
        todo "the 'lan' command is missing: rerun dev-setup with install-lan"
    elif [ -z "$(echo "${LAN_HOSTS:-}" | tr -d ' ,;')" ]; then
        skip "no address book yet (optional): LAN_HOSTS in $SECRETS, every laptop as name=address, the same list on each"
    else
        LAN_BAD=$(lan hosts 2>&1 > /dev/null | sed -n 's/^.*skipped (want name=address): *//p')
        [ -z "$LAN_BAD" ] || todo "fix these LAN_HOSTS entries in $SECRETS (want name=address, e.g. joxer=192.168.1.23): $LAN_BAD"
        if lan hosts check; then
            already "/etc/hosts has the address book: $(echo "$LAN_HOSTS" | tr ',;' '  ' | xargs -n1 | cut -d= -f1 | xargs)"
        elif lan hosts apply > /dev/null; then
            ok "address book written to /etc/hosts: every tool takes the laptop names now"
        else
            todo "writing the address book into /etc/hosts failed: run 'lan hosts apply' to see why"
        fi
        LAN_ME="${LAN_SELF:-${MACHINE_LABEL:-}}"
        if [ -z "$LAN_ME" ]; then
            skip "this machine has no name: set MACHINE_LABEL (or LAN_SELF) in $SECRETS to its name in LAN_HOSTS"
        elif echo "$LAN_HOSTS" | tr ',; ' '\n\n\n' | grep -q "^$LAN_ME="; then
            already "this machine is '$LAN_ME' in the address book (127.0.0.1 from here; $LAN_ME.internal too)"
        else
            skip "this machine ('$LAN_ME') is not in LAN_HOSTS: add it with its address, so every laptop's list is the same"
        fi
        # Which laptops answer right now. One that is off or asleep is a 'skip', not a problem.
        while IFS= read -r LAN_LINE; do
            [ -n "$LAN_LINE" ] || continue
            case "$LAN_LINE" in
                *"nothing answering"*) skip "$(echo "$LAN_LINE" | awk '{ print $1 " (" $2 ")" }'): nothing answers right now (off, asleep, sharing nothing, not on your tailnet, or a Wi-Fi that keeps laptops apart)" ;;
                *) already "$(echo "$LAN_LINE" | awk '{ n = $1; ip = $2; $1 = ""; $2 = ""; sub(/^ +/, ""); print n " (" ip ") shares: " $0 }')" ;;
            esac
        done < <(lan scan --brief 2> /dev/null)
    fi
fi

if has install-lan-share && [ "${LAN_TAILSCALE:-1}" != 0 ] && command -v tailscale > /dev/null 2>&1; then
    # v93: over Tailscale. 'lan share apply' publishes LAN_SHARE with 'tailscale serve' and stops the relay;
    # no ChromeOS port forwards, so no todo per port. Other laptops check the services ('lan probe').
    section "Laptop network: sharing over Tailscale (install-lan-share)"
    if ! command -v lan > /dev/null 2>&1; then
        todo "the 'lan' command is missing: rerun dev-setup with install-lan-share"
    elif [ -z "$(echo "${LAN_SHARE:-}" | tr -d ' ,;')" ]; then
        lan share apply > /dev/null 2>&1 || true
        skip "sharing nothing (optional): LAN_SHARE in $SECRETS, from: ollama mssql oracle ldap ddev dev mcp redis solr opensearch elasticsearch meilisearch typesense qdrant mongodb"
    else
        LAN_OUT=$(lan share apply 2>&1); LAN_RC=$?
        if [ -f "$HOME/.config/dev-lan/sharing-off" ]; then
            skip "sharing is switched off ('lan share off' earlier): 'lan share on' publishes the ports again"
        elif [ "$LAN_RC" = 0 ]; then
            ok "$(echo "$LAN_OUT" | grep -m1 '^Sharing over Tailscale' || echo "shared over Tailscale")"
        else
            todo "'lan share apply' did not publish everything: $(echo "$LAN_OUT" | grep -v '^ ' | tail -n 1)"
        fi
        while IFS=$'\t' read -r LAN_P _ LAN_LABEL; do
            [ -n "$LAN_P" ] || continue
            case "$LAN_P" in
                11434) skip "port 11434 ($LAN_LABEL): other laptops use http://${LAN_SELF:-${MACHINE_LABEL:-NAME}}.internal:11434 (a plain name gets 403 from Ollama)" ;;
                8080|8443) [ "$LAN_P" = 8080 ] && skip "DDEV ($LAN_P/8443): DDEV routes by site name, so another laptop maps a site first: lan site ${LAN_SELF:-${MACHINE_LABEL:-NAME}} SITE" ;;
            esac
        done < <(lan share plan 2> /dev/null)
        while IFS= read -r LAN_NOTE; do
            case "$LAN_NOTE" in
                "") ;;
                *"not shared"*|*"never shared"*|*"unknown service"*|*ignoring*) todo "LAN_SHARE: ${LAN_NOTE#lan: }" ;;
                *) skip "${LAN_NOTE#lan: }" ;;
            esac
        done < <(lan share plan 2>&1 > /dev/null)
        case " $(echo "${LAN_SHARE:-}" | tr ',;' '  ') " in
            *" dev "*|*" mcp "*) skip "dev and mcp servers are not published by 'tailscale serve': start them with --host / 0.0.0.0 and the other laptops reach them on this laptop's Tailscale address ('lan share' shows whether they listen on the network)" ;;
        esac
        skip "only laptops on your tailnet reach these ports; 'lan probe ${LAN_SELF:-${MACHINE_LABEL:-NAME}}' on another laptop checks each service end to end"
    fi
fi

if has install-lan-share && { [ "${LAN_TAILSCALE:-1}" = 0 ] || ! command -v tailscale > /dev/null 2>&1; }; then
    section "Laptop network: sharing through the relay (install-lan-share)"
    if [ ! -f "$HOME/.local/lib/dev-lan/lan-relay.py" ] || ! command -v lan > /dev/null 2>&1; then
        todo "the relay is not installed: rerun dev-setup with install-lan-share"
    else
        # Its notes (the same lines 'lan share plan' prints) are reported once, further down.
        LAN_OUT=$(lan share apply 2>&1); LAN_RC=$?
        [ "$LAN_RC" = 0 ] || todo "'lan share apply' failed: $(echo "$LAN_OUT" | tail -n 1)"
        if ! systemctl is-enabled --quiet dev-lan-relay.service 2> /dev/null; then
            skip "sharing is switched off ('lan share off' earlier): 'lan share on' opens the ports again"
        elif systemctl is-active --quiet dev-lan-relay.service 2> /dev/null; then
            already "the relay is running on this Linux's address $(ip -4 -o addr show 2> /dev/null | awk '$2 !~ /^(lo|docker|br-|veth|virbr|cni|flannel|kube|tailscale|wg)/ { split($4, a, "/"); print a[1] }' | xargs)"
        else
            todo "the relay is not running: 'journalctl -u dev-lan-relay' says why, 'lan share on' starts it"
        fi
        if [ -z "$(echo "${LAN_SHARE:-}" | tr -d ' ,;')" ]; then
            skip "sharing nothing (optional): LAN_SHARE in $SECRETS, from: ollama mssql oracle ldap ddev dev mcp redis solr opensearch elasticsearch meilisearch typesense qdrant mongodb"
        else
            LAN_SEEN=$(lan share seen)
            while IFS=$'\t' read -r LAN_P _ LAN_LABEL; do
                [ -n "$LAN_P" ] || continue
                LAN_HIT=$(echo "$LAN_SEEN" | awk -v p="$LAN_P" '$1 == p { print $2 " on " $3; exit }')
                LAN_ST=$(jq -r --arg p "$LAN_P" '.ports[$p].status // empty' "$HOME/.local/state/dev-lan/relay-status.json" 2> /dev/null)
                if [ -n "$LAN_HIT" ]; then
                    already "port $LAN_P ($LAN_LABEL): reached from the network (last from $LAN_HIT)"
                elif [ "$LAN_ST" = direct ]; then
                    skip "port $LAN_P ($LAN_LABEL): the service listens on every interface itself, so the relay cannot see its connections. Forward it in ChromeOS ('lan share ports'), then check from another laptop with 'lan scan'"
                else
                    todo "ChromeOS port forward for $LAN_P ($LAN_LABEL): Settings > Advanced > Developers > Linux > Port forwarding > Add, $LAN_P, TCP. Then run 'lan scan' on another laptop once; this drops off the list when that connection comes through"
                fi
            done < <(lan share plan 2> /dev/null)
            # v89: a devsvc service in LAN_SHARE without its login (redis, qdrant, mongodb) is not shared, nor are
            # memcached, milvus, atlas-local and (v91) selenium, which have none: the 'lan' command says which and why.
            # Notes that only inform (OpenLDAP missing so lldap alone is shared, a LAN port below 1024) are skips.
            while IFS= read -r LAN_NOTE; do
                case "$LAN_NOTE" in
                    "") ;;
                    *"not shared"*|*"never shared"*|*"unknown service"*|*ignoring*) todo "LAN_SHARE: ${LAN_NOTE#lan: }" ;;
                    *) skip "${LAN_NOTE#lan: }" ;;
                esac
            done < <(lan share plan 2>&1 > /dev/null)
            while read -r LAN_P LAN_LABEL; do
                [ -n "$LAN_P" ] || continue
                skip "port $LAN_P ($LAN_LABEL): forward it in ChromeOS too, and start the server with --host / 0.0.0.0 (init cannot see those connections; 'lan share' shows whether it listens on the network)"
            done < <(case " $(echo "${LAN_SHARE:-}" | tr ',;' '  ') " in
                        *" dev "*) for LAN_P in ${LAN_DEV_PORTS:-3000 4200 5173}; do echo "$LAN_P dev-server"; done ;; esac
                     case " $(echo "${LAN_SHARE:-}" | tr ',;' '  ') " in
                        *" mcp "*) for LAN_P in ${LAN_MCP_PORTS:-8770}; do echo "$LAN_P MCP-server"; done ;; esac)
            skip "anyone on the same Wi-Fi reaches these ports, and Ollama has no login: 'lan share off' on any network that is not yours"
        fi
    fi
fi

if has install-aws; then
    section "AWS CLI (install-aws)"
    if aws sts get-caller-identity > /dev/null 2>&1; then
        already "aws credentials work as $(aws sts get-caller-identity --query Arn --output text 2>/dev/null)"
    elif [ -n "$AWS_ACCESS_KEY_ID" ]; then
        todo "AWS_ACCESS_KEY_ID is exported but 'aws sts get-caller-identity' fails; check key, secret and region in $SECRETS"
    elif [ -n "$AWS_PROFILE" ] && aws configure list-profiles 2>/dev/null | grep -qx "$AWS_PROFILE"; then
        # the profile exists, so this is an expired SSO session: refresh it
        if [ "$INTERACTIVE" = 1 ]; then
            aws sso login && ok "SSO session refreshed for profile $AWS_PROFILE" || todo "aws sso login --profile $AWS_PROFILE"
        else
            todo "aws sso login --profile $AWS_PROFILE (session expired, running noninteractive)"
        fi
    elif [ "$INTERACTIVE" = 1 ]; then
        echo "  starting 'aws configure sso' (asks for the IAM Identity Center start URL and region, then opens a browser)..."
        if aws configure sso; then
            ok "SSO profile configured"
            todo "put the profile name you just chose in AWS_PROFILE in $SECRETS so it is the default in every shell"
        else
            todo "aws configure sso"
        fi
    else
        todo "aws configure sso (or static keys in $SECRETS; running noninteractive)"
    fi
fi

if has install-azure; then
    section "Azure CLI (install-azure)"
    if az account show > /dev/null 2>&1; then
        already "az logged in as $(az account show --query user.name -o tsv 2>/dev/null)"
    elif [ -n "$AZURE_CLIENT_ID" ] && [ -n "$AZURE_CLIENT_SECRET" ] && [ -n "$AZURE_TENANT_ID" ]; then
        az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" > /dev/null 2>&1 \
            && ok "az logged in with the service principal" || todo "az service-principal login failed; check AZURE_* in $SECRETS"
    elif [ "$INTERACTIVE" = 1 ]; then
        az login --use-device-code -o none && ok "az logged in" || todo "az login --use-device-code"
    else
        todo "az login --use-device-code (or a service principal in $SECRETS; running noninteractive)"
    fi
    if [ -n "$AZURE_SUBSCRIPTION_ONCE" ] && az account show > /dev/null 2>&1; then
        if az account show --query '[name,id]' -o tsv 2>/dev/null | tr '\t' '\n' | grep -qx "$AZURE_SUBSCRIPTION_ONCE"; then
            already "default subscription is $AZURE_SUBSCRIPTION_ONCE"
        else
            az account set --subscription "$AZURE_SUBSCRIPTION_ONCE" > /dev/null 2>&1 \
                && ok "default subscription set to $AZURE_SUBSCRIPTION_ONCE" || todo "az account set --subscription '$AZURE_SUBSCRIPTION_ONCE' (not found in this login)"
        fi
    fi
fi

if has install-gcp; then
    section "Google Cloud CLI (install-gcp)"
    GCP_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)
    if [ -n "$GCP_ACCOUNT" ]; then
        already "gcloud active account: $GCP_ACCOUNT"
    elif [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ] && [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
        gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" > /dev/null 2>&1 \
            && ok "gcloud activated the service account from GOOGLE_APPLICATION_CREDENTIALS" || todo "gcloud auth activate-service-account failed; check the key file path in $SECRETS"
    elif [ "$INTERACTIVE" = 1 ]; then
        # Chrome is installed in the container, so the browser flow works without --no-browser.
        gcloud auth login && ok "gcloud logged in" || todo "gcloud auth login"
    else
        todo "gcloud auth login (or a service-account key in $SECRETS; running noninteractive)"
    fi
    # Application Default Credentials are what the google-cloud-* SDKs and Terraform's google provider use.
    if [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ] && [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
        already "SDKs use the service-account key (GOOGLE_APPLICATION_CREDENTIALS)"
    elif [ -f ~/.config/gcloud/application_default_credentials.json ]; then
        already "application default credentials present"
    elif [ "$INTERACTIVE" = 1 ]; then
        gcloud auth application-default login && ok "application default credentials created" || todo "gcloud auth application-default login"
    else
        todo "gcloud auth application-default login (running noninteractive)"
    fi
    if [ -n "$GCP_PROJECT_ONCE" ]; then
        if [ "$(gcloud config get-value project 2>/dev/null)" = "$GCP_PROJECT_ONCE" ]; then
            already "default project is $GCP_PROJECT_ONCE"
        else
            gcloud config set project "$GCP_PROJECT_ONCE" > /dev/null 2>&1 && ok "default project set to $GCP_PROJECT_ONCE" || todo "gcloud config set project $GCP_PROJECT_ONCE"
        fi
    fi
fi

if has install-vercel; then
    section "Vercel CLI (install-vercel)"
    if ! command -v vercel > /dev/null 2>&1; then
        todo "vercel not found: rerun dev-setup with install-vercel"
    else
        VERCEL_USER=$(vercel whoami < /dev/null 2> /dev/null | tail -n 1)
        if [ -n "$VERCEL_USER" ]; then
            if [ -n "$VERCEL_TOKEN" ]; then already "vercel authenticated as $VERCEL_USER (VERCEL_TOKEN)"; else already "vercel logged in as $VERCEL_USER"; fi
        elif [ -n "$VERCEL_TOKEN" ]; then
            todo "VERCEL_TOKEN in $SECRETS was rejected: replace it, or comment it out to use 'vercel login'"
        elif [ "$INTERACTIVE" = 1 ]; then
            vercel login && ok "vercel logged in" || todo "vercel login"
        else
            todo "vercel login (or VERCEL_TOKEN in $SECRETS; running noninteractive)"
        fi
        already "per project: 'vercel link' once, then 'vercel env pull' writes that project's variables to .env.local"
    fi
fi

# v89: Cloudflare (install-cloudflare, install-cloudflared). The one login here, and optional: an empty
# CLOUDFLARE_API_TOKEN with no saved 'wrangler login' is a skip, not a todo.
if has install-cloudflare; then
    section "Cloudflare wrangler (install-cloudflare)"
    if ! command -v wrangler > /dev/null 2>&1; then
        todo "wrangler not found: rerun dev-setup with install-cloudflare"
    else
        CF_WHO=$(CI=1 timeout 60 wrangler whoami < /dev/null 2>&1 || true)
        CF_EMAIL=$(echo "$CF_WHO" | grep -oE '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]+' | head -n 1)
        if echo "$CF_WHO" | grep -qiE 'associated with the email|You are logged in'; then
            already "wrangler reaches Cloudflare${CF_EMAIL:+ as $CF_EMAIL}$( [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && echo ' (CLOUDFLARE_API_TOKEN)')"
            [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ] \
                && skip "CLOUDFLARE_ACCOUNT_ID is empty (optional): with a token for several accounts, wrangler asks which one on deploy"
        elif echo "$CF_WHO" | grep -qiE 'fetch failed|ENOTFOUND|ECONNREFUSED|ETIMEDOUT|network connection'; then
            skip "wrangler could not reach Cloudflare (network), so the login was not checked; rerun dev-init when online"
        elif [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
            todo "Cloudflare rejects CLOUDFLARE_API_TOKEN in $SECRETS: create a new one (template 'Edit Cloudflare Workers') or comment it out"
        else
            skip "no Cloudflare account set up (optional; 'wrangler dev' works without): CLOUDFLARE_API_TOKEN in $SECRETS, or 'wrangler login'"
        fi
    fi
fi
if has install-cloudflared; then
    section "Cloudflare Tunnel (install-cloudflared)"
    if ! command -v cloudflared > /dev/null 2>&1; then
        todo "cloudflared not found: rerun dev-setup with install-cloudflared (its log says why)"
    elif [ -f "$HOME/.cloudflared/cert.pem" ]; then
        already "cloudflared is logged in for named tunnels (~/.cloudflared/cert.pem); quick tunnels need nothing"
    else
        skip "cloudflared: quick tunnels need no login; 'cloudflared tunnel login' only for named tunnels on your own domain (optional)"
    fi
fi

if has install-jev; then
    section "Jev / TypeSafe AI (install-jev)"
    if [ -n "$TYPESAFE_API_KEY" ]; then
        already "TYPESAFE_API_KEY exported (direct access; both TypeSafe SDKs read it)"
    elif [ -n "$AI_GATEWAY_API_KEY" ]; then
        already "AI_GATEWAY_API_KEY exported (Jev through Vercel AI Gateway: AI SDK, model 'typesafe-ai/jev')"
    else
        todo "add TYPESAFE_API_KEY (console.typesafe.ai, waitlisted) or AI_GATEWAY_API_KEY (Vercel dashboard) to $SECRETS, then rerun"
    fi
    [ -n "$TYPESAFE_API_KEY" ] && [ -n "$AI_GATEWAY_API_KEY" ] && already "AI_GATEWAY_API_KEY exported too (gateway route)"
    already "pin the model once you tune thresholds (jev-latest moves), and log response.model; SDKs are per project: 'uv add typesafe-sdk' / 'pnpm add @typesafe-ai/sdk'"
fi

if has install-iac; then
    section "IaC: Terraform (install-iac)"
    # One provider cache for the whole machine: otherwise every project's 'terraform init' downloads
    # its own copy of the AWS/Azure/Google providers (hundreds of MB each) into .terraform/.
    TF_CACHE="$HOME/.terraform.d/plugin-cache"
    mkdir -p "$TF_CACHE"
    if grep -q '^plugin_cache_dir' ~/.terraformrc 2>/dev/null; then
        already "~/.terraformrc has plugin_cache_dir"
    else
        printf 'plugin_cache_dir = "%s"\n' "$TF_CACHE" >> ~/.terraformrc && ok "~/.terraformrc: plugin_cache_dir = $TF_CACHE"
    fi
    if command -v az > /dev/null 2>&1; then
        az bicep version > /dev/null 2>&1 && already "bicep available via 'az bicep'" || todo "az bicep install (the installer does this when install-azure and install-iac run together)"
    fi
    already "no accounts to initialize; state backends and provider credentials are per project (the cloud logins above are what the providers use)"
fi

if has install-ansible-full || has install-ansible-core; then
    section "Ansible (install-ansible-full / install-ansible-core)"
    if [ -n "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ]; then
        VPF="${ANSIBLE_VAULT_PASSWORD_FILE/#\~/$HOME}"
        if [ -f "$VPF" ] && [ -x "$VPF" ]; then
            # Ansible RUNS an executable password file, so a plain password file with +x breaks it.
            if [ "$(head -c 2 "$VPF")" = '#!' ]; then
                already "vault password script $VPF (executable: Ansible runs it for the password)"
            else
                todo "$VPF is executable but not a script, so Ansible would try to run it: chmod 600 it"
            fi
        elif [ -f "$VPF" ]; then
            VPM=$(stat -c %a "$VPF")
            if [ "$VPM" = 600 ] || [ "$VPM" = 400 ]; then
                already "vault password file $VPF (mode $VPM)"
            else
                chmod 600 "$VPF" && ok "vault password file $VPF: mode $VPM -> 600"
            fi
        else
            todo "ANSIBLE_VAULT_PASSWORD_FILE points at $VPF, which does not exist: create it (one line, chmod 600) or comment the line out in secrets.env"
        fi
    else
        skip "no vault password file (optional: ANSIBLE_VAULT_PASSWORD_FILE in secrets.env, or --ask-vault-pass per run)"
    fi
    already "no accounts to initialize; Docker containers need nothing as targets, SSH hosts need 'ssh-copy-id -i ~/.ssh/id_ed25519.pub user@host' once"
fi

if has install-web; then
    section "Web tooling (install-web)"
    if ng analytics info 2>/dev/null | grep -qi 'Global setting: *disabled'; then
        already "Angular CLI analytics disabled"
    else
        ng analytics disable --global > /dev/null 2>&1 && ok "Angular CLI analytics disabled" || todo "ng analytics disable --global"
    fi
    already "corepack and Composer need no accounts; 'corepack use pnpm@latest' pins a package manager per project"
fi

if has install-k8s; then
    section "Kubernetes (install-k8s)"
    if [ -f ~/.kube/config ]; then
        already "~/.kube/config present with $(kubectl config get-contexts -o name 2>/dev/null | wc -l) context(s)"
    else
        already "no ~/.kube/config yet: 'kind create cluster' writes one; cloud clusters via 'aws eks update-kubeconfig', 'az aks get-credentials' or 'gcloud container clusters get-credentials'"
    fi
fi

if has install-cpp || has install-asm || has install-asm-arm; then
    section "Native toolchains (install-cpp / install-asm / install-asm-arm)"
    already "compilers, assemblers and debuggers need no accounts or keys"
fi

if has install-godot; then
    section "Godot (install-godot)"
    if command -v godot > /dev/null 2>&1; then
        already "Godot $(godot --version 2>/dev/null) and godot-mono need no account"
    else
        todo "godot not found: rerun dev-setup with install-godot"
    fi
    already "new projects: pick the Compatibility renderer (Forward+ and Mobile need Vulkan, which Crostini does not expose). Android export settings (SDK path, debug keystore) are per machine in Editor Settings > Export > Android"
fi

if has install-drupal; then
    section "Drupal hosting CLIs and DDEV (install-drupal)"
    DRUPAL_KEY_LABEL="${MACHINE_LABEL:-$(hostname)}-$(date +%Y%m%d)"
    DDEV_ENV=()

    # --- Pantheon / Terminus: machine token only (there is no browser login) ---
    if ! command -v terminus > /dev/null 2>&1; then
        todo "terminus not found: rerun dev-setup with install-drupal"
    else
        TERMINUS_USER=$(timeout 60 terminus auth:whoami --no-interaction < /dev/null 2> /dev/null | grep -m1 '@' || true)
        if [ -z "$TERMINUS_USER" ] && [ -n "$TERMINUS_MACHINE_TOKEN_ONCE" ]; then
            timeout 120 terminus auth:login --machine-token="$TERMINUS_MACHINE_TOKEN_ONCE" --no-interaction < /dev/null > /dev/null 2>&1 || true
            TERMINUS_USER=$(timeout 60 terminus auth:whoami --no-interaction < /dev/null 2> /dev/null | grep -m1 '@' || true)
            if [ -n "$TERMINUS_USER" ]; then ok "terminus logged in as $TERMINUS_USER"; else todo "terminus login failed: check TERMINUS_MACHINE_TOKEN_ONCE in $SECRETS"; fi
        elif [ -n "$TERMINUS_USER" ]; then
            already "terminus logged in as $TERMINUS_USER"
        else
            # v68: no token is not a problem to fix. All three platforms are optional, so this is a
            # 'skip', not a 'todo': nothing lands in the still-manual list at the end.
            skip "Pantheon (optional): terminus is installed and ready. When you want it, put a machine token in TERMINUS_MACHINE_TOKEN_ONCE ($SECRETS) and rerun init"
        fi
        if [ -n "$TERMINUS_USER" ] && [ -f ~/.ssh/id_ed25519.pub ]; then
            # Pantheon identifies a key by its MD5 fingerprint without the colons.
            KEY_MD5=$(ssh-keygen -E md5 -lf ~/.ssh/id_ed25519.pub | awk '{print $2}' | sed 's/^MD5://; s/://g')
            if timeout 60 terminus ssh-key:list --format=json --no-interaction < /dev/null 2> /dev/null | grep -qi "$KEY_MD5"; then
                already "SSH key registered with Pantheon"
            elif timeout 120 terminus ssh-key:add ~/.ssh/id_ed25519.pub --no-interaction < /dev/null > /dev/null 2>&1; then
                ok "SSH key uploaded to Pantheon (git and remote drush use it)"
            else
                todo "terminus ssh-key:add ~/.ssh/id_ed25519.pub"
            fi
        fi
        # Only a token that actually logged in goes on to DDEV.
        [ -n "$TERMINUS_USER" ] && [ -n "$TERMINUS_MACHINE_TOKEN_ONCE" ] && DDEV_ENV+=("TERMINUS_MACHINE_TOKEN=$TERMINUS_MACHINE_TOKEN_ONCE")
    fi

    # --- Acquia / acli: API key + secret ---
    if ! command -v acli > /dev/null 2>&1; then
        todo "acli not found: rerun dev-setup with install-drupal"
    else
        acli_authed() { timeout 90 acli api:accounts:find --no-interaction < /dev/null > /dev/null 2>&1; }
        if acli_authed; then
            already "acli authenticated with Acquia Cloud Platform"; ACLI_OK=1
        elif [ -n "$ACQUIA_API_KEY_ONCE" ] && [ -n "$ACQUIA_API_SECRET_ONCE" ]; then
            timeout 120 acli auth:login --key="$ACQUIA_API_KEY_ONCE" --secret="$ACQUIA_API_SECRET_ONCE" --no-interaction < /dev/null > /dev/null 2>&1 || true
            if acli_authed; then ok "acli authenticated"; ACLI_OK=1; else todo "acli login failed: check ACQUIA_API_KEY_ONCE / ACQUIA_API_SECRET_ONCE in $SECRETS"; ACLI_OK=0; fi
        else
            skip "Acquia (optional): acli is installed and ready. When you want it, put a key and secret in ACQUIA_API_KEY_ONCE / ACQUIA_API_SECRET_ONCE ($SECRETS) and rerun init"; ACLI_OK=0
        fi
        if [ "$ACLI_OK" = 1 ] && [ -f ~/.ssh/id_ed25519.pub ]; then
            KEY_BODY=$(awk '{print $2}' ~/.ssh/id_ed25519.pub)
            if timeout 90 acli api:accounts:ssh-keys-list --no-interaction < /dev/null 2> /dev/null | grep -qF "$KEY_BODY"; then
                already "SSH key registered with Acquia"
            elif timeout 180 acli ssh-key:upload --filepath="$HOME/.ssh/id_ed25519.pub" --label="$(echo "$DRUPAL_KEY_LABEL" | tr -c 'A-Za-z0-9\n' '_')" --no-wait --no-interaction < /dev/null > /dev/null 2>&1; then
                ok "SSH key uploaded to Acquia (can take a few minutes to reach every environment)"
            else
                todo "acli ssh-key:upload --filepath=~/.ssh/id_ed25519.pub"
            fi
        fi
        [ "$ACLI_OK" = 1 ] && [ -n "$ACQUIA_API_KEY_ONCE" ] && [ -n "$ACQUIA_API_SECRET_ONCE" ] && DDEV_ENV+=("ACQUIA_API_KEY=$ACQUIA_API_KEY_ONCE" "ACQUIA_API_SECRET=$ACQUIA_API_SECRET_ONCE")
    fi

    # --- Upsun: optional. The CLI reads UPSUN_CLI_TOKEN from the environment; no key upload (it uses SSH certificates). ---
    if command -v upsun > /dev/null 2>&1; then
        if [ -n "$UPSUN_CLI_TOKEN" ]; then
            if timeout 90 upsun auth:info --no-interaction < /dev/null > /dev/null 2>&1; then
                already "upsun authenticated (UPSUN_CLI_TOKEN)"; DDEV_ENV+=("UPSUN_CLI_TOKEN=$UPSUN_CLI_TOKEN")
            else
                todo "UPSUN_CLI_TOKEN in $SECRETS was rejected"
            fi
        elif timeout 90 upsun auth:info --no-auto-login --no-interaction < /dev/null > /dev/null 2>&1; then
            already "upsun logged in"
        else
            skip "Upsun (optional): uncomment UPSUN_CLI_TOKEN in $SECRETS, or run 'upsun login', if you have projects there"
        fi
    fi

    # --- DDEV global config: what 'ddev pull pantheon|acquia|upsun' reads. Replace-or-add, keeping every
    # other entry: 'ddev config global --web-environment-add' appends a duplicate when the key exists. ---
    if ! command -v ddev > /dev/null 2>&1; then
        todo "ddev not found: rerun dev-setup"
    else
        ddev config global --instrumentation-opt-in=false < /dev/null > /dev/null 2>&1 || true
        if [ ${#DDEV_ENV[@]} -gt 0 ]; then
            DDEV_CFG="$HOME/.ddev/global_config.yaml"
            DDEV_CUR=$(awk '/^web_environment:/{f=1;next} f&&/^[^ -]/{f=0} f&&/^ *- /{sub(/^ *- /,""); gsub(/^"|"$/,""); print}' "$DDEV_CFG" 2> /dev/null || true)
            DDEV_NEW=""
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                for kv in "${DDEV_ENV[@]}"; do [ "${kv%%=*}" = "${line%%=*}" ] && continue 2; done
                DDEV_NEW="${DDEV_NEW:+$DDEV_NEW,}$line"
            done <<< "$DDEV_CUR"
            for kv in "${DDEV_ENV[@]}"; do DDEV_NEW="${DDEV_NEW:+$DDEV_NEW,}$kv"; done
            if ddev config global --web-environment="$DDEV_NEW" < /dev/null > /dev/null 2>&1; then
                chmod 600 "$DDEV_CFG"   # it now holds platform tokens; ddev writes it 644
                ok "DDEV global config carries the platform tokens for 'ddev pull' ($(printf '%s ' "${DDEV_ENV[@]%%=*}")) and is mode 600"
            else
                todo "ddev config global --web-environment=... failed; see 'ddev config global --help'"
            fi
        else
            skip "no platform token set yet, so nothing to give DDEV for 'ddev pull' (rerun init once you add one)"
        fi
    fi

    # --- drupal.org: contrib work pushes to git.drupalcode.org over SSH; there is no API to upload the key ---
    if timeout 25 ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 git@git.drupal.org < /dev/null 2>&1 | grep -qi 'welcome'; then
        already "drupal.org recognises your SSH key (git.drupalcode.org)"
    else
        skip "drupal.org (do it when you next push contrib work): add ~/.ssh/id_ed25519.pub at https://git.drupalcode.org/-/user_settings/ssh_keys"
    fi
fi

# v87: Laravel (install-laravel). Nothing to log in to: Laravel apps keep their settings in each
# project's .env. Init confirms the installer and names the per-project steps.
if has install-laravel; then
    section "Laravel (install-laravel)"
    if command -v laravel > /dev/null 2>&1 || [ -x "$HOME/.config/composer/vendor/bin/laravel" ]; then
        already "Laravel installer: $({ command -v laravel > /dev/null && laravel --version || "$HOME/.config/composer/vendor/bin/laravel" --version; } 2> /dev/null | head -n 1); 'laravel new <app>' in a new terminal"
    else
        todo "the Laravel installer is missing: rerun dev-setup with install-laravel ('composer create-project laravel/laravel <app>' works meanwhile)"
    fi
    skip "per project: Laravel Boost gives Claude Code the app's docs and tools (composer require laravel/boost --dev, then php artisan boost:install)"
    skip "Laravel Cloud and Forge accounts are yours to connect when you deploy; nothing is stored here"
fi

# v88: Symfony (install-symfony). Nothing to log in to: apps keep their settings in .env / .env.local.
# Init confirms the CLI and its requirements check, and that git knows who you are ('symfony new'
# commits the new project unless given --no-git).
if has install-symfony; then
    section "Symfony (install-symfony)"
    if command -v symfony > /dev/null 2>&1; then
        if symfony check:requirements --no-ansi > /dev/null 2>&1; then
            already "$(symfony version --no-ansi 2> /dev/null | head -n 1 | sed 's/ *(.*//'); check:requirements OK"
        else
            todo "'symfony check:requirements' reports a problem: run it to see which PHP setting or extension is missing"
        fi
        if [ -n "$(git config --global user.name)" ] && [ -n "$(git config --global user.email)" ]; then
            already "git identity set, so 'symfony new' can make its first commit"
        else
            todo "set GIT_NAME and GIT_EMAIL in $SECRETS: 'symfony new' commits the new project (or pass --no-git)"
        fi
    else
        todo "the Symfony CLI is missing: rerun dev-setup with install-symfony"
    fi
    skip "https for 'symfony serve' is optional: 'symfony server:ca:install' adds the CLI's local CA to the system and browser trust stores"
    skip "Upsun / Platform.sh deploys: the upsun CLI from install-drupal ('symfony new --upsun' writes its config)"
fi

# v90: Apollo GraphOS (install-graphql). Optional: local federation, the router and apollo-mcp-server need no
# account, so an empty APOLLO_KEY is a skip. A key in secrets.env goes into Rover's default profile, the
# file 'rover config auth' writes (that command reads the key only from its own prompt), and 'rover config
# whoami' asks GraphOS whose it is: a rejected key is a todo, GraphOS out of reach a skip. APOLLO_KEY
# exported anywhere is a todo: every local router and MCP server would then report to GraphOS.
if has install-graphql; then
    section "Apollo GraphOS (install-graphql)"
    ROVER_BIN="$HOME/.local/bin/rover"
    ROVER_PROFILE="${APOLLO_CONFIG_HOME:-$HOME/.config/rover}/profiles/default"
    if [ ! -x "$ROVER_BIN" ]; then
        todo "rover is missing: rerun dev-setup with install-graphql"
    elif [ -z "${APOLLO_KEY:-}" ]; then
        if [ -s "$ROVER_PROFILE/.sensitive" ]; then
            skip "APOLLO_KEY is empty in $SECRETS; Rover's default profile keeps the key it already has ('rover config clear' removes it)"
        else
            skip "no APOLLO_KEY in $SECRETS (optional): local federation, the router and the MCP server need no account"
        fi
    else
        if [ "$(sed -n 's/^api_key = "\(.*\)"$/\1/p' "$ROVER_PROFILE/.sensitive" 2> /dev/null)" = "$APOLLO_KEY" ]; then
            ROVER_KEY_NOTE="already in Rover's default profile"
        else
            mkdir -p "$ROVER_PROFILE"
            (umask 077 && printf 'api_key = "%s"\n' "$APOLLO_KEY" > "$ROVER_PROFILE/.sensitive")
            chmod 600 "$ROVER_PROFILE/.sensitive"
            ROVER_KEY_NOTE="written to Rover's default profile"
        fi
        # The profile alone is checked: APOLLO_KEY is in this script's environment (set -a above), and Rover
        # would read that first. --format json gives a result to read (data.success, or error.code and
        # .message) instead of a table whose layout changes between Rover releases.
        ROVER_WHO=$(env -u APOLLO_KEY APOLLO_TELEMETRY_DISABLED=true timeout 60 "$ROVER_BIN" config whoami --format json --skip-update-check 2> /dev/null \
            | python3 -c '
import json, sys
try:
    r = json.load(sys.stdin)
except ValueError:
    print("unreadable"); sys.exit()
d, e = r.get("data") or {}, r.get("error") or {}
if d.get("success"):
    print("ok\t" + "; ".join(f"{k.replace(chr(95), chr(32))}: {v}" for k, v in d.items()
                             if k not in ("success", "api_key") and isinstance(v, (str, int)) and v != ""))
else:
    print((e.get("code") or "error") + "\t" + " ".join(str(e.get("message", "")).split())[:160])' 2> /dev/null)
        case "${ROVER_WHO%%$'\t'*}" in
            ok)
                ROVER_WHO=${ROVER_WHO#ok}; ROVER_WHO=${ROVER_WHO#$'\t'}
                if [ "$ROVER_KEY_NOTE" = "written to Rover's default profile" ]; then
                    ok "GraphOS key $ROVER_KEY_NOTE${ROVER_WHO:+ ($ROVER_WHO)}"
                else
                    already "GraphOS key $ROVER_KEY_NOTE${ROVER_WHO:+ ($ROVER_WHO)}"
                fi ;;
            unreadable|"")
                # Empty: Rover timed out or did not run.
                skip "GraphOS did not answer (offline?), so the key ($ROVER_KEY_NOTE) is unconfirmed; 'rover config whoami' checks it later" ;;
            E012)
                # E012 covers both "no response" (offline, proxy, DNS) and an HTTP error status: only the
                # network kind and a server-side 5xx are a skip; a 4xx means the key was refused.
                if printf '%s' "${ROVER_WHO#*$'\t'}" | grep -qiE 'connect|sending request|dns|timed out|tunnel|status(: | code )?5[0-9][0-9]|\b5[0-9][0-9] '; then
                    skip "GraphOS is out of reach (offline?), so the key ($ROVER_KEY_NOTE) is unconfirmed; 'rover config whoami' checks it later"
                else
                    todo "GraphOS refused APOLLO_KEY from $SECRETS (E012: ${ROVER_WHO#*$'\t'}). Make a new key in GraphOS Studio and rerun dev-init"
                fi ;;
            *)
                todo "GraphOS rejected APOLLO_KEY from $SECRETS (${ROVER_WHO%%$'\t'*}: ${ROVER_WHO#*$'\t'}). Make a new key in GraphOS Studio and rerun dev-init" ;;
        esac
        if [ -n "${APOLLO_GRAPH_REF:-}" ]; then
            already "APOLLO_GRAPH_REF=$APOLLO_GRAPH_REF, for 'rover dev' with Apollo Connectors (dev-demo drupal-graphql connectors)"
        else
            skip "APOLLO_GRAPH_REF is empty (optional): Apollo Connectors in 'rover dev' need it with the key (graph-id@variant)"
        fi
    fi
    APOLLO_EXPORTED=""
    [ -n "$APOLLO_KEY_INHERITED" ] && APOLLO_EXPORTED="the environment dev-init was started from"
    for APOLLO_F in "$SECRETS" ~/.bashrc; do
        grep -qE '^[[:space:]]*export[[:space:]]+APOLLO_KEY="?[^" ]' "$APOLLO_F" 2> /dev/null && APOLLO_EXPORTED="${APOLLO_EXPORTED:+$APOLLO_EXPORTED, }$APOLLO_F"
    done
    if [ -n "$APOLLO_EXPORTED" ]; then
        todo "APOLLO_KEY is exported ($APOLLO_EXPORTED): every local router and MCP server then reports to GraphOS, where the Free plan allows self-hosted routers 60 requests a minute. Drop the 'export' (secrets.env keeps it unexported; Rover's profile has it)"
    fi
fi

# v91: the test tools (install-testing = install-playwright, install-selenium, install-bdd, install-robot; and
# the opt-in install-cypress). Nothing to log in to: init reports what setup left (Playwright's browsers,
# Selenium Manager's driver for this Chrome, Reqnroll's templates, Robot Framework) and the one optional
# key, CYPRESS_RECORD_KEY. The Selenium Grid's state is in the shared services section above.
T_INIT=0
for T in playwright selenium bdd robot cypress; do has "install-$T" && T_INIT=1; done
if [ "$T_INIT" = 1 ]; then
    section "Test tools (install-testing, install-cypress)"
    if has install-playwright; then
        T_PW=$(find ~/.cache/ms-playwright -mindepth 1 -maxdepth 1 -type d \( -name 'chromium-*' -o -name 'firefox-*' -o -name 'webkit-*' \) -printf '%f\n' 2> /dev/null | sed 's/-[0-9]*$//' | sort -u | xargs)
        if [ "$T_PW" = "chromium firefox webkit" ]; then
            already "Playwright's Chromium, Firefox and WebKit in ~/.cache/ms-playwright (no account; Playwright MCP: 'claude mcp add playwright -- npx @playwright/mcp@latest')"
        else
            todo "Playwright's browsers are incomplete (${T_PW:-none} in ~/.cache/ms-playwright): rerun dev-setup with install-playwright"
        fi
    fi
    if has install-selenium; then
        T_CM=$(google-chrome-stable --version 2> /dev/null | grep -oE '[0-9]+' | head -n 1)
        if [ -n "$T_CM" ] && ls -d ~/.cache/selenium/chromedriver/linux64/"$T_CM".* > /dev/null 2>&1; then
            already "Selenium Manager has the chromedriver for Chrome $T_CM (~/.cache/selenium); the Grid: 'devsvc up selenium'"
        else
            skip "Selenium Manager has no chromedriver for Chrome ${T_CM:-?} yet (Chrome updated since setup?): the next Selenium run fetches it"
        fi
    fi
    if has install-bdd; then
        if ! command -v dotnet > /dev/null 2>&1; then
            already "Gherkin runners need no account; they are per project (cucumber-js, behave, Behat, cucumber-jvm)"
        elif dotnet new list reqnroll-project > /dev/null 2>&1; then
            already "Reqnroll's templates for 'dotnet new' (reqnroll-project); the other Gherkin runners are per project"
        else
            todo "Reqnroll's templates are missing: rerun dev-setup with install-bdd (dotnet new install Reqnroll.Templates.DotNet)"
        fi
    fi
    if has install-robot; then
        if [ -x "$HOME/.local/bin/robot" ] && [ -x "$HOME/.local/bin/rfbrowser" ]; then
            already "$("$HOME/.local/bin/robot" --version 2>&1 | head -n 1 | cut -d' ' -f1-3) with the Browser, SeleniumLibrary and Requests libraries"
        else
            todo "robot or rfbrowser missing from ~/.local/bin: rerun dev-setup with install-robot"
        fi
    fi
    if has install-cypress; then
        if [ -n "${CYPRESS_RECORD_KEY:-}" ]; then
            already "CYPRESS_RECORD_KEY is set: 'npx cypress run --record' reports to Cypress Cloud (the project's cypress.config names its projectId)"
        else
            skip "no CYPRESS_RECORD_KEY in $SECRETS (optional): Cypress runs locally without Cypress Cloud"
        fi
    fi
fi

# v91: GitLab (install-gitlab, install-gitlab-runner). All optional: an empty value is a skip. glab logs in with
# GITLAB_TOKEN_ONCE (gitlab.com) and DRUPALCODE_TOKEN_ONCE (git.drupalcode.org), the SSH key goes to gitlab.com,
# the runner registers once with GITLAB_RUNNER_TOKEN_ONCE, and GITLAB_MCP=1 adds GitLab's MCP server to Claude Code.
if has install-gitlab; then
    section "GitLab (install-gitlab)"
    if ! command -v glab > /dev/null 2>&1; then
        todo "glab is missing: rerun dev-setup with install-gitlab"
    else
        # glab_login HOST TOKEN LABEL: log glab in to HOST once; an existing login is kept.
        glab_login() {
            local host=$1 token=$2 label=$3
            if timeout 60 glab auth status --hostname "$host" > /dev/null 2>&1; then
                already "glab is logged in to $label ($host)"
            elif [ -z "$token" ]; then
                skip "no token for $label in $SECRETS (optional): glab and gitlab-ci-local work without one"
            elif printf '%s' "$token" | timeout 90 glab auth login --hostname "$host" --stdin --git-protocol ssh > /dev/null 2>&1 \
                && timeout 60 glab auth status --hostname "$host" > /dev/null 2>&1; then
                ok "glab logged in to $label ($host)"
            else
                todo "glab could not log in to $host with that token: check it has the api scope and has not expired"
            fi
        }
        glab_login gitlab.com "${GITLAB_TOKEN_ONCE:-}" gitlab.com
        glab_login git.drupalcode.org "${DRUPALCODE_TOKEN_ONCE:-}" "drupal.org's GitLab"
        if timeout 60 glab auth status --hostname gitlab.com > /dev/null 2>&1 && [ -f ~/.ssh/id_ed25519.pub ]; then
            KEY_PART=$(cut -d' ' -f2 ~/.ssh/id_ed25519.pub)
            if GITLAB_HOST=gitlab.com timeout 60 glab ssh-key list 2> /dev/null | grep -qF "$KEY_PART"; then
                already "SSH key ~/.ssh/id_ed25519.pub is on gitlab.com"
            elif GITLAB_HOST=gitlab.com timeout 60 glab ssh-key add ~/.ssh/id_ed25519.pub --title "${MACHINE_LABEL:-$(hostname)}-$(date +%Y%m%d)" > /dev/null 2>&1; then
                ok "SSH key uploaded to gitlab.com"
            else
                todo "upload ~/.ssh/id_ed25519.pub to gitlab.com (Preferences > SSH keys, or a token with the api scope)"
            fi
        fi
    fi
    if [ "${GITLAB_MCP:-}" = 1 ]; then
        if ! command -v claude > /dev/null 2>&1; then
            skip "GITLAB_MCP=1, but Claude Code is not installed (install-node)"
        elif timeout 60 claude mcp get GitLab > /dev/null 2>&1; then
            already "GitLab's MCP server is in Claude Code (its first use asks for GitLab's OAuth login)"
        elif timeout 60 claude mcp add -s user --transport http GitLab https://gitlab.com/api/v4/mcp > /dev/null 2>&1; then
            ok "GitLab's MCP server added to Claude Code (user scope); its first use opens GitLab's OAuth login"
        else
            todo "claude mcp add -s user --transport http GitLab https://gitlab.com/api/v4/mcp"
        fi
    fi
    if has install-gitlab-runner; then
        if ! command -v gitlab-runner > /dev/null 2>&1; then
            todo "gitlab-runner is missing: rerun dev-setup with install-gitlab-runner"
        elif [ -n "${GITLAB_RUNNER_TOKEN_ONCE:-}" ] && sudo -n grep -qF "$GITLAB_RUNNER_TOKEN_ONCE" /etc/gitlab-runner/config.toml 2> /dev/null; then
            already "the runner is registered with that token ('sudo gitlab-runner list')"
        elif [ -n "${GITLAB_RUNNER_TOKEN_ONCE:-}" ]; then
            # Authentication tokens (glrt-) carry the runner's settings from GitLab; only the URL, the executor and
            # this machine's name are given here.
            # The token goes in through the environment (CI_SERVER_TOKEN), not the command line other users can see.
            if timeout 120 sudo -n env CI_SERVER_TOKEN="$GITLAB_RUNNER_TOKEN_ONCE" gitlab-runner register --non-interactive --url https://gitlab.com \
                --executor docker --docker-image alpine:latest --name "${MACHINE_LABEL:-$(hostname)}" > /dev/null 2>&1; then
                ok "runner registered with gitlab.com (Docker executor, name ${MACHINE_LABEL:-$(hostname)})"
            else
                todo "the runner did not register: check GITLAB_RUNNER_TOKEN_ONCE (a glrt- token from Settings > CI/CD > Runners)"
            fi
        elif sudo -n grep -qs '^\[\[runners\]\]' /etc/gitlab-runner/config.toml; then
            already "a runner is registered ('sudo gitlab-runner list')"
        else
            skip "the runner is installed but not registered (optional): GITLAB_RUNNER_TOKEN_ONCE in $SECRETS registers it"
        fi
    fi
fi

# v91: Puppet and Chef (install-puppet, install-chef). No account is needed: both run masterless here. The report
# gives the versions; KNIFE_CHEF_SERVER_URL, KNIFE_NODE_NAME and KNIFE_CLIENT_KEY (all three, optional) write knife's
# default credentials profile once, for a Chef or Cinc server you already use.
if has install-puppet; then
    section "Puppet (install-puppet: OpenVox, OpenBolt)"
    if [ -x /opt/puppetlabs/bin/puppet ]; then
        already "OpenVox $(/opt/puppetlabs/bin/puppet --version 2> /dev/null), facter $(/opt/puppetlabs/bin/facter --version 2> /dev/null | cut -d' ' -f1) need no account: 'puppet apply' runs masterless"
        if systemctl is-enabled puppet > /dev/null 2>&1; then
            todo "the puppet agent service is enabled, but there is no server here: sudo systemctl disable --now puppet"
        fi
    else
        todo "puppet not found in /opt/puppetlabs/bin: rerun dev-setup with install-puppet"
    fi
    if [ -x /opt/puppetlabs/bin/bolt ]; then
        already "OpenBolt $(/opt/puppetlabs/bin/bolt --version 2> /dev/null) needs no account: targets are SSH hosts, containers (docker://) or localhost"
    else
        skip "bolt not found (optional): rerun dev-setup with install-puppet"
    fi
fi

if has install-chef; then
    section "Chef (install-chef: Cinc Workstation)"
    CINC_BIN=/opt/cinc-workstation/bin
    if [ ! -x "$CINC_BIN/cinc-client" ]; then
        todo "Cinc Workstation not found in /opt/cinc-workstation: rerun dev-setup with install-chef"
    else
        CINC_VER=$(dpkg-query -W -f='${Version}' cinc-workstation 2> /dev/null | cut -d- -f1)
        already "Cinc Workstation${CINC_VER:+ $CINC_VER} (cinc-client $("$CINC_BIN/cinc-client" --version 2> /dev/null | awk '{print $NF}')) needs no license or account: 'cinc-client -z' runs local mode"
        # knife's folder is ~/.chef in Chef's builds; Cinc's own build names it, so ask its Ruby rather than guess.
        KNIFE_DIR=$(/opt/cinc-workstation/embedded/bin/ruby -e 'require "chef-utils/dist"; print ChefUtils::Dist::Infra::USER_CONF_DIR' 2> /dev/null)
        KNIFE_DIR="$HOME/${KNIFE_DIR:-.chef}"
        if [ -z "${KNIFE_CHEF_SERVER_URL:-}" ] || [ -z "${KNIFE_NODE_NAME:-}" ] || [ -z "${KNIFE_CLIENT_KEY:-}" ]; then
            if [ -f "$KNIFE_DIR/credentials" ] || [ -f "$KNIFE_DIR/config.rb" ] || [ -f "$KNIFE_DIR/knife.rb" ]; then
                already "knife has a configuration in $KNIFE_DIR"
            else
                skip "no Chef server in $SECRETS (optional): knife, Test Kitchen and local mode work without one"
            fi
        elif grep -qs '^\[default\]' "$KNIFE_DIR/credentials"; then
            already "knife's default profile is in $KNIFE_DIR/credentials (kept as it is)"
        elif [ ! -f "${KNIFE_CLIENT_KEY/#\~/$HOME}" ]; then
            todo "KNIFE_CLIENT_KEY points to ${KNIFE_CLIENT_KEY}, which is not here: download your user's key from the server first"
        else
            mkdir -p "$KNIFE_DIR" && chmod 700 "$KNIFE_DIR"
            KNIFE_SEP=""; [ -s "$KNIFE_DIR/credentials" ] && KNIFE_SEP=$'\n'
            ( umask 077
              { printf '%s' "$KNIFE_SEP"
                echo "[default]"
                echo "client_name     = '$KNIFE_NODE_NAME'"
                echo "client_key      = '${KNIFE_CLIENT_KEY/#\~/$HOME}'"
                echo "chef_server_url = '$KNIFE_CHEF_SERVER_URL'"
              } >> "$KNIFE_DIR/credentials" )
            if timeout 60 "$CINC_BIN/knife" node list > /dev/null 2>&1; then
                ok "knife's default profile written to $KNIFE_DIR/credentials; 'knife node list' reaches the server"
            else
                ok "knife's default profile written to $KNIFE_DIR/credentials"
                todo "knife could not reach $KNIFE_CHEF_SERVER_URL: for a self-signed certificate run 'knife ssl fetch', then 'knife node list'"
            fi
        fi
    fi
fi

if has install-tanstack; then
    section "TanStack (install-tanstack)"
    if command -v tanstack > /dev/null 2>&1; then
        already "TanStack CLI $(tanstack --version 2>/dev/null) needs no account"
    else
        todo "tanstack not found: rerun dev-setup with install-tanstack"
    fi
    already "add-on keys (Clerk, Sentry, ...) live in each project's .env; deploy logins (wrangler, vercel, netlify) are per project, run them there when you pick a target"
fi

if has install-java; then
    section "Java (install-java)"
    if grep -q '^export JAVA_HOME=' ~/.bashrc; then
        already "JAVA_HOME in ~/.bashrc ($(grep -m1 '^export JAVA_HOME=' ~/.bashrc | cut -d'"' -f2))"
    else
        todo "JAVA_HOME missing from ~/.bashrc: rerun dev-setup with install-java"
    fi
    already "Maven Central and the Gradle plugin portal need no account; private repositories go in ~/.m2/settings.xml or ~/.gradle/gradle.properties per project"
fi

if has install-dotnet; then
    section ".NET SDK (install-dotnet)"
    if ! command -v dotnet > /dev/null 2>&1; then
        todo "dotnet not found: rerun dev-setup with install-dotnet"
    else
        if grep -q DOTNET_CLI_TELEMETRY_OPTOUT ~/.bashrc; then
            already "DOTNET_CLI_TELEMETRY_OPTOUT in ~/.bashrc"
        else
            bashrc_once 'DOTNET_CLI_TELEMETRY_OPTOUT' 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' && ok "DOTNET_CLI_TELEMETRY_OPTOUT=1 added to ~/.bashrc"
        fi
        # ASP.NET Core's Kestrel serves https://localhost with this per-user certificate. Creating it
        # is silent; trusting it system-wide ('--trust') edits the CA stores, so that stays a choice.
        if dotnet dev-certs https --check > /dev/null 2>&1; then
            already "ASP.NET Core HTTPS development certificate exists"
        else
            dotnet dev-certs https > /dev/null 2>&1 && ok "ASP.NET Core HTTPS development certificate created" || todo "dotnet dev-certs https"
        fi
        already "NuGet.org needs no account to restore packages; private feeds are per project (nuget.config). Optional: 'dotnet dev-certs https --trust' so browsers accept https://localhost"
    fi
fi

# v85: COM development under Wine (install-com). Nothing to log in to: COM registers into a local Wine
# prefix, not an account. Init confirms the prefix and the tools, and creates the prefix if setup could
# not (a network failure during wineboot).
if has install-com; then
    section "COM development under Wine (install-com)"
    COM_PREFIX="${DEV_COM_PREFIX:-$HOME/.local/share/wine/com}"
    if ! command -v wine > /dev/null 2>&1; then
        todo "wine not found: rerun dev-setup with install-com"
    else
        if [ -f "$COM_PREFIX/system.reg" ]; then
            already "COM Wine prefix ready ($COM_PREFIX); 'wine-com <exe>' runs in it"
        else
            echo "  creating the COM Wine prefix (setup could not); a minute..."
            mkdir -p "$(dirname "$COM_PREFIX")"
            WINEPREFIX="$COM_PREFIX" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -i > /dev/null 2>&1 || true
            # wineboot returns before the registry is on disk; wait for the prefix's wineserver to finish.
            WINEPREFIX="$COM_PREFIX" timeout 120 wineserver -w 2> /dev/null || true
            if [ -f "$COM_PREFIX/system.reg" ]; then
                ok "COM Wine prefix created at $COM_PREFIX"
            else
                todo "create the COM prefix by hand: WINEPREFIX=$COM_PREFIX wineboot -i"
            fi
        fi
        if command -v x86_64-w64-mingw32-widl > /dev/null 2>&1; then
            already "widl + mingw-w64 present: build servers with widl -> mingw gcc (dev-demo has a walkthrough)"
        else
            todo "widl/mingw missing: rerun dev-setup with install-com"
        fi
        command -v winetricks > /dev/null 2>&1 \
            && already "winetricks present (add redistributables per prefix: winetricks -q vcrun2019 mfc42)" \
            || skip "winetricks not installed (optional; rerun dev-setup with install-com)"
        already "DCOM is cross-machine: the server runs on a Windows laptop (the Windows bundle); build and register it there, reach it from here"
    fi
fi

# v85: DOS / Windows 3.x development (install-retro). No accounts. The one manual thing is your own
# Windows 3.1x media and any installers (Delphi 1), which go in ~/win31/install; init reports whether
# they are there yet.
if has install-retro; then
    section "DOS / Windows 3.x development (install-retro)"
    if ! command -v dosbox-x > /dev/null 2>&1; then
        todo "dosbox-x not found: rerun dev-setup with install-retro"
    else
        [ -x /opt/watcom/binl64/wcl ] \
            && already "Open Watcom in /opt/watcom (wcl, wcl386) and DOSBox-X ready; a new terminal has them on PATH" \
            || todo "Open Watcom missing from /opt/watcom: rerun dev-setup with install-retro"
        # v92: every guest is optional (you may want only some), so its media and install state are skips,
        # never todos. 'retro' prints the same table at any time.
        RETRO_H="$HOME/.local/lib/dev-retro/dev-retro"
        [ -x "$RETRO_H" ] || todo "the retro helper is missing (~/.local/lib/dev-retro): rerun dev-setup with install-retro (v92)"
        command -v qemu-system-i386 > /dev/null 2>&1 || todo "QEMU not found: rerun dev-setup with install-retro (v92 adds it for winnt40 and win2000)"
        if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            already "KVM is usable: winnt40 and win2000 run at close to native speed"
        elif [ -c /dev/kvm ]; then
            KVM_GROUP=$(stat -c %G /dev/kvm 2> /dev/null || echo kvm)
            if getent group "$KVM_GROUP" | cut -d: -f4 | tr ',' '\n' | grep -qx "$USER"; then
                todo "the $KVM_GROUP group (/dev/kvm) is not active yet: shut Linux down (right-click Terminal > Shut down Linux) and reopen it, for KVM in winnt40 / win2000"
            else
                todo "/dev/kvm belongs to group '$KVM_GROUP', which you are not in: rerun dev-setup with install-retro (or sudo usermod -aG $KVM_GROUP \$USER), then shut Linux down and reopen it"
            fi
        else
            skip "no /dev/kvm on this Chromebook: winnt40 and win2000 run in software emulation (slow; the 95, NT and 2000 guests belong on a machine with KVM)"
        fi
        retro_guest() {   # retro_guest CMD TITLE MEDIA_DIR PATTERN...
            local cmd=$1 title=$2 dir=$3 media state; shift 3
            media=$(for pat in "$@"; do find "$dir" -maxdepth 4 -type f -iname "$pat" 2> /dev/null; done | head -n 1)
            state=$([ -x "$RETRO_H" ] && "$RETRO_H" "$cmd" status 2> /dev/null | head -n 1)
            case "$state" in
                *"not installed"*|"") state="" ;;
                *"disk created"*) state="its disk is created" ;;
                *installed*) state="installed" ;;
            esac
            case "$state" in
                ?*) already "$title: $state ('$cmd' boots it; '$cmd help')" ;;
                *) if [ -n "$media" ]; then skip "$title: media is in $dir ($(basename "$media")): '$cmd setup' installs it"
                   else skip "$title (optional): put your media in $dir, then '$cmd setup'"; fi ;;
            esac
            [ -f "$HOME/$cmd/setup.skipped" ] && skip "$title: the last '$cmd setup' was refused: $(cat "$HOME/$cmd/setup.skipped")"
            # v93: program CDs (.iso) for the guest, F: inside it
            local apps; apps=$(find "$HOME/$cmd/install/apps" -maxdepth 1 -type f -iname '*.iso' 2> /dev/null | wc -l)
            if [ "$apps" -gt 0 ]; then already "$title: $apps program CD(s) in ~/$cmd/install/apps (F: in the guest; '$cmd cd list')"
            else skip "$title: program CDs (.iso, optional) go in ~/$cmd/install/apps, F: in the guest"; fi
            return 0
        }
        retro_guest win31 "Windows 3.1 (DOSBox-X)" "$HOME/win31/install/windows" setup.exe '*.img' '*.ima'
        retro_guest win95 "Windows 95 (DOSBox-X)" "$HOME/win95/install" '*.iso'
        retro_guest winnt40 "Windows NT 4.0 (QEMU)" "$HOME/winnt40/install" '*.iso' '*.img'
        retro_guest win2000 "Windows 2000 (QEMU)" "$HOME/win2000/install" '*.iso'
        # Delphi 1: its media sits with the Windows 3.1 installers (both routes use it).
        if [ -n "$(find "$HOME/.local/share/wine/delphi1/drive_c" -maxdepth 3 -ipath '*/delphi/bin/delphi.exe' 2> /dev/null | head -n 1)" ]; then
            already "Delphi 1 under Wine: set up ('delphi1' or its launcher icon; no integrated debugger, Database Desktop or BDE tables there: those run in win31)"
        elif [ -n "$(find ~/win31/install/apps -maxdepth 4 -type f -iname setup.exe 2> /dev/null | head -n 1)" ]; then
            skip "Delphi 1's setup is in ~/win31/install/apps: 'delphi1 setup' installs it under Wine (or install it inside win31, D:)"
        else
            skip "Delphi 1 (optional): copy its disks or CD into ~/win31/install/apps, then 'delphi1 setup' (Wine) or install it inside win31 (D:)"
        fi
        # v93: Delphi 3, 4, 5, 6 and 7 under Wine, one prefix each; every one is optional (a skip, never a todo).
        for DN in 3 4 5 6 7; do
            if [ -n "$(find "$HOME/.local/share/wine/delphi$DN/drive_c" -maxdepth 6 -type f -iname delphi32.exe 2> /dev/null | head -n 1)" ]; then
                already "Delphi $DN under Wine: set up ('delphi $DN' or its launcher icon)"
            elif [ -n "$(find "$HOME/delphi/install/$DN" -mindepth 1 -maxdepth 1 ! -name '.*' 2> /dev/null | head -n 1)" ]; then
                skip "Delphi $DN: its media is in ~/delphi/install/$DN: 'delphi $DN setup' installs it under Wine"
            else
                skip "Delphi $DN (optional): its CD (.iso or files) in ~/delphi/install/$DN, then 'delphi $DN setup'"
            fi
        done
        if [ -x "$RETRO_H" ] && grep -q '^sizes_cmd()' "$RETRO_H"; then
            if RETRO_SIZES=$("$RETRO_H" retro sizes 2>&1); then
                already "retro disk sizes: $(echo "$RETRO_SIZES" | grep -o 'RETRO_[A-Z0-9_]*=[0-9]* ([a-z. ]*)' | paste -sd ';' | sed 's/;/; /') (RETRO_EXCHANGE_MB / RETRO_WIN95_DISK_MB in $SECRETS)"
            else
                todo "a retro size in $SECRETS is out of range: $RETRO_SIZES"
            fi
        fi
    fi
fi

# v86: personal agents (install-hermes / install-openclaw). No account of their own: each needs a
# model, and init gives it one from secrets.env (AGENT_PROVIDER, AGENT_MODEL and a key, or
# OLLAMA_REMOTE). Both need a 64K-token context, more than an 8 GB Chromebook holds locally. Init only
# replaces a model it set itself (recorded in ~/.hermes/.dev-init-model and ~/.openclaw/.dev-init-model
# as "what init was asked for<TAB>what it set"): a model you picked with 'hermes model' or
# 'openclaw models set' stays. Channels, gateway services, Nous Portal and skills stay manual.
if has install-hermes || has install-openclaw; then
    # The remote Ollama's OpenAI-compatible URL, from OLLAMA_REMOTE (a name, an address or a URL).
    AGENT_OR_URL=""
    if [ -n "${OLLAMA_REMOTE:-}" ]; then
        AGENT_OR_URL=$OLLAMA_REMOTE
        case "$AGENT_OR_URL" in http://*|https://*) ;; *) AGENT_OR_URL="http://$AGENT_OR_URL" ;; esac
        _hp=${AGENT_OR_URL#*://}; _hp=${_hp%%/*}
        case "$_hp" in *:*) AGENT_OR_URL="${AGENT_OR_URL%%://*}://$_hp" ;; *) AGENT_OR_URL="${AGENT_OR_URL%%://*}://$_hp:11434" ;; esac
        unset _hp
    fi
    # agent_pick: sets AP (anthropic | openrouter | ollama-remote | skip, or empty), AM (the model) and
    # AW ("AP|AM|fingerprint"): the fingerprint is a short hash of the key or URL, never the key, so a
    # new key or model in secrets.env is applied on the next run and an unchanged one is left alone.
    # The agents' Anthropic key: AGENT_ANTHROPIC_API_KEY (not exported, so Claude Code keeps using your
    # subscription), else the exported ANTHROPIC_API_KEY.
    AGENT_ANTH_KEY="${AGENT_ANTHROPIC_API_KEY:-${ANTHROPIC_API_KEY:-}}"
    agent_pick() {
        local key=""
        AP=""; AM="${AGENT_MODEL:-}"
        case "${AGENT_PROVIDER:-auto}" in
            auto|"")
                if [ -n "$AGENT_ANTH_KEY" ]; then AP=anthropic
                elif [ -n "${OPENROUTER_API_KEY:-}" ]; then AP=openrouter
                elif [ -n "${OLLAMA_REMOTE:-}" ] && [ -n "$AM" ]; then AP=ollama-remote
                fi ;;
            anthropic)     [ -n "$AGENT_ANTH_KEY" ] && AP=anthropic ;;
            openrouter)    [ -n "${OPENROUTER_API_KEY:-}" ] && AP=openrouter ;;
            ollama-remote) [ -n "${OLLAMA_REMOTE:-}" ] && [ -n "$AM" ] && AP=ollama-remote ;;
            skip)          AP=skip ;;
        esac
        if [ -z "$AM" ]; then   # Sonnet, the everyday model; AGENT_MODEL picks another
            case "$AP" in anthropic) AM=claude-sonnet-5-5 ;; openrouter) AM=anthropic/claude-sonnet-5.5 ;; esac
        fi
        case "$AP" in
            anthropic) key=$AGENT_ANTH_KEY ;; openrouter) key=$OPENROUTER_API_KEY ;; ollama-remote) key=$AGENT_OR_URL ;;
        esac
        AW="$AP|$AM|$(printf '%s' "$key" | sha256sum | cut -c1-12)"
        return 0
    }
    agent_nomodel="give it a model in $SECRETS: AGENT_ANTHROPIC_API_KEY (or ANTHROPIC_API_KEY), OPENROUTER_API_KEY, or OLLAMA_REMOTE plus AGENT_MODEL (a model on that machine, served with a 64K context: OLLAMA_CONTEXT_LENGTH=65536 there); then rerun dev-init"
fi

if has install-hermes; then
    section "Personal agent: Hermes Agent (install-hermes)"
    if ! command -v hermes > /dev/null 2>&1; then
        todo "hermes not found: rerun dev-setup with install-hermes"
    else
        [ "$(hermes config get auth.adopt_external_logins 2> /dev/null)" = false ] \
            || { hermes config set auth.adopt_external_logins false > /dev/null 2>&1 && ok "Hermes keeps to its own logins (auth.adopt_external_logins=false)"; }
        agent_pick
        H_MARK="$HOME/.hermes/.dev-init-model"
        H_CUR_P=$(hermes config get model.provider 2> /dev/null)
        H_CUR_M=$(hermes config get model.default 2> /dev/null)
        H_OLD_W=$(cut -f1 "$H_MARK" 2> /dev/null)
        H_MINE=0
        { [ -z "$H_CUR_P" ] || [ "$H_CUR_P" = auto ]; } && H_MINE=1
        [ -f "$H_MARK" ] && [ "$(cut -f2 "$H_MARK")" = "$H_CUR_P|$H_CUR_M" ] && H_MINE=1
        case "$AP" in anthropic) H_PROV=anthropic ;; openrouter) H_PROV=openrouter ;; ollama-remote) H_PROV=custom ;; *) H_PROV="" ;; esac
        if [ "$AP" = skip ]; then
            skip "AGENT_PROVIDER=skip: init leaves Hermes' model alone ('hermes model' picks one)"
        elif [ "$H_MINE" = 0 ]; then
            already "Hermes uses $H_CUR_P / $H_CUR_M, which you chose; init leaves it ('hermes config set model.provider auto' hands it back)"
        elif [ -z "$AP" ]; then
            todo "Hermes has no model: $agent_nomodel"
        elif [ "$H_OLD_W" = "$AW" ] && [ "$H_CUR_P" = "$H_PROV" ]; then
            already "Hermes uses $AP / $AM"
        else
            H_ENV="$HOME/.hermes/.env"
            (umask 077; touch "$H_ENV")
            # hermes_env KEY [VALUE]: set (or, without VALUE, remove) one line of ~/.hermes/.env, mode 600,
            # without putting the value on a command line.
            hermes_env() { local tmp; tmp=$(mktemp "$H_ENV.XXXXXX"); grep -v "^$1=" "$H_ENV" > "$tmp" 2> /dev/null; [ $# -ge 2 ] && printf '%s=%s\n' "$1" "$2" >> "$tmp"; chmod 600 "$tmp"; mv "$tmp" "$H_ENV"; }
            hset() { hermes config set "$@" > /dev/null 2>&1 || H_OK=0; }
            hunset() { hermes config unset "$1" > /dev/null 2>&1 || true; }
            # A key init wrote for the provider it is moving away from goes: Hermes would keep it for fallbacks.
            case "${H_OLD_W%%|*}" in
                anthropic)  [ "$AP" != anthropic ] && hermes_env ANTHROPIC_API_KEY ;;
                openrouter) [ "$AP" != openrouter ] && hermes_env OPENROUTER_API_KEY ;;
            esac
            H_OK=1
            case "$AP" in
                anthropic)
                    hermes_env ANTHROPIC_API_KEY "$AGENT_ANTH_KEY"
                    hset model.provider anthropic; hunset model.base_url; hunset model.ollama_num_ctx ;;
                openrouter)
                    hermes_env OPENROUTER_API_KEY "$OPENROUTER_API_KEY"
                    hset model.provider openrouter; hset model.base_url https://openrouter.ai/api/v1; hunset model.ollama_num_ctx ;;
                ollama-remote)
                    hset model.provider custom; hset model.base_url "$AGENT_OR_URL/v1"
                    # Sent with every request, so the remote Ollama loads the model with a 64K window.
                    hset model.ollama_num_ctx 65536 ;;
            esac
            hset model.default "$AM"
            if [ "$H_OK" = 1 ]; then
                printf '%s\t%s\n' "$AW" "$H_PROV|$AM" > "$H_MARK"
                ok "Hermes uses $AP / $AM (from secrets.env); 'hermes' starts a chat"
                if [ "$AP" = ollama-remote ] && ! curl -fsS --max-time 5 "$AGENT_OR_URL/api/version" > /dev/null 2>&1; then
                    skip "OLLAMA_REMOTE ($AGENT_OR_URL) is not answering right now; Hermes reaches it once that machine is awake"
                fi
            else
                # Half-written: hand the choice back (provider auto), so the next run tries again.
                hermes config set model.provider auto > /dev/null 2>&1 || true
                todo "could not write Hermes' model settings (init retries next run): or pick one with 'hermes model'"
            fi
        fi
        skip "Nous Portal (Nous Research's model subscription) signs in through a browser: 'hermes portal'"
        skip "messaging (Telegram, Discord, Slack...): 'hermes gateway setup', with a bot account made for it; the always-on service is 'hermes gateway install' (plus 'loginctl enable-linger' so it outlives your login)"
    fi
fi

if has install-openclaw; then
    section "Personal agent: OpenClaw (install-openclaw)"
    if ! command -v openclaw > /dev/null 2>&1; then
        todo "openclaw not found: rerun dev-setup with install-openclaw"
    else
        agent_pick
        O_DIR="$HOME/.openclaw"; O_CFG="$O_DIR/openclaw.json"; O_MARK="$O_DIR/.dev-init-model"
        O_WHEN=$(jq -r '.wizard.lastRunAt // empty' "$O_CFG" 2> /dev/null)
        O_CUR=$(jq -r '.agents.defaults.model.primary // empty' "$O_CFG" 2> /dev/null)
        O_OLD_W=$(cut -f1 "$O_MARK" 2> /dev/null)
        O_MINE=0
        [ -z "$O_WHEN" ] && O_MINE=1
        [ -f "$O_MARK" ] && [ "$(cut -f2 "$O_MARK")" = "$O_CUR" ] && O_MINE=1
        O_WANT=""
        case "$AP" in anthropic) O_WANT="anthropic/$AM" ;; openrouter) O_WANT="openrouter/$AM" ;; esac
        if [ "$AP" = skip ]; then
            skip "AGENT_PROVIDER=skip: init leaves OpenClaw alone ('openclaw onboard' sets it up)"
        elif [ "$O_MINE" = 0 ]; then
            already "OpenClaw uses $O_CUR, which you chose; init leaves it"
        elif [ -z "$AP" ]; then
            todo "OpenClaw is not set up: $agent_nomodel"
        elif [ -n "$O_WHEN" ] && [ "$O_OLD_W" = "$AW" ]; then
            already "OpenClaw uses $O_CUR"
        elif [ -n "$O_WHEN" ] && [ -n "$O_WANT" ] && [ "${O_OLD_W%%|*}" = "$AP" ] && [ "${O_OLD_W##*|}" = "${AW##*|}" ]; then
            # Same provider and key, another model: no new onboarding, just the model.
            if openclaw models set "$O_WANT" > /dev/null 2>&1; then
                printf '%s\t%s\n' "$AW" "$O_WANT" > "$O_MARK"
                ok "OpenClaw now uses $O_WANT"
            else
                todo "could not set OpenClaw's model to $O_WANT: check the name with 'openclaw models list --all --provider $AP'"
            fi
        else
            # Onboarding without prompts: the key goes through the environment (never the command line),
            # the gateway stays on loopback with a token, and no daemon, channels, skills or hooks.
            O_ARGS=(onboard --non-interactive --accept-risk --mode local --flow manual --gateway-bind loopback --gateway-auth token
                    --skip-daemon --skip-channels --skip-skills --skip-search --skip-ui --skip-health --skip-hooks --json)
            case "$AP" in
                anthropic)     O_ARGS+=(--auth-choice apiKey) ;;
                openrouter)    O_ARGS+=(--auth-choice openrouter-api-key) ;;
                ollama-remote) O_ARGS+=(--auth-choice custom-api-key --custom-base-url "$AGENT_OR_URL/v1" --custom-model-id "$AM"
                                        --custom-api-key ollama --custom-text-input) ;;
            esac
            O_LOG="$HOME/.cache/dev-init/openclaw-onboard.log"; mkdir -p "$(dirname "$O_LOG")"
            O_DONE=0
            if (umask 077; ANTHROPIC_API_KEY="$AGENT_ANTH_KEY" openclaw "${O_ARGS[@]}" > "$O_LOG" 2>&1); then
                O_DONE=1
            else
                # Onboarding again over an existing credential saves the new one inactive and names the
                # command that tests it (one small request to the model) and switches to it.
                O_ID=$(grep -o 'models auth activate [^ ]* --agent main' "$O_LOG" | head -n 1 | awk '{print $4}')
                if [ -n "$O_ID" ] && (umask 077; openclaw models auth activate "$O_ID" --agent main >> "$O_LOG" 2>&1); then
                    O_DONE=1
                    [ -z "$O_WANT" ] && O_WANT="${O_ID%%:*}/$AM"
                fi
            fi
            if [ "$O_DONE" = 1 ]; then
                O_SET=1
                if [ -n "$O_WANT" ] && ! openclaw models set "$O_WANT" > /dev/null 2>&1; then
                    O_SET=0
                    todo "could not set OpenClaw's model to $O_WANT (init retries next run): check the name with 'openclaw models list --all'"
                fi
                if [ "$AP" = ollama-remote ]; then
                    # OpenClaw assumes a 128K window for a custom model; the remote Ollama serves 64K, so say
                    # so, or OpenClaw lets a long session grow past what the model sees.
                    O_PID=$(jq -r --arg u "$AGENT_OR_URL/v1" '.models.providers // {} | to_entries[] | select(.value.baseUrl == $u) | .key' "$O_CFG" 2> /dev/null | head -n 1)
                    O_IDX=$(jq -r --arg p "$O_PID" --arg m "$AM" '.models.providers[$p].models // [] | map(.id) | index($m) // empty' "$O_CFG" 2> /dev/null)
                    [ -n "$O_PID" ] && [ -n "$O_IDX" ] \
                        && openclaw config set "models.providers.$O_PID.models[$O_IDX].contextWindow" 65536 --strict-json > /dev/null 2>&1
                fi
                O_NOW=$(jq -r '.agents.defaults.model.primary // empty' "$O_CFG" 2> /dev/null)
                # A model that did not take is recorded as a retry: still init's to change, not "already".
                if [ "$O_SET" = 1 ]; then printf '%s\t%s\n' "$AW" "$O_NOW" > "$O_MARK"; else printf 'retry\t%s\n' "$O_NOW" > "$O_MARK"; fi
                [ "$O_SET" = 1 ] && ok "OpenClaw set up with $O_NOW (gateway on loopback with a token); 'openclaw chat' starts a chat"
            else
                todo "OpenClaw's onboarding failed (log: $O_LOG); 'openclaw onboard' runs it with prompts"
            fi
        fi
        # OpenClaw runs any shell command without asking by default (exec security full, ask off), as you,
        # and the Crostini user has passwordless sudo. Unless you chose a mode yourself, it asks first.
        if [ -f "$O_CFG" ] && [ -n "$O_WHEN$(jq -r '.wizard.lastRunAt // empty' "$O_CFG" 2> /dev/null)" ]; then
            O_MODE=$(jq -r '.tools.exec.mode // empty' "$O_CFG" 2> /dev/null)
            if [ -z "$O_MODE" ] && [ -z "$(jq -r '.tools.exec.security // .tools.exec.ask // empty' "$O_CFG" 2> /dev/null)" ]; then
                openclaw config set tools.exec.mode ask > /dev/null 2>&1 && ok "OpenClaw asks before running a command that is not on its allowlist (tools.exec.mode=ask)"
            else
                already "OpenClaw's command policy: ${O_MODE:-custom (tools.exec.security / ask)}"
            fi
        fi
        if [ -f "$O_CFG" ] && [ "$(jq -r '.telemetry.enabled | tostring' "$O_CFG" 2> /dev/null)" != false ]; then
            openclaw telemetry off > /dev/null 2>&1 && ok "OpenClaw's anonymous feature statistics recorded as off"
        fi
        skip "channels: 'openclaw channels add' (use a bot account made for it); the always-on gateway service: 'openclaw gateway install'"
        skip "ClawHub skills: none installed; read a skill's files before 'openclaw skills install' (malicious ones have been found there)"
    fi
fi

# =================================================================
# SUMMARY
# =================================================================
echo
echo "================================================================="
if [ ${#TODO[@]} -eq 0 ]; then
    echo "Init Version 93 complete: nothing left to do. 🎉"
else
    echo "Init Version 93 complete. Still manual (${#TODO[@]}):"
    printf '  - %s\n' "${TODO[@]}"
fi
echo
echo "Open a new terminal (or 'source ~/.bashrc') so the exported keys apply, then rerun the"
echo "test script to confirm: ./dev-test-chromebook.sh $*"
echo "================================================================="
