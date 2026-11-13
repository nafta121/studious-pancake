extends Node2D

## Root orchestrator for Incremental Traffic: Karesidenan Madiun (Godot 4.7.2 Android).

var sfx: SfxSynth
var sim: SimEngine
var camera: TouchCamera2D
var map_view: MapView25D
var hud: AndroidHUD

var _target_fps: int = 60
var _autosave_timer: float = 0.0
var _smoke_mode: bool = false
var _smoke_dir: String = ""
var _smoke_frame: int = 0
var _smoke_summary: Array[String] = []

func _ready() -> void:
	var env_smoke: String = OS.get_environment("MADIUN_SMOKE_DIR")
	if env_smoke != "":
		_smoke_mode = true
		_smoke_dir = env_smoke
	var user_args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in range(user_args.size()):
		if user_args[i] == "--smoke-test":
			_smoke_mode = true
			if i + 1 < user_args.size():
				_smoke_dir = user_args[i + 1]

	Engine.max_fps = _target_fps

	sfx = SfxSynth.new()
	add_child(sfx)

	sim = SimEngine.new()
	sim.disable_persistence = _smoke_mode
	add_child(sim)
	sim.initialize(sfx, "karisidenan_madiun", not _smoke_mode)

	camera = TouchCamera2D.new()
	camera.enabled = true
	add_child(camera)
	camera.focus_map(sim.map_def["initialView"], sim.map_def["boundsWorld"])
	camera.world_tapped.connect(_on_world_tapped)
	camera.manual_pan_started.connect(func():
		if hud != null:
			hud.follow_truck_id = ""
	)

	map_view = MapView25D.new()
	add_child(map_view)
	map_view.setup(sim, camera)

	hud = AndroidHUD.new()
	add_child(hud)
	hud.setup(sim, map_view)
	hud.map_selected.connect(_on_map_selected)
	hud.perf_preset_changed.connect(_on_perf_preset_changed)
	hud.theme_toggled.connect(_on_theme_toggled)
	hud.hide_flyovers_toggled.connect(func(on: bool): map_view.set_hide_flyovers(on))
	hud.colorblind_toggled.connect(func(on: bool): map_view.set_colorblind_mode(on))
	hud.cloud_shadows_toggled.connect(func(on: bool): map_view.set_cloud_shadows(on))
	hud.focus_world_requested.connect(func(p: Vector2): camera.pan_to_world(p, 0.85))

	if _smoke_mode:
		_prepare_smoke_test()

func _process(delta: float) -> void:
	if sim == null:
		return
	sim.step_frame(delta)

	if hud != null and hud.follow_truck_id != "":
		var ag_f: Dictionary = sim.get_agent(hud.follow_truck_id)
		if ag_f.is_empty():
			hud.follow_truck_id = ""
		else:
			camera.global_position = camera.global_position.lerp(ag_f["pos"], minf(1.0, delta * 9.0))
			camera._clamp_to_bounds()

	if _smoke_mode:
		_step_smoke()
		return

	_autosave_timer += delta
	if _autosave_timer >= 25.0:
		_autosave_timer = 0.0
		sim.save_to_disk()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if sfx != null:
			sfx.shutdown()
		return
	if sim == null:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		sim.save_to_disk()
		Engine.max_fps = 10
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Engine.max_fps = _target_fps
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if hud != null and hud.current_drawer != "":
			hud.close_drawer()
		elif map_view != null and map_view.active_tool != "pan":
			hud._on_toolbar_pressed("pan")
		else:
			sim.save_to_disk()
			if sfx != null:
				sfx.shutdown()
			get_tree().quit()

func _on_map_selected(map_id: String) -> void:
	sim.save_to_disk()
	sim.load_map(map_id, not _smoke_mode)
	map_view.selected_facility_id = ""
	map_view.selected_junction_id = ""
	map_view.selected_road_id = ""
	map_view.selected_route_id = ""
	map_view.selected_truck_id = ""
	map_view.editing_return_waypoints = false
	map_view.route_draft_from_id = ""
	if hud != null:
		hud.follow_truck_id = ""
	camera.focus_map(sim.map_def["initialView"], sim.map_def["boundsWorld"])
	hud.refresh_top_bar()
	hud.show_toast_banner("Peta dimuat: " + String(sim.map_def["name"]), 2.8)

