class_name ParkingLotSystem
extends RefCounted

## Authentic Incremental Traffic v1.4.1 Physical ParkingSpace & ExitRoads System (`parking_space.gd` + `exit_roads.gd`).
## Scaled to `RoadGeom.UNIT_SCALE = 0.20`:
## - Physical asphalt aprons per facility with numbered outdoor stalls `1..4` (`PITCH = 5.6`)
##   and indoor `garage` bay portals `5..8` when `total_bays > 4`.
## - Single-lane gate throat turn-taking by default; 2-lane simultaneous entry/exit when `wideGate > 0`.
## - Smooth cubic Bezier turn-in (`entering_lot`) and turn-out (`leaving_lot`) aisles.
## - Physical one-way rear slip road (`ExitRoad`, `$20,000` buy / `+$10,000` 50% refund) that creates
##   a real road edge + junction in `sim.roads` and converts the main gate to entry-only.

const LOT_SPEED_ENTER: float = 13.5
const LOT_SPEED_EXIT: float = 15.0
const GATE_COOLDOWN_SINGLE: float = 0.65
const GATE_COOLDOWN_WIDE: float = 0.18
const EXIT_ROAD_PRICE: int = 20000
const EXIT_ROAD_REFUND: int = 10000

static func _cubic_bezier_poly(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps: int = 10) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = maxi(3, steps)
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		var u: float = 1.0 - t
		var pt: Vector2 = (u * u * u) * p0 + (3.0 * u * u * t) * p1 + (3.0 * u * t * t) * p2 + (t * t * t) * p3
		if out.is_empty() or out[out.size() - 1].distance_to(pt) > 0.05:
			out.append(pt)
	if out.size() < 2:
		out.append(p3)
	return out

static func build_all_lots(sim) -> void:
	if sim == null:
		return
	for f in sim.facilities:
		build_facility_lot(sim, f)

