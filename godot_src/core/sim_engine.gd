class_name SimEngine
extends Node

## Core deterministic simulation engine for Incremental Traffic: Karesidenan Madiun.
## Decouples fixed-step micro-agent physics from render framerate for smooth 60-120 FPS on Android.

signal map_static_dirty
signal region_unlocked(region_name: String, subtitle: String)
signal banner_notify(title: String, subtitle: String, accent: Color)

const HOLD_REQUIRED_SEC: float = 30.0
const SIM_DT: float = 1.0 / 30.0

var sfx: SfxSynth
var maps_list: Array = []
var current_map_id: String = "karisidenan_madiun"
var map_def: Dictionary = {}

var regions: Array = []
var junctions: Array = []
var roads: Array = []
var road_offers: Array = []
var facilities: Array = []
var buildings: Array = []
var water_bodies: Array = []
var rivers: Array = []
var railways: Array = []
var patches: Array = []

var junction_map: Dictionary = {}
var road_map: Dictionary = {}
var facility_map: Dictionary = {}
var unlocked_regions: Dictionary = {} # int -> true

var routes: Array = []
var agents: Array = []
var unlocked_licenses: Dictionary = {"hauler": true}

var cash: int = 3500
var real_time_sec: float = 0.0
var speed_multiplier: int = 1 # 0, 1, 2, 4
var night_mode: bool = false
var auto_day_night: bool = false
var day_clock_01: float = 0.35
var left_hand_traffic: bool = true
var boomtown_level: int = 0
var disable_persistence: bool = false

# Telemetry windows
var cash_history: Array[int] = [3500]
var revenue_events: Array = []
var upkeep_events: Array = []
var flow_edges: Dictionary = {} # "from->to->good" : {fromId, toId, good, times: Array[float]}
var floating_toasts: Array = []

var _uid_counter: int = 100
var _sim_accum: float = 0.0
var _upkeep_timer: float = 0.0
var _history_timer: float = 0.0

func initialize(sfx_node: SfxSynth, initial_map: String = "karisidenan_madiun", load_save: bool = true) -> void:
	sfx = sfx_node
	_load_maps_bundle()
	load_map(initial_map, load_save)