func _on_perf_preset_changed(preset_id: String) -> void:
	if preset_id == "battery":
		_target_fps = 30
	elif preset_id == "ultra":
		_target_fps = 120
	else:
		_target_fps = 60
	Engine.max_fps = _target_fps
	map_view.set_perf_preset(preset_id)
	hud.show_toast_banner("Preset performa diatur ke %d FPS" % _target_fps, 2.2)

func _on_theme_toggled(is_dark: bool) -> void:
	map_view.set_theme_dark(is_dark)

func _on_world_tapped(world_pos: Vector2) -> void:
	var inv_z: float = 1.0 / maxf(0.28, camera.zoom.x)
	var fac_r: float = clampf(32.0 * inv_z, 22.0, 68.0)
	var junc_r: float = clampf(26.0 * inv_z, 18.0, 54.0)
	var road_r: float = clampf(22.0 * inv_z, 14.0, 48.0)
	var trk_r: float = clampf(14.5 * inv_z, 8.5, 28.0)

	var tool := map_view.active_tool

	if tool == "route":
		var f_hit: Dictionary = RoadGeom.hit_test_facility(sim.facilities, sim.unlocked_regions, world_pos, fac_r)
		if f_hit.is_empty():
			hud.show_toast_banner("Ketuk tepat pada gedung Supplier, Pabrik, Stasiun, atau Pelabuhan!", 2.2)
			return
		var fid := String(f_hit["id"])
		if map_view.route_draft_from_id == "":
			map_view.route_draft_from_id = fid
			sfx.tap()
			hud.show_toast_banner("Asal: %s → sekarang ketuk Fasilitas Tujuan!" % String(f_hit["name"]), 3.0)
		elif map_view.route_draft_from_id == fid:
			map_view.route_draft_from_id = ""
			hud.show_toast_banner("Pembuatan rute dibatalkan.", 1.8)
		else:
			var created: Dictionary = sim.create_route(map_view.route_draft_from_id, fid, "any", true)
			map_view.route_draft_from_id = ""
			if not created.is_empty():
				map_view.selected_route_id = String(created["id"])
				hud.open_drawer("routes")
				hud.show_toast_banner("Rute baru aktif: " + String(created["name"]), 2.8)
			else:
				hud.show_toast_banner("Gagal membuat rute antar-fasilitas ini.", 2.4)
		return

	if tool in ["yield", "roundabout", "lights"]:
		var j_hit: Dictionary = RoadGeom.hit_test_junction(sim.junctions, sim.unlocked_regions, world_pos, junc_r)
		if j_hit.is_empty():
			hud.show_toast_banner("Ketuk persimpangan jalan yang terbuka!", 2.0)
			return
		var jid := String(j_hit["id"])
		var msg: String = sim.apply_junction_control(jid, tool)
		map_view.selected_junction_id = jid
		if msg != "":
			hud.show_toast_banner(msg, 2.5)
		if tool == "lights" and String(j_hit["control"]) == "lights":
			hud.open_drawer("junction")
		return

	if tool in ["lanes_add", "lanes_remove", "pocket", "turn_arrows", "one_way", "close_street"]:
		var r_hit: Dictionary = RoadGeom.hit_test_road(sim.roads, sim.unlocked_regions, world_pos, road_r, false)
		if r_hit.is_empty():
			hud.show_toast_banner("Ketuk ruas jalan raya yang terbuka!", 2.0)
			return
		var rid := String(r_hit["id"])
		map_view.selected_road_id = rid
		var res_msg: String = ""
		if tool == "lanes_add":
			res_msg = sim.modify_road_lanes(rid, 1, hud.lane_dir_mode)
		elif tool == "lanes_remove":
			res_msg = sim.modify_road_lanes(rid, -1, hud.lane_dir_mode)
		elif tool == "pocket":
			res_msg = sim.cycle_road_pocket(rid)
		elif tool == "turn_arrows":
			res_msg = sim.cycle_road_turn_mask(rid, hud.lane_dir_mode != "backward")
		elif tool == "one_way":
			res_msg = sim.cycle_road_one_way(rid)
		elif tool == "close_street":
			res_msg = sim.toggle_close_street(rid)
		if res_msg != "":
			hud.show_toast_banner(res_msg, 2.5)
		return

	# Default 'pan' / inspect mode:
	# 1) Waypoint editing when a route is highlighted on the map
	if map_view.selected_route_id != "" and hud.current_drawer in ["", "routes"]:
		var j_wp: Dictionary = RoadGeom.hit_test_junction(sim.junctions, sim.unlocked_regions, world_pos, junc_r)
		if not j_wp.is_empty():
			var j_wp_id := String(j_wp["id"])
			sim.toggle_route_waypoint(map_view.selected_route_id, j_wp_id, map_view.editing_return_waypoints)
			if hud.current_drawer == "routes":
				hud._populate_drawer()
			var leg_nm := "arah pulang (return)" if map_view.editing_return_waypoints else "arah berangkat"
			hud.show_toast_banner("Waypoint %s diperbarui pada %s" % [leg_nm, String(j_wp.get("name", "simpang"))], 2.2)
			return

	# 2) Direct Truck hit-test -> opens authentic `TruckInspector`!
	var ag_hit: Dictionary = sim.hit_test_agent(world_pos, trk_r, false)
	if not ag_hit.is_empty():
		sfx.tap(10)
		map_view.selected_truck_id = String(ag_hit["id"])
		map_view.selected_facility_id = ""
		map_view.selected_junction_id = ""
		map_view.selected_road_id = ""
		hud.open_drawer("truck")
		return

	# 3) Facility -> Junction -> Road
	var fac: Dictionary = RoadGeom.hit_test_facility(sim.facilities, sim.unlocked_regions, world_pos, fac_r)
	if not fac.is_empty():
		sfx.tap(10)
		hud.follow_truck_id = ""
		map_view.selected_truck_id = ""
		map_view.selected_facility_id = String(fac["id"])
		map_view.selected_junction_id = ""
		map_view.selected_road_id = ""
		hud.open_drawer("facility")
		return

	var junc: Dictionary = RoadGeom.hit_test_junction(sim.junctions, sim.unlocked_regions, world_pos, junc_r)
	if not junc.is_empty():
		var j_id := String(junc["id"])
		sfx.tap(10)
		hud.follow_truck_id = ""
		map_view.selected_truck_id = ""
		map_view.selected_junction_id = j_id
		map_view.selected_facility_id = ""
		map_view.selected_road_id = ""
		hud.open_drawer("junction")
		return

	var rd: Dictionary = RoadGeom.hit_test_road(sim.roads, sim.unlocked_regions, world_pos, road_r, false)
	if not rd.is_empty():
		sfx.tap(10)
		hud.follow_truck_id = ""
		map_view.selected_truck_id = ""
		map_view.selected_road_id = String(rd["id"])
		map_view.selected_facility_id = ""
		map_view.selected_junction_id = ""
		hud.open_drawer("road")
		return

	hud.follow_truck_id = ""
	map_view.selected_truck_id = ""
	map_view.selected_facility_id = ""
	map_view.selected_junction_id = ""
	map_view.selected_road_id = ""
	map_view.selected_route_id = ""
	map_view.editing_return_waypoints = false
	if hud.current_drawer in ["facility", "truck", "junction", "road"]:
		hud.close_drawer()

