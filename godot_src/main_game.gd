extends Node2D

## Root orchestrator for Incremental Traffic: Karesidenan Madiun (Godot 4.7.2 Android).
## Integrates SimEngine, TouchCamera2D, MapView25D, WorldShows, AndroidHUD, and StageOverlays.

var sfx: SfxSynth
var sim: SimEngine
var camera: TouchCamera2D
var map_view: MapView25D
var world_shows: WorldShows
var hud: AndroidHUD
var stage_overlays: StageOverlays

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
	if not sim.camera_meta.is_empty():
		camera.apply_camera_meta(sim.camera_meta)
	camera.world_tapped.connect(_on_world_tapped)
	camera.manual_pan_started.connect(func():
		if hud != null:
			hud.follow_truck_id = ""
	)

	map_view = MapView25D.new()
	add_child(map_view)
	map_view.setup(sim, camera)

	world_shows = WorldShows.new()
	add_child(world_shows)
	world_shows.setup(sim, camera, map_view, sfx)

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

	stage_overlays = StageOverlays.new()
	add_child(stage_overlays)
	stage_overlays.setup(sim, camera, map_view, hud, sfx)

	world_shows.show_completed.connect(func(info: Dictionary):
		if not _smoke_mode:
			stage_overlays.show_region_open_popup(info)
	)
	world_shows.status_message.connect(func(msg: String): hud.show_toast_banner(msg, 2.6))
	hud.pause_menu_requested.connect(func(): stage_overlays.show_pause_menu())
	stage_overlays.toast_requested.connect(func(msg: String): hud.show_toast_banner(msg, 2.5))
	stage_overlays.map_load_requested.connect(_on_stage_map_load_requested)
	stage_overlays.title_visibility_changed.connect(func(open: bool):
		if world_shows != null:
			world_shows.ui_blocked = open or stage_overlays.is_modal_open
	)

	if _smoke_mode:
		_prepare_smoke_test()
	else:
		stage_overlays.show_title_stage()

func _process(delta: float) -> void:
	if sim == null:
		return

	if world_shows != null and stage_overlays != null:
		world_shows.ui_blocked = stage_overlays.is_title_open or stage_overlays.is_modal_open

	sim.step_frame(delta)

	if sfx != null and camera != null and not _smoke_mode:
		var jammed_cnt: int = 0
		for ag in sim.agents:
			if float(ag.get("stuckTimer", 0.0)) > 1.2:
				jammed_cnt += 1
		var is_paused: bool = (sim.speed_multiplier == 0) or (stage_overlays != null and stage_overlays.is_modal_open)
		sfx.update_world_ambience(delta, camera.zoom.x, jammed_cnt, sim.agents.size(), is_paused)

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
		if camera != null:
			sim.camera_meta = camera.export_camera_meta()
		sim.save_to_disk()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if sfx != null:
			sfx.shutdown()
		return
	if sim == null:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if camera != null:
			sim.camera_meta = camera.export_camera_meta()
		sim.save_to_disk()
		Engine.max_fps = 10
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Engine.max_fps = _target_fps
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if stage_overlays != null and stage_overlays.is_modal_open:
			stage_overlays.close_modal(true)
		elif stage_overlays != null and stage_overlays.is_title_open:
			if camera != null:
				sim.camera_meta = camera.export_camera_meta()
			sim.save_to_disk()
			if sfx != null:
				sfx.shutdown()
			get_tree().quit()
		elif hud != null and hud.current_drawer != "":
			hud.close_drawer()
		elif map_view != null and map_view.active_tool != "pan":
			hud._on_toolbar_pressed("pan")
		elif stage_overlays != null:
			stage_overlays.show_pause_menu()
		else:
			sim.save_to_disk()
			if sfx != null:
				sfx.shutdown()
			get_tree().quit()

