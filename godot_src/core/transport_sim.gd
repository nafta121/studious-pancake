class_name TransportSim
extends RefCounted

## Authentic Incremental Traffic v1.4.1 Rail & Maritime Transport Simulation (`train_service.gd` + `ship_service.gd`).
## Scaled to `RoadGeom.UNIT_SCALE = 0.20`:
## - Active `TrainService`: articulated locomotive + `2..5` flatbed cargo wagons (`5x2` cargo cells = 10 slots/wagon)
##   running along `sim.railways`, stopping at unlocked `station` platforms, loading `yardPile` items via `CargoFlights`,
##   and obeying `timetable` wait factors `[1.0, 0.6, 0.3, 0.0]`.
## - Automatic Rail-Road `levelCrossings`: twin flashing red signals + lowering red/white boom barriers (`5.0s` before
##   train arrival until `1.0s` after tail clears) + `crossing_bell` + road traffic stop-line enforcement.
## - Active `ShipService` + River Barges + Movable `basculeBridges`: cargo ships (`40..100` slots, `2..5` holds + V-wakes)
##   docking at `harbour` quays + river cargo barges on major rivers, with movable bascule bridge spans that close road
##   barriers, wait for bridge-deck trucks to clear, raise twin 2.5D bascule leaves (`lift: 0..1`), let vessels pass, and reopen.

const TRAIN_CRUISE_SPEED: float = 46.0 # 230.0 * 0.20
const TRAIN_ACCEL: float = 12.0
const TRAIN_DECEL: float = 16.0
const LOCO_LEN: float = 13.6
const WAGON_LEN: float = 11.8
const WAGON_GAP: float = 1.6
const SLOTS_PER_WAGON: int = 10
const TRAIN_MAX_HOLD_SEC: float = 14.0
const TRAIN_LOAD_INTERVAL: float = 0.16

const SHIP_CRUISE_SPEED: float = 22.0 # 110.0 * 0.20
const SHIP_ACCEL: float = 5.5
const SHIP_DECEL: float = 7.5
const SHIP_HOLD_SEC: float = 14.0
const SHIP_LOAD_INTERVAL: float = 0.14
const BARGE_CRUISE_SPEED: float = 14.5

var rail_lines: Array = []       # {id, pts, cum, length, stations:[{facId, s, pos}], train:Dictionary}
var level_crossings: Array = []  # {id, pos, railIdx, railS, railAngle, roadId, roadS, roadAngle, closed, down, flashPhase, bellCooldown}
var road_crossings_by_edge: Dictionary = {} # roadId -> Array[Dictionary]

var ship_channels: Array = []    # {id, kind:"sea"|"river", pts, cum, length, harbours:[{facId, s, pos}], vessels:Array}
var bascule_bridges: Array = []  # {id, pos, roadId, roadS, spanHalfLen, roadAngle, channelId, channelS, wantOpen, barrierDown, lift, flashPhase}
var bascule_by_edge: Dictionary = {} # roadId -> Array[Dictionary]

func setup(sim) -> void:
	rail_lines.clear()
	level_crossings.clear()
	road_crossings_by_edge.clear()
	ship_channels.clear()
	bascule_bridges.clear()
	bascule_by_edge.clear()
	if sim == null:
		return

	_build_rail_network(sim)
	_build_maritime_and_river_network(sim)

