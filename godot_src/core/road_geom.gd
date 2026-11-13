class_name RoadGeom
extends RefCounted

## High-speed road curve sampler, swept junction/roundabout geometry builder,
## turn-connector Bezier/orbital arc generator, and mobile touch hit-tester.

const LANE_WIDTH: float = 5.2

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

static func get_road_width(r: Dictionary) -> float:
	var ow: int = int(r.get("oneWay", 0))
	var lf: int = maxi(1, int(r.get("lanesForward", 1)))
	var lb: int = maxi(1, int(r.get("lanesBackward", 1)))
	if ow != 0:
		var lanes_ow: int = lf if ow > 0 else lb
		return float(lanes_ow) * LANE_WIDTH + 3.0
	var tot: int = lf + lb
	var med: float = 1.6 if tot >= 4 else 0.8
	return float(tot) * LANE_WIDTH + med + 3.0

static func get_lane_lateral_offset(
	one_way: int,
	lane_offset_float: float,
	total_lanes_dir: int,
	opp_lanes_dir: int,
	left_hand_traffic: bool
) -> float:
	if one_way != 0:
		var center_idx: float = float(total_lanes_dir - 1) * 0.5
		var signed_idx: float = (center_idx - lane_offset_float) if left_hand_traffic else (lane_offset_float - center_idx)
		return signed_idx * LANE_WIDTH
	var tot: int = total_lanes_dir + maxi(1, opp_lanes_dir)
	var med: float = 1.6 if tot >= 4 else 0.8
	# Shift divider if asymmetric lane counts exist
	var asym_shift: float = float(total_lanes_dir - opp_lanes_dir) * 0.5 * LANE_WIDTH
	var inner_idx: float = float(total_lanes_dir - 1) - lane_offset_float
	var dist_from_div: float = med * 0.5 + (0.5 + inner_idx) * LANE_WIDTH - asym_shift
	return -dist_from_div if left_hand_traffic else dist_from_div

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
	if b_s - a_s < 0.25:
		return out
	var p_start: Vector2 = sample_polyline_raw(pts, cum_len, a_s)["pos"]
	var p_end: Vector2 = sample_polyline_raw(pts, cum_len, b_s)["pos"]
	out.append(p_start)
	for i in range(1, n - 1):
		var d_i: float = cum_len[i]
		if d_i > a_s + 0.15 and d_i < b_s - 0.15:
			out.append(pts[i])
	if out[out.size() - 1].distance_to(p_end) > 0.08:
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

static func sample_stitched_pose(pts: PackedVector2Array, cum_len: PackedFloat32Array, s_px: float) -> Dictionary:
	var raw: Dictionary = sample_polyline_raw(pts, cum_len, s_px)
	var d: Vector2 = raw["dir"]
	return {"pos": raw["pos"], "heading": atan2(d.y, d.x)}

static func _intersect_rays_2d(p1: Vector2, d1: Vector2, p2: Vector2, d2: Vector2) -> Dictionary:
	var denom: float = d1.x * d2.y - d1.y * d2.x
	if absf(denom) < 0.14:
		return {"ok": false}
	var diff: Vector2 = p2 - p1
	var t1: float = (diff.x * d2.y - diff.y * d2.x) / denom
	var t2: float = (diff.x * d1.y - diff.y * d1.x) / denom
	return {"ok": true, "t1": t1, "t2": t2, "pos": p1 + d1 * t1}

