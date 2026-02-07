source (status dirname)/setup.fish

# Setup: temp project dir with .env files
set -g PROJECT (mktemp -d)
git -C $PROJECT init --quiet
git -C $PROJECT commit --allow-empty -m "init" --quiet 2>/dev/null
touch $PROJECT/.env $PROJECT/.env.local $PROJECT/.env.production


@echo "--- sandbox: error handling ---"

@test "fails without project_path" (__hawt_sandbox 2>/dev/null) $status -eq 1
@test "fails on unknown flag" (__hawt_sandbox $PROJECT --bogus 2>/dev/null) $status -eq 1
@test "succeeds with valid project_path" (__hawt_sandbox $PROJECT >/dev/null) $status -eq 0


@echo "--- sandbox: core isolation ---"

set -g ARGS (__hawt_sandbox $PROJECT --no-remap)

@test "first arg is bwrap" "$ARGS[1]" = "bwrap"
@test "includes --die-with-parent" (contains -- --die-with-parent $ARGS) $status -eq 0
@test "includes --unshare-pid" (contains -- --unshare-pid $ARGS) $status -eq 0

@test "ro-bind root" (hawt_test_has_arg_pair --ro-bind / / -- $ARGS) $status -eq 0
@test "tmpfs /home" (hawt_test_has_arg_pair --tmpfs /home -- $ARGS) $status -eq 0
@test "tmpfs /tmp" (hawt_test_has_arg_pair --tmpfs /tmp -- $ARGS) $status -eq 0
@test "proc /proc" (hawt_test_has_arg_pair --proc /proc -- $ARGS) $status -eq 0
@test "dev /dev" (hawt_test_has_arg_pair --dev /dev -- $ARGS) $status -eq 0

# --chdir is last argument pair
set -l second_to_last (math (count $ARGS) - 1)
@test "--chdir is last arg pair" "$ARGS[$second_to_last]" = "--chdir"


@echo "--- sandbox: network ---"

@test "default is --share-net" (contains -- --share-net $ARGS) $status -eq 0

set -g OFFLINE_ARGS (__hawt_sandbox $PROJECT --no-remap --offline)
@test "--offline produces --unshare-net" (contains -- --unshare-net $OFFLINE_ARGS) $status -eq 0
@test "--offline has no --share-net" (not contains -- --share-net $OFFLINE_ARGS) $status -eq 0


@echo "--- sandbox: path remap ---"

set -g REMAP_ARGS (__hawt_sandbox $PROJECT)
set -l name (basename $PROJECT)

@test "remap: bind src to /home/code/name" \
    (hawt_test_has_arg_pair --bind $PROJECT /home/code/$name -- $REMAP_ARGS) $status -eq 0

@test "remap: chdir to /home/code/name" \
    (hawt_test_has_arg_pair --chdir /home/code/$name -- $REMAP_ARGS) $status -eq 0

@test "remap: tmpfs parent dir" \
    (hawt_test_has_arg_pair --tmpfs /home/code -- $REMAP_ARGS) $status -eq 0

@test "no-remap: bind src to itself" \
    (hawt_test_has_arg_pair --bind $PROJECT $PROJECT -- $ARGS) $status -eq 0

@test "no-remap: chdir to project path" \
    (hawt_test_has_arg_pair --chdir $PROJECT -- $ARGS) $status -eq 0


@echo "--- sandbox: home binds ---"

@test "fish config bound" (contains -- "$HOME/.config/fish" $ARGS) $status -eq 0
@test "git config dir bound" (contains -- "$HOME/.config/git" $ARGS) $status -eq 0
@test "gitconfig bound" (contains -- "$HOME/.gitconfig" $ARGS) $status -eq 0
@test "gh config bound" (contains -- "$HOME/.config/gh" $ARGS) $status -eq 0
@test "local bin bound" (contains -- "$HOME/.local/bin" $ARGS) $status -eq 0
@test "npmrc bound" (contains -- "$HOME/.npmrc" $ARGS) $status -eq 0

# SSH: agent socket + config only, no private keys
@test "ssh config bound" (contains -- "$HOME/.ssh/config" $ARGS) $status -eq 0
@test "ssh known_hosts bound" (contains -- "$HOME/.ssh/known_hosts" $ARGS) $status -eq 0
@test "no full .ssh bind" (not hawt_test_has_arg_pair --ro-bind "$HOME/.ssh" "$HOME/.ssh" -- $ARGS) $status -eq 0
@test "no full .ssh bind-try" (not hawt_test_has_arg_pair --ro-bind-try "$HOME/.ssh" "$HOME/.ssh" -- $ARGS) $status -eq 0

# SSH_AUTH_SOCK conditional
@test "SSH_AUTH_SOCK bound when set" (
    if set -q SSH_AUTH_SOCK; and test -e "$SSH_AUTH_SOCK"
        contains -- "$SSH_AUTH_SOCK" $ARGS
    else
        true
    end
) $status -eq 0


@echo "--- sandbox: .env ---"