func _build_rail_network(sim) -> void:
	var stations: Array = []
	for f in sim.facilities:
		if String(f.get("kind", "")) == "station":
			stations.append(f)

	for ri in range(sim.railways.size()):
		var rl: Dictionary = sim.railways[ri]
		var pts: PackedVector2Array = rl.get("pts", PackedVector2Array())
		if pts.size() < 2:
			continue
		var cum: PackedFloat32Array = RoadGeom.build_cum_lengths(pts)
		var total_len: float = cum[cum.size() - 1]
		if total_len < 30.0:
			continue

		var stops: Array = []
		for st_f in stations:
			var best_d: float = INF
			var best_s: float = total_len * 0.5
			var best_p: Vector2 = pts[0]
			var fp: Vector2 = st_f["pos"]
			for pi in range(pts.size() - 1):
				var cp: Vector2 = Geometry2D.get_closest_point_to_segment(fp, pts[pi], pts[pi + 1])
				var d: float = fp.distance_to(cp)
				if d < best_d:
					best_d = d
					best_p = cp
					best_s = cum[pi] + pts[pi].distance_to(cp)
			if best_d <= 95.0:
				stops.append({
					"facId": String(st_f["id"]),
					"s": clampf(best_s, 18.0, total_len - 18.0),
					"pos": best_p
				})
		stops.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))

		var line_id := String(rl.get("id", "rail_%d" % ri))
		var init_s: float = -24.0
		if not stops.is_empty():
			init_s = maxf(6.0, float(stops[0]["s"]) - 42.0)

		var train_dict := {
			"id": "train_" + line_id,
			"lineIdx": rail_lines.size(),
			"headS": init_s,
			"speed": TRAIN_CRUISE_SPEED * 0.65,
			"state": "cruising", # cruising | braking | loading | cooldown
			"stopIdx": 0,
			"dwellSec": 0.0,
			"loadTick": 0.0,
			"cooldownSec": 0.0,
			"wagonCount": 2,
			"cargo": [], # Array of good_ids loaded onto flatbeds
			"unitPoses": [] # [{pos, angle, kind, len, cargoSlice}]
		}
		var line_entry := {
			"id": line_id,
			"pts": pts,
			"cum": cum,
			"length": total_len,
			"stations": stops,
			"train": train_dict
		}
		rail_lines.append(line_entry)
		_update_train_poses(sim, line_entry)

	# Detect all rail-road level crossings on ground-level roads (`elevation == 0`)
	var cx_idx: int = 0
	for li in range(rail_lines.size()):
		var ln: Dictionary = rail_lines[li]
		var rpts: PackedVector2Array = ln["pts"]
		var rcum: PackedFloat32Array = ln["cum"]
		for r in sim.roads:
			if int(r.get("elevation", 0)) > 0 or bool(r.get("isExitRoad", false)):
				continue
			# Flyovers / bridges over rail don't have level crossings unless road is municipal/arterial at grade
			if bool(r.get("isBridge", false)) and String(r.get("roadClass", "")) == "toll":
				continue
			var epts: PackedVector2Array = r["pts"]
			var ecum: PackedFloat32Array = r["cum_len"]
			var found_on_edge := false
			for i in range(rpts.size() - 1):
				if found_on_edge:
					break
				for k in range(epts.size() - 1):
					var hit: Variant = Geometry2D.segment_intersects_segment(rpts[i], rpts[i + 1], epts[k], epts[k + 1])
					if hit != null:
						var hp: Vector2 = hit
						var rail_s: float = rcum[i] + rpts[i].distance_to(hp)
						var road_s: float = ecum[k] + epts[k].distance_to(hp)
						if road_s < 5.0 or road_s > float(r["lengthPx"]) - 5.0:
							continue
						cx_idx += 1
						var cx := {
							"id": "lx_%d" % cx_idx,
							"pos": hp,
							"railIdx": li,
							"railS": rail_s,
							"railAngle": (rpts[i + 1] - rpts[i]).angle(),
							"roadId": String(r["id"]),
							"roadS": road_s,
							"roadAngle": (epts[k + 1] - epts[k]).angle(),
							"closed": false,
							"down": 0.0,
							"flashPhase": 0.0,
							"bellCooldown": 0.0
						}
						level_crossings.append(cx)
						var rid := String(r["id"])
						if not road_crossings_by_edge.has(rid):
							road_crossings_by_edge[rid] = []
						(road_crossings_by_edge[rid] as Array).append(cx)
						found_on_edge = true
						break

