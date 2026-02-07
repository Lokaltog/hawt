function __hawt_unlock --description "Unlock a worktree"
    set -l name $argv[1]
    if test -z "$name"
        __hawt_error "Usage: hawt unlock <name>"
        return 1
    end

    set -l hawt_path (__hawt_resolve_worktree "$name"); or return 1

    set -l lock_file "$hawt_path/.hawt-lock"
    set -l meta_file "$hawt_path/.hawt-session-meta"

    # Check if there's any lock state
    if not test -f "$lock_file" -o -f "$meta_file"
        echo (set_color brblack)"Worktree '$name' is not locked"(set_color normal)
        return 0
    end

    # Read PID from session metadata
    set -l pid ""
    if test -f "$meta_file"
        set pid (head -1 "$meta_file" | string trim)
    end

    # Warn if the lock owner is still alive
    if test -n "$pid"; and kill -0 "$pid" 2>/dev/null
        echo (set_color yellow)"Lock owner (PID $pid) is still alive"(set_color normal)
        read -l -P "  Force unlock? [y/N] " confirm
        if test "$confirm" != y -a "$confirm" != Y
            return 1
        end

        # Kill the holder so the kernel flock is released (matches hawt kill behavior)
        kill -TERM "$pid" 2>/dev/null
        sleep 1
        if kill -0 "$pid" 2>/dev/null
            kill -KILL "$pid" 2>/dev/null
        end
    end

    __hawt_lock_release "$hawt_path"
    echo (set_color green)"Unlocked worktree '$name'"(set_color normal)
end
