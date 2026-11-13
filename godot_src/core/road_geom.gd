class_name RoadGeom
extends RefCounted

## Authentic Incremental Traffic v1.4.1 Road & Lane Geometry Engine
## Reconstructed from `systems/const.gd`, `content/roads/lane_geometry.gd`,
## `content/roads/road_network.gd`, `content/roads/road_surface.gd`, and `content/city/road_bed.gd`,
## scaled by `UNIT_SCALE = 0.20` for real-world Karesidenan Madiun WGS84 coordinates.

const UNIT_SCALE: float = 0.20

# Exact CONST proportions (desktop * 0.20: 33.6->6.72, 19.2->3.84, 30.0->6.00)
const LANE_WIDTH: float = 6.72
const LANE_SEPARATION: float = 3.84
const LANE_SPACING: float = 6.00
const MAX_LANES: int = 4

# Exact RoadBed ring widths (desktop * 0.20: 8.8->1.76, 2.0->0.40, 6.0->1.20)
const SIDEWALK: float = 1.76
const CURB: float = 0.40
const SHADOW_BAND: float = 1.20

# Exact LaneMarkings & Pocket constants (desktop * 0.20)
const LINE_WIDTH: float = 0.44
const STOP_LINE_WIDTH: float = 0.90
const DASH: float = 3.20
const GAP: float = 2.80
const CENTER_SOLID_DIST: float = 10.0
const LANE_SOLID_DIST: float = 14.0
const ARROW_OFFSET: float = 8.4
const POCKET_SIZES: Array[float] = [26.0, 52.0, 82.0]
const POCKET_SPLIT: float = 18.0
const LANE_TAPER: float = 9.0
const MEDIAN_ISLAND_HALF_W: float = 1.15


## Cubic Hermite smoothstep ramp from original `LaneGeometry.ramp(a, b, x)`
static func ramp(a: float, b: float, x: float) -> float:
	if absf(b - a) < 0.0001:
		return 1.0 if x >= b else 0.0
	var t: float = clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Circular-arc cubic Bezier handle factor `(4/3) * tan(angle / 4)` from `LaneGeometry.arc_bezier_factor`
static func arc_bezier_factor(angle: float) -> float:
	var clamped: float = clampf(angle, -PI * 0.92, PI * 0.92)
	return (4.0 / 3.0) * tan(clamped * 0.25)


## Smooth C1 cubic Bezier connector / arc from `LaneGeometry.bend`
static func bend(
	start: Vector2,
	dir_a: Vector2,
	end: Vector2,
	dir_b: Vector2,
	step: float = 1.8,
	arc: bool = false
) -> PackedVector2Array:
	var out := PackedVector2Array()
	var chord: float = start.distance_to(end)
	if chord < 0.12:
		out.append(start)
		if chord > 0.02:
			out.append(end)
		return out

	var ua: Vector2 = dir_a.normalized() if dir_a.length_squared() > 0.0001 else ((end - start) / chord)
	var ub: Vector2 = dir_b.normalized() if dir_b.length_squared() > 0.0001 else ua
	var turn_ang: float = absf(ua.angle_to(ub))
	var handle: float
	if arc:
		if turn_ang > 0.08:
			var radius: float = chord / maxf(0.06, 2.0 * sin(turn_ang * 0.5))
			handle = clampf(radius * absf(arc_bezier_factor(turn_ang)), chord * 0.24, chord * 0.72)
		else:
			handle = chord * 0.35
	else:
		var factor: float = 0.30 if turn_ang > deg_to_rad(62.0) else 0.40
		handle = clampf(chord * factor, 1.4, 22.0)

	var c1: Vector2 = start + ua * handle
	var c2: Vector2 = end - ub * handle
	var n_steps: int = clampi(int(ceil(chord / maxf(0.6, step))), 4, 20)
	for k in range(n_steps + 1):
		var t: float = float(k) / float(n_steps)
		var bp: Vector2 = _cubic_bezier(start, c1, c2, end, t)
		if out.is_empty() or out[out.size() - 1].distance_to(bp) > 0.06:
			out.append(bp)
	return out


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


static func get_effective_approach_lanes(r: Dictionary, forward_dir: bool) -> int:
	var ow: int = int(r.get("oneWay", 0))
	if forward_dir and ow < 0:
		return 0
	if (not forward_dir) and ow > 0:
		return 0
	var main_l: int = clampi(int(r.get("lanesForward" if forward_dir else "lanesBackward", 1)), 1, MAX_LANES)
	var pk_lvl: int = clampi(int(r.get("pocketLevel", 0)), 0, 3)
	var key := "approachLanesForward" if forward_dir else "approachLanesBackward"
	var app_l: int = int(r.get(key, 0))
	if app_l <= 0:
		app_l = mini(MAX_LANES, main_l + (1 if pk_lvl > 0 else 0))
	else:
		app_l = clampi(app_l, main_l, MAX_LANES)
		if pk_lvl > 0 and app_l == main_l:
			app_l = mini(MAX_LANES, main_l + 1)
	return app_l


static func get_effective_pocket_size(r: Dictionary) -> int:
	if r.has("pocketSize"):
		return clampi(int(r["pocketSize"]), 0, 2)
	var pk_lvl: int = clampi(int(r.get("pocketLevel", 0)), 0, 3)
	if pk_lvl > 0:
		return clampi(pk_lvl - 1, 0, 2)
	return 1


## Asphalt width of the main road section (excluding curb & sidewalk, which RoadBed adds)
static func get_road_width(r: Dictionary) -> float:
	var ow: int = int(r.get("oneWay", 0))
	var lf: int = clampi(int(r.get("lanesForward", 1)), 1, MAX_LANES)
	var lb: int = clampi(int(r.get("lanesBackward", 1)), 1, MAX_LANES)
	if ow != 0:
		var lanes_ow: int = lf if ow > 0 else lb
		return LANE_WIDTH + float(lanes_ow - 1) * LANE_SPACING
	return 2.0 * LANE_SEPARATION + LANE_WIDTH + float(lf + lb - 2) * LANE_SPACING


## Signed lateral offset along right_vec `(-dir.y, dir.x)` of travel direction.
## SimEngine convention: `lane_offset_float = 0` is outer/kerbside lane, `total_lanes_dir - 1` is inner/median lane.
static func get_lane_lateral_offset(
	one_way: int,
	lane_offset_float: float,
	total_lanes_dir: int,
	opp_lanes_dir: int,
	left_hand_traffic: bool
) -> float:
	var n_dir: int = maxi(1, total_lanes_dir)
	var side_sign: float = -1.0 if left_hand_traffic else 1.0
	var inner_k: float = float(n_dir - 1) - lane_offset_float
	if one_way != 0:
		var center_k: float = float(n_dir - 1) * 0.5
		return side_sign * (inner_k - center_k) * LANE_SPACING
	var n_opp: int = maxi(1, opp_lanes_dir)
	var asym_shift: float = float(n_dir - n_opp) * 0.5 * LANE_SPACING
	var dist_from_center: float = LANE_SEPARATION + inner_k * LANE_SPACING - asym_shift
	return side_sign * dist_from_center


static func sample_polyline_raw(pts: PackedVector2Array, cum_len: PackedFloat32Array, s_px: float) -> Dictionary:
	var n: int = pts.size()
	if n == 0:
		return {"pos": Vector2.ZERO, "dir": Vector2.RIGHT, "right": Vector2.DOWN}
	if n == 1:
		return {"pos": pts[0], "dir": Vector2.RIGHT, "right": Vector2.DOWN}
	var total_len: float = cum_len[n - 1]
	var target_s: float = clampf(s_px, 0.0, total_len)
	var idx: int = cum_len.bsearch(target_s)
	var seg_idx: int = clampi(idx - 1, 0, n - 2)
	if idx == 0:
		seg_idx = 0
	var s0: float = cum_len[seg_idx]
	var seg_d: float = maxf(0.0001, cum_len[seg_idx + 1] - s0)
	var local_t: float = clampf((target_s - s0) / seg_d, 0.0, 1.0)
	var a: Vector2 = pts[seg_idx]
	var b: Vector2 = pts[seg_idx + 1]
	var dir: Vector2 = (b - a).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	return {
		"pos": a.lerp(b, local_t),
		"dir": dir,
		"right": Vector2(-dir.y, dir.x)
	}


