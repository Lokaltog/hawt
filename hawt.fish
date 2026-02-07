function hawt --description "Git worktree helper with fzf, bootstrap, and lifecycle hooks"
    set -l subcmd $argv[1]

    switch "$subcmd"
        case status
            __hawt_status
        case clean
            __hawt_clean
        case tmp
            __hawt_tmp $argv[2..]
        case rm remove
            __hawt_remove $argv[2..]
        case help -h --help
            __hawt_help
        case ''
            __hawt_pick
        case cc
            __hawt_cc $argv[2..]
        case merge
            __hawt_merge $argv[2..]
        case diff
            __hawt_diff $argv[2..]
        case ps
            __hawt_ps
        case kill
            __hawt_kill $argv[2..]
        case lock
            __hawt_lock $argv[2..]
        case unlock
            __hawt_unlock $argv[2..]
        case sandbox
            __hawt_sandbox_run $argv[2..]
        case batch
            __hawt_batch $argv[2..]
        case review
            __hawt_review $argv[2..]
        case checkpoint
            __hawt_checkpoint $argv[2..]
        case unload
            __hawt_do_unload $argv[2..]
        case reload
            __hawt_do_reload
        case '*'
            # Anything else is treated as a worktree name to upsert
            __hawt_upsert $argv
    end
end

function __hawt_pick --description "Interactive fzf worktree picker"
    set -l root (__hawt_repo_root); or return 1
    set -l worktrees (git worktree list --porcelain | string replace -rf '^worktree (.+)' '$1')

    if test (count $worktrees) -le 1
        echo (set_color yellow)"No additional worktrees. Use: hawt <name> to create one."(set_color normal)
        return 1
    end

    set -l selected (
        for hawt_path in $worktrees
            set -l branch (git -C "$hawt_path" branch --show-current 2>/dev/null; or echo "detached")
            set -l dirty ""
            if test -n "$(git -C "$hawt_path" status --porcelain 2>/dev/null | head -1)"
                set dirty " ●"
            end
            set -l rel_path (string replace "$root/" "" "$hawt_path")
            if not string match -q "$rel_path" "$hawt_path"
                set rel_path (realpath --relative-to=(pwd) "$hawt_path" 2>/dev/null; or echo "$hawt_path")
            end
            printf "%s\t%s%s\t%s\n" "$hawt_path" (set_color cyan)"$branch"(set_color normal) (set_color red)"$dirty"(set_color normal) (set_color brblack)"$rel_path"(set_color normal)
        end | fzf --ansi --delimiter='\t' \
              --with-nth=2,3,4 \
              --header="Select worktree (enter=cd, ctrl-d=remove)" \
              --bind="ctrl-d:execute(git worktree remove --force {1})+reload(git worktree list --porcelain | grep '^worktree ' | sed 's/worktree //')" \
              --preview="git -C {1} log --oneline --graph -15 --color=always 2>/dev/null" \
              --preview-window=right:50%
    )

    if test -n "$selected"
        set -l target (echo "$selected" | cut -f1)
        cd "$target"
    end
end

function __hawt_upsert --description "Create or switch to a named worktree"
    argparse 'f/from=' -- $argv; or return 1

    set -l name $argv[1]
    set -l base_ref (set -q _flag_from; and echo $_flag_from; or echo HEAD)

    set -l root (__hawt_repo_root); or return 1
    set -l hawt_base (__hawt_worktree_base "$root")
    set -l hawt_path "$hawt_base/$name"

    # Check if worktree already exists
    if test -d "$hawt_path"
        echo (set_color green)"↪ Worktree '$name' exists, switching..."(set_color normal)
        cd "$hawt_path"
        return 0
    end

    # Resolve base ref
    if not git rev-parse --verify "$base_ref" >/dev/null 2>&1
        __hawt_error "Ref '$base_ref' does not exist"
        return 1
    end

    # Auto-stash current worktree if dirty
    __hawt_maybe_stash

    echo (set_color blue)"Creating worktree '$name' from $base_ref..."(set_color normal)
    mkdir -p "$hawt_base"

    # Create worktree with a new branch named after the worktree
    if git show-ref --verify --quiet "refs/heads/$name" 2>/dev/null
        git worktree add "$hawt_path" "$name"
    else
        git worktree add -b "$name" "$hawt_path" "$base_ref"
    end

    if test $status -ne 0
        __hawt_error "Failed to create worktree"
        return 1
    end

    # Bootstrap the worktree
    __hawt_bootstrap "$root" "$hawt_path"

    # Run post-create hook
    __hawt_run_hook "$root" "$hawt_path" post-create

    echo (set_color green)"✓ Worktree '$name' ready at $hawt_path"(set_color normal)
    cd "$hawt_path"