static func build_facility_lot(sim, f: Dictionary) -> void:
	var fp: Vector2 = f["pos"]
	var exp_scale: float = 1.24 if int(f["upgrades"].get("expand", 0)) > 0 else 1.0
	var total_bays: int = clampi(sim.get_total_bays(f), 1, 8)
	var wide_gate: bool = int(f["upgrades"].get("wideGate", 0)) > 0
	var has_garage: bool = total_bays > 4
	var exit_road_id := String(f.get("exitRoadId", ""))
	var exit_node_id := String(f.get("exitNodeId", ""))
	var has_exit_road: bool = exit_road_id != "" and sim.road_map.has(exit_road_id)

	var j_id := String(f.get("junctionId", f.get("roadNodeId", "")))
	var j_pos: Vector2 = fp + Vector2(0.0, 20.0 * exp_scale)
	if sim.junction_map.has(j_id):
		j_pos = sim.junction_map[j_id]["pos"]

	var exit_j_pos: Vector2 = fp + Vector2(18.0 * exp_scale, -2.5 * exp_scale)
	if has_exit_road and sim.junction_map.has(exit_node_id):
		exit_j_pos = sim.junction_map[exit_node_id]["pos"]

	var apron_center: Vector2 = fp + Vector2(0.0, 10.6 * exp_scale)
	var apron_w: float = 29.0 * exp_scale
	var apron_d: float = 11.6 * exp_scale

	var to_road: Vector2 = (j_pos - apron_center)
	var road_dir: Vector2 = to_road.normalized() if to_road.length() > 0.5 else Vector2(0.0, 1.0)
	var road_perp := Vector2(-road_dir.y, road_dir.x)
	var lht_sign: float = 1.0 if bool(sim.left_hand_traffic) else -1.0

	var gate_base: Vector2 = apron_center + Vector2(0.0, apron_d * 0.48)
	var lane_sep: float = (2.35 if wide_gate else 0.75) * exp_scale
	var gate_entry_pos: Vector2 = gate_base - road_perp * (lane_sep * lht_sign)
	var gate_exit_pos: Vector2 = gate_base + road_perp * (lane_sep * lht_sign)

	# Far rear/side slip gate (`far_gate` in exit_roads.gd)
	var side_sign: float = -1.0 if (j_pos.x - fp.x) > 4.0 else 1.0
	var far_gate_pos: Vector2 = fp + Vector2(side_sign * 15.2 * exp_scale, 3.2 * exp_scale)
	if has_exit_road:
		far_gate_pos = exit_j_pos.lerp(fp + Vector2(0.0, 4.0 * exp_scale), 0.25)

	# Preserve active bay occupancy across rebuilds
	var prev_occ: Dictionary = {}
	var prev_res: Dictionary = {}
	if f.has("parkingLot") and typeof(f["parkingLot"]) == TYPE_DICTIONARY:
		for ob in (f["parkingLot"] as Dictionary).get("bays", []):
			var obi: int = int(ob.get("index", -1))
			if obi >= 0:
				prev_occ[obi] = String(ob.get("occupiedBy", ""))
				prev_res[obi] = String(ob.get("reservedBy", ""))

	var outdoor_cnt: int = mini(total_bays, 4)
	var indoor_cnt: int = maxi(0, total_bays - 4)
	var bays_arr: Array = []

	for bi in range(total_bays):
		var indoor: bool = bi >= 4
		var b_pos: Vector2
		var b_ang: float = -PI * 0.5
		if not indoor:
			var slot_span: float = 20.4 * exp_scale
			var t_x: float = (float(bi) + 0.5) / float(maxi(1, outdoor_cnt)) - 0.5
			b_pos = Vector2(fp.x + t_x * slot_span, fp.y + 9.4 * exp_scale)
			b_ang = -PI * 0.5 + (-0.18 if t_x < 0.0 else 0.18)
		else:
			var gi: int = bi - 4
			var g_span: float = 17.6 * exp_scale
			var gt_x: float = (float(gi) + 0.5) / float(maxi(1, indoor_cnt)) - 0.5
			b_pos = Vector2(fp.x + gt_x * g_span, fp.y + 4.1 * exp_scale)
			b_ang = -PI * 0.5

		var aisle_in := Vector2(lerpf(gate_entry_pos.x, b_pos.x, 0.65), apron_center.y + 2.8 * exp_scale)
		var entry_pts: PackedVector2Array = _cubic_bezier_poly(
			j_pos,
			j_pos.lerp(gate_entry_pos, 0.62),
			aisle_in,
			b_pos,
			10
		)
		var entry_cum: PackedFloat32Array = RoadGeom.build_cum_lengths(entry_pts)
		var entry_len: float = entry_cum[entry_cum.size() - 1] if not entry_cum.is_empty() else 1.0

		var exit_pts: PackedVector2Array
		if has_exit_road:
			var rear_aisle := Vector2(lerpf(b_pos.x, far_gate_pos.x, 0.55), fp.y + 6.4 * exp_scale)
			exit_pts = _cubic_bezier_poly(
				b_pos,
				b_pos + Vector2(0.0, 2.2 * exp_scale),
				rear_aisle,
				exit_j_pos,
				10
			)
		else:
			var aisle_out := Vector2(lerpf(b_pos.x, gate_exit_pos.x, 0.65), apron_center.y + 3.2 * exp_scale)
			exit_pts = _cubic_bezier_poly(
				b_pos,
				aisle_out,
				gate_exit_pos.lerp(j_pos, 0.38),
				j_pos,
				10
			)
		var exit_cum: PackedFloat32Array = RoadGeom.build_cum_lengths(exit_pts)
		var exit_len: float = exit_cum[exit_cum.size() - 1] if not exit_cum.is_empty() else 1.0

		bays_arr.append({
			"index": bi,
			"number": bi + 1,
			"indoor": indoor,
			"pos": b_pos,
			"angle": b_ang,
			"entryPts": entry_pts,
			"entryCum": entry_cum,
			"entryLen": maxf(1.0, entry_len),
			"exitPts": exit_pts,
			"exitCum": exit_cum,
			"exitLen": maxf(1.0, exit_len),
			"occupiedBy": String(prev_occ.get(bi, "")),
			"reservedBy": String(prev_res.get(bi, ""))
		})

	var drv_pts: PackedVector2Array = _cubic_bezier_poly(
		j_pos,
		j_pos.lerp(gate_base, 0.45),
		j_pos.lerp(gate_base, 0.80),
		gate_base,
		6
	)

	f["parkingLot"] = {
		"apronCenter": apron_center,
		"apronSize": Vector2(apron_w, apron_d),
		"gateBase": gate_base,
		"gateEntryPos": gate_entry_pos,
		"gateExitPos": gate_exit_pos,
		"farGatePos": far_gate_pos,
		"drivewayPts": drv_pts,
		"drivewayWidth": (9.2 if wide_gate else 5.8) * exp_scale,
		"wideGate": wide_gate,
		"hasGarage": has_garage,
		"hasExitRoad": has_exit_road,
		"gateCapacity": 2 if wide_gate else 1,
		"gateUsers": {},
		"gateCooldown": 0.0,
		"bays": bays_arr
	}

