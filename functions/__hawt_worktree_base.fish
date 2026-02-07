function __hawt_worktree_base --description "Return worktrees parent directory" -a root
    echo (dirname "$root")"/"(basename "$root")"-worktrees"
end