func _build_maritime_and_river_network(sim) -> void:
	# 1. Sea harbour channels for `harbour` facilities
	var harbours: Array = []
	for f in sim.facilities:
		if String(f.get("kind", "")) == "harbour":
			harbours.append(f)

	for hi in range(harbours.size()):
		var hf: Dictionary = harbours[hi]
		var hp: Vector2 = hf["pos"]
		# Construct smooth offshore -> harbour quay -> offshore shipping channel in water body / bay
		var sea_center: Vector2 = hp + Vector2(0.0, 95.0)
		for wb in sim.water_bodies:
			var pv: PackedVector2Array = wb.get("poly_vec", PackedVector2Array())
			if pv.size() >= 3:
				var c := Vector2.ZERO
				for p in pv:
					c += p
				c /= float(pv.size())
				if c.distance_to(hp) < 260.0:
					sea_center = c
					break
		var out_dir: Vector2 = (sea_center - hp)
		if out_dir.length() < 8.0:
			out_dir = Vector2(0.0, 1.0)
		else:
			out_dir = out_dir.normalized()
		var side_dir := Vector2(-out_dir.y, out_dir.x)
		var quay_pos: Vector2 = hp + out_dir * 20.0
		var p_in: Vector2 = quay_pos - side_dir * 135.0 + out_dir * 62.0
		var p_c1: Vector2 = quay_pos - side_dir * 45.0 + out_dir * 10.0
		var p_c2: Vector2 = quay_pos + side_dir * 45.0 + out_dir * 10.0
		var p_out: Vector2 = quay_pos + side_dir * 135.0 + out_dir * 62.0

		var ch_pts := PackedVector2Array()
		for i in range(21):
			var t: float = float(i) / 20.0
			var pt: Vector2
			if t <= 0.5:
				var u: float = t * 2.0
				pt = ((1.0 - u) * (1.0 - u)) * p_in + (2.0 * (1.0 - u) * u) * p_c1 + (u * u) * quay_pos
			else:
				var u2: float = (t - 0.5) * 2.0
				pt = ((1.0 - u2) * (1.0 - u2)) * quay_pos + (2.0 * (1.0 - u2) * u2) * p_c2 + (u2 * u2) * p_out
			ch_pts.append(pt)
		var ch_cum: PackedFloat32Array = RoadGeom.build_cum_lengths(ch_pts)
		var ch_len: float = ch_cum[ch_cum.size() - 1]
		var stop_s: float = ch_cum[10]
		var ch_id := "sea_" + String(hf["id"])
		var ship_v := {
			"id": "ship_" + String(hf["id"]),
			"kind": "cargo_ship",
			"headS": maxf(8.0, stop_s - 48.0),
			"speed": SHIP_CRUISE_SPEED * 0.75,
			"state": "cruising",
			"stopIdx": 0,
			"dwellSec": 0.0,
			"loadTick": 0.0,
			"cooldownSec": 0.0,
			"holdCount": 2,
			"length": 26.0,
			"width": 7.4,
			"hullColor": Color("2C4E72"),
			"deckColor": Color("D8CFC0"),
			"cargo": [],
			"pos": quay_pos,
			"angle": side_dir.angle(),
			"wakePhase": 0.0
		}
		var ch_dict := {
			"id": ch_id,
			"kind": "sea",
			"pts": ch_pts,
			"cum": ch_cum,
			"length": ch_len,
			"harbours": [{"facId": String(hf["id"]), "s": stop_s, "pos": quay_pos}],
			"vessels": [ship_v]
		}
		ship_channels.append(ch_dict)
		_update_vessel_pose(ch_dict, ship_v)

	# 2. Navigable River Barge Channels + Movable Bascule Bridges on major rivers (`widthPx >= 12`)
	var boat_colors := [Color("3B6E8C"), Color("8C5B4B"), Color("3F7E6A"), Color("6D5E87")]
	var br_idx: int = 0
	for rvi in range(sim.rivers.size()):
		var rv: Dictionary = sim.rivers[rvi]
		var w: float = float(rv.get("widthPx", 8.0))
		var rpts: PackedVector2Array = rv.get("pts", PackedVector2Array())
		if w < 12.0 or rpts.size() < 3:
			continue
		var rcum: PackedFloat32Array = RoadGeom.build_cum_lengths(rpts)
		var rlen: float = rcum[rcum.size() - 1]
		if rlen < 80.0:
			continue
		var ch_id := "river_" + String(rv.get("id", "rv_%d" % rvi))

		# Find road bridges crossing this river -> select primary navigable bridges as movable Bascule Bridges!
		var river_bridges: Array = []
		for r in sim.roads:
			if not bool(r.get("isBridge", false)) or bool(r.get("isExitRoad", false)):
				continue
			var epts: PackedVector2Array = r["pts"]
			var ecum: PackedFloat32Array = r["cum_len"]
			var matched := false
			for i in range(rpts.size() - 1):
				if matched:
					break
				for k in range(epts.size() - 1):
					var hit: Variant = Geometry2D.segment_intersects_segment(rpts[i], rpts[i + 1], epts[k], epts[k + 1])
					if hit != null:
						var hp: Vector2 = hit
						var ch_s: float = rcum[i] + rpts[i].distance_to(hp)
						var rd_s: float = ecum[k] + epts[k].distance_to(hp)
						if rd_s < 7.0 or rd_s > float(r["lengthPx"]) - 7.0:
							continue
						br_idx += 1
						var bb := {
							"id": "bascule_%d" % br_idx,
							"pos": hp,
							"roadId": String(r["id"]),
							"roadS": rd_s,
							"spanHalfLen": 8.5,
							"roadAngle": (epts[k + 1] - epts[k]).angle(),
							"channelId": ch_id,
							"channelS": ch_s,
							"wantOpen": false,
							"barrierDown": 0.0,
							"lift": 0.0,
							"flashPhase": 0.0
						}
						river_bridges.append(bb)
						matched = true
						break

		# Keep up to 2 bascule bridges per navigable river so traffic stays snappy & dramatic
		if river_bridges.size() > 2:
			river_bridges.resize(2)
		for bb in river_bridges:
			bascule_bridges.append(bb)
			var rid := String(bb["roadId"])
			if not bascule_by_edge.has(rid):
				bascule_by_edge[rid] = []
			(bascule_by_edge[rid] as Array).append(bb)

		var start_s: float = rlen * 0.25
		if not river_bridges.is_empty():
			start_s = maxf(10.0, float(river_bridges[0]["channelS"]) - 52.0)

		var barge := {
			"id": "barge_%d" % rvi,
			"kind": "river_barge",
			"headS": start_s,
			"speed": BARGE_CRUISE_SPEED,
			"state": "cruising",
			"stopIdx": -1,
			"dwellSec": 0.0,
			"loadTick": 0.0,
			"cooldownSec": 0.0,
			"holdCount": 2,
			"length": 19.5,
			"width": 5.4,
			"hullColor": boat_colors[rvi % boat_colors.size()],
			"deckColor": Color("E5DEC9"),
			"cargo": ["block", "capsule"],
			"pos": rpts[0],
			"angle": 0.0,
			"wakePhase": float(rvi) * 1.3
		}
		var r_ch := {
			"id": ch_id,
			"kind": "river",
			"pts": rpts,
			"cum": rcum,
			"length": rlen,
			"harbours": [],
			"vessels": [barge]
		}
		ship_channels.append(r_ch)
		_update_vessel_pose(r_ch, barge)

