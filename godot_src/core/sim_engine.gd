class_name SimEngine
extends Node

## Core deterministic simulation engine for Incremental Traffic: Karesidenan Madiun.
## Aligns economy, fleet resale, 44 goods, Station/Harbour storage piles, multi-phase traffic lights,
## directional lanes/pockets/turn-arrows, Express countdown bonus, and alerts with original Incremental Traffic
## while keeping 60-120 FPS fixed-step performance on Android.

signal map_static_dirty
signal region_unlocked(region_name: String, subtitle: String)
signal banner_notify(title: String, subtitle: String, accent: Color)

const HOLD_REQUIRED_SEC: float = 30.0
const SIM_DT: float = 1.0 / 30.0
const MAX_LOAD_WAIT_SEC: float = 20.0
const SCRAP_WAIT_SEC: float = 5.0

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
var depot: Dictionary = {}
var cargo_flights: Array = []

var _uid_counter: int = 100
var _sim_accum: float = 0.0
var _upkeep_timer: float = 0.0
var _history_timer: float = 0.0
var _turn_curve_cache: Dictionary = {}
var _route_rng := RandomNumberGenerator.new()

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
	_route_rng.seed = int(current_map_id.hash()) ^ 0x517cc1b7
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
	_refresh_network_geometry()

	routes.clear()
	agents.clear()
	cargo_flights.clear()
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
		_refresh_network_geometry()
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
		reg["unlockedAtRealSec"] = float(reg.get("unlockedAtRealSec", 0.0 if bool(reg["unlocked"]) else -1.0))

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
		if String(j["control"]) == "lights":
			if not j.has("light") or j["light"] == null:
				j["light"] = _make_default_light(j)
			else:
				_ensure_light_schema(j)

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
		r["pocketLevel"] = int(r.get("pocketLevel", 0))
		var init_pk: int = int(r["pocketLevel"])
		r["pocketSize"] = clampi(int(r.get("pocketSize", maxi(0, init_pk - 1) if init_pk > 0 else 1)), 0, 2)
		r["approachLanesForward"] = clampi(int(r.get("approachLanesForward", int(r["lanesForward"]) + (1 if init_pk > 0 else 0))), int(r["lanesForward"]), 4)
		r["approachLanesBackward"] = clampi(int(r.get("approachLanesBackward", int(r["lanesBackward"]) + (1 if init_pk > 0 else 0))), int(r["lanesBackward"]), 4)
		r["turnMaskForward"] = int(r.get("turnMaskForward", RoutePathfinder.TURN_ALL))
		r["turnMaskBackward"] = int(r.get("turnMaskBackward", RoutePathfinder.TURN_ALL))

	for f in facilities:
		f["pos"] = Vector2(float(f["x"]), float(f["y"]))
		f["color_val"] = Color(String(f.get("color", "#4ea854")))
		f["roof_val"] = Color(String(f.get("roofColor", "#3a7d40")))
		if not f.has("upgrades") or typeof(f["upgrades"]) != TYPE_DICTIONARY:
			f["upgrades"] = {}
		f["upgrades"]["bays"] = clampi(int(f["upgrades"].get("bays", 0)), 0, 7)
		if not f.has("inputBuffers") or typeof(f["inputBuffers"]) != TYPE_DICTIONARY:
			f["inputBuffers"] = {}
		if not f.has("deliveredWindow") or typeof(f["deliveredWindow"]) != TYPE_DICTIONARY:
			f["deliveredWindow"] = {}
		if not f.has("yardPile") or typeof(f["yardPile"]) != TYPE_ARRAY:
			f["yardPile"] = []
		f["outputBuffer"] = int(f.get("outputBuffer", 2 if String(f["kind"]) == "supplier" else 0))
		f["prodProgress"] = float(f.get("prodProgress", 0.0))
		f["stalledReason"] = String(f.get("stalledReason", "none"))
		f["stalledSec"] = float(f.get("stalledSec", 0.0))
		f["lastGrowSec"] = float(f.get("lastGrowSec", -1000.0))
		f["scrappedCount"] = int(f.get("scrappedCount", 0))
		f["occupiedBays"] = 0
		var kind_s := String(f["kind"])
		f["vehiclePresent"] = true
		f["vehicleTimer"] = 18.0
		f["vehicleCapacityRemaining"] = (40 + 20 * int(f["upgrades"].get("shipSize", 0))) if kind_s == "harbour" else (20 + 10 * int(f["upgrades"].get("trainLength", 0)))
		f["boardedSlots"] = 0
		f["vehicleLoaded"] = 0
		f["vehicleCargo"] = []

	if map_def.has("depot") and typeof(map_def["depot"]) == TYPE_DICTIONARY and not (map_def["depot"] as Dictionary).is_empty():
		depot = (map_def["depot"] as Dictionary).duplicate(true)
		depot["pos"] = Vector2(float(depot.get("x", 0.0)), float(depot.get("y", 0.0)))
		depot["angle"] = float(depot.get("angle", 0.0))
		depot["junctionId"] = String(depot.get("junctionId", ""))
		depot["name"] = String(depot.get("name", "Depo Armada"))
	else:
		var fallback_pos: Vector2 = regions[0]["center_vec"] + Vector2(-28.0, 22.0) if not regions.is_empty() else Vector2(80.0, 80.0)
		var fallback_jid: String = String(junctions[0]["id"]) if not junctions.is_empty() else ""
		depot = {"name": "Depo Armada", "pos": fallback_pos, "x": fallback_pos.x, "y": fallback_pos.y, "angle": 0.0, "junctionId": fallback_jid}


func _make_default_light(j: Dictionary = {}) -> Dictionary:
	var lt := {
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
		"lastDetectorHit": 0.0,
		"phases": []
	}
	if not j.is_empty():
		j["light"] = lt
		_ensure_light_schema(j)
	return lt

func _ensure_light_schema(j: Dictionary) -> void:
	if not j.has("light") or typeof(j["light"]) != TYPE_DICTIONARY:
		j["light"] = _make_default_light()
	var lt: Dictionary = j["light"]
	lt["yellow"] = clampf(float(lt.get("yellow", 1.0)), 0.5, 2.5)
	lt["allRed"] = clampf(float(lt.get("allRed", 0.8)), 0.4, 2.5)
	lt["actuated"] = bool(lt.get("actuated", true))
	lt["sensorGap"] = clampf(float(lt.get("sensorGap", 1.5)), 1.0, 4.0)
	lt["currentPhase"] = int(lt.get("currentPhase", 0))
	lt["stage"] = String(lt.get("stage", "green"))
	lt["timer"] = float(lt.get("timer", 10.0))
	lt["greenElapsed"] = float(lt.get("greenElapsed", 0.0))
	lt["lastDetectorHit"] = float(lt.get("lastDetectorHit", 0.0))

	var arm_ids: Array[String] = []
	if j.has("geom") and (j["geom"] as Dictionary).has("arms"):
		for arm in j["geom"]["arms"]:
			arm_ids.append(String(arm["edge_id"]))
	else:
		for eid_v in j.get("connectedEdgeIds", []):
			arm_ids.append(String(eid_v))

	var phases: Array = lt.get("phases", []) if typeof(lt.get("phases", null)) == TYPE_ARRAY else []
	if phases.size() < 2:
		var g_a: float = clampf(float(lt.get("phaseAGreen", 10.0)), 2.0, 60.0)
		var g_b: float = clampf(float(lt.get("phaseBGreen", 10.0)), 2.0, 60.0)
		var arms_a := {}
		var arms_b := {}
		for idx in range(arm_ids.size()):
			var eid: String = arm_ids[idx]
			if idx % 2 == 0:
				arms_a[eid] = RoutePathfinder.TURN_ALL
				arms_b[eid] = 0
			else:
				arms_a[eid] = 0
				arms_b[eid] = RoutePathfinder.TURN_ALL
		phases = [
			{"green": g_a, "arms": arms_a},
			{"green": g_b, "arms": arms_b}
		]
		lt["phases"] = phases
	else:
		# Ensure any newly built road arm is present in phases
		for idx in range(arm_ids.size()):
			var eid: String = arm_ids[idx]
			var has_any_green: bool = false
			for ph in phases:
				var a_map: Dictionary = ph.get("arms", {})
				if int(a_map.get(eid, 0)) != 0:
					has_any_green = true
			if not has_any_green:
				var target_p: int = idx % phases.size()
				if not (phases[target_p] as Dictionary).has("arms"):
					phases[target_p]["arms"] = {}
				phases[target_p]["arms"][eid] = RoutePathfinder.TURN_ALL
	lt["currentPhase"] = clampi(int(lt["currentPhase"]), 0, maxi(0, phases.size() - 1))
	lt["phaseAGreen"] = float(phases[0].get("green", 10.0))
	lt["phaseBGreen"] = float(phases[mini(1, phases.size() - 1)].get("green", 10.0))

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

func _refresh_network_geometry() -> void:
	_turn_curve_cache.clear()
	for j in junctions:
		if String(j["control"]) == "yield" and (j["yieldMinorEdgeIds"] as Array).is_empty():
			var built_edges: Array = []
			for eid_v in j["connectedEdgeIds"]:
				var eid := String(eid_v)
				if road_map.has(eid) and bool(road_map[eid]["isBuilt"]):
					built_edges.append(eid)
			if built_edges.size() >= 3:
				built_edges.sort_custom(func(a, b):
					var ra: Dictionary = road_map[String(a)]
					var rb: Dictionary = road_map[String(b)]
					return (int(ra["lanesForward"]) + int(ra["lanesBackward"])) > (int(rb["lanesForward"]) + int(rb["lanesBackward"]))
				)
				j["yieldMinorEdgeIds"] = built_edges.slice(2)
	RoadGeom.compute_network_junction_geometry(junctions, roads, road_map, left_hand_traffic)
	for j in junctions:
		if String(j["control"]) == "lights":
			_ensure_light_schema(j)

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

func get_next_truck_resale_price(model_id: String) -> int:
	return GameCatalog.compute_truck_resale_price(model_id, get_owned_count_by_model(model_id), agents.size())

func buy_license(model_id: String) -> bool:
	if unlocked_licenses.has(model_id) or not GameCatalog.TRUCKS.has(model_id):
		return false
	var lic: int = int(GameCatalog.TRUCKS[model_id]["license_price"])
	if cash < lic:
		if sfx:
			sfx.warn()
		return false
	cash -= lic
	unlocked_licenses[model_id] = true
	if sfx:
		sfx.play_ui("purchase")
	return true

func get_capacity_slots(f: Dictionary) -> int:
	var up: Dictionary = f["upgrades"]
	var lvl: int = clampi(int(up.get("buffer", 0)), 0, GameCatalog.BUFFER_CAPACITIES.size() - 1)
	return GameCatalog.BUFFER_CAPACITIES[lvl]

func get_hub_vehicle_capacity_slots(f: Dictionary) -> int:
	var kind_s := String(f["kind"])
	if kind_s == "harbour":
		return 40 + 20 * int(f["upgrades"].get("shipSize", 0))
	if kind_s == "station":
		return 20 + 10 * int(f["upgrades"].get("trainLength", 0))
	return 0

## Update 1.10 authentic on-site Station (2.0×) & Harbour (1.6×) storage yard capacity
func get_hub_yard_capacity_slots(f: Dictionary) -> int:
	var kind_s := String(f["kind"])
	var v_cap: int = get_hub_vehicle_capacity_slots(f)
	if kind_s == "station":
		return int(round(float(v_cap) * 2.0))
	if kind_s == "harbour":
		return int(round(float(v_cap) * 1.6))
	return 9999

func get_hub_yard_used_slots(f: Dictionary) -> int:
	var slots: int = 0
	for g_raw in f.get("yardPile", []):
		var gid := String(g_raw)
		if GameCatalog.GOODS.has(gid):
			slots += int(GameCatalog.GOODS[gid]["slots"])
		else:
			slots += 1
	return slots

func get_total_bays(f: Dictionary) -> int:
	return 1 + int(f["upgrades"].get("bays", 0))

func get_supplier_rate_per_min(f: Dictionary) -> int:
	var up: Dictionary = f["upgrades"]
	var expanded: bool = int(up.get("expand", 0)) > 0
	return int(ceil(6.0 * pow(1.25, float(up.get("rate", 0))) * (1.61 if expanded else 1.0) - 0.0001))

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
			"locked": "Maks" if e_lvl >= 1 else ("Butuh Rate Lv.10" if r_lvl < 10 else "")
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
			"desc": "%d slot/KA · Peron %d slot" % [20 + 10 * t_lvl, (20 + 10 * t_lvl) * 2],
			"level": t_lvl, "max": 3,
			"price": GameCatalog.round_2sig(6000.0 * pow(2.0, float(t_lvl))),
			"locked": "Maks" if t_lvl >= 3 else ""
		})
		var tt_lvl: int = int(up.get("timetable", 0))
		list.append({
			"track": "timetable", "label": "Jadwal KA (Timetable)",
			"desc": "Jeda tunggu KA ×%.1f" % GameCatalog.TIMETABLE_WAIT_FACTORS[clampi(tt_lvl, 0, 3)],
			"level": tt_lvl, "max": 3,
			"price": GameCatalog.round_2sig(6000.0 * pow(2.0, float(tt_lvl))),
			"locked": "Maks" if tt_lvl >= 3 else ""
		})
	elif kind_s == "harbour":
		var sh_lvl: int = int(up.get("shipSize", 0))
		list.append({
			"track": "shipSize", "label": "Tonase Kapal Kargo",
			"desc": "%d slot/kapal · Dermaga %d slot" % [40 + 20 * sh_lvl, int(round(float(40 + 20 * sh_lvl) * 1.6))],
			"level": sh_lvl, "max": 3,
			"price": GameCatalog.round_2sig(6000.0 * pow(2.0, float(sh_lvl))),
			"locked": "Maks" if sh_lvl >= 3 else ""
		})
		var tt_lvl: int = int(up.get("timetable", 0))
		list.append({
			"track": "timetable", "label": "Jadwal Pelayaran",
			"desc": "Jeda tunggu kapal ×%.1f" % GameCatalog.TIMETABLE_WAIT_FACTORS[clampi(tt_lvl, 0, 3)],
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
		"price": GameCatalog.round_2sig(500.0 * pow(2.0, float(bay_lvl))),
		"locked": "Maks" if bay_lvl >= 7 else ("Butuh Wide Gate" if needs_gate else "")
	})
	if total_bays >= 6 or int(up.get("wideGate", 0)) > 0:
		var wg: int = int(up.get("wideGate", 0))
		list.append({
			"track": "wideGate", "label": "Gerbang Lebar (Wide Gate)",
			"desc": "Akses 2 lajur & buka >6 bay",
			"level": wg, "max": 1, "price": 10000,
			"locked": "Terpasang" if wg >= 1 else ""
		})
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
			f["lastGrowSec"] = real_time_sec
			spawn_toast(f["pos"] + Vector2(0, -18), "-" + GameCatalog.fmt_cash(pr), Color("#e67e22"))
			map_static_dirty.emit()
			if sfx:
				sfx.play_ui("purchase")
				sfx.play_ui("building_slam")
			return true
	return false

