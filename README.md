# hawt

AI agents are great until two of them edit the same file, or one of them decides `/home` should be cleaner.

`hawt` gives each agent its own worktree and locks it in a sandbox. You review the work. You decide what ships.

The Claude Code docs describe a [manual workflow for running parallel sessions with git worktrees](https://code.claude.com/docs/en/common-workflows#run-parallel-claude-code-sessions-with-git-worktrees): create worktrees by hand, `cd` into each one, run `claude`, remember to set up your dev environment, and clean up when done. Here's how that compares to `hawt`:

| Manual workflow                                          | `hawt`                                                             |
| -------------------------------------------------------- | ------------------------------------------------------------------ |
| `git worktree add ../project-feature -b feature`         | `hawt cc feature`                                                  |
| `cd` into worktree, run `claude`                         | Handled automatically                                              |
| Manually install deps / set up environment               | Smart bootstrap via `.worktreerc` or auto-detection                |
| Trust that agents won't touch other worktrees or `/home` | bwrap sandbox: read-only root, `.env` nullification, PID isolation |
| Open multiple terminals for parallel sessions            | `hawt batch tasks.hawt -j 4`                                       |
| `git worktree list` / `git worktree remove`              | `hawt ps`, `hawt review`, `hawt merge`, `hawt clean`               |

## Why not `--dangerously-skip-permissions` alone?

Claude Code's `--dangerously-skip-permissions` flag enables fully autonomous operation - no permission prompts, no human-in-the-loop. Without a sandbox, this means unrestricted access to your entire filesystem, network, and running processes. You're trusting the model not to `rm -rf /home` or exfiltrate your SSH keys.

`hawt` makes autonomous mode safe by combining it with a bwrap sandbox. In worktree mode, `hawt cc <name>` passes `--dangerously-skip-permissions` automatically - but Claude runs inside a locked-down namespace where the root filesystem is read-only, `/home` is a tmpfs, `.env` files are nullified, and the only writable directory is the worktree copy. The agent has full autonomy _within_ a space where the blast radius is zero.

**Permissions bypass is only enabled in worktree mode.** Running `hawt cc` without a worktree name sandboxes your current repo but does _not_ pass `--dangerously-skip-permissions`. This is intentional - without a worktree, the sandbox protects a live copy of your repo, so interactive permission prompts remain the appropriate safeguard. The autonomous bypass is reserved for disposable worktree copies where the worst case is deleting work you haven't merged yet.

## Why not Claude Code's built-in sandbox?

Claude Code ships its own bwrap-based sandbox, but it's designed as an opaque safety net rather than a configurable isolation layer:

| Concern                                     | CC built-in sandbox                             | `hawt` sandbox                                                       |
| ------------------------------------------- | ----------------------------------------------- | -------------------------------------------------------------------- |
| Transparency                                | Opaque - no way to inspect the bwrap invocation | `--dry-run` prints the exact bwrap command                           |
| Configurability                             | Not configurable                                | `.worktreerc` directives, CLI flags, env vars                        |
| Home directory                              | Accessible                                      | tmpfs over `/home` with selective re-binds (shell, git, SSH, GPG)    |
| `.env` / secrets                            | Accessible                                      | Nullified by default (`/dev/null` overlay), opt-in via `--allow-env` |
| Extra mounts                                | Not supported                                   | `bwrap-bind-ro:`, `bwrap-bind-rw:`, `bwrap-tmpfs:` in `.worktreerc`  |
| Network isolation                           | Not supported                                   | `--offline` (`--unshare-net`)                                        |
| Path remapping                              | Not supported                                   | Worktree remapped to `/home/code/<name>` by default                  |
| Works with `--dangerously-skip-permissions` | Disabled when skip-permissions is active        | Designed for it - sandbox _is_ the permission boundary               |

The key limitation: CC's built-in sandbox is mutually exclusive with `--dangerously-skip-permissions`. When you enable autonomous mode, the built-in sandbox turns off. `hawt` inverts this - the sandbox is the reason you _can_ skip permissions safely.

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

## Don't Trust This README

Everything above describes what `hawt` _claims_ to do. You should not take our word for it (or anyone else's) when it comes to tools that give system access to an LLM.

Drop into a sandbox yourself and poke around:

```fish
hawt sandbox -- fish
```

Try reading `/home`. Try writing outside the worktree. Try accessing `.env` files. Try killing host processes. Anything you can (and can't) do in there applies to agents as well.

Inspect the exact bwrap invocation with:

```fish
hawt sandbox --dry-run -- fish
```

This prints every mount, namespace flag, and bind path — nothing is hidden. Read it. Understand what's mounted read-only, what's writable, what's a tmpfs, and what's not there at all.

**This applies to every tool in this space, not just `hawt`.** Any project that wraps an LLM with filesystem or shell access deserves the same scrutiny. The cost of verifying is a few minutes in a shell. The cost of blind trust is your SSH keys, your `.env` secrets, and whatever else lives under `/home`.

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
hawt review auth-flow # commits, stats, session log
hawt diff auth-flow # full diff against main
hawt diff auth-flow --stat # quick overview

# happy with it? merge back to main (squash by default)
hawt merge auth-flow

# or pick a different strategy
hawt merge auth-flow --rebase

# done - clean up stale refs and orphaned worktree dirs
hawt clean
```

## Commands

### Worktree Management

| Command                                 | Description                                                                            |
| --------------------------------------- | -------------------------------------------------------------------------------------- |
| `hawt`                                  | Interactive fzf picker - browse/switch worktrees (`ctrl-d` to remove, git log preview) |
| `hawt switch <name> [--from <ref>]`     | Create or switch to a named worktree (auto-stashes uncommitted changes)                |
| `hawt status`                           | Table view: branch, dirty state, ahead/behind, age                                     |
| `hawt tmp [name]`                       | Ephemeral worktree in `/tmp` - auto-cleaned when you `cd` out or run `hawt clean`      |
| `hawt rm <name>`                        | Remove a worktree (warns if dirty, confirms before force)                              |
| `hawt clean`                            | Prune stale git refs + find orphaned worktree directories                              |

`hawt <name>` also works as a shorthand for `hawt switch <name>`.

### Claude Code Integration

| Command                       | Description                                                           |
| ----------------------------- | --------------------------------------------------------------------- |
| `hawt cc`                     | Run Claude Code in a sandbox using the current directory as workspace |
| `hawt cc <name>`              | Create/reuse worktree, run CC in sandbox inside it                    |
| `hawt cc <name> --from <ref>` | Branch worktree from a specific ref                                   |
| `hawt cc <name> --task "..."` | Write task description to TASK.md before launching                    |
| `hawt cc --offline`           | Disable network inside the sandbox                                    |
| `hawt cc --dry-run`           | Print the bwrap command without executing                             |

### Batch & Session Management

| Command                        | Description                                               |
| ------------------------------ | --------------------------------------------------------- |
| `hawt batch <taskfile> [-j N]` | Launch parallel CC sessions from a taskfile               |
| `hawt ps`                      | Show running CC sessions: PID, uptime, branch, lock state |
| `hawt kill <name>`             | Terminate a CC session and clean up                       |
| `hawt lock <name>`             | Manually lock a worktree                                  |
| `hawt unlock <name>`           | Manually unlock a worktree (warns if owner PID is alive)  |

### Review & Merge

| Command                                           | Description                                                    |
| ------------------------------------------------- | -------------------------------------------------------------- |
| `hawt diff <name> [--files\|--stat]`              | Review changes in a worktree branch                            |
| `hawt review <name> [--ai] [--test]`              | Post-session review: commits, stats, logs, optional AI summary |
| `hawt merge <name> [--squash\|--rebase\|--merge]` | Merge worktree branch back (default: squash)                   |
| `hawt checkpoint <name> [message]`                | Commit current worktree state from outside                     |

### Generic Sandbox

| Command                        | Description                        |
| ------------------------------ | ---------------------------------- |
| `hawt sandbox [opts] -- <cmd>` | Run any command in a bwrap sandbox |

Sandbox options: `--offline`, `--no-remap`, `--allow-env`, `--mount-ro <path>`, `--mount-rw <path>`, `--dry-run`

### Batch Taskfiles

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

## Configuration

### Worktree Layout

By default, worktrees are created adjacent to your repo:

```
~/projects/
├── my-app/                    ← main repo
└── my-app-worktrees/          ← worktrees live here (default)
    ├── feature-auth/
    └── bugfix-header/
```

Override with `worktree-dir:` in `.worktreerc` (per-repo) or the `HAWT_WORKTREE_DIR` env var (global).

Precedence: `HAWT_WORKTREE_DIR` > `worktree-dir:` in `.worktreerc` > default (`../<repo>-worktrees/`)

### `.worktreerc`

Place a `.worktreerc` in your repo root for declarative control over worktree setup and sandbox mounts:

```
# Custom worktree location (default: ../<repo>-worktrees/)
worktree-dir: ../my-worktrees

# Symlink (shared with main repo, saves disk)
symlink: node_modules
symlink: .next

# Copy (independent per worktree)
copy: .env
copy: .env.local

# Run after creation (requires TOFU approval, see Security)
post-create: npx prisma generate

# Extra sandbox mounts (validated against blocklist, see Security)
bwrap-bind-ro: ~/.config/some-tool
bwrap-bind-rw: /tmp/shared-cache
bwrap-tmpfs: /some/path
```

Without a `.worktreerc`, `hawt` detects your project type and applies sensible defaults:

- **TypeScript/Node:** symlinks `node_modules`, build caches (`.next`, `.turbo`, `dist`, etc.), copies `.env*` files, handles monorepo nested `node_modules`
- **Python:** symlinks `.venv`, `venv`, `.tox`
- **Nix:** symlinks `.direnv`

### Lifecycle Hooks

Create scripts in `.worktree-hooks/` in your repo root:

- **`post-create`** - runs in the new worktree directory after creation (fish or any executable)
- **`on-leave`** - fires when you `cd` out of a worktree directory (useful for stopping dev servers, saving state)

When switching worktrees, `hawt` detects uncommitted changes and offers to stash them.

## Security

### Sandbox isolation

Every `hawt cc` and `hawt sandbox` invocation runs inside a bwrap (bubblewrap) namespace:

- **Read-only root filesystem** - the agent can't modify the host
- **Isolated home directory** - tmpfs over `/home`, selective re-bind of shell config, git, SSH agent, GPG agent
- **Writable project only** - the worktree (or repo) is the sole writable workspace
- **Path remapping** - worktree is remapped to `/home/code/<name>` so agents see a clean path
- **.env nullification** - `.env*` files are overlaid with `/dev/null` by default
- **PID namespace** - `--unshare-pid` prevents the agent from seeing or signaling host processes
- **Orphan cleanup** - `--die-with-parent` ensures the sandbox dies if the parent process exits
- **Optional network isolation** - `--offline` drops all network access via `--unshare-net`
- **Extensible** - `.worktreerc` can declare extra `bwrap-bind-ro:`, `bwrap-bind-rw:`, `bwrap-tmpfs:` directives

### Selective home re-binds

The sandbox doesn't blanket-expose your home directory. Instead, it re-binds only what's needed:

| Mounted (read-only)               | Why                                      |
| --------------------------------- | ---------------------------------------- |
| Fish config, git config           | Shell/git must work inside the sandbox   |
| SSH agent socket + `known_hosts`  | Git push/pull over SSH (no private keys) |
| GPG agent socket + public keyring | Commit signing (no secret keys)          |
| `gh` CLI config                   | GitHub API access                        |
| `mise`, `cargo`, `rustup`         | Runtime/toolchain resolution             |
| `~/.npmrc`                        | Registry auth for package installs       |

Everything else under `/home` is a tmpfs - invisible to the agent.

### `.worktreerc` mount blocklist

Custom bwrap directives in `.worktreerc` (`bwrap-bind-ro:`, `bwrap-bind-rw:`, `bwrap-tmpfs:`) are validated against a blocklist of system paths: `/`, `/proc`, `/dev`, `/sys`, `/etc`, `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/boot`, `/var`, `/root`, `/run`, `/home`. Paths are resolved through symlinks before checking, so symlink-based bypass attempts (e.g., `/tmp/evil` -> `/etc`) are caught.

### Trust-on-first-use (TOFU)

`.worktreerc` post-create commands and `.worktree-hooks/` scripts can execute arbitrary code. Before running them for the first time, `hawt` computes a SHA-256 hash of the file and prompts for confirmation. Approved hashes are stored as `hash:filepath` entries in `.hawt-trusted` (per-repo). If the file changes, the hash won't match and approval is required again.

This follows the same model as direnv's `.envrc` trust mechanism.

### Concurrency locking

Worktree sessions are protected by `flock(1)` kernel-managed locks (`.hawt-lock` files). Locks auto-release on process death - no stale lock cleanup needed. `--close` prevents the lock fd from leaking into the bwrap child, so the lock is held by `flock` itself, not the sandboxed process.
