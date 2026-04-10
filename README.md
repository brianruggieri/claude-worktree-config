# claude-worktree-config

**Stop losing `.claude/` settings, skills, hooks, and memory when git worktrees are cleaned up.**

When you create a git worktree, Claude Code's `.claude/` directory gets a stale snapshot — or nothing at all. When the worktree is removed after merge, everything created during that session is silently destroyed. Auto-memory (`~/.claude/projects/`) is keyed by absolute path, so worktree sessions get empty memory that can never recall what the main checkout learned.

This is a [well-documented pain point](https://github.com/anthropics/claude-code/issues/28041) affecting Claude Code, Codex, Cursor, and every AI coding tool that stores config in the working tree.

**This repo provides a zero-dependency, pure-shell solution that keeps one canonical `.claude/` and one canonical memory directory — shared across all worktrees via symlinks.**

## What It Does

| Layer | Problem | Fix |
|-------|---------|-----|
| `.claude/` directory | Stale copy in worktree, destroyed on cleanup | Symlinked to main checkout |
| Auto-memory (`~/.claude/projects/`) | Separate empty dir per worktree path | Symlinked to main project's memory |
| Git status noise | Tracked `.claude/` files show as deleted | `skip-worktree` flag + `info/exclude` |

Changes made in any worktree (new skills, updated settings, saved memories) are immediately visible everywhere. `git worktree remove` deletes the symlink, never the target.

## How It Works

One shared shell script (`worktree-setup.sh`) handles everything. It's triggered from two places:

1. **Git `post-checkout` hook** — fires on `git worktree add`, regardless of who calls it (you, Claude, subagents, scripts)
2. **Claude Code `WorktreeCreate` hook** — fires on `claude --worktree` and `Agent(isolation: "worktree")`

```
git worktree add .worktrees/feat-x feat/x
# post-checkout fires → worktree-setup.sh runs
#   ✓ .worktrees/feat-x/.claude/ → symlink to main .claude/
#   ✓ ~/.claude/projects/<worktree-key>/memory/ → symlink to main memory/

# ... work in the worktree ...

git worktree remove .worktrees/feat-x
#   Symlinks deleted. Main .claude/ and memory untouched.
```

## Install

### Quick (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/brianruggieri/claude-worktree-config/main/install.sh | bash
```

### Manual

```bash
# 1. Copy the shared script
mkdir -p ~/.claude/hooks
cp worktree-setup.sh ~/.claude/hooks/worktree-setup.sh
chmod +x ~/.claude/hooks/worktree-setup.sh

# 2. Set up the git template (new clones get the hook automatically)
mkdir -p ~/.config/git/hooks-template/hooks
cp post-checkout ~/.config/git/hooks-template/hooks/post-checkout
chmod +x ~/.config/git/hooks-template/hooks/post-checkout
git config --global init.templateDir ~/.config/git/hooks-template

# 3. Add WorktreeCreate hook to Claude Code global settings
# Add to ~/.claude/settings.json under "hooks":
#   "WorktreeCreate": [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/worktree-setup.sh", "timeout": 30 }] }]

# 4. Install in existing repos
for repo in ~/git/*/; do
    hook="$repo.git/hooks/post-checkout"
    if [ -d "$repo.git" ] && [ ! -f "$hook" ]; then
        mkdir -p "$(dirname "$hook")"
        cp ~/.config/git/hooks-template/hooks/post-checkout "$hook"
    fi
done
```

## What Gets Symlinked

### `.claude/` directory (in-repo)

The worktree's `.claude/` directory is replaced with a symlink to the main checkout's `.claude/`. This shares:

- `settings.json` — project permissions, hooks, MCP servers
- `hooks/` — boundary checks, compile checks, custom hooks
- `skills/` — project-specific skills
- `research/` — research documents
- `handoffs/` — session handoff files
- Plans, design docs, any other `.claude/` content

### Auto-memory (`~/.claude/projects/`)

Claude Code stores per-project memory at `~/.claude/projects/<encoded-path>/memory/`. The path is encoded by replacing all non-alphanumeric characters with `-`. For example:

```
Main:     /Users/me/git/myapp          → -Users-me-git-myapp/memory/
Worktree: /Users/me/git/myapp/.worktrees/feat-x → -Users-me-git-myapp--worktrees-feat-x/memory/
```

**Note:** Modern Claude Code (v2.1.51+) resolves all worktrees to the main repo's memory directory natively ([#24382](https://github.com/anthropics/claude-code/issues/24382)) by following the `.git` file → `gitdir:` → `commondir` chain. Our memory symlink acts as a safety net for edge cases where this resolution fails (e.g., the fallback path uses CWD, which would be the worktree path).

## Safety

| Concern | Status |
|---------|--------|
| `git worktree remove` deletes target? | **No** — removes symlink only |
| `rm -rf` on worktree deletes target? | **No** — POSIX: `rm` on a symlink-to-directory removes the link |
| Parallel agents writing through symlink? | **Safe** for separate files; same-file concurrent writes are a race condition at the filesystem level (rare in practice) |
| Repos without `.claude/`? | Hook exits immediately — zero impact |
| Main checkout affected? | **No** — hook only acts in linked worktrees |

## Compatibility

| Creation method | Git hook fires | Claude hook fires |
|-----------------|---------------|-------------------|
| `git worktree add` (manual) | Yes | No |
| Claude prompted to create worktree | Yes | No |
| `claude --worktree` | Yes | Yes |
| `Agent(isolation: "worktree")` | Yes | Yes |
| `EnterWorktree` tool | Yes | Yes* |

\* `EnterWorktree` has a [known bug](https://github.com/anthropics/claude-code/issues/36205) where `WorktreeCreate` hooks don't fire. The git hook covers this.

## Files

```
worktree-setup.sh   ← Shared script (lives at ~/.claude/hooks/)
post-checkout        ← Git hook template (thin wrapper calling shared script)
install.sh           ← One-command installer
```

## How It Compares

| Solution | `.claude/` dir | Auto-memory | Live sync | Git status clean | Trigger |
|----------|---------------|-------------|-----------|-----------------|---------|
| **This** | **Full symlink** | **Yes** | **Yes** | **Yes** | Git hook + Claude hook |
| [wangmir's hook](https://github.com/anthropics/claude-code/issues/28041#issuecomment-2754308789) | Full copy | No | No (stale) | No | Claude hook only |
| [tfriedel/claude-worktree-hooks](https://github.com/tfriedel/claude-worktree-hooks) | No | No | — | — | Claude hook only |
| [isoapp/claude-worktree-hooks](https://github.com/isoapp/claude-worktree-hooks) | `settings.local.json` only | No | Partial | No | Claude hook only |
| [Wirasm/worktree-manager-skill](https://github.com/Wirasm/worktree-manager-skill) | No | No | — | — | LLM skill (manual) |
| [dot-claude-sync](https://github.com/yugo-ibuki/dot-claude-sync) | Copy-based | No | No (manual) | No | Manual CLI |
| `worktree.symlinkDirectories` only | Partial | No | Yes | No | Claude hook only |

**Key differentiators:**

- **Auto-memory** — no other solution handles `~/.claude/projects/` path mapping. Every other approach ignores it entirely.
- **Dual trigger** — git `post-checkout` hook covers `git worktree add` from any caller. Competing solutions only use Claude's `WorktreeCreate` hook, which doesn't fire for manual worktree creation.
- **Global install** — `init.templateDir` propagates the hook to all new clones automatically. No per-repo setup.
- **Clean git status** — `skip-worktree` flags on tracked `.claude/` files prevent ~30 "deleted" entries from polluting `git status`.

## Known Limitations

- **`init.templateDir` only affects new clones.** Existing repos need a one-time hook copy (the install script handles this).
- **The git hook lives in `.git/hooks/`, not in the repo.** It's local to each clone. The `init.templateDir` and install script propagate it, but it's not version-controlled per-repo.
- **Atomic writes on individual file symlinks can break them.** Claude Code uses write-to-temp-then-rename for some files ([#40857](https://github.com/anthropics/claude-code/issues/40857)), which replaces a symlink with a regular file. **This does not affect our approach** because we symlink the `.claude/` *directory*, not individual files. Writes to files *inside* a symlinked directory work correctly — the OS resolves the directory symlink, then the atomic write operates within the resolved directory.
- **Linux sandbox (bwrap) may not handle symlinked directories inside `.claude/`.** Issues [#40133](https://github.com/anthropics/claude-code/issues/40133) and [#44567](https://github.com/anthropics/claude-code/issues/44567) show bwrap's bind-mount setup doesn't follow symlinks correctly. This only affects Linux users with sandbox enabled. macOS is unaffected.

## FAQ

### Does symlinks cause Claude to "search in the base repo"?

No. A [comment on #28041](https://github.com/anthropics/claude-code/issues/28041) reported that Claude Code "still tries to search in a base repo" after symlinking `.claude/`. Investigation shows this is a **pre-existing worktree bug** ([#36182](https://github.com/anthropics/claude-code/issues/36182)) where Explore agents and Edit/Read tools resolve paths against the main repo root instead of the worktree — regardless of whether `.claude/` is symlinked. The bug is caused by Claude Code using `git rev-parse --git-common-dir` internally, which always returns the main repo's `.git` directory. Our symlink does not make this better or worse.

### Does `git worktree remove` break because of the symlink?

It requires `--force` because git sees the `.claude` symlink as an untracked file. The `skip-worktree` flags prevent tracked files from blocking removal, but the symlink itself is untracked. Use `git worktree remove --force` or remove the symlink first. The target is never affected.

## Related Issues

- [anthropics/claude-code#28041](https://github.com/anthropics/claude-code/issues/28041) — `.claude/` subdirectories not copied to worktree (14 upvotes)
- [anthropics/claude-code#39920](https://github.com/anthropics/claude-code/issues/39920) — Memory resolves to main worktree's directory
- [anthropics/claude-code#41283](https://github.com/anthropics/claude-code/issues/41283) — Memory identity derived from filesystem path
- [anthropics/claude-code#36182](https://github.com/anthropics/claude-code/issues/36182) — Edit/Read tools use main workspace paths in worktrees (not caused by symlinks)

## License

MIT
