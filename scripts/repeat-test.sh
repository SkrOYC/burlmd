#!/usr/bin/env sh

set -eu

usage() {
    printf '%s\n' 'usage: repeat-test.sh --count N -- COMMAND...' >&2
}

if [ "$#" -lt 4 ] || [ "$1" != '--count' ]; then
    usage
    exit 2
fi

count=$2
case "$count" in
    '' | *[!0-9]*)
        printf '%s\n' 'repeat-test.sh: --count must be a positive integer' >&2
        usage
        exit 2
        ;;
esac

if [ "$count" -eq 0 ]; then
    printf '%s\n' 'repeat-test.sh: --count must be a positive integer' >&2
    usage
    exit 2
fi

if [ "$3" != '--' ]; then
    usage
    exit 2
fi

shift 3

iteration=1
while [ "$iteration" -le "$count" ]; do
    if "$@"; then
        :
    else
        status=$?
        printf 'repeat-test.sh: iteration %s of %s failed with exit status %s\n' \
            "$iteration" "$count" "$status" >&2
        exit "$status"
    fi
    iteration=$((iteration + 1))
done