func _prepare_smoke_test() -> void:
	if _smoke_dir != "":
		DirAccess.make_dir_recursive_absolute(_smoke_dir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_tree().root.size = Vector2i(1280, 720)

	# 1. Validate all 44 commodities, `ShapeGlyphs` vector geometry/keylines, and `Ledger` pricing/resale math
	assert(GameCatalog.GOODS.size() == 44, "Must have all 44 Incremental Traffic commodities")
	var cat_errs: Array[String] = GameCatalog.validate_catalog()
	assert(cat_errs.is_empty(), "Catalog validation failed: " + ", ".join(cat_errs))
	var glyph_batch := TriBatch2D.new()
	for gid in GameCatalog.GOODS.keys():
		var c_std: Color = ShapeGlyphs.color_of(String(gid), false)
		var c_cb: Color = ShapeGlyphs.color_of(String(gid), true)
		assert(c_std.a > 0.9 and c_cb.a > 0.9, "Invalid ShapeGlyphs color for " + String(gid))
		assert(ShapeGlyphs.box_center(String(gid)).is_finite(), "Non-finite box_center for " + String(gid))
		glyph_batch.clear()
		ShapeGlyphs.add_to_batch(glyph_batch, String(gid), Vector2.ZERO, 16.0, 0.0, Transform2D.IDENTITY, Color("1D2128"), 0.8, false)
		assert(glyph_batch.verts.size() >= 3 and glyph_batch.indices.size() >= 3, "Empty ShapeGlyphs template for " + String(gid))
		glyph_batch.clear()
		ShapeGlyphs.add_keylined(glyph_batch, String(gid), Vector2.ZERO, 16.0, ShapeGlyphs.truck_angle(String(gid)), Transform2D.IDENTITY, Color("1D2128"), false, true)
		assert(glyph_batch.verts.size() >= 3 and glyph_batch.indices.size() >= 3, "Empty keylined ShapeGlyphs for " + String(gid))
		glyph_batch.clear()
		ShapeGlyphs.add_tinted(glyph_batch, String(gid), Vector2.ZERO, 16.0, Color(0, 0, 0, 0.25))
		assert(glyph_batch.verts.size() >= 3, "Empty silhouette ShapeGlyphs for " + String(gid))
	assert(is_equal_approx(ShapeGlyphs.truck_angle("fish"), PI), "fish truck_angle must be PI")
	assert(is_equal_approx(ShapeGlyphs.truck_angle("bull"), 0.0), "bull truck_angle must be 0.0")
	assert(is_equal_approx(ShapeGlyphs.truck_angle("dot"), PI * 0.5), "default truck_angle must be PI/2")

	# 2. Validate all 5 Truck models (`TruckModel`, capacity rules, kinematics & `Ledger` 2-sig rounding)
	assert(GameCatalog.TRUCK_ORDER == ["hauler", "freighter", "lowloader", "express", "bulker"], "Canonical TRUCK_ORDER mismatch")
	assert(GameCatalog.round_2sig(15.0) == 15 and GameCatalog.round_2sig(64.8) == 65 and GameCatalog.round_2sig(1234.0) == 1200, "Ledger round_2sig mismatch")
	var buy_10: int = GameCatalog.compute_truck_buy_price("freighter", 9, 65)
	var resale_10: int = GameCatalog.compute_truck_resale_price("freighter", 10, 66)
	assert(resale_10 == int(round(float(buy_10) * 0.5)), "Marginal resale mismatch")
	assert(GameCatalog.compute_max_carry_units("bulker", "dot") == 6 and GameCatalog.compute_max_carry_units("bulker", "bar") == 0, "Bulker must carry 6 raw shapes only")
	assert(GameCatalog.compute_max_carry_units("lowloader", "dot") == 3 and GameCatalog.compute_max_carry_units("lowloader", "rocket") == 3, "Lowloader must carry 3 of any size")
	assert(GameCatalog.compute_max_carry_units("freighter", "dot") == 4 and GameCatalog.compute_max_carry_units("freighter", "fish") == 2, "Freighter must carry 4 small or 2 large")
	assert(GameCatalog.compute_max_carry_units("hauler", "dot") == 2 and GameCatalog.compute_max_carry_units("hauler", "fish") == 1, "Hauler must carry 2 small or 1 large")
	assert(GameCatalog.get_truck_units("lowloader").size() == 4 and GameCatalog.get_truck_units("bulker").size() == 3, "Articulated unit counts mismatch")
	assert(GameCatalog.compute_truck_drive_time("express", 220.0) < GameCatalog.compute_truck_drive_time("hauler", 220.0), "Express drive_time must beat Hauler")

	# 3. Load & step all 7 Karesidenan Madiun maps, verifying starter Depot, initial Lv.0 = 1 bay, and storage pads
	for m in sim.maps_list:
		var mid := String(m["id"])
		sim.load_map(mid, false)
		assert(not sim.depot.is_empty() and sim.junction_map.has(String(sim.depot["junctionId"])), "Missing starter Depot on " + mid)
		assert(sim.get_total_bays(sim.facilities[0]) == 1, "Initial Lv.0 facility must start with 1 bay on " + mid)
		for _step in range(15):
			sim._step_fixed(SimEngine.SIM_DT)
		_smoke_summary.append("%s(regs=%d,roads=%d,facs=%d,trucks=%d)" % [
			mid, sim.regions.size(), sim.roads.size(), sim.facilities.size(), sim.agents.size()
		])

	# 4. Exercise Storage capacities (`4..60`), `CargoFlights`, Scrapping, `waypointsBack`, `RouteBreakMarks`,
	#    `Depot` & `TruckInspector` interventions, and Schema `v: 3` save/restore roundtrip!
	sim.load_map("karisidenan_madiun", false)
	sim.cash = 500000
	for ri in [1, 2]:
		sim.regions[ri]["unlocked"] = true
	sim._rebuild_lookups()
	sim._refresh_network_geometry()
	sim.recompute_all_routes()

	var fac0: Dictionary = sim.facilities[0]
	var expected_caps := [4, 8, 15, 30, 60]
	for blv in range(5):
		fac0["upgrades"]["buffer"] = blv
		assert(sim.get_capacity_slots(fac0) == expected_caps[blv], "Buffer capacity mismatch at Lv." + str(blv))
	fac0["upgrades"]["buffer"] = 1
	assert(not sim.get_facility_storage_pads(fac0).is_empty(), "Supplier must expose concrete storage pad")

	# Test CargoFlights hop + crumble lifecycle
	sim.launch_cargo_hop("dot", fac0["pos"], fac0["pos"] + Vector2(24, 0))
	sim.launch_cargo_crumble("wedge", fac0["pos"])
	assert(sim.cargo_flights.size() >= 2, "CargoFlights failed to spawn")

	# Test RouteWaypoints (`waypointsBack`), `RouteBreakMarks` (`toggle_close_street`), `Depot`, `leave_bay_early`, and Schema `v: 3` save/restore
	assert(not sim.routes.is_empty(), "Starter route must exist")
	var rt0: Dictionary = sim.routes[0]
	var rt0_id := String(rt0["id"])
	sim.set_route_same_way_back(rt0_id, false)
	var test_wp_jid := String(sim.junctions[0]["id"])
	sim.toggle_route_waypoint(rt0_id, test_wp_jid, true)
	assert((rt0["waypointsBack"] as Array).has(test_wp_jid), "Return-leg waypoint not recorded")

	# Test RouteBreakMarks when closing an edge on rt0
	if not (rt0["forwardPath"] as Array).is_empty():
		var close_eid := String(rt0["forwardPath"][0]["edgeId"])
		sim.toggle_close_street(close_eid)
		if String(rt0["brokenReason"]) != "":
			assert(String(rt0["brokenTag"]) != "", "Broken route must populate RouteBreakMarks brokenTag")
		sim.toggle_close_street(close_eid) # reopen

	# Test TruckInspector interventions (`diagnose_agent`, `leave_bay_early`, `send_agent_to_depot`) & Schema `v: 3` save/restore
	assert(not sim.agents.is_empty(), "Starter fleet must have agents")
	var ag0: Dictionary = sim.agents[0]
	var ag0_id := String(ag0["id"])
	var diag0: Dictionary = sim.diagnose_agent(ag0)
	assert(diag0.has("status") and diag0.has("chain"), "diagnose_agent missing keys")
	ag0["state"] = "queuing_bay"
	ag0["cargoGood"] = "dot"
	ag0["cargoQty"] = 2
	var pre_cash: int = sim.cash
	assert(sim.leave_bay_early(ag0_id), "leave_bay_early must succeed from queuing_bay")
	assert(sim.cash > pre_cash, "leave_bay_early must pay 10% salvage scrap")
	assert(sim.send_agent_to_depot(ag0_id), "send_agent_to_depot must succeed")
	assert(String(ag0["state"]) in ["driving_to_depot", "at_depot"], "Agent must enter depot state")

	var prev_persist: bool = sim.disable_persistence
	sim.disable_persistence = false
	sim.save_to_disk()
	var save_path := "user://save_karisidenan_madiun.json"
	assert(FileAccess.file_exists(save_path), "save_to_disk must create save file")
	var sf := FileAccess.open(save_path, FileAccess.READ)
	var saved_v3: Dictionary = JSON.parse_string(sf.get_as_text())
	sf = null
	assert(int(saved_v3["v"]) == 3, "Save schema must be v: 3")
	sim.load_map("karisidenan_madiun", true)
	sim.disable_persistence = prev_persist
	var found_restored_wp := false
	for rt_chk in sim.routes:
		if (rt_chk.get("waypointsBack", []) as Array).has(test_wp_jid):
			found_restored_wp = true
			break
	assert(found_restored_wp, "Schema v3 must restore waypointsBack")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	# 5. Prepare rich showcase scene for Karesidenan Madiun featuring all 5 truck models!
	sim.load_map("karisidenan_madiun", false)
	sim.cash = 48200
	sim.cash_history = [32400, 33800, 35100, 36900, 38200, 40500, 41900, 44100, 46300, 48200]
	for m_ulk in GameCatalog.TRUCK_ORDER:
		sim.unlocked_licenses[m_ulk] = true
	for ri2 in [1, 2]:
		sim.regions[ri2]["unlocked"] = true
	sim._rebuild_lookups()
	sim._refresh_network_geometry()
	sim.recompute_all_routes()

	# Upgrade starter facilities' buffers so stocked concrete storage beds show crisp ShapeGlyphs grids
	for fi in range(mini(6, sim.facilities.size())):
		sim.facilities[fi]["upgrades"]["buffer"] = 2
		sim.facilities[fi]["upgrades"]["bays"] = 2
	if sim.facilities.size() >= 10:
		var r_fr: Dictionary = sim.create_route(String(sim.facilities[0]["id"]), String(sim.facilities[3]["id"]), "any", true)
		if not r_fr.is_empty():
			sim.cash += 50000
			sim.apply_route_model_swap(String(r_fr["id"]), "bulker")
			sim.add_truck_to_route(String(r_fr["id"]), false)
		var r_ex: Dictionary = sim.create_route(String(sim.facilities[2]["id"]), String(sim.facilities[4]["id"]), "any", true)
		if not r_ex.is_empty():
			sim.cash += 50000
			sim.apply_route_model_swap(String(r_ex["id"]), "express")
			sim.add_truck_to_route(String(r_ex["id"]), false)
		var r_ll: Dictionary = sim.create_route(String(sim.facilities[3]["id"]), String(sim.facilities[6]["id"]), "any", true)
		if not r_ll.is_empty():
			sim.cash += 50000
			sim.apply_route_model_swap(String(r_ll["id"]), "lowloader")
			sim.add_truck_to_route(String(r_ll["id"]), false)
		if sim.routes.size() >= 1:
			sim.cash += 50000
			sim.apply_route_model_swap(String(sim.routes[0]["id"]), "freighter")
			sim.add_truck_to_route(String(sim.routes[0]["id"]), false)
	sim.cash = 48200
	sim.map_static_dirty.emit()
	for _s in range(300):
		sim._step_fixed(SimEngine.SIM_DT)
	if sim.facilities.size() >= 4:
		sim.spawn_toast(sim.facilities[3]["pos"] + Vector2(0, -18), "⚡+$200", Color("FFD54A"))
		sim.launch_cargo_hop("dot", sim.facilities[0]["pos"], sim.facilities[0]["pos"] + Vector2(16, 2))
	camera.focus_map({"x": 225.0, "y": -265.0, "zoom": 1.32}, sim.map_def["boundsWorld"])
	hud._layout_responsive()
	hud.refresh_top_bar()
	hud._refresh_goals_panel()

func _step_smoke() -> void:
	_smoke_frame += 1
	if _smoke_frame == 8:
		_save_shot_sync("godot_android_landscape_karisidenan.png")
		var pick_fid := String(sim.facilities[1]["id"])
		for f in sim.facilities:
			if String(f["kind"]) == "factory" and sim.unlocked_regions.has(int(f["regionIndex"])):
				pick_fid = String(f["id"])
				break
		map_view.selected_facility_id = pick_fid
		if not sim.routes.is_empty():
			hud._fac_swap_route_id = String(sim.routes[0]["id"])
		hud.open_drawer("facility")
		camera.focus_map({"x": 140.0, "y": -250.0, "zoom": 1.18}, sim.map_def["boundsWorld"])
	elif _smoke_frame == 16:
		_save_shot_sync("godot_android_inspector_madiun.png")
		hud._fac_swap_route_id = ""
		map_view.selected_facility_id = ""
		# Select an active driving truck to showcase authentic TruckInspector + remaining path + concrete storage beds!
		var pick_tid := ""
		var pick_tpos := Vector2(200.0, -250.0)
		for ag in sim.agents:
			if String(ag["state"]) in ["driving_outbound", "driving_return"] and int(ag.get("cargoQty", 0)) > 0:
				pick_tid = String(ag["id"])
				pick_tpos = ag["pos"]
				break
		if pick_tid == "" and not sim.agents.is_empty():
			pick_tid = String(sim.agents[0]["id"])
			pick_tpos = sim.agents[0]["pos"]
		if pick_tid != "":
			map_view.selected_truck_id = pick_tid
			hud.open_drawer("truck")
			if sim.facilities.size() >= 2:
				sim.launch_cargo_hop("wedge", sim.facilities[1]["pos"] + Vector2(-15, 1), sim.facilities[1]["pos"])
			camera.focus_map({"x": pick_tpos.x - 36.0, "y": pick_tpos.y, "zoom": 2.05}, sim.map_def["boundsWorld"])
	elif _smoke_frame == 22:
		_save_shot_sync("godot_android_trucks_storage_closeup.png")
		map_view.selected_truck_id = ""
		hud.open_drawer("trucks")
		hud.open_drawer("alerts")
		hud.open_drawer("settings")
		hud.open_drawer("routes")
		camera.focus_map({"x": 225.0, "y": -265.0, "zoom": 1.25}, sim.map_def["boundsWorld"])
	elif _smoke_frame == 28:
		_save_shot_sync("godot_android_overview_routes.png")
		hud.close_drawer()
		sim.night_mode = true
		sim.day_clock_01 = 22.0 / 24.0
		map_view._night_blend = 1.0
		hud.dark_mode = true
		hud._apply_styles()
		map_view.set_theme_dark(true)
		hud._toggle_overlay_mode("flow")
	elif _smoke_frame == 36:
		_save_shot_sync("godot_android_night_flow.png")
		sim.night_mode = false
		sim.day_clock_01 = 0.375
		map_view._night_blend = 0.0
		hud.dark_mode = false
		hud._apply_styles()
		map_view.set_theme_dark(false)
		hud._toggle_overlay_mode("flow") # back to "none"
		_on_map_selected("kab_pacitan")
		for _s2 in range(180):
			sim._step_fixed(SimEngine.SIM_DT)
		for fp in sim.facilities:
			if String(fp["kind"]) == "harbour":
				map_view.selected_facility_id = String(fp["id"])
				hud.open_drawer("facility")
				break
		hud.close_drawer()
		map_view.selected_facility_id = ""
	elif _smoke_frame == 44:
		_save_shot_sync("godot_android_pacitan_harbour.png")
		sim.load_map("kota_madiun", false)
		sim.cash = 65000
		for m_u2 in GameCatalog.TRUCK_ORDER:
			sim.unlocked_licenses[m_u2] = true
		for ri3 in [1, 2]:
			if ri3 < sim.regions.size():
				sim.regions[ri3]["unlocked"] = true
		sim._rebuild_lookups()
		if sim.junction_map.has("km_sleko"):
			sim.junction_map["km_sleko"]["control"] = "roundabout2"
		if sim.road_map.has("km_e10"):
			sim.road_map["km_e10"]["approachLanesForward"] = 3
			sim.road_map["km_e10"]["pocketSize"] = 1
		if sim.road_map.has("km_e12"):
			sim.road_map["km_e12"]["approachLanesBackward"] = 3
			sim.road_map["km_e12"]["pocketSize"] = 1
		if sim.road_map.has("km_e13"):
			sim.road_map["km_e13"]["approachLanesForward"] = 2
			sim.road_map["km_e13"]["pocketSize"] = 1
		sim._refresh_network_geometry()
		sim.recompute_all_routes()
		if sim.facilities.size() >= 7:
			var r_km: Dictionary = sim.create_route(String(sim.facilities[3]["id"]), String(sim.facilities[5]["id"]), "any", true)
			if not r_km.is_empty():
				sim.cash += 50000
				sim.apply_route_model_swap(String(r_km["id"]), "express")
				sim.add_truck_to_route(String(r_km["id"]), false)
				sim.add_truck_to_route(String(r_km["id"]), false)
		sim.cash = 65000
		sim.map_static_dirty.emit()
		for _s_cu in range(240):
			sim._step_fixed(SimEngine.SIM_DT)
		hud.close_drawer()
		hud.show_toast_banner("", 0.0)
		map_view.selected_junction_id = "km_pasarbesar"
		camera.focus_map({"x": -62.0, "y": 90.0, "zoom": 2.15}, sim.map_def["boundsWorld"])
		hud._layout_responsive()
		hud.refresh_top_bar()
		hud._refresh_goals_panel()
	elif _smoke_frame == 52:
		_save_shot_sync("godot_android_junction_roundabout_closeup.png")
		map_view.selected_junction_id = ""
		map_view.selected_road_id = "km_e10"
		hud.open_drawer("road")
		camera.focus_map({"x": -115.0, "y": 82.0, "zoom": 2.05}, sim.map_def["boundsWorld"])
	elif _smoke_frame == 58:
		_save_shot_sync("godot_android_street_editor_lanes.png")
		map_view.selected_road_id = ""
		DisplayServer.window_set_size(Vector2i(480, 960))
		get_tree().root.size = Vector2i(480, 960)
		_on_map_selected("kota_madiun")
		for _s3 in range(160):
			sim._step_fixed(SimEngine.SIM_DT)
		hud._layout_responsive()
		hud.open_drawer("maps")
	elif _smoke_frame == 68:
		_save_shot_sync("godot_android_portrait_kota_madiun.png")
		hud.close_drawer()
		if sfx != null:
			sfx.shutdown()
	elif _smoke_frame == 70:
		print("SMOKE_TEST_OK goods=%d trucks=%d maps=%d details=%s" % [
			GameCatalog.GOODS.size(), GameCatalog.TRUCK_ORDER.size(), _smoke_summary.size(), "; ".join(_smoke_summary)
		])
		get_tree().quit(0)

func _save_shot_sync(filename: String) -> void:
	if _smoke_dir == "":
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(_smoke_dir.path_join(filename))
