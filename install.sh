#!/bin/bash
# install.sh — One-command installer for claude-worktree-config.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/brianruggieri/claude-worktree-config/main/install.sh | bash
#
# Or clone and run:
#   git clone https://github.com/brianruggieri/claude-worktree-config.git
#   cd claude-worktree-config && ./install.sh

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/brianruggieri/claude-worktree-config/main"

echo "=== claude-worktree-config installer ==="
echo ""

# --- Step 1: Install the shared script ---
echo "[1/4] Installing worktree-setup.sh..."
mkdir -p ~/.claude/hooks

if [ -f "worktree-setup.sh" ]; then
    cp worktree-setup.sh ~/.claude/hooks/worktree-setup.sh
else
    curl -fsSL "$REPO_URL/worktree-setup.sh" -o ~/.claude/hooks/worktree-setup.sh
fi
chmod +x ~/.claude/hooks/worktree-setup.sh
echo "      -> ~/.claude/hooks/worktree-setup.sh"

# --- Step 2: Set up git template ---
echo "[2/4] Setting up git template for new clones..."
mkdir -p ~/.config/git/hooks-template/hooks

if [ -f "post-checkout" ]; then
    cp post-checkout ~/.config/git/hooks-template/hooks/post-checkout
else
    curl -fsSL "$REPO_URL/post-checkout" -o ~/.config/git/hooks-template/hooks/post-checkout
fi
chmod +x ~/.config/git/hooks-template/hooks/post-checkout

# Only set templateDir if not already configured
CURRENT_TEMPLATE=$(git config --global init.templateDir 2>/dev/null || true)
if [ -z "$CURRENT_TEMPLATE" ]; then
    git config --global init.templateDir ~/.config/git/hooks-template
    echo "      -> init.templateDir set to ~/.config/git/hooks-template"
elif [ "$CURRENT_TEMPLATE" = "$HOME/.config/git/hooks-template" ] || [ "$CURRENT_TEMPLATE" = "~/.config/git/hooks-template" ]; then
    echo "      -> init.templateDir already configured"
else
    echo "      -> WARNING: init.templateDir already set to '$CURRENT_TEMPLATE'"
    echo "         Copy post-checkout manually: cp ~/.config/git/hooks-template/hooks/post-checkout $CURRENT_TEMPLATE/hooks/"
fi

# --- Step 3: Claude Code WorktreeCreate hook ---
echo "[3/4] Claude Code WorktreeCreate hook..."
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    if grep -q "WorktreeCreate" "$SETTINGS" 2>/dev/null; then
        echo "      -> Already configured in $SETTINGS"
    else
        echo "      -> ACTION REQUIRED: Add to $SETTINGS under \"hooks\":"
        echo '         "WorktreeCreate": [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/worktree-setup.sh", "timeout": 30 }] }]'
    fi
else
    echo "      -> No ~/.claude/settings.json found. Create one or add the hook manually."
fi

# --- Step 4: Install in existing repos ---
echo "[4/4] Installing hook in existing repos..."
INSTALLED=0
SKIPPED=0
SEARCH_DIR="${1:-$HOME/git}"

if [ -d "$SEARCH_DIR" ]; then
    for repo in "$SEARCH_DIR"/*/; do
        hook="$repo.git/hooks/post-checkout"
        if [ -d "$repo.git" ]; then
            if [ -f "$hook" ]; then
                SKIPPED=$((SKIPPED + 1))
            else
                mkdir -p "$(dirname "$hook")"
                cp ~/.config/git/hooks-template/hooks/post-checkout "$hook"
                INSTALLED=$((INSTALLED + 1))
            fi
        fi
    done
    echo "      -> Installed in $INSTALLED repos, skipped $SKIPPED (already had post-checkout)"
else
    echo "      -> $SEARCH_DIR not found. Pass your repos directory: ./install.sh ~/projects"
fi

echo ""
echo "Done! New worktrees will automatically share .claude/ and auto-memory."
echo ""
echo "To add .claude to Claude Code's symlinkDirectories (optional belt-and-suspenders):"
echo "  Add \".claude\" to worktree.symlinkDirectories in ~/.claude/settings.json"
