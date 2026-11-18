# Sourced by every fake executable. Appends one line per call to
# $QUICKPDF_CALL_LOG: the program name, then each argument in base64 so that
# spaces, quotes and newlines survive the round trip.

quickpdf_record() {
    [ -n "${QUICKPDF_CALL_LOG:-}" ] || return 0
    local record="$(basename "$0")"
    local arg
    for arg in "$@"; do
        record="$record $(printf '%s' "$arg" | base64 -w0)"
    done
    printf '%s\n' "$record" >>"$QUICKPDF_CALL_LOG"
}
