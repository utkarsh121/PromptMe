#!/usr/bin/env bash
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  PromptMe Lite — One-shot Installer                                         │
# │                                                                             │
# │  curl -fsSL https://raw.githubusercontent.com/utkarsh121/PromptMe/         │
# │             lite-mode/installer.sh | bash                                   │
# │                                                                             │
# │  Also works as:  bash installer.sh                                          │
# │                  sudo bash installer.sh                                     │
# │  Supports: Ubuntu/Debian (apt) · RHEL/Fedora/CentOS (dnf/yum)              │
# │  GPU:       auto-detects NVIDIA/AMD, enables GPU passthrough to Ollama      │
# └─────────────────────────────────────────────────────────────────────────────┘

# NOTE: We intentionally do NOT use `set -euo pipefail` globally.
# Many probe commands (grep -q, command -v, systemctl is-active …) return
# nonzero when "not found" — which is expected, not an error.  We use
# explicit || true / || { fail …; exit 1; } guards throughout.

export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

###############################################################################
# ── Colour & output helpers ──────────────────────────────────────────────────
###############################################################################

# Detect colour capability BEFORE the exec→tee redirect changes stdout.
[[ -t 1 ]] && _CLR=1 || _CLR=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'
# Suppress ANSI if not a tty (keeps log file readable).
if [[ $_CLR -eq 0 ]]; then
    RED=''; GREEN=''; YELLOW=''; CYAN=''; DIM=''; BOLD=''; RESET=''
fi

_ts()    { date '+%Y-%m-%d %H:%M:%S'; }
info()   { printf "%s ${CYAN}[INFO]${RESET}   %s\n" "$(_ts)" "$*"; }
ok()     { printf "%s ${GREEN}[ OK ]${RESET}   %s\n" "$(_ts)" "$*"; }
warn()   { printf "%s ${YELLOW}[WARN]${RESET}   %s\n" "$(_ts)" "$*"; }
detail() { printf "%s ${DIM}[....${RESET}]   %s\n" "$(_ts)" "$*"; }
fail()   { printf "%s ${RED}[FAIL]${RESET}   %s\n" "$(_ts)" "$*" >&2; }