func step(sim, dt: float) -> void:
	if sim == null or dt <= 0.0:
		return
	_step_trains_and_crossings(sim, dt)
	_step_ships_and_bridges(sim, dt)

func _step_trains_and_crossings(sim, dt: float) -> void:
	for ln in rail_lines:
		var tr: Dictionary = ln["train"]
		var stops: Array = ln["stations"]
		# Check if at least one station on this line is unlocked
		var unlocked_stops: Array = []
		for st in stops:
			var sf: Dictionary = sim.facility_map.get(String(st["facId"]), {})
			if not sf.is_empty() and sim.unlocked_regions.has(int(sf.get("regionIndex", 0))):
				unlocked_stops.append(st)

		if unlocked_stops.is_empty():
			continue

		# Sync wagonCount with highest unlocked station `trainLength` upgrade
		var max_tlen_lv: int = 0
		for st in unlocked_stops:
			var sf: Dictionary = sim.facility_map[String(st["facId"])]
			max_tlen_lv = maxi(max_tlen_lv, int(sf["upgrades"].get("trainLength", 0)))
		tr["wagonCount"] = clampi(2 + max_tlen_lv, 2, 5)
		var cap_slots: int = int(tr["wagonCount"]) * SLOTS_PER_WAGON

		var st_mode := String(tr["state"])
		if st_mode == "cooldown":
			tr["cooldownSec"] = float(tr["cooldownSec"]) - dt
			if float(tr["cooldownSec"]) <= 0.0:
				tr["headS"] = -18.0
				tr["speed"] = TRAIN_CRUISE_SPEED * 0.55
				tr["stopIdx"] = 0
				(tr["cargo"] as Array).clear()
				tr["state"] = "cruising"
			continue

		var cur_stop_idx: int = int(tr["stopIdx"])
		var has_next_stop: bool = cur_stop_idx >= 0 and cur_stop_idx < unlocked_stops.size()
		var target_s: float = float(unlocked_stops[cur_stop_idx]["s"]) if has_next_stop else (float(ln["length"]) + 90.0)

		if st_mode == "loading":
			tr["speed"] = 0.0
			tr["dwellSec"] = float(tr["dwellSec"]) + dt
			tr["loadTick"] = float(tr["loadTick"]) + dt
			var st_fac: Dictionary = sim.facility_map.get(String(unlocked_stops[cur_stop_idx]["facId"]), {})
			if not st_fac.is_empty():
				var pile: Array = st_fac.get("yardPile", [])
				var cargo_arr: Array = tr["cargo"]
				while float(tr["loadTick"]) >= TRAIN_LOAD_INTERVAL and not pile.is_empty() and cargo_arr.size() < cap_slots:
					tr["loadTick"] = float(tr["loadTick"]) - TRAIN_LOAD_INTERVAL
					var item: Variant = pile.pop_front()
					var gid: String = String((item as Dictionary).get("good", "dot")) if typeof(item) == TYPE_DICTIONARY else String(item)
					var slots_used: int = maxi(1, int(GameCatalog.GOODS.get(gid, {"slots": 1})["slots"]))
					for _si in range(mini(slots_used, cap_slots - cargo_arr.size())):
						cargo_arr.append(gid)
					# Visual CargoFlight from station platform onto flatbed wagon!
					var wagon_i: int = mini(int(tr["wagonCount"]) - 1, cargo_arr.size() / SLOTS_PER_WAGON)
					var dst_pos: Vector2 = st_fac["pos"]
					var poses: Array = tr.get("unitPoses", [])
					if wagon_i + 1 < poses.size():
						dst_pos = poses[wagon_i + 1]["pos"]
					sim.launch_cargo_hop(gid, st_fac["pos"] + Vector2(0.0, -5.0), dst_pos)

				var tt_lv: int = clampi(int(st_fac["upgrades"].get("timetable", 0)), 0, GameCatalog.TIMETABLE_WAIT_FACTORS.size() - 1)
				var wait_limit: float = TRAIN_MAX_HOLD_SEC * float(GameCatalog.TIMETABLE_WAIT_FACTORS[tt_lv])
				var min_stop: float = 1.4
				var full_now: bool = (tr["cargo"] as Array).size() >= cap_slots
				var yard_empty: bool = pile.is_empty()
				if float(tr["dwellSec"]) >= min_stop and (full_now or float(tr["dwellSec"]) >= maxf(min_stop, wait_limit) or (tt_lv >= 3 and yard_empty)):
					tr["stopIdx"] = cur_stop_idx + 1
					tr["state"] = "cruising"
					if sim.sfx != null:
						sim.sfx.play_train_depart()
			else:
				tr["stopIdx"] = cur_stop_idx + 1
				tr["state"] = "cruising"
		else:
			var dist_to_stop: float = target_s - float(tr["headS"])
			var v: float = float(tr["speed"])
			if has_next_stop and dist_to_stop <= 0.6:
				tr["headS"] = target_s
				tr["speed"] = 0.0
				tr["dwellSec"] = 0.0
				tr["loadTick"] = 0.0
				tr["state"] = "loading"
			else:
				var desired_v: float = TRAIN_CRUISE_SPEED
				if has_next_stop and dist_to_stop > 0.0:
					var brake_v: float = sqrt(2.0 * TRAIN_DECEL * maxf(0.0, dist_to_stop))
					desired_v = minf(desired_v, maxf(3.5, brake_v))
				if v < desired_v:
					v = minf(desired_v, v + TRAIN_ACCEL * dt)
				else:
					v = maxf(desired_v, v - TRAIN_DECEL * dt)
				tr["speed"] = v
				tr["headS"] = float(tr["headS"]) + v * dt
				var total_train_len: float = LOCO_LEN + float(int(tr["wagonCount"])) * (WAGON_LEN + WAGON_GAP)
				if float(tr["headS"]) - total_train_len > float(ln["length"]) + 32.0:
					tr["state"] = "cooldown"
					tr["cooldownSec"] = 10.0

		_update_train_poses(sim, ln)

	# Update all rail-road level crossings (`5.0s` advance close, `1.0s` tail clearance)
	for cx in level_crossings:
		var li: int = int(cx["railIdx"])
		var want_closed := false
		if li >= 0 and li < rail_lines.size():
			var ln: Dictionary = rail_lines[li]
			var tr: Dictionary = ln["train"]
			if String(tr["state"]) != "cooldown":
				var head_s: float = float(tr["headS"])
				var train_len: float = LOCO_LEN + float(int(tr["wagonCount"])) * (WAGON_LEN + WAGON_GAP)
				var tail_s: float = head_s - train_len
				var v_ref: float = maxf(float(tr["speed"]), 12.0)
				var warn_dist: float = clampf(v_ref * 5.0, 36.0, 230.0)
				var cx_s: float = float(cx["railS"])
				# Close if train front is within `warn_dist` ahead of crossing AND tail hasn't cleared `cx_s + 12.0`
				if head_s >= cx_s - warn_dist and tail_s <= cx_s + 12.0:
					want_closed = true

		cx["closed"] = want_closed
		var cur_down: float = float(cx["down"])
		if want_closed:
			cx["down"] = minf(1.0, cur_down + dt * 2.2)
			cx["flashPhase"] = fmod(float(cx["flashPhase"]) + dt * 2.6, 1.0)
			cx["bellCooldown"] = float(cx["bellCooldown"]) - dt
			if float(cx["bellCooldown"]) <= 0.0:
				cx["bellCooldown"] = 0.55
				if sim.sfx != null:
					sim.sfx.play_crossing_bell(cx["pos"])
		else:
			cx["down"] = maxf(0.0, cur_down - dt * 1.9)

