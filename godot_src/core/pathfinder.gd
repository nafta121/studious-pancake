class_name RoutePathfinder
extends RefCounted

## Directed road-graph Dijkstra router supporting waypoints, one-way rules,
## closed streets, region locks, Express kinematic clear-time, and Indonesian diagnostics.

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
		return {"steps": [], "clear_time_sec": 2.5, "broken_reason": ""}

	var chain: Array[String] = [start_junction_id]
	for wp in waypoints:
		var wps := String(wp)
		if junction_map.has(wps) and chain[chain.size() - 1] != wps:
			chain.append(wps)
	if chain[chain.size() - 1] != end_junction_id:
		chain.append(end_junction_id)

	var all_steps: Array[Dictionary] = []
	var total_clear_sec: float = 0.0

	for leg_i in range(chain.size() - 1):
		var leg_res: Dictionary = _dijkstra_leg(
			chain[leg_i],
			chain[leg_i + 1],
			junction_map,
			road_map,
			unlocked_regions,
			truck_model_id
		)
		var reason := String(leg_res["broken_reason"])
		if reason != "":
			return {"steps": [], "clear_time_sec": 0.0, "broken_reason": reason}
		for st in leg_res["steps"]:
			all_steps.append(st)
		total_clear_sec += float(leg_res["clear_time_sec"])

	return {
		"steps": all_steps,
		"clear_time_sec": maxf(3.0, total_clear_sec),
		"broken_reason": ""
	}

static func _dijkstra_leg(
	src_id: String,
	dst_id: String,
	junction_map: Dictionary,
	road_map: Dictionary,
	unlocked_regions: Dictionary,
	truck_model_id: String
) -> Dictionary:
	if src_id == dst_id:
		return {"steps": [], "clear_time_sec": 1.0, "broken_reason": ""}
	if not junction_map.has(src_id) or not junction_map.has(dst_id):
		return {"steps": [], "clear_time_sec": 0.0, "broken_reason": "Simpang rute tidak valid"}

	var tdef: Dictionary = GameCatalog.TRUCKS.get(truck_model_id, GameCatalog.TRUCKS["hauler"])
	var max_v: float = float(tdef["max_speed_px"])

	var dist := {src_id: 0.0}
	var prev_node := {}
	var prev_step := {}
	var visited := {}
	var queue: Array[String] = [src_id]

	var blocked_by_oneway: bool = false
	var blocked_by_closed: bool = false

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
				blocked_by_closed = true
				continue

			var forward: bool = String(edge["from"]) == best_u
			var nxt_id: String = String(edge["to"]) if forward else String(edge["from"])
			if not unlocked_regions.has(int(junction_map[nxt_id]["regionIndex"])):
				continue

			var ow: int = int(edge["oneWay"])
			if (forward and ow == -1) or ((not forward) and ow == 1):
				blocked_by_oneway = true
				continue

			var class_factor: float = 1.0
			var rc := String(edge["roadClass"])
			if rc == "toll":
				class_factor = 1.22
			elif rc == "national":
				class_factor = 1.06
			elif rc == "local":
				class_factor = 0.84

			var seg_len: float = float(edge["lengthPx"])
			var travel_sec: float = seg_len / maxf(14.0, max_v * class_factor)
			var j_next: Dictionary = junction_map[nxt_id]
			var ctrl := String(j_next["control"])
			var j_pen: float = 0.55
			if ctrl == "lights":
				var lt: Dictionary = j_next.get("light", {})
				if float(lt.get("phaseAGreen", 10.0)) <= 0.1 or float(lt.get("phaseBGreen", 10.0)) <= 0.1:
					continue
				j_pen = 1.35
			elif ctrl == "roundabout" or ctrl == "roundabout2":
				j_pen = 0.40

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
		if blocked_by_oneway:
			msg = "Terhalang arah jalan satu arah (One-Way)"
		elif blocked_by_closed:
			msg = "Terhalang jalan ditutup (Close Street)"
		return {"steps": [], "clear_time_sec": 0.0, "broken_reason": msg}

	var rev_steps: Array[Dictionary] = []
	var cur: String = dst_id
	while cur != src_id and prev_step.has(cur):
		rev_steps.append(prev_step[cur])
		cur = String(prev_node[cur])
	rev_steps.reverse()

	return {
		"steps": rev_steps,
		"clear_time_sec": float(dist[dst_id]),
		"broken_reason": ""
	}