STEP=0; TOTAL_STEPS=11
step_header() {
    STEP=$(( STEP + 1 ))
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  [${STEP}/${TOTAL_STEPS}]  $*"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

###############################################################################
# ── Logging setup ─────────────────────────────────────────────────────────────
# All stdout/stderr is tee'd to the log file from this point onwards.
###############################################################################

LOG_FILE="/var/log/promptme-install.log"

_setup_log() {
    # Try direct write → sudo write → /tmp fallback
    if touch "$LOG_FILE" 2>/dev/null; then
        chmod 644 "$LOG_FILE" 2>/dev/null || true
    elif sudo touch "$LOG_FILE" 2>/dev/null; then
        sudo chmod 666 "$LOG_FILE"   # world-writable so tee (running as real user) can write
    else
        LOG_FILE="/tmp/promptme-install.log"
        touch "$LOG_FILE"
    fi
}
_setup_log

exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════════════"
echo -e "  PromptMe Lite — Installer  ($(date '+%Y-%m-%d %H:%M:%S'))"
echo -e "════════════════════════════════════════════════════════════════════${RESET}"
info "Logging to: $LOG_FILE"

###############################################################################
# ── Error / exit traps ────────────────────────────────────────────────────────
###############################################################################

_INSTALL_OK=false

_on_error() {
    local code=$? line=$1
    echo ""
    fail "Installer failed at line ${line} (exit code: ${code})."
    fail "Review the log for details: ${LOG_FILE}"
    fail "Fix the issue above, then re-run the installer — it is safe to retry."
    exit "$code"
}
trap '_on_error $LINENO' ERR

_on_exit() {
    sleep 0.2   # let tee flush
    echo ""
    if [[ "$_INSTALL_OK" == "true" ]]; then
        ok "Installer exited cleanly."
    else
        warn "Installer exited with errors.  Full log: ${LOG_FILE}"
    fi
}
trap '_on_exit' EXIT

###############################################################################
# ── Privilege helpers ─────────────────────────────────────────────────────────
###############################################################################

# Run a command as root (directly if already root, via sudo otherwise).
priv() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Run a command as the real (non-root) user.
# Populated after _resolve_user runs.
as_user() {
    if [[ $EUID -eq 0 && "${REAL_USER:-root}" != "root" ]]; then
        su -s /bin/bash - "$REAL_USER" -c "$(printf '%q ' "$@")"
    else
        "$@"
    fi
}

###############################################################################
# ── User resolution ───────────────────────────────────────────────────────────
# Handles: regular user, sudo bash, sudo su, direct root, root-group member.
###############################################################################

REAL_USER=""
REAL_HOME=""
CREATE_SERVICE_ACCOUNT=false

_resolve_user() {
    local _candidate=""

    # 1. SUDO_USER — most reliable for `sudo bash installer.sh`
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        _candidate="$SUDO_USER"
        detail "User candidate via SUDO_USER: $_candidate"
    fi

    # 2. logname — survives `sudo su` (reads /var/run/utmp)
    if [[ -z "$_candidate" ]]; then
        local _ln
        _ln=$(logname 2>/dev/null || true)
        if [[ -n "$_ln" && "$_ln" != "root" ]]; then
            _candidate="$_ln"
            detail "User candidate via logname: $_candidate"
        fi
    fi

    # 3. `who am i` — shows the original login user via controlling terminal
    if [[ -z "$_candidate" ]]; then
        local _who
        _who=$(who am i 2>/dev/null | awk '{print $1}' || true)
        if [[ -n "$_who" && "$_who" != "root" ]]; then
            _candidate="$_who"
            detail "User candidate via who am i: $_candidate"
        fi
    fi

    # 4. Parent process environment — useful for `sudo su` with no tty
    if [[ -z "$_candidate" ]]; then
        local _ppid _env_user
        _ppid=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ' || true)
        if [[ -n "$_ppid" && -f "/proc/$_ppid/environ" ]]; then
            _env_user=$(tr '\0' '\n' < "/proc/$_ppid/environ" 2>/dev/null \
                        | grep '^USER=' | cut -d= -f2 || true)
            if [[ -n "$_env_user" && "$_env_user" != "root" ]]; then
                _candidate="$_env_user"
                detail "User candidate via parent environ: $_candidate"
            fi
        fi
    fi

    # 5. Interactive prompt (only when stdin is a real terminal)
    if [[ -z "$_candidate" && -t 0 ]]; then
        echo ""
        warn "Could not auto-detect the real user account."
        read -rp "  Enter the username to own this installation (blank = create service account): " _candidate
        _candidate="${_candidate// /}"   # strip spaces
    fi

    # 6. Fall back to a dedicated service account
    if [[ -z "$_candidate" ]]; then
        warn "No real user detected — will create/use 'promptme' service account."
        _candidate="promptme"
        CREATE_SERVICE_ACCOUNT=true
    fi

    # Validate the resolved user exists (skip validation for the service account
    # that will be created in step 2).
    if [[ "$CREATE_SERVICE_ACCOUNT" == "false" ]] && ! id "$_candidate" &>/dev/null; then
        fail "Resolved user '$_candidate' does not exist.  Aborting."
        exit 1
    fi

    REAL_USER="$_candidate"
    REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || eval echo "~$REAL_USER")

    ok "Installing for user: ${BOLD}${REAL_USER}${RESET}  (home: ${REAL_HOME})"
    if [[ $EUID -ne 0 ]]; then
        info "Non-root execution — sudo will be used for privileged operations."
    fi
}

_resolve_user

###############################################################################
# ── Idempotency helpers ───────────────────────────────────────────────────────
###############################################################################

INSTALL_DIR="${PROMPTME_DIR:-/opt/promptme}"
STATE_DIR="${INSTALL_DIR}/.install-state"

mark_done()    { priv mkdir -p "$STATE_DIR"; priv touch "$STATE_DIR/$1"; }
already_done() { [[ -f "$STATE_DIR/$1" ]]; }

###############################################################################
# ── Package manager detection ─────────────────────────────────────────────────
###############################################################################

echo -e "\n${BOLD}━━━ Detecting system ━━━${RESET}"

if command -v apt-get &>/dev/null; then
    PKG="apt"
elif command -v dnf &>/dev/null; then
    PKG="dnf"
elif command -v yum &>/dev/null; then
    PKG="yum"
else
    fail "No supported package manager found (apt / dnf / yum).  Aborting."
    exit 1
fi

OS_ID=$(. /etc/os-release 2>/dev/null && echo "${ID:-linux}" || echo "linux")
OS_VER=$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-}" || echo "")

info "Package manager : $PKG"
info "OS              : $OS_ID $OS_VER"
info "Architecture    : $(uname -m)"
info "Kernel          : $(uname -r)"

