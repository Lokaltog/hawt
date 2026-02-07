function __hawt_maybe_clean_ephemeral --description "Auto-remove ephemeral worktrees" -a hawt_path
    # Check if this worktree is tagged as ephemeral
    set -l git_common (git -C "$hawt_path" rev-parse --git-common-dir 2>/dev/null)
    if test -z "$git_common"
        return
    end

    set -l main_root (realpath "$git_common" 2>/dev/null | string replace "/.git" "")
    set -l ephemeral_file "$main_root/.git/hawt-ephemeral"

    if test -f "$ephemeral_file"
        if grep -qF "$hawt_path" "$ephemeral_file"
            echo (set_color magenta)"Cleaning up ephemeral worktree: "(basename "$hawt_path")(set_color normal)
            git worktree remove --force "$hawt_path" 2>/dev/null
            # Remove from ephemeral tracking
            set -l tmp (mktemp "$ephemeral_file.XXXXXX")
            grep -vF "$hawt_path" "$ephemeral_file" >"$tmp"
            mv "$tmp" "$ephemeral_file"
        end
    end
end
