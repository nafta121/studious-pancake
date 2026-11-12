class_name RoadGeom
extends RefCounted

## High-speed O(log N) road curve pose sampler & mobile touch hit-tester.

static func build_cum_lengths(pts: PackedVector2Array) -> PackedFloat32Array:
	var n: int = pts.size()
	var cum := PackedFloat32Array()
	cum.resize(maxi(1, n))
	cum[0] = 0.0
	var acc: float = 0.0
	for i in range(n - 1):
		acc += pts[i].distance_to(pts[i + 1])
		cum[i + 1] = acc
	return cum

static func sample_road_pose(
	pts: PackedVector2Array,
	cum_len: PackedFloat32Array,
	total_len: float,
	one_way: int,
	forward: bool,
	s_px: float,
	lane_offset_float: float,
	total_lanes_dir: int,
	left_hand_traffic: bool
) -> Dictionary:
	var n: int = pts.size()
	if n < 2:
		var p0: Vector2 = pts[0] if n == 1 else Vector2.ZERO
		return {"pos": p0, "heading": 0.0, "right": Vector2(0.0, 1.0)}

	var clamped_s: float = clampf(s_px, 0.0, total_len)
	var target_s: float = clamped_s if forward else maxf(0.0, total_len - clamped_s)

	# Binary search on precomputed cumulative segment lengths
	var idx: int = cum_len.bsearch(target_s)
	var seg_idx: int = clampi(idx - 1, 0, n - 2)
	var s0: float = cum_len[seg_idx]
	var seg_d: float = maxf(0.001, cum_len[seg_idx + 1] - s0)
	var local_t: float = clampf((target_s - s0) / seg_d, 0.0, 1.0)

	var a: Vector2 = pts[seg_idx]
	var b: Vector2 = pts[seg_idx + 1]
	var pos: Vector2 = a.lerp(b, local_t)

	var dir: Vector2 = (b - a) if forward else (a - b)
	var heading: float = atan2(dir.y, dir.x)
	var right_vec := Vector2(-sin(heading), cos(heading))

	var lane_width: float = 4.8
	var lateral: float = 0.0
	if one_way != 0:
		var center_idx: float = float(total_lanes_dir - 1) * 0.5
		var signed_idx: float = (center_idx - lane_offset_float) if left_hand_traffic else (lane_offset_float - center_idx)
		lateral = signed_idx * lane_width
	else:
		var inner_idx: float = float(total_lanes_dir - 1) - lane_offset_float
		var dist_center: float = (0.55 + inner_idx) * lane_width
		lateral = -dist_center if left_hand_traffic else dist_center

	pos += right_vec * lateral
	return {"pos": pos, "heading": heading, "right": right_vec}

static func point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var v: Vector2 = b - a
	var l2: float = v.length_squared()
	if l2 < 0.00001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(v) / l2, 0.0, 1.0)
	return p.distance_to(a + v * t)

static func hit_test_facility(facilities: Array, unlocked_regions: Dictionary, world_p: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = radius
	for f in facilities:
		if not unlocked_regions.has(int(f["regionIndex"])):
			continue
		var fp: Vector2 = f["pos"]
		var d: float = world_p.distance_to(fp)
		if d < best_d:
			best_d = d
			best = f
	return best

static func hit_test_junction(junctions: Array, unlocked_regions: Dictionary, world_p: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = radius
	for j in junctions:
		if not unlocked_regions.has(int(j["regionIndex"])):
			continue
		var jp: Vector2 = j["pos"]
		var d: float = world_p.distance_to(jp)
		if d < best_d:
			best_d = d
			best = j
	return best

static func hit_test_road(roads: Array, unlocked_regions: Dictionary, world_p: Vector2, radius: float, include_offers: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = radius
	for r in roads:
		if not unlocked_regions.has(int(r["regionIndex"])):
			continue
		if not bool(r["isBuilt"]) and not include_offers:
			continue
		var pts: PackedVector2Array = r["pts"]
		for i in range(pts.size() - 1):
			var d: float = point_to_segment_dist(world_p, pts[i], pts[i + 1])
			if d < best_d:
				best_d = d
				best = r
	return best