###############################################################################
# ── [1/11]  System prerequisites ─────────────────────────────────────────────
###############################################################################

step_header "System prerequisites"

if already_done "prereqs"; then
    ok "Prerequisites already installed (cached state)"
else
    info "Updating and upgrading system packages (may take a few minutes) …"
    if [[ "$PKG" == "apt" ]]; then
        priv apt-get update -qq
        priv apt-get upgrade -y -qq
        priv apt-get install -y -qq \
            curl unzip python3 python3-pip python3-venv \
            ca-certificates gnupg lsb-release
    else
        priv "$PKG" upgrade -y -q
        priv "$PKG" install -y -q \
            curl unzip python3 python3-pip python3-venv \
            ca-certificates
    fi
    mark_done "prereqs"
    ok "Prerequisites installed"
fi

###############################################################################
# ── [2/11]  Service account (only when no real user could be detected) ────────
###############################################################################

step_header "User / service account"

if [[ "$CREATE_SERVICE_ACCOUNT" == "true" ]]; then
    if id promptme &>/dev/null; then
        ok "Service account 'promptme' already exists"
    else
        priv useradd --system --create-home \
            --home-dir /home/promptme \
            --shell /bin/bash \
            --comment "PromptMe service account" \
            promptme
        ok "Created service account: promptme"
    fi
    REAL_HOME="/home/promptme"
else
    ok "Using existing account: $REAL_USER"
fi

###############################################################################
# ── [3/11]  Docker ────────────────────────────────────────────────────────────
###############################################################################

step_header "Docker"

if command -v docker &>/dev/null; then
    ok "Docker already installed ($(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ','))"
else
    if already_done "docker"; then
        ok "Docker install marked done — skipping"
    else
        info "Downloading Docker installer …"
        # IMPORTANT: We download to a temp file rather than piping directly into
        # `sh`, because when THIS script runs via `curl | bash`, bash's stdin is
        # the pipe carrying this script.  A nested `curl URL | sh` would compete
        # for that same stdin and corrupt both scripts.
        _docker_tmp=$(mktemp /tmp/get-docker-XXXXXX.sh)
        curl -fsSL https://get.docker.com -o "$_docker_tmp"
        info "Running Docker installer …"
        priv sh "$_docker_tmp"
        priv rm -f "$_docker_tmp"
        mark_done "docker"
        ok "Docker installed"
    fi
fi

# Add real user to docker group so they can use docker without sudo post-install.
if ! groups "$REAL_USER" 2>/dev/null | grep -qw docker; then
    priv usermod -aG docker "$REAL_USER" 2>/dev/null || true
    warn "Added '$REAL_USER' to the docker group."
    warn "You will need to log out and back in before running docker without sudo."
fi

# Ensure the daemon is running.
priv systemctl enable --now docker 2>/dev/null || true

# Verify docker is accessible (we run as root/priv, so group membership is moot here).
priv docker info &>/dev/null || {
    fail "Docker daemon is not responding.  Check: sudo journalctl -u docker"
    exit 1
}
ok "Docker daemon is running"

###############################################################################
# ── [4/11]  GPU detection ─────────────────────────────────────────────────────
###############################################################################

step_header "GPU detection"

GPU_FOUND=false; GPU_TYPE="none"; GPU_FLAGS=""; GPU_INFO="none"

if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    GPU_FOUND=true
    GPU_TYPE="nvidia"
    GPU_FLAGS="--gpus all"
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total \
               --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
    ok "NVIDIA GPU detected: $GPU_INFO"
elif command -v rocm-smi &>/dev/null && rocm-smi &>/dev/null; then
    GPU_FOUND=true
    GPU_TYPE="amd"
    GPU_FLAGS="--device=/dev/kfd --device=/dev/dri"
    GPU_INFO=$(rocm-smi --showproductname 2>/dev/null | grep -i "card\|gpu" | head -1 | sed 's/.*: //' || echo "unknown")
    ok "AMD GPU detected via rocm-smi: $GPU_INFO"
elif [[ -e /dev/kfd ]]; then
    # /dev/kfd present but rocm-smi not installed yet — AMD ROCm device confirmed via kernel driver
    GPU_FOUND=true
    GPU_TYPE="amd"
    GPU_FLAGS="--device=/dev/kfd --device=/dev/dri"
    GPU_INFO=$(lspci 2>/dev/null | grep -i "amd\|ati\|radeon\|instinct" | head -1 | sed 's/.*: //' || echo "AMD GPU (ROCm)")
    ok "AMD GPU detected via /dev/kfd: $GPU_INFO"
