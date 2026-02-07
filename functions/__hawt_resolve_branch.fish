function __hawt_resolve_branch --description "Map worktree name to branch" -a name
    for candidate in "cc/$name" "$name"
        if git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null
            echo "$candidate"
            return 0
        end
    end

    __hawt_error "No branch found for '$name'"
    return 1
end
