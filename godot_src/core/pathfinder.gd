class_name RoutePathfinder
extends RefCounted

## Directed road-graph Dijkstra router matching Incremental Traffic v1.4.1 `TruckRoute` & `RouteBreakMarks`:
## Supports forward & separate return waypoints, one-way rules, closed streets, multi-phase traffic-light
## turn masks, lane turn-arrow restrictions, region locks, exact kinematic `TruckModel.drive_time` for
## Express deadlines (`now + best * 1.3 + 3.0`), and pinpointed break location diagnostics.

const TURN_LEFT := 1
const TURN_STRAIGHT := 2
const TURN_RIGHT := 4
const TURN_ALL := 7

static func classify_turn_bit(j_map: Dictionary, road_map: Dictionary, in_edge_id: String, in_fwd: bool, j_id: String, out_edge_id: String, out_fwd: bool) -> int:
	if in_edge_id == "" or out_edge_id == "" or in_edge_id == out_edge_id:
		return TURN_STRAIGHT
	if not road_map.has(in_edge_id) or not road_map.has(out_edge_id) or not j_map.has(j_id):
		return TURN_STRAIGHT
	var r_in: Dictionary = road_map[in_edge_id]
	var r_out: Dictionary = road_map[out_edge_id]
	var pts_in: PackedVector2Array = r_in["pts"]
	var pts_out: PackedVector2Array = r_out["pts"]
	if pts_in.size() < 2 or pts_out.size() < 2:
		return TURN_STRAIGHT
	var dir_in: Vector2
	if in_fwd:
		dir_in = (pts_in[pts_in.size() - 1] - pts_in[maxi(0, pts_in.size() - 2)]).normalized()
	else:
		dir_in = (pts_in[0] - pts_in[mini(1, pts_in.size() - 1)]).normalized()
	var dir_out: Vector2
	if out_fwd:
		dir_out = (pts_out[mini(1, pts_out.size() - 1)] - pts_out[0]).normalized()
	else:
		dir_out = (pts_out[maxi(0, pts_out.size() - 2)] - pts_out[pts_out.size() - 1]).normalized()
	if dir_in.length_squared() < 0.001 or dir_out.length_squared() < 0.001:
		return TURN_STRAIGHT
	var ang: float = dir_in.angle_to(dir_out)
	if absf(ang) <= 0.48:
		return TURN_STRAIGHT
	return TURN_RIGHT if ang > 0.0 else TURN_LEFT

static func light_allows_turn(j_node: Dictionary, in_edge_id: String, turn_bit: int) -> bool:
	if String(j_node.get("control", "none")) != "lights":
		return true
	var lt: Variant = j_node.get("light", null)
	if typeof(lt) != TYPE_DICTIONARY:
		return true
	var lt_d: Dictionary = lt
	if lt_d.has("phases") and typeof(lt_d["phases"]) == TYPE_ARRAY:
		var phases: Array = lt_d["phases"]
		if phases.is_empty():
			return false
		for ph in phases:
			if float(ph.get("green", 10.0)) <= 0.1:
				continue
			var arms: Dictionary = ph.get("arms", {})
			var mask: int = int(arms.get(in_edge_id, 0))
			if (mask & turn_bit) != 0:
				return true
		return false
	return float(lt_d.get("phaseAGreen", 10.0)) > 0.1 and float(lt_d.get("phaseBGreen", 10.0)) > 0.1

static func _road_speed_mult(road_class: String) -> float:
	match road_class:
		"toll":
			return 1.22
		"national":
			return 1.06
		"local":
			return 0.84
	return 1.0