else
    # Last-resort lspci check — catches MxGPU/SR-IOV AMD vGPUs where /dev/kfd may not exist
    _lspci_amd=$(lspci 2>/dev/null | grep -iE "amd|ati|radeon|instinct" | grep -iv "audio\|usb\|sata" | head -1 || true)
    _lspci_nvidia=$(lspci 2>/dev/null | grep -iE "nvidia" | grep -iv "audio" | head -1 || true)
    if [[ -n "$_lspci_nvidia" ]]; then
        # NVIDIA GPU visible in PCI but nvidia-smi failed — driver not loaded
        GPU_FOUND=false
        GPU_TYPE="nvidia-no-driver"
        GPU_INFO="$_lspci_nvidia"
        warn "NVIDIA GPU found in lspci but nvidia-smi failed — driver may not be loaded; falling back to CPU"
    elif [[ -n "$_lspci_amd" ]]; then
        # AMD/Instinct visible in PCI but no ROCm stack — attempt device passthrough anyway
        GPU_FOUND=true
        GPU_TYPE="amd"
        GPU_FLAGS="--device=/dev/dri"
        # /dev/kfd may not exist without ROCm driver; omit it to avoid docker run failure
        [[ -e /dev/kfd ]] && GPU_FLAGS="--device=/dev/kfd --device=/dev/dri"
        GPU_INFO="$_lspci_amd (ROCm driver not confirmed)"
        warn "AMD GPU found via lspci — ROCm driver not confirmed; attempting DRI passthrough: $GPU_INFO"
    else
        info "No GPU detected — running CPU-only (Lite mode works fine on CPU)"
    fi
fi

###############################################################################
# ── [5/11]  NVIDIA Container Toolkit (NVIDIA GPU only) ───────────────────────
###############################################################################

step_header "NVIDIA Container Toolkit"

if [[ "$GPU_TYPE" != "nvidia" ]]; then
    info "GPU type is '${GPU_TYPE}' — skipping NVIDIA Container Toolkit"
else
    _nct_installed=false
    dpkg -l nvidia-container-toolkit &>/dev/null 2>&1 && _nct_installed=true || true
    rpm -q  nvidia-container-toolkit &>/dev/null 2>&1 && _nct_installed=true || true

    if [[ "$_nct_installed" == "true" ]] || already_done "nct"; then
        ok "NVIDIA Container Toolkit already installed"
    else
        info "Installing NVIDIA Container Toolkit …"
        _tmp_list=$(mktemp /tmp/nvidia-XXXXXX.list)
        _tmp_key=$(mktemp /tmp/nvidia-XXXXXX.gpg)

        if [[ "$PKG" == "apt" ]]; then
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
                | gpg --dearmor -o "$_tmp_key"
            priv cp "$_tmp_key" \
                /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            priv chmod 644 \
                /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

            curl -sL \
                https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
                | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
                > "$_tmp_list"
            priv cp "$_tmp_list" \
                /etc/apt/sources.list.d/nvidia-container-toolkit.list
            priv apt-get update -qq
            priv apt-get install -y -qq nvidia-container-toolkit
        else
            curl -sL \
                https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
                > "$_tmp_list"
            priv cp "$_tmp_list" /etc/yum.repos.d/nvidia-container-toolkit.repo
            priv "$PKG" install -y -q nvidia-container-toolkit
        fi

        rm -f "$_tmp_list" "$_tmp_key"
        priv nvidia-ctk runtime configure --runtime=docker
        priv systemctl restart docker
        mark_done "nct"
        ok "NVIDIA Container Toolkit installed"
    fi
fi

###############################################################################
# ── [6/11]  Ollama container ──────────────────────────────────────────────────
###############################################################################

step_header "Ollama container"

OLLAMA_CONTAINER="ollama"
OLLAMA_PORT=11434

# Pull the Ollama Docker image explicitly before attempting container operations.
# docker run would auto-pull, but doing it separately gives visible progress and
# ensures the image is present before any container state logic runs.
if priv docker image inspect ollama/ollama &>/dev/null; then
    ok "ollama/ollama image already present"
else
    info "Pulling ollama/ollama Docker image (≈ 1 GB) …"
    priv docker pull ollama/ollama
    ok "ollama/ollama image pulled"
fi