@test "env: .env bound to /dev/null" \
    (hawt_test_has_arg_pair --ro-bind /dev/null "$PROJECT/.env" -- $ARGS) $status -eq 0

@test "env: .env.local bound to /dev/null" \
    (hawt_test_has_arg_pair --ro-bind /dev/null "$PROJECT/.env.local" -- $ARGS) $status -eq 0

@test "env: .env.production bound to /dev/null" \
    (hawt_test_has_arg_pair --ro-bind /dev/null "$PROJECT/.env.production" -- $ARGS) $status -eq 0

# --allow-env disables nullification
set -g ALLOW_ARGS (__hawt_sandbox $PROJECT --no-remap --allow-env)
@test "--allow-env: no /dev/null binds" (
    not hawt_test_has_arg_pair --ro-bind /dev/null "$PROJECT/.env" -- $ALLOW_ARGS
) $status -eq 0


@echo "--- sandbox: extra mounts ---"

set -l ro_dir (mktemp -d)
set -l rw_dir (mktemp -d)

set -g RO_ARGS (__hawt_sandbox $PROJECT --no-remap --mount-ro $ro_dir)
@test "--mount-ro adds --ro-bind" \
    (hawt_test_has_arg_pair --ro-bind $ro_dir $ro_dir -- $RO_ARGS) $status -eq 0

set -g RW_ARGS (__hawt_sandbox $PROJECT --no-remap --mount-rw $rw_dir)
@test "--mount-rw adds --bind" \
    (hawt_test_has_arg_pair --bind $rw_dir $rw_dir -- $RW_ARGS) $status -eq 0

# src:dest mapping
set -g MAPPED_ARGS (__hawt_sandbox $PROJECT --no-remap --mount-ro "$ro_dir:/inside/path")
@test "--mount-ro src:dest maps correctly" \
    (hawt_test_has_arg_pair --ro-bind $ro_dir /inside/path -- $MAPPED_ARGS) $status -eq 0


@echo "--- sandbox: home binds ---"

set -l hb_dir (mktemp -d)

set -g HB_ARGS (__hawt_sandbox $PROJECT --no-remap --home-bind $hb_dir)
@test "--home-bind produces --bind" \
    (hawt_test_has_arg_pair --bind $hb_dir $hb_dir -- $HB_ARGS) $status -eq 0

set -g HBR_ARGS (__hawt_sandbox $PROJECT --no-remap --home-bind-ro $hb_dir)
@test "--home-bind-ro produces --ro-bind" \
    (hawt_test_has_arg_pair --ro-bind $hb_dir $hb_dir -- $HBR_ARGS) $status -eq 0


@echo "--- sandbox: worktreerc blocklist ---"

# Create a separate project for worktreerc tests (needs its own .worktreerc)
set -g RC_PROJECT (mktemp -d)
git -C $RC_PROJECT init --quiet
git -C $RC_PROJECT commit --allow-empty -m "init" --quiet 2>/dev/null

# Helper: run __hawt_sandbox from within the project dir so
# __hawt_sandbox_find_rc_root resolves .worktreerc correctly
function hawt_test_sandbox_in_project
    set -l proj $argv[1]
    set -l rest $argv[2..]
    set -l _saved (pwd)
    builtin cd $proj
    __hawt_sandbox $proj $rest
    set -l rc $status
    builtin cd $_saved
    return $rc
end

# bwrap-tmpfs: blocked system paths must be rejected
# Note: /root and /home are tested only via bind-ro/bind-rw because core
# isolation already adds --tmpfs for both, making the tmpfs blocklist test ambiguous.
for blocked_path in /proc /dev /sys /etc /usr /bin /sbin /var /
    printf 'bwrap-tmpfs: %s\n' "$blocked_path" >$RC_PROJECT/.worktreerc
    set -g RC_TMPFS_ARGS (hawt_test_sandbox_in_project $RC_PROJECT --no-remap)

    @test "rc tmpfs: rejects blocked path $blocked_path" \
        (not hawt_test_has_arg_pair --tmpfs "$blocked_path" -- $RC_TMPFS_ARGS) $status -eq 0
end

# bwrap-bind-ro: blocked system paths must be rejected
for blocked_path in /proc /dev /sys /etc /usr /bin /sbin /var /root /home /
    printf 'bwrap-bind-ro: %s\n' "$blocked_path" >$RC_PROJECT/.worktreerc
    set -g RC_BIND_RO_ARGS (hawt_test_sandbox_in_project $RC_PROJECT --no-remap)

    @test "rc bind-ro: rejects blocked path $blocked_path" \
        (not hawt_test_has_arg_pair --ro-bind "$blocked_path" "$blocked_path" -- $RC_BIND_RO_ARGS) $status -eq 0
end

