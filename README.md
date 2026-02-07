# hawt

AI agents are great until two of them edit the same file, or one of them decides `/home` should be cleaner.

`hawt` gives each agent its own worktree and locks it in a sandbox. You review the work. You decide what ships.

## Try Without Installing

```fish
git clone https://github.com/Lokaltog/hawt.git ~/tools/hawt
cd ~/tools/hawt
source try.fish
```

This loads `hawt` into your current shell session only - nothing is written to `~/.config/fish/`.

## Install

```fish
cd ~/tools/hawt
fish install.fish
```

Dependencies: `git`, `fish`, `fzf`, `bwrap` (bubblewrap)

Optional: `claude` CLI, `delta`/`diff-so-fancy` (for pretty diffs)

Full fish tab completions are included for subcommands, worktree names, and flags.

## End-to-End Example

```fish
# spin up a sandboxed worktree and drop Claude Code into it
hawt cc auth-flow --task "Add JWT auth middleware to all API routes"

# Claude works in its own worktree at my-app-worktrees/auth-flow/
# with a read-only root filesystem, no access to your main repo,
# and .env files nullified - it can only touch its own copy

# meanwhile, kick off another task in parallel - no conflicts
hawt cc fix-nav --task "Fix mobile nav dropdown z-index"

# branch from a specific ref
hawt cc hotfix-login --from release/2.0 --task "Fix OAuth callback URL"

# check what's running
hawt ps

# when a session finishes, review what it did
hawt review auth-flow            # commits, stats, session log
hawt diff auth-flow              # full diff against main
hawt diff auth-flow --stat       # quick overview

# happy with it? merge back to main (squash by default)
hawt merge auth-flow

# or pick a different strategy
hawt merge auth-flow --rebase

# done - clean up stale refs and orphaned worktree dirs
hawt clean
```

## Commands

### Worktree Management

| Command | Description |
| --- | --- |
| `hawt` | Interactive fzf picker - browse/switch worktrees (`ctrl-d` to remove, git log preview) |
| `hawt <name> [--from <ref>]` | Create or switch to a named worktree (auto-stashes uncommitted changes) |
| `hawt status` | Table view: branch, dirty state, ahead/behind, age |
| `hawt tmp [name]` | Ephemeral worktree in `/tmp` - auto-cleaned when you `cd` out or run `hawt clean` |
| `hawt rm <name>` | Remove a worktree (warns if dirty, confirms before force) |
| `hawt clean` | Prune stale git refs + find orphaned worktree directories |

### Claude Code Integration

| Command | Description |
| --- | --- |
| `hawt cc` | Run Claude Code in a sandbox using the current directory as workspace |
| `hawt cc <name>` | Create/reuse worktree, run CC in sandbox inside it |
| `hawt cc <name> --from <ref>` | Branch worktree from a specific ref |
| `hawt cc <name> --task "..."` | Write task description to TASK.md before launching |
| `hawt cc --offline` | Disable network inside the sandbox |
| `hawt cc --dry-run` | Print the bwrap command without executing |

### Batch & Session Management

| Command | Description |
| --- | --- |
| `hawt batch <taskfile> [-j N]` | Launch parallel CC sessions from a taskfile |
| `hawt ps` | Show running CC sessions: PID, uptime, branch, lock state |
| `hawt kill <name>` | Terminate a CC session and clean up |
| `hawt lock <name>` | Manually lock a worktree |
| `hawt unlock <name>` | Manually unlock a worktree (warns if owner PID is alive) |

### Review & Merge

| Command | Description |
| --- | --- |
| `hawt diff <name> [--files\|--stat]` | Review changes in a worktree branch |
| `hawt review <name> [--ai] [--test]` | Post-session review: commits, stats, logs, optional AI summary |
| `hawt merge <name> [--squash\|--rebase\|--merge]` | Merge worktree branch back (default: squash) |
| `hawt checkpoint <name> [message]` | Commit current worktree state from outside |