# Use &>/dev/null to suppress both stdout and stderr from docker inspect —
# some Docker versions write errors to stdout which would pollute the variable.
if ! priv docker inspect "$OLLAMA_CONTAINER" &>/dev/null; then
    # Container does not exist — create and start it.
    info "Creating Ollama container '${OLLAMA_CONTAINER}' (GPU: ${GPU_FOUND}) …"
    # shellcheck disable=SC2086
    priv docker run -d \
        --name "$OLLAMA_CONTAINER" \
        --restart unless-stopped \
        -p "${OLLAMA_PORT}:11434" \
        -v ollama:/root/.ollama \
        $GPU_FLAGS \
        ollama/ollama
    ok "Ollama container '${OLLAMA_CONTAINER}' created and started"
else
    _ollama_state=$(priv docker inspect -f '{{.State.Status}}' "$OLLAMA_CONTAINER" 2>/dev/null || true)
    if [[ "$_ollama_state" == "running" ]]; then
        ok "Ollama container '${OLLAMA_CONTAINER}' already running"
    else
        info "Ollama container '${OLLAMA_CONTAINER}' exists (state: ${_ollama_state}) — starting …"
        priv docker start "$OLLAMA_CONTAINER"
        ok "Ollama container '${OLLAMA_CONTAINER}' started"
    fi
fi

# Wait for Ollama API to become ready.
info "Waiting for Ollama API (up to 60 s) …"
_ollama_ready=false
for _i in $(seq 1 30); do
    if curl -sf "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null; then
        _ollama_ready=true
        break
    fi
    detail "  attempt ${_i}/30 …"
    sleep 2
done

if [[ "$_ollama_ready" == "false" ]]; then
    fail "Ollama did not become ready within 60 s."
    fail "Inspect with:  sudo docker logs $OLLAMA_CONTAINER"
    exit 1
fi
ok "Ollama API is up at http://localhost:${OLLAMA_PORT}"

###############################################################################
# ── [7/11]  Pull models ───────────────────────────────────────────────────────
###############################################################################

step_header "Pulling models"

warn "Model downloads can take several minutes depending on internet speed."
warn "phi3:mini ≈ 2.2 GB  ·  granite3.1-moe:1b ≈ 800 MB"

MODELS=("phi3:mini" "granite3.1-moe:1b")
for _model in "${MODELS[@]}"; do
    # `ollama list` output includes the model name before the colon tag.
    _model_base="${_model%%:*}"
    if priv docker exec "$OLLAMA_CONTAINER" ollama list 2>/dev/null \
            | grep -q "$_model_base"; then
        ok "Model already present: $_model"
    else
        info "Pulling $_model …"
        priv docker exec "$OLLAMA_CONTAINER" ollama pull "$_model"
        ok "Pulled: $_model"
    fi
done

###############################################################################
# ── [8/11]  Download PromptMe application files ──────────────────────────────
###############################################################################

step_header "PromptMe application files"

REPO_ZIP="https://github.com/utkarsh121/PromptMe/archive/refs/heads/lite-mode.zip"
_zip_tmp=$(mktemp /tmp/promptme-XXXXXX.zip)

info "Downloading PromptMe (lite-mode) …"
curl -fsSL "$REPO_ZIP" -o "$_zip_tmp"
ok "Download complete"

info "Installing to $INSTALL_DIR …"
priv rm -rf "$INSTALL_DIR"
priv mkdir -p "$INSTALL_DIR"

# GitHub zips extract to a subdirectory named <repo>-<branch>/
_extract_tmp=$(mktemp -d /tmp/promptme-extract-XXXXXX)
unzip -q "$_zip_tmp" -d "$_extract_tmp"
priv cp -r "$_extract_tmp"/PromptMe-lite-mode/. "$INSTALL_DIR/"
rm -rf "$_zip_tmp" "$_extract_tmp"

priv chown -R "$REAL_USER":"$REAL_USER" "$INSTALL_DIR"
ok "PromptMe files installed to $INSTALL_DIR"

###############################################################################
# ── [9/11]  Python virtual environment & dependencies ────────────────────────
###############################################################################

step_header "Python dependencies"

VENV="$INSTALL_DIR/.venv"
_pip="$VENV/bin/pip"
_python="$VENV/bin/python"

# Idempotency: check for a key package rather than just the venv dir,
# because a partial pip install (e.g. network drop during torch download)
# leaves the venv in a broken state.
_deps_ok=false
if [[ -f "$_python" ]]; then
    as_user "$_python" -c "import flask, torch, faiss" 2>/dev/null \
        && _deps_ok=true || true
fi

if [[ "$_deps_ok" == "true" ]]; then
    ok "Python dependencies already installed"