func _load_maps_bundle() -> void:
	var f := FileAccess.open("res://data/madiun_maps.json", FileAccess.READ)
	if f == null:
		push_error("Failed to open res://data/madiun_maps.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("maps"):
		maps_list = (parsed as Dictionary)["maps"]

func _next_uid(prefix: String) -> String:
	_uid_counter += 1
	return "%s_%d" % [prefix, _uid_counter]

func load_map(map_id: String, try_restore: bool = true) -> void:
	var template: Dictionary = {}
	for m in maps_list:
		if String(m["id"]) == map_id:
			template = m
			break
	if template.is_empty() and not maps_list.is_empty():
		template = maps_list[0]
	if template.is_empty():
		return

	map_def = template.duplicate(true)
	current_map_id = String(map_def["id"])
	regions = map_def["regions"]
	junctions = map_def["junctions"]
	roads = map_def["roads"]
	road_offers = map_def["roadOffers"]
	facilities = map_def["facilities"]
	buildings = map_def["buildings"]
	water_bodies = map_def["waterBodies"]
	rivers = map_def["rivers"]
	railways = map_def["railways"]
	patches = map_def["patches"]
	left_hand_traffic = bool(map_def.get("leftHandTrafficDefault", true))

	_hydrate_geometry()
	_rebuild_lookups()

	routes.clear()
	agents.clear()
	unlocked_licenses = {"hauler": true}
	cash = 3500
	real_time_sec = 0.0
	boomtown_level = 0
	cash_history = [3500]
	revenue_events.clear()
	upkeep_events.clear()
	flow_edges.clear()
	floating_toasts.clear()
	_uid_counter = 100

	if try_restore and not disable_persistence and _restore_save(current_map_id):
		recompute_all_routes()
		map_static_dirty.emit()
		return

	_seed_starter_routes()
	map_static_dirty.emit()

func _hydrate_geometry() -> void:
	for reg in regions:
		var poly_arrays: Array[PackedVector2Array] = []
		var min_x: float = 1e9
		var min_y: float = 1e9
		var max_x: float = -1e9
		var max_y: float = -1e9
		for ring in reg["polygons"]:
			var pv := PackedVector2Array()
			for pt in ring:
				var vx: float = float(pt[0])
				var vy: float = float(pt[1])
				pv.append(Vector2(vx, vy))
				min_x = minf(min_x, vx)
				min_y = minf(min_y, vy)
				max_x = maxf(max_x, vx)
				max_y = maxf(max_y, vy)
			if pv.size() >= 3:
				poly_arrays.append(pv)
		reg["poly_vecs"] = poly_arrays
		reg["center_vec"] = Vector2(float(reg["center"][0]), float(reg["center"][1]))
		reg["aabb"] = Rect2(min_x, min_y, maxf(1.0, max_x - min_x), maxf(1.0, max_y - min_y))
		reg["holdSeconds"] = float(reg.get("holdSeconds", 0.0))

	for wb in water_bodies:
		var pv := PackedVector2Array()
		for pt in wb["polygon"]:
			pv.append(Vector2(float(pt[0]), float(pt[1])))
		wb["poly_vec"] = pv

	for rv in rivers:
		var pv := PackedVector2Array()
		for pt in rv["points"]:
			pv.append(Vector2(float(pt[0]), float(pt[1])))
		rv["pts"] = pv

	for rl in railways:
		var pv := PackedVector2Array()
		for pt in rl["points"]:
			pv.append(Vector2(float(pt[0]), float(pt[1])))
		rl["pts"] = pv

	for j in junctions:
		j["pos"] = Vector2(float(j["x"]), float(j["y"]))
		if String(j["control"]) == "lights" and not j.has("light"):
			j["light"] = _make_default_light()
		elif j.has("light") and j["light"] != null:
			var lt: Dictionary = j["light"]
			lt["currentPhase"] = int(lt.get("currentPhase", 0))
			lt["stage"] = String(lt.get("stage", "green"))
			lt["timer"] = float(lt.get("timer", 10.0))
			lt["greenElapsed"] = float(lt.get("greenElapsed", 0.0))
			lt["lastDetectorHit"] = float(lt.get("lastDetectorHit", 0.0))

	for r in roads:
		var pv := PackedVector2Array()
		var min_x: float = 1e9
		var min_y: float = 1e9
		var max_x: float = -1e9
		var max_y: float = -1e9
		for pt in r["points"]:
			var vx: float = float(pt[0])
			var vy: float = float(pt[1])
			pv.append(Vector2(vx, vy))
			min_x = minf(min_x, vx)
			min_y = minf(min_y, vy)
			max_x = maxf(max_x, vx)
			max_y = maxf(max_y, vy)
		r["pts"] = pv
		r["cum_len"] = RoadGeom.build_cum_lengths(pv)
		var total_l: float = r["cum_len"][r["cum_len"].size() - 1] if r["cum_len"].size() > 0 else float(r["lengthPx"])
		r["lengthPx"] = maxf(8.0, total_l)
		r["aabb"] = Rect2(min_x - 24.0, min_y - 24.0, (max_x - min_x) + 48.0, (max_y - min_y) + 48.0)
		r["congestionEMA"] = float(r.get("congestionEMA", 0.0))

	for f in facilities:
		f["pos"] = Vector2(float(f["x"]), float(f["y"]))
		f["color_val"] = Color(String(f.get("color", "#4ea854")))
		f["roof_val"] = Color(String(f.get("roofColor", "#3a7d40")))
		if not f.has("inputBuffers") or typeof(f["inputBuffers"]) != TYPE_DICTIONARY:
			f["inputBuffers"] = {}
		if not f.has("deliveredWindow") or typeof(f["deliveredWindow"]) != TYPE_DICTIONARY:
			f["deliveredWindow"] = {}
		f["outputBuffer"] = int(f.get("outputBuffer", 2 if String(f["kind"]) == "supplier" else 0))
		f["prodProgress"] = float(f.get("prodProgress", 0.0))
		f["stalledReason"] = String(f.get("stalledReason", "none"))
		f["occupiedBays"] = 0
		var kind_s := String(f["kind"])
		f["vehiclePresent"] = true
		f["vehicleTimer"] = 18.0
		f["vehicleCapacityRemaining"] = 40 if kind_s == "harbour" else 20

func _make_default_light() -> Dictionary:
	return {
		"phaseAGreen": 10.0,
		"phaseBGreen": 10.0,
		"yellow": 1.0,
		"allRed": 0.8,
		"actuated": true,
		"sensorGap": 1.5,
		"currentPhase": 0,
		"stage": "green",
		"timer": 10.0,
		"greenElapsed": 0.0,
		"lastDetectorHit": 0.0
	}

func _rebuild_lookups() -> void:
	junction_map.clear()
	road_map.clear()
	facility_map.clear()
	unlocked_regions.clear()
	for reg in regions:
		if bool(reg["unlocked"]):
			unlocked_regions[int(reg["index"])] = true
	for j in junctions:
		junction_map[String(j["id"])] = j
	for r in roads:
		road_map[String(r["id"])] = r
	for f in facilities:
		facility_map[String(f["id"])] = f

func _seed_starter_routes() -> void:
	var r0_facs: Array = []
	for f in facilities:
		if int(f["regionIndex"]) == 0:
			r0_facs.append(f)

	var dot_sup: Dictionary = {}
	var wedge_sup: Dictionary = {}
	var caps_fac: Dictionary = {}
	var hub_fac: Dictionary = {}

	for f in r0_facs:
		var k := String(f["kind"])
		var out_g := String(f["outputGood"]) if f["outputGood"] != null else ""
		if k == "supplier" and out_g == "dot" and dot_sup.is_empty():
			dot_sup = f
		elif k == "supplier" and wedge_sup.is_empty():
			wedge_sup = f
		elif k == "factory" and out_g == "capsule" and caps_fac.is_empty():
			caps_fac = f
		elif (k == "station" or k == "harbour" or k == "market") and hub_fac.is_empty():
			hub_fac = f

	if not dot_sup.is_empty() and not caps_fac.is_empty():
		var rt1: Dictionary = create_route(String(dot_sup["id"]), String(caps_fac["id"]), "dot", false)
		if not rt1.is_empty():
			add_truck_to_route(String(rt1["id"]), true)
			add_truck_to_route(String(rt1["id"]), true)
	if not caps_fac.is_empty() and not hub_fac.is_empty():
		caps_fac["outputBuffer"] = 2
		var rt2: Dictionary = create_route(String(caps_fac["id"]), String(hub_fac["id"]), "capsule", false)
		if not rt2.is_empty():
			add_truck_to_route(String(rt2["id"]), true)
	elif not wedge_sup.is_empty() and not hub_fac.is_empty():
		var rt3: Dictionary = create_route(String(wedge_sup["id"]), String(hub_fac["id"]), "any", false)
		if not rt3.is_empty():
			add_truck_to_route(String(rt3["id"]), true)

# === ECONOMY & UPGRADE HELPERS ===

func get_owned_count_by_model(model_id: String) -> int:
	var c: int = 0
	for a in agents:
		if String(a["model"]) == model_id:
			c += 1
	return c

func get_next_truck_price(model_id: String) -> int:
	return GameCatalog.compute_truck_buy_price(model_id, get_owned_count_by_model(model_id), agents.size())

func get_capacity_slots(f: Dictionary) -> int:
	var up: Dictionary = f["upgrades"]
	var lvl: int = clampi(int(up.get("buffer", 0)), 0, GameCatalog.BUFFER_CAPACITIES.size() - 1)
	return GameCatalog.BUFFER_CAPACITIES[lvl]

func get_total_bays(f: Dictionary) -> int:
	return 1 + int(f["upgrades"].get("bays", 0))

func get_supplier_rate_per_min(f: Dictionary) -> int:
	var up: Dictionary = f["upgrades"]
	var base: int = int(ceil(6.0 * pow(1.25, float(up.get("rate", 0)))))
	return int(round(float(base) * 1.61)) if int(up.get("expand", 0)) > 0 else base

func get_factory_output_per_min(f: Dictionary) -> float:
	if f["outputGood"] == null:
		return 0.0
	var gid := String(f["outputGood"])
	if not GameCatalog.GOODS.has(gid):
		return 0.0
	var g: Dictionary = GameCatalog.GOODS[gid]
	var total_in: int = 0
	for inp in g["inputs"]:
		total_in += int(inp["qty"])
	total_in = maxi(1, total_in)
	var s_lvl: int = clampi(int(f["upgrades"].get("speed", 0)), 0, GameCatalog.FACTORY_SPEED_SHAPES_PER_MIN.size() - 1)
	return snappedf(float(GameCatalog.FACTORY_SPEED_SHAPES_PER_MIN[s_lvl]) / float(total_in), 0.1)

func get_facility_upgrades(f: Dictionary) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var up: Dictionary = f["upgrades"]
	var kind_s := String(f["kind"])

	if kind_s == "supplier":
		var r_lvl: int = int(up.get("rate", 0))
		list.append({
			"track": "rate", "label": "Laju Hulu (Rate)",
			"desc": "%d unit/mnt (×1.25)" % get_supplier_rate_per_min(f),
			"level": r_lvl, "max": 10,
			"price": GameCatalog.round_2sig(600.0 * pow(1.45, float(r_lvl))),
			"locked": "Maks" if r_lvl >= 10 else ""
		})
		var e_lvl: int = int(up.get("expand", 0))
		list.append({
			"track": "expand", "label": "Perluasan Lahan",
			"desc": "Output hulu ×1.61 permanen",
			"level": e_lvl, "max": 1, "price": 80000,
			"locked": "Maks" if e_lvl >= 1 else ("Butuh Rate Lv.6" if r_lvl < 6 else "")
		})
		var b_lvl: int = int(up.get("buffer", 0))
		list.append({
			"track": "buffer", "label": "Gudang Hulu",
			"desc": "Kapasitas %d slot" % get_capacity_slots(f),
			"level": b_lvl, "max": 4,
			"price": GameCatalog.round_2sig(300.0 * pow(4.0, float(b_lvl))),
			"locked": "Maks" if b_lvl >= 4 else ""
		})
	elif kind_s == "factory":
		var gid: String = String(f["outputGood"]) if f["outputGood"] != null else "capsule"
		var tier: int = int(GameCatalog.GOODS.get(gid, {"tier": 2})["tier"])
		var tf: float = 3.0 if tier >= 4 else (2.0 if tier == 3 else 1.0)
		var s_lvl: int = int(up.get("speed", 0))
		list.append({
			"track": "speed", "label": "Kecepatan Olah",
			"desc": "Output %.1f unit/mnt" % get_factory_output_per_min(f),
			"level": s_lvl, "max": 12,
			"price": GameCatalog.round_2sig(400.0 * pow(1.5, float(s_lvl)) * tf),
			"locked": "Maks" if s_lvl >= 12 else ""
		})
		var b_lvl: int = int(up.get("buffer", 0))
		list.append({
			"track": "buffer", "label": "Gudang Pabrik",
			"desc": "Kapasitas %d slot" % get_capacity_slots(f),
			"level": b_lvl, "max": 4,
			"price": GameCatalog.round_2sig(300.0 * pow(4.0, float(b_lvl))),
			"locked": "Maks" if b_lvl >= 4 else ""
		})
	elif kind_s == "station":
		var t_lvl: int = int(up.get("trainLength", 0))
		list.append({
			"track": "trainLength", "label": "Rangkaian Kereta",
			"desc": "Kapasitas %d slot/KA" % (20 + 10 * t_lvl),
			"level": t_lvl, "max": 3,
			"price": GameCatalog.round_2sig(6000.0 * pow(2.0, float(t_lvl))),
			"locked": "Maks" if t_lvl >= 3 else ""
		})
		var tt_lvl: int = int(up.get("timetable", 0))
		list.append({
			"track": "timetable", "label": "Jadwal KA (Timetable)",
			"desc": "Pangkas jeda tunggu kereta",
			"level": tt_lvl, "max": 3,
			"price": GameCatalog.round_2sig(6000.0 * pow(2.0, float(tt_lvl))),
			"locked": "Maks" if tt_lvl >= 3 else ""
		})
	elif kind_s == "harbour":
		var sh_lvl: int = int(up.get("shipSize", 0))
		list.append({
			"track": "shipSize", "label": "Tonase Kapal Kargo",
			"desc": "Kapasitas %d slot/kapal" % (40 + 20 * sh_lvl),
			"level": sh_lvl, "max": 3,
			"price": GameCatalog.round_2sig(6000.0 * pow(2.0, float(sh_lvl))),
			"locked": "Maks" if sh_lvl >= 3 else ""
		})
		var tt_lvl: int = int(up.get("timetable", 0))
		list.append({
			"track": "timetable", "label": "Jadwal Pelayaran",
			"desc": "Percepat kedatangan kapal",
			"level": tt_lvl, "max": 3,
			"price": GameCatalog.round_2sig(6000.0 * pow(2.0, float(tt_lvl))),
			"locked": "Maks" if tt_lvl >= 3 else ""
		})

	var bay_lvl: int = int(up.get("bays", 0))
	var total_bays: int = get_total_bays(f)
	var needs_gate: bool = total_bays >= 6 and int(up.get("wideGate", 0)) == 0
	list.append({
		"track": "bays", "label": "Dermaga Muat (Bays)",
		"desc": "%d truk bongkar/muat paralel" % total_bays,
		"level": bay_lvl, "max": 7,
		"price": GameCatalog.round_2sig(500.0 * pow(2.0, float(maxi(0, bay_lvl - 1)))),
		"locked": "Maks" if bay_lvl >= 7 else ("Butuh Wide Gate" if needs_gate else "")
	})
	if total_bays >= 5 or int(up.get("wideGate", 0)) > 0:
		var wg: int = int(up.get("wideGate", 0))
		list.append({
			"track": "wideGate", "label": "Gerbang Lebar (Wide Gate)",
			"desc": "Akses 2 lajur & buka >6 bay",
			"level": wg, "max": 1, "price": 10000,
			"locked": "Terpasang" if wg >= 1 else ""
		})
	if total_bays >= 4 or int(up.get("exitRoad", 0)) > 0:
		var ex: int = int(up.get("exitRoad", 0))
		list.append({
			"track": "exitRoad", "label": "Jalan Keluar Khusus",
			"desc": "Waktu bongkar/muat −35%",
			"level": ex, "max": 1, "price": 20000,
			"locked": "Terpasang" if ex >= 1 else ""
		})
	return list

func buy_facility_upgrade(fac_id: String, track: String) -> bool:
	if not facility_map.has(fac_id):
		return false
	var f: Dictionary = facility_map[fac_id]
	for info in get_facility_upgrades(f):
		if String(info["track"]) == track:
			if String(info["locked"]) != "" or cash < int(info["price"]):
				if sfx:
					sfx.warn()
				return false
			var pr: int = int(info["price"])
			cash -= pr
			f["upgrades"][track] = int(f["upgrades"].get(track, 0)) + 1
			spawn_toast(f["pos"] + Vector2(0, -18), "-" + GameCatalog.fmt_cash(pr), Color("#e67e22"))
			if sfx:
				sfx.tap()
			return true
	return false

# === ROUTES & FLEET ===

func create_route(from_fac_id: String, to_fac_id: String, good_filter: String = "any", buy_first_truck: bool = true) -> Dictionary:
	if from_fac_id == to_fac_id or not facility_map.has(from_fac_id) or not facility_map.has(to_fac_id):
		return {}
	var f_from: Dictionary = facility_map[from_fac_id]
	var f_to: Dictionary = facility_map[to_fac_id]
	if not unlocked_regions.has(int(f_from["regionIndex"])) or not unlocked_regions.has(int(f_to["regionIndex"])):
		return {}

	var resolved_good: String = good_filter
	if resolved_good == "any" and f_from["outputGood"] != null:
		var out_g := String(f_from["outputGood"])
		var acc: Array = f_to["acceptedGoods"]
		if acc.is_empty() or acc.has(out_g):
			resolved_good = out_g

	var col: Color = GameCatalog.ROUTE_PALETTE[routes.size() % GameCatalog.ROUTE_PALETTE.size()]
	var from_short: String = String(f_from["name"]).split(" ")[0]
	var to_short: String = String(f_to["name"]).split(" ")[0]
	var rt := {
		"id": _next_uid("rt"),
		"name": "%s → %s" % [from_short, to_short],
		"color": col,
		"fromFacilityId": from_fac_id,
		"toFacilityId": to_fac_id,
		"goodFilter": resolved_good,
		"waypoints": [],
		"truckModel": "hauler",
		"forwardPath": [],
		"returnPath": [],
		"clearTimeForwardSec": 8.0,
		"brokenReason": "",
		"activeTruckIds": [],
		"totalRevenue": 0,
		"deliveriesCount": 0
	}
	recompute_single_route(rt)
	routes.append(rt)
	if buy_first_truck:
		add_truck_to_route(String(rt["id"]), false)
	if sfx:
		sfx.tap()
	return rt

func delete_route(route_id: String) -> void:
	for i in range(routes.size()):
		if String(routes[i]["id"]) == route_id:
			var rt: Dictionary = routes[i]
			var tids: Array = (rt["activeTruckIds"] as Array).duplicate()
			for tid in tids:
				remove_truck_from_route(route_id, String(tid))
			routes.remove_at(i)
			if sfx:
				sfx.tap()
			return

func toggle_route_waypoint(route_id: String, junction_id: String) -> void:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty():
		return
	var f_from: Dictionary = facility_map[String(rt["fromFacilityId"])]
	var f_to: Dictionary = facility_map[String(rt["toFacilityId"])]
	if junction_id == String(f_from["junctionId"]) or junction_id == String(f_to["junctionId"]):
		return
	var wps: Array = rt["waypoints"]
	var idx: int = wps.find(junction_id)
	if idx >= 0:
		wps.remove_at(idx)
	else:
		if wps.size() >= 3:
			wps.pop_front()
		wps.append(junction_id)
	recompute_single_route(rt)
	if sfx:
		sfx.tap()

func get_route(route_id: String) -> Dictionary:
	for r in routes:
		if String(r["id"]) == route_id:
			return r
	return {}

func recompute_single_route(rt: Dictionary) -> void:
	var f_from: Dictionary = facility_map.get(String(rt["fromFacilityId"]), {})
	var f_to: Dictionary = facility_map.get(String(rt["toFacilityId"]), {})
	if f_from.is_empty() or f_to.is_empty():
		return
	var fwd: Dictionary = RoutePathfinder.find_directed_path(
		String(f_from["junctionId"]),
		String(f_to["junctionId"]),
		rt["waypoints"],
		junction_map,
		road_map,
		unlocked_regions,
		String(rt["truckModel"])
	)
	var ret: Dictionary = RoutePathfinder.find_directed_path(
		String(f_to["junctionId"]),
		String(f_from["junctionId"]),
		[],
		junction_map,
		road_map,
		unlocked_regions,
		String(rt["truckModel"])
	)
	rt["forwardPath"] = fwd["steps"]
	rt["returnPath"] = ret["steps"]
	rt["clearTimeForwardSec"] = maxf(3.5, float(fwd["clear_time_sec"]))
	var br := String(fwd["broken_reason"])
	if br == "":
		br = String(ret["broken_reason"])
	rt["brokenReason"] = br

func recompute_all_routes() -> void:
	for rt in routes:
		recompute_single_route(rt)

func add_truck_to_route(route_id: String, free_starter: bool = false) -> bool:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty():
		return false
	var model_id := String(rt["truckModel"])
	var tdef: Dictionary = GameCatalog.TRUCKS[model_id]
	if not unlocked_licenses.has(model_id) and not free_starter:
		var lic: int = int(tdef["license_price"])
		if cash < lic:
			if sfx:
				sfx.warn()
			return false
		cash -= lic
		unlocked_licenses[model_id] = true

	var price: int = 0 if free_starter else get_next_truck_price(model_id)
	if not free_starter and cash < price:
		if sfx:
			sfx.warn()
		return false
	if not free_starter:
		cash -= price

	var f_from: Dictionary = facility_map[String(rt["fromFacilityId"])]
	var fpos: Vector2 = f_from["pos"]
	var tr_poses: Array = []
	for _k in tdef["trailers"]:
		tr_poses.append({"pos": fpos, "heading": 0.0})

	var ag := {
		"id": _next_uid("trk"),
		"routeId": route_id,
		"model": model_id,
		"state": "loading",
		"waitReason": "none",
		"stepIndex": 0,
		"sPx": 0.0,
		"laneIndex": 0,
		"visualLane": 0.0,
		"speedPx": 0.0,
		"cargoGood": "",
		"cargoQty": 0,
		"departedSec": real_time_sec,
		"expressDeadlineSec": 0.0,
		"dwellSec": 0.35 + float((rt["activeTruckIds"] as Array).size()) * 0.55,
		"waitSec": 0.0,
		"junctionWaitSec": 0.0,
		"gridlockSec": 0.0,
		"pos": fpos,
		"heading": 0.0,
		"trailerPoses": tr_poses
	}
	agents.append(ag)
	(rt["activeTruckIds"] as Array).append(ag["id"])
	if not free_starter:
		spawn_toast(fpos + Vector2(0, -14), "-" + GameCatalog.fmt_cash(price), Color("#e67e22"))
		if sfx:
			sfx.tap()
	return true

func remove_truck_from_route(route_id: String, specific_id: String = "") -> bool:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty():
		return false
	var tids: Array = rt["activeTruckIds"]
	if tids.is_empty():
		return false
	var target_id: String = specific_id if specific_id != "" else String(tids[tids.size() - 1])
	for i in range(agents.size()):
		if String(agents[i]["id"]) == target_id:
			var ag: Dictionary = agents[i]
			var refund: int = int(round(float(GameCatalog.TRUCKS[String(ag["model"])]["base_price"]) * 0.5))
			cash += refund
			spawn_toast(ag["pos"] + Vector2(0, -12), "+" + GameCatalog.fmt_cash(refund), Color("#2b8a3e"))
			agents.remove_at(i)
			break
	tids.erase(target_id)
	if sfx:
		sfx.tap()
	return true

func quote_route_model_swap(route_id: String, target_model: String) -> Dictionary:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty():
		return {}
	var count: int = (rt["activeTruckIds"] as Array).size()
	var lic: int = 0 if unlocked_licenses.has(target_model) else int(GameCatalog.TRUCKS[target_model]["license_price"])
	var old_base: int = int(GameCatalog.TRUCKS[String(rt["truckModel"])]["base_price"])
	var refund: int = int(round(float(old_base) * 0.5)) * count

	var owned_target: int = get_owned_count_by_model(target_model)
	if String(rt["truckModel"]) == target_model:
		owned_target = maxi(0, owned_target - count)
	var fleet_after_sell: int = maxi(0, agents.size() - count)
	var buy_cost: int = 0
	for i in range(count):
		buy_cost += GameCatalog.compute_truck_buy_price(target_model, owned_target + i, fleet_after_sell + i)

	return {
		"targetModel": target_model,
		"count": count,
		"license": lic,
		"refund": refund,
		"buyCost": buy_cost,
		"netCost": lic + buy_cost - refund
	}

func apply_route_model_swap(route_id: String, target_model: String) -> bool:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty() or String(rt["truckModel"]) == target_model:
		return false
	var q: Dictionary = quote_route_model_swap(route_id, target_model)
	var net: int = int(q["netCost"])
	if cash < net:
		if sfx:
			sfx.warn()
		return false
	cash -= net
	unlocked_licenses[target_model] = true
	rt["truckModel"] = target_model
	var new_def: Dictionary = GameCatalog.TRUCKS[target_model]
	for ag in agents:
		if String(ag["routeId"]) == route_id:
			ag["model"] = target_model
			var tp: Array = []
			for _k in new_def["trailers"]:
				tp.append({"pos": ag["pos"], "heading": ag["heading"]})
			ag["trailerPoses"] = tp
	recompute_single_route(rt)
	if sfx:
		sfx.tap()
	return true

# === TRAFFIC ENGINEERING RULES ===

func apply_junction_control(junction_id: String, tool: String) -> String:
	if not junction_map.has(junction_id):
		return ""
	var j: Dictionary = junction_map[junction_id]
	if not unlocked_regions.has(int(j["regionIndex"])):
		return "Wilayah simpang belum terbuka"

	var cur_ctrl := String(j["control"])
	var deg: int = (j["connectedEdgeIds"] as Array).size()

	if tool == "yield":
		if cur_ctrl == "yield":
			j["control"] = "none"
			j["yieldMinorEdgeIds"] = []
			map_static_dirty.emit()
			if sfx:
				sfx.tap()
			return "Rambu Yield dilepas"
		if deg < 3:
			return "Yield butuh minimal simpang 3 lengan"
		_refund_junction_hardware(j)
		j["control"] = "yield"
		var edges_sorted: Array = (j["connectedEdgeIds"] as Array).duplicate()
		edges_sorted.sort_custom(func(a, b):
			var ra: Dictionary = road_map[String(a)]
			var rb: Dictionary = road_map[String(b)]
			return (int(ra["lanesForward"]) + int(ra["lanesBackward"])) > (int(rb["lanesForward"]) + int(rb["lanesBackward"]))
		)
		j["yieldMinorEdgeIds"] = edges_sorted.slice(2)
		map_static_dirty.emit()
		if sfx:
			sfx.tap()
		return "Rambu Yield dipasang ($0)"

	if tool == "roundabout":
		if deg < 3:
			return "Bundaran butuh minimal 3 lengan jalan"
		if cur_ctrl == "roundabout":
			var up_p: int = int(GameCatalog.INFRA_PRICES["roundabout2_upgrade"])
			if cash < up_p:
				if sfx:
					sfx.warn()
				return "Kas kurang untuk Bundaran 2 Lajur (%s)" % GameCatalog.fmt_cash(up_p)
			cash -= up_p
			j["control"] = "roundabout2"
			spawn_toast(j["pos"] + Vector2(0, -16), "-" + GameCatalog.fmt_cash(up_p), Color("#e67e22"))
			map_static_dirty.emit()
			if sfx:
				sfx.tap()
			return "Bundaran ditingkatkan ke 2 Lajur!"
		if cur_ctrl == "roundabout2":
			var ref2: int = int(round(float(int(GameCatalog.INFRA_PRICES["roundabout"]) + int(GameCatalog.INFRA_PRICES["roundabout2_upgrade"])) * 0.5))
			cash += ref2
			j["control"] = "none"
			spawn_toast(j["pos"] + Vector2(0, -16), "+" + GameCatalog.fmt_cash(ref2), Color("#2b8a3e"))
			map_static_dirty.emit()
			if sfx:
				sfx.tap()
			return "Bundaran dibongkar (+%s)" % GameCatalog.fmt_cash(ref2)
		var rb_p: int = int(GameCatalog.INFRA_PRICES["roundabout"])
		if cash < rb_p:
			if sfx:
				sfx.warn()
			return "Kas kurang (%s)" % GameCatalog.fmt_cash(rb_p)
		_refund_junction_hardware(j)
		cash -= rb_p
		j["control"] = "roundabout"
		spawn_toast(j["pos"] + Vector2(0, -16), "-" + GameCatalog.fmt_cash(rb_p), Color("#e67e22"))
		map_static_dirty.emit()
		if sfx:
			sfx.tap()
		return "Bundaran dibangun!"

	if tool == "lights":
		if cur_ctrl == "lights":
			if sfx:
				sfx.tap()
			return "Mengatur durasi lampu lalu lintas"
		var lt_p: int = int(GameCatalog.INFRA_PRICES["light"])
		if cash < lt_p:
			if sfx:
				sfx.warn()
			return "Kas kurang (%s)" % GameCatalog.fmt_cash(lt_p)
		_refund_junction_hardware(j)
		cash -= lt_p
		j["control"] = "lights"
		j["light"] = _make_default_light()
		spawn_toast(j["pos"] + Vector2(0, -16), "-" + GameCatalog.fmt_cash(lt_p), Color("#e67e22"))
		map_static_dirty.emit()
		if sfx:
			sfx.tap()
		return "Lampu lalu lintas teraktuasi dipasang!"

	return ""

func remove_traffic_lights(junction_id: String) -> void:
	if not junction_map.has(junction_id):
		return
	var j: Dictionary = junction_map[junction_id]
	if String(j["control"]) != "lights":
		return
	var ref: int = int(round(float(GameCatalog.INFRA_PRICES["light"]) * 0.5))
	cash += ref
	j["control"] = "none"
	j.erase("light")
	spawn_toast(j["pos"] + Vector2(0, -16), "+" + GameCatalog.fmt_cash(ref), Color("#2b8a3e"))
	map_static_dirty.emit()
	if sfx:
		sfx.tap()

func _refund_junction_hardware(j: Dictionary) -> void:
	var c := String(j["control"])
	if c == "lights":
		cash += int(round(float(GameCatalog.INFRA_PRICES["light"]) * 0.5))
		j.erase("light")
	elif c == "roundabout":
		cash += int(round(float(GameCatalog.INFRA_PRICES["roundabout"]) * 0.5))
	elif c == "roundabout2":
		cash += int(round(float(int(GameCatalog.INFRA_PRICES["roundabout"]) + int(GameCatalog.INFRA_PRICES["roundabout2_upgrade"])) * 0.5))

func modify_road_lanes(edge_id: String, delta: int) -> String:
	if not road_map.has(edge_id):
		return ""
	var r: Dictionary = road_map[edge_id]
	if not bool(r["isBuilt"]) or not unlocked_regions.has(int(r["regionIndex"])):
		return ""
	var pts: PackedVector2Array = r["pts"]
	var mid: Vector2 = pts[pts.size() / 2]
	var cur_lanes: int = int(r["lanesForward"])

	if delta > 0:
		if cur_lanes >= 4:
			return "Maksimal 4 lajur per arah"
		var nxt: int = cur_lanes + 1
		var price: int = GameCatalog.round_2sig(float(GameCatalog.INFRA_PRICES["lane_base"]) + float(GameCatalog.INFRA_PRICES["lane_per_px"]) * float(r["lengthPx"])) * maxi(1, nxt - 1)
		if cash < price:
			if sfx:
				sfx.warn()
			return "Kas kurang (%s)" % GameCatalog.fmt_cash(price)
		cash -= price
		r["lanesForward"] = nxt
		r["lanesBackward"] = nxt
		spawn_toast(mid, "-" + GameCatalog.fmt_cash(price), Color("#e67e22"))
		map_static_dirty.emit()
		if sfx:
			sfx.tap()
		return "%s diperlebar ke %d lajur" % [String(r["name"]), nxt]
	else:
		if cur_lanes <= 1:
			return "Minimal 1 lajur jalan"
		var paid: int = GameCatalog.round_2sig(float(GameCatalog.INFRA_PRICES["lane_base"]) + float(GameCatalog.INFRA_PRICES["lane_per_px"]) * float(r["lengthPx"])) * maxi(1, cur_lanes - 1)
		var refund: int = int(round(float(paid) * 0.5))
		cash += refund
		r["lanesForward"] = cur_lanes - 1
		r["lanesBackward"] = cur_lanes - 1
		spawn_toast(mid, "+" + GameCatalog.fmt_cash(refund), Color("#2b8a3e"))
		map_static_dirty.emit()
		if sfx:
			sfx.tap()
		return "%s dikurangi ke %d lajur (+%s)" % [String(r["name"]), cur_lanes - 1, GameCatalog.fmt_cash(refund)]

func cycle_road_one_way(edge_id: String) -> String:
	if not road_map.has(edge_id):
		return ""
	var r: Dictionary = road_map[edge_id]
	if not bool(r["isBuilt"]) or bool(r["closed"]) or not unlocked_regions.has(int(r["regionIndex"])):
		return ""
	var ow: int = int(r["oneWay"])
	r["oneWay"] = 1 if ow == 0 else (-1 if ow == 1 else 0)
	recompute_all_routes()
	map_static_dirty.emit()
	if sfx:
		sfx.tap()
	var label := "Dua Arah" if int(r["oneWay"]) == 0 else ("Satu Arah →" if int(r["oneWay"]) == 1 else "Satu Arah ←")
	return "%s: %s" % [String(r["name"]), label]

func toggle_close_street(edge_id: String) -> String:
	if not road_map.has(edge_id):
		return ""
	var r: Dictionary = road_map[edge_id]
	if not bool(r["isBuilt"]) or not unlocked_regions.has(int(r["regionIndex"])):
		return ""
	var pts: PackedVector2Array = r["pts"]
	var mid: Vector2 = pts[pts.size() / 2]
	if bool(r["closed"]):
		r["closed"] = false
		recompute_all_routes()
		map_static_dirty.emit()
		if sfx:
			sfx.tap()
		return "%s dibuka kembali ($0)" % String(r["name"])
	var price: int = int(GameCatalog.INFRA_PRICES["close_street"])
	if cash < price:
		if sfx:
			sfx.warn()
		return "Kas kurang (%s)" % GameCatalog.fmt_cash(price)
	cash -= price
	r["closed"] = true
	r["oneWay"] = 0
	spawn_toast(mid, "-" + GameCatalog.fmt_cash(price), Color("#e67e22"))
	recompute_all_routes()
	map_static_dirty.emit()
	if sfx:
		sfx.tap()
	return "%s ditutup menjadi taman kota" % String(r["name"])

func purchase_road_offer(offer_id: String) -> String:
	for off in road_offers:
		if String(off["id"]) == offer_id:
			if bool(off["purchased"]):
				return "Proyek sudah dibangun"
			if not unlocked_regions.has(int(off["regionIndex"])):
				return "Buka wilayah terkait terlebih dahulu"
			var pr: int = int(off["price"])
			if cash < pr:
				if sfx:
					sfx.warn()
				return "Kas kurang (%s)" % GameCatalog.fmt_cash(pr)
			cash -= pr
			off["purchased"] = true
			for eid in off["edgeIds"]:
				if road_map.has(String(eid)):
					road_map[String(eid)]["isBuilt"] = true
			recompute_all_routes()
			map_static_dirty.emit()
			if sfx:
				sfx.unlock_region()
			banner_notify.emit("Proyek Jalan Selesai!", String(off["name"]), Color("#2b8a3e"))
			return "%s resmi beroperasi!" % String(off["name"])
	return ""

# === MAIN FIXED-TIMESTEP SIMULATION LOOP ===

func step_frame(frame_dt: float) -> void:
	# Update floating cash toasts smoothly at render rate
	for i in range(floating_toasts.size() - 1, -1, -1):
		floating_toasts[i]["age"] = float(floating_toasts[i]["age"]) + frame_dt
		if float(floating_toasts[i]["age"]) > 1.45:
			floating_toasts.remove_at(i)

	if speed_multiplier == 0:
		return

	var clamped_dt: float = minf(frame_dt, 0.08) * float(speed_multiplier)
	_sim_accum += clamped_dt
	var substeps: int = 0
	while _sim_accum >= SIM_DT and substeps < 6:
		_step_fixed(SIM_DT)
		_sim_accum -= SIM_DT
		substeps += 1
	if substeps >= 6:
		_sim_accum = 0.0

func _step_fixed(dt: float) -> void:
	real_time_sec += dt
	if auto_day_night:
		day_clock_01 = fmod(day_clock_01 + dt / 150.0, 1.0)
		night_mode = day_clock_01 < 0.22 or day_clock_01 > 0.78

	_step_facilities(dt)
	_step_traffic_lights(dt)
	_step_agents(dt)
	_step_upkeep_and_goals(dt)

func _step_facilities(dt: float) -> void:
	for f in facilities:
		if not unlocked_regions.has(int(f["regionIndex"])):
			continue
		var k := String(f["kind"])
		var cap: int = get_capacity_slots(f)

		if k == "supplier" and f["outputGood"] != null:
			var out_g := String(f["outputGood"])
			var slot_sz: int = int(GameCatalog.GOODS[out_g]["slots"])
			if int(f["outputBuffer"]) * slot_sz >= cap:
				f["stalledReason"] = "output_full"
			else:
				f["stalledReason"] = "none"
				var rate_sec: float = float(get_supplier_rate_per_min(f)) / 60.0
				f["prodProgress"] = float(f["prodProgress"]) + rate_sec * dt
				while float(f["prodProgress"]) >= 1.0 and int(f["outputBuffer"]) * slot_sz < cap:
					f["prodProgress"] = float(f["prodProgress"]) - 1.0
					f["outputBuffer"] = int(f["outputBuffer"]) + 1

		elif k == "factory" and f["outputGood"] != null:
			var out_g := String(f["outputGood"])
			var gdef: Dictionary = GameCatalog.GOODS[out_g]
			var slot_sz: int = int(gdef["slots"])
			if int(f["outputBuffer"]) * slot_sz >= cap:
				f["stalledReason"] = "output_full"
				continue
			var in_bufs: Dictionary = f["inputBuffers"]
			var has_inputs: bool = true
			for inp in gdef["inputs"]:
				if int(in_bufs.get(String(inp["good"]), 0)) < int(inp["qty"]):
					has_inputs = false
					break
			if not has_inputs:
				f["stalledReason"] = "missing_input"
				continue
			f["stalledReason"] = "none"
			var out_rate_sec: float = get_factory_output_per_min(f) / 60.0
			f["prodProgress"] = float(f["prodProgress"]) + out_rate_sec * dt
			if float(f["prodProgress"]) >= 1.0:
				f["prodProgress"] = float(f["prodProgress"]) - 1.0
				for inp in gdef["inputs"]:
					var ig := String(inp["good"])
					in_bufs[ig] = maxi(0, int(in_bufs.get(ig, 0)) - int(inp["qty"]))
				f["outputBuffer"] = int(f["outputBuffer"]) + 1

		elif k == "station" or k == "harbour":
			var tt_lvl: int = clampi(int(f["upgrades"].get("timetable", 0)), 0, 3)
			var wait_factor: float = GameCatalog.TIMETABLE_WAIT_FACTORS[tt_lvl]
			f["vehicleTimer"] = float(f["vehicleTimer"]) - dt
			if float(f["vehicleTimer"]) <= 0.0:
				if bool(f["vehiclePresent"]):
					var away_sec: float = (7.5 if k == "station" else 10.0) * wait_factor
					if away_sec <= 0.45:
						f["vehiclePresent"] = true
						f["vehicleTimer"] = 18.0
						f["vehicleCapacityRemaining"] = (40 + 20 * int(f["upgrades"].get("shipSize", 0))) if k == "harbour" else (20 + 10 * int(f["upgrades"].get("trainLength", 0)))
					else:
						f["vehiclePresent"] = false
						f["vehicleTimer"] = away_sec
				else:
					f["vehiclePresent"] = true
					f["vehicleTimer"] = 18.0 if k == "station" else 22.0
					f["vehicleCapacityRemaining"] = (40 + 20 * int(f["upgrades"].get("shipSize", 0))) if k == "harbour" else (20 + 10 * int(f["upgrades"].get("trainLength", 0)))

func _get_edge_phase_at_junction(j: Dictionary, edge_id: String) -> int:
	var idx: int = (j["connectedEdgeIds"] as Array).find(edge_id)
	return 0 if (idx < 0 or idx % 2 == 0) else 1

func _step_traffic_lights(dt: float) -> void:
	for j in junctions:
		if String(j["control"]) != "lights" or not j.has("light"):
			continue
		var lt: Dictionary = j["light"]
		lt["timer"] = float(lt["timer"]) - dt
		if String(lt["stage"]) == "green":
			lt["greenElapsed"] = float(lt["greenElapsed"]) + dt
			var target_green: float = float(lt["phaseAGreen"]) if int(lt["currentPhase"]) == 0 else float(lt["phaseBGreen"])
			# Actuated gap-out sensor
			if bool(lt["actuated"]) and float(lt["greenElapsed"]) >= 3.5:
				var gap_idle: float = real_time_sec - float(lt["lastDetectorHit"])
				if gap_idle >= float(lt["sensorGap"]):
					lt["timer"] = 0.0
			if float(lt["timer"]) <= 0.0 or float(lt["greenElapsed"]) >= target_green * 1.5:
				lt["stage"] = "yellow"
				lt["timer"] = maxf(0.5, float(lt["yellow"]))
		elif String(lt["stage"]) == "yellow":
			if float(lt["timer"]) <= 0.0:
				lt["stage"] = "allred"
				lt["timer"] = maxf(0.4, float(lt["allRed"]))
		else:
			if float(lt["timer"]) <= 0.0:
				var nxt_phase: int = 1 if int(lt["currentPhase"]) == 0 else 0
				lt["currentPhase"] = nxt_phase
				lt["stage"] = "green"
				lt["greenElapsed"] = 0.0
				lt["lastDetectorHit"] = real_time_sec
				lt["timer"] = float(lt["phaseAGreen"]) if nxt_phase == 0 else float(lt["phaseBGreen"])

func _step_agents(dt: float) -> void:
	for f in facilities:
		f["occupiedBays"] = 0

	# Bucket active driving agents by directed road key "edgeId:1" / "edgeId:0"
	var lane_buckets: Dictionary = {}
	for ag in agents:
		var st := String(ag["state"])
		if st == "loading" or st == "unloading":
			var rt_b: Dictionary = get_route(String(ag["routeId"]))
			if not rt_b.is_empty():
				var fid: String = String(rt_b["fromFacilityId"]) if st == "loading" else String(rt_b["toFacilityId"])
				if facility_map.has(fid):
					facility_map[fid]["occupiedBays"] = int(facility_map[fid]["occupiedBays"]) + 1
		elif st == "driving_outbound" or st == "driving_return":
			var step_d: Dictionary = _get_agent_current_step(ag)
			if not step_d.is_empty():
				var key := "%s:%d" % [String(step_d["edgeId"]), 1 if bool(step_d["forward"]) else 0]
				if not lane_buckets.has(key):
					lane_buckets[key] = []
				(lane_buckets[key] as Array).append(ag)

	for k in lane_buckets.keys():
		(lane_buckets[k] as Array).sort_custom(func(a, b): return float(a["sPx"]) > float(b["sPx"]))

	# Update congestion EMA per road
	for r in roads:
		var rid := String(r["id"])
		var cnt: int = (lane_buckets.get(rid + ":1", []) as Array).size() + (lane_buckets.get(rid + ":0", []) as Array).size()
		var cap_est: float = maxf(1.5, (float(r["lengthPx"]) / 34.0) * float(int(r["lanesForward"]) + int(r["lanesBackward"])) * 0.5)
		var ratio: float = minf(1.5, float(cnt) / cap_est)
		r["congestionEMA"] = float(r["congestionEMA"]) * 0.94 + ratio * 0.06

	for ag in agents:
		var rt: Dictionary = get_route(String(ag["routeId"]))
		if rt.is_empty():
			continue
		var tdef: Dictionary = GameCatalog.TRUCKS[String(ag["model"])]
		var st := String(ag["state"])

		if st == "loading":
			_update_loading_agent(ag, rt, dt)
		elif st == "queuing_bay":
			var f_to: Dictionary = facility_map[String(rt["toFacilityId"])]
			if int(f_to["occupiedBays"]) < get_total_bays(f_to):
				f_to["occupiedBays"] = int(f_to["occupiedBays"]) + 1
				ag["state"] = "unloading"
				ag["waitReason"] = "none"
				var exit_mult: float = 0.65 if int(f_to["upgrades"].get("exitRoad", 0)) > 0 else 1.0
				var c_slots: int = int(GameCatalog.GOODS[String(ag["cargoGood"])]["slots"]) * maxi(1, int(ag["cargoQty"])) if String(ag["cargoGood"]) != "" else 1
				ag["dwellSec"] = maxf(0.45, 0.85 * float(c_slots) * exit_mult)
				ag["waitSec"] = 0.0
			else:
				ag["waitReason"] = "bay_full"
				ag["speedPx"] = 0.0
		elif st == "unloading":
			_update_unloading_agent(ag, rt, dt)
		elif st == "driving_outbound" or st == "driving_return":
			_update_driving_agent(ag, rt, tdef, lane_buckets, dt)

func _update_loading_agent(ag: Dictionary, rt: Dictionary, dt: float) -> void:
	var f_from: Dictionary = facility_map[String(rt["fromFacilityId"])]
	ag["pos"] = f_from["pos"]
	ag["speedPx"] = 0.0
	if String(rt["brokenReason"]) != "":
		ag["waitReason"] = "cargo_wait"
		return
	ag["dwellSec"] = float(ag["dwellSec"]) - dt
	if float(ag["dwellSec"]) > 0.0:
		return

	var good_to_load: String = String(rt["goodFilter"])
	if good_to_load == "any":
		good_to_load = String(f_from["outputGood"]) if f_from["outputGood"] != null else ""

	var max_units: int = GameCatalog.compute_max_carry_units(String(ag["model"]), good_to_load) if good_to_load != "" else 0
	var avail: int = int(f_from["outputBuffer"])
	if good_to_load != "" and max_units > 0 and avail > 0:
		var take: int = mini(max_units, avail)
		f_from["outputBuffer"] = avail - take
		ag["cargoGood"] = good_to_load
		ag["cargoQty"] = take
		ag["departedSec"] = real_time_sec
		ag["expressDeadlineSec"] = real_time_sec + float(rt["clearTimeForwardSec"]) * 1.35 + 3.0
		ag["state"] = "driving_outbound"
		ag["stepIndex"] = 0
		ag["sPx"] = 0.0
		ag["waitSec"] = 0.0
		ag["waitReason"] = "none"
	else:
		ag["waitSec"] = float(ag["waitSec"]) + dt
		ag["waitReason"] = "cargo_wait"

func _update_unloading_agent(ag: Dictionary, rt: Dictionary, dt: float) -> void:
	var f_to: Dictionary = facility_map[String(rt["toFacilityId"])]
	ag["pos"] = f_to["pos"]
	ag["speedPx"] = 0.0
	ag["dwellSec"] = float(ag["dwellSec"]) - dt
	if float(ag["dwellSec"]) > 0.0:
		return

	var c_good := String(ag["cargoGood"])
	var c_qty: int = int(ag["cargoQty"])
	if c_good != "" and c_qty > 0:
		var gdef: Dictionary = GameCatalog.GOODS[c_good]
		var can_accept: bool = false
		var fk := String(f_to["kind"])

		if fk == "factory":
			var cur_in: int = int(f_to["inputBuffers"].get(c_good, 0))
			if (cur_in + c_qty) * int(gdef["slots"]) <= get_capacity_slots(f_to):
				f_to["inputBuffers"][c_good] = cur_in + c_qty
				can_accept = true
		elif fk == "station" or fk == "harbour":
			if bool(f_to["vehiclePresent"]) and int(f_to["vehicleCapacityRemaining"]) >= c_qty * int(gdef["slots"]):
				f_to["vehicleCapacityRemaining"] = int(f_to["vehicleCapacityRemaining"]) - c_qty * int(gdef["slots"])
				can_accept = true
		elif fk == "market":
			can_accept = true

		if can_accept:
			var is_express_hit: bool = String(ag["model"]) == "express" and real_time_sec <= float(ag["expressDeadlineSec"])
			var bonus: int = 2 if is_express_hit else 1
			var payout: int = int(gdef["value"]) * c_qty * bonus
			cash += payout
			rt["totalRevenue"] = int(rt["totalRevenue"]) + payout
			rt["deliveriesCount"] = int(rt["deliveriesCount"]) + c_qty
			revenue_events.append({"t": real_time_sec, "amount": payout})
			_record_delivery(String(rt["fromFacilityId"]), String(f_to["id"]), c_good, c_qty)
			var toast_txt: String = ("⚡+" if is_express_hit else "+") + GameCatalog.fmt_cash(payout)
			spawn_toast(f_to["pos"] + Vector2(0, -16), toast_txt, Color("#f59f00") if is_express_hit else Color("#2b8a3e"))
			if sfx:
				sfx.coin(is_express_hit)
			ag["cargoGood"] = ""
			ag["cargoQty"] = 0
		else:
			# 5s scrap fallback at 10% value prevents permanent bay gridlock
			ag["waitSec"] = float(ag["waitSec"]) + dt
			ag["waitReason"] = "scrap_wait"
			if float(ag["waitSec"]) < 5.0:
				return
			var scrap_pay: int = maxi(1, int(round(float(int(gdef["value"]) * c_qty) * 0.10)))
			cash += scrap_pay
			revenue_events.append({"t": real_time_sec, "amount": scrap_pay})
			spawn_toast(f_to["pos"] + Vector2(0, -14), "Scrap +" + GameCatalog.fmt_cash(scrap_pay), Color("#868e96"))
			ag["cargoGood"] = ""
			ag["cargoQty"] = 0

	ag["state"] = "driving_return"
	ag["stepIndex"] = 0
	ag["sPx"] = 0.0
	ag["waitSec"] = 0.0
	ag["waitReason"] = "none"

func _get_agent_current_step(ag: Dictionary) -> Dictionary:
	var rt: Dictionary = get_route(String(ag["routeId"]))
	if rt.is_empty():
		return {}
	var path: Array = rt["forwardPath"] if String(ag["state"]) == "driving_outbound" else rt["returnPath"]
	var idx: int = int(ag["stepIndex"])
	if idx < 0 or idx >= path.size():
		return {}
	return path[idx]

func _update_driving_agent(ag: Dictionary, rt: Dictionary, tdef: Dictionary, lane_buckets: Dictionary, dt: float) -> void:
	var path: Array = rt["forwardPath"] if String(ag["state"]) == "driving_outbound" else rt["returnPath"]
	if int(ag["stepIndex"]) >= path.size():
		_finish_agent_leg(ag, rt)
		return

	var step_d: Dictionary = path[int(ag["stepIndex"])]
	var eid := String(step_d["edgeId"])
	if not road_map.has(eid):
		_finish_agent_leg(ag, rt)
		return
	var edge: Dictionary = road_map[eid]
	var forward: bool = bool(step_d["forward"])
	var lanes_dir: int = maxi(1, int(edge["lanesForward"]) if forward else int(edge["lanesBackward"]))
	if int(ag["laneIndex"]) >= lanes_dir:
		ag["laneIndex"] = lanes_dir - 1

	var key := "%s:%d" % [eid, 1 if forward else 0]
	var bucket: Array = lane_buckets.get(key, [])

	var leader: Dictionary = {}
	for other in bucket:
		if String(other["id"]) == String(ag["id"]):
			continue
		if int(other["laneIndex"]) == int(ag["laneIndex"]) and float(other["sPx"]) > float(ag["sPx"]):
			if leader.is_empty() or float(other["sPx"]) < float(leader["sPx"]):
				leader = other

	# Cooperative overtake on multi-lane roads
	if not leader.is_empty() and lanes_dir > 1 and float(leader["sPx"]) - float(ag["sPx"]) < float(tdef["body_len"]) + 20.0 and float(leader["speedPx"]) < float(tdef["max_speed_px"]) * 0.72:
		for cand_lane in range(lanes_dir):
			if cand_lane == int(ag["laneIndex"]):
				continue
			var clear_lane: bool = true
			for other in bucket:
				if int(other["laneIndex"]) == cand_lane and absf(float(other["sPx"]) - float(ag["sPx"])) < float(tdef["body_len"]) + 14.0:
					clear_lane = false
					break
			if clear_lane:
				ag["laneIndex"] = cand_lane
				leader = {}
				break

	var target_v: float = float(tdef["max_speed_px"])
	var rc := String(edge["roadClass"])
	if rc == "toll":
		target_v *= 1.18
	elif rc == "local":
		target_v *= 0.85

	ag["waitReason"] = "none"

	if not leader.is_empty():
		var leader_body: float = float(GameCatalog.TRUCKS[String(leader["model"])]["body_len"])
		var gap: float = float(leader["sPx"]) - float(ag["sPx"]) - leader_body * 0.5 - float(tdef["body_len"]) * 0.5
		if gap < 9.0:
			target_v = 0.0
			ag["waitReason"] = "following"
		elif gap < 28.0:
			target_v = minf(target_v, float(leader["speedPx"]) * 0.90)
			ag["waitReason"] = "following"

	var dist_to_end: float = float(edge["lengthPx"]) - float(ag["sPx"])
	var j_ahead: Dictionary = junction_map.get(String(step_d["toJunctionId"]), {})
	if not j_ahead.is_empty() and dist_to_end < 54.0:
		var ctrl := String(j_ahead["control"])
		if ctrl == "lights" and j_ahead.has("light"):
			var lt: Dictionary = j_ahead["light"]
			var my_phase: int = _get_edge_phase_at_junction(j_ahead, eid)
			if int(lt["currentPhase"]) == my_phase and String(lt["stage"]) == "green":
				lt["lastDetectorHit"] = real_time_sec
				target_v = minf(target_v, 44.0)
			else:
				if dist_to_end < 14.0:
					target_v = 0.0
					ag["waitReason"] = "red_light"
				else:
					target_v = minf(target_v, maxf(6.0, dist_to_end * 0.8))
		elif ctrl == "yield":
			var is_minor: bool = (j_ahead["yieldMinorEdgeIds"] as Array).has(eid)
			if is_minor and dist_to_end < 20.0 and float(ag["junctionWaitSec"]) < 1.2:
				var conflict: bool = _has_junction_conflict(String(j_ahead["id"]), eid)
				if conflict:
					target_v = 0.0
					ag["waitReason"] = "yield"
			elif String(ag["model"]) != "express":
				target_v = minf(target_v, 36.0)
		elif ctrl == "roundabout" or ctrl == "roundabout2":
			var cap_rb: int = 4 if ctrl == "roundabout2" else 2
			if dist_to_end < 16.0 and float(ag["junctionWaitSec"]) < 0.9 and _count_near_junction(String(j_ahead["id"]), 24.0) >= cap_rb:
				target_v = 0.0
				ag["waitReason"] = "roundabout"
			else:
				target_v = minf(target_v, 36.0 if ctrl == "roundabout2" else 28.0)

	var cur_v: float = float(ag["speedPx"])
	if cur_v < target_v:
		cur_v = minf(target_v, cur_v + float(tdef["accel"]) * dt)
	else:
		cur_v = maxf(target_v, cur_v - float(tdef["decel"]) * dt)
	ag["speedPx"] = cur_v

	if cur_v < 0.8:
		ag["junctionWaitSec"] = float(ag["junctionWaitSec"]) + dt
		ag["gridlockSec"] = float(ag["gridlockSec"]) + dt
		if float(ag["gridlockSec"]) > 25.0:
			cur_v = 22.0
			ag["speedPx"] = cur_v
			ag["gridlockSec"] = 0.0
	else:
		ag["junctionWaitSec"] = 0.0
		ag["gridlockSec"] = 0.0

	ag["sPx"] = float(ag["sPx"]) + cur_v * dt
	ag["visualLane"] = lerpf(float(ag["visualLane"]), float(ag["laneIndex"]), minf(1.0, dt * 8.0))

	if float(ag["sPx"]) >= float(edge["lengthPx"]):
		ag["sPx"] = float(ag["sPx"]) - float(edge["lengthPx"])
		ag["stepIndex"] = int(ag["stepIndex"]) + 1
		ag["junctionWaitSec"] = 0.0
		if int(ag["stepIndex"]) >= path.size():
			_finish_agent_leg(ag, rt)
			return

	var active_step: Dictionary = path[int(ag["stepIndex"])]
	var active_edge: Dictionary = road_map[String(active_step["edgeId"])]
	var active_fwd: bool = bool(active_step["forward"])
	var active_lanes: int = maxi(1, int(active_edge["lanesForward"]) if active_fwd else int(active_edge["lanesBackward"]))

	var pose: Dictionary = RoadGeom.sample_road_pose(
		active_edge["pts"],
		active_edge["cum_len"],
		float(active_edge["lengthPx"]),
		int(active_edge["oneWay"]),
		active_fwd,
		float(ag["sPx"]),
		minf(float(active_lanes - 1), float(ag["visualLane"])),
		active_lanes,
		left_hand_traffic
	)
	ag["pos"] = pose["pos"]
	ag["heading"] = pose["heading"]

	var t_poses: Array = ag["trailerPoses"]
	var spacing: float = 8.8
	for ti in range(t_poses.size()):
		var tr_s: float = float(ag["sPx"]) - float(ti + 1) * spacing
		if tr_s >= 0.0:
			var tp: Dictionary = RoadGeom.sample_road_pose(
				active_edge["pts"],
				active_edge["cum_len"],
				float(active_edge["lengthPx"]),
				int(active_edge["oneWay"]),
				active_fwd,
				tr_s,
				minf(float(active_lanes - 1), float(ag["visualLane"])),
				active_lanes,
				left_hand_traffic
			)
			t_poses[ti]["pos"] = tp["pos"]
			t_poses[ti]["heading"] = tp["heading"]
		else:
			var lead_p: Vector2 = ag["pos"] if ti == 0 else t_poses[ti - 1]["pos"]
			var cur_p: Vector2 = t_poses[ti]["pos"]
			var delta_v: Vector2 = lead_p - cur_p
			var ang: float = atan2(delta_v.y, delta_v.x)
			t_poses[ti]["heading"] = ang
			t_poses[ti]["pos"] = lead_p - Vector2(cos(ang), sin(ang)) * spacing

func _finish_agent_leg(ag: Dictionary, rt: Dictionary) -> void:
	ag["speedPx"] = 0.0
	if String(ag["state"]) == "driving_outbound":
		ag["state"] = "queuing_bay"
		ag["pos"] = facility_map[String(rt["toFacilityId"])]["pos"]
	else:
		ag["state"] = "loading"
		ag["dwellSec"] = 0.55
		ag["pos"] = facility_map[String(rt["fromFacilityId"])]["pos"]

func _has_junction_conflict(j_id: String, minor_edge_id: String) -> bool:
	var jp: Vector2 = junction_map[j_id]["pos"]
	for other in agents:
		var st := String(other["state"])
		if st != "driving_outbound" and st != "driving_return":
			continue
		var sd: Dictionary = _get_agent_current_step(other)
		if sd.is_empty() or String(sd["edgeId"]) == minor_edge_id:
			continue
		if String(sd["toJunctionId"]) == j_id and (other["pos"] as Vector2).distance_to(jp) < 34.0 and float(other["speedPx"]) > 5.0:
			return true
	return false

func _count_near_junction(j_id: String, rad: float) -> int:
	var jp: Vector2 = junction_map[j_id]["pos"]
	var c: int = 0
	for other in agents:
		if (other["pos"] as Vector2).distance_to(jp) < rad:
			c += 1
	return c

func _record_delivery(from_id: String, to_id: String, good_id: String, qty: int) -> void:
	var f_to: Dictionary = facility_map[to_id]
	var dw: Dictionary = f_to["deliveredWindow"]
	if not dw.has(good_id):
		dw[good_id] = []
	var arr: Array = dw[good_id]
	for _i in range(qty):
		arr.append(real_time_sec)

	var fkey := "%s->%s->%s" % [from_id, to_id, good_id]
	if not flow_edges.has(fkey):
		flow_edges[fkey] = {"fromId": from_id, "toId": to_id, "good": good_id, "times": []}
	var ftimes: Array = flow_edges[fkey]["times"]
	for _i in range(qty):
		ftimes.append(real_time_sec)

func _step_upkeep_and_goals(dt: float) -> void:
	_upkeep_timer += dt
	if _upkeep_timer >= 2.0:
		var elapsed: float = _upkeep_timer
		_upkeep_timer = 0.0
		var upkeep_min: float = 0.0
		for ag in agents:
			upkeep_min += float(GameCatalog.TRUCKS[String(ag["model"])]["upkeep_min"])
		var cost: int = int(round((upkeep_min / 60.0) * elapsed))
		if cost > 0:
			cash = maxi(0, cash - cost)
			upkeep_events.append({"t": real_time_sec, "amount": cost})

		var cutoff: float = real_time_sec - 60.0
		while not revenue_events.is_empty() and float(revenue_events[0]["t"]) < cutoff:
			revenue_events.pop_front()
		while not upkeep_events.is_empty() and float(upkeep_events[0]["t"]) < cutoff:
			upkeep_events.pop_front()

		for f in facilities:
			var dw: Dictionary = f["deliveredWindow"]
			for gk in dw.keys():
				var ts: Array = dw[gk]
				while not ts.is_empty() and float(ts[0]) < cutoff:
					ts.pop_front()

		var empty_fkeys: Array[String] = []
		for fk in flow_edges.keys():
			var ts: Array = flow_edges[fk]["times"]
			while not ts.is_empty() and float(ts[0]) < cutoff:
				ts.pop_front()
			if ts.is_empty():
				empty_fkeys.append(fk)
		for fk in empty_fkeys:
			flow_edges.erase(fk)

	_history_timer += dt
	if _history_timer >= 5.0:
		_history_timer = 0.0
		cash_history.append(cash)
		if cash_history.size() > 60:
			cash_history.pop_front()

	# Evaluate active locked region gate OR Boomtown endless goal
	var next_locked: Dictionary = get_active_goal_region()
	if not next_locked.is_empty() and not bool(next_locked["unlocked"]):
		var all_met: bool = true
		for g in next_locked["goals"]:
			var cur_rate: float = get_global_delivery_rate_per_min(String(g["good"]))
			g["currentPerMin"] = cur_rate
			if cur_rate + 0.05 < float(g["targetPerMin"]):
				all_met = false
		if all_met:
			next_locked["holdSeconds"] = minf(HOLD_REQUIRED_SEC, float(next_locked["holdSeconds"]) + dt)
			if float(next_locked["holdSeconds"]) >= HOLD_REQUIRED_SEC:
				next_locked["unlocked"] = true
				next_locked["unlockedAtRealSec"] = real_time_sec
				unlocked_regions[int(next_locked["index"])] = true
				recompute_all_routes()
				map_static_dirty.emit()
				if sfx:
					sfx.unlock_region()
				region_unlocked.emit(String(next_locked["name"]), String(next_locked["subtitle"]))
				banner_notify.emit("Wilayah Baru Terbuka!", "%s — %s" % [String(next_locked["name"]), String(next_locked["subtitle"])], Color(String(next_locked["accentColor"])))
				save_to_disk()
		else:
			next_locked["holdSeconds"] = maxf(0.0, float(next_locked["holdSeconds"]) - dt)
	elif not regions.is_empty():
		var last_reg: Dictionary = regions[regions.size() - 1]
		var all_boom: bool = true
		for g in last_reg["goals"]:
			var cur_r: float = get_global_delivery_rate_per_min(String(g["good"]))
			g["currentPerMin"] = cur_r
			if cur_r + 0.05 < float(g["targetPerMin"]):
				all_boom = false
		if all_boom:
			last_reg["holdSeconds"] = float(last_reg["holdSeconds"]) + dt
			if float(last_reg["holdSeconds"]) >= HOLD_REQUIRED_SEC:
				boomtown_level += 1
				last_reg["holdSeconds"] = 0.0
				for g in last_reg["goals"]:
					g["targetPerMin"] = float(g["targetPerMin"]) + 2.5
				if sfx:
					sfx.unlock_region()
				banner_notify.emit("BOOMTOWN LEVEL %d!" % boomtown_level, "Permintaan ekspor Karesidenan Madiun meningkat!", Color("#d9480f"))
		else:
			last_reg["holdSeconds"] = maxf(0.0, float(last_reg["holdSeconds"]) - dt)

func get_active_goal_region() -> Dictionary:
	for reg in regions:
		if not bool(reg["unlocked"]):
			return reg
	return regions[regions.size() - 1] if not regions.is_empty() else {}

func get_global_delivery_rate_per_min(good_id: String) -> float:
	var cutoff: float = real_time_sec - 60.0
	var count: int = 0
	for f in facilities:
		var k := String(f["kind"])
		if k != "station" and k != "harbour" and k != "market" and k != "factory":
			continue
		var ts: Array = f["deliveredWindow"].get(good_id, [])
		for t in ts:
			if float(t) >= cutoff:
				count += 1
	var win_sec: float = clampf(real_time_sec, 20.0, 60.0)
	return snappedf(float(count) * (60.0 / win_sec), 0.1)

func get_revenue_per_min() -> int:
	var s: int = 0
	for e in revenue_events:
		s += int(e["amount"])
	return s

func get_upkeep_per_min() -> int:
	var s: int = 0
	for ag in agents:
		s += int(GameCatalog.TRUCKS[String(ag["model"])]["upkeep_min"])
	return s

func spawn_toast(pos: Vector2, text: String, col: Color) -> void:
	if floating_toasts.size() > 24:
		floating_toasts.pop_front()
	floating_toasts.append({"pos": pos, "text": text, "color": col, "age": 0.0})

# === SAVE & RESTORE (user://save_<map_id>.json) ===

func save_to_disk() -> void:
	if disable_persistence or current_map_id == "":
		return
	var unlocked_arr: Array[int] = []
	for reg in regions:
		if bool(reg["unlocked"]):
			unlocked_arr.append(int(reg["index"]))
	var offers_arr: Array[String] = []
	for off in road_offers:
		if bool(off["purchased"]):
			offers_arr.append(String(off["id"]))
	var save_roads: Array = []
	for r in roads:
		save_roads.append({
			"id": r["id"], "lf": r["lanesForward"], "lb": r["lanesBackward"],
			"ow": r["oneWay"], "cl": r["closed"], "built": r["isBuilt"]
		})
	var save_juncs: Array = []
	for j in junctions:
		save_juncs.append({
			"id": j["id"], "ctrl": j["control"],
			"ym": j["yieldMinorEdgeIds"], "lt": j.get("light", null)
		})
	var save_facs: Array = []
	for f in facilities:
		save_facs.append({"id": f["id"], "up": f["upgrades"], "out": f["outputBuffer"]})
	var save_routes: Array = []
	for rt in routes:
		save_routes.append({
			"from": rt["fromFacilityId"], "to": rt["toFacilityId"],
			"good": rt["goodFilter"], "wps": rt["waypoints"],
			"model": rt["truckModel"], "cnt": (rt["activeTruckIds"] as Array).size()
		})

	var payload := {
		"v": 1,
		"cash": cash,
		"time": real_time_sec,
		"lht": left_hand_traffic,
		"boom": boomtown_level,
		"lic": unlocked_licenses.keys(),
		"regs": unlocked_arr,
		"offers": offers_arr,
		"roads": save_roads,
		"juncs": save_juncs,
		"facs": save_facs,
		"routes": save_routes
	}
	var f := FileAccess.open("user://save_%s.json" % current_map_id, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload))