static func slice_polyline(pts: PackedVector2Array, cum_len: PackedFloat32Array, s_start: float, s_end: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = pts.size()
	if n < 2 or cum_len.size() != n:
		return out
	var total_len: float = cum_len[n - 1]
	var a_s: float = clampf(s_start, 0.0, total_len)
	var b_s: float = clampf(s_end, 0.0, total_len)
	if b_s - a_s < 0.20:
		return out
	var p_start: Vector2 = sample_polyline_raw(pts, cum_len, a_s)["pos"]
	var p_end: Vector2 = sample_polyline_raw(pts, cum_len, b_s)["pos"]
	out.append(p_start)
	for i in range(1, n - 1):
		var d_i: float = cum_len[i]
		if d_i > a_s + 0.12 and d_i < b_s - 0.12:
			out.append(pts[i])
	if out[out.size() - 1].distance_to(p_end) > 0.06:
		out.append(p_end)
	return out


static func sample_road_pose(
	pts: PackedVector2Array,
	cum_len: PackedFloat32Array,
	total_len: float,
	one_way: int,
	forward: bool,
	s_px: float,
	lane_offset_float: float,
	total_lanes_dir: int,
	left_hand_traffic: bool,
	opp_lanes_dir: int = -1
) -> Dictionary:
	var n: int = pts.size()
	if n < 2:
		var p0: Vector2 = pts[0] if n == 1 else Vector2.ZERO
		return {"pos": p0, "heading": 0.0, "right": Vector2(0.0, 1.0)}

	var clamped_s: float = clampf(s_px, 0.0, total_len)
	var target_s: float = clamped_s if forward else maxf(0.0, total_len - clamped_s)
	var raw: Dictionary = sample_polyline_raw(pts, cum_len, target_s)
	var dir: Vector2 = raw["dir"] if forward else -(raw["dir"] as Vector2)
	var heading: float = atan2(dir.y, dir.x)
	var right_vec := Vector2(-dir.y, dir.x)
	var opp_l: int = total_lanes_dir if opp_lanes_dir < 0 else opp_lanes_dir
	var lateral: float = get_lane_lateral_offset(one_way, lane_offset_float, total_lanes_dir, opp_l, left_hand_traffic)
	var pos: Vector2 = (raw["pos"] as Vector2) + right_vec * lateral
	return {"pos": pos, "heading": heading, "right": right_vec}


## Build full-length trajectory polyline for a vehicle on `edge` (supporting explicit `lanesFwd` / `lanesBwd` + turn pockets!)
static func build_edge_lane_polyline(
	edge: Dictionary,
	forward: bool,
	sim_lane_idx: int,
	use_pocket: bool,
	s_begin: float,
	s_finish: float,
	left_hand_traffic: bool
) -> PackedVector2Array:
	var lanes_arr: Array = edge.get("lanesFwd" if forward else "lanesBwd", [])
	var main_lanes: int = maxi(1, int(edge["lanesForward"]) if forward else int(edge["lanesBackward"]))
	var opp_lanes: int = maxi(1, int(edge["lanesBackward"]) if forward else int(edge["lanesForward"]))
	var clamped_main: int = clampi(sim_lane_idx, 0, main_lanes - 1)
	var inner_k: int = (main_lanes - 1) - clamped_main

	if not lanes_arr.is_empty() and inner_k >= 0 and inner_k < lanes_arr.size():
		if use_pocket and lanes_arr.size() > main_lanes and clamped_main == 0:
			var main_d: Dictionary = lanes_arr[main_lanes - 1]
			var pk_d: Dictionary = lanes_arr[lanes_arr.size() - 1]
			var pk_pts: PackedVector2Array = pk_d["pts"]
			var main_pts: PackedVector2Array = main_d["pts"]
			var main_cum: PackedFloat32Array = main_d["cum_len"]
			if pk_pts.size() >= 2 and main_pts.size() >= 2:
				var split_dist: float = maxf(0.0, main_cum[main_cum.size() - 1] - float(pk_d["cum_len"][pk_d["cum_len"].size() - 1]))
				var out := PackedVector2Array()
				if split_dist > 0.6:
					var pre: PackedVector2Array = slice_polyline(main_pts, main_cum, 0.0, split_dist)
					for p in pre:
						out.append(p)
				for p in pk_pts:
					if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.08:
						out.append(p)
				if out.size() >= 2:
					return out
		var ld: Dictionary = lanes_arr[inner_k]
		var lpts: PackedVector2Array = ld["pts"]
		if lpts.size() >= 2:
			return lpts.duplicate()

	# Fallback analytical sampling (e.g. first/last facility access leg with shortened trim)
	var stitched := PackedVector2Array()
	var rlen: float = float(edge["lengthPx"])
	var sample_count: int = maxi(4, int(ceil((s_finish - s_begin) / 5.5)))
	for i in range(sample_count + 1):
		var s_val: float = lerpf(s_begin, s_finish, float(i) / float(sample_count))
		var rp: Dictionary = sample_road_pose(
			edge["pts"], edge["cum_len"], rlen, int(edge["oneWay"]),
			forward, s_val, float(clamped_main), main_lanes, left_hand_traffic, opp_lanes
		)
		var vp: Vector2 = rp["pos"]
		if stitched.is_empty() or stitched[stitched.size() - 1].distance_to(vp) > 0.08:
			stitched.append(vp)
	return stitched


static func sample_stitched_pose(pts: PackedVector2Array, cum_len: PackedFloat32Array, s_px: float) -> Dictionary:
	var raw: Dictionary = sample_polyline_raw(pts, cum_len, s_px)
	var d: Vector2 = raw["dir"]
	return {"pos": raw["pos"], "heading": atan2(d.y, d.x)}


static func _intersect_rays_2d(p1: Vector2, d1: Vector2, p2: Vector2, d2: Vector2) -> Dictionary:
	var denom: float = d1.x * d2.y - d1.y * d2.x
	if absf(denom) < 0.12:
		return {"ok": false}
	var diff: Vector2 = p2 - p1
	var t1: float = (diff.x * d2.y - diff.y * d2.x) / denom
	var t2: float = (diff.x * d1.y - diff.y * d1.x) / denom
	return {"ok": true, "t1": t1, "t2": t2, "pos": p1 + d1 * t1}


## Vertex-smoothed lateral offset along road centerline so curved OSM polyline vertices never pinch or fold
static func _sample_smoothed_frame(pts: PackedVector2Array, cum: PackedFloat32Array, rlen: float, s: float) -> Dictionary:
	var raw_c: Dictionary = sample_polyline_raw(pts, cum, s)
	if rlen < 4.0:
		return raw_c
	var eps: float = minf(2.2, rlen * 0.15)
	var d_a: Vector2 = sample_polyline_raw(pts, cum, maxf(0.0, s - eps))["dir"]
	var d_b: Vector2 = sample_polyline_raw(pts, cum, minf(rlen, s + eps))["dir"]
	var d_avg: Vector2 = (d_a + d_b + (raw_c["dir"] as Vector2) * 2.0).normalized()
	if d_avg.length_squared() < 0.001:
		d_avg = raw_c["dir"]
	return {
		"pos": raw_c["pos"],
		"dir": d_avg,
		"right": Vector2(-d_avg.y, d_avg.x)
	}


static func _build_station_samples(pts: PackedVector2Array, cum: PackedFloat32Array, s0: float, s1: float, fine_step: float = 2.6) -> PackedFloat32Array:
	var raw_s: Array[float] = [s0, s1]
	for i in range(1, pts.size() - 1):
		var sv: float = cum[i]
		if sv > s0 + 0.25 and sv < s1 - 0.25:
			raw_s.append(sv)
	var span: float = s1 - s0
	var n_sub: int = maxi(2, int(ceil(span / maxf(1.2, fine_step))))
	for k in range(1, n_sub):
		raw_s.append(lerpf(s0, s1, float(k) / float(n_sub)))
	raw_s.sort()
	var dedup := PackedFloat32Array()
	for sv in raw_s:
		if dedup.is_empty() or absf(sv - dedup[dedup.size() - 1]) > 0.22:
			dedup.append(sv)
	if dedup.size() >= 2:
		dedup[dedup.size() - 1] = s1
	elif dedup.size() == 1:
		dedup.append(s1)
	return dedup


## Authentic `RoadSurface.plaza_polygon` builder using exact asymmetric `[lo_ext, hi_ext]` arm lane edges!
static func _build_plaza_polygon(jp: Vector2, arms: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var n: int = arms.size()
	if n < 2:
		return poly

	var max_trim: float = 12.0
	for a in arms:
		max_trim = maxf(max_trim, float(a["trim"]))

	var corner_crossed: Array[bool] = []
	var corner_crotch: Array[Vector2] = []
	corner_crossed.resize(n)
	corner_crotch.resize(n)

	for i in range(n):
		var a_cur: Dictionary = arms[i]
		var a_nxt: Dictionary = arms[(i + 1) % n]
		var p_cur: Vector2 = a_cur["throat_pos"]
		var u_cur: Vector2 = a_cur["throat_out_dir"]
		var rn_cur := Vector2(-u_cur.y, u_cur.x)
		var right_cur: Vector2 = a_cur.get("right_corner", p_cur + rn_cur * float(a_cur["hi_ext"]))

		var p_nxt: Vector2 = a_nxt["throat_pos"]
		var u_nxt: Vector2 = a_nxt["throat_out_dir"]
		var rn_nxt := Vector2(-u_nxt.y, u_nxt.x)
		var left_nxt: Vector2 = a_nxt.get("left_corner", p_nxt + rn_nxt * float(a_nxt["lo_ext"]))

		var delta_ang: float = fposmod(float(a_nxt["angle"]) - float(a_cur["angle"]), TAU)
		var ang_r: float = atan2((right_cur - jp).y, (right_cur - jp).x)
		var ang_ln: float = atan2((left_nxt - jp).y, (left_nxt - jp).x)
		var ccw_gap: float = fposmod(ang_ln - ang_r, TAU)

		var seg_out: Variant = null
		if delta_ang < deg_to_rad(115.0):
			seg_out = Geometry2D.segment_intersects_segment(
				right_cur - u_cur * 1.0, right_cur + u_cur * 34.0,
				left_nxt - u_nxt * 1.0, left_nxt + u_nxt * 34.0
			)

		if seg_out != null or (delta_ang < deg_to_rad(115.0) and ccw_gap > PI):
			corner_crossed[i] = true
			if seg_out != null:
				corner_crotch[i] = seg_out as Vector2
			else:
				var hit_c: Dictionary = _intersect_rays_2d(right_cur, u_cur, left_nxt, u_nxt)
				var crotch: Vector2 = 0.5 * (right_cur + left_nxt)
				if bool(hit_c.get("ok", false)) and float(hit_c["t1"]) >= -2.0:
					var hp: Vector2 = hit_c["pos"]
					if hp.distance_to(jp) <= max_trim * 2.2:
						crotch = hp
				corner_crotch[i] = crotch
		else:
			corner_crossed[i] = false
			corner_crotch[i] = Vector2.ZERO

	for i in range(n):
		var prev_i: int = (i - 1 + n) % n
		var a_cur: Dictionary = arms[i]
		var a_nxt: Dictionary = arms[(i + 1) % n]
		var p_cur: Vector2 = a_cur["throat_pos"]
		var u_cur: Vector2 = a_cur["throat_out_dir"]
		var rn_cur := Vector2(-u_cur.y, u_cur.x)

		var p_nxt: Vector2 = a_nxt["throat_pos"]
		var u_nxt: Vector2 = a_nxt["throat_out_dir"]
		var rn_nxt := Vector2(-u_nxt.y, u_nxt.x)

		var left_cur: Vector2 = a_cur.get("left_corner", p_cur + rn_cur * float(a_cur["lo_ext"]))
		var right_cur: Vector2 = a_cur.get("right_corner", p_cur + rn_cur * float(a_cur["hi_ext"]))
		var left_nxt: Vector2 = a_nxt.get("left_corner", p_nxt + rn_nxt * float(a_nxt["lo_ext"]))

		if not corner_crossed[prev_i]:
			if poly.is_empty() or poly[poly.size() - 1].distance_to(left_cur) > 0.12:
				poly.append(left_cur)

		if corner_crossed[i]:
			var vc: Vector2 = corner_crotch[i]
			if poly.is_empty() or poly[poly.size() - 1].distance_to(vc) > 0.12:
				poly.append(vc)
			continue

		if poly.is_empty() or poly[poly.size() - 1].distance_to(right_cur) > 0.12:
			poly.append(right_cur)

		var delta_ang: float = fposmod(float(a_nxt["angle"]) - float(a_cur["angle"]), TAU)
		if delta_ang >= deg_to_rad(145.0):
			# Straight pass-through, 2-arm width taper / outer elbow, or reflex T-junction back: circular-arc cubic Bezier!
			var arc_pts: PackedVector2Array = bend(right_cur, -u_cur, left_nxt, u_nxt, 1.8, true)
			for k in range(1, arc_pts.size() - 1):
				if poly[poly.size() - 1].distance_to(arc_pts[k]) > 0.12:
					poly.append(arc_pts[k])
		else:
			# 8-step quadratic Bezier corner fillet (`< 145 deg`)
			var hit: Dictionary = _intersect_rays_2d(right_cur, -u_cur, left_nxt, -u_nxt)
			var ctrl_pt: Vector2 = 0.5 * (right_cur + left_nxt)
			if bool(hit.get("ok", false)) and float(hit["t1"]) >= -0.4 and float(hit["t2"]) >= -0.4:
				var t1_c: float = clampf(float(hit["t1"]), 0.0, float(a_cur["trim"]) * 0.95)
				ctrl_pt = right_cur - u_cur * t1_c
			var fillet_steps: int = 8
			for k in range(1, fillet_steps):
				var t: float = float(k) / float(fillet_steps)
				var omt: float = 1.0 - t
				var bp: Vector2 = (omt * omt) * right_cur + (2.0 * omt * t) * ctrl_pt + (t * t) * left_nxt
				if poly[poly.size() - 1].distance_to(bp) > 0.12:
					poly.append(bp)

	return poly


static func _arm_throat_extents_for_counts(
	ow: int,
	is_start: bool,
	lf: int,
	lb: int,
	arr_lanes: int,
	island_hw: float,
	left_hand_traffic: bool
) -> Vector2:
	var side_sign: float = -1.0 if left_hand_traffic else 1.0
	var min_rn: float = 1e9
	var max_rn: float = -1e9
	var half_lw: float = LANE_WIDTH * 0.5

	if ow != 0:
		var n_ow: int = arr_lanes if ((ow > 0 and not is_start) or (ow < 0 and is_start)) else (lf if ow > 0 else lb)
		var main_ow: int = lf if ow > 0 else lb
		var center_k: float = float(main_ow - 1) * 0.5
		for k in range(maxi(1, n_ow)):
			# Along forward right_vec:
			var lat_fwd: float = side_sign * (float(k) - center_k) * LANE_SPACING
			if ow < 0:
				lat_fwd = -lat_fwd
			var rn_coord: float = lat_fwd if is_start else -lat_fwd
			min_rn = minf(min_rn, rn_coord - half_lw)
			max_rn = maxf(max_rn, rn_coord + half_lw)
		return Vector2(min_rn, max_rn)

	var asym: float = float(lf - lb) * 0.5 * LANE_SPACING
	var div_shift: float = -side_sign * asym
	var n_f_here: int = lf if is_start else maxi(lf, arr_lanes)
	var n_b_here: int = maxi(lb, arr_lanes) if is_start else lb

	for kf in range(n_f_here):
		var lat_f: float = div_shift + side_sign * (island_hw + LANE_SEPARATION + float(kf) * LANE_SPACING)
		var rn_f: float = lat_f if is_start else -lat_f
		min_rn = minf(min_rn, rn_f - half_lw)
		max_rn = maxf(max_rn, rn_f + half_lw)

	for kb in range(n_b_here):
		var lat_b: float = div_shift - side_sign * (island_hw + LANE_SEPARATION + float(kb) * LANE_SPACING)
		var rn_b: float = lat_b if is_start else -lat_b
		min_rn = minf(min_rn, rn_b - half_lw)
		max_rn = maxf(max_rn, rn_b + half_lw)

	return Vector2(min_rn, max_rn)


static func compute_network_junction_geometry(
	junctions: Array,
	roads: Array,
	road_map: Dictionary,
	left_hand_traffic: bool = true
) -> void:
	var jmap_local := {}
	for j in junctions:
		jmap_local[String(j["id"])] = j

	for r in roads:
		r["trimStart"] = 0.0
		r["trimEnd"] = 0.0
		r["widthPx"] = get_road_width(r)
		r["lanesFwd"] = []
		r["lanesBwd"] = []
		r["centerLine"] = PackedVector2Array()
		r["centerSingleZones"] = []
		r["medianZones"] = []
		r["medianShifted"] = false

	# === STAGE 1: Compute Junction Setbacks (Trims), Allowed Turn Flags & Roundabout Radii ===
	for j in junctions:
		var jid := String(j["id"])
		var jp: Vector2 = j["pos"]
		var ctrl := String(j.get("control", "none"))
		var raw_arms: Array = []

		for eid_v in j["connectedEdgeIds"]:
			var eid := String(eid_v)
			if not road_map.has(eid):
				continue
			var r: Dictionary = road_map[eid]
			if not bool(r["isBuilt"]):
				continue
			var pts: PackedVector2Array = r["pts"]
			var cum: PackedFloat32Array = r["cum_len"]
			var rlen: float = float(r["lengthPx"])
			var is_start: bool = String(r["from"]) == jid
			var ref_d: float = minf(18.0, rlen * 0.32)
			var s_ref: float = ref_d if is_start else maxf(0.0, rlen - ref_d)
			var p_ref: Vector2 = sample_polyline_raw(pts, cum, s_ref)["pos"]
			var out_dir: Vector2 = (p_ref - jp).normalized()
			if out_dir.length_squared() < 0.001:
				out_dir = Vector2.RIGHT
			var ow: int = int(r["oneWay"])
			var closed: bool = bool(r["closed"])
			var can_enter: bool = (not closed) and (ow == 0 or (ow == 1 and not is_start) or (ow == -1 and is_start))
			var can_exit: bool = (not closed) and (ow == 0 or (ow == 1 and is_start) or (ow == -1 and not is_start))
			var rw: float = float(r["widthPx"])
			raw_arms.append({
				"edge_id": eid,
				"is_start": is_start,
				"angle": atan2(out_dir.y, out_dir.x),
				"out_dir": out_dir,
				"road_w": rw,
				"hw": rw * 0.5,
				"rlen": rlen,
				"can_enter": can_enter,
				"can_exit": can_exit,
				"closed": closed,
				"one_way": ow,
				"trim": 6.0,
				"lo_ext": -rw * 0.5,
				"hi_ext": rw * 0.5
			})

		raw_arms.sort_custom(func(a, b): return float(a["angle"]) < float(b["angle"]))
		var n: int = raw_arms.size()
		if n == 0:
			j["geom"] = {"kind": "empty", "arms": []}
			continue

		var multi_junc: bool = (n >= 3 or ctrl == "lights") and ctrl != "roundabout" and ctrl != "roundabout2"

		# Update exact asymmetric throat extents `[lo_ext, hi_ext]` per arm
		for a in raw_arms:
			var r_e: Dictionary = road_map[String(a["edge_id"])]
			var is_st: bool = bool(a["is_start"])
			var ow_e: int = int(r_e["oneWay"])
			var lf_e: int = clampi(int(r_e["lanesForward"]), 1, MAX_LANES)
			var lb_e: int = clampi(int(r_e["lanesBackward"]), 1, MAX_LANES)
			var arr_e: int = get_effective_approach_lanes(r_e, not is_st) if (multi_junc and float(a["rlen"]) >= 36.0 and not bool(a["closed"])) else (lb_e if is_st else lf_e)
			var has_isl: bool = (ow_e == 0 and not bool(a["closed"]) and float(a["rlen"]) >= 46.0 and ctrl == "lights" and (lf_e + lb_e >= 4 or arr_e > (lb_e if is_st else lf_e) or String(r_e["roadClass"]) == "toll"))
			var isl_hw: float = MEDIAN_ISLAND_HALF_W if has_isl else 0.0
			var exts: Vector2 = _arm_throat_extents_for_counts(ow_e, is_st, lf_e, lb_e, arr_e, isl_hw, left_hand_traffic)
			a["lo_ext"] = exts.x
			a["hi_ext"] = exts.y
			a["hw"] = maxf(absf(exts.x), absf(exts.y))
			a["road_w"] = exts.y - exts.x
			a["approach_lanes"] = arr_e
			a["has_median_island"] = has_isl

		# Allowed turn flags per arm
		for i in range(n):
			var a_in: Dictionary = raw_arms[i]
			var v_in: Vector2 = -(a_in["out_dir"] as Vector2)
			var has_l := false
			var has_s := false
			var has_r := false
			for k in range(n):
				if k == i:
					continue
				var a_out: Dictionary = raw_arms[k]
				if not bool(a_out["can_exit"]):
					continue
				var v_out: Vector2 = a_out["out_dir"]
				var tang: float = atan2(v_in.x * v_out.y - v_in.y * v_out.x, v_in.dot(v_out))
				if absf(tang) <= deg_to_rad(38.0):
					has_s = true
				elif tang > 0.0:
					has_r = true
				else:
					has_l = true
			if not has_l and not has_s and not has_r:
				has_s = true
			a_in["turns"] = {"left": has_l, "straight": has_s, "right": has_r}

		if (ctrl == "roundabout" or ctrl == "roundabout2") and n >= 2:
			var max_hw: float = 7.2
			var min_len: float = 9999.0
			for a in raw_arms:
				max_hw = maxf(max_hw, float(a["hw"]))
				min_len = minf(min_len, float(a["rlen"]))
			var r_island: float
			var r_outer: float
			if ctrl == "roundabout2":
				r_island = clampf(maxf(10.0, max_hw * 0.96), 7.6, maxf(8.4, min_len * 0.20))
				r_outer = r_island + LANE_WIDTH + LANE_SPACING + 1.1
			else:
				r_island = clampf(maxf(8.6, max_hw * 0.88), 6.6, maxf(7.2, min_len * 0.19))
				r_outer = r_island + LANE_WIDTH * 1.32

			for a in raw_arms:
				var r_edge: Dictionary = road_map[String(a["edge_id"])]
				var tr: float = clampf(r_outer + 5.6, r_outer + 2.0, maxf(r_outer + 2.2, float(a["rlen"]) * 0.45))
				a["trim"] = tr
				var s_th: float = tr if bool(a["is_start"]) else maxf(0.0, float(a["rlen"]) - tr)
				var raw_th: Dictionary = _sample_smoothed_frame(r_edge["pts"], r_edge["cum_len"], float(a["rlen"]), s_th)
				var u_out: Vector2 = raw_th["dir"] if bool(a["is_start"]) else -(raw_th["dir"] as Vector2)
				if (raw_th["pos"] as Vector2 - jp).dot(u_out) < 0.0:
					u_out = -u_out
				a["throat_pos"] = raw_th["pos"]
				a["throat_out_dir"] = u_out
				if bool(a["is_start"]):
					r_edge["trimStart"] = maxf(float(r_edge["trimStart"]), tr)
				else:
					r_edge["trimEnd"] = maxf(float(r_edge["trimEnd"]), tr)

			j["geom"] = {
				"kind": ctrl,
				"r_outer": r_outer,
				"r_island": r_island,
				"arms": raw_arms,
				"lht": left_hand_traffic
			}
			continue

		if n == 1:
			var a0: Dictionary = raw_arms[0]
			var r0: Dictionary = road_map[String(a0["edge_id"])]
			var tr0: float = minf(5.5, float(a0["rlen"]) * 0.20)
			a0["trim"] = tr0
			var s0_th: float = tr0 if bool(a0["is_start"]) else maxf(0.0, float(a0["rlen"]) - tr0)
			var raw0: Dictionary = _sample_smoothed_frame(r0["pts"], r0["cum_len"], float(a0["rlen"]), s0_th)
			var u0: Vector2 = raw0["dir"] if bool(a0["is_start"]) else -(raw0["dir"] as Vector2)
			a0["throat_pos"] = raw0["pos"]
			a0["throat_out_dir"] = u0
			if bool(a0["is_start"]):
				r0["trimStart"] = maxf(float(r0["trimStart"]), tr0)
			else:
				r0["trimEnd"] = maxf(float(r0["trimEnd"]), tr0)
			j["geom"] = {"kind": "culdesac", "arms": raw_arms, "radius": float(a0["hw"])}
			continue

		var r_fillet: float = 5.6 if multi_junc else 3.2
		var req_trims: Array[float] = []
		req_trims.resize(n)
		for i in range(n):
			req_trims[i] = float(raw_arms[i]["hw"]) + (4.0 if multi_junc else 2.0)

		for i in range(n):
			var i_nxt: int = (i + 1) % n
			var w_a: float = maxf(3.0, float(raw_arms[i]["hi_ext"]))
			var w_b: float = maxf(3.0, absf(float(raw_arms[i_nxt]["lo_ext"])))
			var delta: float = fposmod(float(raw_arms[i_nxt]["angle"]) - float(raw_arms[i]["angle"]), TAU)
			if delta < deg_to_rad(154.0):
				var clamped_d: float = clampf(delta, deg_to_rad(25.0), deg_to_rad(154.0))
				var sin_d: float = sin(clamped_d)
				var cos_d: float = cos(clamped_d)
				var fil_tan: float = r_fillet * tan((PI - clamped_d) * 0.5)
				var ta: float = (w_b + w_a * cos_d) / sin_d + fil_tan
				var tb: float = (w_a + w_b * cos_d) / sin_d + fil_tan
				req_trims[i] = maxf(req_trims[i], ta)
				req_trims[i_nxt] = maxf(req_trims[i_nxt], tb)
			else:
				var flat_t: float = maxf(w_a, w_b) + (4.2 if multi_junc else 2.2)
				req_trims[i] = maxf(req_trims[i], flat_t)
				req_trims[i_nxt] = maxf(req_trims[i_nxt], flat_t)

		for i in range(n):
			var a: Dictionary = raw_arms[i]
			var r_edge: Dictionary = road_map[String(a["edge_id"])]
			var min_t: float = maxf(float(a["hw"]) + 2.6, 8.8 if multi_junc else 5.2)
			var max_t: float = minf(float(a["rlen"]) * 0.36, 32.0)
			var tr: float = clampf(req_trims[i], minf(min_t, max_t), max_t)
			a["trim"] = tr
			var s_th: float = tr if bool(a["is_start"]) else maxf(0.0, float(a["rlen"]) - tr)
			var raw_th: Dictionary = _sample_smoothed_frame(r_edge["pts"], r_edge["cum_len"], float(a["rlen"]), s_th)
			var u_out: Vector2 = raw_th["dir"] if bool(a["is_start"]) else -(raw_th["dir"] as Vector2)
			if (raw_th["pos"] as Vector2 - jp).dot(u_out) < 0.0:
				u_out = -u_out
			a["throat_pos"] = raw_th["pos"]
			a["throat_out_dir"] = u_out
			if bool(a["is_start"]):
				r_edge["trimStart"] = maxf(float(r_edge["trimStart"]), tr)
			else:
				r_edge["trimEnd"] = maxf(float(r_edge["trimEnd"]), tr)

		j["geom"] = {
			"kind": "standard",
			"arms": raw_arms
		}

	# === STAGE 2: Build Explicit Per-Lane Polylines, Turn Pockets & Median Islands on Built Roads ===
	var side_sign: float = -1.0 if left_hand_traffic else 1.0
	for r in roads:
		if not bool(r["isBuilt"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		var cum: PackedFloat32Array = r["cum_len"]
		var rlen: float = float(r["lengthPx"])
		var s0: float = clampf(float(r["trimStart"]), 0.0, rlen * 0.46)
		var s1: float = clampf(rlen - float(r["trimEnd"]), s0 + 1.5, rlen)
		var span: float = s1 - s0
		if span < 1.2:
			continue

		var ow: int = int(r["oneWay"])
		var closed: bool = bool(r["closed"])
		var lf: int = clampi(int(r["lanesForward"]), 1, MAX_LANES)
		var lb: int = clampi(int(r["lanesBackward"]), 1, MAX_LANES)

		var j_u: Dictionary = jmap_local.get(String(r["from"]), {})
		var j_v: Dictionary = jmap_local.get(String(r["to"]), {})
		var u_ctrl := String(j_u.get("control", "none"))
		var v_ctrl := String(j_v.get("control", "none"))
		var u_arms_n: int = ((j_u.get("geom", {}) as Dictionary).get("arms", []) as Array).size()
		var v_arms_n: int = ((j_v.get("geom", {}) as Dictionary).get("arms", []) as Array).size()
		var u_multi: bool = (u_arms_n >= 3 or u_ctrl == "lights") and u_ctrl != "roundabout" and u_ctrl != "roundabout2"
		var v_multi: bool = (v_arms_n >= 3 or v_ctrl == "lights") and v_ctrl != "roundabout" and v_ctrl != "roundabout2"

		var app_f: int = get_effective_approach_lanes(r, true) if (v_multi and span >= 22.0 and not closed) else (lf if ow >= 0 else 0)
		var app_b: int = get_effective_approach_lanes(r, false) if (u_multi and span >= 22.0 and not closed) else (lb if ow <= 0 else 0)
		var pk_sz: int = get_effective_pocket_size(r)
		var pk_base_len: float = POCKET_SIZES[pk_sz]

		var pk_len_f: float = minf(span * 0.44, pk_base_len) if app_f > lf else 0.0
		var split_f: float = minf(POCKET_SPLIT, maxf(6.0, span * 0.26)) if app_f > lf else 0.0
		var s_split_f0: float = maxf(s0, s1 - pk_len_f - split_f)
		var s_split_f1: float = maxf(s_split_f0 + 0.5, s1 - pk_len_f)

		var pk_len_b: float = minf(span * 0.44, pk_base_len) if app_b > lb else 0.0
		var split_b: float = minf(POCKET_SPLIT, maxf(6.0, span * 0.26)) if app_b > lb else 0.0
		var s_split_b1: float = minf(s1, s0 + pk_len_b)
		var s_split_b0: float = minf(s1, s0 + pk_len_b + split_b)

		var isl_u: bool = (ow == 0 and not closed and rlen >= 46.0 and span >= 28.0 and u_ctrl == "lights" and (lf + lb >= 4 or app_b > lb or String(r["roadClass"]) == "toll"))
		var isl_v: bool = (ow == 0 and not closed and rlen >= 46.0 and span >= 28.0 and v_ctrl == "lights" and (lf + lb >= 4 or app_f > lf or String(r["roadClass"]) == "toll"))
		var isl_len: float = minf(16.0, span * 0.30)
		var isl_taper: float = minf(LANE_TAPER, span * 0.18)

		var stations: PackedFloat32Array = _build_station_samples(pts, cum, s0, s1, 2.6 if (app_f > lf or app_b > lb or isl_u or isl_v) else 4.8)
		var frames: Array[Dictionary] = []
		frames.resize(stations.size())
		for si in range(stations.size()):
			frames[si] = _sample_smoothed_frame(pts, cum, rlen, stations[si])

		var asym_shift: float = float(lf - lb) * 0.5 * LANE_SPACING
		var div_shift: float = -side_sign * asym_shift

		# Centerline & median island zones for two-way roads
		if ow == 0:
			var center_pts := PackedVector2Array()
			for si in range(stations.size()):
				center_pts.append((frames[si]["pos"] as Vector2) + (frames[si]["right"] as Vector2) * div_shift)
			r["centerLine"] = center_pts
			r["medianShifted"] = isl_u or isl_v

			var med_zones: Array = []
			var single_s0: float = s0
			var single_s1: float = s1
			if isl_u:
				var zu_end: float = minf(s1, s0 + isl_len + isl_taper)
				single_s0 = zu_end
				var l_pts := PackedVector2Array()
				var r_pts := PackedVector2Array()
				for si in range(stations.size()):
					var sv: float = stations[si]
					if sv <= zu_end + 0.3:
						var hw_u: float = MEDIAN_ISLAND_HALF_W * ramp(zu_end, s0 + isl_len, sv)
						var c_p: Vector2 = (frames[si]["pos"] as Vector2) + (frames[si]["right"] as Vector2) * div_shift
						var rn_p: Vector2 = frames[si]["right"]
						l_pts.append(c_p - rn_p * hw_u)
						r_pts.append(c_p + rn_p * hw_u)
				if l_pts.size() >= 2:
					med_zones.append({"left_pts": l_pts, "right_pts": r_pts})
			if isl_v:
				var zv_start: float = maxf(single_s0, s1 - isl_len - isl_taper)
				single_s1 = zv_start
				var l_pts_v := PackedVector2Array()
				var r_pts_v := PackedVector2Array()
				for si in range(stations.size()):
					var sv: float = stations[si]
					if sv >= zv_start - 0.3:
						var hw_v: float = MEDIAN_ISLAND_HALF_W * ramp(zv_start, s1 - isl_len, sv)
						var c_p: Vector2 = (frames[si]["pos"] as Vector2) + (frames[si]["right"] as Vector2) * div_shift
						var rn_p: Vector2 = frames[si]["right"]
						l_pts_v.append(c_p - rn_p * hw_v)
						r_pts_v.append(c_p + rn_p * hw_v)
				if l_pts_v.size() >= 2:
					med_zones.append({"left_pts": l_pts_v, "right_pts": r_pts_v})
			r["medianZones"] = med_zones
			if single_s1 - single_s0 >= 1.2:
				r["centerSingleZones"] = [[single_s0, single_s1]]

		# Forward lanes (`inner_k = 0 .. app_f - 1`, traveling `s0 -> s1`)
		var fwd_list: Array = []
		if ow >= 0:
			for kf in range(app_f):
				var is_pk_f: bool = kf >= lf
				var start_s_f: float = s_split_f0 if is_pk_f else s0
				var l_pts_f := PackedVector2Array()
				for si in range(stations.size()):
					var sv: float = stations[si]
					if sv < start_s_f - 0.15:
						continue
					var wf: float = ramp(s_split_f0, s_split_f1, sv) if is_pk_f else 1.0
					var eff_k: float = (float(lf - 1) + float(kf - (lf - 1)) * wf) if is_pk_f else float(kf)
					var lat_f: float
					if ow != 0:
						lat_f = side_sign * (eff_k - float(lf - 1) * 0.5) * LANE_SPACING
					else:
						var ihw: float = 0.0
						if isl_u:
							ihw = maxf(ihw, MEDIAN_ISLAND_HALF_W * ramp(s0 + isl_len + isl_taper, s0 + isl_len, sv))
						if isl_v:
							ihw = maxf(ihw, MEDIAN_ISLAND_HALF_W * ramp(s1 - isl_len - isl_taper, s1 - isl_len, sv))
						lat_f = div_shift + side_sign * (ihw + LANE_SEPARATION + eff_k * LANE_SPACING)
					var p_f: Vector2 = (frames[si]["pos"] as Vector2) + (frames[si]["right"] as Vector2) * lat_f
					if l_pts_f.is_empty() or l_pts_f[l_pts_f.size() - 1].distance_to(p_f) > 0.05:
						l_pts_f.append(p_f)
				if l_pts_f.size() >= 2:
					fwd_list.append({
						"inner_k": kf,
						"is_pocket": is_pk_f,
						"s0": start_s_f,
						"s1": s1,
						"pts": l_pts_f,
						"cum_len": build_cum_lengths(l_pts_f)
					})
		r["lanesFwd"] = fwd_list

		# Backward lanes (`inner_k = 0 .. app_b - 1`, traveling `s1 -> s0`!)
		var bwd_list: Array = []
		if ow <= 0:
			for kb in range(app_b):
				var is_pk_b: bool = kb >= lb
				var start_s_b: float = s_split_b0 if is_pk_b else s1
				var l_pts_b := PackedVector2Array()
				for si in range(stations.size() - 1, -1, -1):
					var sv: float = stations[si]
					if sv > start_s_b + 0.15:
						continue
					var wb: float = ramp(s_split_b0, s_split_b1, sv) if is_pk_b else 1.0
					var eff_kb: float = (float(lb - 1) + float(kb - (lb - 1)) * wb) if is_pk_b else float(kb)
					var lat_b: float
					if ow != 0:
						lat_b = -side_sign * (eff_kb - float(lb - 1) * 0.5) * LANE_SPACING
					else:
						var ihw_b: float = 0.0
						if isl_u:
							ihw_b = maxf(ihw_b, MEDIAN_ISLAND_HALF_W * ramp(s0 + isl_len + isl_taper, s0 + isl_len, sv))
						if isl_v:
							ihw_b = maxf(ihw_b, MEDIAN_ISLAND_HALF_W * ramp(s1 - isl_len - isl_taper, s1 - isl_len, sv))
						lat_b = div_shift - side_sign * (ihw_b + LANE_SEPARATION + eff_kb * LANE_SPACING)
					var p_b: Vector2 = (frames[si]["pos"] as Vector2) + (frames[si]["right"] as Vector2) * lat_b
					if l_pts_b.is_empty() or l_pts_b[l_pts_b.size() - 1].distance_to(p_b) > 0.05:
						l_pts_b.append(p_b)
				if l_pts_b.size() >= 2:
					bwd_list.append({
						"inner_k": kb,
						"is_pocket": is_pk_b,
						"s0": s0,
						"s1": start_s_b,
						"pts": l_pts_b,
						"cum_len": build_cum_lengths(l_pts_b)
					})
		r["lanesBwd"] = bwd_list

	# === STAGE 3: Sync Exact Built Lane Endpoints & Build `plaza_poly` / Roundabout Curved Throat Flares ===
	var half_lw_st3: float = LANE_WIDTH * 0.5
	for j in junctions:
		var jp: Vector2 = j["pos"]
		var geom: Dictionary = j.get("geom", {})
		var gkind := String(geom.get("kind", "empty"))
		var arms: Array = geom.get("arms", [])
		for a in arms:
			var eid_a := String(a["edge_id"])
			if not road_map.has(eid_a):
				continue
			var r_a: Dictionary = road_map[eid_a]
			var is_st_a: bool = bool(a["is_start"])
			var rlen_a: float = float(r_a["lengthPx"])
			var s0_a: float = clampf(float(r_a["trimStart"]), 0.0, rlen_a * 0.46)
			var s1_a: float = clampf(rlen_a - float(r_a["trimEnd"]), s0_a + 1.5, rlen_a)
			var s_actual: float = s0_a if is_st_a else s1_a
			var fr_a: Dictionary = _sample_smoothed_frame(r_a["pts"], r_a["cum_len"], rlen_a, s_actual)
			var u_out_a: Vector2 = fr_a["dir"] if is_st_a else -(fr_a["dir"] as Vector2)
			var p_th_a: Vector2 = fr_a["pos"]
			var rn_a := Vector2(-u_out_a.y, u_out_a.x)
			a["throat_pos"] = p_th_a
			a["throat_out_dir"] = u_out_a
			a["trim"] = s0_a if is_st_a else (rlen_a - s1_a)

			var min_proj: float = 1e9
			var max_proj: float = -1e9
			for ld_f in r_a.get("lanesFwd", []):
				var fpts: PackedVector2Array = ld_f["pts"]
				if fpts.size() < 2:
					continue
				if is_st_a and bool(ld_f["is_pocket"]):
					continue
				var ep_f: Vector2 = fpts[0] if is_st_a else fpts[fpts.size() - 1]
				var pr_f: float = (ep_f - p_th_a).dot(rn_a)
				min_proj = minf(min_proj, pr_f - half_lw_st3)
				max_proj = maxf(max_proj, pr_f + half_lw_st3)
			for ld_b in r_a.get("lanesBwd", []):
				var bpts: PackedVector2Array = ld_b["pts"]
				if bpts.size() < 2:
					continue
				if (not is_st_a) and bool(ld_b["is_pocket"]):
					continue
				# Note: `lanesBwd` pts run from `s1` (`index 0`) to `s0` (`index size-1`)!
				var ep_b: Vector2 = bpts[bpts.size() - 1] if is_st_a else bpts[0]
				var pr_b: float = (ep_b - p_th_a).dot(rn_a)
				min_proj = minf(min_proj, pr_b - half_lw_st3)
				max_proj = maxf(max_proj, pr_b + half_lw_st3)
			if min_proj < max_proj:
				a["lo_ext"] = min_proj
				a["hi_ext"] = max_proj
				a["road_w"] = max_proj - min_proj
				a["hw"] = maxf(absf(min_proj), absf(max_proj))
			a["left_corner"] = p_th_a + rn_a * float(a["lo_ext"])
			a["right_corner"] = p_th_a + rn_a * float(a["hi_ext"])

		if gkind == "standard":
			var ppoly: PackedVector2Array = _build_plaza_polygon(jp, arms)
			geom["plaza_poly"] = ppoly
			geom["swept_asphalt"] = ppoly
		elif gkind == "roundabout" or gkind == "roundabout2":
			var r_out: float = float(geom["r_outer"])
			for a in arms:
				var p_th: Vector2 = a["throat_pos"]
				var u_out: Vector2 = a["throat_out_dir"]
				var rn := Vector2(-u_out.y, u_out.x)
				var lo_p: Vector2 = a.get("left_corner", p_th + rn * float(a["lo_ext"]))
				var hi_p: Vector2 = a.get("right_corner", p_th + rn * float(a["hi_ext"]))
				var ang_c: float = atan2((p_th - jp).y, (p_th - jp).x)
				var spread_lo: float = clampf(atan2(absf(float(a["lo_ext"])) + 4.4, r_out), 0.20, 0.66)
				var spread_hi: float = clampf(atan2(absf(float(a["hi_ext"])) + 4.4, r_out), 0.20, 0.66)
				var ring_lo: Vector2 = jp + Vector2(cos(ang_c - spread_lo), sin(ang_c - spread_lo)) * (r_out - 1.2)
				var ring_hi: Vector2 = jp + Vector2(cos(ang_c + spread_hi), sin(ang_c + spread_hi)) * (r_out - 1.2)
				var tan_lo := Vector2(sin(ang_c - spread_lo), -cos(ang_c - spread_lo))
				var tan_hi := Vector2(sin(ang_c + spread_hi), -cos(ang_c + spread_hi))

				var flare := PackedVector2Array()
				var side_a: PackedVector2Array = bend(lo_p, -u_out, ring_lo, tan_lo, 1.8, false)
				for pt in side_a:
					flare.append(pt)
				var arc_steps: int = 6
				for k in range(1, arc_steps):
					var ang_k: float = lerpf(ang_c - spread_lo, ang_c + spread_hi, float(k) / float(arc_steps))
					flare.append(jp + Vector2(cos(ang_k), sin(ang_k)) * (r_out - 1.8))
				var side_b: PackedVector2Array = bend(ring_hi, tan_hi, hi_p, u_out, 1.8, false)
				for pt in side_b:
					flare.append(pt)
				a["flare_asphalt"] = flare
				a["ring_entry_ang"] = ang_c


static func _endpoint_and_dir_for_edge_lane(
	edge: Dictionary,
	forward: bool,
	at_exit_end: bool,
	sim_lane: float,
	sim_lanes_dir: int,
	left_hand_traffic: bool,
	prefer_pocket: bool = false
) -> Dictionary:
	var lanes_arr: Array = edge.get("lanesFwd" if forward else "lanesBwd", [])
	var main_lanes: int = maxi(1, int(edge["lanesForward"]) if forward else int(edge["lanesBackward"]))
	var clamped_l: int = clampi(int(round(sim_lane)), 0, maxi(1, sim_lanes_dir) - 1)
	var inner_k: int = clampi((main_lanes - 1) - clamped_l, 0, maxi(0, lanes_arr.size() - 1))
	if at_exit_end and prefer_pocket and lanes_arr.size() > main_lanes and clamped_l == 0:
		inner_k = lanes_arr.size() - 1

	if not lanes_arr.is_empty() and inner_k < lanes_arr.size():
		var lpts: PackedVector2Array = lanes_arr[inner_k]["pts"]
		if lpts.size() >= 2:
			if at_exit_end:
				var p1: Vector2 = lpts[lpts.size() - 1]
				var p0: Vector2 = lpts[lpts.size() - 2]
				var d_end: Vector2 = (p1 - p0).normalized()
				if d_end.length_squared() < 0.001:
					d_end = Vector2.RIGHT
				return {"pos": p1, "dir": d_end}
			else:
				var q0: Vector2 = lpts[0]
				var q1: Vector2 = lpts[1]
				var d_st: Vector2 = (q1 - q0).normalized()
				if d_st.length_squared() < 0.001:
					d_st = Vector2.RIGHT
				return {"pos": q0, "dir": d_st}

	var opp_l: int = int(edge["lanesBackward"]) if forward else int(edge["lanesForward"])
	var trim_v: float
	var s_v: float
	if at_exit_end:
		trim_v = float(edge.get("trimEnd", 0.0)) if forward else float(edge.get("trimStart", 0.0))
		s_v = maxf(0.0, float(edge["lengthPx"]) - trim_v)
	else:
		trim_v = float(edge.get("trimStart", 0.0)) if forward else float(edge.get("trimEnd", 0.0))
		s_v = minf(float(edge["lengthPx"]), trim_v)
	var pose: Dictionary = sample_road_pose(
		edge["pts"], edge["cum_len"], float(edge["lengthPx"]),
		int(edge["oneWay"]), forward, s_v, sim_lane, sim_lanes_dir, left_hand_traffic, opp_l
	)
	var h: float = float(pose["heading"])
	return {"pos": pose["pos"], "dir": Vector2(cos(h), sin(h))}


static func build_turn_connector_pts(
	j: Dictionary,
	in_edge: Dictionary,
	in_fwd: bool,
	in_lane: float,
	in_lanes: int,
	out_edge: Dictionary,
	out_fwd: bool,
	out_lane: float,
	out_lanes: int,
	left_hand_traffic: bool,
	use_in_pocket: bool = false
) -> PackedVector2Array:
	var ep_in: Dictionary = _endpoint_and_dir_for_edge_lane(in_edge, in_fwd, true, in_lane, in_lanes, left_hand_traffic, use_in_pocket)
	var ep_out: Dictionary = _endpoint_and_dir_for_edge_lane(out_edge, out_fwd, false, out_lane, out_lanes, left_hand_traffic, false)

	var p_start: Vector2 = ep_in["pos"]
	var dir_start: Vector2 = ep_in["dir"]
	var p_end: Vector2 = ep_out["pos"]
	var dir_end: Vector2 = ep_out["dir"]

	var geom: Dictionary = j.get("geom", {})
	var gkind := String(geom.get("kind", "standard"))
	var out := PackedVector2Array()

	if gkind == "roundabout" or gkind == "roundabout2":
		var jp: Vector2 = j["pos"]
		var r_island: float = float(geom.get("r_island", 8.6))
		var r_outer: float = float(geom.get("r_outer", 18.0))
		var r_circ: float = 0.5 * (r_island + r_outer)
		if gkind == "roundabout2":
			r_circ = lerpf(r_island, r_outer, 0.34 if in_lane >= 0.6 else 0.70)

		var raw_in_ang: float = atan2(p_start.y - jp.y, p_start.x - jp.x)
		var raw_out_ang: float = atan2(p_end.y - jp.y, p_end.x - jp.x)
		var sign_dir: float = 1.0 if left_hand_traffic else -1.0
		var raw_sweep: float = fposmod((raw_out_ang - raw_in_ang) * sign_dir, TAU)
		if String(in_edge["id"]) == String(out_edge["id"]):
			raw_sweep = TAU * 0.86

		if raw_sweep >= 0.40:
			var lead: float = minf(0.28, raw_sweep * 0.25)
			var a0: float = raw_in_ang + sign_dir * lead
			var arc_span: float = maxf(0.05, raw_sweep - 2.0 * lead)
			var ring_p0: Vector2 = jp + Vector2(cos(a0), sin(a0)) * r_circ
			var ring_t0 := Vector2(-sin(a0) * sign_dir, cos(a0) * sign_dir)
			var a1: float = a0 + sign_dir * arc_span
			var ring_p1: Vector2 = jp + Vector2(cos(a1), sin(a1)) * r_circ
			var ring_t1 := Vector2(-sin(a1) * sign_dir, cos(a1) * sign_dir)

			var entry_pts: PackedVector2Array = bend(p_start, dir_start, ring_p0, ring_t0, 1.8, false)
			for pt in entry_pts:
				out.append(pt)

			var arc_steps: int = maxi(4, int(ceil(arc_span / 0.20)))
			for k in range(1, arc_steps + 1):
				var ang: float = a0 + sign_dir * arc_span * (float(k) / float(arc_steps))
				var rp: Vector2 = jp + Vector2(cos(ang), sin(ang)) * r_circ
				if out.is_empty() or out[out.size() - 1].distance_to(rp) > 0.10:
					out.append(rp)

			var exit_pts: PackedVector2Array = bend(ring_p1, ring_t1, p_end, dir_end, 1.8, false)
			for k in range(1, exit_pts.size()):
				if out[out.size() - 1].distance_to(exit_pts[k]) > 0.10:
					out.append(exit_pts[k])
			return out

	return bend(p_start, dir_start, p_end, dir_end, 1.8, false)


static func _cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	var uu: float = u * u
	var tt: float = t * t
	return (uu * u) * p0 + (3.0 * uu * t) * p1 + (3.0 * u * tt) * p2 + (tt * t) * p3


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
		var geom: Dictionary = j.get("geom", {})
		var extra_r: float = maxf(0.0, float(geom.get("r_outer", 0.0)) - 10.0)
		var d: float = world_p.distance_to(jp) - extra_r * 0.45
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
		var half_bonus: float = clampf((float(r.get("widthPx", 14.4)) - 14.4) * 0.35, 0.0, 12.0)
		for i in range(pts.size() - 1):
			var d: float = point_to_segment_dist(world_p, pts[i], pts[i + 1]) - half_bonus
			if d < best_d:
				best_d = d
				best = r
	return best


static func sample_polyline_pose_clamped(pts: PackedVector2Array, cum_len: PackedFloat32Array, s_px: float) -> Dictionary:
	if pts.is_empty():
		return {"pos": Vector2.ZERO, "angle": 0.0, "dir": Vector2.RIGHT}
	if pts.size() == 1 or cum_len.is_empty():
		return {"pos": pts[0], "angle": 0.0, "dir": Vector2.RIGHT}
	var total: float = cum_len[cum_len.size() - 1]
	if s_px < 0.0:
		var d0: Vector2 = (pts[1] - pts[0]).normalized()
		if d0.length_squared() < 0.001:
			d0 = Vector2.RIGHT
		return {"pos": pts[0] + d0 * s_px, "angle": atan2(d0.y, d0.x), "dir": d0}
	if s_px > total:
		var n: int = pts.size()
		var d1: Vector2 = (pts[n - 1] - pts[n - 2]).normalized()
		if d1.length_squared() < 0.001:
			d1 = Vector2.RIGHT
		return {"pos": pts[n - 1] + d1 * (s_px - total), "angle": atan2(d1.y, d1.x), "dir": d1}
	var raw: Dictionary = sample_polyline_raw(pts, cum_len, s_px)
	var dr: Vector2 = raw["dir"]
	return {"pos": raw["pos"], "angle": atan2(dr.y, dr.x), "dir": dr}


static func min_polyline_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.is_empty() or b.is_empty():
		return INF
	var best: float = INF
	for i in range(a.size() - 1):
		var a0: Vector2 = a[i]
		var a1: Vector2 = a[i + 1]
		for k in range(b.size() - 1):
			var b0: Vector2 = b[k]
			var b1: Vector2 = b[k + 1]
			if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
				return 0.0
			best = minf(best, point_to_segment_dist(a0, b0, b1))
			best = minf(best, point_to_segment_dist(b0, a0, a1))
		best = minf(best, point_to_segment_dist(a[a.size() - 1], b[0], b[b.size() - 1]))
	return best


## Authentic pairwise junction & roundabout movement `conflict_zones` check (`CROSS`, `MERGE`, `DIVERGE`).
static func movements_conflict(
	j: Dictionary,
	a_pts: PackedVector2Array,
	a_in_road: String,
	a_out_road: String,
	a_out_lane: int,
	b_pts: PackedVector2Array,
	b_in_road: String,
	b_out_road: String,
	b_out_lane: int
) -> bool:
	# Identical exit road + identical exit lane => MERGE conflict
	if a_out_road != "" and a_out_road == b_out_road and a_out_lane == b_out_lane:
		return true
	# Same incoming road on parallel distinct lanes going to same road on distinct lanes => non-conflicting parallel turn!
	if a_in_road != "" and a_in_road == b_in_road and a_out_road == b_out_road and a_out_lane != b_out_lane:
		return false
	if a_pts.size() >= 2 and b_pts.size() >= 2:
		var clearance: float = LANE_SEPARATION * 0.84
		var geom: Dictionary = j.get("geom", {})
		if String(geom.get("kind", "")) == "roundabout2":
			clearance = LANE_SEPARATION * 0.72
		return min_polyline_distance(a_pts, b_pts) < clearance
	# Fallback conservative check if turn connector pts unavailable
	return a_in_road != b_in_road or a_out_road == b_out_road


## Authentic `CityRebuild` (`city_rebuild.gd`): trims, slides back, or demolishes `sim.buildings`
## whenever roads are widened, Road Offers are built, ExitRoads are added, or Roundabouts expand.
static func rebuild_city_buildings_around_roads(buildings: Array, roads: Array, junctions: Array) -> int:
	var touched: int = 0
	var active_roads: Array = []
	for r in roads:
		if bool(r.get("isBuilt", true)) and not bool(r.get("closed", false)):
			active_roads.append(r)

	for b in buildings:
		if bool(b.get("demolished", false)):
			continue
		if not b.has("origX"):
			b["origX"] = float(b["x"])
			b["origY"] = float(b["y"])
			b["origW"] = float(b["w"])
			b["origD"] = float(b["d"])
		var bp := Vector2(float(b["x"]), float(b["y"]))
		var rad_b: float = 0.5 * maxf(float(b["w"]), float(b["d"]))

		# 1. Check Roundabout & large plaza clearance
		var max_pen: float = 0.0
		var push_vec := Vector2.ZERO
		for j in junctions:
			var geom: Dictionary = j.get("geom", {})
			var r_out: float = float(geom.get("r_outer", 0.0))
			if r_out <= 6.0:
				continue
			var jp: Vector2 = j["pos"]
			var req: float = r_out + 1.8 + rad_b * 0.78
			var dist: float = bp.distance_to(jp)
			if dist < req:
				var pen: float = req - dist
				if pen > max_pen:
					max_pen = pen
					push_vec = (bp - jp).normalized() if dist > 0.1 else Vector2.UP

		# 2. Check widened road / built offer / exit slip clearance
		for r in active_roads:
			var pts: PackedVector2Array = r["pts"]
			if pts.size() < 2:
				continue
			var half_road: float = float(r.get("widthPx", 12.0)) * 0.5 + 1.5
			var req_r: float = half_road + rad_b * 0.72
			for i in range(pts.size() - 1):
				var cp: Vector2 = Geometry2D.get_closest_point_to_segment(bp, pts[i], pts[i + 1])
				var dist_r: float = bp.distance_to(cp)
				if dist_r < req_r:
					var pen_r: float = req_r - dist_r
					if pen_r > max_pen:
						max_pen = pen_r
						push_vec = (bp - cp).normalized() if dist_r > 0.1 else Vector2(0.0, -1.0)

		if max_pen <= 0.15:
			continue
		touched += 1
		if max_pen <= 2.4 and float(b["d"]) > 7.5:
			# Shallow trim
			b["d"] = maxf(6.0, float(b["d"]) - max_pen * 0.85)
			var slide_s: Vector2 = bp + push_vec * (max_pen * 0.65)
			b["x"] = slide_s.x
			b["y"] = slide_s.y
		elif max_pen <= 8.5:
			# Slide building back away from widened curb
			var slide_p: Vector2 = bp + push_vec * (max_pen + 0.8)
			b["x"] = slide_p.x
			b["y"] = slide_p.y
		else:
			# Deep encroachment inside new corridor or roundabout -> demolish cleanly
			b["demolished"] = true
	return touched

