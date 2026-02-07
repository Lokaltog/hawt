function __hawt_repo_root --description "Resolve git repo root"
    set -l root (git rev-parse --show-toplevel 2>/dev/null)
    if test -z "$root"
        __hawt_error "Not in a git repository"
        return 1
    end

    # If we're in a worktree, resolve back to the main repo
    set -l common_dir (git rev-parse --git-common-dir 2>/dev/null)
    if test -n "$common_dir"
        set -l resolved (realpath "$common_dir" 2>/dev/null)
        if string match -q "*/.git" "$resolved"
            set root (string replace "/.git" "" "$resolved")
        end
    end

    echo "$root"
end
