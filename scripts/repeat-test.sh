#!/usr/bin/env sh

set -eu

usage() {
    printf '%s\n' 'usage: repeat-test.sh --count N -- COMMAND...' >&2
}

invalid_count() {
    printf '%s\n' 'repeat-test.sh: --count must be a positive integer representable by this shell' >&2
    usage
    exit 2
}

# Returns twice a non-negative decimal string plus one. Each arithmetic
# operation only handles one digit, so this can derive the shell's full signed
# range without overflowing while it validates the caller's count.
double_plus_one() {
    value=$1
    carry=1
    result=
    while [ -n "$value" ]; do
        prefix=${value%?}
        digit=${value#"$prefix"}
        value=$prefix
        digit=$((digit * 2 + carry))
        if [ "$digit" -ge 10 ]; then
            digit=$((digit - 10))
            carry=1
        else
            carry=0
        fi
        result=$digit$result
    done
    if [ "$carry" -ne 0 ]; then
        result=$carry$result
    fi
    printf '%s\n' "$result"
}

# POSIX shell arithmetic uses signed long integers. Build its maximum as a
# decimal string so an overlarge but digit-only count is rejected before any
# numeric comparison can emit an implementation diagnostic.
shell_long_bits=$(getconf LONG_BIT 2>/dev/null)
shell_long_max=0
bit=1
while [ "$bit" -lt "$shell_long_bits" ]; do
    shell_long_max=$(double_plus_one "$shell_long_max")
    bit=$((bit + 1))
done

if [ "$#" -lt 4 ] || [ "$1" != '--count' ]; then
    usage
    exit 2
fi

count=$2
case "$count" in
    '' | *[!0-9]*)
        invalid_count
        ;;
esac

# Strip leading zeroes before comparing or using shell arithmetic; an
# otherwise valid value such as 0001 must not overflow only because of its
# presentation.
count=$(printf '%s\n' "$count" | sed 's/^0*//')
if [ -z "$count" ]; then
    invalid_count
fi

if [ "${#count}" -gt "${#shell_long_max}" ] || {
    [ "${#count}" -eq "${#shell_long_max}" ] && [ "$count" \> "$shell_long_max" ]
}; then
    invalid_count
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
