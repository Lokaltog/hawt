# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**hawt** is a Git worktree helper CLI written in Fish shell. It enables AI agents (particularly Claude Code) to work in isolated, sandboxed git worktrees - preventing conflicts when multiple agents edit the same repository simultaneously.

## Architecture

**Entry point:** `hawt.fish` contains the main `hawt()` dispatcher function which routes subcommands to `__hawt_*` functions. Core worktree functions (`__hawt_upsert`, `__hawt_bootstrap`, `__hawt_remove`, `__hawt_clean`, `__hawt_status`, `__hawt_tmp`, `__hawt_pick`, `__hawt_help`) are defined inline in `hawt.fish`. Larger subsystems live in separate files under `functions/` (e.g., `hawt cc` → `functions/__hawt_cc.fish`).

**Function naming convention:** All functions use the `__hawt_` prefix.

**Key subsystems:**

- **Worktree lifecycle** - create (`__hawt_upsert`), bootstrap (`__hawt_bootstrap`), remove (`__hawt_remove`), clean (`__hawt_clean`)
- **Sandbox isolation** - `__hawt_cc` wraps Claude Code in `bwrap` (bubblewrap) with read-only root, writable worktree, optional network isolation
- **Concurrency control** - `flock(1)` kernel-based locking via `.hawt-lock` files; session metadata in `.hawt-session-meta`
- **Batch processing** - `__hawt_batch` launches parallel CC sessions from a taskfile
- **Lifecycle hooks** - `.worktree-hooks/post-create` and `.worktree-hooks/on-leave` run at worktree boundaries
- **PWD watcher** - `__hawt_on_pwd_change` fires hooks and cleans ephemeral worktrees when leaving a worktree directory

**Worktree layout (default, configurable via `worktree-dir:` in `.worktreerc` or `HAWT_WORKTREE_DIR` env var):**

- Main repo: `/path/to/my-app/`
- Worktrees: `/path/to/my-app-worktrees/<name>/` (default)

**Configuration files (in user's repo):**

- `.worktreerc` - bootstrap config defining symlinks, copies, post-create commands, and worktree location
- `.worktree-hooks/` - lifecycle hook scripts
- `tasks.hawt` - batch task definitions (`name: description` per line)

## Development

**Language:** Fish shell 4.3+

**Dependencies:** `fish`, `git` (worktree support), `fzf`, `bwrap` (bubblewrap). Optional: `claude` CLI, `delta`/`diff-so-fancy`.

**Installation:** `fish install.fish` symlinks functions and completions into `~/.config/fish/`.

**Testing changes:** Source modified functions directly in a Fish shell session or re-run `install.fish`.

## Code Style

- Fish shell idioms: `set` for variables, `test` for conditionals, `string` builtins for text processing
- Color output via `set_color` with named colors
- Error messages go to stderr: `echo "error" >&2`
- Exit codes: 0 success, 1 error
- Helper functions are defined inline within their parent function file when not shared
- **Fish autoloading rule:** Fish autoloads one function per file (`functions/__hawt_foo.fish` → `__hawt_foo`). Functions defined in the same file as the autoloaded function are available within the same process, but NOT in child `fish -c` processes. Any function invoked via `fish -c` (e.g., inside `flock ... fish -c 'func'`) must have its own file in `functions/`.

## Security Architecture

**Sandbox isolation (`__hawt_sandbox`):**
- Read-only root filesystem with selective writable mounts
- Home directory isolation via `--tmpfs /home` with explicit re-binds for config
- `.env` nullification (mount `/dev/null` over `.env*` files)
- Path remapping - worktree mounted at `$HAWT_SANDBOX_HOME/<name>` (default `/home/code/<name>`)
- PID namespace isolation (`--unshare-pid`)
- `--die-with-parent` ensures orphan cleanup

**Locking (`flock`):**
- Kernel-managed via `flock(1)` - auto-releases on process death, no stale locks
- `.hawt-lock` is a plain file (not directory), used as the flock target
- `.hawt-session-meta` stores PID + timestamp for `hawt ps` display (informational only)
- `flock --close` prevents fd inheritance to bwrap child processes

**Trust-on-first-use:**
- `.worktreerc` post-create commands and `.worktree-hooks/` scripts require SHA-256 hash-based trust approval before execution
- Trust entries stored as `hash:filepath` lines in `.hawt-trusted`
- `.worktreerc` bwrap directives (`bwrap-bind-ro`, `bwrap-bind-rw`, `bwrap-tmpfs`) are validated against a path blocklist (system dirs like `/proc`, `/dev`, `/sys`, `/etc`, `/home`, etc.)

## Testing

**Framework:** Fishtape (auto-downloaded to `tests/.cache/fishtape.fish`)
**Run:** `make test`
**Discovery:** `tests/test_*.fish`
**Helpers:** `tests/setup.fish` provides `hawt_test_make_repo`, `hawt_test_make_repo_with_worktree`, `hawt_test_has_arg_pair`
