function __hawt_worktree_base --description "Return worktrees parent directory" -a root
    # 1. Environment variable override
    if set -q HAWT_WORKTREE_DIR; and test -n "$HAWT_WORKTREE_DIR"
        echo "$HAWT_WORKTREE_DIR"
        return
    end

    # 2. Per-repo .worktreerc directive
    if test -f "$root/.worktreerc"
        while read -l line
            set -l m (string match -r '^worktree-dir:\s*(.+)' "$line")
            if test (count $m) -ge 2
                set -l dir (string trim $m[2])
                if string match -q '/*' "$dir"
                    echo "$dir"
                else
                    echo (path normalize "$root/$dir")
                end
                return
            end
        end <"$root/.worktreerc"
    end

    # 3. Default: <dirname>/<basename>-worktrees
    echo (dirname "$root")"/"(basename "$root")"-worktrees"
end