# === STORAGE PADS & CARGO FLIGHTS ===

func get_facility_storage_pads(f: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kind_s := String(f.get("kind", ""))
	var fpos: Vector2 = f.get("pos", Vector2.ZERO)
	var up: Dictionary = f.get("upgrades", {})
	var buf_lv: int = clampi(int(up.get("buffer", 0)), 0, 4)
	var grow_w: float = float(buf_lv) * 0.65
	var grow_h: float = float(buf_lv) * 0.55

	if kind_s == "supplier" and f.get("outputGood", null) != null:
		var og := String(f["outputGood"])
		out.append({
			"role": "output",
			"good": og,
			"pos": fpos + Vector2(15.2 + grow_w * 0.5, 1.5),
			"size": Vector2(11.4 + grow_w, 8.6 + grow_h),
			"buffer_lv": buf_lv,
			"count": int(f.get("outputBuffer", 0)),
			"items": []
		})
	elif kind_s == "factory" and f.get("outputGood", null) != null:
		var og := String(f["outputGood"])
		if GameCatalog.GOODS.has(og):
			var inputs: Array = GameCatalog.GOODS[og]["inputs"]
			var n_in: int = inputs.size()
			var in_bufs: Dictionary = f.get("inputBuffers", {})
			for i in range(n_in):
				var ig := String(inputs[i]["good"])
				var y_off: float = (float(i) - float(n_in - 1) * 0.5) * (8.8 + grow_h * 0.5) + 1.0
				out.append({
					"role": "input",
					"good": ig,
					"pos": fpos + Vector2(-15.2 - grow_w * 0.5, y_off),
					"size": Vector2(10.6 + grow_w, 7.8 + grow_h * 0.7),
					"buffer_lv": buf_lv,
					"count": int(in_bufs.get(ig, 0)),
					"items": []
				})
		out.append({
			"role": "output",
			"good": og,
			"pos": fpos + Vector2(15.2 + grow_w * 0.5, 1.5),
			"size": Vector2(11.4 + grow_w, 8.6 + grow_h),
			"buffer_lv": buf_lv,
			"count": int(f.get("outputBuffer", 0)),
			"items": []
		})
	elif kind_s == "station" or kind_s == "harbour":
		var hub_lv: int = clampi(int(up.get("shipSize" if kind_s == "harbour" else "trainLength", 0)), 0, 3)
		var off: Vector2 = Vector2(-16.5, 2.5) if kind_s == "station" else Vector2(-18.5, 3.0)
		var pile: Array = f.get("yardPile", [])
		out.append({
			"role": "yard",
			"good": "",
			"pos": fpos + off,
			"size": Vector2(13.2 + float(hub_lv) * 1.1, 9.6 + float(hub_lv) * 0.8),
			"buffer_lv": mini(4, hub_lv + 1),
			"count": pile.size(),
			"items": pile
		})
	return out

func get_facility_pad_world_pos(f: Dictionary, role: String, good_id: String = "") -> Vector2:
	for pad in get_facility_storage_pads(f):
		if String(pad["role"]) == role and (good_id == "" or String(pad["good"]) == "" or String(pad["good"]) == good_id):
			return pad["pos"]
	return f.get("pos", Vector2.ZERO)

func get_facility_vehicle_world_pos(f: Dictionary) -> Vector2:
	var kind_s := String(f.get("kind", ""))
	var fpos: Vector2 = f.get("pos", Vector2.ZERO)
	if kind_s == "station":
		return fpos + Vector2(0.0, 16.2)
	if kind_s == "harbour":
		return fpos + Vector2(2.0, 18.5)
	return fpos

func launch_cargo_hop(good_id: String, from_pos: Vector2, to_pos: Vector2) -> void:
	if good_id == "" or not GameCatalog.GOODS.has(good_id):
		return
	if cargo_flights.size() >= 72:
		cargo_flights.pop_front()
	var dist: float = from_pos.distance_to(to_pos)
	var dur: float = clampf(0.38 + dist / 216.0, 0.38, 0.95)
	cargo_flights.append({
		"kind": "hop",
		"good": good_id,
		"from": from_pos,
		"to": to_pos,
		"t": 0.0,
		"dur": dur,
		"ring": -1.0
	})

func launch_cargo_crumble(good_id: String, pos: Vector2) -> void:
	if good_id == "" or not GameCatalog.GOODS.has(good_id):
		return
	if cargo_flights.size() >= 72:
		cargo_flights.pop_front()
	cargo_flights.append({
		"kind": "crumble",
		"good": good_id,
		"pos": pos,
		"rot": _route_rng.randf_range(-0.45, 0.45),
		"t": 0.0,
		"dur": 0.55,
		"seed": int(_route_rng.randi() & 0x7fffffff)
	})

static func _make_initial_unit_poses(model_id: String, origin_pos: Vector2, heading: float = 0.0) -> Array:
	var units: Array[Dictionary] = GameCatalog.get_truck_units(model_id)
	var cab_mid: float = (float(units[0]["front"]) + float(units[0]["rear"])) * 0.5
	var dir := Vector2(cos(heading), sin(heading))
	var poses: Array = []
	for u in units:
		var u_mid: float = (float(u["front"]) + float(u["rear"])) * 0.5
		var back_px: float = (u_mid - cab_mid) * GameCatalog.TRUCK_VIEW_SCALE
		poses.append({"pos": origin_pos - dir * back_px, "heading": heading})
	return poses

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

	var taken_colors: Array = []
	for existing_rt in routes:
		taken_colors.append(existing_rt["color"])
	var color_seed_good: String = resolved_good if resolved_good != "any" else (String(f_from["outputGood"]) if f_from.get("outputGood", null) != null else "")
	var col: Color = GameCatalog.pick_route_color(_route_rng, taken_colors, color_seed_good)
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
		"waypointsBack": [],
		"sameWayBack": true,
		"truckModel": "hauler",
		"forwardPath": [],
		"returnPath": [],
		"clearTimeForwardSec": 8.0,
		"brokenReason": "",
		"brokenKind": "",
		"brokenTag": "",
		"brokenEdgeId": "",
		"brokenJunctionId": "",
		"brokenPos": Vector2.INF,
		"activeTruckIds": [],
		"totalRevenue": 0,
		"deliveriesCount": 0,
		"openedAtSec": real_time_sec
	}
	recompute_single_route(rt)
	routes.append(rt)
	if buy_first_truck:
		add_truck_to_route(String(rt["id"]), false)
	if sfx:
		sfx.play_ui("route_opened")
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
				sfx.play_ui("remove")
			return

func toggle_route_waypoint(route_id: String, junction_id: String, is_return_leg: bool = false) -> void:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty():
		return
	var f_from: Dictionary = facility_map[String(rt["fromFacilityId"])]
	var f_to: Dictionary = facility_map[String(rt["toFacilityId"])]
	if junction_id == String(f_from["junctionId"]) or junction_id == String(f_to["junctionId"]):
		return
	var use_back: bool = is_return_leg and not bool(rt.get("sameWayBack", true))
	if not rt.has("waypointsBack") or typeof(rt["waypointsBack"]) != TYPE_ARRAY:
		rt["waypointsBack"] = []
	var wps: Array = rt["waypointsBack"] if use_back else rt["waypoints"]
	var idx: int = wps.find(junction_id)
	if idx >= 0:
		wps.remove_at(idx)
	else:
		if wps.size() >= 4:
			wps.pop_front()
		wps.append(junction_id)
	recompute_single_route(rt)
	if sfx:
		sfx.play_ui("edit")

func set_route_same_way_back(route_id: String, enabled: bool) -> void:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty():
		return
	var prev_swb: bool = bool(rt.get("sameWayBack", true))
	rt["sameWayBack"] = enabled
	if not enabled and prev_swb:
		if not rt.has("waypointsBack") or (rt["waypointsBack"] as Array).is_empty():
			var rev: Array = (rt.get("waypoints", []) as Array).duplicate()
			rev.reverse()
			rt["waypointsBack"] = rev
	recompute_single_route(rt)
	if sfx:
		sfx.play_ui("tick")

func clear_route_waypoints(route_id: String, is_return_leg: bool = false) -> void:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty():
		return
	if is_return_leg and not bool(rt.get("sameWayBack", true)):
		if rt.has("waypointsBack"):
			(rt["waypointsBack"] as Array).clear()
	else:
		(rt["waypoints"] as Array).clear()
		if bool(rt.get("sameWayBack", true)) and rt.has("waypointsBack"):
			(rt["waypointsBack"] as Array).clear()
	recompute_single_route(rt)
	if sfx:
		sfx.play_ui("remove")

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
	if not rt.has("waypointsBack") or typeof(rt["waypointsBack"]) != TYPE_ARRAY:
		rt["waypointsBack"] = []
	var wps_fwd: Array = rt.get("waypoints", [])
	var fwd: Dictionary = RoutePathfinder.find_directed_path(
		String(f_from["junctionId"]),
		String(f_to["junctionId"]),
		wps_fwd,
		junction_map,
		road_map,
		unlocked_regions,
		String(rt["truckModel"])
	)
	var swb: bool = bool(rt.get("sameWayBack", true))
	var ret_wps: Array = []
	if swb:
		if not wps_fwd.is_empty():
			ret_wps = wps_fwd.duplicate()
			ret_wps.reverse()
	else:
		ret_wps = rt.get("waypointsBack", [])

	var ret: Dictionary = RoutePathfinder.find_directed_path(
		String(f_to["junctionId"]),
		String(f_from["junctionId"]),
		ret_wps,
		junction_map,
		road_map,
		unlocked_regions,
		String(rt["truckModel"])
	)
	# Graceful fallback to direct return ONLY when sameWayBack auto-reversed waypoints hit a one-way street
	if swb and String(ret["broken_reason"]) != "" and not ret_wps.is_empty():
		var ret_direct: Dictionary = RoutePathfinder.find_directed_path(
			String(f_to["junctionId"]),
			String(f_from["junctionId"]),
			[],
			junction_map,
			road_map,
			unlocked_regions,
			String(rt["truckModel"])
		)
		if String(ret_direct["broken_reason"]) == "":
			ret = ret_direct

	rt["forwardPath"] = fwd["steps"]
	rt["returnPath"] = ret["steps"]
	rt["clearTimeForwardSec"] = maxf(3.0, float(fwd["clear_time_sec"]))
	var fault_src: Dictionary = fwd if String(fwd["broken_reason"]) != "" else ret
	rt["brokenReason"] = String(fault_src.get("broken_reason", ""))
	rt["brokenKind"] = String(fault_src.get("broken_kind", ""))
	rt["brokenTag"] = String(fault_src.get("broken_tag", ""))
	rt["brokenEdgeId"] = String(fault_src.get("broken_edge_id", ""))
	rt["brokenJunctionId"] = String(fault_src.get("broken_junction_id", ""))
	rt["brokenPos"] = fault_src.get("broken_pos", Vector2.INF)

func recompute_all_routes() -> void:
	for rt in routes:
		recompute_single_route(rt)

func add_truck_to_route(route_id: String, free_starter: bool = false) -> bool:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty():
		return false
	var model_id := String(rt["truckModel"])
	var tdef: Dictionary = GameCatalog.TRUCKS[model_id]
	var g_filter := String(rt.get("goodFilter", "any"))
	if g_filter != "any" and GameCatalog.GOODS.has(g_filter):
		if GameCatalog.compute_max_carry_units(model_id, g_filter) <= 0:
			if sfx:
				sfx.warn()
			return false

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
	var unit_poses: Array = _make_initial_unit_poses(model_id, fpos, 0.0)
	var tr_poses: Array = unit_poses.slice(1)

	var ag := {
		"id": _next_uid("trk"),
		"routeId": route_id,
		"model": model_id,
		"isStarter": free_starter,
		"state": "loading",
		"waitReason": "none",
		"lastIssue": "",
		"stepIndex": 0,
		"sPx": 0.0,
		"laneIndex": 0,
		"visualLane": 0.0,
		"speedPx": 0.0,
		"braking": false,
		"turnSignal": 0,
		"cargoGood": "",
		"cargoQty": 0,
		"departedSec": real_time_sec,
		"expressWindowSec": 0.0,
		"expressDeadlineSec": 0.0,
		"expressBonusLocked": -1.0,
		"dwellSec": 0.35 + float((rt["activeTruckIds"] as Array).size()) * 0.55,
		"waitSec": 0.0,
		"junctionWaitSec": 0.0,
		"gridlockSec": 0.0,
		"pos": fpos,
		"heading": 0.0,
		"unitPoses": unit_poses,
		"trailerPoses": tr_poses,
		"depotPath": [],
		"blockerAgentId": ""
	}
	agents.append(ag)
	(rt["activeTruckIds"] as Array).append(ag["id"])
	if not free_starter:
		spawn_toast(fpos + Vector2(0, -14), "-" + GameCatalog.fmt_cash(price), Color("#e67e22"))
		if sfx:
			sfx.play_ui("purchase")
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
			var model_id := String(ag["model"])
			var owned_m: int = get_owned_count_by_model(model_id)
			var total_f: int = agents.size()
			var refund: int = GameCatalog.compute_truck_resale_price(model_id, owned_m, total_f)
			cash += refund
			spawn_toast(ag["pos"] + Vector2(0, -12), "+" + GameCatalog.fmt_cash(refund), Color("#2b8a3e"))
			agents.remove_at(i)
			break
	tids.erase(target_id)
	if sfx:
		sfx.play_ui("sell")
	return true

