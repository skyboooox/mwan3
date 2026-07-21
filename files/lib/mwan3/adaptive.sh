#!/bin/sh

# Shared adaptive-policy helpers. This file expects common.sh to provide
# mwan3_id2mask() and mwan3_or_chain_suffix().

_mwan3_reduce_member_weights()
{
	local members="$1" member iface id weight a b tmp divisor=0 reduced="" total=0

	for member in $members; do
		weight="${member##*:}"
		case "$weight" in ''|*[!0-9]*|0) return 1 ;; esac
		a=$weight
		b=$divisor
		while [ "$b" -ne 0 ]; do
			tmp=$((a % b))
			a=$b
			b=$tmp
		done
		divisor=$a
	done
	[ "$divisor" -gt 0 ] || return 1

	for member in $members; do
		iface="${member%%:*}"
		id="${member#*:}"
		id="${id%%:*}"
		weight="${member##*:}"
		weight=$((weight / divisor))
		reduced="$reduced $iface:$id:$weight"
		total=$((total + weight))
	done
	_mwan3_reduced_members="$reduced"
	_mwan3_reduced_total=$total
}

# Build a deterministic smooth weighted round-robin verdict map body.
#
# The old policy rule used one contiguous range per member. With numgen inc,
# a 7/7/6 policy consequently sent seven consecutive new connections to the
# first member, seven to the second, and six to the third. Short connection
# bursts were badly skewed even though a complete 20-connection cycle had the
# requested proportions.
#
# This implementation adds every member's weight to its accumulator, selects
# the largest accumulator, then subtracts the total weight from the selected
# member. It preserves exact configured proportions when slots == total weight
# and spreads assignments evenly for a fixed-size adaptive map.
#
# $1: space-separated iface:id:weight tuples
# $2: number of slots
# Sets _mwan3_vmap_entries.

_mwan3_build_smooth_vmap()
{
	local members="$1" slots="$2" member id weight mark action
	local count=0 total=0 slot i current best best_current entries=""

	case "$slots" in
		''|*[!0-9]*|0) return 1 ;;
	esac

	for member in $members; do
		id="${member#*:}"
		id="${id%%:*}"
		weight="${member##*:}"
		case "$weight" in
			''|*[!0-9]*|0) continue ;;
		esac
		count=$((count + 1))
		mark=$(mwan3_id2mask id MMX_MASK)
		action="mwan3_or_meta_$(mwan3_or_chain_suffix "$mark")"
		eval "_mwan3_smooth_weight_$count=\$weight"
		eval "_mwan3_smooth_current_$count=0"
		eval "_mwan3_smooth_action_$count=\$action"
		total=$((total + weight))
	done

	[ "$count" -gt 0 ] && [ "$total" -gt 0 ] || return 1

	slot=0
	while [ "$slot" -lt "$slots" ]; do
		best=0
		best_current=0
		i=1
		while [ "$i" -le "$count" ]; do
			eval "weight=\${_mwan3_smooth_weight_$i}"
			eval "current=\${_mwan3_smooth_current_$i}"
			current=$((current + weight))
			eval "_mwan3_smooth_current_$i=\$current"
			if [ "$best" -eq 0 ] || [ "$current" -gt "$best_current" ]; then
				best=$i
				best_current=$current
			fi
			i=$((i + 1))
		done

		best_current=$((best_current - total))
		eval "_mwan3_smooth_current_$best=\$best_current"
		eval "action=\${_mwan3_smooth_action_$best}"
		[ -n "$entries" ] && entries="$entries, "
		entries="${entries}${slot} : jump ${action}"
		slot=$((slot + 1))
	done

	_mwan3_vmap_entries="$entries"
}

# Bounded maps can otherwise round a low-weight member down to zero slots.
# Reserve one slot per member, distribute the remainder with smooth weighted
# round-robin, then smooth the resulting exact slot counts a second time.

_mwan3_build_minimum_smooth_vmap()
{
	local members="$1" slots="$2" member iface id weight
	local count=0 total=0 remaining i best best_current current target tuples=""

	case "$slots" in ''|*[!0-9]*|0) return 1 ;; esac
	for member in $members; do
		iface="${member%%:*}"
		id="${member#*:}"
		id="${id%%:*}"
		weight="${member##*:}"
		case "$weight" in ''|*[!0-9]*|0) continue ;; esac
		count=$((count + 1))
		eval "_mwan3_min_iface_$count=\$iface"
		eval "_mwan3_min_id_$count=\$id"
		eval "_mwan3_min_weight_$count=\$weight"
		eval "_mwan3_min_current_$count=0"
		eval "_mwan3_min_target_$count=1"
		total=$((total + weight))
	done
	[ "$count" -gt 0 ] && [ "$slots" -ge "$count" ] || return 1

	remaining=$((slots - count))
	while [ "$remaining" -gt 0 ]; do
		best=0
		best_current=0
		i=1
		while [ "$i" -le "$count" ]; do
			eval "weight=\${_mwan3_min_weight_$i}"
			eval "current=\${_mwan3_min_current_$i}"
			current=$((current + weight))
			eval "_mwan3_min_current_$i=\$current"
			if [ "$best" -eq 0 ] || [ "$current" -gt "$best_current" ]; then
				best=$i
				best_current=$current
			fi
			i=$((i + 1))
		done
		eval "_mwan3_min_current_$best=$((best_current - total))"
		eval "target=\${_mwan3_min_target_$best}"
		eval "_mwan3_min_target_$best=$((target + 1))"
		remaining=$((remaining - 1))
	done

	i=1
	while [ "$i" -le "$count" ]; do
		eval "iface=\${_mwan3_min_iface_$i}"
		eval "id=\${_mwan3_min_id_$i}"
		eval "target=\${_mwan3_min_target_$i}"
		tuples="$tuples $iface:$id:$target"
		i=$((i + 1))
	done
	_mwan3_build_smooth_vmap "$tuples" "$slots"
}