static func step_lots(sim, dt: float) -> void:
	var valid_ids: Dictionary = {}
	for ag in sim.agents:
		valid_ids[String(ag["id"])] = String(ag["state"])

	for f in sim.facilities:
		var lot: Dictionary = f.get("parkingLot", {})
		if lot.is_empty():
			continue
		lot["gateCooldown"] = maxf(0.0, float(lot.get("gateCooldown", 0.0)) - dt)
		var g_users: Dictionary = lot.get("gateUsers", {})
		var stale_g: Array[String] = []
		for gid in g_users.keys():
			var st := String(valid_ids.get(String(gid), ""))
			if st != "entering_lot" and st != "leaving_lot":
				stale_g.append(String(gid))
		for sg in stale_g:
			g_users.erase(sg)

		for bay in lot.get("bays", []):
			var occ := String(bay.get("occupiedBy", ""))
			if occ != "" and not valid_ids.has(occ):
				bay["occupiedBy"] = ""
			var res := String(bay.get("reservedBy", ""))
			if res != "" and not valid_ids.has(res):
				bay["reservedBy"] = ""

static func find_or_claim_bay(f: Dictionary, agent_id: String) -> int:
	var lot: Dictionary = f.get("parkingLot", {})
	if lot.is_empty():
		return 0
	var bays: Array = lot.get("bays", [])
	if bays.is_empty():
		return 0
	# First check if already claimed by this agent
	for b in bays:
		if String(b.get("occupiedBy", "")) == agent_id or String(b.get("reservedBy", "")) == agent_id:
			b["occupiedBy"] = agent_id
			b["reservedBy"] = ""
			return int(b["index"])
	# Next find first free outdoor stall, then indoor garage stall
	for b in bays:
		var occ := String(b.get("occupiedBy", ""))
		var res := String(b.get("reservedBy", ""))
		if occ == "" and (res == "" or res == agent_id):
			b["occupiedBy"] = agent_id
			b["reservedBy"] = ""
			return int(b["index"])
	return -1

static func release_bay(f: Dictionary, agent_id: String) -> void:
	var lot: Dictionary = f.get("parkingLot", {})
	if lot.is_empty():
		return
	for b in lot.get("bays", []):
		if String(b.get("occupiedBy", "")) == agent_id:
			b["occupiedBy"] = ""
		if String(b.get("reservedBy", "")) == agent_id:
			b["reservedBy"] = ""
	var g_users: Dictionary = lot.get("gateUsers", {})
	g_users.erase(agent_id)

static func can_enter_gate(f: Dictionary, agent_id: String) -> bool:
	var lot: Dictionary = f.get("parkingLot", {})
	if lot.is_empty():
		return true
	var g_users: Dictionary = lot.get("gateUsers", {})
	if g_users.has(agent_id):
		return true
	if float(lot.get("gateCooldown", 0.0)) > 0.01 and not bool(lot.get("wideGate", false)):
		return false
	var cap: int = int(lot.get("gateCapacity", 1))
	if g_users.size() >= cap:
		return false
	# Ensure at least one bay is free before letting truck enter apron
	for b in lot.get("bays", []):
		var occ := String(b.get("occupiedBy", ""))
		var res := String(b.get("reservedBy", ""))
		if occ == agent_id or (occ == "" and (res == "" or res == agent_id)):
			return true
	return false

static func acquire_gate(f: Dictionary, agent_id: String, dir_mode: String) -> void:
	var lot: Dictionary = f.get("parkingLot", {})
	if lot.is_empty():
		return
	var g_users: Dictionary = lot.get("gateUsers", {})
	g_users[agent_id] = dir_mode
	lot["gateCooldown"] = GATE_COOLDOWN_WIDE if bool(lot.get("wideGate", false)) else GATE_COOLDOWN_SINGLE

