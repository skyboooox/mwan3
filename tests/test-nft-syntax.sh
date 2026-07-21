#!/bin/sh

set -u

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
set +e
. "$repo_dir/files/lib/mwan3/common.sh"
set -e
. "$repo_dir/files/lib/mwan3/adaptive.sh"

MMX_MASK=0x3f00
_mwan3_build_smooth_vmap "a:1:7 b:2:7 c:3:6" 20
static_entries=$_mwan3_vmap_entries
# Ubuntu 24.04 currently ships nftables 1.0.9, whose check-only parser can
# segfault on a 256-element verdict-map literal. A 16-slot map exercises the
# identical named-map grammar and teardown dependencies; the full 256-slot
# allocation is covered by test-adaptive.sh and target-device nft 1.1.x tests.
_mwan3_build_minimum_smooth_vmap "a:1:7 b:2:7 c:3:6" 16
adaptive_entries=$_mwan3_vmap_entries

{
	printf '%s\n' \
		'table inet mwan3_syntax_test' \
		'delete table inet mwan3_syntax_test' \
		'table inet mwan3_syntax_test {' \
		' chain mwan3_or_meta_0x100 { }' \
		' chain mwan3_or_meta_0x200 { }' \
		' chain mwan3_or_meta_0x300 { }'
	printf ' map mwan3_adaptive_v4_test { type mark : verdict; elements = { %s } }\n' "$adaptive_entries"
	printf ' chain static_policy { numgen inc mod 20 vmap { %s }; }\n' "$static_entries"
	printf '%s\n' \
		' chain adaptive_policy { numgen inc mod 16 vmap @mwan3_adaptive_v4_test; }' \
		'}' \
		'flush chain inet mwan3_syntax_test adaptive_policy' \
		'flush chain inet mwan3_syntax_test static_policy' \
		'flush map inet mwan3_syntax_test mwan3_adaptive_v4_test' \
		'delete map inet mwan3_syntax_test mwan3_adaptive_v4_test' \
		'delete chain inet mwan3_syntax_test adaptive_policy' \
		'delete chain inet mwan3_syntax_test static_policy'
} | nft -c -f -

echo "PASS: nft verdict-map syntax and teardown ordering"