static func _build_swept_junction_poly(jp: Vector2, arms: Array, expand: float, fillet_steps: int = 6) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var n: int = arms.size()
	if n < 2:
		return poly
	var max_trim: float = 12.0
	for a in arms:
		max_trim = maxf(max_trim, float(a["trim"]))

	# Precompute whether corner i -> i+1 has acute curb overlap (right_cur crosses past left_nxt)
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
		var hw_cur: float = float(a_cur["hw"]) + expand

		var p_nxt: Vector2 = a_nxt["throat_pos"]
		var u_nxt: Vector2 = a_nxt["throat_out_dir"]
		var rn_nxt := Vector2(-u_nxt.y, u_nxt.x)
		var hw_nxt: float = float(a_nxt["hw"]) + expand

		var right_cur: Vector2 = p_cur + rn_cur * hw_cur
		var left_nxt: Vector2 = p_nxt - rn_nxt * hw_nxt
		var delta_ang: float = fposmod(float(a_nxt["angle"]) - float(a_cur["angle"]), TAU)
		var ang_r: float = atan2((right_cur - jp).y, (right_cur - jp).x)
		var ang_ln: float = atan2((left_nxt - jp).y, (left_nxt - jp).x)
		var ccw_gap: float = fposmod(ang_ln - ang_r, TAU)

		if delta_ang < PI and ccw_gap > PI:
			corner_crossed[i] = true
			var hit_c: Dictionary = _intersect_rays_2d(right_cur, u_cur, left_nxt, u_nxt)
			var crotch: Vector2 = 0.5 * (right_cur + left_nxt)
			if bool(hit_c.get("ok", false)):
				var hp: Vector2 = hit_c["pos"]
				if hp.distance_to(jp) <= max_trim * 1.20:
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
		var hw_cur: float = float(a_cur["hw"]) + expand

		var p_nxt: Vector2 = a_nxt["throat_pos"]
		var u_nxt: Vector2 = a_nxt["throat_out_dir"]
		var rn_nxt := Vector2(-u_nxt.y, u_nxt.x)
		var hw_nxt: float = float(a_nxt["hw"]) + expand

		var left_cur: Vector2 = p_cur - rn_cur * hw_cur
		var right_cur: Vector2 = p_cur + rn_cur * hw_cur
		var left_nxt: Vector2 = p_nxt - rn_nxt * hw_nxt

		if not corner_crossed[prev_i]:
			if poly.is_empty() or poly[poly.size() - 1].distance_to(left_cur) > 0.15:
				poly.append(left_cur)

		if corner_crossed[i]:
			var vc: Vector2 = corner_crotch[i]
			if poly.is_empty() or poly[poly.size() - 1].distance_to(vc) > 0.15:
				poly.append(vc)
			continue

		if poly.is_empty() or poly[poly.size() - 1].distance_to(right_cur) > 0.15:
			poly.append(right_cur)

		# Smooth inward Bezier fillet (or flush/rounded outer elbow for >= 150 deg)
		var delta_ang: float = fposmod(float(a_nxt["angle"]) - float(a_cur["angle"]), TAU)
		var ctrl_pt: Vector2
		if delta_ang >= deg_to_rad(150.0):
			var mid_ang: float = float(a_cur["angle"]) + delta_ang * 0.5
			var out_n := Vector2(cos(mid_ang), sin(mid_ang))
			var outer_scale: float = 1.0 / maxf(0.58, cos((delta_ang - PI) * 0.5))
			ctrl_pt = jp + out_n * (maxf(hw_cur, hw_nxt) * outer_scale)
		else:
			var hit: Dictionary = _intersect_rays_2d(right_cur, u_cur, left_nxt, u_nxt)
			if bool(hit.get("ok", false)) and float(hit["t1"]) <= 0.6 and float(hit["t2"]) <= 0.6:
				var t1_clamped: float = clampf(float(hit["t1"]), -float(a_cur["trim"]) * 0.95, 0.25)
				ctrl_pt = right_cur + u_cur * t1_clamped
			else:
				ctrl_pt = 0.5 * (right_cur + left_nxt)

		for k in range(1, fillet_steps):
			var t: float = float(k) / float(fillet_steps)
			var omt: float = 1.0 - t
			var bp: Vector2 = (omt * omt) * right_cur + (2.0 * omt * t) * ctrl_pt + (t * t) * left_nxt
			if poly[poly.size() - 1].distance_to(bp) > 0.15:
				poly.append(bp)
	return poly


