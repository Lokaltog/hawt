source (status dirname)/setup.fish

@echo "--- __hawt_worktree_base ---"

@test "appends -worktrees suffix" \
    (__hawt_worktree_base /home/code/my-app) = "/home/code/my-app-worktrees"

@test "handles nested paths" \
    (__hawt_worktree_base /home/code/deep/nested/project) = "/home/code/deep/nested/project-worktrees"

@test "handles root-level repo" \
    (__hawt_worktree_base /myrepo) = "//myrepo-worktrees"
