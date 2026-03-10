#!/usr/bin/env bash
# PromptMe Lite — Single-shot Installer
# Supports: Ubuntu/Debian (apt), RHEL/Fedora (dnf/yum)
# GPU: Detects NVIDIA GPU and installs NVIDIA Container Toolkit if found

set -euo pipefail

###############################################################################
# Colours & helpers
###############################################################################
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}"; }

###############################################################################
# 0. Detect package manager
###############################################################################
section "Detecting system"
if command -v apt-get &>/dev/null; then
    PKG="apt"; INSTALL="apt-get install -y -qq"
elif command -v dnf &>/dev/null; then
    PKG="dnf"; INSTALL="dnf install -y -q"
elif command -v yum &>/dev/null; then
    PKG="yum"; INSTALL="yum install -y -q"
else
    error "No supported package manager found (apt/dnf/yum). Aborting."
fi
info "Package manager: $PKG"
OS_ID=$(. /etc/os-release 2>/dev/null && echo "${ID}" || echo "linux")
OS_VER=$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-}" || echo "")
info "OS: $OS_ID $OS_VER"

###############################################################################
# 1. Preflight — system packages
###############################################################################
section "Installing prerequisites"
if [[ "$PKG" == "apt" ]]; then
    apt-get update -qq
    $INSTALL curl git python3 python3-pip python3-venv ca-certificates gnupg lsb-release
else
    $INSTALL curl git python3 python3-pip ca-certificates
fi
ok "Prerequisites ready"

###############################################################################
# 2. Docker
###############################################################################
section "Docker"
if command -v docker &>/dev/null; then
    ok "Docker already installed ($(docker --version | cut -d' ' -f3 | tr -d ','))"
else
    info "Installing Docker via get.docker.com …"
    curl -fsSL https://get.docker.com | sh
    # Add current user to docker group (takes effect after re-login)
    if id -nG "$USER" | grep -qv docker 2>/dev/null; then
        usermod -aG docker "$USER" 2>/dev/null || true
        warn "Added $USER to docker group. You may need to log out and back in."
    fi
    ok "Docker installed"
fi
# Ensure Docker daemon is running
systemctl enable --now docker 2>/dev/null || true
docker info &>/dev/null || error "Docker daemon is not running. Start it and re-run the installer."

###############################################################################
# 3. GPU detection
###############################################################################
section "GPU detection"
GPU_FOUND=false
GPU_FLAGS=""

if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    GPU_FOUND=true
    GPU_FLAGS="--gpus all"
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
    ok "NVIDIA GPU detected: $GPU_INFO"
else
    info "No NVIDIA GPU detected (or nvidia-smi not found) — running CPU-only"
fi

###############################################################################
# 4. NVIDIA Container Toolkit (only if GPU detected)
###############################################################################
if [[ "$GPU_FOUND" == "true" ]]; then
    section "NVIDIA Container Toolkit"
    if dpkg -l nvidia-container-toolkit &>/dev/null 2>&1 || \
       rpm -q nvidia-container-toolkit &>/dev/null 2>&1; then
        ok "nvidia-container-toolkit already installed"
    else
        info "Installing NVIDIA Container Toolkit …"
        if [[ "$PKG" == "apt" ]]; then
            # Official NVIDIA repo for Debian/Ubuntu
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
              | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
              | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
              | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
            apt-get update -qq
            $INSTALL nvidia-container-toolkit
        elif [[ "$PKG" =~ ^(dnf|yum)$ ]]; then
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
              | tee /etc/yum.repos.d/nvidia-container-toolkit.repo
            $INSTALL nvidia-container-toolkit
        fi
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker
        ok "NVIDIA Container Toolkit installed"
    fi
fi

###############################################################################
# 5. Launch Ollama container
###############################################################################
section "Ollama"
OLLAMA_CONTAINER="ollama"
OLLAMA_PORT=11434

if docker ps -a --format '{{.Names}}' | grep -q "^${OLLAMA_CONTAINER}$"; then
    STATE=$(docker inspect -f '{{.State.Status}}' "$OLLAMA_CONTAINER")
    if [[ "$STATE" == "running" ]]; then
        ok "Ollama container already running"
    else
        info "Starting existing Ollama container …"
        docker start "$OLLAMA_CONTAINER"
        ok "Ollama container started"
    fi
else
    info "Creating Ollama container (GPU_FLAGS='${GPU_FLAGS}') …"
    # shellcheck disable=SC2086
    docker run -d \
        --name "$OLLAMA_CONTAINER" \
        --restart unless-stopped \
        -p ${OLLAMA_PORT}:11434 \
        -v ollama:/root/.ollama \
        $GPU_FLAGS \
        ollama/ollama
    ok "Ollama container created"