func quote_route_model_swap(route_id: String, target_model: String) -> Dictionary:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty() or not GameCatalog.TRUCKS.has(target_model):
		return {}
	var count: int = (rt["activeTruckIds"] as Array).size()
	var lic: int = 0 if unlocked_licenses.has(target_model) else int(GameCatalog.TRUCKS[target_model]["license_price"])
	var old_model := String(rt["truckModel"])
	var owned_old: int = get_owned_count_by_model(old_model)
	var fleet_cur: int = agents.size()
	var refund: int = 0
	for i in range(count):
		refund += GameCatalog.compute_truck_resale_price(old_model, maxi(1, owned_old - i), maxi(1, fleet_cur - i))

	var owned_target: int = get_owned_count_by_model(target_model)
	if old_model == target_model:
		owned_target = maxi(0, owned_target - count)
	var fleet_after_sell: int = maxi(0, fleet_cur - count)
	var buy_cost: int = 0
	for i in range(count):
		buy_cost += GameCatalog.compute_truck_buy_price(target_model, owned_target + i, fleet_after_sell + i)

	var compatible: bool = true
	var gf := String(rt.get("goodFilter", "any"))
	if gf != "any" and GameCatalog.GOODS.has(gf):
		compatible = GameCatalog.compute_max_carry_units(target_model, gf) > 0

	return {
		"targetModel": target_model,
		"count": count,
		"license": lic,
		"refund": refund,
		"buyCost": buy_cost,
		"netCost": lic + buy_cost - refund,
		"compatible": compatible
	}

func apply_route_model_swap(route_id: String, target_model: String) -> bool:
	var rt: Dictionary = get_route(route_id)
	if rt.is_empty() or String(rt["truckModel"]) == target_model:
		return false
	var q: Dictionary = quote_route_model_swap(route_id, target_model)
	if q.is_empty() or not bool(q.get("compatible", true)):
		if sfx:
			sfx.warn()
		return false
	var net: int = int(q["netCost"])
	if cash < net:
		if sfx:
			sfx.warn()
		return false
	cash -= net
	unlocked_licenses[target_model] = true
	rt["truckModel"] = target_model
	for ag in agents:
		if String(ag["routeId"]) == route_id:
			ag["model"] = target_model
			var uposes: Array = _make_initial_unit_poses(target_model, ag["pos"], float(ag["heading"]))
			ag["unitPoses"] = uposes
			ag["trailerPoses"] = uposes.slice(1)
	recompute_single_route(rt)
	if sfx:
		sfx.play_ui("purchase")
	return true

# === TRUCK INSPECTOR & FLEET INTERVENTION (`truck_inspector.gd`) ===

func get_agent(agent_id: String) -> Dictionary:
	for ag in agents:
		if String(ag["id"]) == agent_id:
			return ag
	return {}

func get_agent_resale_value(ag: Dictionary) -> int:
	if ag.is_empty():
		return 0
	var model_id := String(ag.get("model", "hauler"))
	return GameCatalog.compute_truck_resale_price(model_id, get_owned_count_by_model(model_id), agents.size())

func sell_agent(agent_id: String) -> int:
	var ag: Dictionary = get_agent(agent_id)
	if ag.is_empty():
		return 0
	var refund: int = get_agent_resale_value(ag)
	if remove_truck_from_route(String(ag["routeId"]), agent_id):
		return refund
	return 0

