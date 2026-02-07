function __hawt_lock_acquire --description "Probe lock availability" -a hawt_path
    set -l lock_file "$hawt_path/.hawt-lock"

    # If lock file doesn't exist, the lock is available
    if not test -e "$lock_file"
        return 0
    end

    # Probe: try a non-blocking flock; if it succeeds the lock is free
    if flock --nonblock "$lock_file" true 2>/dev/null
        return 0
    end

    # Lock is held by another process
    set -l pid ""
    set -l lock_time ""
    set -l meta_file "$hawt_path/.hawt-session-meta"
    if test -f "$meta_file"
        set pid (head -1 "$meta_file" | string trim)
        set lock_time (sed -n '2p' "$meta_file" | string trim)
    end

    if test -n "$pid"
        __hawt_error "Worktree is locked by PID $pid (since $lock_time)"
        echo (set_color brblack)"  Use 'hawt unlock "(basename "$hawt_path")"' or 'hawt kill "(basename "$hawt_path")"' to force"(set_color normal) >&2
    end

    return 1
end
