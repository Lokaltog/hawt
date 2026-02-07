function __hawt_review --description "Post-session review"
    argparse ai test -- $argv; or return 1

    set -l name $argv[1]
    set -l do_ai 0
    set -l do_test 0
    set -q _flag_ai; and set do_ai 1
    set -q _flag_test; and set do_test 1

    if test -z "$name"
        __hawt_error "Usage: hawt review <name> [--ai] [--test]"
        return 1
    end

    set -l root (__hawt_repo_root); or return 1
    set -l hawt_base (__hawt_worktree_base "$root")
    set -l hawt_path "$hawt_base/$name"

    # Resolve branch
    set -l branch_name (__hawt_resolve_branch "$name"); or return 1

    set -l current_branch (git -C "$root" branch --show-current)
    set -l merge_base (git -C "$root" merge-base "$current_branch" "$branch_name" 2>/dev/null)

    echo ""
    echo (set_color --bold)"═══ Review: $name ($branch_name) ═══"(set_color normal)
    echo ""

    # Commit summary
    echo (set_color --bold)"Commits"(set_color normal)
    echo (set_color brblack)(string repeat -n 50 "─")(set_color normal)

    set -l commit_count (git -C "$root" rev-list --count "$merge_base..$branch_name" 2>/dev/null)
    echo (set_color brblack)"$commit_count commit(s)"(set_color normal)
    echo ""
    git -C "$root" log --format='  %C(yellow)%h%C(reset) %s %C(dim)(%cr)%C(reset)' "$merge_base..$branch_name" 2>/dev/null
    echo ""

    # Change summary
    echo (set_color --bold)"Changes"(set_color normal)
    echo (set_color brblack)(string repeat -n 50 "─")(set_color normal)
    git -C "$root" diff --stat "$merge_base..$branch_name" 2>/dev/null
    echo ""
    git -C "$root" diff --shortstat "$merge_base..$branch_name" 2>/dev/null
    echo ""

    # Uncommitted work
    if test -d "$hawt_path"
        set -l dirty_count (__hawt_dirty_count "$hawt_path")
        if test "$dirty_count" -gt 0
            echo (set_color yellow)"⚠ $dirty_count uncommitted files in worktree"(set_color normal)
            git -C "$hawt_path" status --short 2>/dev/null | head -15
            echo ""
        end
    end

    # Session logs
    set -l session_dir "$hawt_path/.hawt-session"
    if test -d "$session_dir"
        set -l log_files "$session_dir"/*.log
        set -l log_count (count $log_files)
        if test "$log_count" -gt 0
            echo (set_color --bold)"Session Logs ($log_count)"(set_color normal)
            echo (set_color brblack)(string repeat -n 50 "─")(set_color normal)
            for log in $log_files
                set -l size (wc -c <"$log" | string trim)
                set -l lines (wc -l <"$log" | string trim)
                echo "  "(basename "$log")" - $lines lines ($size bytes)"
            end
            echo ""
        end
    end

    # TASK.md
    if test -f "$hawt_path/TASK.md"
        echo (set_color --bold)"Original Task"(set_color normal)
        echo (set_color brblack)(string repeat -n 50 "─")(set_color normal)
        cat "$hawt_path/TASK.md"
        echo ""
    end

    # Test run
    if test $do_test -eq 1
        echo (set_color --bold)"Test Results"(set_color normal)
        echo (set_color brblack)(string repeat -n 50 "─")(set_color normal)

        # Detect test command from .worktreerc or common conventions
        set -l test_cmd ""
        if test -f "$root/.worktreerc"
            set test_cmd (string match -r '^test-cmd:\s*(.+)' <"$root/.worktreerc" | string replace -r '^test-cmd:\s*' '')
        end

        if test -z "$test_cmd"
            # Heuristic: check package.json
            if test -f "$hawt_path/package.json"
                set test_cmd "npm test"
            else if test -f "$hawt_path/pyproject.toml"
                set test_cmd "python -m pytest"
            else if test -f "$hawt_path/Makefile"
                if grep -q '^test:' "$hawt_path/Makefile"
                    set test_cmd "make test"
                end
            end
        end

        if test -n "$test_cmd"
            echo (set_color brblack)"Running: $test_cmd"(set_color normal)
            pushd "$hawt_path"; or return 1
            fish -c "$test_cmd"
            set -l test_exit $status
            popd

            if test $test_exit -eq 0
                echo (set_color green)"✓ Tests passed"(set_color normal)
            else
                __hawt_error "✗ Tests failed (exit: $test_exit)"
            end
        else
            echo (set_color brblack)"No test command found. Add 'test-cmd: ...' to .worktreerc"(set_color normal)
        end
        echo ""
    end

    # AI review
    if test $do_ai -eq 1
        echo (set_color --bold)"AI Review"(set_color normal)
        echo (set_color brblack)(string repeat -n 50 "─")(set_color normal)

        if not command -q claude
            __hawt_error "claude CLI not found - install Claude Code for AI review"
            return 1
        end

        set -l diff_content (git -C "$root" diff "$merge_base..$branch_name" 2>/dev/null | head -5000)
        set -l commit_log (git -C "$root" log --oneline "$merge_base..$branch_name" 2>/dev/null)

        set -l review_prompt "Review this code diff from a CC session. Be concise. Focus on:
1. Summary of what was done
2. Potential issues (bugs, security, perf)
3. Code quality observations
4. Suggestions for improvement

Commits:
$commit_log

Diff (truncated to 5000 chars):
$diff_content"

        echo "$review_prompt" | claude --print 2>/dev/null
        echo ""
    end

    # Actions
    echo (set_color --bold)"Actions"(set_color normal)
    echo (set_color brblack)(string repeat -n 50 "─")(set_color normal)
    echo "  hawt diff $name         Full diff"
    echo "  hawt merge $name        Merge into "(git -C "$root" branch --show-current)
    echo "  hawt checkpoint $name   Snapshot current state"
    echo "  hawt rm $name           Remove worktree"
    echo ""
end
