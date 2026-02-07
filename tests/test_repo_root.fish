source (status dirname)/setup.fish

@echo "--- __hawt_repo_root ---"

# Setup
set -l paths (hawt_test_make_repo_with_worktree)
set -g MAIN_REPO $paths[1]
set -g WT_PATH $paths[2]

# From main repo
@test "returns repo root from main repo" (
    cd $MAIN_REPO
    __hawt_repo_root
) = $MAIN_REPO

# From worktree, resolves back to main repo
@test "resolves worktree back to main repo" (
    cd $WT_PATH
    __hawt_repo_root
) = $MAIN_REPO

# From subdirectory of main repo
@test "resolves from subdirectory" (
    mkdir -p $MAIN_REPO/sub/dir
    cd $MAIN_REPO/sub/dir
    __hawt_repo_root
) = $MAIN_REPO

# Fails outside git repo
@test "fails outside git repo" (
    cd (mktemp -d)
    __hawt_repo_root >/dev/null 2>/dev/null
) $status -eq 1

# Teardown
rm -rf $MAIN_REPO (dirname $WT_PATH)
