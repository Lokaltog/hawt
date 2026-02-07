function __hawt_post_session --description "Auto-commit after CC session" -a hawt_path -a session_id
    set -l dirty_count (__hawt_dirty_count "$hawt_path")

    if test "$dirty_count" -gt 0
        echo ""
        echo (set_color yellow)"Auto-committing $dirty_count uncommitted changes..."(set_color normal)
        git -C "$hawt_path" add -A
        git -C "$hawt_path" commit -m "wip: cc session $session_id

Automated commit of uncommitted changes at end of Claude Code session.
Files changed: $dirty_count"
        echo (set_color green)"✓ Changes committed"(set_color normal)
    end
end
