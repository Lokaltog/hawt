function __hawt_resolve_worktree --description "Map worktree name to path" -a name
    set -l root (__hawt_repo_root); or return 1
    set -l hawt_base (__hawt_worktree_base "$root")
    set -l hawt_path "$hawt_base/$name"

    if not test -d "$hawt_path"
        __hawt_error "Worktree '$name' not found"
        return 1
    end

    echo "$hawt_path"
end
