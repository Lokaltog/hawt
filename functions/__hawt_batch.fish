function __hawt_batch --description "Launch parallel CC sessions from taskfile"
    argparse 'f/from=' dry-run 'j/max-parallel=' -- $argv; or return 1

    set -l taskfile $argv[1]
    set -l base_ref (set -q _flag_from; and echo $_flag_from; or echo HEAD)
    set -l dry_run 0
    set -l max_parallel (set -q _flag_max_parallel; and echo $_flag_max_parallel; or echo 4)
    set -q _flag_dry_run; and set dry_run 1

    if not string match -rq '^\d+$' "$max_parallel"; or test "$max_parallel" -lt 1
        __hawt_error "--max-parallel must be a positive integer (got: $max_parallel)"
        return 1
    end

    if test -z "$taskfile" -o ! -f "$taskfile"
        __hawt_error "Usage: hawt batch <taskfile> [--from <ref>] [--max-parallel <n>]"
        echo "" >&2
        echo "  Taskfile format:" >&2
        echo "    feature-auth: Implement OAuth2 flow" >&2
        echo "    fix-perf: Profile and fix slow queries" >&2
        return 1
    end

    set -l root (__hawt_repo_root); or return 1

    # Parse taskfile
    set -l names
    set -l tasks

    while read -l line
        # Skip comments and blank lines
        if string match -q '#*' "$line"; or test -z "$(string trim "$line")"
            continue
        end

        set -l parsed (string match -r '^([^:]+):\s*(.+)' "$line")
        if test (count $parsed) -lt 3
            echo (set_color yellow)"Skipping malformed line: $line"(set_color normal) >&2
            continue
        end

        set -l name (string trim $parsed[2])
        set -l task (string trim $parsed[3])
        set -a names "$name"
        set -a tasks "$task"
    end <"$taskfile"

    if test (count $names) -eq 0
        __hawt_error "No tasks found in $taskfile"
        return 1
    end

    echo ""
    echo (set_color --bold)"Batch: $taskfile"(set_color normal)
    echo (set_color brblack)(string repeat -n 60 "─")(set_color normal)
    echo (set_color brblack)"  Tasks:        "(count $names)(set_color normal)
    echo (set_color brblack)"  Base ref:     $base_ref"(set_color normal)
    echo (set_color brblack)"  Max parallel: $max_parallel"(set_color normal)
    echo ""

    for j in (seq (count $names))
        printf "  %-25s %s\n" (set_color cyan)$names[$j](set_color normal) $tasks[$j]
    end
    echo ""

    if test $dry_run -eq 1
        echo (set_color yellow)"Dry run - no sessions launched"(set_color normal)
        return 0
    end

    read -l -P "Launch all sessions? [Y/n] " confirm
    if test "$confirm" = n -o "$confirm" = N
        return 1
    end

    # Track launched PIDs
    set -l pids
    set -l running 0

    for j in (seq (count $names))
        # Throttle if at max parallel
        while test $running -ge $max_parallel
            # Wait for any child to finish
            sleep 1
            set running 0
            for pid in $pids
                if kill -0 "$pid" 2>/dev/null
                    set running (math $running + 1)
                end
            end
        end

        set -l name $names[$j]
        set -l task $tasks[$j]

        echo (set_color blue)"[$j/"(count $names)"] Launching: $name"(set_color normal)

        # Launch in background - each hawt cc handles its own worktree creation + bwrap
        # Pass task via environment variable to avoid shell injection from taskfile content
        HAWT_BATCH_TASK="$task" fish -c '
            __hawt_cc $argv[1] --from $argv[2] --task "$HAWT_BATCH_TASK"
        ' -- "$name" "$base_ref" &

        set -a pids $last_pid
        set running (math $running + 1)

        # Small delay to avoid git lock contention on worktree creation
        sleep 1
    end

    echo ""
    echo (set_color magenta)"All sessions launched. Monitor with: hawt ps"(set_color normal)
    echo (set_color brblack)"  PIDs: $pids"(set_color normal)

    # Optionally wait for all
    read -l -P "Wait for all sessions to complete? [y/N] " wait_confirm
    if test "$wait_confirm" = y -o "$wait_confirm" = Y
        echo (set_color brblack)"Waiting for all sessions..."(set_color normal)
        for pid in $pids
            wait $pid 2>/dev/null
        end
        echo (set_color green)"✓ All sessions complete"(set_color normal)
        echo ""
        echo "Review results:"
        for name in $names
            echo "  hawt diff $name"
        end
        echo ""
        echo "Merge all:"
        for name in $names
            echo "  hawt merge $name"
        end
    end
end