func _reset_view_selection() -> void:
	map_view.selected_facility_id = ""
	map_view.selected_junction_id = ""
	map_view.selected_road_id = ""
	map_view.selected_route_id = ""
	map_view.selected_truck_id = ""
	map_view.editing_return_waypoints = false
	map_view.route_draft_from_id = ""
	if world_shows != null:
		world_shows.preview_offer_id = ""
	if hud != null:
		hud.follow_truck_id = ""

func _on_stage_map_load_requested(map_id: String, load_save: bool, city_code: String) -> void:
	if camera != null:
		sim.camera_meta = camera.export_camera_meta()
	sim.save_to_disk()
	if city_code != "":
		var dec: Dictionary = StageOverlays.decode_city_code(city_code, sim.maps_list.size())
		if bool(dec.get("valid", false)):
			sim.left_hand_traffic = bool(dec["lht"])
		sim.current_city_code = city_code
	sim.load_map(map_id, load_save and (not _smoke_mode))
	if city_code != "":
		sim.current_city_code = city_code
	_reset_view_selection()
	camera.focus_map(sim.map_def["initialView"], sim.map_def["boundsWorld"])
	if load_save and not sim.camera_meta.is_empty():
		camera.apply_camera_meta(sim.camera_meta)
	hud.refresh_top_bar()
	hud._refresh_goals_panel()
	hud.show_toast_banner("Peta dimuat: " + String(sim.map_def["name"]), 2.8)

func _on_map_selected(map_id: String) -> void:
	if stage_overlays != null and not _smoke_mode:
		hud.close_drawer()
		stage_overlays.play_loading_transition("Memuat %s..." % map_id, func():
			_perform_direct_map_switch(map_id)
		)
	else:
		_perform_direct_map_switch(map_id)

