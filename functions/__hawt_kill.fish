function __hawt_kill --description "Terminate a CC session"
    set -l name $argv[1]
    if test -z "$name"
        __hawt_error "Usage: hawt kill <name>"
        return 1
    end

    set -l hawt_path (__hawt_resolve_worktree "$name"); or return 1

    set -l lock_file "$hawt_path/.hawt-lock"
    set -l meta_file "$hawt_path/.hawt-session-meta"

    if not test -f "$lock_file" -o -f "$meta_file"
        echo (set_color yellow)"No active session for '$name'"(set_color normal)
        return 0
    end

    # Read PID from session metadata
    set -l pid ""
    if test -f "$meta_file"
        set pid (head -1 "$meta_file" | string trim)
    end

    if test -n "$pid"
        if kill -0 "$pid" 2>/dev/null
            echo (set_color yellow)"Terminating CC session (PID: $pid) for '$name'..."(set_color normal)

            # Try graceful SIGTERM first
            kill -TERM "$pid" 2>/dev/null
            sleep 2

            # Check if still alive, force kill
            if kill -0 "$pid" 2>/dev/null
                echo (set_color yellow)"Process still alive, sending SIGKILL..."(set_color normal)
                kill -KILL "$pid" 2>/dev/null

                # Also kill any child bwrap processes
                set -l children (pgrep -P "$pid" 2>/dev/null)
                for child in $children
                    kill -KILL "$child" 2>/dev/null
                end
            end

            echo (set_color green)"Session terminated"(set_color normal)
        else
            echo (set_color brblack)"Process $pid already dead (stale lock)"(set_color normal)
        end
    end

    # Clean up lock artifacts directly
    rm -f "$lock_file" "$meta_file"

    # Auto-commit any orphaned changes
    set -l dirty_count (__hawt_dirty_count "$hawt_path")
    if test "$dirty_count" -gt 0
        echo (set_color yellow)"Auto-committing $dirty_count orphaned changes..."(set_color normal)
        git -C "$hawt_path" add -A
        git -C "$hawt_path" commit -m "wip: auto-commit after killed cc session"
        echo (set_color green)"Changes preserved"(set_color normal)
    end
end
