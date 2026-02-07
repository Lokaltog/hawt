function __hawt_error --description "Print error message to stderr"
    echo (set_color red)"$argv"(set_color normal) >&2
end