static func find_directed_path(
	start_junction_id: String,
	end_junction_id: String,
	waypoints: Array,
	junction_map: Dictionary,
	road_map: Dictionary,
	unlocked_regions: Dictionary,
	truck_model_id: String
) -> Dictionary:
	if start_junction_id == end_junction_id and waypoints.is_empty():
		return {
			"steps": [],
			"clear_time_sec": 2.5,
			"broken_reason": "",
			"broken_kind": "",
			"broken_tag": "",
			"broken_edge_id": "",
			"broken_junction_id": "",
			"broken_pos": Vector2.INF
		}

	var chain: Array[String] = [start_junction_id]
	for wp in waypoints:
		var wps := String(wp)
		if junction_map.has(wps) and chain[chain.size() - 1] != wps:
			chain.append(wps)
	if chain[chain.size() - 1] != end_junction_id:
		chain.append(end_junction_id)

	var all_steps: Array[Dictionary] = []

	for leg_i in range(chain.size() - 1):
		var prev_edge_id: String = ""
		var prev_fwd: bool = true
		if not all_steps.is_empty():
			var last_st: Dictionary = all_steps[all_steps.size() - 1]
			prev_edge_id = String(last_st["edgeId"])
			prev_fwd = bool(last_st["forward"])
		var leg_res: Dictionary = _dijkstra_leg(
			chain[leg_i],
			chain[leg_i + 1],
			junction_map,
			road_map,
			unlocked_regions,
			truck_model_id,
			prev_edge_id,
			prev_fwd
		)
		var reason := String(leg_res["broken_reason"])
		if reason != "":
			return leg_res
		for st in leg_res["steps"]:
			all_steps.append(st)

	# Compute exact kinematic traversal time (`TruckModel.drive_time`) across the assembled road chain!
	var tdef: Dictionary = GameCatalog.TRUCKS.get(truck_model_id, GameCatalog.TRUCKS["hauler"])
	var max_v: float = float(tdef["max_speed_px"])
	var total_clear_sec: float = 0.0
	for si in range(all_steps.size()):
		var st: Dictionary = all_steps[si]
		var eid := String(st["edgeId"])
		var edge: Dictionary = road_map[eid]
		var mult: float = _road_speed_mult(String(edge["roadClass"]))
		var seg_len: float = float(st["lengthPx"])
		var v0: float = 0.0 if si == 0 else max_v * 0.72
		var v1: float = 0.0 if si == all_steps.size() - 1 else max_v * 0.72
		var j_to: Dictionary = junction_map.get(String(st["toJunctionId"]), {})
		var ctrl := String(j_to.get("control", "none"))
		if si < all_steps.size() - 1:
			if ctrl == "roundabout" or ctrl == "roundabout2":
				v1 = minf(v1, max_v * 0.58)
			elif ctrl == "lights":
				total_clear_sec += 0.45
		total_clear_sec += GameCatalog.compute_truck_drive_time(truck_model_id, seg_len, v0, v1, mult)

	return {
		"steps": all_steps,
		"clear_time_sec": maxf(2.5, total_clear_sec),
		"broken_reason": "",
		"broken_kind": "",
		"broken_tag": "",
		"broken_edge_id": "",
		"broken_junction_id": "",
		"broken_pos": Vector2.INF
	}

