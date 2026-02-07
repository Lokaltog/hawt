source (status dirname)/setup.fish

@echo "--- hawt unload ---"

# Verify hawt is loaded before testing unload
@test "hawt function exists before unload" (functions -q hawt) $status -eq 0
@test "__hawt_do_unload exists before unload" (functions -q __hawt_do_unload) $status -eq 0
@test "__hawt_on_pwd_change exists before unload" (functions -q __hawt_on_pwd_change) $status -eq 0

# Set the variable that unload should clean up
set -g __hawt_last_pwd /tmp/fake

# Run unload
__hawt_do_unload --quiet

@test "hawt function erased after unload" (not functions -q hawt) $status -eq 0
@test "__hawt_do_unload erased after unload" (not functions -q __hawt_do_unload) $status -eq 0
@test "__hawt_do_reload erased after unload" (not functions -q __hawt_do_reload) $status -eq 0
@test "__hawt_on_pwd_change erased after unload" (not functions -q __hawt_on_pwd_change) $status -eq 0
@test "__hawt_help erased after unload" (not functions -q __hawt_help) $status -eq 0
@test "__hawt_cc erased after unload" (not functions -q __hawt_cc) $status -eq 0
@test "__hawt_last_pwd variable erased" (not set -q __hawt_last_pwd) $status -eq 0
@test "completions erased" (not complete -C "hawt " 2>/dev/null | string match -q "*status*") $status -eq 0

@echo "--- hawt reload ---"

# Re-source to restore hawt (simulating a fresh load)
source $HAWT_ROOT/hawt.fish
for f in $HAWT_ROOT/functions/__hawt_*.fish
    source $f
end

# Verify it's back
@test "hawt restored after source" (functions -q hawt) $status -eq 0

# Now test reload via the function
__hawt_do_reload

@test "hawt exists after reload" (functions -q hawt) $status -eq 0
@test "__hawt_do_unload exists after reload" (functions -q __hawt_do_unload) $status -eq 0
@test "__hawt_on_pwd_change exists after reload" (functions -q __hawt_on_pwd_change) $status -eq 0
@test "__hawt_help exists after reload" (functions -q __hawt_help) $status -eq 0
@test "__hawt_cc exists after reload" (functions -q __hawt_cc) $status -eq 0

@echo "--- help does not mention unload/reload ---"

set -g HELP (__hawt_help)

@test "help does not mention unload" (not string match -q "*hawt unload*" "$HELP") $status -eq 0
@test "help does not mention reload" (not string match -q "*hawt reload*" "$HELP") $status -eq 0
