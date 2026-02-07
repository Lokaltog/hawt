# Verify a file is trusted before execution. Uses hash-based trust-on-first-use.
# Trust entries stored as "sha256hash:/path/to/file" lines in .hawt-trusted.
function __hawt_check_file_trust --description "Verify file trust via SHA-256 TOFU" -a file_path -a trust_file -a description
    if not test -f "$file_path"
        return 1
    end

    set -l file_hash (sha256sum "$file_path" 2>/dev/null | string split ' ')[1]
    if test -z "$file_hash"
        return 1
    end

    # Check if this exact file+hash is already trusted
    if test -f "$trust_file"
        if grep -qxF "$file_hash:$file_path" "$trust_file"
            return 0
        end
    end

    # Not trusted - prompt user
    echo (set_color yellow)"WARNING: $description will execute code from the repository."(set_color normal) >&2
    echo (set_color brblack)"  File: $file_path"(set_color normal) >&2
    echo "" >&2
    read -l -P "Trust and execute? [y/N] " confirm
    if test "$confirm" = y -o "$confirm" = Y
        echo "$file_hash:$file_path" >>"$trust_file"
        return 0
    end
    return 1
end
