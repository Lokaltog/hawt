function hawt --description "Git worktree helper with fzf, bootstrap, and lifecycle hooks"
    set -l subcmd $argv[1]

    switch "$subcmd"
        case status
            __hawt_status
        case clean
            __hawt_clean
        case tmp
            __hawt_tmp $argv[2..]
        case rm remove
            __hawt_remove $argv[2..]
        case help -h --help
            __hawt_help
        case ''
            __hawt_pick
        case cc
            __hawt_cc $argv[2..]
        case merge
            __hawt_merge $argv[2..]
        case diff
            __hawt_diff $argv[2..]
        case ps
            __hawt_ps
        case kill
            __hawt_kill $argv[2..]
        case lock
            __hawt_lock $argv[2..]
        case unlock
            __hawt_unlock $argv[2..]
        case sandbox
            __hawt_sandbox_run $argv[2..]
        case batch
            __hawt_batch $argv[2..]
        case review
            __hawt_review $argv[2..]
        case checkpoint
            __hawt_checkpoint $argv[2..]
        case unload
            __hawt_do_unload $argv[2..]
        case reload
            __hawt_do_reload
        case '*'
            # Anything else is treated as a worktree name to upsert
            __hawt_upsert $argv
    end
end

function __hawt_pick --description "Interactive fzf worktree picker"
    set -l root (__hawt_repo_root); or return 1
    set -l worktrees (git worktree list --porcelain | string replace -rf '^worktree (.+)' '$1')

    if test (count $worktrees) -le 1
        echo (set_color yellow)"No additional worktrees. Use: hawt <name> to create one."(set_color normal)
        return 1
    end

    set -l selected (
        for hawt_path in $worktrees
            set -l branch (git -C "$hawt_path" branch --show-current 2>/dev/null; or echo "detached")
            set -l dirty ""
            if test -n "$(git -C "$hawt_path" status --porcelain 2>/dev/null | head -1)"
                set dirty " ●"
            end
            set -l rel_path (string replace "$root/" "" "$hawt_path")
            if not string match -q "$rel_path" "$hawt_path"
                set rel_path (realpath --relative-to=(pwd) "$hawt_path" 2>/dev/null; or echo "$hawt_path")
            end
            printf "%s\t%s%s\t%s\n" "$hawt_path" (set_color cyan)"$branch"(set_color normal) (set_color red)"$dirty"(set_color normal) (set_color brblack)"$rel_path"(set_color normal)
        end | fzf --ansi --delimiter='\t' \
              --with-nth=2,3,4 \
              --header="Select worktree (enter=cd, ctrl-d=remove)" \
              --bind="ctrl-d:execute(git worktree remove --force {1})+reload(git worktree list --porcelain | grep '^worktree ' | sed 's/worktree //')" \
              --preview="git -C {1} log --oneline --graph -15 --color=always 2>/dev/null" \
              --preview-window=right:50%
    )

    if test -n "$selected"
        set -l target (echo "$selected" | cut -f1)
        cd "$target"
        __hawt_announce_path "Switched to: $target"
    end
end

function __hawt_upsert --description "Create or switch to a named worktree"
    argparse 'f/from=' -- $argv; or return 1

    set -l name $argv[1]
    set -l base_ref (set -q _flag_from; and echo $_flag_from; or echo HEAD)

    set -l root (__hawt_repo_root); or return 1
    set -l hawt_base (__hawt_worktree_base "$root")
    set -l hawt_path "$hawt_base/$name"

    # Check if worktree already exists
    if test -d "$hawt_path"
        cd "$hawt_path"
        __hawt_announce_path "Switched to worktree: $hawt_path"
        return 0
    end

    # Resolve base ref
    if not git rev-parse --verify "$base_ref" >/dev/null 2>&1
        __hawt_error "Ref '$base_ref' does not exist"
        return 1
    end

    # Auto-stash current worktree if dirty
    __hawt_maybe_stash

    echo (set_color blue)"Creating worktree '$name' from $base_ref..."(set_color normal)
    mkdir -p "$hawt_base"

    # Create worktree with a new branch named after the worktree
    if git show-ref --verify --quiet "refs/heads/$name" 2>/dev/null
        git worktree add "$hawt_path" "$name"
    else
        git worktree add -b "$name" "$hawt_path" "$base_ref"
    end

    if test $status -ne 0
        __hawt_error "Failed to create worktree"
        return 1
    end

    # Bootstrap the worktree
    __hawt_bootstrap "$root" "$hawt_path"

    # Run post-create hook
    __hawt_run_hook "$root" "$hawt_path" post-create

    echo (set_color green)"✓ Worktree '$name' ready"(set_color normal)
    cd "$hawt_path"
    __hawt_announce_path "Now in: $hawt_path"
