function __hawt_run_hook --description "Execute lifecycle hooks" -a root -a hawt_path -a hook_name
    # Check for project-level hook file - require trust before execution
    set -l hook_file "$root/.worktree-hooks/$hook_name"
    if test -f "$hook_file"
        set -l trust_file "$root/.hawt-trusted"
        if not __hawt_check_file_trust "$hook_file" "$trust_file" "Hook '$hook_name'"
            echo (set_color brblack)"  Skipping untrusted hook: $hook_name"(set_color normal)
            # Fall through to .worktreerc post-create handling below
        else
            echo (set_color blue)"Running $hook_name hook..."(set_color normal)
            pushd "$hawt_path"; or return 1
            if test -x "$hook_file"
                $hook_file
            else
                fish "$hook_file"
            end
            popd
        end
    end

    # Check .worktreerc for inline post-create commands
    # WARNING: These commands run with full user privileges outside the sandbox.
    # This is an intentional trust boundary (like .envrc with direnv).
    # Only .worktreerc files in repos you trust should contain post-create commands.
    if test -f "$root/.worktreerc" -a "$hook_name" = post-create
        set -l trust_file "$root/.hawt-trusted"

        # Migrate old single-hash trust file to new hash:filepath format
        if test -f "$trust_file"
            set -l content (string trim <"$trust_file")
            if test -n "$content"; and not string match -q '*:*' "$content"
                echo "$content:$root/.worktreerc" >"$trust_file"
            end
        end

        set -l rc_hash (sha256sum "$root/.worktreerc" 2>/dev/null | string split ' ')[1]
        set -l has_post_create 0

        # Check if any post-create commands exist
        string match -rq '^post-create:' <"$root/.worktreerc"
        and set has_post_create 1

        if test $has_post_create -eq 1
            # Verify trust - check if .worktreerc hash:path entry exists
            set -l is_trusted 0
            if test -f "$trust_file"
                if grep -qxF "$rc_hash:$root/.worktreerc" "$trust_file"
                    set is_trusted 1
                end
            end

            if test $is_trusted -eq 0
                echo (set_color yellow)"WARNING: .worktreerc contains post-create commands that will run outside the sandbox."(set_color normal) >&2
                echo (set_color brblack)"  File: $root/.worktreerc"(set_color normal) >&2
                echo "" >&2
                # Show the commands that would run
                while read -l line
                    set -l action (string match -r '^post-create:\s*(.+)' "$line")
                    if test (count $action) -ge 2
                        echo (set_color brblack)"  > $action[2]"(set_color normal) >&2
                    end
                end <"$root/.worktreerc"
                echo "" >&2
                read -l -P "Trust this .worktreerc and run post-create commands? [y/N] " confirm
                if test "$confirm" = y -o "$confirm" = Y
                    echo "$rc_hash:$root/.worktreerc" >>"$trust_file"
                    set is_trusted 1
                end
            end

            if test $is_trusted -eq 1
                while read -l line
                    set -l action (string match -r '^post-create:\s*(.+)' "$line")
                    if test (count $action) -ge 2
                        echo (set_color blue)"Running: $action[2]"(set_color normal)
                        pushd "$hawt_path"; or continue
                        fish -c "$action[2]"
                        popd
                    end
                end <"$root/.worktreerc"
            end
        end
    end
end