static func _dijkstra_leg(
	src_id: String,
	dst_id: String,
	junction_map: Dictionary,
	road_map: Dictionary,
	unlocked_regions: Dictionary,
	truck_model_id: String,
	initial_in_edge: String = "",
	initial_in_fwd: bool = true
) -> Dictionary:
	if src_id == dst_id:
		return {
			"steps": [], "clear_time_sec": 1.0, "broken_reason": "",
			"broken_kind": "", "broken_tag": "", "broken_edge_id": "",
			"broken_junction_id": "", "broken_pos": Vector2.INF
		}
	if not junction_map.has(src_id) or not junction_map.has(dst_id):
		return {
			"steps": [], "clear_time_sec": 0.0,
			"broken_reason": "Simpang rute tidak valid",
			"broken_kind": "no_road", "broken_tag": "No road",
			"broken_edge_id": "", "broken_junction_id": src_id, "broken_pos": Vector2.INF
		}

	var dist := {src_id: 0.0}
	var prev_node := {}
	var prev_step := {}
	var visited := {}
	var queue: Array[String] = [src_id]

	var blocked_oneway_edge := ""
	var blocked_closed_edge := ""
	var blocked_light_junc := ""
	var blocked_lanes_junc := ""
	var blocked_lanes_edge := ""

	while not queue.is_empty():
		var best_idx: int = 0
		var best_u: String = queue[0]
		var best_d: float = float(dist[best_u])
		for qi in range(1, queue.size()):
			var cand: String = queue[qi]
			var cd: float = float(dist[cand])
			if cd < best_d:
				best_d = cd
				best_u = cand
				best_idx = qi
		queue.remove_at(best_idx)

		if visited.has(best_u):
			continue
		visited[best_u] = true
		if best_u == dst_id:
			break

		var in_edge_u: String = initial_in_edge if best_u == src_id else ""
		var in_fwd_u: bool = initial_in_fwd
		if prev_step.has(best_u):
			in_edge_u = String(prev_step[best_u]["edgeId"])
			in_fwd_u = bool(prev_step[best_u]["forward"])

		var jnode: Dictionary = junction_map[best_u]
		for eid_raw in jnode["connectedEdgeIds"]:
			var eid := String(eid_raw)
			if not road_map.has(eid):
				continue
			var edge: Dictionary = road_map[eid]
			if not bool(edge["isBuilt"]):
				continue
			if not unlocked_regions.has(int(edge["regionIndex"])):
				continue
			if bool(edge["closed"]):
				if blocked_closed_edge == "":
					blocked_closed_edge = eid
				continue

			var forward: bool = String(edge["from"]) == best_u
			var nxt_id: String = String(edge["to"]) if forward else String(edge["from"])
			if not unlocked_regions.has(int(junction_map[nxt_id]["regionIndex"])):
				continue

			var ow: int = int(edge["oneWay"])
			if (forward and ow == -1) or ((not forward) and ow == 1):
				if blocked_oneway_edge == "":
					blocked_oneway_edge = eid
				continue

			if in_edge_u != "" and in_edge_u != eid:
				var t_bit: int = classify_turn_bit(junction_map, road_map, in_edge_u, in_fwd_u, best_u, eid, forward)
				var r_prev: Dictionary = road_map[in_edge_u]
				var lane_mask: int = int(r_prev.get("turnMaskForward" if in_fwd_u else "turnMaskBackward", TURN_ALL))
				if (lane_mask & t_bit) == 0:
					if blocked_lanes_junc == "":
						blocked_lanes_junc = best_u
						blocked_lanes_edge = in_edge_u
					continue
				if not light_allows_turn(jnode, in_edge_u, t_bit):
					if blocked_light_junc == "":
						blocked_light_junc = best_u
					continue

			var mult: float = _road_speed_mult(String(edge["roadClass"]))
			var seg_len: float = float(edge["lengthPx"])
			var tdef: Dictionary = GameCatalog.TRUCKS.get(truck_model_id, GameCatalog.TRUCKS["hauler"])
			var v_cruise: float = float(tdef["max_speed_px"]) * 0.72
			var travel_sec: float = GameCatalog.compute_truck_drive_time(truck_model_id, seg_len, v_cruise, v_cruise, mult)
			var j_next: Dictionary = junction_map[nxt_id]
			var ctrl := String(j_next["control"])
			var j_pen: float = 0.50
			if ctrl == "lights":
				j_pen = 1.25
			elif ctrl == "roundabout" or ctrl == "roundabout2":
				j_pen = 0.38
			elif ctrl == "yield":
				var is_minor: bool = (j_next.get("yieldMinorEdgeIds", []) as Array).has(eid)
				j_pen = 0.80 if is_minor else 0.15

			var alt: float = best_d + travel_sec + j_pen
			if not dist.has(nxt_id) or alt < float(dist[nxt_id]):
				dist[nxt_id] = alt
				prev_node[nxt_id] = best_u
				prev_step[nxt_id] = {
					"edgeId": eid,
					"forward": forward,
					"fromJunctionId": best_u,
					"toJunctionId": nxt_id,
					"lengthPx": seg_len
				}
				if not visited.has(nxt_id):
					queue.append(nxt_id)

	if not prev_step.has(dst_id):
		var msg := "Tidak ada jalur jalan terhubung"
		var b_kind := "no_road"
		var b_tag := "No road"
		var b_edge := ""
		var b_junc := dst_id
		var b_pos: Vector2 = junction_map[dst_id]["pos"] if junction_map.has(dst_id) else Vector2.INF

		if blocked_closed_edge != "" and road_map.has(blocked_closed_edge):
			msg = "Terhalang jalan ditutup (Close Street)"
			b_kind = "closed"
			b_tag = "Closed"
			b_edge = blocked_closed_edge
			var pts_c: PackedVector2Array = road_map[b_edge]["pts"]
			b_pos = pts_c[pts_c.size() / 2] if not pts_c.is_empty() else b_pos
			b_junc = ""
		elif blocked_oneway_edge != "" and road_map.has(blocked_oneway_edge):
			msg = "Terhalang arah jalan satu arah (One-Way)"
			b_kind = "one_way"
			b_tag = "One-way"
			b_edge = blocked_oneway_edge
			var pts_o: PackedVector2Array = road_map[b_edge]["pts"]
			b_pos = pts_o[pts_o.size() / 2] if not pts_o.is_empty() else b_pos
			b_junc = ""
		elif blocked_lanes_junc != "" and junction_map.has(blocked_lanes_junc):
			msg = "Terhalang panah lajur belok (No Turn)"
			b_kind = "no_turn"
			b_tag = "No turn"
			b_edge = blocked_lanes_edge
			b_junc = blocked_lanes_junc
			b_pos = junction_map[b_junc]["pos"]
		elif blocked_light_junc != "" and junction_map.has(blocked_light_junc):
			msg = "Terhalang fase lampu (No Green)"
			b_kind = "no_green"
			b_tag = "No green"
			b_junc = blocked_light_junc
			b_pos = junction_map[b_junc]["pos"]

		return {
			"steps": [],
			"clear_time_sec": 0.0,
			"broken_reason": msg,
			"broken_kind": b_kind,
			"broken_tag": b_tag,
			"broken_edge_id": b_edge,
			"broken_junction_id": b_junc,
			"broken_pos": b_pos
		}

	var rev_steps: Array[Dictionary] = []
	var cur: String = dst_id
	while cur != src_id and prev_step.has(cur):
		rev_steps.append(prev_step[cur])
		cur = String(prev_node[cur])
	rev_steps.reverse()

	return {
		"steps": rev_steps,
		"clear_time_sec": float(dist[dst_id]),
		"broken_reason": "",
		"broken_kind": "",
		"broken_tag": "",
		"broken_edge_id": "",
		"broken_junction_id": "",
		"broken_pos": Vector2.INF
	}