func _update_train_poses(_sim, ln: Dictionary) -> void:
	var tr: Dictionary = ln["train"]
	var pts: PackedVector2Array = ln["pts"]
	var cum: PackedFloat32Array = ln["cum"]
	var poses: Array = []
	if String(tr["state"]) == "cooldown":
		tr["unitPoses"] = poses
		return
	var head_s: float = float(tr["headS"])
	var loco_center_s: float = head_s - LOCO_LEN * 0.5
	var lp: Dictionary = RoadGeom.sample_polyline_pose_clamped(pts, cum, loco_center_s)
	poses.append({
		"kind": "loco",
		"pos": lp["pos"],
		"angle": float(lp["angle"]),
		"len": LOCO_LEN,
		"cargo": []
	})
	var cargo_all: Array = tr["cargo"]
	var w_cnt: int = int(tr["wagonCount"])
	var cursor_s: float = head_s - LOCO_LEN
	for wi in range(w_cnt):
		cursor_s -= (WAGON_GAP + WAGON_LEN * 0.5)
		var wp: Dictionary = RoadGeom.sample_polyline_pose_clamped(pts, cum, cursor_s)
		var c_start: int = wi * SLOTS_PER_WAGON
		var c_slice: Array = []
		for ci in range(c_start, mini(cargo_all.size(), c_start + SLOTS_PER_WAGON)):
			c_slice.append(cargo_all[ci])
		poses.append({
			"kind": "wagon",
			"pos": wp["pos"],
			"angle": float(wp["angle"]),
			"len": WAGON_LEN,
			"cargo": c_slice
		})
		cursor_s -= WAGON_LEN * 0.5
	tr["unitPoses"] = poses

