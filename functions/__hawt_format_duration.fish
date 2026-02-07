function __hawt_format_duration --description "Format seconds as human-readable duration" -a seconds
    if test "$seconds" -lt 60
        echo "$seconds"s
    else if test "$seconds" -lt 3600
        set -l m (math "floor($seconds / 60)")
        set -l s (math "$seconds % 60")
        echo "$m"m"$s"s
    else
        set -l h (math "floor($seconds / 3600)")
        set -l m (math "floor(($seconds % 3600) / 60)")
        echo "$h"h"$m"m
    end
end