func _perform_direct_map_switch(map_id: String) -> void:
	if camera != null:
		sim.camera_meta = camera.export_camera_meta()
	sim.save_to_disk()
	sim.load_map(map_id, not _smoke_mode)
	_reset_view_selection()
	camera.focus_map(sim.map_def["initialView"], sim.map_def["boundsWorld"])
	if not _smoke_mode and not sim.camera_meta.is_empty():
		camera.apply_camera_meta(sim.camera_meta)
	hud.refresh_top_bar()
	hud._refresh_goals_panel()
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
	if stage_overlays != null and (stage_overlays.is_title_open or stage_overlays.is_modal_open):
		return

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
	# 0) Interactive `RegionGate` (`OPEN` / `GROW`) & in-world `RoadOfferSigns` (2-tap preview + purchase)!
	if world_shows != null and world_shows.try_handle_world_tap(world_pos):
		return

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
	world_shows.suppress_cinematics = true

	# =========================================================================
	# PILLAR 3A: Catalog, Starting Cash $500, $0 Close-Street, 60s Hold, 105s MarketDemand, 10-Level Boomtown
	# =========================================================================
	assert(GameCatalog.GOODS.size() == 44, "Must have all 44 Incremental Traffic commodities")
	assert(GameCatalog.STARTING_CASH == 500, "Authentic starting cash must be $500")
	assert(int(GameCatalog.INFRA_PRICES["close_street"]) == 0, "Closing a street must cost $0")
	assert(is_equal_approx(SimEngine.HOLD_REQUIRED_SEC, 60.0), "RegionGate hold must be 60.0s")
	assert(is_equal_approx(GameCatalog.MARKET_DEMAND_SPAN, 105.0), "MarketDemand kernel span must be 105.0s")
	assert(GameCatalog.MAX_BOOMTOWN_LEVELS == 10 and is_equal_approx(GameCatalog.BOOM_STEP_PER_MIN, 3.0), "Boomtown constants mismatch")
	var cat_errs: Array[String] = GameCatalog.validate_catalog()
	assert(cat_errs.is_empty(), "Catalog validation failed: " + ", ".join(cat_errs))

	# Validate `ShapeGlyphs` & `TruckModel`
	var glyph_batch := TriBatch2D.new()
	for gid in GameCatalog.GOODS.keys():
		var c_std: Color = ShapeGlyphs.color_of(String(gid), false)
		var c_cb: Color = ShapeGlyphs.color_of(String(gid), true)
		assert(c_std.a > 0.9 and c_cb.a > 0.9, "Invalid ShapeGlyphs color for " + String(gid))
		glyph_batch.clear()
		ShapeGlyphs.add_keylined(glyph_batch, String(gid), Vector2.ZERO, 16.0, ShapeGlyphs.truck_angle(String(gid)), Transform2D.IDENTITY, Color("1D2128"), false, true)
		assert(glyph_batch.verts.size() >= 3 and glyph_batch.indices.size() >= 3, "Empty keylined ShapeGlyphs for " + String(gid))
	assert(GameCatalog.TRUCK_ORDER == ["hauler", "freighter", "lowloader", "express", "bulker"], "Canonical TRUCK_ORDER mismatch")

	# Validate `CityCode` Base-32 encode/decode roundtrip (Pillar 4)
	var cc_enc: String = StageOverlays.encode_city_code(3, true, 0x12AB34)
	var cc_dec: Dictionary = StageOverlays.decode_city_code(cc_enc, 7)
	assert(bool(cc_dec.get("valid", false)) and int(cc_dec["mapIndex"]) == 3 and bool(cc_dec["lht"]) == true and int(cc_dec["seed"]) == 0x12AB34, "CityCode roundtrip failed: " + cc_enc)

	# =========================================================================
	# PILLAR 1 & 2 ACROSS ALL 7 MAPS: ParkingSpace aprons, Starter $500, Rail/Ship TransportSim
	# =========================================================================
	var total_trains: int = 0
	var total_crossings: int = 0
	var total_ships: int = 0
	var total_bridges: int = 0
	for m in sim.maps_list:
		var mid := String(m["id"])
		sim.load_map(mid, false)
		assert(sim.cash == 500, "Fresh map must start with $500 on " + mid)
		assert(not sim.depot.is_empty() and sim.junction_map.has(String(sim.depot["junctionId"])), "Missing starter Depot on " + mid)
		assert(sim.get_total_bays(sim.facilities[0]) == 1, "Initial Lv.0 facility must start with 1 bay on " + mid)
		for f_chk in sim.facilities:
			var plot: Dictionary = f_chk.get("parkingLot", {})
			assert(not plot.is_empty() and (plot.get("bays", []) as Array).size() == sim.get_total_bays(f_chk), "Facility missing ParkingSpace bays on " + mid)
		assert(sim.transport != null, "TransportSim missing on " + mid)
		var m_trains: int = sim.transport.rail_lines.size()
		var m_ships: int = 0
		for sch in sim.transport.ship_channels:
			m_ships += (sch.get("vessels", []) as Array).size()
		total_trains += m_trains
		total_crossings += sim.transport.level_crossings.size()
		total_ships += m_ships
		total_bridges += sim.transport.bascule_bridges.size()
		for _step in range(18):
			sim._step_fixed(SimEngine.SIM_DT)
		_smoke_summary.append("%s(trains=%d,xing=%d,ships=%d,brg=%d)" % [
			mid, m_trains, sim.transport.level_crossings.size(),
			m_ships, sim.transport.bascule_bridges.size()
		])
	assert(total_trains >= 3 and total_crossings >= 2, "TrainService & level crossings must be active across rail maps")
	assert(total_ships >= 3 and total_bridges >= 2, "ShipService & bascule bridges must be active across river/harbour maps")

	# =========================================================================
	# PILLAR 1, 3 & 4 DEEP ASSERTIONS ON KARESIDENAN MADIUN
	# =========================================================================
	sim.load_map("karisidenan_madiun", false)
	sim.cash = 500000
	for ri in [1, 2]:
		sim.regions[ri]["unlocked"] = true
	sim._rebuild_lookups()
	sim._refresh_network_geometry()
	sim.recompute_all_routes()

	# 1) 2-Slot Commodity Integer Cap (`15 / 2 == 7` units for size-2 goods, `15` for size-1) + 8-bay Garage portal check
	var fac0: Dictionary = sim.facilities[0]
	fac0["upgrades"]["buffer"] = 2 # 15 slots
	fac0["upgrades"]["wideGate"] = 1
	fac0["upgrades"]["bays"] = 7 # 8 total bays (4 outdoor + 4 indoor garage)
	ParkingLotSystem.build_facility_lot(sim, fac0)
	assert((fac0["parkingLot"]["bays"] as Array).size() == 8 and bool(fac0["parkingLot"]["hasGarage"]), "8-bay facility must expose 4 outdoor + 4 indoor garage stalls")
	fac0["upgrades"]["bays"] = 0
	ParkingLotSystem.build_facility_lot(sim, fac0)
	assert(sim.get_capacity_slots(fac0) == 15, "Buffer Lv.2 must be 15 slots")
	assert(int(GameCatalog.GOODS["fish"]["slots"]) == 2 and is_equal_approx(GameCatalog.lot_limit("dot"), 85.0) and GameCatalog.lot_limit("fish") < 30.0, "Good slots & Boomtown.lot_limit mismatch")
	assert(sim.get_good_unit_capacity(fac0, "fish") == 7, "15-slot buffer must cap 2-slot 'fish' at integer 7 units (14 slots)")
	assert(sim.get_good_unit_capacity(fac0, "dot") == 15, "15-slot buffer must allow 15 units of 1-slot 'dot'")

	# 2) Physical `ExitRoad` purchase (-$20,000, creates `isExitRoad` edge + `CityRebuild`) & 50% refund (+$10,000)
	var fac_exit: Dictionary = sim.facilities[0]
	for fc in sim.facilities:
		if sim.unlocked_regions.has(int(fc["regionIndex"])) and String(fc["kind"]) in ["supplier", "factory"] and not ParkingLotSystem.find_exit_road_candidate_target(sim, fc).is_empty():
			fac_exit = fc
			break
	var fid_exit := String(fac_exit["id"])
	var cash_before_exit: int = sim.cash
	assert(sim.buy_facility_upgrade(fid_exit, "exitRoad"), "Buying physical ExitRoad must succeed")
	assert(sim.cash == cash_before_exit - 20000, "ExitRoad must cost $20,000")
	var exit_eid := String(fac_exit.get("exitRoadId", ""))
	assert(exit_eid != "" and sim.road_map.has(exit_eid) and bool(sim.road_map[exit_eid].get("isExitRoad", false)), "Physical isExitRoad edge must exist in road_map")
	assert(bool(fac_exit["parkingLot"].get("hasExitRoad", false)), "ParkingSpace apron must enable hasExitRoad")
	assert(sim.sell_facility_exit_road(fid_exit), "Selling physical ExitRoad must succeed")
	assert(sim.cash == cash_before_exit - 10000, "Selling ExitRoad must refund 50% (+$10,000)")
	assert(not sim.road_map.has(exit_eid) and int(fac_exit["upgrades"]["exitRoad"]) == 0, "ExitRoad edge must be removed after sale")

	# 3) Per-direction lane pricing (`$1,250` one-dir vs `$2,500` both) & `1.2^n` RoadOffer inflation
	var test_rid := ""
	for r_cand in sim.roads:
		if not bool(r_cand.get("isExitRoad", false)) and int(r_cand["lanesForward"]) == 1 and int(r_cand["lanesBackward"]) == 1 and sim.unlocked_regions.has(int(r_cand["regionIndex"])):
			test_rid = String(r_cand["id"])
			break
	if test_rid != "":
		var exp_one_dir: int = sim.get_lane_step_price(sim.road_map[test_rid], 2)
		var c_pre_lane: int = sim.cash
		sim.modify_road_lanes(test_rid, 1, "forward")
		var one_dir_paid: int = c_pre_lane - sim.cash
		assert(one_dir_paid == exp_one_dir and exp_one_dir > 0, "Single-direction lane upgrade must charge 1x get_lane_step_price (%d vs %d)" % [one_dir_paid, exp_one_dir])

	if sim.road_offers.size() >= 2:
		var off_a: Dictionary = sim.road_offers[0]
		var off_b: Dictionary = sim.road_offers[1]
		off_a["regionIndex"] = 0
		off_b["regionIndex"] = 0
		var p_b_before: int = sim.get_road_offer_price(off_b)
		sim.purchase_road_offer(String(off_a["id"]))
		var p_b_after: int = sim.get_road_offer_price(off_b)
		assert(p_b_after > p_b_before, "RoadOffer price must inflate by 1.2^n after building a road (%d -> %d)" % [p_b_before, p_b_after])

	# 4) Trapezoidal 105s `MarketDemand` kernel weights (30s rise + 15s plateau + 60s fade = 60s area)
	assert(is_equal_approx(SimEngine.market_demand_kernel_weight(15.0), 0.5), "MarketDemand mid-rise (15s) weight must be 0.5")
	assert(is_equal_approx(SimEngine.market_demand_kernel_weight(37.5), 1.0), "MarketDemand plateau (37.5s) weight must be 1.0")
	assert(is_equal_approx(SimEngine.market_demand_kernel_weight(75.0), 0.5), "MarketDemand mid-fade (75s) weight must be 0.5")
	assert(is_equal_approx(SimEngine.market_demand_kernel_weight(108.0), 0.0), "MarketDemand >105s weight must be 0.0")

	# 5) Unit-by-unit partial unloading (`0.55s` intervals)
	if not sim.agents.is_empty() and not sim.routes.is_empty():
		var ag_u: Dictionary = sim.agents[0]
		var rt_u: Dictionary = sim.routes[0]
		for rt_cand in sim.routes:
			if String(rt_cand["id"]) == String(ag_u["routeId"]):
				rt_u = rt_cand
				break
		var to_fid := String(rt_u["toFacilityId"])
		var to_f: Dictionary = sim.facility_map[to_fid]
		to_f["inputBuffers"] = {}
		ag_u["state"] = "unloading"
		ag_u["atFacilityId"] = to_fid
		ag_u["bayIndex"] = 0
		ag_u["cargoGood"] = "dot"
		ag_u["cargoQty"] = 4
		ag_u["dwellSec"] = 0.0
		ag_u["unloadTick"] = 0.55
		sim._update_unloading_agent(ag_u, rt_u, 0.05)
		assert(int(ag_u["cargoQty"]) == 3 and String(ag_u["state"]) == "unloading", "Partial unloading must transfer 1 unit at a time (remaining=" + str(ag_u["cargoQty"]) + ")")

	# 6) Interactive `RegionGate` + 10-Level `Boomtown` + `CityBoom`
	var locked_idx: int = -1
	for ri_chk in range(sim.regions.size()):
		if not bool(sim.regions[ri_chk]["unlocked"]):
			locked_idx = ri_chk
			break
	if locked_idx >= 0:
		sim.regions[locked_idx]["holdSeconds"] = 60.0
		sim.regions[locked_idx]["goalReady"] = true
		var gst: Dictionary = sim.get_region_gate_state()
		assert(bool(gst.get("isReady", false)) and not bool(gst.get("isBoom", true)), "RegionGate must report ready for locked region")
		var unl_res: Dictionary = sim.trigger_ready_region_or_boom()
		assert(not unl_res.is_empty() and bool(sim.regions[locked_idx]["unlocked"]), "Region must be unlocked after tapping gate")

	for reg_all in sim.regions:
		reg_all["unlocked"] = true
	sim._rebuild_lookups()
	var pop_before: int = sim.town_population
	var boom_reg: Dictionary = sim.get_active_goal_region()
	boom_reg["holdSeconds"] = 60.0
	boom_reg["goalReady"] = true
	var boom_gst: Dictionary = sim.get_region_gate_state()
	assert(bool(boom_gst.get("isReady", false)) and bool(boom_gst.get("isBoom", false)), "Boomtown gate must report ready when all regions open")
	var boom_res: Dictionary = sim.trigger_ready_region_or_boom()
	assert(not boom_res.is_empty() and sim.boomtown_level == 1 and sim.town_population > pop_before, "Boomtown Lv.1 must increment level and population")

	# 7) Atomic Multi-Slot `RunSave` Schema `v: 4` roundtrip + 5-Channel Audio
	sfx.set_volumes(0.85, 0.90, 0.80, 0.70, 0.75)
	assert(is_equal_approx(sfx.ambience_volume, 0.70) and is_equal_approx(sfx.trucks_volume, 0.75), "5-channel audio volumes not stored")

	var prev_persist: bool = sim.disable_persistence
	sim.disable_persistence = false
	assert(sim.save_named_slot("Smoke Slot Alpha"), "save_named_slot must succeed")
	var slots: Array[Dictionary] = sim.list_save_slots()
	assert(not slots.is_empty() and int(slots[0].get("version", 0)) == 4, "RunSave slot must use schema v4")
	var slot_id := String(slots[0]["slotId"])
	assert(sim.rename_save_slot(slot_id, "Smoke Slot Renamed"), "rename_save_slot must succeed")
	var slots_after_rn: Array[Dictionary] = sim.list_save_slots()
	assert(not slots_after_rn.is_empty() and String(slots_after_rn[0].get("label", "")) == "Smoke Slot Renamed", "Renamed slot label must persist")
	var renamed_id := String(slots_after_rn[0]["slotId"])
	sim.cash = 123
	assert(sim.load_named_slot(renamed_id), "load_named_slot must succeed")
	assert(sim.cash != 123 and sim.boomtown_level == 1, "load_named_slot v4 must restore cash and boomtown_level")
	assert(sim.delete_save_slot(renamed_id), "delete_save_slot must clean up test slot")
	var legacy_auto := ProjectSettings.globalize_path("user://save_karisidenan_madiun.json")
	if FileAccess.file_exists("user://save_karisidenan_madiun.json"):
		DirAccess.remove_absolute(legacy_auto)
	sim.disable_persistence = prev_persist

	# =========================================================================
	# PREPARE VISUAL SHOWCASE SCENE FOR SCREENSHOT VERIFICATION
	# =========================================================================
	world_shows.suppress_cinematics = false
	sim.load_map("karisidenan_madiun", false)
	sim.cash = 48200
	sim.cash_history = [500, 4200, 9800, 16400, 23100, 29800, 35400, 40900, 44600, 48200]
	for m_ulk in GameCatalog.TRUCK_ORDER:
		sim.unlocked_licenses[m_ulk] = true
	for ri2 in [1, 2]:
		sim.regions[ri2]["unlocked"] = true
	sim._rebuild_lookups()
	sim._refresh_network_geometry()
	sim.recompute_all_routes()

	# Upgrade starter facilities including a physical ExitRoad so aprons, garages & rear exit slip roads are visible!
	for fi in range(mini(6, sim.facilities.size())):
		sim.facilities[fi]["upgrades"]["buffer"] = 2
		sim.facilities[fi]["upgrades"]["bays"] = 2
		sim.facilities[fi]["upgrades"]["wideGate"] = 1
	sim.cash += 30000
	sim.buy_facility_upgrade(String(sim.facilities[0]["id"]), "exitRoad")

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
	for _s in range(320):
		sim._step_fixed(SimEngine.SIM_DT)

	# Set Region 3 ready AFTER stepping so the interactive `RegionGate` ("OPEN") & HUD button shine in screenshot 02!
	if sim.regions.size() > 3:
		sim.regions[3]["holdSeconds"] = 60.0
		sim.regions[3]["goalReady"] = true

	camera.focus_map({"x": 225.0, "y": -265.0, "zoom": 1.32}, sim.map_def["boundsWorld"])
	hud._layout_responsive()
	hud.refresh_top_bar()
	hud._refresh_goals_panel()

	# Start smoke frame sequence on `TitleStage` + `NewGame` CityPreview subpanel!
	stage_overlays.show_title_stage()
	stage_overlays._populate_title_new_game_subpanel()

