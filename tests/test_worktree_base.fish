source (status dirname)/setup.fish

@echo "--- __hawt_worktree_base: default ---"

@test "appends -worktrees suffix" \
    (__hawt_worktree_base /home/code/my-app) = "/home/code/my-app-worktrees"

@test "handles nested paths" \
    (__hawt_worktree_base /home/code/deep/nested/project) = "/home/code/deep/nested/project-worktrees"

@test "handles root-level repo" \
    (__hawt_worktree_base /myrepo) = "//myrepo-worktrees"

@echo "--- __hawt_worktree_base: HAWT_WORKTREE_DIR ---"

@test "env var overrides default" (
    set -x HAWT_WORKTREE_DIR /custom/worktrees
    __hawt_worktree_base /home/code/my-app
) = "/custom/worktrees"

@test "env var takes precedence over .worktreerc" (
    set -l tmp (hawt_test_make_repo)
    echo "worktree-dir: ../from-rc" > $tmp/.worktreerc
    set -x HAWT_WORKTREE_DIR /from-env
    __hawt_worktree_base $tmp
) = "/from-env"

@test "empty env var is ignored" (
    set -x HAWT_WORKTREE_DIR ""
    __hawt_worktree_base /home/code/my-app
) = "/home/code/my-app-worktrees"

@echo "--- __hawt_worktree_base: .worktreerc worktree-dir ---"

# Erase env var so .worktreerc tests are clean
set -e HAWT_WORKTREE_DIR

@test "absolute path from .worktreerc" (
    set -l tmp (hawt_test_make_repo)
    echo "worktree-dir: /tmp/my-worktrees" > $tmp/.worktreerc
    __hawt_worktree_base $tmp
) = "/tmp/my-worktrees"

@test "relative path from .worktreerc" (
    set -l tmp (hawt_test_make_repo)
    echo "worktree-dir: ../sibling-wt" > $tmp/.worktreerc
    set -l actual (__hawt_worktree_base $tmp)
    set -l expected (path normalize "$tmp/../sibling-wt")
    test "$actual" = "$expected"; and echo pass; or echo "fail: $actual != $expected"
) = pass

@test "relative path inside repo from .worktreerc" (
    set -l tmp (hawt_test_make_repo)
    echo "worktree-dir: .worktrees" > $tmp/.worktreerc
    set -l actual (__hawt_worktree_base $tmp)
    test "$actual" = "$tmp/.worktrees"; and echo pass; or echo "fail: $actual != $tmp/.worktrees"
) = pass

@test "worktree-dir with other directives" (
    set -l tmp (hawt_test_make_repo)
    printf "symlink: node_modules\nworktree-dir: /custom/path\ncopy: .env\n" > $tmp/.worktreerc
    __hawt_worktree_base $tmp
) = "/custom/path"

@test "default when .worktreerc has no worktree-dir" (
    set -l tmp (hawt_test_make_repo)
    echo "symlink: node_modules" > $tmp/.worktreerc
    set -l actual (__hawt_worktree_base $tmp)
    test "$actual" = "$tmp-worktrees"; and echo pass; or echo "fail: $actual != $tmp-worktrees"
) = pass