func hit_test_agent(world_pos: Vector2, max_dist: float = 10.5, include_parked: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = max_dist
	for ag in agents:
		var st := String(ag["state"])
		if not include_parked and (st == "loading" or st == "unloading"):
			continue
		var uposes: Array = ag.get("unitPoses", [])
		if uposes.is_empty():
			var d0: float = (ag["pos"] as Vector2).distance_to(world_pos)
			if d0 < best_d:
				best_d = d0
				best = ag
		else:
			for up in uposes:
				var du: float = (up["pos"] as Vector2).distance_to(world_pos)
				if du < best_d:
					best_d = du
					best = ag
	return best

func leave_bay_early(agent_id: String) -> bool:
	var ag: Dictionary = get_agent(agent_id)
	if ag.is_empty():
		return false
	var rt: Dictionary = get_route(String(ag["routeId"]))
	if rt.is_empty() or String(rt.get("brokenReason", "")) != "":
		return false
	var st := String(ag["state"])
	if st == "loading":
		ag["dwellSec"] = 0.0
		ag["waitSec"] = 0.0
		ag["waitReason"] = "none"
		ag["departedSec"] = real_time_sec
		ag["state"] = "driving_outbound"
		ag["stepIndex"] = 0
		ag["sPx"] = 0.0
		ag["lastIssue"] = "Diminta berangkat dari dermaga muat"
		if sfx:
			sfx.play_ui("tick")
		return true
	if st == "queuing_bay" or st == "unloading":
		var c_good := String(ag.get("cargoGood", ""))
		var c_qty: int = int(ag.get("cargoQty", 0))
		if c_good != "" and c_qty > 0 and GameCatalog.GOODS.has(c_good):
			var f_to: Dictionary = facility_map.get(String(rt["toFacilityId"]), {})
			var scrap_pay: int = maxi(1, int(round(float(int(GameCatalog.GOODS[c_good]["value"]) * c_qty) * 0.10)))
			cash += scrap_pay
			revenue_events.append({"t": real_time_sec, "amount": scrap_pay})
			if not f_to.is_empty():
				f_to["scrappedCount"] = int(f_to.get("scrappedCount", 0)) + c_qty
				launch_cargo_crumble(c_good, f_to["pos"])
				spawn_toast(f_to["pos"] + Vector2(0, -14), "Scrap +" + GameCatalog.fmt_cash(scrap_pay), Color("#868e96"))
		ag["cargoGood"] = ""
		ag["cargoQty"] = 0
		ag["expressBonusLocked"] = -1.0
		ag["state"] = "driving_return"
		ag["stepIndex"] = 0
		ag["sPx"] = 0.0
		ag["waitSec"] = 0.0
		ag["waitReason"] = "none"
		if sfx:
			sfx.play_ui("tick")
		return true
	return false

func send_agent_to_depot(agent_id: String) -> bool:
	var ag: Dictionary = get_agent(agent_id)
	if ag.is_empty() or depot.is_empty():
		return false
	var c_good := String(ag.get("cargoGood", ""))
	if c_good != "" and int(ag.get("cargoQty", 0)) > 0:
		launch_cargo_crumble(c_good, ag["pos"])
	ag["cargoGood"] = ""
	ag["cargoQty"] = 0
	ag["expressBonusLocked"] = -1.0
	ag["waitSec"] = 0.0
	ag["waitReason"] = "none"
	ag["blockerAgentId"] = ""

	var start_jid: String = ""
	var sd: Dictionary = _get_agent_current_step(ag)
	if not sd.is_empty():
		start_jid = String(sd.get("toJunctionId", ""))
	else:
		var rt: Dictionary = get_route(String(ag["routeId"]))
		if not rt.is_empty():
			var fid: String = String(rt["toFacilityId"]) if (String(ag["state"]) == "unloading" or String(ag["state"]) == "queuing_bay") else String(rt["fromFacilityId"])
			if facility_map.has(fid):
				start_jid = String(facility_map[fid]["junctionId"])

	var depot_jid := String(depot.get("junctionId", ""))
	if start_jid != "" and depot_jid != "" and start_jid != depot_jid and junction_map.has(start_jid) and junction_map.has(depot_jid):
		var dp: Dictionary = RoutePathfinder.find_directed_path(start_jid, depot_jid, [], junction_map, road_map, unlocked_regions, String(ag["model"]))
		var steps: Array = dp.get("steps", [])
		if not steps.is_empty() and String(dp.get("broken_reason", "")) == "":
			ag["depotPath"] = steps
			ag["state"] = "driving_to_depot"
			ag["stepIndex"] = 0
			ag["sPx"] = 0.0
			if sfx:
				sfx.play_ui("tick")
			return true

	ag["depotPath"] = []
	ag["state"] = "at_depot"
	ag["dwellSec"] = 1.4
	ag["speedPx"] = 0.0
	ag["pos"] = depot.get("pos", ag["pos"])
	var d_ang: float = float(depot.get("angle", 0.0))
	ag["heading"] = d_ang
	var uposes: Array = _make_initial_unit_poses(String(ag["model"]), ag["pos"], d_ang)
	ag["unitPoses"] = uposes
	ag["trailerPoses"] = uposes.slice(1)
	if sfx:
		sfx.play_ui("tick")
	return true

func get_agent_blocking_chain(ag: Dictionary) -> Dictionary:
	var links: Array[Dictionary] = []
	var visited: Dictionary = {String(ag.get("id", "")): true}
	var cur: Dictionary = ag
	var is_gridlock: bool = false
	var root_cause_pos: Vector2 = ag.get("pos", Vector2.ZERO)
	var root_reason: String = String(ag.get("waitReason", "none"))
	for _depth in range(8):
		var bid := String(cur.get("blockerAgentId", ""))
		if bid == "":
			break
		var blk: Dictionary = get_agent(bid)
		if blk.is_empty():
			break
		links.append({
			"fromId": String(cur["id"]),
			"toId": bid,
			"fromPos": cur["pos"],
			"toPos": blk["pos"],
			"reason": String(blk.get("waitReason", "none"))
		})
		root_cause_pos = blk["pos"]
		root_reason = String(blk.get("waitReason", "none"))
		if visited.has(bid):
			is_gridlock = true
			break
		visited[bid] = true
		cur = blk
	return {
		"links": links,
		"isGridlock": is_gridlock,
		"rootPos": root_cause_pos,
		"rootReason": root_reason
	}

func diagnose_agent(ag: Dictionary) -> Dictionary:
	if ag.is_empty():
		return {}
	var rt: Dictionary = get_route(String(ag.get("routeId", "")))
	var st := String(ag.get("state", "loading"))
	var wr := String(ag.get("waitReason", "none"))
	var ws: float = float(ag.get("waitSec", 0.0))
	var chain_info: Dictionary = get_agent_blocking_chain(ag)
	var status_label := "Mengemudi"
	var wait_label := ""
	var cause_pos: Vector2 = ag.get("pos", Vector2.ZERO)
	var has_cause: bool = false

	match st:
		"loading":
			status_label = "Di dermaga muat asal"
			if wr == "broken_route":
				wait_label = "Rute terputus: %s" % String(rt.get("brokenReason", ""))
				var bp: Vector2 = rt.get("brokenPos", Vector2.INF)
				if bp.is_finite():
					cause_pos = bp
					has_cause = true
			elif wr == "cargo_wait":
				wait_label = "Menunggu produksi muatan (%.0f / %.0f dtk)" % [ws, MAX_LOAD_WAIT_SEC]
				cause_pos = ag["pos"]
				has_cause = true
			else:
				wait_label = "Memuat kargo ke trailer..."
		"queuing_bay":
			status_label = "Antre masuk dermaga tujuan"
			wait_label = "Semua dermaga bongkar penuh (%.0f dtk)" % ws
			if not rt.is_empty() and facility_map.has(String(rt["toFacilityId"])):
				cause_pos = facility_map[String(rt["toFacilityId"])]["pos"]
				has_cause = true
		"unloading":
			status_label = "Membongkar muatan"
			if wr == "scrap_wait":
				wait_label = "Gudang tujuan penuh! Scrap dalam %.1f dtk" % maxf(0.0, SCRAP_WAIT_SEC - ws)
				cause_pos = ag["pos"]
				has_cause = true
			else:
				wait_label = "Bongkar kargo ke gudang..."
		"driving_outbound":
			status_label = "Mengantar kargo ke tujuan"
		"driving_return":
			status_label = "Kembali ke fasilitas asal"
		"driving_to_depot":
			status_label = "Menuju Depo Armada"
		"driving_from_depot":
			status_label = "Kembali ke rute dari Depo"
		"at_depot":
			status_label = "Siaga di Depo Armada"

	if st in ["driving_outbound", "driving_return", "driving_to_depot", "driving_from_depot"]:
		if bool(chain_info["isGridlock"]):
			wait_label = "GRIDLOCK — rantai antrean melingkar!"
			cause_pos = chain_info["rootPos"]
			has_cause = true
		elif wr == "red_light":
			wait_label = "Berhenti di lampu merah"
			var sd: Dictionary = _get_agent_current_step(ag)
			if not sd.is_empty() and junction_map.has(String(sd["toJunctionId"])):
				cause_pos = junction_map[String(sd["toJunctionId"])]["pos"]
				has_cause = true
		elif wr == "yield":
			wait_label = "Memberi jalan (Yield) pada arus utama"
			var sd2: Dictionary = _get_agent_current_step(ag)
			if not sd2.is_empty() and junction_map.has(String(sd2["toJunctionId"])):
				cause_pos = junction_map[String(sd2["toJunctionId"])]["pos"]
				has_cause = true
		elif wr == "roundabout":
			wait_label = "Menunggu celah masuk bundaran"
			var sd3: Dictionary = _get_agent_current_step(ag)
			if not sd3.is_empty() and junction_map.has(String(sd3["toJunctionId"])):
				cause_pos = junction_map[String(sd3["toJunctionId"])]["pos"]
				has_cause = true
		elif wr == "following":
			var links: Array = chain_info["links"]
			wait_label = "Mengikuti %d truk di depan (%s)" % [maxi(1, links.size()), String(chain_info["rootReason"])]
			cause_pos = chain_info["rootPos"]
			has_cause = true

	return {
		"status": status_label,
		"waiting": wait_label,
		"hasCause": has_cause,
		"causePos": cause_pos,
		"chain": chain_info["links"],
		"isGridlock": bool(chain_info["isGridlock"])
	}

func get_agent_remaining_polyline(ag: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	if ag.is_empty():
		return out
	var st := String(ag.get("state", ""))
	if st not in ["driving_outbound", "driving_return", "driving_to_depot", "driving_from_depot"]:
		return out
	var rt: Dictionary = get_route(String(ag.get("routeId", "")))
	var path: Array = _get_agent_active_path(ag, rt)
	var s_idx: int = int(ag.get("stepIndex", 0))
	if s_idx < 0 or s_idx >= path.size():
		return out
	out.append(ag["pos"])
	for idx in range(s_idx, path.size()):
		var eid := String(path[idx]["edgeId"])
		if not road_map.has(eid):
			continue
		var traj: Dictionary = _get_step_trajectory(path, idx, int(ag.get("laneIndex", 0)) if idx == s_idx else 0)
		var pts: PackedVector2Array = traj["pts"]
		var cum: PackedFloat32Array = traj["cum_len"]
		var tot_l: float = float(traj["total_len"])
		var s0: float = clampf(float(ag.get("sPx", 0.0)), 0.0, tot_l) if idx == s_idx else 0.0
		var sl: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, s0, tot_l)
		for p in sl:
			if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.3:
				out.append(p)
	return out



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
			_refresh_network_geometry()
			recompute_all_routes()
			map_static_dirty.emit()
			if sfx:
				sfx.play_ui("remove")
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
		_refresh_network_geometry()
		recompute_all_routes()
		map_static_dirty.emit()
		if sfx:
			sfx.play_ui("place")
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
			_refresh_network_geometry()
			recompute_all_routes()
			map_static_dirty.emit()
			if sfx:
				sfx.play_ui("purchase")
			return "Bundaran ditingkatkan ke 2 Lajur!"
		if cur_ctrl == "roundabout2":
			var ref2: int = int(round(float(int(GameCatalog.INFRA_PRICES["roundabout"]) + int(GameCatalog.INFRA_PRICES["roundabout2_upgrade"])) * 0.5))
			cash += ref2
			j["control"] = "none"
			spawn_toast(j["pos"] + Vector2(0, -16), "+" + GameCatalog.fmt_cash(ref2), Color("#2b8a3e"))
			_refresh_network_geometry()
			recompute_all_routes()
			map_static_dirty.emit()
			if sfx:
				sfx.play_ui("remove")
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
		_refresh_network_geometry()
		recompute_all_routes()
		map_static_dirty.emit()
		if sfx:
			sfx.play_ui("place")
		return "Bundaran dibangun!"

	if tool == "lights":
		if cur_ctrl == "lights":
			_ensure_light_schema(j)
			if sfx:
				sfx.play_ui("edit")
			return "Mengatur fase & sensor lampu lalu lintas"
		var lt_p: int = int(GameCatalog.INFRA_PRICES["light"])
		if cash < lt_p:
			if sfx:
				sfx.warn()
			return "Kas kurang (%s)" % GameCatalog.fmt_cash(lt_p)
		_refund_junction_hardware(j)
		cash -= lt_p
		j["control"] = "lights"
		_make_default_light(j)
		spawn_toast(j["pos"] + Vector2(0, -16), "-" + GameCatalog.fmt_cash(lt_p), Color("#e67e22"))
		_refresh_network_geometry()
		recompute_all_routes()
		map_static_dirty.emit()
		if sfx:
			sfx.play_ui("place")
		return "Lampu lalu lintas multi-fase dipasang!"

	return ""

func rotate_yield_priority(junction_id: String) -> String:
	if not junction_map.has(junction_id):
		return ""
	var j: Dictionary = junction_map[junction_id]
	if String(j["control"]) != "yield":
		return ""
	var built: Array = []
	for eid_v in j["connectedEdgeIds"]:
		var eid := String(eid_v)
		if road_map.has(eid) and bool(road_map[eid]["isBuilt"]):
			built.append(eid)
	if built.size() < 3:
		return ""
	var cur_minor: Array = j["yieldMinorEdgeIds"]
	var first_major_idx: int = 0
	for i in range(built.size()):
		if not cur_minor.has(built[i]):
			first_major_idx = i
			break
	var next_m0: int = (first_major_idx + 1) % built.size()
	var next_m1: int = (next_m0 + 1) % built.size()
	var new_minor: Array = []
	for i in range(built.size()):
		if i != next_m0 and i != next_m1:
			new_minor.append(built[i])
	j["yieldMinorEdgeIds"] = new_minor
	_refresh_network_geometry()
	recompute_all_routes()
	map_static_dirty.emit()
	if sfx:
		sfx.play_ui("edit")
	return "Poros utama Yield diputar"

# === MULTI-PHASE TRAFFIC LIGHT CONTROLS ===

func add_light_phase(junction_id: String) -> bool:
	if not junction_map.has(junction_id):
		return false
	var j: Dictionary = junction_map[junction_id]
	if String(j["control"]) != "lights":
		return false
	_ensure_light_schema(j)
	var phases: Array = j["light"]["phases"]
	if phases.size() >= 4:
		return false
	var arms_new := {}
	var conn: Array = j["connectedEdgeIds"]
	if not conn.is_empty():
		var pick_eid := String(conn[phases.size() % conn.size()])
		arms_new[pick_eid] = RoutePathfinder.TURN_ALL
	phases.append({"green": 10.0, "arms": arms_new})
	recompute_all_routes()
	map_static_dirty.emit()
	if sfx:
		sfx.play_ui("edit")
	return true

func remove_light_phase(junction_id: String, phase_idx: int) -> bool:
	if not junction_map.has(junction_id):
		return false
	var j: Dictionary = junction_map[junction_id]
	if String(j["control"]) != "lights":
		return false
	_ensure_light_schema(j)
	var lt: Dictionary = j["light"]
	var phases: Array = lt["phases"]
	if phases.size() <= 2 or phase_idx < 0 or phase_idx >= phases.size():
		return false
	phases.remove_at(phase_idx)
	lt["currentPhase"] = clampi(int(lt["currentPhase"]), 0, phases.size() - 1)
	lt["phaseAGreen"] = float(phases[0]["green"])
	lt["phaseBGreen"] = float(phases[mini(1, phases.size() - 1)]["green"])
	recompute_all_routes()
	map_static_dirty.emit()
	if sfx:
		sfx.play_ui("remove")
	return true

func set_light_phase_green(junction_id: String, phase_idx: int, seconds: float) -> void:
	if not junction_map.has(junction_id):
		return
	var j: Dictionary = junction_map[junction_id]
	if String(j["control"]) != "lights":
		return
	_ensure_light_schema(j)
	var lt: Dictionary = j["light"]
	var phases: Array = lt["phases"]
	if phase_idx < 0 or phase_idx >= phases.size():
		return
	var g_sec: float = clampf(seconds, 2.0, 60.0)
	phases[phase_idx]["green"] = g_sec
	if phase_idx == 0:
		lt["phaseAGreen"] = g_sec
	elif phase_idx == 1:
		lt["phaseBGreen"] = g_sec

const TURN_MASK_CYCLE: Array[int] = [0, 7, 3, 6, 2, 1, 4]

static func format_turn_mask(mask: int) -> String:
	match mask:
		0:
			return "STOP"
		7:
			return "↰↑↱ Semua"
		3:
			return "↰↑ Kiri+Lurus"
		6:
			return "↑↱ Lurus+Kanan"
		2:
			return "↑ Lurus"
		1:
			return "↰ Belok Kiri"
		4:
			return "↱ Belok Kanan"
	return "↰↑↱"

func cycle_light_arm_turn_mask(junction_id: String, phase_idx: int, edge_id: String) -> int:
	if not junction_map.has(junction_id):
		return 0
	var j: Dictionary = junction_map[junction_id]
	if String(j["control"]) != "lights":
		return 0
	_ensure_light_schema(j)
	var phases: Array = j["light"]["phases"]
	if phase_idx < 0 or phase_idx >= phases.size():
		return 0
	var arms: Dictionary = phases[phase_idx]["arms"]
	var cur: int = int(arms.get(edge_id, 0))
	var pos: int = TURN_MASK_CYCLE.find(cur)
	var nxt: int = TURN_MASK_CYCLE[(pos + 1) % TURN_MASK_CYCLE.size()]
	arms[edge_id] = nxt
	recompute_all_routes()
	map_static_dirty.emit()
	if sfx:
		sfx.play_ui("tick")
	return nxt

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
	_refresh_network_geometry()
	recompute_all_routes()
	map_static_dirty.emit()
	if sfx:
		sfx.play_ui("remove")

func _refund_junction_hardware(j: Dictionary) -> void:
	var c := String(j["control"])
	if c == "lights":
		cash += int(round(float(GameCatalog.INFRA_PRICES["light"]) * 0.5))
		j.erase("light")
	elif c == "roundabout":
		cash += int(round(float(GameCatalog.INFRA_PRICES["roundabout"]) * 0.5))
	elif c == "roundabout2":
		cash += int(round(float(int(GameCatalog.INFRA_PRICES["roundabout"]) + int(GameCatalog.INFRA_PRICES["roundabout2_upgrade"])) * 0.5))

func modify_road_lanes(edge_id: String, delta: int, dir_mode: String = "both") -> String:
	if not road_map.has(edge_id):
		return ""
	var r: Dictionary = road_map[edge_id]
	if not bool(r["isBuilt"]) or not unlocked_regions.has(int(r["regionIndex"])):
		return ""
	var pts: PackedVector2Array = r["pts"]
	var mid: Vector2 = pts[pts.size() / 2]
	var lf: int = int(r["lanesForward"])
	var lb: int = int(r["lanesBackward"])
	var edit_f: bool = (dir_mode == "both" or dir_mode == "forward")
	var edit_b: bool = (dir_mode == "both" or dir_mode == "backward")
	var unit_scale: float = 0.5 if dir_mode != "both" else 1.0

	if delta > 0:
		if (edit_f and lf >= 4) or (edit_b and lb >= 4):
			return "Maksimal 4 lajur per arah"
		var top_nxt: int = maxi(lf + (1 if edit_f else 0), lb + (1 if edit_b else 0))
		var base_p: int = GameCatalog.round_2sig(float(GameCatalog.INFRA_PRICES["lane_base"]) + float(GameCatalog.INFRA_PRICES["lane_per_px"]) * float(r["lengthPx"])) * maxi(1, top_nxt - 1)
		var price: int = maxi(250, int(round(float(base_p) * unit_scale)))
		if cash < price:
			if sfx:
				sfx.warn()
			return "Kas kurang (%s)" % GameCatalog.fmt_cash(price)
		cash -= price
		if edit_f:
			r["lanesForward"] = lf + 1
			r["approachLanesForward"] = maxi(RoadGeom.get_effective_approach_lanes(r, true), int(r["lanesForward"]))
		if edit_b:
			r["lanesBackward"] = lb + 1
			r["approachLanesBackward"] = maxi(RoadGeom.get_effective_approach_lanes(r, false), int(r["lanesBackward"]))
		spawn_toast(mid, "-" + GameCatalog.fmt_cash(price), Color("#e67e22"))
		_refresh_network_geometry()
		map_static_dirty.emit()
		if sfx:
			sfx.play_ui("place")
		return "%s: %d/%d lajur" % [String(r["name"]), int(r["lanesForward"]), int(r["lanesBackward"])]
	else:
		if (edit_f and lf <= 1) or (edit_b and lb <= 1):
			return "Minimal 1 lajur per arah"
		var cur_top: int = maxi(lf, lb)
		var base_paid: int = GameCatalog.round_2sig(float(GameCatalog.INFRA_PRICES["lane_base"]) + float(GameCatalog.INFRA_PRICES["lane_per_px"]) * float(r["lengthPx"])) * maxi(1, cur_top - 1)
		var refund: int = maxi(125, int(round(float(base_paid) * 0.5 * unit_scale)))
		cash += refund
		if edit_f:
			r["lanesForward"] = lf - 1
			r["approachLanesForward"] = clampi(int(r.get("approachLanesForward", lf - 1)), int(r["lanesForward"]), 4)
		if edit_b:
			r["lanesBackward"] = lb - 1
			r["approachLanesBackward"] = clampi(int(r.get("approachLanesBackward", lb - 1)), int(r["lanesBackward"]), 4)
		spawn_toast(mid, "+" + GameCatalog.fmt_cash(refund), Color("#2b8a3e"))
		_refresh_network_geometry()
		map_static_dirty.emit()
		if sfx:
			sfx.play_ui("remove")
		return "%s: %d/%d lajur (+%s)" % [String(r["name"]), int(r["lanesForward"]), int(r["lanesBackward"]), GameCatalog.fmt_cash(refund)]


func modify_junction_approach_lanes(edge_id: String, delta: int, forward_dir: bool = true) -> String:
	if not road_map.has(edge_id):
		return ""
	var r: Dictionary = road_map[edge_id]
	if not bool(r["isBuilt"]) or not unlocked_regions.has(int(r["regionIndex"])):
		return ""
	var ow: int = int(r["oneWay"])
	if (forward_dir and ow < 0) or ((not forward_dir) and ow > 0):
		return "Arah ini tidak aktif pada jalan satu arah"

	var main_l: int = int(r["lanesForward"] if forward_dir else r["lanesBackward"])
	var cur_app: int = RoadGeom.get_effective_approach_lanes(r, forward_dir)
	var key := "approachLanesForward" if forward_dir else "approachLanesBackward"
	var pts: PackedVector2Array = r["pts"]
	var anchor: Vector2 = pts[pts.size() - 1] if forward_dir else pts[0]
	var step_p: int = int(GameCatalog.INFRA_PRICES["pocket"])

	if delta > 0:
		if cur_app >= 4:
			return "Maksimal 4 lajur simpang"
		if cash < step_p:
			if sfx:
				sfx.warn()
			return "Kas kurang (%s)" % GameCatalog.fmt_cash(step_p)
		cash -= step_p
		r[key] = cur_app + 1
		if not r.has("pocketSize"):
			r["pocketSize"] = 1
		spawn_toast(anchor, "-" + GameCatalog.fmt_cash(step_p), Color("#e67e22"))
		_refresh_network_geometry()
		map_static_dirty.emit()
		if sfx:
			sfx.play_ui("place")
		return "%s (%s): %d lajur di simpang" % [String(r["name"]), "Fwd" if forward_dir else "Back", int(r[key])]
	else:
		if cur_app <= main_l:
			return "Minimal mengikuti lajur utama (%d)" % main_l
		var refund: int = int(round(float(step_p) * 0.5))
		cash += refund
		r[key] = cur_app - 1
		if int(r.get("approachLanesForward", int(r["lanesForward"]))) <= int(r["lanesForward"]) and int(r.get("approachLanesBackward", int(r["lanesBackward"]))) <= int(r["lanesBackward"]):
			r["pocketLevel"] = 0
		spawn_toast(anchor, "+" + GameCatalog.fmt_cash(refund), Color("#2b8a3e"))
		_refresh_network_geometry()
		map_static_dirty.emit()
		if sfx:
			sfx.play_ui("remove")
		return "%s (%s): %d lajur di simpang (+%s)" % [String(r["name"]), "Fwd" if forward_dir else "Back", int(r[key]), GameCatalog.fmt_cash(refund)]


func cycle_road_pocket_size(edge_id: String) -> String:
	if not road_map.has(edge_id):
		return ""
	var r: Dictionary = road_map[edge_id]
	if not bool(r["isBuilt"]) or not unlocked_regions.has(int(r["regionIndex"])):
		return ""
	var cur_sz: int = RoadGeom.get_effective_pocket_size(r)
	var nxt_sz: int = (cur_sz + 1) % 3
	r["pocketSize"] = nxt_sz
	if int(r.get("pocketLevel", 0)) > 0:
		r["pocketLevel"] = nxt_sz + 1
	_refresh_network_geometry()
	map_static_dirty.emit()
	if sfx:
		sfx.play_ui("edit")
	var sz_names: Array[String] = ["Short", "Medium", "Long"]
	return "%s Pocket Length: %s" % [String(r["name"]), sz_names[nxt_sz]]


func cycle_road_pocket(edge_id: String) -> String:
	if not road_map.has(edge_id):
		return ""
	var r: Dictionary = road_map[edge_id]
	if not bool(r["isBuilt"]) or not unlocked_regions.has(int(r["regionIndex"])):
		return ""
	var cur: int = clampi(int(r.get("pocketLevel", 0)), 0, 3)
	var nxt: int = (cur + 1) % 4
	var pts: PackedVector2Array = r["pts"]
	var mid: Vector2 = pts[pts.size() / 2]
	var step_p: int = int(GameCatalog.INFRA_PRICES["pocket"])
	if cur == 0 and nxt == 1:
		if cash < step_p:
			if sfx:
				sfx.warn()
			return "Kas kurang untuk Kantong Belok (%s)" % GameCatalog.fmt_cash(step_p)
		cash -= step_p
		spawn_toast(mid, "-" + GameCatalog.fmt_cash(step_p), Color("#e67e22"))
	elif nxt == 0 and cur > 0:
		var refund: int = int(round(float(step_p) * 0.5))
		cash += refund
		spawn_toast(mid, "+" + GameCatalog.fmt_cash(refund), Color("#2b8a3e"))
	r["pocketLevel"] = nxt
	if nxt > 0:
		r["pocketSize"] = nxt - 1
		r["approachLanesForward"] = mini(4, maxi(int(r["lanesForward"]) + 1, int(r.get("approachLanesForward", 1))))
		r["approachLanesBackward"] = mini(4, maxi(int(r["lanesBackward"]) + 1, int(r.get("approachLanesBackward", 1))))
	else:
		r["approachLanesForward"] = int(r["lanesForward"])
		r["approachLanesBackward"] = int(r["lanesBackward"])
	_refresh_network_geometry()
	map_static_dirty.emit()
	if sfx:
		sfx.play_ui("edit")
	return "%s Kantong Simpang: %s" % [String(r["name"]), GameCatalog.POCKET_LABELS[nxt]]

const LANE_ARROW_CYCLE: Array[int] = [7, 3, 6, 2, 1, 4]

func cycle_road_turn_mask(edge_id: String, forward_dir: bool = true) -> String:
	if not road_map.has(edge_id):
		return ""
	var r: Dictionary = road_map[edge_id]
	if not bool(r["isBuilt"]) or not unlocked_regions.has(int(r["regionIndex"])):
		return ""
	var key := "turnMaskForward" if forward_dir else "turnMaskBackward"
	var cur: int = int(r.get(key, 7))
	var idx: int = LANE_ARROW_CYCLE.find(cur)
	var nxt: int = LANE_ARROW_CYCLE[(idx + 1) % LANE_ARROW_CYCLE.size()]
	r[key] = nxt
	recompute_all_routes()
	map_static_dirty.emit()
	if sfx:
		sfx.play_ui("edit")
	return "%s (%s): %s" % [String(r["name"]), "Maju" if forward_dir else "Balik", format_turn_mask(nxt)]

func cycle_road_one_way(edge_id: String) -> String:
	if not road_map.has(edge_id):
		return ""
	var r: Dictionary = road_map[edge_id]
	if not bool(r["isBuilt"]) or bool(r["closed"]) or not unlocked_regions.has(int(r["regionIndex"])):
		return ""
	var ow: int = int(r["oneWay"])
	r["oneWay"] = 1 if ow == 0 else (-1 if ow == 1 else 0)
	_refresh_network_geometry()
	recompute_all_routes()
	map_static_dirty.emit()
	if sfx:
		sfx.play_ui("edit")
	var label := "Dua Arah" if int(r["oneWay"]) == 0 else ("Satu Arah →" if int(r["oneWay"]) == 1 else "Satu Arah ←")
	return "%s: %s" % [String(r["name"]), label]

func count_routes_cut_by_closing(edge_id: String) -> int:
	if not road_map.has(edge_id):
		return 0
	var r: Dictionary = road_map[edge_id]
	if bool(r["closed"]):
		return 0
	var cut: int = 0
	for rt in routes:
		if String(rt["brokenReason"]) != "":
			continue
		var uses_edge: bool = false
		for st in rt["forwardPath"]:
			if String(st["edgeId"]) == edge_id:
				uses_edge = true
				break
		if not uses_edge:
			for st in rt["returnPath"]:
				if String(st["edgeId"]) == edge_id:
					uses_edge = true
					break
		if uses_edge:
			cut += 1
	return cut

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
		_refresh_network_geometry()
		recompute_all_routes()
		map_static_dirty.emit()
		if sfx:
			sfx.play_ui("place")
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
	_refresh_network_geometry()
	recompute_all_routes()
	map_static_dirty.emit()
	if sfx:
		sfx.play_ui("remove")
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
			_refresh_network_geometry()
			recompute_all_routes()
			map_static_dirty.emit()
			if sfx:
				sfx.unlock_region()
			banner_notify.emit("Proyek Jalan Selesai!", String(off["name"]), Color("#2b8a3e"))
			return "%s resmi beroperasi!" % String(off["name"])
	return ""

# === MAIN FIXED-TIMESTEP SIMULATION LOOP ===

func step_frame(frame_dt: float) -> void:
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
	_step_cargo_flights(dt)
	_step_upkeep_and_goals(dt)

func _step_cargo_flights(dt: float) -> void:
	for i in range(cargo_flights.size() - 1, -1, -1):
		var fl: Dictionary = cargo_flights[i]
		var fk := String(fl.get("kind", "hop"))
		if fk == "hop":
			var ring: float = float(fl.get("ring", -1.0))
			if ring < 0.0:
				var nt: float = float(fl["t"]) + dt
				var dur: float = maxf(0.15, float(fl["dur"]))
				if nt >= dur:
					fl["t"] = dur
					fl["ring"] = 0.0
				else:
					fl["t"] = nt
			else:
				ring += dt
				fl["ring"] = ring
				if ring >= 0.35:
					cargo_flights.remove_at(i)
		else:
			var ct: float = float(fl["t"]) + dt
			fl["t"] = ct
			if ct >= maxf(0.2, float(fl.get("dur", 0.55))):
				cargo_flights.remove_at(i)

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
				f["stalledSec"] = float(f.get("stalledSec", 0.0)) + dt
			else:
				f["stalledReason"] = "none"
				f["stalledSec"] = 0.0
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
				f["stalledSec"] = float(f.get("stalledSec", 0.0)) + dt
				continue
			var in_bufs: Dictionary = f["inputBuffers"]
			var has_inputs: bool = true
			for inp in gdef["inputs"]:
				if int(in_bufs.get(String(inp["good"]), 0)) < int(inp["qty"]):
					has_inputs = false
					break
			if not has_inputs:
				f["stalledReason"] = "missing_input"
				f["stalledSec"] = float(f.get("stalledSec", 0.0)) + dt
				continue
			f["stalledReason"] = "none"
			f["stalledSec"] = 0.0
			var out_rate_sec: float = get_factory_output_per_min(f) / 60.0
			f["prodProgress"] = float(f["prodProgress"]) + out_rate_sec * dt
			if float(f["prodProgress"]) >= 1.0:
				f["prodProgress"] = float(f["prodProgress"]) - 1.0
				for inp in gdef["inputs"]:
					var ig := String(inp["good"])
					in_bufs[ig] = maxi(0, int(in_bufs.get(ig, 0)) - int(inp["qty"]))
				f["outputBuffer"] = int(f["outputBuffer"]) + 1
				launch_cargo_hop(out_g, f["pos"], get_facility_pad_world_pos(f, "output", out_g))

		elif k == "station" or k == "harbour":
			var tt_lvl: int = clampi(int(f["upgrades"].get("timetable", 0)), 0, 3)
			var wait_factor: float = GameCatalog.TIMETABLE_WAIT_FACTORS[tt_lvl]
			var v_cap: int = get_hub_vehicle_capacity_slots(f)
			var pile: Array = f["yardPile"]
			if not f.has("vehicleCargo") or typeof(f["vehicleCargo"]) != TYPE_ARRAY:
				f["vehicleCargo"] = []
			var v_cargo: Array = f["vehicleCargo"]

			# While train/ship is docked, load cargo continuously from on-site yardPile onto vehicle!
			if bool(f["vehiclePresent"]) and not pile.is_empty() and int(f["vehicleCapacityRemaining"]) > 0:
				var hopped_this_step: int = 0
				while not pile.is_empty():
					var first_g := String(pile[0])
					var g_slots: int = int(GameCatalog.GOODS.get(first_g, {"slots": 1})["slots"])
					if int(f["vehicleCapacityRemaining"]) < g_slots:
						break
					pile.pop_front()
					f["vehicleCapacityRemaining"] = int(f["vehicleCapacityRemaining"]) - g_slots
					var new_boarded: int = int(f.get("boardedSlots", 0)) + g_slots
					f["boardedSlots"] = new_boarded
					f["vehicleLoaded"] = new_boarded
					if v_cargo.size() < 48:
						v_cargo.append(first_g)
					if hopped_this_step < 2:
						launch_cargo_hop(first_g, get_facility_pad_world_pos(f, "yard"), get_facility_vehicle_world_pos(f))
						hopped_this_step += 1

			f["vehicleTimer"] = float(f["vehicleTimer"]) - dt
			# Depart early once full, or when dwell timer expires
			if bool(f["vehiclePresent"]) and int(f["vehicleCapacityRemaining"]) <= 0 and float(f["vehicleTimer"]) > 1.2:
				f["vehicleTimer"] = 1.2

			if float(f["vehicleTimer"]) <= 0.0:
				if bool(f["vehiclePresent"]):
					var away_sec: float = (7.5 if k == "station" else 10.0) * wait_factor
					if away_sec <= 0.05:
						# Timetable Lv.3 (0.0 factor): next train/ship arrives immediately with zero gap!
						f["vehiclePresent"] = true
						f["vehicleTimer"] = 18.0 if k == "station" else 22.0
						f["vehicleCapacityRemaining"] = v_cap
						f["boardedSlots"] = 0
						f["vehicleLoaded"] = 0
						v_cargo.clear()
					else:
						f["vehiclePresent"] = false
						f["vehicleTimer"] = away_sec
						f["boardedSlots"] = 0
						f["vehicleLoaded"] = 0
						v_cargo.clear()
				else:
					f["vehiclePresent"] = true
					f["vehicleTimer"] = 18.0 if k == "station" else 22.0
					f["vehicleCapacityRemaining"] = v_cap
					f["boardedSlots"] = 0
					f["vehicleLoaded"] = 0
					v_cargo.clear()

func get_edge_phase_at_junction(j: Dictionary, edge_id: String) -> int:
	if j.has("light") and typeof(j["light"]) == TYPE_DICTIONARY and (j["light"] as Dictionary).has("phases"):
		var phases: Array = j["light"]["phases"]
		for p_i in range(phases.size()):
			var arms: Dictionary = phases[p_i].get("arms", {})
			if int(arms.get(edge_id, 0)) != 0:
				return p_i
	if j.has("geom") and (j["geom"] as Dictionary).has("arms"):
		var arms_g: Array = j["geom"]["arms"]
		for i in range(arms_g.size()):
			if String(arms_g[i]["edge_id"]) == edge_id:
				return 0 if (i % 2 == 0) else 1
	var idx: int = (j["connectedEdgeIds"] as Array).find(edge_id)
	return 0 if (idx < 0 or idx % 2 == 0) else 1

func _get_edge_phase_at_junction(j: Dictionary, edge_id: String) -> int:
	return get_edge_phase_at_junction(j, edge_id)

## Checks multi-phase signal head + green-continuation across consecutive phases (Update 1.8)
func is_movement_green_at_light(j: Dictionary, in_edge_id: String, in_fwd: bool, out_edge_id: String, out_fwd: bool) -> bool:
	if not j.has("light") or typeof(j["light"]) != TYPE_DICTIONARY:
		return true
	_ensure_light_schema(j)
	var lt: Dictionary = j["light"]
	var phases: Array = lt["phases"]
	if phases.is_empty():
		return true
	var cur_p: int = clampi(int(lt["currentPhase"]), 0, phases.size() - 1)
	var t_bit: int = RoutePathfinder.classify_turn_bit(junction_map, road_map, in_edge_id, in_fwd, String(j["id"]), out_edge_id, out_fwd)
	var cur_mask: int = int((phases[cur_p].get("arms", {}) as Dictionary).get(in_edge_id, 0))
	var stage := String(lt["stage"])
	if stage == "green":
		return (cur_mask & t_bit) != 0
	# Green continuation: if both currentPhase and nextPhase allow this exact movement, keep green through yellow/allred!
	var nxt_p: int = (cur_p + 1) % phases.size()
	var nxt_mask: int = int((phases[nxt_p].get("arms", {}) as Dictionary).get(in_edge_id, 0))
	return ((cur_mask & t_bit) != 0) and ((nxt_mask & t_bit) != 0) and phases.size() > 1 and nxt_p != cur_p

func get_arm_signal_state(j: Dictionary, edge_id: String) -> String:
	if not j.has("light") or typeof(j["light"]) != TYPE_DICTIONARY:
		return "green"
	_ensure_light_schema(j)
	var lt: Dictionary = j["light"]
	var phases: Array = lt["phases"]
	if phases.is_empty():
		return "green"
	var cur_p: int = clampi(int(lt["currentPhase"]), 0, phases.size() - 1)
	var cur_mask: int = int((phases[cur_p].get("arms", {}) as Dictionary).get(edge_id, 0))
	var stage := String(lt["stage"])
	if cur_mask == 0:
		return "red"
	if stage == "green":
		return "green"
	var nxt_p: int = (cur_p + 1) % phases.size()
	var nxt_mask: int = int((phases[nxt_p].get("arms", {}) as Dictionary).get(edge_id, 0))
	if nxt_p != cur_p and (cur_mask & nxt_mask) == cur_mask:
		return "green"
	return "yellow" if stage == "yellow" else "red"

func _step_traffic_lights(dt: float) -> void:
	for j in junctions:
		if String(j["control"]) != "lights" or not j.has("light"):
			continue
		_ensure_light_schema(j)
		var lt: Dictionary = j["light"]
		var phases: Array = lt["phases"]
		var cur_p: int = clampi(int(lt["currentPhase"]), 0, phases.size() - 1)
		lt["timer"] = float(lt["timer"]) - dt
		if String(lt["stage"]) == "green":
			lt["greenElapsed"] = float(lt["greenElapsed"]) + dt
			var target_green: float = float(phases[cur_p].get("green", 10.0))
			if bool(lt["actuated"]) and float(lt["greenElapsed"]) >= minf(4.0, target_green):
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
				var nxt_phase: int = (cur_p + 1) % phases.size()
				lt["currentPhase"] = nxt_phase
				lt["stage"] = "green"
				lt["greenElapsed"] = 0.0
				lt["lastDetectorHit"] = real_time_sec
				lt["timer"] = float(phases[nxt_phase].get("green", 10.0))

func get_agent_express_bonus_left(ag: Dictionary) -> float:
	if String(ag.get("model", "")) != "express" or int(ag.get("cargoQty", 0)) <= 0:
		return -1.0
	var locked: float = float(ag.get("expressBonusLocked", -1.0))
	if locked >= 0.0:
		return locked
	var win: float = float(ag.get("expressWindowSec", 0.0))
	var dl: float = float(ag.get("expressDeadlineSec", 0.0))
	if win <= 0.0 or dl <= 0.0:
		return -1.0
	return clampf((dl - real_time_sec) / win, 0.0, 1.0)

func _get_agent_active_path(ag: Dictionary, rt: Dictionary) -> Array:
	var st := String(ag.get("state", ""))
	if st == "driving_outbound":
		return rt.get("forwardPath", [])
	if st == "driving_return":
		return rt.get("returnPath", [])
	if st == "driving_to_depot" or st == "driving_from_depot":
		return ag.get("depotPath", [])
	return []

func _step_agents(dt: float) -> void:
	for f in facilities:
		f["occupiedBays"] = 0

	var lane_buckets: Dictionary = {}
	for ag in agents:
		var st := String(ag["state"])
		if st == "loading" or st == "unloading":
			var rt_b: Dictionary = get_route(String(ag["routeId"]))
			if not rt_b.is_empty():
				var fid: String = String(rt_b["fromFacilityId"]) if st == "loading" else String(rt_b["toFacilityId"])
				if facility_map.has(fid):
					facility_map[fid]["occupiedBays"] = int(facility_map[fid]["occupiedBays"]) + 1
		elif st == "driving_outbound" or st == "driving_return" or st == "driving_to_depot" or st == "driving_from_depot":
			var step_d: Dictionary = _get_agent_current_step(ag)
			if not step_d.is_empty():
				var key := "%s:%d" % [String(step_d["edgeId"]), 1 if bool(step_d["forward"]) else 0]
				if not lane_buckets.has(key):
					lane_buckets[key] = []
				(lane_buckets[key] as Array).append(ag)

	for k in lane_buckets.keys():
		(lane_buckets[k] as Array).sort_custom(func(a, b): return float(a["sPx"]) > float(b["sPx"]))

	for r in roads:
		var rid := String(r["id"])
		var cnt: int = (lane_buckets.get(rid + ":1", []) as Array).size() + (lane_buckets.get(rid + ":0", []) as Array).size()
		var pocket_bonus: float = 1.0 + 0.14 * float(int(r.get("pocketLevel", 0)))
		var cap_est: float = maxf(1.5, (float(r["lengthPx"]) / 34.0) * float(int(r["lanesForward"]) + int(r["lanesBackward"])) * 0.5 * pocket_bonus)
		var ratio: float = minf(1.5, float(cnt) / cap_est)
		r["congestionEMA"] = float(r["congestionEMA"]) * 0.94 + ratio * 0.06

	for ag in agents:
		var rt: Dictionary = get_route(String(ag["routeId"]))
		if rt.is_empty():
			continue
		var tdef: Dictionary = GameCatalog.TRUCKS[String(ag["model"])]
		var st := String(ag["state"])

		if st == "loading":
			ag["braking"] = false
			ag["turnSignal"] = 0
			ag["blockerAgentId"] = ""
			_update_loading_agent(ag, rt, dt)
		elif st == "queuing_bay":
			ag["braking"] = true
			ag["turnSignal"] = 0
			ag["blockerAgentId"] = ""
			var f_to: Dictionary = facility_map[String(rt["toFacilityId"])]
			# Lock Express on-time bonus as soon as truck reaches destination entrance!
			if String(ag["model"]) == "express" and float(ag.get("expressBonusLocked", -1.0)) < 0.0:
				var win: float = maxf(1.0, float(ag.get("expressWindowSec", 1.0)))
				ag["expressBonusLocked"] = clampf((float(ag["expressDeadlineSec"]) - real_time_sec) / win, 0.0, 1.0) if real_time_sec <= float(ag["expressDeadlineSec"]) else 0.0
			if int(f_to["occupiedBays"]) < get_total_bays(f_to):
				f_to["occupiedBays"] = int(f_to["occupiedBays"]) + 1
				ag["state"] = "unloading"
				ag["waitReason"] = "none"
				var exit_mult: float = 0.65 if int(f_to["upgrades"].get("exitRoad", 0)) > 0 else 1.0
				var c_slots: int = int(GameCatalog.GOODS[String(ag["cargoGood"])]["slots"]) * maxi(1, int(ag["cargoQty"])) if String(ag["cargoGood"]) != "" else 0
				ag["dwellSec"] = 0.25 if c_slots <= 0 else maxf(0.45, 0.80 * float(c_slots) * exit_mult)
				ag["waitSec"] = 0.0
			else:
				ag["waitReason"] = "bay_full"
				ag["waitSec"] = float(ag["waitSec"]) + dt
				ag["speedPx"] = 0.0
		elif st == "unloading":
			ag["braking"] = false
			ag["turnSignal"] = 0
			ag["blockerAgentId"] = ""
			_update_unloading_agent(ag, rt, dt)
		elif st == "at_depot":
			ag["braking"] = false
			ag["turnSignal"] = 0
			ag["blockerAgentId"] = ""
			ag["speedPx"] = 0.0
			ag["dwellSec"] = float(ag.get("dwellSec", 0.0)) - dt
			if float(ag["dwellSec"]) <= 0.0 and String(rt.get("brokenReason", "")) == "":
				var f_orig: Dictionary = facility_map.get(String(rt["fromFacilityId"]), {})
				var d_jid := String(depot.get("junctionId", ""))
				var orig_jid := String(f_orig.get("junctionId", ""))
				if d_jid != "" and orig_jid != "" and d_jid != orig_jid:
					var dp_back: Dictionary = RoutePathfinder.find_directed_path(d_jid, orig_jid, [], junction_map, road_map, unlocked_regions, String(ag["model"]))
					var steps_b: Array = dp_back.get("steps", [])
					if not steps_b.is_empty() and String(dp_back.get("broken_reason", "")) == "":
						ag["depotPath"] = steps_b
						ag["state"] = "driving_from_depot"
						ag["stepIndex"] = 0
						ag["sPx"] = 0.0
						continue
				ag["state"] = "loading"
				ag["dwellSec"] = 0.45
				ag["pos"] = f_orig.get("pos", ag["pos"])
		elif st == "driving_outbound" or st == "driving_return" or st == "driving_to_depot" or st == "driving_from_depot":
			_update_driving_agent(ag, rt, tdef, lane_buckets, dt)

func _update_loading_agent(ag: Dictionary, rt: Dictionary, dt: float) -> void:
	var f_from: Dictionary = facility_map[String(rt["fromFacilityId"])]
	ag["pos"] = f_from["pos"]
	ag["speedPx"] = 0.0
	if String(rt["brokenReason"]) != "":
		ag["waitReason"] = "broken_route"
		ag["waitSec"] = float(ag["waitSec"]) + dt
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
		var win_sec: float = float(rt["clearTimeForwardSec"]) * GameCatalog.EXPRESS_DEADLINE_MULT + GameCatalog.EXPRESS_DEADLINE_PAD_SEC
		ag["expressWindowSec"] = win_sec
		ag["expressDeadlineSec"] = real_time_sec + win_sec
		ag["expressBonusLocked"] = -1.0
		ag["state"] = "driving_outbound"
		ag["stepIndex"] = 0
		ag["sPx"] = 0.0
		ag["waitSec"] = 0.0
		ag["waitReason"] = "none"
		ag["lastIssue"] = ""
		var pad_from: Vector2 = get_facility_pad_world_pos(f_from, "output", good_to_load)
		for _h in range(mini(take, 2)):
			launch_cargo_hop(good_to_load, pad_from, f_from["pos"])
	else:
		ag["waitSec"] = float(ag["waitSec"]) + dt
		ag["waitReason"] = "cargo_wait"
		# Authentic TruckOperator MAX_WAIT (20s): depart empty to release loading bay rather than blocking forever
		if float(ag["waitSec"]) >= MAX_LOAD_WAIT_SEC:
			ag["cargoGood"] = ""
			ag["cargoQty"] = 0
			ag["departedSec"] = real_time_sec
			ag["expressWindowSec"] = 0.0
			ag["expressDeadlineSec"] = 0.0
			ag["expressBonusLocked"] = -1.0
			ag["state"] = "driving_outbound"
			ag["stepIndex"] = 0
			ag["sPx"] = 0.0
			ag["waitSec"] = 0.0
			ag["waitReason"] = "none"
			ag["lastIssue"] = "Berangkat kosong dari %s (>20 dtk)" % String(f_from["name"])

func _update_unloading_agent(ag: Dictionary, rt: Dictionary, dt: float) -> void:
	var f_to: Dictionary = facility_map[String(rt["toFacilityId"])]
	ag["pos"] = f_to["pos"]
	ag["speedPx"] = 0.0
	ag["dwellSec"] = float(ag["dwellSec"]) - dt
	if float(ag["dwellSec"]) > 0.0:
		return

	var c_good := String(ag["cargoGood"])
	var c_qty: int = int(ag["cargoQty"])
	if c_good != "" and c_qty > 0 and GameCatalog.GOODS.has(c_good):
		var gdef: Dictionary = GameCatalog.GOODS[c_good]
		var g_slots: int = int(gdef["slots"])
		var can_accept: bool = false
		var fk := String(f_to["kind"])

		if fk == "factory":
			var cur_in: int = int(f_to["inputBuffers"].get(c_good, 0))
			if (cur_in + c_qty) * g_slots <= get_capacity_slots(f_to):
				f_to["inputBuffers"][c_good] = cur_in + c_qty
				can_accept = true
		elif fk == "station" or fk == "harbour":
			# Authentic Station (2.0×) & Harbour (1.6×) on-site storage yard pile!
			var yard_used: int = get_hub_yard_used_slots(f_to)
			var yard_cap: int = get_hub_yard_capacity_slots(f_to)
			if yard_used + c_qty * g_slots <= yard_cap:
				var pile: Array = f_to["yardPile"]
				for _u in range(c_qty):
					pile.append(c_good)
				can_accept = true
		elif fk == "market":
			can_accept = true

		if can_accept:
			var is_express_hit: bool = false
			if String(ag["model"]) == "express":
				var locked_b: float = float(ag.get("expressBonusLocked", -1.0))
				is_express_hit = (locked_b > 0.0) if locked_b >= 0.0 else (real_time_sec <= float(ag["expressDeadlineSec"]))
			var bonus: int = int(GameCatalog.EXPRESS_BONUS_FACTOR) if is_express_hit else 1
			var payout: int = int(gdef["value"]) * c_qty * bonus
			cash += payout
			rt["totalRevenue"] = int(rt["totalRevenue"]) + payout
			rt["deliveriesCount"] = int(rt["deliveriesCount"]) + c_qty
			revenue_events.append({"t": real_time_sec, "amount": payout})
			_record_delivery(String(rt["fromFacilityId"]), String(f_to["id"]), c_good, c_qty)
			var pad_role: String = "input" if fk == "factory" else ("yard" if (fk == "station" or fk == "harbour") else "")
			var dst_pad: Vector2 = get_facility_pad_world_pos(f_to, pad_role, c_good) if pad_role != "" else f_to["pos"] + Vector2(0.0, -8.0)
			for _h in range(mini(c_qty, 2)):
				launch_cargo_hop(c_good, f_to["pos"], dst_pad)
			var toast_txt: String = ("⚡+" if is_express_hit else "+") + GameCatalog.fmt_cash(payout)
			spawn_toast(f_to["pos"] + Vector2(0, -16), toast_txt, Color("#f59f00") if is_express_hit else Color("#2b8a3e"))
			if sfx:
				sfx.coin(is_express_hit)
			ag["cargoGood"] = ""
			ag["cargoQty"] = 0
			ag["expressBonusLocked"] = -1.0
		else:
			ag["waitSec"] = float(ag["waitSec"]) + dt
			ag["waitReason"] = "scrap_wait"
			if float(ag["waitSec"]) < SCRAP_WAIT_SEC:
				return
			var scrap_pay: int = maxi(1, int(round(float(int(gdef["value"]) * c_qty) * 0.10)))
			cash += scrap_pay
			f_to["scrappedCount"] = int(f_to.get("scrappedCount", 0)) + c_qty
			revenue_events.append({"t": real_time_sec, "amount": scrap_pay})
			launch_cargo_crumble(c_good, f_to["pos"])
			spawn_toast(f_to["pos"] + Vector2(0, -14), "Scrap +" + GameCatalog.fmt_cash(scrap_pay), Color("#868e96"))
			ag["lastIssue"] = "Kargo di-scrap di %s (gudang penuh)" % String(f_to["name"])
			ag["cargoGood"] = ""
			ag["cargoQty"] = 0
			ag["expressBonusLocked"] = -1.0

	ag["state"] = "driving_return"
	ag["stepIndex"] = 0
	ag["sPx"] = 0.0
	ag["waitSec"] = 0.0
	ag["waitReason"] = "none"

func _get_agent_current_step(ag: Dictionary) -> Dictionary:
	var rt: Dictionary = get_route(String(ag["routeId"]))
	var path: Array = _get_agent_active_path(ag, rt)
	var idx: int = int(ag["stepIndex"])
	if idx < 0 or idx >= path.size():
		return {}
	return path[idx]

func _get_step_trajectory(path: Array, step_idx: int, lane_idx: int) -> Dictionary:
	var step_d: Dictionary = path[step_idx]
	var eid := String(step_d["edgeId"])
	var edge: Dictionary = road_map[eid]
	var forward: bool = bool(step_d["forward"])
	var lanes_dir: int = maxi(1, int(edge["lanesForward"]) if forward else int(edge["lanesBackward"]))
	var clamped_lane: int = clampi(lane_idx, 0, lanes_dir - 1)

	var has_next: bool = (step_idx + 1) < path.size() and road_map.has(String(path[step_idx + 1]["edgeId"]))
	var next_sig: String = "END"
	if has_next:
		var ns: Dictionary = path[step_idx + 1]
		next_sig = "%s:%d" % [String(ns["edgeId"]), 1 if bool(ns["forward"]) else 0]
	var cache_key := "%s:%d:%d->%s:%d" % [eid, 1 if forward else 0, clamped_lane, next_sig, 1 if left_hand_traffic else 0]
	if _turn_curve_cache.has(cache_key):
		return _turn_curve_cache[cache_key]

	var rlen: float = float(edge["lengthPx"])
	var trim_in: float = float(edge.get("trimStart", 0.0)) if forward else float(edge.get("trimEnd", 0.0))
	var trim_out: float = float(edge.get("trimEnd", 0.0)) if forward else float(edge.get("trimStart", 0.0))
	var use_explicit_geom: bool = (step_idx > 0 and has_next)
	if step_idx == 0:
		trim_in = minf(trim_in, rlen * 0.25)
	if not has_next:
		trim_out = minf(trim_out, rlen * 0.25)

	var s_begin: float = clampf(trim_in, 0.0, maxf(0.0, rlen - 3.0))
	var s_finish: float = clampf(rlen - trim_out, s_begin + 2.5, rlen)

	var turn_sig: int = 0
	var use_pocket: bool = false
	var j_ahead: Dictionary = {}
	var nxt_edge: Dictionary = {}
	var nxt_fwd: bool = true
	if has_next:
		j_ahead = junction_map.get(String(step_d["toJunctionId"]), {})
		if not j_ahead.is_empty():
			var nxt_step: Dictionary = path[step_idx + 1]
			var nxt_eid := String(nxt_step["edgeId"])
			nxt_edge = road_map[nxt_eid]
			nxt_fwd = bool(nxt_step["forward"])
			var t_bit: int = RoutePathfinder.classify_turn_bit(junction_map, road_map, eid, forward, String(j_ahead["id"]), nxt_eid, nxt_fwd)
			if t_bit == RoutePathfinder.TURN_LEFT:
				turn_sig = -1
			elif t_bit == RoutePathfinder.TURN_RIGHT:
				turn_sig = 1
			var is_kerbside_turn: bool = (turn_sig == -1) if left_hand_traffic else (turn_sig == 1)
			var app_lanes: int = RoadGeom.get_effective_approach_lanes(edge, forward)
			use_pocket = (use_explicit_geom and is_kerbside_turn and app_lanes > lanes_dir and clamped_lane == 0)

	var stitched: PackedVector2Array
	if use_explicit_geom:
		stitched = RoadGeom.build_edge_lane_polyline(edge, forward, clamped_lane, use_pocket, s_begin, s_finish, left_hand_traffic)
	else:
		var opp_lanes: int = maxi(1, int(edge["lanesBackward"]) if forward else int(edge["lanesForward"]))
		stitched = PackedVector2Array()
		var sample_count: int = maxi(4, int(ceil((s_finish - s_begin) / 5.5)))
		for i in range(sample_count + 1):
			var s_val: float = lerpf(s_begin, s_finish, float(i) / float(sample_count))
			var rp: Dictionary = RoadGeom.sample_road_pose(
				edge["pts"], edge["cum_len"], rlen, int(edge["oneWay"]),
				forward, s_val, float(clamped_lane), lanes_dir, left_hand_traffic, opp_lanes
			)
			var vp: Vector2 = rp["pos"]
			if stitched.is_empty() or stitched[stitched.size() - 1].distance_to(vp) > 0.08:
				stitched.append(vp)

	var cum_road: PackedFloat32Array = RoadGeom.build_cum_lengths(stitched)
	var stop_s: float = cum_road[cum_road.size() - 1] if cum_road.size() > 0 else 4.0

	if has_next and not j_ahead.is_empty() and not nxt_edge.is_empty():
		var nxt_lanes: int = maxi(1, int(nxt_edge["lanesForward"]) if nxt_fwd else int(nxt_edge["lanesBackward"]))
		var out_lane: int = mini(clamped_lane, nxt_lanes - 1)
		var conn: PackedVector2Array = RoadGeom.build_turn_connector_pts(
			j_ahead, edge, forward, float(clamped_lane), lanes_dir,
			nxt_edge, nxt_fwd, float(out_lane), nxt_lanes, left_hand_traffic, use_pocket
		)
		for cp in conn:
			if stitched.is_empty() or stitched[stitched.size() - 1].distance_to(cp) > 0.08:
				stitched.append(cp)

	var cum_all: PackedFloat32Array = RoadGeom.build_cum_lengths(stitched)
	var tot_l: float = maxf(4.0, cum_all[cum_all.size() - 1] if cum_all.size() > 0 else 4.0)
	var entry := {
		"pts": stitched,
		"cum_len": cum_all,
		"stop_s": stop_s,
		"total_len": tot_l,
		"turn_sig": turn_sig
	}
	_turn_curve_cache[cache_key] = entry
	return entry

func _sample_agent_step_pose(path: Array, step_idx: int, visual_lane: float, s_px: float) -> Dictionary:
	var step_d: Dictionary = path[step_idx]
	var edge: Dictionary = road_map[String(step_d["edgeId"])]
	var fwd: bool = bool(step_d["forward"])
	var lanes_dir: int = maxi(1, int(edge["lanesForward"]) if fwd else int(edge["lanesBackward"]))
	var vl: float = clampf(visual_lane, 0.0, float(lanes_dir - 1))
	var l0: int = int(floor(vl))
	var l1: int = mini(lanes_dir - 1, l0 + 1)
	var frac: float = vl - float(l0)
	var tr0: Dictionary = _get_step_trajectory(path, step_idx, l0)
	var p0: Dictionary = RoadGeom.sample_stitched_pose(tr0["pts"], tr0["cum_len"], s_px)
	if frac < 0.03 or l0 == l1:
		return p0
	var tr1: Dictionary = _get_step_trajectory(path, step_idx, l1)
	var p1: Dictionary = RoadGeom.sample_stitched_pose(tr1["pts"], tr1["cum_len"], s_px)
	return {
		"pos": (p0["pos"] as Vector2).lerp(p1["pos"] as Vector2, frac),
		"heading": lerp_angle(float(p0["heading"]), float(p1["heading"]), frac)
	}

func _update_driving_agent(ag: Dictionary, rt: Dictionary, tdef: Dictionary, lane_buckets: Dictionary, dt: float) -> void:
	var path: Array = _get_agent_active_path(ag, rt)
	var s_idx: int = int(ag["stepIndex"])
	if s_idx >= path.size():
		_finish_agent_leg(ag, rt)
		return

	var step_d: Dictionary = path[s_idx]
	var eid := String(step_d["edgeId"])
	if not road_map.has(eid):
		_finish_agent_leg(ag, rt)
		return
	var edge: Dictionary = road_map[eid]
	var forward: bool = bool(step_d["forward"])
	var pocket_lvl: int = int(edge.get("pocketLevel", 0))
	var base_lanes_dir: int = maxi(1, int(edge["lanesForward"]) if forward else int(edge["lanesBackward"]))
	var lanes_dir: int = mini(4, base_lanes_dir + (1 if pocket_lvl > 0 and float(ag["sPx"]) > maxf(8.0, float(edge["lengthPx"]) - (22.0 + 16.0 * float(pocket_lvl))) else 0))
	if int(ag["laneIndex"]) >= base_lanes_dir:
		ag["laneIndex"] = base_lanes_dir - 1

	var traj: Dictionary = _get_step_trajectory(path, s_idx, mini(int(ag["laneIndex"]), base_lanes_dir - 1))
	var stop_s: float = float(traj["stop_s"])
	var step_total_len: float = float(traj["total_len"])

	var key := "%s:%d" % [eid, 1 if forward else 0]
	var bucket: Array = lane_buckets.get(key, [])

	var leader: Dictionary = {}
	for other in bucket:
		if String(other["id"]) == String(ag["id"]):
			continue
		if int(other["laneIndex"]) == int(ag["laneIndex"]) and float(other["sPx"]) > float(ag["sPx"]):
			if leader.is_empty() or float(other["sPx"]) < float(leader["sPx"]):
				leader = other

	# Cooperative overtake on multi-lane roads or turn pockets
	if float(ag["sPx"]) < stop_s - 8.0 and not leader.is_empty() and lanes_dir > 1 and float(leader["sPx"]) - float(ag["sPx"]) < float(tdef["body_len"]) + 20.0 and float(leader["speedPx"]) < float(tdef["max_speed_px"]) * 0.72:
		for cand_lane in range(base_lanes_dir):
			if cand_lane == int(ag["laneIndex"]):
				continue
			var clear_lane: bool = true
			for other in bucket:
				if int(other["laneIndex"]) == cand_lane and absf(float(other["sPx"]) - float(ag["sPx"])) < float(tdef["body_len"]) + 14.0:
					clear_lane = false
					break
			if clear_lane:
				ag["laneIndex"] = cand_lane
				traj = _get_step_trajectory(path, s_idx, cand_lane)
				stop_s = float(traj["stop_s"])
				step_total_len = float(traj["total_len"])
				leader = {}
				break

	var target_v: float = float(tdef["max_speed_px"])
	var rc := String(edge["roadClass"])
	if rc == "toll":
		target_v *= 1.18
	elif rc == "local":
		target_v *= 0.85

	ag["waitReason"] = "none"
	ag["blockerAgentId"] = ""

	if not leader.is_empty():
		var leader_body: float = float(GameCatalog.TRUCKS[String(leader["model"])]["body_len"])
		var gap: float = float(leader["sPx"]) - float(ag["sPx"]) - leader_body * 0.5 - float(tdef["body_len"]) * 0.5
		if gap < 8.5:
			target_v = 0.0
			ag["waitReason"] = "following"
			ag["blockerAgentId"] = String(leader["id"])
		elif gap < 26.0:
			target_v = minf(target_v, float(leader["speedPx"]) * 0.90)
			ag["waitReason"] = "following"
			ag["blockerAgentId"] = String(leader["id"])

	var cab_stop_line: float = maxf(0.0, stop_s - float(tdef["cab_len"]) * 0.48 - 1.4)
	var dist_to_stop: float = cab_stop_line - float(ag["sPx"])
	ag["turnSignal"] = int(traj.get("turn_sig", 0)) if dist_to_stop < 44.0 else 0

	var nxt_eid: String = eid
	var nxt_fwd: bool = forward
	if (s_idx + 1) < path.size():
		nxt_eid = String(path[s_idx + 1]["edgeId"])
		nxt_fwd = bool(path[s_idx + 1]["forward"])

	var j_ahead: Dictionary = junction_map.get(String(step_d["toJunctionId"]), {})
	if not j_ahead.is_empty():
		var ctrl := String(j_ahead["control"])
		if float(ag["sPx"]) <= cab_stop_line + 1.5 and dist_to_stop < 48.0:
			if ctrl == "lights" and j_ahead.has("light"):
				var lt: Dictionary = j_ahead["light"]
				if is_movement_green_at_light(j_ahead, eid, forward, nxt_eid, nxt_fwd):
					lt["lastDetectorHit"] = real_time_sec
					target_v = minf(target_v, 48.0)
				else:
					if dist_to_stop <= 3.2:
						target_v = 0.0
						ag["waitReason"] = "red_light"
						ag["blockerAgentId"] = ""
					else:
						target_v = minf(target_v, maxf(5.5, dist_to_stop * 0.95))
			elif ctrl == "yield":
				# Update 1.9 authentic rule: ONLY minor arms check/yield; priority main-road trucks keep full road speed!
				var is_minor: bool = (j_ahead["yieldMinorEdgeIds"] as Array).has(eid)
				if is_minor:
					var conflict_id: String = _find_junction_conflict_agent(String(j_ahead["id"]), eid)
					if dist_to_stop <= 8.5 and float(ag["junctionWaitSec"]) < 1.35 and conflict_id != "":
						target_v = 0.0
						ag["waitReason"] = "yield"
						ag["blockerAgentId"] = conflict_id
					elif dist_to_stop < 22.0:
						target_v = minf(target_v, 28.0)
			elif ctrl == "roundabout" or ctrl == "roundabout2":
				var cap_rb: int = 4 if ctrl == "roundabout2" else 2
				var rb_rad: float = float((j_ahead.get("geom", {}) as Dictionary).get("r_outer", 18.0)) + 4.0
				if dist_to_stop <= 7.0 and float(ag["junctionWaitSec"]) < 0.95 and _count_near_junction(String(j_ahead["id"]), rb_rad) >= cap_rb:
					target_v = 0.0
					ag["waitReason"] = "roundabout"
					ag["blockerAgentId"] = _find_nearest_junction_agent(String(j_ahead["id"]), rb_rad, String(ag["id"]))
				else:
					target_v = minf(target_v, 36.0 if ctrl == "roundabout2" else 28.0)
		elif float(ag["sPx"]) > cab_stop_line + 1.5:
			if ctrl == "roundabout" or ctrl == "roundabout2":
				target_v = minf(target_v, 34.0 if ctrl == "roundabout2" else 27.0)
			elif ctrl == "yield" and not (j_ahead["yieldMinorEdgeIds"] as Array).has(eid) and int(traj.get("turn_sig", 0)) == 0:
				# Priority straight-through on main road keeps brisk speed
				target_v = minf(target_v, 54.0)
			else:
				target_v = minf(target_v, 40.0)

	var prev_v: float = float(ag["speedPx"])
	var cur_v: float = prev_v
	if cur_v < target_v:
		cur_v = minf(target_v, cur_v + float(tdef["accel"]) * dt)
	else:
		cur_v = maxf(target_v, cur_v - float(tdef["decel"]) * dt)

	ag["braking"] = (cur_v < prev_v - 4.5 * dt) or (cur_v < 4.0 and String(ag["waitReason"]) != "none")
	ag["speedPx"] = cur_v

	# Smooth 3-Stage Conflict / Gridlock Escalation (replaces abrupt 25s teleport!)
	if cur_v < 0.8:
		ag["junctionWaitSec"] = float(ag["junctionWaitSec"]) + dt
		ag["gridlockSec"] = float(ag["gridlockSec"]) + dt
		var gl: float = float(ag["gridlockSec"])
		var wr := String(ag["waitReason"])
		if gl > 3.5 and (wr == "yield" or wr == "roundabout"):
			cur_v = 9.5
			ag["speedPx"] = cur_v
		elif gl > 9.0 and wr != "red_light":
			cur_v = 14.0
			ag["speedPx"] = cur_v
		elif gl > 18.0:
			cur_v = 20.0
			ag["speedPx"] = cur_v
			ag["gridlockSec"] = 0.0
	else:
		ag["junctionWaitSec"] = 0.0
		ag["gridlockSec"] = maxf(0.0, float(ag["gridlockSec"]) - dt * 2.0)

	ag["sPx"] = float(ag["sPx"]) + cur_v * dt
	ag["visualLane"] = lerpf(float(ag["visualLane"]), float(ag["laneIndex"]), minf(1.0, dt * 8.0))

	if float(ag["sPx"]) >= step_total_len:
		ag["sPx"] = float(ag["sPx"]) - step_total_len
		ag["stepIndex"] = s_idx + 1
		ag["junctionWaitSec"] = 0.0
		s_idx = int(ag["stepIndex"])
		if s_idx >= path.size():
			_finish_agent_leg(ag, rt)
			return

	var pose: Dictionary = _sample_agent_step_pose(path, s_idx, float(ag["visualLane"]), float(ag["sPx"]))
	ag["pos"] = pose["pos"]
	ag["heading"] = pose["heading"]

	var units: Array[Dictionary] = GameCatalog.get_truck_units(String(ag["model"]))
	var cab_mid: float = (float(units[0]["front"]) + float(units[0]["rear"])) * 0.5
	var uposes: Array = ag.get("unitPoses", [])
	if uposes.size() != units.size():
		uposes = _make_initial_unit_poses(String(ag["model"]), ag["pos"], float(ag["heading"]))
		ag["unitPoses"] = uposes
	uposes[0]["pos"] = ag["pos"]
	uposes[0]["heading"] = ag["heading"]

	for ui in range(1, units.size()):
		var u_mid: float = (float(units[ui]["front"]) + float(units[ui]["rear"])) * 0.5
		var back_px: float = (u_mid - cab_mid) * GameCatalog.TRUCK_VIEW_SCALE
		var tr_s: float = float(ag["sPx"]) - back_px
		if tr_s >= 0.0:
			var tp: Dictionary = _sample_agent_step_pose(path, s_idx, float(ag["visualLane"]), tr_s)
			uposes[ui]["pos"] = tp["pos"]
			uposes[ui]["heading"] = tp["heading"]
		elif s_idx > 0 and road_map.has(String(path[s_idx - 1]["edgeId"])):
			var prev_traj: Dictionary = _get_step_trajectory(path, s_idx - 1, int(ag["laneIndex"]))
			var prev_s: float = maxf(0.0, float(prev_traj["total_len"]) + tr_s)
			var tp_prev: Dictionary = _sample_agent_step_pose(path, s_idx - 1, float(ag["visualLane"]), prev_s)
			uposes[ui]["pos"] = tp_prev["pos"]
			uposes[ui]["heading"] = tp_prev["heading"]
		else:
			var lead_p: Vector2 = uposes[ui - 1]["pos"]
			var cur_p: Vector2 = uposes[ui]["pos"]
			var prev_u_mid: float = (float(units[ui - 1]["front"]) + float(units[ui - 1]["rear"])) * 0.5
			var seg_len: float = maxf(1.5, (u_mid - prev_u_mid) * GameCatalog.TRUCK_VIEW_SCALE)
			var delta_v: Vector2 = lead_p - cur_p
			var ang: float = float(uposes[ui - 1]["heading"]) if delta_v.length_squared() < 0.005 else atan2(delta_v.y, delta_v.x)
			uposes[ui]["heading"] = ang
			uposes[ui]["pos"] = lead_p - Vector2(cos(ang), sin(ang)) * seg_len

	ag["trailerPoses"] = uposes.slice(1)

func _finish_agent_leg(ag: Dictionary, rt: Dictionary) -> void:
	ag["speedPx"] = 0.0
	ag["turnSignal"] = 0
	ag["blockerAgentId"] = ""
	var st := String(ag["state"])
	if st == "driving_outbound":
		ag["state"] = "queuing_bay"
		ag["pos"] = facility_map[String(rt["toFacilityId"])]["pos"]
	elif st == "driving_to_depot":
		ag["state"] = "at_depot"
		ag["dwellSec"] = 1.4
		ag["pos"] = depot.get("pos", ag["pos"])
		var d_ang: float = float(depot.get("angle", 0.0))
		ag["heading"] = d_ang
		var uposes: Array = _make_initial_unit_poses(String(ag["model"]), ag["pos"], d_ang)
		ag["unitPoses"] = uposes
		ag["trailerPoses"] = uposes.slice(1)
	else:
		ag["state"] = "loading"
		ag["dwellSec"] = 0.55
		ag["waitSec"] = 0.0
		ag["pos"] = facility_map[String(rt["fromFacilityId"])]["pos"]

func _find_junction_conflict_agent(j_id: String, minor_edge_id: String) -> String:
	var jp: Vector2 = junction_map[j_id]["pos"]
	for other in agents:
		var st := String(other["state"])
		if st != "driving_outbound" and st != "driving_return" and st != "driving_to_depot" and st != "driving_from_depot":
			continue
		var sd: Dictionary = _get_agent_current_step(other)
		if sd.is_empty() or String(sd["edgeId"]) == minor_edge_id:
			continue
		if String(sd["toJunctionId"]) == j_id and (other["pos"] as Vector2).distance_to(jp) < 34.0 and float(other["speedPx"]) > 5.0:
			return String(other["id"])
	return ""

func _has_junction_conflict(j_id: String, minor_edge_id: String) -> bool:
	return _find_junction_conflict_agent(j_id, minor_edge_id) != ""

func _find_nearest_junction_agent(j_id: String, rad: float, exclude_id: String) -> String:
	var jp: Vector2 = junction_map[j_id]["pos"]
	var best_id := ""
	var best_d := rad
	for other in agents:
		var oid := String(other["id"])
		if oid == exclude_id:
			continue
		var d: float = (other["pos"] as Vector2).distance_to(jp)
		if d < best_d:
			best_d = d
			best_id = oid
	return best_id


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

## Authentic CityGoals delivery rate: counts demand hubs (Station, Harbour, Market) only!
func get_global_delivery_rate_per_min(good_id: String) -> float:
	var cutoff: float = real_time_sec - 60.0
	var count: int = 0
	for f in facilities:
		var k := String(f["kind"])
		if k != "station" and k != "harbour" and k != "market":
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

## Authentic Overview Alerts generator (broken routes, idle trucks, stalled facilities, congested streets)
func get_system_alerts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rt in routes:
		var br := String(rt.get("brokenReason", ""))
		if br != "":
			var f_from: Dictionary = facility_map.get(String(rt["fromFacilityId"]), {})
			out.append({
				"kind": "broken_route",
				"severity": "bad",
				"title": "Rute Terputus: %s" % String(rt["name"]),
				"subtitle": br,
				"pos": f_from.get("pos", Vector2.ZERO),
				"routeId": String(rt["id"])
			})
	for ag in agents:
		var wr := String(ag.get("waitReason", "none"))
		var ws: float = float(ag.get("waitSec", 0.0))
		if ws >= 10.0 and (wr == "cargo_wait" or wr == "bay_full" or wr == "scrap_wait"):
			var rt_a: Dictionary = get_route(String(ag["routeId"]))
			var desc := "Menunggu muatan (%.0f dtk)" % ws if wr == "cargo_wait" else ("Antre dermaga muat (%.0f dtk)" % ws if wr == "bay_full" else "Gudang tujuan penuh!")
			out.append({
				"kind": "idle_truck",
				"severity": "warn" if wr != "scrap_wait" else "bad",
				"title": "Truk Tertahan (%s)" % String(rt_a.get("name", ag["id"])),
				"subtitle": desc,
				"pos": ag["pos"],
				"routeId": String(ag["routeId"])
			})
	for f in facilities:
		if not unlocked_regions.has(int(f["regionIndex"])):
			continue
		var sr := String(f.get("stalledReason", "none"))
		var ss: float = float(f.get("stalledSec", 0.0))
		if sr != "none" and ss >= 12.0:
			out.append({
				"kind": "facility_stall",
				"severity": "warn",
				"title": "%s: %s" % [String(f["name"]), "Gudang Output Penuh" if sr == "output_full" else "Kekurangan Bahan Input"],
				"subtitle": "Terhenti %.0f dtk — klik untuk inspeksi" % ss,
				"pos": f["pos"],
				"facilityId": String(f["id"])
			})
	for r in roads:
		if bool(r["isBuilt"]) and unlocked_regions.has(int(r["regionIndex"])) and float(r.get("congestionEMA", 0.0)) >= 0.85:
			var pts: PackedVector2Array = r["pts"]
			var mid: Vector2 = pts[pts.size() / 2] if not pts.is_empty() else Vector2.ZERO
			out.append({
				"kind": "congestion",
				"severity": "bad" if float(r["congestionEMA"]) >= 1.1 else "warn",
				"title": "Kemacetan Tinggi: %s" % String(r["name"]),
				"subtitle": "Kepadatan %d%% — tambah lajur, lampu, atau bundaran" % int(round(float(r["congestionEMA"]) * 100.0)),
				"pos": mid,
				"edgeId": String(r["id"])
			})
	return out

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
			"ow": r["oneWay"], "cl": r["closed"], "built": r["isBuilt"],
			"pk": r.get("pocketLevel", 0),
			"ps": r.get("pocketSize", 1),
			"alf": RoadGeom.get_effective_approach_lanes(r, true),
			"alb": RoadGeom.get_effective_approach_lanes(r, false),
			"tmf": r.get("turnMaskForward", 7),
			"tmb": r.get("turnMaskBackward", 7)
		})
	var save_juncs: Array = []
	for j in junctions:
		save_juncs.append({
			"id": j["id"], "ctrl": j["control"],
			"ym": j["yieldMinorEdgeIds"], "lt": j.get("light", null)
		})
	var save_facs: Array = []
	for f in facilities:
		save_facs.append({
			"id": f["id"], "up": f["upgrades"],
			"out": f["outputBuffer"], "in": f.get("inputBuffers", {}),
			"pile": f.get("yardPile", []), "scrap": f.get("scrappedCount", 0)
		})
	var save_routes: Array = []
	for rt in routes:
		save_routes.append({
			"from": rt["fromFacilityId"], "to": rt["toFacilityId"],
			"good": rt["goodFilter"], "wps": rt["waypoints"],
			"wpsBack": rt.get("waypointsBack", []),
			"swb": rt.get("sameWayBack", true),
			"col": (rt["color"] as Color).to_html(false),
			"model": rt["truckModel"], "cnt": (rt["activeTruckIds"] as Array).size()
		})

	var payload := {
		"v": 3,
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
	var save_v: int = int(d.get("v", 2))
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
			regions[ri]["unlockedAtRealSec"] = 0.0
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
			var spk: int = int(sr.get("pk", 0))
			rm["pocketLevel"] = spk
			rm["pocketSize"] = clampi(int(sr.get("ps", maxi(0, spk - 1) if spk > 0 else 1)), 0, 2)
			rm["approachLanesForward"] = clampi(int(sr.get("alf", int(rm["lanesForward"]) + (1 if spk > 0 else 0))), int(rm["lanesForward"]), 4)
			rm["approachLanesBackward"] = clampi(int(sr.get("alb", int(rm["lanesBackward"]) + (1 if spk > 0 else 0))), int(rm["lanesBackward"]), 4)
			rm["turnMaskForward"] = int(sr.get("tmf", 7))
			rm["turnMaskBackward"] = int(sr.get("tmb", 7))
	for sj in d.get("juncs", []):
		var jm: Dictionary = junction_map.get(String(sj["id"]), {})
		if not jm.is_empty():
			jm["control"] = String(sj["ctrl"])
			jm["yieldMinorEdgeIds"] = sj["ym"]
			if sj["lt"] != null:
				jm["light"] = sj["lt"]
				_ensure_light_schema(jm)
	for sf in d.get("facs", []):
		var fm: Dictionary = facility_map.get(String(sf["id"]), {})
		if not fm.is_empty():
			var up_d: Dictionary = (sf["up"] as Dictionary).duplicate(true)
			var raw_bays: int = int(up_d.get("bays", 0))
			if save_v < 3 and raw_bays > 0:
				raw_bays -= 1
			up_d["bays"] = clampi(raw_bays, 0, 7)
			fm["upgrades"] = up_d
			fm["outputBuffer"] = int(sf["out"])
			if sf.has("in") and typeof(sf["in"]) == TYPE_DICTIONARY:
				fm["inputBuffers"] = (sf["in"] as Dictionary).duplicate(true)
			if sf.has("pile") and typeof(sf["pile"]) == TYPE_ARRAY:
				fm["yardPile"] = (sf["pile"] as Array).duplicate()
			fm["scrappedCount"] = int(sf.get("scrap", 0))
	for srt in d.get("routes", []):
		var created: Dictionary = create_route(String(srt["from"]), String(srt["to"]), String(srt["good"]), false)
		if not created.is_empty():
			created["waypoints"] = (srt.get("wps", []) as Array).duplicate()
			created["waypointsBack"] = (srt.get("wpsBack", []) as Array).duplicate()
			created["sameWayBack"] = bool(srt.get("swb", true))
			if srt.has("col"):
				created["color"] = Color.from_string("#" + String(srt["col"]).trim_prefix("#"), created["color"])
			created["truckModel"] = String(srt["model"])
			recompute_single_route(created)
			for _k in range(int(srt["cnt"])):
				add_truck_to_route(String(created["id"]), true)
	return true

