source (status dirname)/setup.fish

@echo "--- __hawt_format_duration ---"

# Seconds range (< 60)
@test "0 seconds" (__hawt_format_duration 0) = "0s"
@test "1 second" (__hawt_format_duration 1) = "1s"
@test "30 seconds" (__hawt_format_duration 30) = "30s"
@test "59 seconds" (__hawt_format_duration 59) = "59s"

# Minutes range (60..3599)
@test "exactly 1 minute" (__hawt_format_duration 60) = "1m0s"
@test "1 min 1 sec" (__hawt_format_duration 61) = "1m1s"
@test "2 min 5 sec" (__hawt_format_duration 125) = "2m5s"
@test "59 min 59 sec" (__hawt_format_duration 3599) = "59m59s"

# Hours range (>= 3600)
@test "exactly 1 hour" (__hawt_format_duration 3600) = "1h0m"
@test "2 hours 5 min" (__hawt_format_duration 7500) = "2h5m"
@test "1 hour 30 min" (__hawt_format_duration 5400) = "1h30m"
