function __hawt_maybe_stash --description "Offer to stash dirty state"
    # Check if current directory is a git worktree with dirty state
    if git rev-parse --git-dir >/dev/null 2>&1
        set -l dirty_count (__hawt_dirty_count ".")
        if test "$dirty_count" -gt 0
            echo (set_color yellow)"Current worktree has $dirty_count uncommitted changes."(set_color normal)
            read -l -P "  Stash before switching? [y/N] " confirm
            if test "$confirm" = y -o "$confirm" = Y
                git stash push -m "hawt auto-stash before switch"
                echo (set_color green)"  Stashed."(set_color normal)
            end
        end
    end
end
