function __hawt_ps --description "Show running CC sessions"
    set -l root (__hawt_repo_root); or return 1
    set -l hawt_base (__hawt_worktree_base "$root")
    set -l found 0

    printf "\n"
    printf (set_color --bold)" %-25s %-10s %-12s %-20s %-15s %s\n"(set_color normal) WORKTREE PID UPTIME BRANCH STATE LOCK
    printf " %s\n" (string repeat -n 95 "─")

    for hawt_dir in $hawt_base/*/
        set -l hawt_path (string trim --right --chars=/ "$hawt_dir")
        set -l name (basename "$hawt_path")
        set -l lock_file "$hawt_path/.hawt-lock"
        set -l meta_file "$hawt_path/.hawt-session-meta"
        set -l branch (git -C "$hawt_path" branch --show-current 2>/dev/null; or echo "?")

        # Dirty state
        set -l state_text clean
        set -l state_color green
        set -l dirty_count (__hawt_dirty_count "$hawt_path")
        if test "$dirty_count" -gt 0
            set state_text "dirty ($dirty_count)"
            set state_color red
        end

        set -l pid_text -
        set -l pid_color normal
        set -l uptime -
        set -l lock_text unlocked
        set -l lock_color brblack

        # Read PID from session metadata
        if test -f "$meta_file"
            set pid_text (head -1 "$meta_file" | string trim)
            set -l lock_time (sed -n '2p' "$meta_file" | string trim)

            if test -n "$pid_text"; and kill -0 "$pid_text" 2>/dev/null
                # Process is alive - probe flock to confirm active lock
                if test -f "$lock_file"; and not flock --nonblock "$lock_file" true 2>/dev/null
                    set lock_text active
                    set lock_color green
                else
                    set lock_text "running (no flock)"
                    set lock_color yellow
                end

                # Calculate uptime from metadata timestamp
                if test -n "$lock_time"
                    set -l lock_epoch (date -d "$lock_time" +%s 2>/dev/null)
                    if test -n "$lock_epoch"
                        set -l now (date +%s)
                        set -l elapsed (math $now - $lock_epoch)
                        set uptime (__hawt_format_duration $elapsed)
                    end
                end
            else
                set lock_text stale
                set lock_color yellow
                set pid_text "$pid_text†"
                set pid_color brblack
            end
        else if test -f "$lock_file"; and not flock --nonblock "$lock_file" true 2>/dev/null
            # Lock file held but no metadata
            set lock_text "locked (no meta)"
            set lock_color yellow
        end

        # Pad plain text before applying colors to avoid ANSI codes breaking printf widths
        set -l c1 (string pad -r -w 25 -- "$name")
        set -l c2 (string pad -r -w 10 -- "$pid_text")
        set -l c3 (string pad -r -w 12 -- "$uptime")
        set -l c4 (string pad -r -w 20 -- "$branch")
        set -l c5 (string pad -r -w 15 -- "$state_text")

        printf " %s %s%s%s %s %s%s%s %s%s%s %s%s%s\n" \
            "$c1" \
            (set_color $pid_color) "$c2" (set_color normal) \
            "$c3" \
            (set_color cyan) "$c4" (set_color normal) \
            (set_color $state_color) "$c5" (set_color normal) \
            (set_color $lock_color) "$lock_text" (set_color normal)
        set found 1
    end

    if test $found -eq 0
        echo (set_color brblack)"  No worktrees found"(set_color normal)
    end

    # Also check for bwrap processes related to this repo
    echo ""
    set -l bwrap_pids (pgrep -f "bwrap.*$hawt_base" 2>/dev/null)
    if test -n "$bwrap_pids"
        echo (set_color brblack)"  Active bwrap PIDs: $bwrap_pids"(set_color normal)
    end

    printf "\n"
end