else
    if [[ ! -d "$VENV" ]]; then
        info "Creating Python virtual environment …"
        as_user python3 -m venv "$VENV"
        ok "Virtual environment created at $VENV"
    fi

    info "Upgrading pip …"
    as_user "$_pip" install --upgrade pip -q

    warn "Installing Python packages (torch alone is ~2 GB — this may take a while) …"
    as_user "$_pip" install -r "$INSTALL_DIR/requirements.txt" -q
    ok "Python packages installed"
fi

# Re-assert ownership (pip may write cache files as root if priv was used).
priv chown -R "$REAL_USER":"$REAL_USER" "$INSTALL_DIR"

###############################################################################
# ── [10/11]  Systemd service ──────────────────────────────────────────────────
###############################################################################

step_header "Systemd service"

SERVICE_FILE="/etc/systemd/system/promptme.service"

_REAL_GRP=$(id -gn "$REAL_USER" 2>/dev/null || echo "$REAL_USER")

priv bash -c "cat > '$SERVICE_FILE'" <<EOF
[Unit]
Description=PromptMe Lite — OWASP LLM Top 10 CTF Lab
Documentation=https://github.com/utkarsh121/PromptMe
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=${REAL_USER}
Group=${_REAL_GRP}
WorkingDirectory=${INSTALL_DIR}
Environment="OLLAMA_BASE_URL=http://localhost:${OLLAMA_PORT}"
ExecStart=${_python} ${INSTALL_DIR}/main.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=promptme

[Install]
WantedBy=multi-user.target
EOF

priv systemctl daemon-reload
priv systemctl enable promptme
priv systemctl restart promptme
ok "systemd service enabled and started"

###############################################################################
# ── [11/11]  Desktop shortcut ─────────────────────────────────────────────────
###############################################################################

step_header "Desktop shortcut"

DESKTOP_DIR="$REAL_HOME/Desktop"
SHORTCUT="$DESKTOP_DIR/PromptMe.desktop"

if [[ -d "$DESKTOP_DIR" ]]; then
    as_user bash -c "cat > '$SHORTCUT'" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=PromptMe Lab
Comment=OWASP LLM Top 10 CTF Challenges
Exec=xdg-open http://localhost:5000
Icon=utilities-terminal
Terminal=false
Categories=Education;Security;
EOF
    priv chmod +x "$SHORTCUT"
    ok "Desktop shortcut created: $SHORTCUT"
else
    info "No Desktop directory found — skipping shortcut"
fi

###############################################################################
# ── Post-install verification ─────────────────────────────────────────────────
###############################################################################

echo ""
info "Verifying installation …"

# Give Flask a moment to bind.
_ready=false
for _i in $(seq 1 15); do
    if curl -sf "http://localhost:5000" &>/dev/null; then
        _ready=true; break
    fi
    sleep 2
done

if [[ "$_ready" == "true" ]]; then
    ok "PromptMe dashboard is responding at http://localhost:5000"
else
    warn "Dashboard not yet reachable — it may still be starting."
    warn "Check with:  systemctl status promptme"
fi

###############################################################################
# ── Summary ───────────────────────────────────────────────────────────────────
###############################################################################

_INSTALL_OK=true

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════════════"
echo -e "  Installation complete  🎉"
echo -e "════════════════════════════════════════════════════════════════════${RESET}"
echo ""
printf "  %-22s %s\n" "Dashboard:"        "http://localhost:5000"
printf "  %-22s %s\n" "Challenges:"       "http://localhost:5001 – 5010"
printf "  %-22s %s\n" "Models:"           "phi3:mini + granite3.1-moe:1b"
printf "  %-22s %s\n" "GPU acceleration:" "${GPU_FOUND} [${GPU_TYPE}]  ($GPU_INFO)"
printf "  %-22s %s\n" "Install directory:" "$INSTALL_DIR"
printf "  %-22s %s\n" "Running as user:"  "$REAL_USER"
printf "  %-22s %s\n" "Install log:"      "$LOG_FILE"
echo ""
printf "  %-22s %s\n" "Service status:"   "systemctl status promptme"
printf "  %-22s %s\n" "Live logs:"        "journalctl -fu promptme"
echo ""

if ! groups "$REAL_USER" 2>/dev/null | grep -qw docker; then
    echo -e "  ${YELLOW}NOTE:${RESET} '$REAL_USER' was added to the docker group."
    echo -e "        Log out and back in to run docker without sudo."
    echo ""
fi

echo -e "  Open ${CYAN}http://localhost:5000${RESET} in your browser to get started."
echo ""