### Generic Sandbox

| Command | Description |
| --- | --- |
| `hawt sandbox [opts] -- <cmd>` | Run any command in a bwrap sandbox |

Sandbox options: `--offline`, `--no-remap`, `--allow-env`, `--mount-ro <path>`, `--mount-rw <path>`, `--dry-run`

## Worktree Layout

By default, worktrees are created adjacent to your repo, keeping the project directory clean:

```
~/projects/
├── my-app/                    ← main repo
└── my-app-worktrees/          ← worktrees live here (default)
    ├── feature-auth/
    └── bugfix-header/
```

### Custom Worktree Location

Override the default with `worktree-dir:` in `.worktreerc` (per-repo) or `HAWT_WORKTREE_DIR` env var (global):

```
# .worktreerc — relative to repo root
worktree-dir: ../my-worktrees

# .worktreerc — absolute path
worktree-dir: /tmp/worktrees/my-app

# .worktreerc — inside the repo
worktree-dir: .worktrees
```

```fish
# Environment variable (overrides .worktreerc)
set -x HAWT_WORKTREE_DIR /data/worktrees/my-app
```

Precedence: `HAWT_WORKTREE_DIR` > `worktree-dir:` in `.worktreerc` > default (`../<repo>-worktrees/`)

## Smart Bootstrap

When creating a worktree, `hawt` automatically symlinks or copies files to make the worktree immediately usable.

### With `.worktreerc` (recommended)

Place a `.worktreerc` in your repo root for declarative control:

```
# Custom worktree location (default: ../<repo>-worktrees/)
worktree-dir: ../my-worktrees

# Symlink (shared with main repo, saves disk)
symlink: node_modules
symlink: .next

# Copy (independent per worktree)
copy: .env
copy: .env.local

# Run after creation
post-create: npx prisma generate

# Extra sandbox mounts
bwrap-bind-ro: ~/.config/some-tool
bwrap-bind-rw: /tmp/shared-cache
bwrap-tmpfs: /some/path
```

### Without `.worktreerc` (heuristics)

If no config is found, `hawt` detects your project type and applies sensible defaults:

**TypeScript/Node:** symlinks `node_modules`, build caches (`.next`, `.turbo`, `dist`, etc.), copies `.env*` files, handles monorepo nested `node_modules`

**Python:** symlinks `.venv`, `venv`, `.tox`

**Nix:** symlinks `.direnv`

## Sandbox Isolation

The bwrap sandbox provides:

- **Read-only root filesystem** - the agent can't modify the host
- **Isolated home directory** - tmpfs over `/home`, selective re-bind of shell config, git, SSH agent, GPG agent
- **Writable project only** - the worktree (or repo) is the sole writable workspace
- **Path remapping** - worktree is remapped to `/home/code/<name>` so agents see a clean path
- **.env nullification** - `.env*` files are overlaid with `/dev/null` by default
- **Optional network isolation** - `--offline` drops all network access
- **Extensible** - `.worktreerc` can declare extra `bwrap-bind-ro:`, `bwrap-bind-rw:`, `bwrap-tmpfs:` directives

## Batch Mode

Define tasks in a file (one per line, `name: description`):

```
# tasks.hawt
auth: Implement JWT authentication
api-docs: Generate OpenAPI spec from route handlers
fix-nav: Fix mobile navigation dropdown z-index
```

Launch them all:

```fish
hawt batch tasks.hawt --from main -j 3
```

Each task gets its own worktree, branch (`cc/<name>`), and sandboxed CC session.

## Lifecycle Hooks

Create scripts in `.worktree-hooks/` in your repo root:

- **`post-create`** - runs in the new worktree directory after creation (fish or any executable)
- **`on-leave`** - fires when you `cd` out of a worktree directory (useful for stopping dev servers, saving state)

When switching worktrees, `hawt` detects uncommitted changes and offers to stash them.