func _step_ships_and_bridges(sim, dt: float) -> void:
	# Reset wantOpen flags on bascule bridges; vessels will assert them below
	var bridge_map_by_channel: Dictionary = {}
	for bb in bascule_bridges:
		bb["wantOpen"] = false
		var cid := String(bb["channelId"])
		if not bridge_map_by_channel.has(cid):
			bridge_map_by_channel[cid] = []
		(bridge_map_by_channel[cid] as Array).append(bb)

	for ch in ship_channels:
		var cid := String(ch["id"])
		var ch_len: float = float(ch["length"])
		var harbours: Array = ch["harbours"]
		var ch_bridges: Array = bridge_map_by_channel.get(cid, [])

		for vs in ch["vessels"]:
			vs["wakePhase"] = fmod(float(vs.get("wakePhase", 0.0)) + dt * 1.8, 100.0)
			var is_sea: bool = String(ch["kind"]) == "sea"
			var unlocked_harbours: Array = []
			for hb in harbours:
				var hf: Dictionary = sim.facility_map.get(String(hb["facId"]), {})
				if not hf.is_empty() and sim.unlocked_regions.has(int(hf.get("regionIndex", 0))):
					unlocked_harbours.append(hb)
			if is_sea and unlocked_harbours.is_empty():
				continue

			if is_sea:
				var hf0: Dictionary = sim.facility_map[String(unlocked_harbours[0]["facId"])]
				var sz_lv: int = clampi(int(hf0["upgrades"].get("shipSize", 0)), 0, 3)
				vs["holdCount"] = 2 + sz_lv # 2..5 holds
				vs["length"] = 24.0 + float(sz_lv) * 4.5

			var st_mode := String(vs["state"])
			if st_mode == "cooldown":
				vs["cooldownSec"] = float(vs["cooldownSec"]) - dt
				if float(vs["cooldownSec"]) <= 0.0:
					vs["headS"] = -12.0
					vs["speed"] = (SHIP_CRUISE_SPEED if is_sea else BARGE_CRUISE_SPEED) * 0.65
					vs["stopIdx"] = 0 if is_sea else -1
					if is_sea:
						(vs["cargo"] as Array).clear()
					vs["state"] = "cruising"
				continue

			var v_len: float = float(vs["length"])
			var head_s: float = float(vs["headS"])
			var stern_s: float = head_s - v_len

			# Check upcoming bascule bridges along this channel
			var bridge_stop_s: float = INF
			for bb in ch_bridges:
				var bs: float = float(bb["channelS"])
				if head_s >= bs - 58.0 and stern_s <= bs + 12.0:
					bb["wantOpen"] = true
					if float(bb["lift"]) < 0.88 and head_s < bs - 4.0:
						bridge_stop_s = minf(bridge_stop_s, bs - 11.0)

			var stop_idx: int = int(vs["stopIdx"])
			var has_harbour_stop: bool = is_sea and stop_idx >= 0 and stop_idx < unlocked_harbours.size()
			var quay_s: float = float(unlocked_harbours[stop_idx]["s"]) if has_harbour_stop else INF

			if st_mode == "loading" and has_harbour_stop:
				vs["speed"] = 0.0
				vs["dwellSec"] = float(vs["dwellSec"]) + dt
				vs["loadTick"] = float(vs["loadTick"]) + dt
				var hf_cur: Dictionary = sim.facility_map.get(String(unlocked_harbours[stop_idx]["facId"]), {})
				if not hf_cur.is_empty():
					var sz_lv2: int = clampi(int(hf_cur["upgrades"].get("shipSize", 0)), 0, GameCatalog.HARBOUR_CAPACITIES.size() - 1)
					var cap_slots: int = int(GameCatalog.HARBOUR_CAPACITIES[sz_lv2])
					var pile: Array = hf_cur.get("yardPile", [])
					var c_arr: Array = vs["cargo"]
					while float(vs["loadTick"]) >= SHIP_LOAD_INTERVAL and not pile.is_empty() and c_arr.size() < cap_slots:
						vs["loadTick"] = float(vs["loadTick"]) - SHIP_LOAD_INTERVAL
						var item: Variant = pile.pop_front()
						var gid: String = String((item as Dictionary).get("good", "dot")) if typeof(item) == TYPE_DICTIONARY else String(item)
						var sl: int = maxi(1, int(GameCatalog.GOODS.get(gid, {"slots": 1})["slots"]))
						for _si in range(mini(sl, cap_slots - c_arr.size())):
							c_arr.append(gid)
						sim.launch_cargo_hop(gid, hf_cur["pos"] + Vector2(0.0, 4.0), vs["pos"])

					var full_ship: bool = c_arr.size() >= cap_slots
					if float(vs["dwellSec"]) >= 1.8 and (full_ship or float(vs["dwellSec"]) >= SHIP_HOLD_SEC or (pile.is_empty() and float(vs["dwellSec"]) >= 5.5)):
						vs["stopIdx"] = stop_idx + 1
						vs["state"] = "cruising"
						if sim.sfx != null:
							sim.sfx.play_ship_horn()
				else:
					vs["stopIdx"] = stop_idx + 1
					vs["state"] = "cruising"
			else:
				var cruise_max: float = SHIP_CRUISE_SPEED if is_sea else BARGE_CRUISE_SPEED
				var desired_v: float = cruise_max
				if bridge_stop_s < INF:
					var d_br: float = maxf(0.0, bridge_stop_s - head_s)
					desired_v = minf(desired_v, sqrt(2.0 * SHIP_DECEL * d_br))
				if has_harbour_stop:
					var d_q: float = quay_s - head_s
					if d_q <= 0.6:
						vs["headS"] = quay_s
						vs["speed"] = 0.0
						vs["dwellSec"] = 0.0
						vs["loadTick"] = 0.0
						vs["state"] = "loading"
						_update_vessel_pose(ch, vs)
						continue
					desired_v = minf(desired_v, maxf(2.6, sqrt(2.0 * SHIP_DECEL * maxf(0.0, d_q))))

				var cur_v: float = float(vs["speed"])
				if cur_v < desired_v:
					cur_v = minf(desired_v, cur_v + SHIP_ACCEL * dt)
				else:
					cur_v = maxf(desired_v, cur_v - SHIP_DECEL * dt)
				vs["speed"] = cur_v
				vs["headS"] = head_s + cur_v * dt
				if float(vs["headS"]) - v_len > ch_len + 24.0:
					vs["state"] = "cooldown"
					vs["cooldownSec"] = 12.0 if is_sea else 16.0
			_update_vessel_pose(ch, vs)

	# Step movable Bascule Bridges with mutual road-deck clearance interlock!
	for bb in bascule_bridges:
		var want: bool = bool(bb["wantOpen"])
		var b_down: float = float(bb["barrierDown"])
		var lift: float = float(bb["lift"])
		if want:
			bb["flashPhase"] = fmod(float(bb["flashPhase"]) + dt * 2.2, 1.0)
			b_down = minf(1.0, b_down + dt * 2.0)
			if b_down >= 0.92 and not _any_truck_on_bridge_span(sim, bb):
				lift = minf(1.0, lift + dt * 0.95)
		else:
			lift = maxf(0.0, lift - dt * 0.95)
			if lift <= 0.04:
				b_down = maxf(0.0, b_down - dt * 2.0)
		bb["barrierDown"] = b_down
		bb["lift"] = lift