end

function __hawt_status --description "Overview table of all worktrees"
    set -l root (__hawt_repo_root); or return 1

    # Determine default branch for fork-point fallback
    set -l default_branch ""
    set -l remote_head (git -C "$root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | string replace 'refs/remotes/origin/' '')
    if test -n "$remote_head"
        set default_branch "$remote_head"
    else
        for candidate in main master
            if git -C "$root" show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null
                set default_branch "$candidate"
                break
            end
        end
    end

    printf "\n"
    printf (set_color --bold)" %-30s %-25s %-15s %-15s %s\n"(set_color normal) WORKTREE BRANCH STATE "↑↓ SYNC" AGE
    printf " %s\n" (string repeat -n 95 "─")

    git worktree list --porcelain | while read -l line
        if string match -q "worktree *" "$line"
            set -l hawt_path (string replace "worktree " "" "$line")
            set -l branch (git -C "$hawt_path" branch --show-current 2>/dev/null; or echo "detached")
            set -l display_path (basename "$hawt_path")

            # Mark main worktree
            if test "$hawt_path" = "$root"
                set display_path "$display_path (main)"
            end

            # Dirty state
            set -l state_text clean
            set -l state_color green
            set -l dirty_count (__hawt_dirty_count "$hawt_path")
            if test "$dirty_count" -gt 0
                set state_text "dirty ($dirty_count)"
                set state_color red
            end

            # Ahead/behind - try upstream tracking, then remote branch, then fork-point
            set -l ab_text ""
            set -l ab_color brblack
            set -l upstream (git -C "$hawt_path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
            if test -z "$upstream"
                set -l remote_ref "origin/$branch"
                if git -C "$hawt_path" rev-parse --verify "$remote_ref" >/dev/null 2>&1
                    set upstream "$remote_ref"
                end
            end
            if test -n "$upstream"
                set -l ahead (git -C "$hawt_path" rev-list --count "$upstream..HEAD" 2>/dev/null; or echo 0)
                set -l behind (git -C "$hawt_path" rev-list --count "HEAD..$upstream" 2>/dev/null; or echo 0)
                if test "$ahead" -gt 0 -o "$behind" -gt 0
                    set ab_text "↑$ahead ↓$behind"
                    set ab_color yellow
                else
                    set ab_text "in sync"
                end
            else if test -n "$default_branch" -a "$branch" != "$default_branch"
                set -l ahead (git -C "$hawt_path" rev-list --count "$default_branch..HEAD" 2>/dev/null; or echo 0)
                if test "$ahead" -gt 0
                    set ab_text "↑$ahead vs $default_branch"
                    set ab_color cyan
                else
                    set ab_text "=$default_branch"
                end
            else
                set ab_text "no upstream"
            end

            # Age of last commit
            set -l age (git -C "$hawt_path" log -1 --format='%cr' 2>/dev/null; or echo "unknown")

            # Pad plain text before applying colors to avoid ANSI codes breaking printf widths
            set -l c1 (string pad -r -w 30 -- "$display_path")
            set -l c2 (string pad -r -w 25 -- "$branch")
            set -l c3 (string pad -r -w 15 -- "$state_text")
            set -l c4 (string pad -r -w 15 -- "$ab_text")

            printf " %s %s%s%s %s%s%s %s%s%s %s%s%s\n" \
                "$c1" \
                (set_color cyan) "$c2" (set_color normal) \
                (set_color $state_color) "$c3" (set_color normal) \
                (set_color $ab_color) "$c4" (set_color normal) \
                (set_color brblack) "$age" (set_color normal)
        end
    end
    printf "\n"
end

function __hawt_clean --description "Prune stale refs and orphaned directories"
    set -l root (__hawt_repo_root); or return 1
    set -l hawt_base (__hawt_worktree_base "$root")

    echo (set_color blue)"Pruning stale worktree references..."(set_color normal)
    git worktree prune -v

    # Check for orphaned directories in the worktree base
    if test -d "$hawt_base"
        set -l tracked_paths (git worktree list --porcelain | string match -r 'worktree (.+)' | string replace 'worktree ' '')

        for dir in $hawt_base/*/
            set -l dir (string trim --right --chars=/ "$dir")
            if not contains "$dir" $tracked_paths
                echo (set_color yellow)"Orphaned directory: $dir"(set_color normal)
                read -l -P "  Remove? [y/N] " confirm
                if test "$confirm" = y -o "$confirm" = Y
                    rm -rf "$dir"
                    echo (set_color green)"  Removed."(set_color normal)
                end
            end
        end
    end

    echo (set_color green)"✓ Clean complete"(set_color normal)
end

function __hawt_tmp --description "Create an ephemeral worktree in /tmp"
    set -l name $argv[1]
    if test -z "$name"
        set name "tmp-"(date +%s | tail -c 7)
    end

    set -l root (__hawt_repo_root); or return 1
    set -l tmp_path "/tmp/hawt-"(basename "$root")"-$name"

    echo (set_color magenta)"Creating ephemeral worktree '$name'..."(set_color normal)
    git worktree add --detach "$tmp_path" HEAD

    if test $status -ne 0
        return 1
    end

    __hawt_bootstrap "$root" "$tmp_path"

    # Tag this as ephemeral so the leave hook can auto-clean
    echo "$tmp_path" >>"$root/.git/hawt-ephemeral"

    echo (set_color green)"✓ Ephemeral worktree ready"(set_color normal)
    echo (set_color brblack)"  Will be cleaned up on hawt clean or leave"(set_color normal)
    cd "$tmp_path"
    __hawt_announce_path "Now in: $tmp_path"
end

function __hawt_remove --description "Remove a worktree"
    set -l name $argv[1]
    if test -z "$name"
        __hawt_error "Usage: hawt rm <name>"
        return 1
    end

    set -l root (__hawt_repo_root); or return 1
    set -l hawt_base (__hawt_worktree_base "$root")
    set -l hawt_path "$hawt_base/$name"

    if not test -d "$hawt_path"
        # Try matching by branch name in all worktrees
        set hawt_path (git worktree list --porcelain | while read -l line
            if string match -q "worktree *" "$line"
                set -l p (string replace "worktree " "" "$line")
                set -l b (git -C "$p" branch --show-current 2>/dev/null)
                if test "$b" = "$name"
                    echo "$p"
                    break
                end
            end
        end)
    end

    if test -z "$hawt_path" -o ! -d "$hawt_path"
        __hawt_error "Worktree '$name' not found"
        return 1
    end

    # Warn if dirty
    set -l dirty_count (__hawt_dirty_count "$hawt_path")
    if test "$dirty_count" -gt 0
        echo (set_color yellow)"⚠ Worktree has $dirty_count uncommitted changes"(set_color normal)
        read -l -P "  Force remove? [y/N] " confirm
        if test "$confirm" != y -a "$confirm" != Y
            return 1
        end
        git worktree remove --force "$hawt_path"
    else
        git worktree remove "$hawt_path"
    end

    echo (set_color green)"✓ Removed worktree '$name'"(set_color normal)
end

function __hawt_help --description "Show help"
    echo ""
    echo (set_color --bold cyan)"  ╻ ╻┏━┓╻ ╻╺┳╸"(set_color normal)
    echo (set_color --bold cyan)"  ┣━┫┣━┫┃╻┃ ┃ "(set_color normal)"  git worktree helper"
    echo (set_color --bold cyan)"  ╹ ╹╹ ╹┗┻┛ ╹ "(set_color normal)"  for sandboxed AI agents"
    echo ""
    echo (set_color brblack)"  AI agents are great until two of them edit the same file."(set_color normal)
    echo (set_color brblack)"  hawt gives each agent its own worktree and locks it in a sandbox."(set_color normal)
    echo ""
    echo (set_color --bold yellow)"  WORKTREE MANAGEMENT "(set_color brblack)(string repeat -n 39 "─")(set_color normal)
    echo ""
    echo "  hawt                              Interactive fzf picker "(set_color brblack)"(ctrl-d to remove)"(set_color normal)
    echo "  hawt <name> [--from <ref>]        Create or switch to a named worktree"
    echo "  hawt status                       Table view: branch, dirty state, sync, age"
    echo "  hawt tmp [name]                   Ephemeral worktree in /tmp "(set_color brblack)"(auto-cleaned)"(set_color normal)
    echo "  hawt rm <name>                    Remove a worktree"
    echo "  hawt clean                        Prune stale refs and orphaned directories"
    echo ""
    echo (set_color --bold yellow)"  CLAUDE CODE INTEGRATION "(set_color brblack)(string repeat -n 35 "─")(set_color normal)
    echo ""
    echo "  hawt cc                           Run CC in sandbox on current repo"
    echo "  hawt cc <name> [--from <ref>]     Run CC in sandboxed worktree"
    echo "    --task \"...\"                     Write task to TASK.md before launching"
    echo "    --offline                        Disable network inside sandbox"
    echo "    --dry-run                        Print bwrap command only"
    echo ""
    echo (set_color --bold yellow)"  BATCH & SESSION MANAGEMENT "(set_color brblack)(string repeat -n 32 "─")(set_color normal)
    echo ""
    echo "  hawt batch <taskfile> [-j N]      Launch parallel CC sessions from taskfile"
    echo "  hawt ps                           Show running sessions: PID, uptime, branch"
    echo "  hawt kill <name>                  Terminate a session and clean up"
    echo "  hawt lock <name>                  Manually lock a worktree"
    echo "  hawt unlock <name>                Manually unlock a worktree"
    echo ""
    echo (set_color --bold yellow)"  REVIEW & MERGE "(set_color brblack)(string repeat -n 43 "─")(set_color normal)
    echo ""
    echo "  hawt diff <name> [--files|--stat] Review worktree changes"
    echo "  hawt review <name> [--ai] [--test] Post-session review: commits, stats, logs"
    echo "  hawt merge <name> [--squash|...]  Merge worktree branch back "(set_color brblack)"(default: squash)"(set_color normal)
    echo "  hawt checkpoint <name> [msg]      Commit worktree state from outside"
    echo ""
    echo (set_color --bold yellow)"  SANDBOX "(set_color brblack)(string repeat -n 51 "─")(set_color normal)
    echo ""
    echo "  hawt sandbox [opts] -- <cmd>      Run any command in a bwrap sandbox"
    echo (set_color brblack)"    --offline  --no-remap  --allow-env  --mount-ro  --mount-rw  --dry-run"(set_color normal)
    echo ""
    echo (set_color --bold yellow)"  CONFIGURATION "(set_color brblack)(string repeat -n 44 "─")(set_color normal)
    echo ""
    echo "  .worktreerc                       Bootstrap config "(set_color brblack)"(symlinks, copies, hooks)"(set_color normal)
    echo "  .worktree-hooks/post-create       Runs after worktree creation"
    echo "  .worktree-hooks/on-leave          Runs when leaving a worktree"
    echo "  tasks.hawt                        Batch task definitions "(set_color brblack)"(name: description)"(set_color normal)
    echo ""
    echo (set_color brblack)"  Worktrees: ../<repo>-worktrees/<name> "(set_color normal)"(override: .worktreerc or HAWT_WORKTREE_DIR)"
    echo ""
end
