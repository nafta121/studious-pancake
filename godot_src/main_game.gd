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

	map_view = MapView25D.new()
	add_child(map_view)
	map_view.setup(sim, camera)

	hud = AndroidHUD.new()
	add_child(hud)
	hud.setup(sim, map_view)
	hud.map_selected.connect(_on_map_selected)
	hud.perf_preset_changed.connect(_on_perf_preset_changed)
	hud.theme_toggled.connect(_on_theme_toggled)
	hud.focus_world_requested.connect(func(p: Vector2): camera.pan_to_world(p, 0.85))

	if _smoke_mode:
		_prepare_smoke_test()

func _process(delta: float) -> void:
	if sim == null:
		return
	sim.step_frame(delta)

	if _smoke_mode:
		_step_smoke()
		return

	_autosave_timer += delta
	if _autosave_timer >= 25.0:
		_autosave_timer = 0.0
		sim.save_to_disk()

func _notification(what: int) -> void:
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
			get_tree().quit()

func _on_map_selected(map_id: String) -> void:
	sim.save_to_disk()
	sim.load_map(map_id, not _smoke_mode)
	map_view.selected_facility_id = ""
	map_view.selected_junction_id = ""
	map_view.selected_road_id = ""
	map_view.selected_route_id = ""
	map_view.route_draft_from_id = ""
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

	if tool in ["lanes_add", "lanes_remove", "one_way", "close_street"]:
		var r_hit: Dictionary = RoadGeom.hit_test_road(sim.roads, sim.unlocked_regions, world_pos, road_r, false)
		if r_hit.is_empty():
			hud.show_toast_banner("Ketuk ruas jalan raya yang terbuka!", 2.0)
			return
		var rid := String(r_hit["id"])
		map_view.selected_road_id = rid
		var res_msg: String = ""
		if tool == "lanes_add":
			res_msg = sim.modify_road_lanes(rid, 1)
		elif tool == "lanes_remove":
			res_msg = sim.modify_road_lanes(rid, -1)
		elif tool == "one_way":
			res_msg = sim.cycle_road_one_way(rid)
		elif tool == "close_street":
			res_msg = sim.toggle_close_street(rid)
		if res_msg != "":
			hud.show_toast_banner(res_msg, 2.5)
		return

	# Default 'pan' / inspect mode: check Facility -> Junction -> Road
	var fac: Dictionary = RoadGeom.hit_test_facility(sim.facilities, sim.unlocked_regions, world_pos, fac_r)
	if not fac.is_empty():
		sfx.tap(10)
		map_view.selected_facility_id = String(fac["id"])
		map_view.selected_junction_id = ""
		map_view.selected_road_id = ""
		hud.open_drawer("facility")
		return

	var junc: Dictionary = RoadGeom.hit_test_junction(sim.junctions, sim.unlocked_regions, world_pos, junc_r)
	if not junc.is_empty():
		var j_id := String(junc["id"])
		if hud.current_drawer == "routes" and map_view.selected_route_id != "":
			sim.toggle_route_waypoint(map_view.selected_route_id, j_id)
			hud._populate_drawer()
			hud.show_toast_banner("Waypoint diperbarui pada " + String(junc.get("name", "simpang")), 2.2)
			return
		sfx.tap(10)
		map_view.selected_junction_id = j_id
		map_view.selected_facility_id = ""
		map_view.selected_road_id = ""
		hud.open_drawer("junction")
		return

	var rd: Dictionary = RoadGeom.hit_test_road(sim.roads, sim.unlocked_regions, world_pos, road_r, false)
	if not rd.is_empty():
		sfx.tap(10)
		map_view.selected_road_id = String(rd["id"])
		map_view.selected_facility_id = ""
		map_view.selected_junction_id = ""
		hud.open_drawer("road")
		return

	map_view.selected_facility_id = ""
	map_view.selected_junction_id = ""
	map_view.selected_road_id = ""
	if hud.current_drawer in ["facility", "junction", "road"]:
		hud.close_drawer()

