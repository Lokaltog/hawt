function __hawt_lock_release --description "Clean up lock artifacts" -a hawt_path
    rm -f "$hawt_path/.hawt-lock" "$hawt_path/.hawt-session-meta"
end
