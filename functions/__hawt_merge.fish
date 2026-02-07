function __hawt_merge --description "Merge worktree branch back"
    argparse squash rebase merge keep no-delete-branch -- $argv; or return 1

    set -l name $argv[1]
    set -l strategy squash
    set -l keep_worktree 0
    set -l keep_branch 0
    set -q _flag_rebase; and set strategy rebase
    set -q _flag_merge; and set strategy merge
    set -q _flag_keep; and set keep_worktree 1
    set -q _flag_no_delete_branch; and set keep_branch 1

    if test -z "$name"
        __hawt_error "Usage: hawt merge <name> [--squash|--rebase|--merge] [--keep]"
        return 1
    end

    set -l root (__hawt_repo_root); or return 1
    set -l hawt_base (__hawt_worktree_base "$root")
    set -l hawt_path "$hawt_base/$name"

    # Resolve branch name (try cc/ prefix convention first)
    set -l branch_name (__hawt_resolve_branch "$name"); or return 1

    # Check for lock
    if test -d "$hawt_path/.hawt-lock"
        __hawt_error "Worktree '$name' has an active CC session. Stop it first with: hawt kill $name"
        return 1
    end

    # Show diff summary first
    echo ""
    echo (set_color --bold)"Merge preview: $branch_name → "(git -C "$root" branch --show-current)(set_color normal)
    echo (set_color brblack)(string repeat -n 60 "─")(set_color normal)

    set -l current_branch (git -C "$root" branch --show-current)
    set -l merge_base (git -C "$root" merge-base "$current_branch" "$branch_name")

    # Stats
    set -l stat_output (git -C "$root" diff --stat "$merge_base..$branch_name" 2>/dev/null)
    set -l shortstat (git -C "$root" diff --shortstat "$merge_base..$branch_name" 2>/dev/null)
    echo "$stat_output"
    echo ""
    echo (set_color --bold)"$shortstat"(set_color normal)
    echo ""

    # Commit log
    set -l commit_count (git -C "$root" rev-list --count "$merge_base..$branch_name" 2>/dev/null)
    echo (set_color brblack)"$commit_count commit(s) on $branch_name:"(set_color normal)
    git -C "$root" log --oneline --graph "$merge_base..$branch_name" 2>/dev/null | head -20
    echo ""

    # Generate merge commit message
    set -l merge_msg ""
    if test "$strategy" = squash; and command -q claude
        echo (set_color brblack)"Generating commit message..."(set_color normal)
        set -l diff_content (git -C "$root" diff "$merge_base..$branch_name" 2>/dev/null | head -5000)
        set -l commit_log (git -C "$root" log --oneline "$merge_base..$branch_name" 2>/dev/null)

        set -l msg_prompt "Generate a single conventional commit message for a squash merge of this branch.

Rules:
- Use conventional commits format: type(scope): description
- Types: feat, fix, refactor, chore, docs, test, perf, style, ci, build
- The scope is optional - only include it if there's a clear, narrow scope (e.g. a module, package, or subsystem name - NOT the git operation like 'merge')
- Use imperative mood in the description (e.g. 'add feature', 'fix bug', not 'added' or 'fixes')
- First line must be under 72 characters
- Add a blank line then a concise body (2-5 bullet points) summarizing the key changes
- Do NOT wrap the message in markdown code fences or quotes
- Output ONLY the commit message, nothing else

Branch: $branch_name

Commits:
$commit_log

Diff (truncated):
$diff_content"

        set -l ai_msg (echo "$msg_prompt" | claude --print 2>/dev/null | string collect)
        if test $status -eq 0; and test -n "$ai_msg"
            set merge_msg "$ai_msg"
        end
    end

    # Fallback if AI message wasn't generated
    if test -z "$merge_msg"
        set merge_msg (printf "Merge %s\n\nCommits:\n%s" "$branch_name" (git -C "$root" log --oneline "$merge_base..$branch_name" 2>/dev/null | string collect))
    end

    # Confirm
    echo (set_color --bold)"Strategy: $strategy"(set_color normal)
    echo (set_color --bold)"Commit message:"(set_color normal)
    echo (set_color brblack)(string repeat -n 60 "─")(set_color normal)
    echo "$merge_msg"
    echo (set_color brblack)(string repeat -n 60 "─")(set_color normal)
    echo ""
    read -l -P "Proceed? [Y/n/e(dit)] " confirm
    if test "$confirm" = n -o "$confirm" = N
        return 1
    else if test "$confirm" = e -o "$confirm" = E
        set -l tmpfile (mktemp /tmp/hawt-merge-msg.XXXXXX)
        echo "$merge_msg" >"$tmpfile"
        set -l editor $EDITOR
        test -z "$editor"; and set editor vim
        $editor "$tmpfile"
        set merge_msg (cat "$tmpfile" | string collect)
        rm -f "$tmpfile"
        if test -z "$merge_msg"
            __hawt_error "Empty commit message, aborting"
            return 1
        end
    end

    # Perform the merge using git -C to avoid pushd/popd
    switch $strategy
        case squash
            git -C "$root" merge --squash "$branch_name"
            if test $status -ne 0
                __hawt_error "Conflicts detected. Resolve them in: $root"
                echo (set_color brblack)"  After resolving: git add . && git commit"(set_color normal) >&2
                return 1
            end
            # Auto-commit the squash
            git -C "$root" commit -m "$merge_msg"

        case rebase
            # Rebase the branch onto current, then fast-forward
            git -C "$root" rebase "$current_branch" "$branch_name"
            if test $status -ne 0
                __hawt_error "Rebase conflicts. Resolve and continue with: git rebase --continue"
                return 1
            end
            git -C "$root" checkout "$current_branch"
            git -C "$root" merge --ff-only "$branch_name"

        case merge
            git -C "$root" merge --no-ff "$branch_name" -m "$merge_msg"
            if test $status -ne 0
                __hawt_error "Conflicts detected. Resolve them in: $root"
                return 1
            end
    end

    echo (set_color green)"✓ Merged $branch_name via $strategy"(set_color normal)

    # Cleanup
    if test $keep_worktree -eq 0
        if test -d "$hawt_path"
            # cd to main repo first in case we're inside the worktree being removed
            cd "$root"
            __hawt_announce_path "Returned to main repo: $root"
            git worktree remove "$hawt_path" 2>/dev/null
            or git worktree remove --force "$hawt_path" 2>/dev/null
            echo (set_color green)"✓ Removed worktree"(set_color normal)
        end
    end

    if test $keep_branch -eq 0 -a $keep_worktree -eq 0
        git branch -D "$branch_name" 2>/dev/null
        echo (set_color green)"✓ Deleted branch $branch_name"(set_color normal)
    end
end