# bwrap-bind-rw: blocked system paths must be rejected
for blocked_path in /proc /dev /sys /etc /usr /bin /sbin /var /root /home /
    printf 'bwrap-bind-rw: %s\n' "$blocked_path" >$RC_PROJECT/.worktreerc
    set -g RC_BIND_RW_ARGS (hawt_test_sandbox_in_project $RC_PROJECT --no-remap)

    @test "rc bind-rw: rejects blocked path $blocked_path" \
        (not hawt_test_has_arg_pair --bind "$blocked_path" "$blocked_path" -- $RC_BIND_RW_ARGS) $status -eq 0
end

# Valid (non-system) paths should still work
set -g RC_VALID_DIR (mktemp -d)

printf 'bwrap-tmpfs: %s\n' "$RC_VALID_DIR" >$RC_PROJECT/.worktreerc
set -g RC_VALID_TMPFS_ARGS (hawt_test_sandbox_in_project $RC_PROJECT --no-remap)
@test "rc tmpfs: allows non-system path" \
    (hawt_test_has_arg_pair --tmpfs "$RC_VALID_DIR" -- $RC_VALID_TMPFS_ARGS) $status -eq 0

printf 'bwrap-bind-ro: %s\n' "$RC_VALID_DIR" >$RC_PROJECT/.worktreerc
set -g RC_VALID_RO_ARGS (hawt_test_sandbox_in_project $RC_PROJECT --no-remap)
@test "rc bind-ro: allows non-system path" \
    (hawt_test_has_arg_pair --ro-bind "$RC_VALID_DIR" "$RC_VALID_DIR" -- $RC_VALID_RO_ARGS) $status -eq 0

printf 'bwrap-bind-rw: %s\n' "$RC_VALID_DIR" >$RC_PROJECT/.worktreerc
set -g RC_VALID_RW_ARGS (hawt_test_sandbox_in_project $RC_PROJECT --no-remap)
@test "rc bind-rw: allows non-system path" \
    (hawt_test_has_arg_pair --bind "$RC_VALID_DIR" "$RC_VALID_DIR" -- $RC_VALID_RW_ARGS) $status -eq 0


@echo "--- sandbox: worktreerc tilde expansion ---"

# ~/path expands to $HOME/path - but /home is blocked, so the expanded path
# must be rejected by the blocklist. This verifies both tilde expansion AND
# that the /home blocklist entry works correctly together.
set -g RC_TILDE_DIR "$HOME/.hawt-test-tilde-"(random)
mkdir -p "$RC_TILDE_DIR"
set -l tilde_relative (string replace "$HOME" "~" "$RC_TILDE_DIR")

printf 'bwrap-bind-ro: %s\n' "$tilde_relative" >$RC_PROJECT/.worktreerc
set -g RC_TILDE_RO_ARGS (hawt_test_sandbox_in_project $RC_PROJECT --no-remap 2>/dev/null)
@test "rc bind-ro: ~/path blocked (expands under /home)" \
    (not hawt_test_has_arg_pair --ro-bind "$RC_TILDE_DIR" "$RC_TILDE_DIR" -- $RC_TILDE_RO_ARGS) $status -eq 0

# ~/path should expand to $HOME/path for bind-rw - also blocked
printf 'bwrap-bind-rw: %s\n' "$tilde_relative" >$RC_PROJECT/.worktreerc
set -g RC_TILDE_RW_ARGS (hawt_test_sandbox_in_project $RC_PROJECT --no-remap 2>/dev/null)
@test "rc bind-rw: ~/path blocked (expands under /home)" \
    (not hawt_test_has_arg_pair --bind "$RC_TILDE_DIR" "$RC_TILDE_DIR" -- $RC_TILDE_RW_ARGS) $status -eq 0

# Tilde in middle of path must NOT be expanded (e.g. data~backup)
set -g RC_MID_TILDE_DIR (mktemp -d)
set -g RC_MID_TILDE_PATH "$RC_MID_TILDE_DIR/data~backup"
mkdir -p "$RC_MID_TILDE_PATH"

printf 'bwrap-bind-ro: %s\n' "$RC_MID_TILDE_PATH" >$RC_PROJECT/.worktreerc
set -g RC_MID_TILDE_ARGS (hawt_test_sandbox_in_project $RC_PROJECT --no-remap)
@test "rc bind-ro: mid-path tilde not expanded" \
    (hawt_test_has_arg_pair --ro-bind "$RC_MID_TILDE_PATH" "$RC_MID_TILDE_PATH" -- $RC_MID_TILDE_ARGS) $status -eq 0

printf 'bwrap-bind-rw: %s\n' "$RC_MID_TILDE_PATH" >$RC_PROJECT/.worktreerc
set -g RC_MID_TILDE_RW_ARGS (hawt_test_sandbox_in_project $RC_PROJECT --no-remap)
@test "rc bind-rw: mid-path tilde not expanded" \
    (hawt_test_has_arg_pair --bind "$RC_MID_TILDE_PATH" "$RC_MID_TILDE_PATH" -- $RC_MID_TILDE_RW_ARGS) $status -eq 0

# Teardown
rm -rf $PROJECT $ro_dir $rw_dir $hb_dir $RC_PROJECT $RC_VALID_DIR $RC_TILDE_DIR $RC_MID_TILDE_DIR