static func compute_network_junction_geometry(junctions: Array, roads: Array, road_map: Dictionary, left_hand_traffic: bool = true) -> void:
	for r in roads:
		r["trimStart"] = 0.0
		r["trimEnd"] = 0.0
		r["widthPx"] = get_road_width(r)

	for j in junctions:
		var jid := String(j["id"])
		var jp: Vector2 = j["pos"]
		var ctrl := String(j.get("control", "none"))
		var arms: Array = []

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
			arms.append({
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
				"trim": 6.0
			})

		arms.sort_custom(func(a, b): return float(a["angle"]) < float(b["angle"]))
		var n: int = arms.size()

		if n == 0:
			j["geom"] = {"kind": "empty", "arms": []}
			continue

		# Compute allowed turn flags per arm (for accurate road paint turn arrows)
		for i in range(n):
			var a_in: Dictionary = arms[i]
			var v_in: Vector2 = -(a_in["out_dir"] as Vector2)
			var has_l := false
			var has_s := false
			var has_r := false
			for k in range(n):
				if k == i:
					continue
				var a_out: Dictionary = arms[k]
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
			var max_hw: float = 6.0
			var min_len: float = 9999.0
			for a in arms:
				max_hw = maxf(max_hw, float(a["hw"]))
				min_len = minf(min_len, float(a["rlen"]))
			var r_outer: float
			var r_island: float
			if ctrl == "roundabout2":
				r_island = clampf(maxf(9.6, max_hw * 1.02), 7.2, maxf(7.8, min_len * 0.21))
				r_outer = r_island + 11.4
			else:
				r_island = clampf(maxf(8.2, max_hw * 0.90), 6.2, maxf(6.8, min_len * 0.19))
				r_outer = r_island + 7.6

			for a in arms:
				var r_edge: Dictionary = road_map[String(a["edge_id"])]
				var tr: float = clampf(r_outer + 5.2, r_outer + 1.8, maxf(r_outer + 2.0, float(a["rlen"]) * 0.45))
				a["trim"] = tr
				var s_th: float = tr if bool(a["is_start"]) else maxf(0.0, float(a["rlen"]) - tr)
				var raw_th: Dictionary = sample_polyline_raw(r_edge["pts"], r_edge["cum_len"], s_th)
				var u_out: Vector2 = raw_th["dir"] if bool(a["is_start"]) else -(raw_th["dir"] as Vector2)
				if (raw_th["pos"] as Vector2 - jp).dot(u_out) < 0.0:
					u_out = -u_out
				a["throat_pos"] = raw_th["pos"]
				a["throat_out_dir"] = u_out
				if bool(a["is_start"]):
					r_edge["trimStart"] = maxf(float(r_edge["trimStart"]), tr)
				else:
					r_edge["trimEnd"] = maxf(float(r_edge["trimEnd"]), tr)

				# Build smooth flared throat polygon into the roundabout ring
				var rn := Vector2(-u_out.y, u_out.x)
				var p_th: Vector2 = raw_th["pos"]
				var hw: float = float(a["hw"])
				var ang_c: float = atan2((p_th - jp).y, (p_th - jp).x)
				var spread: float = clampf(atan2(hw + 4.8, r_outer), 0.22, 0.68)
				var ring_l: Vector2 = jp + Vector2(cos(ang_c - spread), sin(ang_c - spread)) * (r_outer - 1.6)
				var ring_r: Vector2 = jp + Vector2(cos(ang_c + spread), sin(ang_c + spread)) * (r_outer - 1.6)
				a["flare_asphalt"] = PackedVector2Array([p_th - rn * hw, p_th + rn * hw, ring_r, ring_l])
				var sp_curb: float = clampf(atan2(hw + 6.2, r_outer + 1.2), 0.25, 0.72)
				a["flare_curb"] = PackedVector2Array([
					p_th - rn * (hw + 1.2), p_th + rn * (hw + 1.2),
					jp + Vector2(cos(ang_c + sp_curb), sin(ang_c + sp_curb)) * (r_outer + 0.4),
					jp + Vector2(cos(ang_c - sp_curb), sin(ang_c - sp_curb)) * (r_outer + 0.4)
				])
				var sp_sw: float = clampf(atan2(hw + 8.0, r_outer + 3.0), 0.28, 0.76)
				a["flare_sidewalk"] = PackedVector2Array([
					p_th - rn * (hw + 2.8), p_th + rn * (hw + 2.8),
					jp + Vector2(cos(ang_c + sp_sw), sin(ang_c + sp_sw)) * (r_outer + 2.0),
					jp + Vector2(cos(ang_c - sp_sw), sin(ang_c - sp_sw)) * (r_outer + 2.0)
				])
				a["ring_entry_ang"] = ang_c

			j["geom"] = {
				"kind": ctrl,
				"r_outer": r_outer,
				"r_island": r_island,
				"arms": arms,
				"lht": left_hand_traffic
			}
			continue

		# Standard Junction (none, yield, lights, or dead-end)
		if n == 1:
			var a0: Dictionary = arms[0]
			var r0: Dictionary = road_map[String(a0["edge_id"])]
			var tr0: float = minf(6.5, float(a0["rlen"]) * 0.22)
			a0["trim"] = tr0
			var s0_th: float = tr0 if bool(a0["is_start"]) else maxf(0.0, float(a0["rlen"]) - tr0)
			var raw0: Dictionary = sample_polyline_raw(r0["pts"], r0["cum_len"], s0_th)
			var u0: Vector2 = raw0["dir"] if bool(a0["is_start"]) else -(raw0["dir"] as Vector2)
			a0["throat_pos"] = raw0["pos"]
			a0["throat_out_dir"] = u0
			if bool(a0["is_start"]):
				r0["trimStart"] = maxf(float(r0["trimStart"]), tr0)
			else:
				r0["trimEnd"] = maxf(float(r0["trimEnd"]), tr0)
			j["geom"] = {"kind": "culdesac", "arms": arms, "radius": float(a0["hw"])}
			continue

		var r_fillet: float = 5.5 if n >= 3 or ctrl == "lights" else 3.2
		var req_trims: Array[float] = []
		req_trims.resize(n)
		for i in range(n):
			req_trims[i] = float(arms[i]["hw"]) + (4.2 if ctrl == "lights" or n >= 3 else 2.2)

		for i in range(n):
			var i_nxt: int = (i + 1) % n
			var hw_a: float = float(arms[i]["hw"])
			var hw_b: float = float(arms[i_nxt]["hw"])
			var delta: float = fposmod(float(arms[i_nxt]["angle"]) - float(arms[i]["angle"]), TAU)
			if delta < deg_to_rad(156.0):
				var clamped_d: float = clampf(delta, deg_to_rad(24.0), deg_to_rad(156.0))
				var sin_d: float = sin(clamped_d)
				var cos_d: float = cos(clamped_d)
				var fil_tan: float = r_fillet * tan((PI - clamped_d) * 0.5)
				var ta: float = (hw_b + hw_a * cos_d) / sin_d + fil_tan
				var tb: float = (hw_a + hw_b * cos_d) / sin_d + fil_tan
				req_trims[i] = maxf(req_trims[i], ta)
				req_trims[i_nxt] = maxf(req_trims[i_nxt], tb)
			else:
				var flat_t: float = maxf(hw_a, hw_b) + (4.5 if n >= 3 or ctrl == "lights" else 2.4)
				req_trims[i] = maxf(req_trims[i], flat_t)
				req_trims[i_nxt] = maxf(req_trims[i_nxt], flat_t)

		for i in range(n):
			var a: Dictionary = arms[i]
			var r_edge: Dictionary = road_map[String(a["edge_id"])]
			var min_t: float = maxf(float(a["hw"]) + 2.8, 8.5 if (n >= 3 or ctrl == "lights") else 5.5)
			var max_t: float = minf(float(a["rlen"]) * 0.36, 27.0)
			var tr: float = clampf(req_trims[i], minf(min_t, max_t), max_t)
			a["trim"] = tr
			var s_th: float = tr if bool(a["is_start"]) else maxf(0.0, float(a["rlen"]) - tr)
			var raw_th: Dictionary = sample_polyline_raw(r_edge["pts"], r_edge["cum_len"], s_th)
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
			"arms": arms,
			"swept_asphalt": _build_swept_junction_poly(jp, arms, 0.15, 6),
			"swept_curb": _build_swept_junction_poly(jp, arms, 1.25, 6),
			"swept_sidewalk": _build_swept_junction_poly(jp, arms, 2.95, 6)
		}

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
	left_hand_traffic: bool
) -> PackedVector2Array:
	var in_opp: int = int(in_edge["lanesBackward"]) if in_fwd else int(in_edge["lanesForward"])
	var out_opp: int = int(out_edge["lanesBackward"]) if out_fwd else int(out_edge["lanesForward"])
	var trim_in: float = float(in_edge.get("trimEnd", 0.0)) if in_fwd else float(in_edge.get("trimStart", 0.0))
	var trim_out: float = float(out_edge.get("trimStart", 0.0)) if out_fwd else float(out_edge.get("trimEnd", 0.0))
	var s_in_end: float = maxf(0.0, float(in_edge["lengthPx"]) - trim_in)
	var s_out_start: float = minf(float(out_edge["lengthPx"]), trim_out)

	var pose_in: Dictionary = sample_road_pose(
		in_edge["pts"], in_edge["cum_len"], float(in_edge["lengthPx"]),
		int(in_edge["oneWay"]), in_fwd, s_in_end, in_lane, in_lanes, left_hand_traffic, in_opp
	)
	var pose_out: Dictionary = sample_road_pose(
		out_edge["pts"], out_edge["cum_len"], float(out_edge["lengthPx"]),
		int(out_edge["oneWay"]), out_fwd, s_out_start, out_lane, out_lanes, left_hand_traffic, out_opp
	)

	var p_start: Vector2 = pose_in["pos"]
	var h_start: float = float(pose_in["heading"])
	var dir_start := Vector2(cos(h_start), sin(h_start))

	var p_end: Vector2 = pose_out["pos"]
	var h_end: float = float(pose_out["heading"])
	var dir_end := Vector2(cos(h_end), sin(h_end))

	var geom: Dictionary = j.get("geom", {})
	var gkind := String(geom.get("kind", "standard"))
	var out := PackedVector2Array()

	if gkind == "roundabout" or gkind == "roundabout2":
		var jp: Vector2 = j["pos"]
		var r_island: float = float(geom.get("r_island", 6.5))
		var r_outer: float = float(geom.get("r_outer", 16.0))
		var r_circ: float = 0.5 * (r_island + r_outer)
		if gkind == "roundabout2":
			r_circ = lerpf(r_island, r_outer, 0.35 if in_lane >= 0.6 else 0.71)

		var raw_in_ang: float = atan2(p_start.y - jp.y, p_start.x - jp.x)
		var raw_out_ang: float = atan2(p_end.y - jp.y, p_end.x - jp.x)
		var sign_dir: float = 1.0 if left_hand_traffic else -1.0
		var raw_sweep: float = fposmod((raw_out_ang - raw_in_ang) * sign_dir, TAU)
		if String(in_edge["id"]) == String(out_edge["id"]):
			raw_sweep = TAU * 0.86

		if raw_sweep >= 0.42:
			var lead: float = minf(0.26, raw_sweep * 0.25)
			var a0: float = raw_in_ang + sign_dir * lead
			var arc_span: float = maxf(0.05, raw_sweep - 2.0 * lead)
			var ring_p0: Vector2 = jp + Vector2(cos(a0), sin(a0)) * r_circ
			var ring_t0 := Vector2(-sin(a0) * sign_dir, cos(a0) * sign_dir)
			var a1: float = a0 + sign_dir * arc_span
			var ring_p1: Vector2 = jp + Vector2(cos(a1), sin(a1)) * r_circ
			var ring_t1 := Vector2(-sin(a1) * sign_dir, cos(a1) * sign_dir)

			# Smooth entry Hermite/Bezier into circulatory ring
			var d_en: float = p_start.distance_to(ring_p0) * 0.42
			for k in range(4):
				var t: float = float(k) / 4.0
				out.append(_cubic_bezier(p_start, p_start + dir_start * d_en, ring_p0 - ring_t0 * d_en, ring_p0, t))

			# Circular orbit around central island
			var arc_steps: int = maxi(4, int(ceil(arc_span / 0.22)))
			for k in range(arc_steps + 1):
				var ang: float = a0 + sign_dir * arc_span * (float(k) / float(arc_steps))
				var rp: Vector2 = jp + Vector2(cos(ang), sin(ang)) * r_circ
				if out.is_empty() or out[out.size() - 1].distance_to(rp) > 0.12:
					out.append(rp)

			# Smooth exit Hermite/Bezier out of circulatory ring
			var d_ex: float = ring_p1.distance_to(p_end) * 0.42
			for k in range(1, 5):
				var t: float = float(k) / 4.0
				var ep: Vector2 = _cubic_bezier(ring_p1, ring_p1 + ring_t1 * d_ex, p_end - dir_end * d_ex, p_end, t)
				if out[out.size() - 1].distance_to(ep) > 0.12:
					out.append(ep)
			return out

	# Standard junction smooth C1 cubic Bezier turn connector
	var chord: float = p_start.distance_to(p_end)
	var handle: float = clampf(chord * 0.42, 2.5, 19.0)
	var c1: Vector2 = p_start + dir_start * handle
	var c2: Vector2 = p_end - dir_end * handle
	var steps: int = 8
	for k in range(steps + 1):
		var t: float = float(k) / float(steps)
		var bp: Vector2 = _cubic_bezier(p_start, c1, c2, p_end, t)
		if out.is_empty() or out[out.size() - 1].distance_to(bp) > 0.08:
			out.append(bp)
	return out

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
		for i in range(pts.size() - 1):
			var d: float = point_to_segment_dist(world_p, pts[i], pts[i + 1])
			if d < best_d:
				best_d = d
				best = r
	return best
