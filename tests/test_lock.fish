source (status dirname)/setup.fish

@echo "--- flock-based locking subsystem ---"

# Setup - fresh temp dir for each test group
set -g WT (mktemp -d)


# Probe succeeds when no lock is held
@test "acquire probe returns 0 on unlocked dir" (
    __hawt_lock_acquire $WT 2>/dev/null
) $status -eq 0

# Probe-only means acquire must NOT create any lock artifacts
@test "acquire does not create lock artifacts" (
    rm -rf $WT/.hawt-lock $WT/.hawt-session-meta
    __hawt_lock_acquire $WT 2>/dev/null
    test ! -e $WT/.hawt-lock -a ! -e $WT/.hawt-session-meta
) $status -eq 0

# Clean slate for next test
rm -rf $WT/.hawt-lock

# Hold a flock in the background, then probe should report held
@test "acquire probe returns 1 when flock is held" (
    touch $WT/.hawt-lock
    flock --nonblock $WT/.hawt-lock sleep 10 &
    set -l bg_pid $last_pid
    sleep 0.1
    __hawt_lock_acquire $WT 2>/dev/null
    set -l rc $status
    kill $bg_pid 2>/dev/null
    wait $bg_pid 2>/dev/null
    rm -f $WT/.hawt-lock
    test $rc -eq 1
) $status -eq 0

# After the flock holder exits, probe succeeds again (kernel auto-release)
@test "acquire probe returns 0 after flock holder exits" (
    rm -rf $WT/.hawt-lock
    touch $WT/.hawt-lock
    flock --nonblock $WT/.hawt-lock fish -c 'true'
    # flock holder has exited, lock should be free
    __hawt_lock_acquire $WT 2>/dev/null
    set -l rc $status
    rm -f $WT/.hawt-lock
    test $rc -eq 0
) $status -eq 0


# Clean slate
rm -rf $WT/.hawt-lock $WT/.hawt-session-meta

# Release removes .hawt-lock file
@test "release removes .hawt-lock file" (
    touch $WT/.hawt-lock
    __hawt_lock_release $WT
    test ! -e $WT/.hawt-lock
) $status -eq 0

# Release removes .hawt-session-meta file
@test "release removes .hawt-session-meta file" (
    printf '%s\n%s\n' "12345" "2025-01-01 00:00:00" > $WT/.hawt-session-meta
    __hawt_lock_release $WT
    test ! -e $WT/.hawt-session-meta
) $status -eq 0

# Release cleans up both files at once
@test "release removes both .hawt-lock and .hawt-session-meta" (
    touch $WT/.hawt-lock
    printf '%s\n%s\n' "12345" "2025-01-01 00:00:00" > $WT/.hawt-session-meta
    __hawt_lock_release $WT
    test ! -e $WT/.hawt-lock -a ! -e $WT/.hawt-session-meta
) $status -eq 0

# Release is idempotent (no error when files are already absent)
@test "release succeeds when no lock files exist" (
    rm -f $WT/.hawt-lock $WT/.hawt-session-meta
    __hawt_lock_release $WT 2>/dev/null
) $status -eq 0


# When the flock holder process exits, the kernel releases the lock
# --close prevents fd inheritance to the child process (sleep), ensuring
# that killing flock releases the lock even if the child survives
@test "flock auto-releases when holder process exits" (
    rm -rf $WT/.hawt-lock
    touch $WT/.hawt-lock
    flock --nonblock --close $WT/.hawt-lock sleep 10 &
    set -l bg_pid $last_pid
    sleep 0.1
    # Verify lock is currently held
    not flock --nonblock $WT/.hawt-lock true 2>/dev/null
    set -l held $status
    # Kill the holder - kernel releases the flock
    kill $bg_pid 2>/dev/null
    wait $bg_pid 2>/dev/null
    # Verify lock is now free
    flock --nonblock $WT/.hawt-lock true
    set -l free $status
    rm -f $WT/.hawt-lock
    test $held -eq 0 -a $free -eq 0
) $status -eq 0


# flock holding a command blocks concurrent acquisition, and releases when the command exits
@test "flock wrapping a command holds lock for duration" (
    rm -f $WT/.hawt-lock
    touch $WT/.hawt-lock
    # flock wraps sleep - lock held while sleep runs
    flock --nonblock --close $WT/.hawt-lock sleep 10 &
    set -l bg_pid $last_pid
    sleep 0.1
    # Concurrent flock should fail
    not flock --nonblock $WT/.hawt-lock true 2>/dev/null
    set -l blocked $status
    kill $bg_pid 2>/dev/null; wait $bg_pid 2>/dev/null
    # After kill, lock is free
    flock --nonblock $WT/.hawt-lock true 2>/dev/null
    set -l freed $status
    rm -f $WT/.hawt-lock
    test $blocked -eq 0 -a $freed -eq 0
) $status -eq 0

rm -rf $WT