func _update_vessel_pose(ch: Dictionary, vs: Dictionary) -> void:
	var pts: PackedVector2Array = ch["pts"]
	var cum: PackedFloat32Array = ch["cum"]
	var center_s: float = float(vs["headS"]) - float(vs["length"]) * 0.5
	var p: Dictionary = RoadGeom.sample_polyline_pose_clamped(pts, cum, center_s)
	vs["pos"] = p["pos"]
	vs["angle"] = float(p["angle"])

func _any_truck_on_bridge_span(sim, bb: Dictionary) -> bool:
	var rid := String(bb["roadId"])
	var bpos: Vector2 = bb["pos"]
	var half_w: float = float(bb["spanHalfLen"]) + 4.5
	for ag in sim.agents:
		var st_s := String(ag.get("state", ""))
		if st_s != "driving_outbound" and st_s != "driving_return" and st_s != "driving_to_depot" and st_s != "driving_from_depot":
			continue
		var st: Dictionary = sim._get_agent_current_step(ag)
		if st.is_empty() or String(st.get("edgeId", "")) != rid:
			continue
		if (ag["pos"] as Vector2).distance_to(bpos) <= half_w:
			return true
		for up in ag.get("unitPoses", []):
			if (up["pos"] as Vector2).distance_to(bpos) <= half_w:
				return true
	return false

