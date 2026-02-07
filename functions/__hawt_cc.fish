function __hawt_cc --description "Launch Claude Code in bwrap sandbox"
    argparse 'f/from=' 't/task=' offline dry-run -- $argv; or return 1

    set -l name $argv[1]
    set -l base_ref (set -q _flag_from; and echo $_flag_from; or echo HEAD)
    set -l task (set -q _flag_task; and echo $_flag_task; or echo "")
    set -l offline 0
    set -l dry_run 0
    set -q _flag_offline; and set offline 1
    set -q _flag_dry_run; and set dry_run 1

    set -l root (__hawt_repo_root); or return 1

    if test -z "$name"
        # No-worktree mode: sandbox the current repo directly
        set -l cc_run_opts "$root" ""
        test $offline -eq 1; and set -a cc_run_opts --offline
        test $dry_run -eq 1; and set -a cc_run_opts --dry-run
        test -n "$task"; and set -a cc_run_opts --task "$task"
        __hawt_cc_run $cc_run_opts
    else
        # Worktree mode: create/reuse worktree, then sandbox it
        set -l hawt_base (__hawt_worktree_base "$root")
        set -l branch_name "cc/$name"
        set -l hawt_path "$hawt_base/$name"

        if not test -d "$hawt_path"
            echo (set_color blue)"Creating worktree '$name' (branch: $branch_name) from $base_ref..."(set_color normal)
            mkdir -p "$hawt_base"

            if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null
                git worktree add "$hawt_path" "$branch_name"
            else
                git worktree add -b "$branch_name" "$hawt_path" "$base_ref"
            end

            if test $status -ne 0
                __hawt_error "Failed to create worktree"
                return 1
            end

            __hawt_bootstrap "$root" "$hawt_path"
            __hawt_run_hook "$root" "$hawt_path" post-create
        else
            echo (set_color green)"Worktree '$name' exists"(set_color normal)
        end

        set -l cc_run_opts "$hawt_path" "$name"
        test $offline -eq 1; and set -a cc_run_opts --offline
        test $dry_run -eq 1; and set -a cc_run_opts --dry-run
        test -n "$task"; and set -a cc_run_opts --task "$task"
        __hawt_cc_run $cc_run_opts
    end
end

# __hawt_cc_run - Build sandbox, acquire flock, run CC
function __hawt_cc_run --description "Execute CC session with lock and sandbox"
    argparse offline dry-run 'task=' -- $argv; or return 1

    set -l project_path $argv[1]
    set -l name $argv[2]
    set -l offline 0
    set -l dry_run 0
    set -l task ""
    set -q _flag_offline; and set offline 1
    set -q _flag_dry_run; and set dry_run 1
    set -q _flag_task; and set task "$_flag_task"

    set -l is_worktree 0
    if test -n "$name"
        set is_worktree 1
    end

    # Probe lock availability
    if not __hawt_lock_acquire "$project_path"
        return 1
    end

    # Build bwrap command via __hawt_sandbox
    set -l sandbox_opts "$project_path"
    if test $offline -eq 1
        set -a sandbox_opts --offline
    end

    set -l bwrap_cmd (__hawt_sandbox $sandbox_opts)

    # Claude-specific home binds (writable - CC needs to persist state)
    for cc_path in $HOME/.claude $HOME/.claude.json $XDG_DATA_HOME/claude $HOME/.serena
        if test -e "$cc_path"
            set -a bwrap_cmd --bind-try "$cc_path" "$cc_path"
        end
    end

    # Append the command
    set -a bwrap_cmd -- (command -v claude)

    # Only skip permissions in worktree mode where CC operates in an isolated copy
    if test $is_worktree -eq 1
        set -a bwrap_cmd --dangerously-skip-permissions
    end

    if test $dry_run -eq 1
        echo ""
        echo (set_color --bold)"Dry run - would execute:"(set_color normal)
        echo ""
        for part in $bwrap_cmd
            echo "  $part"
        end
        return 0
    end

    # Write TASK.md if --task provided
    if test -n "$task"
        echo "$task" >"$project_path/TASK.md"
        echo (set_color blue)"Wrote TASK.md"(set_color normal)
    end

    set -l lock_file "$project_path/.hawt-lock"
    touch "$lock_file"

    # Write session metadata (informational - not part of lock protocol)
    set -l meta_file "$project_path/.hawt-session-meta"
    echo "$fish_pid" >"$meta_file"
    date '+%Y-%m-%d %H:%M:%S' >>"$meta_file"

    set -l branch (git -C "$project_path" branch --show-current 2>/dev/null; or echo "detached")

    echo (set_color magenta)"--- Launching Claude Code in sandbox ---"(set_color normal)
    if test $is_worktree -eq 1
        echo (set_color brblack)"  Worktree: $project_path"(set_color normal)
    else
        echo (set_color brblack)"  Repo:     $project_path"(set_color normal)
    end
    echo (set_color brblack)"  Branch:   $branch"(set_color normal)
    if test -n "$task"
        echo (set_color brblack)"  Task:     $task"(set_color normal)
    end
    echo ""

    # Launch CC inside bwrap, wrapped by flock for concurrency control.
    # --close prevents the lock fd from leaking into the child (bwrap),
    # so the lock releases when flock exits, not when bwrap exits.
    flock --nonblock --close --conflict-exit-code 1 "$lock_file" \
        $bwrap_cmd 2>&1
    set -l cc_exit $status

    # Post-session: auto-commit uncommitted work (worktree mode only)
    if test $is_worktree -eq 1
        set -l session_id (date +%Y%m%d-%H%M%S)
        __hawt_post_session "$project_path" "$session_id"
    end

    # Clean up lock artifacts
    __hawt_lock_release "$project_path"

    echo ""
    if test $cc_exit -eq 0
        if test $is_worktree -eq 1
            echo (set_color green)"CC session complete. Review with: hawt diff $name"(set_color normal)
            echo (set_color brblack)"  Merge with: hawt merge $name"(set_color normal)
        else
            echo (set_color green)"CC session complete."(set_color normal)
        end
    else
        echo (set_color yellow)"CC exited with code $cc_exit. Changes preserved."(set_color normal)
    end

    return $cc_exit
end
