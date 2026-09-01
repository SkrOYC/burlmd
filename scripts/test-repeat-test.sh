#!/usr/bin/env sh

set -eu

root=$(cd "$(dirname "$0")/.." && pwd -P)
repeat_test=$root/scripts/repeat-test.sh
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-repeat-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

# Mirror repeat-test.sh's digit-at-a-time maximum derivation so these fixtures
# remain valid on both 32-bit and 64-bit POSIX shells.
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
    [ "$carry" -eq 0 ] || result=$carry$result
    printf '%s\n' "$result"
}

decimal_adjust() {
    value=$1
    delta=$2
    carry=$delta
    result=
    while [ -n "$value" ]; do
        prefix=${value%?}
        digit=${value#"$prefix"}
        value=$prefix
        digit=$((digit + carry))
        if [ "$digit" -eq 10 ]; then
            digit=0; carry=1
        elif [ "$digit" -lt 0 ]; then
            digit=9; carry=-1
        else
            carry=0
        fi
        result=$digit$result
    done
    [ "$carry" -ne 1 ] || result=1$result
    printf '%s\n' "$result"
}

expect_first_failure() {
    count=$1
    if output=$(sh "$repeat_test" --count "$count" -- sh -c 'exit 7' 2>&1); then
        printf '%s\n' "accepted command unexpectedly succeeded for count $count" >&2; exit 1
    else status=$?; fi
    [ "$status" -eq 7 ] || { printf '%s\n' "count $count exited $status, expected 7" >&2; exit 1; }
    case "$output" in
        *"iteration 1 of $count failed with exit status 7"*) ;;
        *) printf '%s\n' "count $count was not accepted: $output" >&2; exit 1 ;;
    esac
}

expect_rejected() {
    count=$1
    if output=$(sh "$repeat_test" --count "$count" -- true 2>&1); then
        printf '%s\n' "accepted invalid count $count" >&2; exit 1
    else status=$?; fi
    [ "$status" -eq 2 ] || { printf '%s\n' "count $count exited $status, expected 2: $output" >&2; exit 1; }
}

shell_long_max=0
bit=1
shell_long_bits=$(getconf LONG_BIT)
while [ "$bit" -lt "$shell_long_bits" ]; do
    shell_long_max=$(double_plus_one "$shell_long_max")
    bit=$((bit + 1))
done

one_below=$(decimal_adjust "$shell_long_max" -1)
one_above=$(decimal_adjust "$shell_long_max" 1)
# This value is smaller at its first digit but larger at its final digit. A
# right-to-left comparison rejects it incorrectly on ordinary POSIX long max.
earlier_digit_smaller="8${shell_long_max#?}"
earlier_digit_smaller="${earlier_digit_smaller%?}9"

expect_first_failure "$shell_long_max"
expect_first_failure "$one_below"
expect_rejected "$one_above"
expect_first_failure "$earlier_digit_smaller"
expect_rejected 0100

counter=$tmp/count
: >"$counter"
sh "$repeat_test" --count 100 -- sh -c 'printf x >> "$1"' sh "$counter"
[ "$(wc -c <"$counter")" -eq 100 ] || { printf '%s\n' 'count 100 did not run exactly 100 times' >&2; exit 1; }
