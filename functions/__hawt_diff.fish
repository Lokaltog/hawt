function __hawt_diff --description "Review changes in a worktree"
    argparse files stat -- $argv; or return 1

    set -l name $argv[1]
    set -l files_only 0
    set -l stat_only 0
    set -q _flag_files; and set files_only 1
    set -q _flag_stat; and set stat_only 1

    if test -z "$name"
        __hawt_error "Usage: hawt diff <n> [--files] [--stat]"
        return 1
    end

    set -l root (__hawt_repo_root); or return 1

    # Resolve branch
    set -l branch_name (__hawt_resolve_branch "$name"); or return 1

    set -l current_branch (git -C "$root" branch --show-current)
    set -l merge_base (git -C "$root" merge-base "$current_branch" "$branch_name" 2>/dev/null)

    if test -z "$merge_base"
        __hawt_error "Cannot find common ancestor between $current_branch and $branch_name"
        return 1
    end

    # Header
    echo ""
    echo (set_color --bold)"Changes in $branch_name (vs $current_branch)"(set_color normal)
    echo (set_color brblack)(string repeat -n 60 "─")(set_color normal)

    set -l shortstat (git -C "$root" diff --shortstat "$merge_base..$branch_name")
    echo (set_color --bold)"$shortstat"(set_color normal)
    echo ""

    if test $files_only -eq 1
        git -C "$root" diff --name-status "$merge_base..$branch_name"
        return 0
    end

    if test $stat_only -eq 1
        git -C "$root" diff --stat "$merge_base..$branch_name"
        return 0
    end

    # Full diff - use delta or diff-so-fancy if available, otherwise plain git diff
    if command -q delta
        git -C "$root" diff "$merge_base..$branch_name" | delta
    else if command -q diff-so-fancy
        git -C "$root" diff "$merge_base..$branch_name" | diff-so-fancy
    else
        git -C "$root" diff --color=always "$merge_base..$branch_name" | less -R
    end
end
