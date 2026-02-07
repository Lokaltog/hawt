function __hawt_sandbox_run --description "Run a command in bwrap sandbox"
    # We need manual -- splitting here because argparse would consume flags
    # meant for __hawt_sandbox (--offline, --mount-ro, etc.) which we pass through.
    # We only parse --dry-run ourselves; everything else before -- goes to __hawt_sandbox.
    set -l separator_idx 0
    set -l i 1
    while test $i -le (count $argv)
        if test "$argv[$i]" = --
            set separator_idx $i
            break
        end
        set i (math $i + 1)
    end

    if test $separator_idx -eq 0
        __hawt_error "Usage: hawt sandbox [options...] -- <command> [args...]"
        return 1
    end

    # Split into sandbox opts (before --) and tool command (after --)
    set -l sandbox_opts
    if test $separator_idx -gt 1
        set sandbox_opts $argv[1..(math $separator_idx - 1)]
    end
    set -l tool_cmd
    if test $separator_idx -lt (count $argv)
        set tool_cmd $argv[(math $separator_idx + 1)..]
    end

    if test (count $tool_cmd) -eq 0
        __hawt_error "No command specified after --"
        return 1
    end

    # Extract --dry-run (ours, not __hawt_sandbox's)
    set -l dry_run 0
    set -l filtered_opts
    for opt in $sandbox_opts
        if test "$opt" = --dry-run
            set dry_run 1
        else
            set -a filtered_opts $opt
        end
    end

    # Default project path to current directory
    set -l has_path 0
    for opt in $filtered_opts
        if not string match -q -- '--*' "$opt"
            set has_path 1
            break
        end
    end
    if test $has_path -eq 0
        set -a filtered_opts (pwd)
    end

    set -l bwrap_cmd (__hawt_sandbox $filtered_opts)
    set -a bwrap_cmd -- $tool_cmd

    if test $dry_run -eq 1
        echo ""
        echo (set_color --bold)"Dry run - would execute:"(set_color normal)
        echo ""
        for part in $bwrap_cmd
            echo "  $part"
        end
        return 0
    end

    $bwrap_cmd
end