func _prepare_smoke_test() -> void:
	if _smoke_dir != "":
		DirAccess.make_dir_recursive_absolute(_smoke_dir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_tree().root.size = Vector2i(1280, 720)

	for m in sim.maps_list:
		var mid := String(m["id"])
		sim.load_map(mid, false)
		for _step in range(15):
			sim._step_fixed(SimEngine.SIM_DT)
		_smoke_summary.append("%s(regs=%d,roads=%d,facs=%d,trucks=%d)" % [
			mid, sim.regions.size(), sim.roads.size(), sim.facilities.size(), sim.agents.size()
		])

	sim.load_map("karisidenan_madiun", false)
	sim.cash = 48200
	sim.cash_history = [32400, 33800, 35100, 36900, 38200, 40500, 41900, 44100, 46300, 48200]
	for ri in [1, 2]:
		sim.regions[ri]["unlocked"] = true
	sim._rebuild_lookups()
	sim._refresh_network_geometry()
	sim.recompute_all_routes()
	if sim.facilities.size() >= 10:
		var r_extra: Dictionary = sim.create_route(String(sim.facilities[2]["id"]), String(sim.facilities[4]["id"]), "any", true)
		if not r_extra.is_empty():
			sim.add_truck_to_route(String(r_extra["id"]), false)
			sim.add_truck_to_route(String(r_extra["id"]), false)
	sim.map_static_dirty.emit()
	for _s in range(280):
		sim._step_fixed(SimEngine.SIM_DT)
	# Seed a fresh delivery popup so the authentic dark/gold +$100 coin pill is visible in shot 1!
	if sim.facilities.size() >= 4:
		sim.spawn_toast(sim.facilities[3]["pos"] + Vector2(0, -18), "+$100", Color("FFD54A"))
	camera.focus_map({"x": 225.0, "y": -265.0, "zoom": 1.32}, sim.map_def["boundsWorld"])
	hud._layout_responsive()
	hud.refresh_top_bar()
	hud._refresh_goals_panel()

func _step_smoke() -> void:
	_smoke_frame += 1
	if _smoke_frame == 8:
		_save_shot_sync("godot_android_landscape_karisidenan.png")
		# Select a multi-input Factory with outgoing route to show In->Ring->Out + Upgrades + Swap All!
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
		hud.open_drawer("routes")
	elif _smoke_frame == 24:
		_save_shot_sync("godot_android_overview_routes.png")
		hud.close_drawer()
		sim.night_mode = true
		sim.day_clock_01 = 22.0 / 24.0
		map_view._night_blend = 1.0
		hud.dark_mode = true
		hud._apply_styles()
		map_view.set_theme_dark(true)
		hud._toggle_overlay_mode("flow")
	elif _smoke_frame == 32:
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
	elif _smoke_frame == 40:
		_save_shot_sync("godot_android_pacitan_harbour.png")
		# Close-up showcase on Kota Madiun (1280x720): swept Bezier junctions, 2-lane & 1-lane roundabouts,
		# Kali Madiun bridges, lane markings/arrows, yield shark-teeth, corner signals & lane-connector bands!
		sim.load_map("kota_madiun", false)
		sim.cash = 65000
		for ri2 in [1, 2]:
			if ri2 < sim.regions.size():
				sim.regions[ri2]["unlocked"] = true
		sim._rebuild_lookups()
		if sim.junction_map.has("km_sleko"):
			sim.junction_map["km_sleko"]["control"] = "roundabout2"
		sim._refresh_network_geometry()
		sim.recompute_all_routes()
		if sim.facilities.size() >= 7:
			var r_km: Dictionary = sim.create_route(String(sim.facilities[3]["id"]), String(sim.facilities[5]["id"]), "any", true)
			if not r_km.is_empty():
				sim.add_truck_to_route(String(r_km["id"]), false)
				sim.add_truck_to_route(String(r_km["id"]), false)
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
	elif _smoke_frame == 48:
		_save_shot_sync("godot_android_junction_roundabout_closeup.png")
		map_view.selected_junction_id = ""
		DisplayServer.window_set_size(Vector2i(480, 960))
		get_tree().root.size = Vector2i(480, 960)
		_on_map_selected("kota_madiun")
		for _s3 in range(160):
			sim._step_fixed(SimEngine.SIM_DT)
		hud._layout_responsive()
		hud.open_drawer("maps")
	elif _smoke_frame == 58:
		_save_shot_sync("godot_android_portrait_kota_madiun.png")
		print("SMOKE_TEST_OK maps=%d details=%s" % [_smoke_summary.size(), "; ".join(_smoke_summary)])
		get_tree().quit(0)

func _save_shot_sync(filename: String) -> void:
	if _smoke_dir == "":
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(_smoke_dir.path_join(filename))
