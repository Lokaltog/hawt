# tests/setup.fish - Shared test helpers
# Source this at the top of every test file:
#   source (status dirname)/setup.fish

set -g HAWT_ROOT (realpath (status dirname)/..)

# Load hawt functions via fish autoloader
set -p fish_function_path $HAWT_ROOT/functions $HAWT_ROOT

# Source hawt.fish for inline helpers (__hawt_repo_root, __hawt_worktree_base, __hawt_help)
source $HAWT_ROOT/hawt.fish


# Create a temporary git repo, echo its path
function hawt_test_make_repo
    set -l tmp (mktemp -d)
    git -C $tmp init --quiet
    git -C $tmp commit --allow-empty -m "init" --quiet 2>/dev/null
    echo $tmp
end

# Create a temporary git repo with a worktree
# Outputs two lines: main repo path, then worktree path
function hawt_test_make_repo_with_worktree
    set -l main (hawt_test_make_repo)
    set -l wt_base "$main-worktrees"
    mkdir -p $wt_base
    set -l wt_path "$wt_base/test-wt"
    git -C $main worktree add -b test-branch $wt_path HEAD --quiet 2>/dev/null
    echo $main
    echo $wt_path
end

# Check if a bwrap arg sequence exists in an args array
# Usage: hawt_test_has_arg_pair <flag> <val1> [val2] -- <args...>
# Returns 0 if found, 1 otherwise
function hawt_test_has_arg_pair
    set -l flag $argv[1]
    set -l val1 $argv[2]
    set -l val2 ""
    set -l args_start 3

    # Check for optional val2 before --
    if test "$argv[3]" != "--"
        set val2 $argv[3]
        set args_start 5 # skip val2 and --
    else
        set args_start 4 # skip --
    end

    set -l args $argv[$args_start..]
    set -l n (count $args)

    for i in (seq $n)
        if test "$args[$i]" = "$flag"
            set -l j (math $i + 1)
            if test $j -le $n; and test "$args[$j]" = "$val1"
                if test -z "$val2"
                    return 0
                end
                set -l k (math $i + 2)
                if test $k -le $n; and test "$args[$k]" = "$val2"
                    return 0
                end
            end
        end
    end
    return 1
end
