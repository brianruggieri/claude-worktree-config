#!/bin/bash
# worktree-setup.sh — Symlink .claude/ and auto-memory into git worktrees.
#
# Called from two places:
#   1. Git post-checkout hook (args: $1=prev HEAD, $2=new HEAD, $3=flag)
#   2. Claude Code WorktreeCreate hook (stdin = JSON with worktree_path)
#
# Detects which caller based on arguments, resolves paths, then:
#   - Symlinks .claude/ in the worktree to the main checkout's .claude/
#   - Marks tracked .claude/ files as skip-worktree so they don't pollute git status
#   - Symlinks ~/.claude/projects/<wt-key>/memory/ to the main project's memory/
#
# Safe to run in any repo. Exits immediately if no .claude/ directory exists.

set -euo pipefail

# --- Path encoding (matches Claude Code's internal encoding) ---
# Replace '/' and '.' with '-'
encode_path() { echo "$1" | tr '/.' '-'; }

# --- Resolve main repo root and worktree path ---

if [ $# -ge 3 ]; then
    # Called from git post-checkout: $3=1 means branch checkout
    [ "$3" = "1" ] || exit 0

    MAIN_ROOT=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')
    WT_ROOT=$(pwd)

    # Only act in linked worktrees, not in the main checkout
    [ "$WT_ROOT" != "$MAIN_ROOT" ] || exit 0
else
    # Called from Claude Code WorktreeCreate hook: read JSON from stdin
    INPUT=$(cat)
    WT_ROOT=$(echo "$INPUT" | grep -o '"worktree_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"//; s/"$//')

    if [ -z "$WT_ROOT" ]; then
        echo "worktree-setup: could not parse worktree_path from stdin" >&2
        exit 0
    fi

    # Resolve main repo root from the worktree
    MAIN_ROOT=$(git -C "$WT_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')
fi

# --- Guard: only act if the main checkout has .claude/ ---
[ -d "$MAIN_ROOT/.claude" ] || exit 0

# --- Layer 1a: Symlink .claude/ in the worktree ---
if [ -d "$WT_ROOT/.claude" ] && [ ! -L "$WT_ROOT/.claude" ]; then
    rm -rf "$WT_ROOT/.claude"
    ln -s "$MAIN_ROOT/.claude" "$WT_ROOT/.claude"
    echo "worktree-setup: symlinked .claude/ -> $MAIN_ROOT/.claude/" >&2
fi

# --- Layer 1b: Hide tracked .claude/ files from git status in worktree ---
# The symlink replaces the real directory, so git sees tracked files as deleted.
# skip-worktree tells git to ignore these index entries in this worktree's index.
TRACKED_CLAUDE_FILES=$(git -C "$WT_ROOT" ls-files .claude/ 2>/dev/null)
if [ -n "$TRACKED_CLAUDE_FILES" ]; then
    echo "$TRACKED_CLAUDE_FILES" | xargs git -C "$WT_ROOT" update-index --skip-worktree 2>/dev/null
    echo "worktree-setup: set skip-worktree on $(echo "$TRACKED_CLAUDE_FILES" | wc -l | tr -d ' ') .claude/ files" >&2
fi

# The .claude symlink itself appears as an untracked entry. Suppress it via
# the repo's shared info/exclude (per-worktree info/exclude is not supported).
# This is safe: in the main checkout .claude/ contains tracked files, so the
# exclude pattern has no effect there.
COMMON_EXCLUDE="$MAIN_ROOT/.git/info/exclude"
if [ -f "$COMMON_EXCLUDE" ] && ! grep -qxF '.claude' "$COMMON_EXCLUDE" 2>/dev/null; then
    echo '.claude' >> "$COMMON_EXCLUDE"
    echo "worktree-setup: added .claude to $COMMON_EXCLUDE" >&2
fi

# --- Layer 2: Symlink auto-memory directory ---
CLAUDE_PROJECTS="$HOME/.claude/projects"
MAIN_PROJECT_DIR="$CLAUDE_PROJECTS/$(encode_path "$MAIN_ROOT")"
WT_PROJECT_DIR="$CLAUDE_PROJECTS/$(encode_path "$WT_ROOT")"

if [ -d "$MAIN_PROJECT_DIR/memory" ]; then
    mkdir -p "$WT_PROJECT_DIR"
    if [ ! -L "$WT_PROJECT_DIR/memory" ]; then
        rm -rf "$WT_PROJECT_DIR/memory" 2>/dev/null
        ln -s "$MAIN_PROJECT_DIR/memory" "$WT_PROJECT_DIR/memory"
        echo "worktree-setup: symlinked auto-memory -> $MAIN_PROJECT_DIR/memory/" >&2
    fi
fi

# If called from WorktreeCreate, echo the worktree path back (required by Claude Code)
if [ $# -lt 3 ] && [ -n "$WT_ROOT" ]; then
    echo "$WT_ROOT"
fi