func reset_current_map() -> void:
	var path := "user://save_%s.json" % current_map_id
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	load_map(current_map_id, false)

func _restore_save(map_id: String) -> bool:
	var path := "user://save_%s.json" % map_id
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	cash = int(d.get("cash", 3500))
	real_time_sec = float(d.get("time", 0.0))
	left_hand_traffic = bool(d.get("lht", true))
	boomtown_level = int(d.get("boom", 0))
	unlocked_licenses.clear()
	for lk in d.get("lic", ["hauler"]):
		unlocked_licenses[String(lk)] = true
	for r_idx in d.get("regs", [0]):
		var ri: int = int(r_idx)
		if ri >= 0 and ri < regions.size():
			regions[ri]["unlocked"] = true
	for oid in d.get("offers", []):
		for off in road_offers:
			if String(off["id"]) == String(oid):
				off["purchased"] = true
	_rebuild_lookups()
	for sr in d.get("roads", []):
		var rm: Dictionary = road_map.get(String(sr["id"]), {})
		if not rm.is_empty():
			rm["lanesForward"] = int(sr["lf"])
			rm["lanesBackward"] = int(sr["lb"])
			rm["oneWay"] = int(sr["ow"])
			rm["closed"] = bool(sr["cl"])
			rm["isBuilt"] = bool(sr["built"])
	for sj in d.get("juncs", []):
		var jm: Dictionary = junction_map.get(String(sj["id"]), {})
		if not jm.is_empty():
			jm["control"] = String(sj["ctrl"])
			jm["yieldMinorEdgeIds"] = sj["ym"]
			if sj["lt"] != null:
				jm["light"] = sj["lt"]
	for sf in d.get("facs", []):
		var fm: Dictionary = facility_map.get(String(sf["id"]), {})
		if not fm.is_empty():
			fm["upgrades"] = sf["up"]
			fm["outputBuffer"] = int(sf["out"])
	for srt in d.get("routes", []):
		var created: Dictionary = create_route(String(srt["from"]), String(srt["to"]), String(srt["good"]), false)
		if not created.is_empty():
			created["waypoints"] = srt["wps"]
			created["truckModel"] = String(srt["model"])
			recompute_single_route(created)
			for _k in range(int(srt["cnt"])):
				add_truck_to_route(String(created["id"]), true)
	return true
