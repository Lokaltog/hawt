function __hawt_do_unload --description "Unload hawt from current shell"
    set -l quiet 0
    if contains -- --quiet $argv
        set quiet 1
    end

    # Resolve source directory for path cleanup
    set -l hawt_file (functions --details hawt 2>/dev/null)
    set -l src_dir ""
    if test -n "$hawt_file" -a "$hawt_file" != stdin -a "$hawt_file" != -
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
