#!/bin/sh

set -u

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
set +e
. "$repo_dir/files/lib/mwan3/common.sh"
set -e
. "$repo_dir/files/lib/mwan3/adaptive.sh"

MMX_MASK=0x3f00

fail()
{
	echo "FAIL: $*" >&2
	exit 1
}

count_action()
{
	printf '%s\n' "$_mwan3_vmap_entries" | grep -o "mwan3_or_meta_$1" | wc -l | tr -d ' '
}

sequence()
{
	printf '%s\n' "$_mwan3_vmap_entries" |
		grep -o 'mwan3_or_meta_0x[0-9a-f]*' |
		sed 's/mwan3_or_meta_//' |
		tr '\n' ' ' |
		sed 's/ $//'
}

_mwan3_reduce_member_weights "a:1:700 b:2:700 c:3:600"
[ "$_mwan3_reduced_total" = 20 ] || fail "weight GCD reduction has wrong total"
[ "$_mwan3_reduced_members" = " a:1:7 b:2:7 c:3:6" ] || fail "weight GCD reduction has wrong members"

_mwan3_build_smooth_vmap "a:1:7 b:2:7 c:3:6" 20
[ "$(count_action 0x100)" = 7 ] || fail "7/7/6 map has wrong A count"
[ "$(count_action 0x200)" = 7 ] || fail "7/7/6 map has wrong B count"
[ "$(count_action 0x300)" = 6 ] || fail "7/7/6 map has wrong C count"
[ "$(sequence)" = "0x100 0x200 0x300 0x100 0x200 0x300 0x100 0x200 0x300 0x100 0x200 0x300 0x100 0x200 0x300 0x100 0x200 0x300 0x100 0x200" ] ||
	fail "7/7/6 assignments are not smoothly interleaved"

_mwan3_build_smooth_vmap "a:1:700 b:2:350 c:3:50" 256
[ "$(count_action 0x100)" = 163 ] || fail "adaptive map has wrong A count"
[ "$(count_action 0x200)" = 81 ] || fail "adaptive map has wrong B count"
[ "$(count_action 0x300)" = 12 ] || fail "adaptive map has wrong C count"

_mwan3_build_minimum_smooth_vmap "a:1:1000000 b:2:1 c:3:1" 256
[ "$(count_action 0x100)" = 254 ] || fail "bounded map has wrong dominant count"
[ "$(count_action 0x200)" = 1 ] || fail "bounded map starved member B"
[ "$(count_action 0x300)" = 1 ] || fail "bounded map starved member C"

if _mwan3_build_smooth_vmap "a:1:0 b:2:bad" 20; then
	fail "invalid weights unexpectedly produced a map"
fi
if _mwan3_build_smooth_vmap "a:1:1" 0; then
	fail "zero slots unexpectedly produced a map"
fi

echo "PASS: adaptive weighted-map tests"
