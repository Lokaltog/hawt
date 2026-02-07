#!/usr/bin/env fish
# try.fish - Load hawt into the current shell without installing

set -l script_dir (status dirname)

set -p fish_function_path $script_dir/functions $script_dir
set -p fish_complete_path $script_dir/completions
source $script_dir/completions/hawt.fish

echo (set_color green)"hawt loaded into current shell."(set_color normal)
echo "Run 'hawt help' to get started."
