function __hawt_do_reload --description "Reload hawt in current shell"
    # Determine source directory before unloading
    set -l hawt_file (functions --details hawt 2>/dev/null)
    if test -z "$hawt_file" -o "$hawt_file" = stdin -o "$hawt_file" = -
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
