# Completions for hawt - git worktree helper

# Disable file completions by default
complete -c hawt -f

# --- Completion helpers ---

function __hawt_complete_base --description "Resolve worktree base directory"
    set -l root (git rev-parse --show-toplevel 2>/dev/null); or return 1
    set -l common_dir (git rev-parse --git-common-dir 2>/dev/null)
    if test -n "$common_dir"
        set -l resolved (realpath "$common_dir" 2>/dev/null)
        if string match -q "*/.git" "$resolved"
            set root (string replace "/.git" "" "$resolved")
        end
    end
    echo (dirname "$root")/(basename "$root")-worktrees
end

function __hawt_complete_worktrees --description "List worktrees with branch names"
    set -l base (__hawt_complete_base); or return
    test -d "$base"; or return
    for name in (command ls -1 "$base" 2>/dev/null)
        set -l dir "$base/$name"
        test -d "$dir"; or continue
        set -l branch (git -C "$dir" branch --show-current 2>/dev/null)
        if test -n "$branch"
            printf '%s\t%s\n' "$name" "$branch"
        else
            echo "$name"
        end
    end
end

function __hawt_complete_locked_worktrees --description "List locked worktrees"
    set -l base (__hawt_complete_base); or return
    test -d "$base"; or return
    for name in (command ls -1 "$base" 2>/dev/null)
        set -l dir "$base/$name"
        set -l meta_file "$dir/.hawt-session-meta"
        set -l lock_file "$dir/.hawt-lock"

        # Check for session metadata or held flock
        if test -f "$meta_file"
            set -l pid (head -1 "$meta_file" | string trim)
            if test -n "$pid"; and kill -0 "$pid" 2>/dev/null
                printf '%s\t%s\n' "$name" "active (PID $pid)"
            else
                printf '%s\t%s\n' "$name" "stale lock"
            end
        else if test -f "$lock_file"; and not flock --nonblock "$lock_file" true 2>/dev/null
            printf '%s\t%s\n' "$name" locked
        else
            continue
        end
    end
end

function __hawt_sandbox_past_separator --description "Check if past -- in sandbox command"
    set -l cmd (commandline -opc)
    contains -- sandbox $cmd; or return 1
    contains -- -- $cmd; or return 1
end

# --- Subcommands ---
# Descriptions are derived from function --description to avoid duplication.
# Trigger autoload of hawt.fish (for inline functions) and each separate-file function.
# subcmd:function_name pairs - descriptions come from the function's --description
set -l _hawt_subcmds \
    status:__hawt_status \
    clean:__hawt_clean \
    tmp:__hawt_tmp \
    rm:__hawt_remove \
    cc:__hawt_cc \
    merge:__hawt_merge \
    diff:__hawt_diff \
    ps:__hawt_ps \
    kill:__hawt_kill \
    lock:__hawt_lock \
    unlock:__hawt_unlock \
    batch:__hawt_batch \
    review:__hawt_review \
    checkpoint:__hawt_checkpoint \
    sandbox:__hawt_sandbox_run \
    unload:__hawt_do_unload \
    reload:__hawt_do_reload \
    help:__hawt_help

for entry in $_hawt_subcmds
    set -l parts (string split : $entry)
    # Trigger autoload so the function definition (and its description) is available
    functions -q $parts[2] 2>/dev/null
    set -l desc (functions -D --verbose $parts[2] 2>/dev/null | sed -n 5p)
    if test -n "$desc" -a "$desc" != n/a
        complete -c hawt -n __fish_use_subcommand -a $parts[1] -d "$desc"
    else
        complete -c hawt -n __fish_use_subcommand -a $parts[1]
    end
end

# --- Worktree name completions ---

# Default (upsert) - existing worktrees with branch info
complete -c hawt -n __fish_use_subcommand -a "(__hawt_complete_worktrees)"

