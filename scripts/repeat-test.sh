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

# Compare equal-length non-negative decimal strings from their most-significant
# digits. Do not use the shell's string-ordering operators here: their
# collation behavior is not a portable numeric comparison under an arbitrary
# POSIX `sh` locale.
decimal_greater_than() {
    left=$1
    right=$2
    while [ -n "$left" ]; do
        left_rest=${left#?}
        right_rest=${right#?}
        left_digit=${left%"$left_rest"}
        right_digit=${right%"$right_rest"}
        if [ "$left_digit" -gt "$right_digit" ]; then
            return 0
        fi
        if [ "$left_digit" -lt "$right_digit" ]; then
            return 1
        fi
        left=$left_rest
        right=$right_rest
    done
    return 1
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

# Keep the decimal representation canonical. Accepting leading zeroes would
# make otherwise distinct command lines compare differently at the boundary.
case "$count" in
    0 | 0*)
    invalid_count
    ;;
esac

if [ "${#count}" -gt "${#shell_long_max}" ] || {
    [ "${#count}" -eq "${#shell_long_max}" ] && decimal_greater_than "$count" "$shell_long_max"
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
    # Do not increment after the final accepted iteration: a count equal to
    # the shell's largest representable positive integer would otherwise
    # overflow despite passing the input-range check above.
    [ "$iteration" = "$count" ] && break
    iteration=$((iteration + 1))
done