## Returns `{stop_s, reason, pos}` in trajectory `sPx` space (subtracting `trim_in`), or `{stop_s: INF}` if clear.
func get_road_hazard_info(sim, road_id: String, dir_forward: bool, cur_s: float, trim_in: float = 0.0) -> Dictionary:
	if not sim.road_map.has(road_id):
		return {"stop_s": INF, "reason": "none", "pos": Vector2.ZERO}
	var rlen: float = float(sim.road_map[road_id]["lengthPx"])
	var best_stop: float = INF
	var best_reason := "none"
	var best_pos := Vector2.ZERO

	if road_crossings_by_edge.has(road_id):
		for cx in road_crossings_by_edge[road_id]:
			if not bool(cx["closed"]) and float(cx["down"]) < 0.15:
				continue
			var cx_edge_s: float = float(cx["roadS"]) if dir_forward else (rlen - float(cx["roadS"]))
			var stop_s: float = maxf(0.5, (cx_edge_s - trim_in) - 5.2)
			if stop_s >= cur_s - 1.5 and stop_s < best_stop:
				best_stop = stop_s
				best_reason = "rail_crossing"
				best_pos = cx["pos"]

	if bascule_by_edge.has(road_id):
		for bb in bascule_by_edge[road_id]:
			if not bool(bb["wantOpen"]) and float(bb["barrierDown"]) < 0.12 and float(bb["lift"]) < 0.05:
				continue
			var bb_edge_s: float = float(bb["roadS"]) if dir_forward else (rlen - float(bb["roadS"]))
			var stop_s2: float = maxf(0.5, (bb_edge_s - trim_in) - float(bb["spanHalfLen"]) - 4.0)
			if stop_s2 >= cur_s - 1.5 and stop_s2 < best_stop:
				best_stop = stop_s2
				best_reason = "bascule_bridge"
				best_pos = bb["pos"]

	return {"stop_s": best_stop, "reason": best_reason, "pos": best_pos}

func get_road_hazard_stop_s(sim, road_id: String, dir_forward: bool, cur_s: float, trim_in: float = 0.0) -> float:
	return float(get_road_hazard_info(sim, road_id, dir_forward, cur_s, trim_in)["stop_s"])

