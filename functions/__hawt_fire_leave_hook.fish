function __hawt_fire_leave_hook --description "Execute on-leave hook" -a hawt_path
    # Resolve to main repo to find hooks
    set -l git_common (git -C "$hawt_path" rev-parse --git-common-dir 2>/dev/null)
    if test -z "$git_common"
        return
    end

    set -l main_root (realpath "$git_common" 2>/dev/null | string replace "/.git" "")
    set -l hook_file "$main_root/.worktree-hooks/on-leave"

    if test -f "$hook_file"
        set -l trust_file "$main_root/.hawt-trusted"
        if not __hawt_check_file_trust "$hook_file" "$trust_file" "on-leave hook"
            return
        end
        pushd "$hawt_path"; or return 1
        if test -x "$hook_file"
            $hook_file
        else
            fish "$hook_file"
        end
        popd
    end
end