fi

# Wait for Ollama to be ready
info "Waiting for Ollama API …"
for i in {1..30}; do
    if curl -sf "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null; then
        ok "Ollama API is up"
        break
    fi
    sleep 2
    if [[ $i -eq 30 ]]; then
        error "Ollama did not start within 60 s. Check: docker logs $OLLAMA_CONTAINER"
    fi
done

###############################################################################
# 6. Pull models
###############################################################################
section "Pulling models"
MODELS=("phi3:mini" "granite3.1-moe:1b")
for MODEL in "${MODELS[@]}"; do
    if docker exec "$OLLAMA_CONTAINER" ollama list 2>/dev/null | grep -q "${MODEL%%:*}"; then
        ok "Model already present: $MODEL"
    else
        info "Pulling $MODEL (this may take a few minutes) …"
        docker exec "$OLLAMA_CONTAINER" ollama pull "$MODEL"
        ok "Pulled: $MODEL"
    fi
done

###############################################################################
# 7. Clone / update PromptMe repo
###############################################################################
section "PromptMe application"
INSTALL_DIR="${PROMPTME_DIR:-/opt/promptme}"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Repository already present at $INSTALL_DIR — pulling latest …"
    git -C "$INSTALL_DIR" fetch origin lite-mode
    git -C "$INSTALL_DIR" checkout lite-mode
    git -C "$INSTALL_DIR" pull origin lite-mode
    ok "Repository updated"
else
    info "Cloning PromptMe (lite-mode branch) into $INSTALL_DIR …"
    git clone --branch lite-mode --single-branch \
        https://github.com/utkarsh121/PromptMe.git "$INSTALL_DIR"
    ok "Repository cloned"
fi

###############################################################################
# 8. Python virtual environment & dependencies
###############################################################################
section "Python dependencies"
VENV="$INSTALL_DIR/.venv"

if [[ ! -d "$VENV" ]]; then
    python3 -m venv "$VENV"
    ok "Virtual environment created"
fi

source "$VENV/bin/activate"
pip install --upgrade pip -q
pip install -r "$INSTALL_DIR/requirements.txt" -q
ok "Python packages installed"

###############################################################################
# 9. Systemd service
###############################################################################
section "Systemd service"
SERVICE_FILE="/etc/systemd/system/promptme.service"

# Resolve the effective user for the service
RUN_USER="${SUDO_USER:-$USER}"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=PromptMe Lite — OWASP LLM CTF Lab
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${VENV}/bin/python main.py
Restart=on-failure
RestartSec=5
Environment="OLLAMA_BASE_URL=http://localhost:${OLLAMA_PORT}"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable promptme
systemctl restart promptme
ok "systemd service enabled and started"

###############################################################################
# 10. Desktop shortcut (optional — only if a display is available)
###############################################################################
section "Desktop shortcut"
DESKTOP_DIR=""
if [[ -n "${SUDO_USER:-}" ]]; then
    DESKTOP_DIR="/home/${SUDO_USER}/Desktop"
elif [[ -d "$HOME/Desktop" ]]; then
    DESKTOP_DIR="$HOME/Desktop"
fi

if [[ -n "$DESKTOP_DIR" && -d "$DESKTOP_DIR" ]]; then
    cat > "$DESKTOP_DIR/PromptMe.desktop" <<EOF
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
    chmod +x "$DESKTOP_DIR/PromptMe.desktop"
    ok "Desktop shortcut created at $DESKTOP_DIR/PromptMe.desktop"
else
    info "No Desktop directory found — skipping shortcut"
fi

###############################################################################
# 11. Post-install summary
###############################################################################
section "Installation complete"
echo ""
echo -e "  ${BOLD}Dashboard:${RESET}       http://localhost:5000"
echo -e "  ${BOLD}Models:${RESET}          phi3:mini + granite3.1-moe:1b"
echo -e "  ${BOLD}GPU acceleration:${RESET} ${GPU_FOUND}"
if [[ "$GPU_FOUND" == "true" ]]; then
    echo -e "  ${BOLD}GPU info:${RESET}        $GPU_INFO"
fi
echo -e "  ${BOLD}Install dir:${RESET}     $INSTALL_DIR"
echo -e "  ${BOLD}Service status:${RESET}  systemctl status promptme"
echo ""
echo -e "  To view logs:  ${CYAN}journalctl -fu promptme${RESET}"
echo ""
ok "PromptMe Lite is ready. Open http://localhost:5000 in your browser."
