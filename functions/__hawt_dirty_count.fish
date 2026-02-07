function __hawt_dirty_count --description "Count uncommitted changes" -a path
    git -C "$path" status --porcelain 2>/dev/null | wc -l | string trim
end
