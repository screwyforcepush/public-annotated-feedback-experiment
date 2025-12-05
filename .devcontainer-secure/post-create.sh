#!/bin/bash
set -euo pipefail

echo "🔒 Setting up SECURE sandbox environment..."
echo ""

# ============================================
# SECURITY HARDENING - Run first!
# ============================================

# Kill SSH agent forwarding - remove socket and unset variable
if [ -n "${SSH_AUTH_SOCK:-}" ]; then
    echo "🔐 Disabling SSH agent forwarding..."
    rm -f "${SSH_AUTH_SOCK}" 2>/dev/null || true
fi
unset SSH_AUTH_SOCK
export SSH_AUTH_SOCK=""

# Prevent SSH agent from being set in future shells
echo "" >> ~/.bashrc
echo "# SECURITY: Disable SSH agent forwarding" >> ~/.bashrc
echo "unset SSH_AUTH_SOCK" >> ~/.bashrc
echo "export SSH_AUTH_SOCK=''" >> ~/.bashrc

# Remove any SSH keys that might have been copied
rm -rf ~/.ssh/id_* ~/.ssh/known_hosts 2>/dev/null || true

# Verify no SSH agent access
if ssh-add -l 2>/dev/null; then
    echo "⚠️  WARNING: SSH agent still accessible - attempting to block"
    unset SSH_AUTH_SOCK
fi

echo "✓ SSH agent forwarding disabled"
echo ""

# ============================================
# Standard setup continues below
# ============================================

# Validate required environment variables
if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "❌ Error: GITHUB_TOKEN environment variable is not set"
    exit 1
fi

if [ -z "${REPO_URL:-}" ]; then
    echo "❌ Error: REPO_URL environment variable is not set"
    exit 1
fi

# Set default branch if not specified
BRANCH_NAME="${BRANCH_NAME:-main}"

# Configure git to use token for authentication via helper
git config --global user.email "claude-agent@anthropic.com"
git config --global user.name "Claude Agent"

# Use a more secure credential helper configuration
git config --global credential.helper 'cache --timeout=3600'
git config --global credential.https://github.com.username oauth2

# Store token using git credential helper (more secure than .git-credentials file)
printf "protocol=https\nhost=github.com\nusername=oauth2\npassword=%s\n\n" "${GITHUB_TOKEN}" | git credential-cache store

# Find the repository directory (DevPod should have cloned it)
if [ -d "/workspace/.git" ]; then
    cd /workspace
elif [ -d "/workspaces/${REPO_NAME}/.git" ]; then
    cd "/workspaces/${REPO_NAME}"
elif [ -d ".git" ]; then
    # Already in repo directory
    :
else
    echo "⚠️  Warning: Could not find Git repository. DevPod should have cloned it."
    echo "   You may need to clone manually if needed."
fi

# If we're in a git repo, show current status and handle branch
if [ -d ".git" ]; then
    echo "📦 Repository information:"
    echo "   Location: $(pwd)"
    echo "   Remote: $(git remote get-url origin 2>/dev/null || echo 'No remote configured')"
    echo "   Current Branch: $(git branch --show-current 2>/dev/null || echo 'No branch')"

    # Handle branch creation if BRANCH_NAME is specified and different from current
    if [ -n "${BRANCH_NAME:-}" ]; then
        CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
        if [ "${CURRENT_BRANCH}" != "${BRANCH_NAME}" ]; then
            echo ""
            echo "🌿 Switching to branch: ${BRANCH_NAME}"

            # Try to checkout existing branch or create new one
            if git show-ref --verify --quiet "refs/remotes/origin/${BRANCH_NAME}"; then
                echo "   Branch exists on remote, checking out..."
                git checkout "${BRANCH_NAME}"
            else
                echo "   Branch doesn't exist, creating new branch..."
                git checkout -b "${BRANCH_NAME}"
                echo "   📤 Branch created locally. Push when ready with:"
                echo "      git push -u origin ${BRANCH_NAME}"
            fi
        fi
    fi
    echo ""
fi