# Subcommands that accept any worktree name
for sub in cc merge diff rm review checkpoint lock tmp
    complete -c hawt -n "__fish_seen_subcommand_from $sub" -a "(__hawt_complete_worktrees)"
end

# kill/unlock - only locked worktrees with active/stale status
for sub in kill unlock
    complete -c hawt -n "__fish_seen_subcommand_from $sub" -a "(__hawt_complete_locked_worktrees)"
end

# --from flag (for upsert and cc)
complete -c hawt -n "not __fish_seen_subcommand_from status clean tmp rm help ps kill lock unlock batch review checkpoint" -l from -s f -d "Base branch/ref" -x -a "(git branch --format='%(refname:short)' 2>/dev/null)"

# cc-specific flags
complete -c hawt -n "__fish_seen_subcommand_from cc" -l task -s t -d "Task description (written to TASK.md)"
complete -c hawt -n "__fish_seen_subcommand_from cc" -l offline -d "Network isolation (no internet in sandbox)"
complete -c hawt -n "__fish_seen_subcommand_from cc" -l dry-run -d "Show bwrap command without executing"

# merge-specific flags
complete -c hawt -n "__fish_seen_subcommand_from merge" -l squash -d "Squash merge (default)"
complete -c hawt -n "__fish_seen_subcommand_from merge" -l rebase -d "Rebase then fast-forward"
complete -c hawt -n "__fish_seen_subcommand_from merge" -l merge -d "Merge commit (no-ff)"
complete -c hawt -n "__fish_seen_subcommand_from merge" -l keep -d "Keep worktree after merge"
complete -c hawt -n "__fish_seen_subcommand_from merge" -l no-delete-branch -d "Keep branch after merge"

# diff-specific flags
complete -c hawt -n "__fish_seen_subcommand_from diff" -l files -d "Show only file names"
complete -c hawt -n "__fish_seen_subcommand_from diff" -l stat -d "Show only stat summary"

# review-specific flags
complete -c hawt -n "__fish_seen_subcommand_from review" -l ai -d "Include AI code review"
complete -c hawt -n "__fish_seen_subcommand_from review" -l test -d "Run tests"

# sandbox-specific flags (before --)
complete -c hawt -n "__fish_seen_subcommand_from sandbox; and not __hawt_sandbox_past_separator" -l offline -d "Network isolation (no internet in sandbox)"
complete -c hawt -n "__fish_seen_subcommand_from sandbox; and not __hawt_sandbox_past_separator" -l no-remap -d "Keep host path (don't remap to /home/code/)"
complete -c hawt -n "__fish_seen_subcommand_from sandbox; and not __hawt_sandbox_past_separator" -l allow-env -d "Don't nullify .env files"
complete -c hawt -n "__fish_seen_subcommand_from sandbox; and not __hawt_sandbox_past_separator" -l mount-ro -d "Extra read-only bind mount (src[:dest])" -x
complete -c hawt -n "__fish_seen_subcommand_from sandbox; and not __hawt_sandbox_past_separator" -l mount-rw -d "Extra read-write bind mount (src[:dest])" -x
complete -c hawt -n "__fish_seen_subcommand_from sandbox; and not __hawt_sandbox_past_separator" -l dry-run -d "Show bwrap command without executing"

# sandbox: after --, complete commands and files
complete -c hawt -n __hawt_sandbox_past_separator -F -a "(complete -C (commandline -ct) 2>/dev/null)"

# batch-specific flags
complete -c hawt -n "__fish_seen_subcommand_from batch" -l from -s f -d "Base branch for all tasks" -x -a "(git branch --format='%(refname:short)' 2>/dev/null)"
complete -c hawt -n "__fish_seen_subcommand_from batch" -l dry-run -d "Preview tasks without launching"
complete -c hawt -n "__fish_seen_subcommand_from batch" -l max-parallel -s j -d "Max concurrent sessions"
complete -c hawt -n "__fish_seen_subcommand_from batch" -F # Allow file completion for taskfile arg
