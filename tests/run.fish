#!/usr/bin/env fish
# Download fishtape on-demand and run all tests

set -l test_dir (status dirname)
set -l cache_dir "$test_dir/.cache"
set -l fishtape_url "https://raw.githubusercontent.com/jorgebucaran/fishtape/main/functions/fishtape.fish"

# Download fishtape if not cached
if not test -f "$cache_dir/fishtape.fish"
    echo "Downloading fishtape..."
    mkdir -p $cache_dir
    curl -sfL "$fishtape_url" -o "$cache_dir/fishtape.fish"; or begin
        echo "Failed to download fishtape" >&2
        exit 1
    end
end

# Make fishtape available via fish autoloader
set -p fish_function_path $cache_dir

fishtape $test_dir/test_*.fish
