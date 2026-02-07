function __hawt_lock --description "Lock a worktree"
    set -l name $argv[1]
    if test -z "$name"
        __hawt_error "Usage: hawt lock <name>"
        return 1
    end

    set -l hawt_path (__hawt_resolve_worktree "$name"); or return 1
    set -l lock_file "$hawt_path/.hawt-lock"

    # Probe first to give a clear error if already held
    if not __hawt_lock_acquire "$hawt_path"
        return 1
    end

    touch "$lock_file"
    echo (set_color green)"Locked worktree '$name'"(set_color normal)
    flock --nonblock --close "$lock_file" fish -c 'read -l -P "Press Enter to unlock..."'
    echo (set_color green)"Unlocked worktree '$name'"(set_color normal)
end