static func release_gate(f: Dictionary, agent_id: String) -> void:
	var lot: Dictionary = f.get("parkingLot", {})
	if lot.is_empty():
		return
	var g_users: Dictionary = lot.get("gateUsers", {})
	g_users.erase(agent_id)

static func can_exit_gate(f: Dictionary, agent_id: String) -> bool:
	var lot: Dictionary = f.get("parkingLot", {})
	if lot.is_empty():
		return true
	# ExitRoad uses dedicated rear one-way slip gate — zero conflict with main gate!
	if bool(lot.get("hasExitRoad", false)):
		return true
	var g_users: Dictionary = lot.get("gateUsers", {})
	if g_users.has(agent_id):
		return true
	if float(lot.get("gateCooldown", 0.0)) > 0.01 and not bool(lot.get("wideGate", false)):
		return false
	var cap: int = int(lot.get("gateCapacity", 1))
	return g_users.size() < cap

static func find_exit_road_candidate_target(sim, f: Dictionary) -> Dictionary:
	var fp: Vector2 = f["pos"]
	var main_jid := String(f.get("junctionId", f.get("roadNodeId", "")))
	var f_reg: int = int(f.get("regionIndex", 0))
	var best_j: Dictionary = {}
	var best_score: float = INF

	# Prefer downstream junctions used by routes starting from this facility
	var preferred_jids: Dictionary = {}
	for rt in sim.routes:
		if String(rt.get("fromFacilityId", "")) == String(f["id"]) or String(rt.get("toFacilityId", "")) == String(f["id"]):
			var steps: Array = rt.get("forwardPath", []) if String(rt.get("fromFacilityId", "")) == String(f["id"]) else rt.get("returnPath", [])
			for si in range(mini(3, steps.size())):
				preferred_jids[String(steps[si].get("toJunctionId", ""))] = true

	for j in sim.junctions:
		var jid := String(j["id"])
		if jid == main_jid or jid.begins_with("j_exit_"):
			continue
		if not sim.unlocked_regions.has(int(j.get("regionIndex", 0))):
			continue
		# Must have at least 1 built road attached
		var has_built := false
		for r in sim.roads:
			if bool(r["isBuilt"]) and not bool(r["closed"]) and (String(r["from"]) == jid or String(r["to"]) == jid):
				has_built = true
				break
		if not has_built:
			continue
		var d: float = fp.distance_to(j["pos"])
		if d < 16.0 or d > 210.0:
			continue
		var score: float = d
		if preferred_jids.has(jid):
			score *= 0.58
		if int(j.get("regionIndex", 0)) == f_reg:
			score *= 0.85
		if score < best_score:
			best_score = score
			best_j = j

	# Fallback: relax distance if map has sparse rural junctions
	if best_j.is_empty():
		for j in sim.junctions:
			var jid := String(j["id"])
			if jid == main_jid or jid.begins_with("j_exit_"):
				continue
			if not sim.unlocked_regions.has(int(j.get("regionIndex", 0))):
				continue
			var d: float = fp.distance_to(j["pos"])
			if d < best_score:
				best_score = d
				best_j = j
	return best_j