end

function __hawt_status --description "Overview table of all worktrees"
    set -l root (__hawt_repo_root); or return 1

    # Determine default branch for fork-point fallback
    set -l default_branch ""
    set -l remote_head (git -C "$root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | string replace 'refs/remotes/origin/' '')
    if test -n "$remote_head"
        set default_branch "$remote_head"
    else
        for candidate in main master
            if git -C "$root" show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null
                set default_branch "$candidate"
                break
            end
        end
    end

    printf "\n"
    printf (set_color --bold)" %-30s %-25s %-15s %-15s %s\n"(set_color normal) WORKTREE BRANCH STATE "↑↓ SYNC" AGE
    printf " %s\n" (string repeat -n 95 "─")

    git worktree list --porcelain | while read -l line
        if string match -q "worktree *" "$line"
            set -l hawt_path (string replace "worktree " "" "$line")
            set -l branch (git -C "$hawt_path" branch --show-current 2>/dev/null; or echo "detached")
            set -l display_path (basename "$hawt_path")

            # Mark main worktree
            if test "$hawt_path" = "$root"
                set display_path "$display_path (main)"
            end

            # Dirty state
            set -l state_text clean
            set -l state_color green
            set -l dirty_count (__hawt_dirty_count "$hawt_path")
            if test "$dirty_count" -gt 0
                set state_text "dirty ($dirty_count)"
                set state_color red
            end

            # Ahead/behind - try upstream tracking, then remote branch, then fork-point
            set -l ab_text ""
            set -l ab_color brblack
            set -l upstream (git -C "$hawt_path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
            if test -z "$upstream"
                set -l remote_ref "origin/$branch"
                if git -C "$hawt_path" rev-parse --verify "$remote_ref" >/dev/null 2>&1
                    set upstream "$remote_ref"
                end
            end
            if test -n "$upstream"
                set -l ahead (git -C "$hawt_path" rev-list --count "$upstream..HEAD" 2>/dev/null; or echo 0)
                set -l behind (git -C "$hawt_path" rev-list --count "HEAD..$upstream" 2>/dev/null; or echo 0)
                if test "$ahead" -gt 0 -o "$behind" -gt 0
                    set ab_text "↑$ahead ↓$behind"
                    set ab_color yellow
                else
                    set ab_text "in sync"
                end
            else if test -n "$default_branch" -a "$branch" != "$default_branch"
                set -l ahead (git -C "$hawt_path" rev-list --count "$default_branch..HEAD" 2>/dev/null; or echo 0)
                if test "$ahead" -gt 0
                    set ab_text "↑$ahead vs $default_branch"
                    set ab_color cyan
                else
                    set ab_text "=$default_branch"
                end
            else
                set ab_text "no upstream"
            end

            # Age of last commit
            set -l age (git -C "$hawt_path" log -1 --format='%cr' 2>/dev/null; or echo "unknown")

            # Pad plain text before applying colors to avoid ANSI codes breaking printf widths
            set -l c1 (string pad -r -w 30 -- "$display_path")
            set -l c2 (string pad -r -w 25 -- "$branch")
            set -l c3 (string pad -r -w 15 -- "$state_text")
            set -l c4 (string pad -r -w 15 -- "$ab_text")

            printf " %s %s%s%s %s%s%s %s%s%s %s%s%s\n" \
                "$c1" \
                (set_color cyan) "$c2" (set_color normal) \
                (set_color $state_color) "$c3" (set_color normal) \
                (set_color $ab_color) "$c4" (set_color normal) \
                (set_color brblack) "$age" (set_color normal)
        end
    end
    printf "\n"
end

function __hawt_clean --description "Prune stale refs and orphaned directories"
    set -l root (__hawt_repo_root); or return 1
    set -l hawt_base (__hawt_worktree_base "$root")

    echo (set_color blue)"Pruning stale worktree references..."(set_color normal)
    git worktree prune -v

    # Check for orphaned directories in the worktree base
    if test -d "$hawt_base"
        set -l tracked_paths (git worktree list --porcelain | string match -r 'worktree (.+)' | string replace 'worktree ' '')

        for dir in $hawt_base/*/
            set -l dir (string trim --right --chars=/ "$dir")
            if not contains "$dir" $tracked_paths
                echo (set_color yellow)"Orphaned directory: $dir"(set_color normal)
                read -l -P "  Remove? [y/N] " confirm
                if test "$confirm" = y -o "$confirm" = Y
                    rm -rf "$dir"
                    echo (set_color green)"  Removed."(set_color normal)
                end
            end
        end
    end

    echo (set_color green)"✓ Clean complete"(set_color normal)
end

function __hawt_tmp --description "Create an ephemeral worktree in /tmp"
    set -l name $argv[1]
    if test -z "$name"
        set name "tmp-"(date +%s | tail -c 7)
    end

    set -l root (__hawt_repo_root); or return 1
    set -l tmp_path "/tmp/hawt-"(basename "$root")"-$name"

    echo (set_color magenta)"Creating ephemeral worktree '$name'..."(set_color normal)
    git worktree add --detach "$tmp_path" HEAD

    if test $status -ne 0
        return 1
    end

    __hawt_bootstrap "$root" "$tmp_path"

    # Tag this as ephemeral so the leave hook can auto-clean
    echo "$tmp_path" >>"$root/.git/hawt-ephemeral"

    echo (set_color green)"✓ Ephemeral worktree at $tmp_path"(set_color normal)
    echo (set_color brblack)"  Will be cleaned up on hawt clean or leave"(set_color normal)
    cd "$tmp_path"
end

function __hawt_remove --description "Remove a worktree"
    set -l name $argv[1]
    if test -z "$name"
        __hawt_error "Usage: hawt rm <name>"
        return 1
    end

    set -l root (__hawt_repo_root); or return 1
    set -l hawt_base (__hawt_worktree_base "$root")
    set -l hawt_path "$hawt_base/$name"

    if not test -d "$hawt_path"
        # Try matching by branch name in all worktrees
        set hawt_path (git worktree list --porcelain | while read -l line
            if string match -q "worktree *" "$line"
                set -l p (string replace "worktree " "" "$line")
                set -l b (git -C "$p" branch --show-current 2>/dev/null)
                if test "$b" = "$name"
                    echo "$p"
                    break
                end
            end
        end)
    end

    if test -z "$hawt_path" -o ! -d "$hawt_path"
        __hawt_error "Worktree '$name' not found"
        return 1
    end

    # Warn if dirty
    set -l dirty_count (__hawt_dirty_count "$hawt_path")
    if test "$dirty_count" -gt 0
        echo (set_color yellow)"⚠ Worktree has $dirty_count uncommitted changes"(set_color normal)
        read -l -P "  Force remove? [y/N] " confirm
        if test "$confirm" != y -a "$confirm" != Y
            return 1
        end
        git worktree remove --force "$hawt_path"
    else
        git worktree remove "$hawt_path"
    end

    echo (set_color green)"✓ Removed worktree '$name'"(set_color normal)
end

# ══════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════

function __hawt_repo_root --description "Resolve git repo root"
    set -l root (git rev-parse --show-toplevel 2>/dev/null)
    if test -z "$root"
        __hawt_error "Not in a git repository"
        return 1
    end

    # If we're in a worktree, resolve back to the main repo
    set -l common_dir (git rev-parse --git-common-dir 2>/dev/null)
    if test -n "$common_dir"
        set -l resolved (realpath "$common_dir" 2>/dev/null)
        if string match -q "*/.git" "$resolved"
            set root (string replace "/.git" "" "$resolved")
        end
    end

    echo "$root"
end

function __hawt_worktree_base --description "Return worktrees parent directory" -a root
    echo (dirname "$root")"/"(basename "$root")"-worktrees"
end

function __hawt_bootstrap --description "Set up worktree with symlinks and copies" -a root -a hawt_path
    echo (set_color blue)"Bootstrapping worktree..."(set_color normal)

    set -l rc_file "$root/.worktreerc"
    set -l did_something 0

    if test -f "$rc_file"
        # Parse .worktreerc
        while read -l line
            # Skip comments and empty lines
            if string match -q '#*' "$line"; or test -z "$(string trim "$line")"
                continue
            end

            set -l action (string match -r '^(\w+):\s*(.+)' "$line")
            if test (count $action) -lt 3
                continue
            end

            set -l cmd $action[2]
            set -l target $action[3]

            switch "$cmd"
                case symlink
                    if test -e "$root/$target"
                        if not test -e "$hawt_path/$target"
                            set -l resolved_target (path resolve "$hawt_path/$target")
                            if not string match -q "$hawt_path/*" "$resolved_target"
                                echo "  "(set_color yellow)"! Skipping $target (path escapes worktree)"(set_color normal) >&2
                                continue
                            end
                            # Ensure parent directory exists
                            mkdir -p (dirname "$hawt_path/$target")
                            ln -s "$root/$target" "$hawt_path/$target"
                            echo "  "(set_color green)"↳"(set_color normal)" symlinked $target"
                            set did_something 1
                        end
                    else
                        echo "  "(set_color brblack)"⊘ skipped $target (not in main repo)"(set_color normal)
                    end
                case copy
                    if test -e "$root/$target"
                        if not test -e "$hawt_path/$target"
                            set -l resolved_target (path resolve "$hawt_path/$target")
                            if not string match -q "$hawt_path/*" "$resolved_target"
                                echo "  "(set_color yellow)"! Skipping $target (path escapes worktree)"(set_color normal) >&2
                                continue
                            end
                            mkdir -p (dirname "$hawt_path/$target")
                            cp -a "$root/$target" "$hawt_path/$target"
                            echo "  "(set_color green)"⇒"(set_color normal)" copied $target"
                            set did_something 1
                        end
                    end
            end
        end <"$rc_file"
    else
        # Default heuristics for TypeScript/Node projects
        if test -f "$root/package.json"
            echo "  "(set_color brblack)"No .worktreerc found, applying TS/Node heuristics..."(set_color normal)

            # Symlink node_modules (always for TS projects)
            if test -d "$root/node_modules"
                if not test -e "$hawt_path/node_modules"
                    ln -s "$root/node_modules" "$hawt_path/node_modules"
                    echo "  "(set_color green)"↳"(set_color normal)" symlinked node_modules"
                    set did_something 1
                end
            end

            # Symlink common build caches
            for cache_dir in .next .turbo .nuxt dist .output .svelte-kit .parcel-cache
                if test -d "$root/$cache_dir"
                    if not test -e "$hawt_path/$cache_dir"
                        ln -s "$root/$cache_dir" "$hawt_path/$cache_dir"
                        echo "  "(set_color green)"↳"(set_color normal)" symlinked $cache_dir"
                        set did_something 1
                    end
                end
            end

            # Copy env files (never symlink secrets)
            for env_file in .env .env.local .env.development .env.development.local
                if test -f "$root/$env_file"
                    if not test -f "$hawt_path/$env_file"
                        cp "$root/$env_file" "$hawt_path/$env_file"
                        echo "  "(set_color green)"⇒"(set_color normal)" copied $env_file"
                        set did_something 1
                    end
                end
            end

            # Monorepo support: symlink nested node_modules
            if test -f "$root/pnpm-workspace.yaml" -o -f "$root/lerna.json" -o -d "$root/packages"
                for nested_nm in $root/packages/*/node_modules
                    if test -d "$nested_nm"
                        set -l rel (string replace "$root/" "" "$nested_nm")
                        if not test -e "$hawt_path/$rel"
                            mkdir -p (dirname "$hawt_path/$rel")
                            ln -s "$nested_nm" "$hawt_path/$rel"
                            echo "  "(set_color green)"↳"(set_color normal)" symlinked $rel"
                            set did_something 1
                        end
                    end
                end
            end
        end

        # Python heuristics
        if test -f "$root/pyproject.toml" -o -f "$root/setup.py"
            for venv_dir in .venv venv .tox
                if test -d "$root/$venv_dir"
                    if not test -e "$hawt_path/$venv_dir"
                        ln -s "$root/$venv_dir" "$hawt_path/$venv_dir"
                        echo "  "(set_color green)"↳"(set_color normal)" symlinked $venv_dir"
                        set did_something 1
                    end
                end
            end
        end

        # Nix heuristics
        if test -d "$root/.direnv"
            if not test -e "$hawt_path/.direnv"
                ln -s "$root/.direnv" "$hawt_path/.direnv"
                echo "  "(set_color green)"↳"(set_color normal)" symlinked .direnv"
                set did_something 1
            end
        end
    end

    if test $did_something -eq 0
        echo "  "(set_color brblack)"Nothing to bootstrap"(set_color normal)
    end
end

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

        set -l rc_hash (shasum -a 256 "$root/.worktreerc" 2>/dev/null | string split ' ')[1]
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

function __hawt_maybe_stash --description "Offer to stash dirty state"
    # Check if current directory is a git worktree with dirty state
    if git rev-parse --git-dir >/dev/null 2>&1
        set -l dirty_count (__hawt_dirty_count ".")
        if test "$dirty_count" -gt 0
            echo (set_color yellow)"Current worktree has $dirty_count uncommitted changes."(set_color normal)
            read -l -P "  Stash before switching? [y/N] " confirm
            if test "$confirm" = y -o "$confirm" = Y
                git stash push -m "hawt auto-stash before switch"
                echo (set_color green)"  Stashed."(set_color normal)
            end
        end
    end
end

# Verify a file is trusted before execution. Uses hash-based trust-on-first-use.
# Trust entries stored as "sha256hash:/path/to/file" lines in .hawt-trusted.
function __hawt_check_file_trust --description "Verify file trust via SHA-256 TOFU" -a file_path -a trust_file -a description
    if not test -f "$file_path"
        return 1
    end

    set -l file_hash (shasum -a 256 "$file_path" 2>/dev/null | string split ' ')[1]
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

function __hawt_do_unload --description "Unload hawt from current shell"
    set -l quiet 0
    if contains -- --quiet $argv
        set quiet 1
    end

    # Resolve source directory for path cleanup
    set -l hawt_file (functions --details hawt 2>/dev/null)
    set -l src_dir ""
    if test -n "$hawt_file" -a "$hawt_file" != stdin -a "$hawt_file" != "-"
        set src_dir (dirname (realpath "$hawt_file" 2>/dev/null) 2>/dev/null)
    end

    # Erase the PWD event handler to prevent firing during cleanup
    functions -e __hawt_on_pwd_change

    # Clean up global variables
    set -e __hawt_last_pwd

    # Erase all __hawt_* functions (includes completion helpers and this function)
    set -l hawt_funcs (functions -a | string match '__hawt_*')
    if test (count $hawt_funcs) -gt 0
        functions -e $hawt_funcs
    end

    # Erase all completions registered for the hawt command
    complete -e -c hawt

    # Remove hawt source dirs from fish function/completion paths (try.fish loading)
    if test -n "$src_dir"
        set -l func_dir "$src_dir/functions"
        set -l comp_dir "$src_dir/completions"

        set -l new_fp
        for p in $fish_function_path
            set -l rp (realpath "$p" 2>/dev/null; or echo "$p")
            if test "$rp" != "$src_dir" -a "$rp" != "$func_dir"
                set -a new_fp $p
            end
        end
        set fish_function_path $new_fp

        set -l new_cp
        for p in $fish_complete_path
            set -l rp (realpath "$p" 2>/dev/null; or echo "$p")
            if test "$rp" != "$comp_dir"
                set -a new_cp $p
            end
        end
        set fish_complete_path $new_cp
    end

    # Erase the main hawt function last
    functions -e hawt

    if test $quiet -eq 0
        echo (set_color green)"hawt unloaded from current shell."(set_color normal)
    end
end

function __hawt_do_reload --description "Reload hawt in current shell"
    # Determine source directory before unloading
    set -l hawt_file (functions --details hawt 2>/dev/null)
    if test -z "$hawt_file" -o "$hawt_file" = stdin -o "$hawt_file" = "-"
        __hawt_error "Cannot determine hawt source location"
        return 1
    end

    set -l src_dir (dirname (realpath "$hawt_file" 2>/dev/null) 2>/dev/null)
    if not test -d "$src_dir"
        __hawt_error "Source directory not found: $src_dir"
        return 1
    end

    if not test -f "$src_dir/hawt.fish"
        __hawt_error "hawt.fish not found in $src_dir"
        return 1
    end

    # Unload everything silently
    __hawt_do_unload --quiet

    # Re-add function and completion paths
    set -p fish_function_path "$src_dir/functions" "$src_dir"
    set -p fish_complete_path "$src_dir/completions"

    # Source all function files to override tombstones from functions -e
    source "$src_dir/hawt.fish"
    for f in "$src_dir"/functions/__hawt_*.fish
        source "$f"
    end

    # Source completions
    if test -f "$src_dir/completions/hawt.fish"
        source "$src_dir/completions/hawt.fish"
    end

    echo (set_color green)"hawt reloaded from $src_dir"(set_color normal)
end

function __hawt_help --description "Show help"
    echo ""
    echo (set_color --bold)"hawt - Git Worktree Helper"(set_color normal)
    echo ""
    echo (set_color --bold)"Worktrees:"(set_color normal)
    echo "  hawt                              Interactive fzf picker"
    echo "  hawt <name> [--from <ref>]        Create or switch to a named worktree"
    echo "  hawt status                       Overview table of all worktrees"
    echo "  hawt tmp [name]                   Ephemeral worktree in /tmp"
    echo "  hawt rm <name>                    Remove a worktree"
    echo "  hawt clean                        Prune stale refs and orphans"
    echo ""
    echo (set_color --bold)"Claude Code:"(set_color normal)
    echo "  hawt cc                           Run CC in sandbox on current repo"
    echo "  hawt cc <name> [--from <ref>]     Run CC in sandboxed worktree"
    echo "    --task \"...\"                     Write task to TASK.md"
    echo "    --offline                        Disable network"
    echo "    --dry-run                        Print bwrap command only"
    echo ""
    echo (set_color --bold)"Sessions:"(set_color normal)
    echo "  hawt batch <taskfile> [-j N]      Launch parallel CC sessions (-j/--max-parallel)"
    echo "  hawt ps                           Show running sessions"
    echo "  hawt kill <name>                  Terminate a session"
    echo "  hawt lock <name>                  Manually lock a worktree"
    echo "  hawt unlock <name>                Manually unlock a worktree"
    echo ""
    echo (set_color --bold)"Review & Merge:"(set_color normal)
    echo "  hawt diff <name> [--files|--stat] Review worktree changes"
    echo "  hawt review <name> [--ai] [--test] Post-session review"
    echo "  hawt merge <name> [--squash|...]  Merge worktree branch back"
    echo "  hawt checkpoint <name> [msg]      Commit worktree state from outside"
    echo ""
    echo (set_color --bold)"Sandbox:"(set_color normal)
    echo "  hawt sandbox [opts] -- <cmd>      Run any command in bwrap sandbox"
    echo ""
    echo (set_color --bold)"Shell:"(set_color normal)
    echo "  hawt unload                       Unload hawt from current shell"
    echo "  hawt reload                       Reload hawt (pick up code changes)"
    echo ""
    echo (set_color --bold)"Config:"(set_color normal)
    echo "  .worktreerc                       Bootstrap config (symlink/copy/post-create)"
    echo "  .worktree-hooks/post-create       Hook: runs after worktree creation"
    echo "  .worktree-hooks/on-leave          Hook: runs when leaving a worktree"
    echo ""
    echo "  Worktrees are created in ../<repo>-worktrees/<name>"
    echo ""
end
