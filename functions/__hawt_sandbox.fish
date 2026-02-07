function __hawt_sandbox --description "Build bwrap sandbox arguments"
    argparse no-remap offline allow-env 'mount-ro=+' 'mount-rw=+' 'home-bind=+' 'home-bind-ro=+' -- $argv; or return 1

    set -l project_path $argv[1]
    if test -z "$project_path"
        __hawt_error "__hawt_sandbox: project_path required"
        return 1
    end

    set -l remap 1
    set -q _flag_no_remap; and set remap 0
    set -l offline 0
    set -q _flag_offline; and set offline 1
    set -l env_block 1
    set -q _flag_allow_env; and set env_block 0
    set -l extra_ro_mounts $_flag_mount_ro
    set -l extra_rw_mounts $_flag_mount_rw
    set -l extra_home_binds $_flag_home_bind
    set -l extra_home_ro_binds $_flag_home_bind_ro

    set project_path (path resolve "$project_path")

    # Resolve target path
    set -l target_path "$project_path"
    if test $remap -eq 1
        set -l code_base (set -q HAWT_SANDBOX_HOME; and echo $HAWT_SANDBOX_HOME; or echo /home/code)
        set target_path "$code_base/"(basename "$project_path")
    end

    # Resolve XDG base dirs with spec defaults
    set -l xdg_config (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo "$HOME/.config")
    set -l xdg_data (set -q XDG_DATA_HOME; and echo $XDG_DATA_HOME; or echo "$HOME/.local/share")
    set -l xdg_cache (set -q XDG_CACHE_HOME; and echo $XDG_CACHE_HOME; or echo "$HOME/.cache")

    set -l cmd bwrap

    set -a cmd --die-with-parent

    # Read-only root filesystem - deferred until after .worktreerc blocklist check
    # (added near end of function unless a blocked directive attempted to override it)
    set -l add_root_ro_bind 1

    # Full home isolation - tmpfs hides all user dirs
    set -a cmd --tmpfs /home
    set -a cmd --tmpfs /root
    set -a cmd --tmpfs $HOME
    set -a cmd --tmpfs "$xdg_cache"

    # Writable tmp
    set -a cmd --tmpfs /tmp

    # Process and device namespace
    set -a cmd --unshare-pid
    set -a cmd --proc /proc
    set -a cmd --dev /dev

    # Network
    if test $offline -eq 1
        set -a cmd --unshare-net
    else
        set -a cmd --share-net
    end

    # --ro-bind-try silently skips non-existent sources

    # Shell config
    set -a cmd --ro-bind-try "$xdg_config/fish" "$xdg_config/fish"

    # Git config
    set -a cmd --ro-bind-try "$xdg_config/git" "$xdg_config/git"
    set -a cmd --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig"

    # User-local binaries
    set -a cmd --ro-bind-try "$HOME/.local/bin" "$HOME/.local/bin"

    # SSH agent (socket-only - private keys stay on host)
    if set -q SSH_AUTH_SOCK; and test -e "$SSH_AUTH_SOCK"
        set -a cmd --ro-bind "$SSH_AUTH_SOCK" "$SSH_AUTH_SOCK"
    end
    set -a cmd --ro-bind-try "$HOME/.ssh/config" "$HOME/.ssh/config"
    set -a cmd --ro-bind-try "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts"

    # GPG smart card signing (agent socket + public keyring - no secret keys)
    set -l gpg_sock (gpgconf --list-dirs agent-socket 2>/dev/null)
    if test -n "$gpg_sock" -a -e "$gpg_sock"
        set -a cmd --ro-bind "$gpg_sock" "$gpg_sock"
    end
    set -l gnupg_home (gpgconf --list-dirs homedir 2>/dev/null)
    if test -n "$gnupg_home"
        set -a cmd --ro-bind-try "$gnupg_home/gpg.conf" "$gnupg_home/gpg.conf"
        set -a cmd --ro-bind-try "$gnupg_home/gpg-agent.conf" "$gnupg_home/gpg-agent.conf"
        set -a cmd --ro-bind-try "$gnupg_home/pubring.kbx" "$gnupg_home/pubring.kbx"
        set -a cmd --ro-bind-try "$gnupg_home/trustdb.gpg" "$gnupg_home/trustdb.gpg"
    end

    # GitHub CLI config
    set -a cmd --ro-bind-try "$xdg_config/gh" "$xdg_config/gh"

    # Runtime managers
    set -a cmd --ro-bind-try "$xdg_data/mise" "$xdg_data/mise"
    set -a cmd --ro-bind-try "$xdg_config/mise" "$xdg_config/mise"
    set -a cmd --ro-bind-try "$HOME/.cargo/bin" "$HOME/.cargo/bin"
    set -a cmd --ro-bind-try "$HOME/.rustup" "$HOME/.rustup"

    # Package manager config
    set -a cmd --ro-bind-try "$HOME/.npmrc" "$HOME/.npmrc"

    for mount in $extra_home_binds
        set -l parts (string split : "$mount")
        if test (count $parts) -eq 2
            if test -e "$parts[1]"
                set -a cmd --bind "$parts[1]" "$parts[2]"
            end
        else if test -e "$mount"
            set -a cmd --bind "$mount" "$mount"
        end
    end

    for mount in $extra_home_ro_binds
        set -l parts (string split : "$mount")
        if test (count $parts) -eq 2
            if test -e "$parts[1]"
                set -a cmd --ro-bind "$parts[1]" "$parts[2]"
            end
        else if test -e "$mount"
            set -a cmd --ro-bind "$mount" "$mount"
        end
    end

    if test $remap -eq 1
        set -a cmd --tmpfs (dirname "$target_path")
    end
    set -a cmd --bind "$project_path" "$target_path"

    # Worktrees have a .git *file* (not directory) pointing to the main
    # repo's .git/worktrees/<name>. Mount the main .git dir so git works.
    if test -f "$project_path/.git"
        set -l gitdir (string replace 'gitdir: ' '' (string trim <"$project_path/.git"))
        if not string match -q '/*' "$gitdir"
            set gitdir (path resolve "$project_path/$gitdir")
        end
        # gitdir is .git/worktrees/<name> - go up two levels to .git/
        set -l git_common_dir (path resolve "$gitdir/../..")
        if test -d "$git_common_dir"
            set -a cmd --bind "$git_common_dir" "$git_common_dir"
        end
    end

    if test $env_block -eq 1
        for env_file in (find "$project_path" -maxdepth 1 -name '.env*' -type f 2>/dev/null)
            set -a cmd --ro-bind /dev/null "$target_path/"(basename "$env_file")
        end
    end

    for mount in $extra_ro_mounts
        set -l parts (string split : "$mount")
        if test (count $parts) -eq 2
            if test -e "$parts[1]"
                set -a cmd --ro-bind "$parts[1]" "$parts[2]"
            end
        else if test -e "$mount"
            set -a cmd --ro-bind "$mount" "$mount"
        end
    end

    for mount in $extra_rw_mounts
        set -l parts (string split : "$mount")
        if test (count $parts) -eq 2
            if test -e "$parts[1]"
                set -a cmd --bind "$parts[1]" "$parts[2]"
            end
        else if test -e "$mount"
            set -a cmd --bind "$mount" "$mount"
        end
    end

    set -l rc_root (__hawt_sandbox_find_rc_root "$project_path")
    set -l rc_file "$rc_root/.worktreerc"

    # Blocked system path prefixes - .worktreerc must not override these
    set -l blocked_prefixes / /proc /dev /sys /etc /usr /bin /sbin /lib /lib64 /boot /var /root /run /home

    # Check if a resolved path matches any blocked prefix (exact or starts with prefix/).
    # path resolve follows symlinks, so symlink-based bypass attempts are handled:
    # e.g. /tmp/evil -> /etc would resolve to /etc and be blocked.
    function __hawt_sandbox_is_blocked -S
        set -l check_path (path resolve "$argv[1]")
        for prefix in $blocked_prefixes
            if test "$check_path" = "$prefix"
                return 0
            end
            if test "$prefix" != /; and string match -q "$prefix/*" "$check_path"
                return 0
            end
        end
        return 1
    end

    if test -f "$rc_file"
        while read -l line
            set -l ro_match (string match -r '^bwrap-bind-ro:\s*(.+)' "$line")
            if test (count $ro_match) -ge 2
                set -l raw (string trim $ro_match[2])
                set -l expanded (string replace -r '^~/' "$HOME/" "$raw")
                if test "$expanded" = "~"
                    set expanded "$HOME"
                end
                if __hawt_sandbox_is_blocked "$expanded"
                    echo "hawt: worktreerc: blocked bind-ro path: $expanded" >&2
                    if test "$expanded" = /
                        set add_root_ro_bind 0
                    end
                    continue
                end
                if test -e "$expanded"
                    set -a cmd --ro-bind "$expanded" "$expanded"
                end
            end

            set -l rw_match (string match -r '^bwrap-bind-rw:\s*(.+)' "$line")
            if test (count $rw_match) -ge 2
                set -l raw (string trim $rw_match[2])
                set -l expanded (string replace -r '^~/' "$HOME/" "$raw")
                if test "$expanded" = "~"
                    set expanded "$HOME"
                end
                if __hawt_sandbox_is_blocked "$expanded"
                    echo "hawt: worktreerc: blocked bind-rw path: $expanded" >&2
                    continue
                end
                if test -e "$expanded"
                    set -a cmd --bind "$expanded" "$expanded"
                end
            end

            set -l tmpfs_match (string match -r '^bwrap-tmpfs:\s*(.+)' "$line")
            if test (count $tmpfs_match) -ge 2
                set -l tmpfs_path (string trim $tmpfs_match[2])
                if __hawt_sandbox_is_blocked "$tmpfs_path"
                    echo "hawt: worktreerc: blocked tmpfs path: $tmpfs_path" >&2
                    continue
                end
                set -a cmd --tmpfs "$tmpfs_path"
            end
        end <"$rc_file"
    end

    functions -e __hawt_sandbox_is_blocked

    # Added early in the arg list (after --die-with-parent) so more specific
    # mounts overlay it. Skipped only if a .worktreerc tried to override /.
    # Invariant: cmd[1] is "bwrap", cmd[2] is "--die-with-parent".
    # The insertion at cmd[3..] relies on this ordering.
    if test $add_root_ro_bind -eq 1
        set -l head $cmd[1..2]
        set -l tail $cmd[3..]
        set cmd $head --ro-bind / / $tail
    end

    set -a cmd --chdir "$target_path"

    # Output one arg per line for clean fish array capture
    printf '%s\n' $cmd
end
