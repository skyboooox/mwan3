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
# Keep the syntax fixture compact. The full 256-slot allocation is covered by
# test-adaptive.sh, while this test exercises the nft verdict-map grammar.
_mwan3_build_minimum_smooth_vmap "a:1:7 b:2:7 c:3:6" 16
adaptive_entries=$_mwan3_vmap_entries

nft_version=$(nft --version | sed -n 's/^nftables v\([0-9][0-9.]*\).*/\1/p')
case "$nft_version" in
	0.*|1.0.*) check_atomic_teardown=0 ;;
	*) check_atomic_teardown=1 ;;
esac

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
		'}'
	if [ "$check_atomic_teardown" -eq 1 ]; then
		printf '%s\n' \
			'flush chain inet mwan3_syntax_test adaptive_policy' \
			'flush chain inet mwan3_syntax_test static_policy' \
			'flush map inet mwan3_syntax_test mwan3_adaptive_v4_test' \
			'delete map inet mwan3_syntax_test mwan3_adaptive_v4_test' \
			'delete chain inet mwan3_syntax_test adaptive_policy' \
			'delete chain inet mwan3_syntax_test static_policy'
	fi
} | nft -c -f -

if [ "$check_atomic_teardown" -eq 1 ]; then
	echo "PASS: nft verdict-map syntax and teardown ordering"
else
	echo "PASS: nft verdict-map syntax (atomic teardown skipped on nftables $nft_version)"
fi
