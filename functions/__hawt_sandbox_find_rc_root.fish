function __hawt_sandbox_find_rc_root --description "Resolve project path to repo root" -a project_path
    # Resolve to main repo root for .worktreerc lookup.
    # Falls back to project_path if not in a git repo (unlike __hawt_repo_root which errors).
    set -l rc_root (git -C "$project_path" rev-parse --show-toplevel 2>/dev/null)
    if test -z "$rc_root"
        echo "$project_path"
        return
    end

    # Resolve through git-common-dir to find the main repo (same logic as __hawt_repo_root)
    set -l common_dir (git -C "$project_path" rev-parse --git-common-dir 2>/dev/null)
    if test -n "$common_dir"
        # common_dir may be relative - resolve it against the project path, not CWD
        if not string match -q '/*' "$common_dir"
            set common_dir "$project_path/$common_dir"
        end
        set -l resolved (realpath "$common_dir" 2>/dev/null)
        if string match -q "*/.git" "$resolved"
            set rc_root (string replace "/.git" "" "$resolved")
        end
    end

    echo "$rc_root"
end