static func build_facility_exit_road(sim, f: Dictionary) -> Dictionary:
	var existing_id := String(f.get("exitRoadId", ""))
	if existing_id != "" and sim.road_map.has(existing_id):
		return sim.road_map[existing_id]

	var target_j: Dictionary = find_exit_road_candidate_target(sim, f)
	if target_j.is_empty():
		return {}

	var fp: Vector2 = f["pos"]
	var exp_scale: float = 1.24 if int(f["upgrades"].get("expand", 0)) > 0 else 1.0
	var tgt_pos: Vector2 = target_j["pos"]
	var side_sign: float = 1.0 if tgt_pos.x >= fp.x else -1.0
	var start_pos: Vector2 = fp + Vector2(side_sign * 15.8 * exp_scale, 2.8 * exp_scale)
	var fid := String(f["id"])
	var j_exit_id := "j_exit_" + fid
	var r_exit_id := "e_exit_" + fid

	if not sim.junction_map.has(j_exit_id):
		var new_j := {
			"id": j_exit_id,
			"x": start_pos.x,
			"y": start_pos.y,
			"pos": start_pos,
			"regionIndex": int(f.get("regionIndex", 0)),
			"control": "none",
			"connectedEdgeIds": [r_exit_id],
			"yieldMinorEdgeIds": [],
			"isExitGate": true
		}
		sim.junctions.append(new_j)
		sim.junction_map[j_exit_id] = new_j
	else:
		var ej_ce: Array = sim.junction_map[j_exit_id].get("connectedEdgeIds", [])
		if not ej_ce.has(r_exit_id):
			ej_ce.append(r_exit_id)

	var tgt_ce: Array = target_j.get("connectedEdgeIds", [])
	if not tgt_ce.has(r_exit_id):
		tgt_ce.append(r_exit_id)

	var mid_dir: Vector2 = (tgt_pos - start_pos)
	var perp := Vector2(-mid_dir.y, mid_dir.x).normalized() * (side_sign * clampf(mid_dir.length() * 0.16, 4.0, 14.0))
	var c1: Vector2 = start_pos + Vector2(side_sign * 8.0, 0.0).lerp(mid_dir * 0.32 + perp, 0.65)
	var c2: Vector2 = start_pos.lerp(tgt_pos, 0.68) + perp * 0.45
	var pts: PackedVector2Array = _cubic_bezier_poly(start_pos, c1, c2, tgt_pos, 12)
	var cum: PackedFloat32Array = RoadGeom.build_cum_lengths(pts)
	var rlen: float = maxf(12.0, cum[cum.size() - 1] if not cum.is_empty() else start_pos.distance_to(tgt_pos))
	var min_x: float = 1e9
	var min_y: float = 1e9
	var max_x: float = -1e9
	var max_y: float = -1e9
	var pts_arr: Array = []
	for p in pts:
		pts_arr.append([p.x, p.y])
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)

	var new_r := {
		"id": r_exit_id,
		"name": "Exit Slip " + String(f.get("name", fid)),
		"from": j_exit_id,
		"to": String(target_j["id"]),
		"points": pts_arr,
		"pts": pts,
		"cum_len": cum,
		"lengthPx": rlen,
		"aabb": Rect2(min_x - 24.0, min_y - 24.0, (max_x - min_x) + 48.0, (max_y - min_y) + 48.0),
		"congestionEMA": 0.0,
		"roadClass": "local",
		"regionIndex": int(f.get("regionIndex", 0)),
		"lanesForward": 1,
		"lanesBackward": 0,
		"approachLanesForward": 1,
		"approachLanesBackward": 0,
		"pocketSize": 0,
		"pocketLevel": 0,
		"turnMaskForward": 7,
		"turnMaskBackward": 7,
		"oneWay": 1,
		"closed": false,
		"isBuilt": true,
		"isBridge": false,
		"elevation": 0,
		"isExitRoad": true,
		"facilityId": fid,
		"trimStart": 2.0,
		"trimEnd": 5.0
	}
	sim.roads.append(new_r)
	sim.road_map[r_exit_id] = new_r
	f["exitRoadId"] = r_exit_id
	f["exitNodeId"] = j_exit_id
	build_facility_lot(sim, f)
	return new_r

static func remove_facility_exit_road(sim, f: Dictionary) -> bool:
	var r_id := String(f.get("exitRoadId", ""))
	var j_id := String(f.get("exitNodeId", ""))
	if r_id == "":
		return false
	for j in sim.junctions:
		var ce: Array = j.get("connectedEdgeIds", [])
		ce.erase(r_id)
		var ym: Array = j.get("yieldMinorEdgeIds", [])
		ym.erase(r_id)
	for i in range(sim.roads.size() - 1, -1, -1):
		if String(sim.roads[i]["id"]) == r_id:
			sim.roads.remove_at(i)
	sim.road_map.erase(r_id)

	for i in range(sim.junctions.size() - 1, -1, -1):
		if String(sim.junctions[i]["id"]) == j_id:
			sim.junctions.remove_at(i)
	sim.junction_map.erase(j_id)

	f["exitRoadId"] = ""
	f["exitNodeId"] = ""
	f["upgrades"]["exitRoad"] = 0
	build_facility_lot(sim, f)
	return true
