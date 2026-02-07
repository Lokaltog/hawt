function __hawt_on_pwd_change --description "Detect leaving a git worktree" --on-variable PWD
    set -l old $__hawt_last_pwd
    set -q __hawt_last_pwd; or set -g __hawt_last_pwd ""
    set -g __hawt_last_pwd $PWD

    # Skip if old pwd is empty (first cd) or same directory
    if test -z "$old" -o "$old" = "$PWD"
        return
    end

    # Check if we LEFT a worktree (old was in a worktree, new is not the same one)
    set -l old_git_dir ""
    if test -d "$old/.git" -o -f "$old/.git"
        set old_git_dir "$old"
    else
        # Walk up from old path to find .git
        set -l check "$old"
        while test "$check" != /
            if test -d "$check/.git" -o -f "$check/.git"
                set old_git_dir "$check"
                break
            end
            set check (dirname "$check")
        end
    end

    if test -z "$old_git_dir"
        return
    end

    # Is the old dir actually a worktree (not the main repo)?
    if test -f "$old_git_dir/.git"
        # It's a linked worktree (.git is a file, not a directory)
        set -l still_in_same 0
        if test "$PWD" = "$old_git_dir"; or string match -q "$old_git_dir/*" "$PWD"
            set still_in_same 1
        end

        if test $still_in_same -eq 0
            __hawt_fire_leave_hook "$old_git_dir"

            # Auto-clean ephemeral worktrees
            __hawt_maybe_clean_ephemeral "$old_git_dir"
        end
    end
end
