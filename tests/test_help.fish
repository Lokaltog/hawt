source (status dirname)/setup.fish

@echo "--- __hawt_help ---"

set -g HELP (__hawt_help)

@test "mentions hawt" (string match -q "*hawt*" "$HELP") $status -eq 0
@test "mentions cc subcommand" (string match -q "*hawt cc*" "$HELP") $status -eq 0
@test "mentions batch" (string match -q "*hawt batch*" "$HELP") $status -eq 0
@test "mentions sandbox" (string match -q "*hawt sandbox*" "$HELP") $status -eq 0
@test "mentions .worktreerc" (string match -q "*.worktreerc*" "$HELP") $status -eq 0
@test "mentions merge" (string match -q "*hawt merge*" "$HELP") $status -eq 0
@test "mentions diff" (string match -q "*hawt diff*" "$HELP") $status -eq 0
