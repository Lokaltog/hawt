function __hawt_checkpoint --description "Snapshot worktree state"
    set -l name $argv[1]
    if test -z "$name"
        __hawt_error "Usage: hawt checkpoint <n> [message]"
        return 1
    end

    set -l hawt_path (__hawt_resolve_worktree "$name"); or return 1

    set -l msg $argv[2..]
    if test -z "$msg"
        set msg "checkpoint: "(date '+%Y-%m-%d %H:%M:%S')
    end

    # Check for changes
    set -l dirty_count (__hawt_dirty_count "$hawt_path")

    if test "$dirty_count" -eq 0
        echo (set_color brblack)"No uncommitted changes in '$name'"(set_color normal)
        return 0
    end

    echo (set_color blue)"Checkpointing '$name': $dirty_count file(s)..."(set_color normal)

    # Show what's being committed
    git -C "$hawt_path" status --short 2>/dev/null | head -20
    if test "$dirty_count" -gt 20
        echo (set_color brblack)"  ... and "(math $dirty_count - 20)" more"(set_color normal)
    end
    echo ""

    # Stage and commit
    git -C "$hawt_path" add -A
    git -C "$hawt_path" commit -m "$msg"

    if test $status -eq 0
        set -l hash (git -C "$hawt_path" rev-parse --short HEAD)
        echo (set_color green)"✓ Checkpoint $hash: $msg"(set_color normal)
    else
        __hawt_error "Failed to create checkpoint"
        return 1
    end
end