func _step_smoke() -> void:
	_smoke_frame += 1
	if _smoke_frame == 8:
		_save_shot_sync("01_title_stage_city_preview.png")
		stage_overlays.hide_title_stage()
		if not sim.road_offers.is_empty():
			world_shows.preview_offer_id = String(sim.road_offers[0]["id"])
		if sim.regions.size() > 3:
			sim.regions[3]["holdSeconds"] = 60.0
			sim.regions[3]["goalReady"] = true
		camera.focus_map({"x": 215.0, "y": -255.0, "zoom": 1.28}, sim.map_def["boundsWorld"])
		hud._layout_responsive()
		hud.refresh_top_bar()
		hud._refresh_goals_panel()
	elif _smoke_frame == 16:
		_save_shot_sync("02_gameplay_parking_offers_gate.png")
		world_shows.preview_offer_id = ""
		# Focus right onto an active train / level crossing or physical ParkingSpace apron + ExitRoad!
		var focus_pt: Vector2 = sim.facilities[0]["pos"]
		if sim.transport != null and not sim.transport.level_crossings.is_empty():
			var xing: Dictionary = sim.transport.level_crossings[0]
			xing["closed"] = true
			xing["down"] = 1.0
			xing["flashPhase"] = 1.2
			focus_pt = xing["pos"]
			var r_idx: int = int(xing.get("railIdx", 0))
			if r_idx >= 0 and r_idx < sim.transport.rail_lines.size():
				var rl_entry: Dictionary = sim.transport.rail_lines[r_idx]
				var tr_d: Dictionary = rl_entry["train"]
				tr_d["headS"] = clampf(float(xing["railS"]) + 10.0, 0.0, float(rl_entry["length"]))
				sim.transport._update_train_poses(sim, rl_entry)
		camera.focus_map({"x": focus_pt.x, "y": focus_pt.y, "zoom": 2.15}, sim.map_def["boundsWorld"])
	elif _smoke_frame == 24:
		_save_shot_sync("03_train_crossing_parking_closeup.png")
		# Trigger interactive RegionGate unlock -> `UnlockShow` confetti + `RegionOpenPopup`!
		if sim.regions.size() > 3:
			sim.regions[3]["holdSeconds"] = 60.0
			sim.regions[3]["goalReady"] = true
		var u_info: Dictionary = sim.trigger_ready_region_or_boom()
		if not u_info.is_empty():
			stage_overlays.show_region_open_popup(u_info)
	elif _smoke_frame == 32:
		_save_shot_sync("04_region_open_popup_confetti.png")
		stage_overlays.close_modal(true)
		camera.cancel_cinematic_tour()
		stage_overlays.show_pause_menu()
	elif _smoke_frame == 40:
		_save_shot_sync("05_pause_menu_citycode.png")
		stage_overlays.close_modal(true)
		DisplayServer.window_set_size(Vector2i(540, 1080))
		get_tree().root.size = Vector2i(540, 1080)
		_perform_direct_map_switch("kota_madiun")
		for _s3 in range(140):
			sim._step_fixed(SimEngine.SIM_DT)
		hud._layout_responsive()
		hud.refresh_top_bar()
		hud._refresh_goals_panel()
	elif _smoke_frame == 50:
		_save_shot_sync("06_portrait_kota_madiun.png")
		if sfx != null:
			sfx.shutdown()
	elif _smoke_frame == 52:
		print("SMOKE_TEST_OK goods=%d trucks=%d maps=%d details=%s" % [
			GameCatalog.GOODS.size(), GameCatalog.TRUCK_ORDER.size(), _smoke_summary.size(), "; ".join(_smoke_summary)
		])
		get_tree().quit(0)

func _save_shot_sync(filename: String) -> void:
	if _smoke_dir == "":
		return
	var vp_tex: ViewportTexture = get_viewport().get_texture()
	if vp_tex == null:
		return
	var img: Image = vp_tex.get_image()
	if img != null and not img.is_empty():
		img.save_png(_smoke_dir.path_join(filename))