# Install essential development tools only
echo "📦 Installing essential development tools..."
sudo apt-get update > /dev/null 2>&1
sudo apt-get install -y --no-install-recommends \
    curl \
    wget \
    jq \
    tree \
    htop \
    build-essential \
    python3-pip \
    vim \
    tmux \
    ripgrep \
    > /dev/null 2>&1

# Install uv - Fast Python package manager
echo "📦 Installing uv (fast Python package manager)..."
curl -LsSf https://astral.sh/uv/install.sh | sh > /dev/null 2>&1

# Add uv to PATH immediately
export PATH="$PATH:$HOME/.local/bin"

# Install common Python packages
echo "📦 Installing common Python packages..."
sudo apt-get install -y --no-install-recommends python3-requests > /dev/null 2>&1

# Install tiktoken using pip
echo "📦 Installing tiktoken..."
pip3 install --break-system-packages tiktoken > /dev/null 2>&1

# Install ast-grep for code analysis
echo "🔍 Installing ast-grep..."
npm install -g @ast-grep/cli > /dev/null 2>&1

echo ""
echo "✅ Secure sandbox environment ready!"
echo ""
echo "📋 Environment details:"
echo "   Repository: ${REPO_OWNER:-unknown}/${REPO_NAME:-unknown}"
echo "   Branch: ${BRANCH_NAME}"
echo "   Working directory: $(pwd)"
echo ""
echo "🔒 SECURE MODE - Security features:"
echo "   ✓ Running as non-root user (node)"
echo "   ✓ No host network access (host.docker.internal disabled)"
echo "   ✓ No port forwarding to host"
echo "   ✓ No SSH agent forwarding (host keys inaccessible)"
echo "   ✓ No external API keys configured"
echo "   ✓ Capabilities dropped: SYS_ADMIN, NET_ADMIN, NET_RAW"
echo "   ✓ Fine-grained PAT: Single repository access only"
echo "   ✓ Token cached in memory (not on disk)"
echo ""
echo "📦 Package installation available:"
echo "   - System packages: sudo apt-get install <package>"
echo "   - Python packages: uv pip install <package> (in venv) or pip install <package>"
echo "   - Node packages: npm install [-g] <package>"
echo "   - Fast Python: uv venv, uv pip, uv run"
echo ""

# Configure locale settings in user's bashrc
echo "" >> ~/.bashrc
echo "# Locale configuration" >> ~/.bashrc
echo "export LANG=en_US.UTF-8" >> ~/.bashrc
echo "export LC_ALL=en_US.UTF-8" >> ~/.bashrc

# Add uv to PATH in bashrc for future sessions
echo "" >> ~/.bashrc
echo "# Add uv to PATH" >> ~/.bashrc
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc

# Install tmux helper for sandbox sessions
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/smux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PHONETIC=(alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu)

find_free() {
    for n in "${PHONETIC[@]}"; do
        tmux has-session -t "$n" 2>/dev/null || { echo "$n"; return; }
    done
    echo "session-$(date +%s)"
}

case "${1:-}" in
    ls)
        tmux ls
        exit 0
        ;;
    kill)
        shift
        tmux kill-session -t "${1:?session name}"
        exit 0
        ;;
esac

session="${1:-$(find_free)}"
shift || true
cmd="${*:-${SHELL:-/bin/bash}}"

tmux has-session -t "$session" 2>/dev/null || tmux new-session -d -s "$session" "$cmd"
tmux attach -t "$session"
EOF
chmod +x "$HOME/.local/bin/smux"

# Add helper alias for bash/zsh shells
touch ~/.bashrc ~/.zshrc
if ! grep -q 'alias smux=' ~/.bashrc 2>/dev/null; then
    echo 'alias smux="$HOME/.local/bin/smux"' >> ~/.bashrc
fi
if ! grep -q 'alias smux=' ~/.zshrc 2>/dev/null; then
    echo 'alias smux="$HOME/.local/bin/smux"' >> ~/.zshrc
fi

echo "🌍 Locale configured: en_US.UTF-8"
echo "⚡ uv installed: Fast Python package management available"
echo "🔍 ast-grep installed: Code analysis available"

# Clear sensitive tokens from environment
unset GITHUB_TOKEN
