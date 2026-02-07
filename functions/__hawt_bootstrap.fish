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
