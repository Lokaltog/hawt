#!/usr/bin/env fish
# install.fish - Install hawt (git worktree helper) for fish shell

set -l script_dir (status dirname)
set -l fish_func_dir "$HOME/.config/fish/functions"
set -l fish_comp_dir "$HOME/.config/fish/completions"

mkdir -p "$fish_func_dir" "$fish_comp_dir"

# Install function files
for f in $script_dir/functions/*.fish
    set -l target "$fish_func_dir/"(basename "$f")
    if test -L "$target" -o -f "$target"
        echo (set_color yellow)"Replacing: "(basename "$f")(set_color normal)
    else
        echo (set_color green)"Installing: "(basename "$f")(set_color normal)
    end
    ln -sf (realpath "$f") "$target"
end

# Install completions
for f in $script_dir/completions/*.fish
    set -l target "$fish_comp_dir/"(basename "$f")
    if test -L "$target" -o -f "$target"
        echo (set_color yellow)"Replacing: "(basename "$f")(set_color normal)
    else
        echo (set_color green)"Installing: "(basename "$f")(set_color normal)
    end
    ln -sf (realpath "$f") "$target"
end

echo ""
echo (set_color green)"✓ hawt installed successfully!"(set_color normal)
echo ""
echo "  Reload your shell or run: source ~/.config/fish/config.fish"
echo ""
echo "  Usage:"
echo "    hawt                  - fzf picker"
echo "    hawt <name>           - create/switch to worktree"
echo "    hawt status           - overview table"
echo "    hawt help             - full help"
echo ""
echo "  Optional: copy .worktreerc.example to your repo root as .worktreerc"
echo ""
