class_name MapView25D
extends Node2D

## Authentic Incremental Traffic 2.5D cartographic world renderer for Karesidenan Madiun.
## Directly integrates original Incremental Traffic shaders (`city_building.gdshader` +
## `city_reveal.gdshaderinc`, `city_shadow.gdshader`, `cloud_puff.gdshader`,
## `rule_hints.gdshader`, and `water_ripples.gdshader`) via GPU `ArrayMesh` (`CUSTOM0`),
## Update 1.10 overlay map wash, Hide Flyovers, Colour-blind palette, Station/Harbour
## yard piles, and articulated TruckView (Express shrinking bonus bar, brake lights,
## turn blinkers, and multi-slot cargo glyphs) at locked 60-120 FPS on Android.

const COL_BG := Color("F2F0E5")
const COL_ROAD := Color("3C3F4A")
const COL_LANE_MARK := Color("F2F0E5")
const COL_SIDEWALK := Color("E2DED2")
const COL_CURB := Color("A9A59B")
const COL_WATER := Color("A9CDD8")
const COL_WATER_DEEP := Color("86B5C6")
const COL_GRASS := Color("C9D8A6")
const COL_TREE_A := Color("6F9A52")
const COL_TREE_B := Color("5F9B52")
const COL_TREE_AUTUMN := Color("D99B4E")
const COL_TREE_RED := Color("C76B4B")
const COL_SHADOW := Color(0.21, 0.24, 0.33, 0.18)

# Authentic TruckView v1.4.1 palette (`gd_src/content/vehicles/truck_view.gd`)
const TRUCK_INK := Color("1D2128")
const TRUCK_TILE := Color("ECEEEA")
const TRUCK_PAPER := Color("F6F5EF")
const TRUCK_GLASS := Color("2B3442")
const TRUCK_CHROME := Color("B9C0C8")
const TRUCK_BRAKE_ON := Color("FF2B3B")
const TRUCK_BRAKE_OFF := Color("7A2C33")
const TRUCK_BLINKER := Color("FFE14B")
const TRUCK_HEADLAMP := Color("E9E3C8")
const TRUCK_HOPPER_WELL := Color("B4B9B3")

var sim: SimEngine
var camera: Camera2D

var overlay_mode: String = "none" # none | routes | traffic | flow | buildings | demand
var dark_theme: bool = false
var perf_preset: String = "balanced" # battery | balanced | ultra
var hide_flyovers: bool = false
var colorblind_mode: bool = false
var cloud_shadows_enabled: bool = true

var selected_facility_id: String = ""
var selected_junction_id: String = ""
var selected_road_id: String = ""
var selected_route_id: String = ""
var selected_truck_id: String = ""
var editing_return_waypoints: bool = false
var route_draft_from_id: String = ""
var active_tool: String = "pan"
var hidden_route_ids: Dictionary = {} # route_id -> true (for OverlayBar Network filter)
var interactive_gate_handled: bool = false

var _terrain_node: _StaticBatchLayer
var _water_node: _StaticBatchLayer
var _road_node: _StaticBatchLayer
var _shadow_node: _MeshBatchLayer
var _building_node: _MeshBatchLayer
var _cloud_veil_node: _StaticBatchLayer
var _cloud_puff_node: _MeshBatchLayer
var _rule_hint_node: _MeshBatchLayer
var _underlay_node: _WorldUnderlayDrawer
var _truck_ghost_node: _StaticBatchLayer
var _truck_node: _StaticBatchLayer
var _dynamic_node: _DynamicWorldDrawer

var _ground_mat: ShaderMaterial
var _ground_noise_tex: ImageTexture
var _water_mat: ShaderMaterial
var _shadow_mat: ShaderMaterial
var _building_mat: ShaderMaterial
var _cloud_puff_mat: ShaderMaterial
var _rule_hint_mat: ShaderMaterial
var _truck_mat: ShaderMaterial
var _truck_ghost_mat: ShaderMaterial
var _ghost_flat_mat: ShaderMaterial

var _terrain_batch := TriBatch2D.new()
var _water_batch := TriBatch2D.new()
var _road_batch := TriBatch2D.new()
var _shadow_batch := TriBatch2D.new()
var _building_batch := TriBatch2D.new()
var _cloud_veil_batch := TriBatch2D.new()
var _cloud_puff_batch := TriBatch2D.new()
var _rule_hint_batch := TriBatch2D.new()
var _truck_ghost_batch := TriBatch2D.new()
var _truck_batch := TriBatch2D.new()

var _shadow_mesh := ArrayMesh.new()
var _building_mesh := ArrayMesh.new()
var _cloud_puff_mesh := ArrayMesh.new()
var _rule_hint_mesh := ArrayMesh.new()

var _night_blend: float = 0.0
var _cloud_clock: float = 0.0
var _static_dirty: bool = true
var _last_hint_sig: String = "__init__"
var _ui_font: Font

func setup(sim_engine: SimEngine, cam: Camera2D) -> void:
	sim = sim_engine
	camera = cam
	if not sim.map_static_dirty.is_connected(_on_static_dirty):
		sim.map_static_dirty.connect(_on_static_dirty)
	if ResourceLoader.exists("res://gui/theme_studies/fonts/Jost-Variable.ttf"):
		_ui_font = load("res://gui/theme_studies/fonts/Jost-Variable.ttf") as Font
	else:
		_ui_font = ThemeDB.fallback_font

	_terrain_node = _StaticBatchLayer.new()
	_terrain_node.batch = _terrain_batch

	_water_node = _StaticBatchLayer.new()
	_water_node.batch = _water_batch

	_road_node = _StaticBatchLayer.new()
	_road_node.batch = _road_batch

	_shadow_node = _MeshBatchLayer.new()
	_shadow_node.mesh = _shadow_mesh

	_building_node = _MeshBatchLayer.new()
	_building_node.mesh = _building_mesh

	_cloud_veil_node = _StaticBatchLayer.new()
	_cloud_veil_node.batch = _cloud_veil_batch

	_cloud_puff_node = _MeshBatchLayer.new()
	_cloud_puff_node.mesh = _cloud_puff_mesh

	_rule_hint_node = _MeshBatchLayer.new()
	_rule_hint_node.mesh = _rule_hint_mesh

	_underlay_node = _WorldUnderlayDrawer.new()
	_underlay_node.owner_view = self

	_truck_ghost_node = _StaticBatchLayer.new()
	_truck_ghost_node.batch = _truck_ghost_batch

	_truck_node = _StaticBatchLayer.new()
	_truck_node.batch = _truck_batch

	_dynamic_node = _DynamicWorldDrawer.new()
	_dynamic_node.owner_view = self

	var fnl := FastNoiseLite.new()
	fnl.seed = 47214
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.032
	fnl.fractal_octaves = 3
	var n_img: Image = fnl.get_seamless_image(128, 128)
	_ground_noise_tex = ImageTexture.create_from_image(n_img)

	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://shaders/road_verge.gdshader") as Shader
	_ground_mat.set_shader_parameter("noise_tex", _ground_noise_tex)
	_ground_mat.set_shader_parameter("scale", 520.0)
	_ground_mat.set_shader_parameter("strength", 1.0)
	_terrain_node.material = _ground_mat

	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/water_ripples.gdshader") as Shader
	_water_node.material = _water_mat

	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = load("res://shaders/city_shadow.gdshader") as Shader
	_shadow_node.material = _shadow_mat

	_building_mat = ShaderMaterial.new()
	_building_mat.shader = load("res://shaders/city_building.gdshader") as Shader
	_building_node.material = _building_mat

	_cloud_puff_mat = ShaderMaterial.new()
	_cloud_puff_mat.shader = load("res://shaders/cloud_puff.gdshader") as Shader
	_cloud_puff_node.material = _cloud_puff_mat

	_rule_hint_mat = ShaderMaterial.new()
	_rule_hint_mat.shader = load("res://shaders/rule_hints.gdshader") as Shader
	_rule_hint_node.material = _rule_hint_mat

	var tp_shader := load("res://shaders/truck_part.gdshader") as Shader
	_truck_mat = ShaderMaterial.new()
	_truck_mat.shader = tp_shader
	_truck_mat.set_shader_parameter("ghost", false)
	_truck_node.material = _truck_mat

	_truck_ghost_mat = ShaderMaterial.new()
	_truck_ghost_mat.shader = tp_shader
	_truck_ghost_mat.set_shader_parameter("ghost", true)
	_truck_ghost_node.material = _truck_ghost_mat

	_ghost_flat_mat = ShaderMaterial.new()
	_ghost_flat_mat.shader = load("res://shaders/truck_ghost.gdshader") as Shader

	add_child(_terrain_node)
	add_child(_water_node)
	add_child(_road_node)
	add_child(_shadow_node)
	add_child(_building_node)
	add_child(_cloud_veil_node)
	add_child(_cloud_puff_node)
	add_child(_rule_hint_node)
	add_child(_underlay_node)
	add_child(_truck_ghost_node)
	add_child(_truck_node)
	add_child(_dynamic_node)

	_static_dirty = true
	_last_hint_sig = "__init__"

func _exit_tree() -> void:
	if sim != null and sim.map_static_dirty.is_connected(_on_static_dirty):
		sim.map_static_dirty.disconnect(_on_static_dirty)
	for n in [_terrain_node, _water_node, _shadow_node, _building_node, _cloud_puff_node, _rule_hint_node, _truck_ghost_node, _truck_node]:
		if n != null:
			n.material = null
	for m in [_shadow_mesh, _building_mesh, _cloud_puff_mesh, _rule_hint_mesh]:
		if m != null:
			m.clear_surfaces()
	if _shadow_node != null:
		_shadow_node.mesh = null
	if _building_node != null:
		_building_node.mesh = null
	if _cloud_puff_node != null:
		_cloud_puff_node.mesh = null
	if _rule_hint_node != null:
		_rule_hint_node.mesh = null
	_ground_mat = null
	_ground_noise_tex = null
	_water_mat = null
	_shadow_mat = null
	_building_mat = null
	_cloud_puff_mat = null
	_rule_hint_mat = null
	_truck_mat = null
	_truck_ghost_mat = null
	_ghost_flat_mat = null
	_ui_font = null

func _on_static_dirty() -> void:
	_static_dirty = true

func set_theme_dark(is_dark: bool) -> void:
	if dark_theme != is_dark:
		dark_theme = is_dark
		_static_dirty = true

func set_perf_preset(preset: String) -> void:
	if perf_preset != preset:
		perf_preset = preset
		_static_dirty = true

func set_hide_flyovers(hide_on: bool) -> void:
	if hide_flyovers != hide_on:
		hide_flyovers = hide_on
		_static_dirty = true

func set_colorblind_mode(cb_on: bool) -> void:
	colorblind_mode = cb_on

func set_cloud_shadows(clouds_on: bool) -> void:
	cloud_shadows_enabled = clouds_on
	if _cloud_puff_node != null:
		_cloud_puff_node.visible = clouds_on and perf_preset != "battery"

func _process(delta: float) -> void:
	if sim == null or camera == null:
		return
	if _static_dirty:
		_rebuild_static_batches()
		_static_dirty = false
		_last_hint_sig = "__dirty__"

	var sel_rt_wp_sig := ""
	if selected_route_id != "":
		var srt_chk: Dictionary = sim.get_route(selected_route_id)
		if not srt_chk.is_empty():
			sel_rt_wp_sig = "%d:%d:%d" % [
				(srt_chk.get("waypoints", []) as Array).size(),
				(srt_chk.get("waypointsBack", []) as Array).size(),
				1 if bool(srt_chk.get("sameWayBack", true)) else 0
			]
	var hint_sig := "%s|%s|%s|%s" % [active_tool, selected_route_id, route_draft_from_id, sel_rt_wp_sig]
	if hint_sig != _last_hint_sig:
		_last_hint_sig = hint_sig
		_rebuild_rule_hints_batch()

	var target_night: float = 1.0 if sim.night_mode else 0.0
	_night_blend = lerpf(_night_blend, target_night, minf(1.0, delta * 4.5))
	_cloud_clock += delta * (0.45 if perf_preset == "battery" else 1.0)

	# Authentic directional sun vector & shadow offset driven by day_clock_01
	var day_ang: float = (sim.day_clock_01 - 0.25) * TAU
	var sun_dir := Vector2(cos(day_ang), -0.58 - 0.35 * sin(day_ang)).normalized()
	var sunlit: float = clampf(1.0 - _night_blend * 0.88, 0.12, 1.0)
	var shadow_len: float = lerpf(0.30, 0.14, _night_blend)
	var sun_offset: Vector2 = -sun_dir * shadow_len

	if _building_mat != null:
		_building_mat.set_shader_parameter("cam_center", camera.global_position)
		_building_mat.set_shader_parameter("cam_zoom", camera.zoom.x)
		_building_mat.set_shader_parameter("lean_scale", 0.00032 if perf_preset == "battery" else 0.00052)
		_building_mat.set_shader_parameter("sun_dir", sun_dir)
		_building_mat.set_shader_parameter("sunlit", sunlit)
		_building_mat.set_shader_parameter("night", _night_blend)
		_building_mat.set_shader_parameter("reveal_clock", sim.real_time_sec)
		_building_mat.set_shader_parameter("grow_clock", sim.real_time_sec)

	if _shadow_mat != null:
		_shadow_mat.set_shader_parameter("sun_offset", sun_offset)
		_shadow_mat.set_shader_parameter("reveal_clock", sim.real_time_sec)
		_shadow_mat.set_shader_parameter("grow_clock", sim.real_time_sec)

	if _cloud_puff_mat != null:
		_cloud_puff_mat.set_shader_parameter("clock", _cloud_clock)

	if _ground_mat != null:
		var g_str: float = 0.0 if (dark_theme or perf_preset == "battery") else clampf(1.0 - _night_blend * 0.92, 0.0, 1.0)
		_ground_mat.set_shader_parameter("strength", g_str)

	if _water_mat != null:
		_water_mat.set_shader_parameter("night_blend", _night_blend)
		_water_mat.set_shader_parameter("shimmer_amp", 0.018 if perf_preset == "battery" else 0.058)

	var bg_day := Color("20242C") if dark_theme else COL_BG
	var bg_night := Color("121620")
	RenderingServer.set_default_clear_color(bg_day.lerp(bg_night, _night_blend))

	_rebuild_trucks_batches()
	_underlay_node.queue_redraw()
	_truck_ghost_node.queue_redraw()
	_truck_node.queue_redraw()
	_dynamic_node.queue_redraw()

func get_world_frustum() -> Rect2:
	var vp_size: Vector2 = get_viewport_rect().size
	var half_world: Vector2 = (vp_size * 0.5) / maxf(0.15, camera.zoom.x)
	var margin := Vector2(110.0, 110.0)
	return Rect2(camera.global_position - half_world - margin, (half_world + margin) * 2.0)

func _rebuild_rule_hints_batch() -> void:
	_rule_hint_batch.clear()
	if sim == null or _rule_hint_node == null:
		return

	var tool_s := active_tool
	var over_col := Color(0.18, 0.52, 0.96, 1.0)
	if tool_s == "route":
		over_col = Color(0.24, 0.68, 0.40, 1.0)
	elif tool_s == "close_street":
		over_col = Color(0.82, 0.24, 0.26, 1.0)

	if _rule_hint_mat != null:
		_rule_hint_mat.set_shader_parameter("over_color", over_col)

	if tool_s in ["yield", "roundabout", "lights"]:
		for j_h in sim.junctions:
			if not sim.unlocked_regions.has(int(j_h["regionIndex"])):
				continue
			var arms_h: Array = (j_h.get("geom", {}) as Dictionary).get("arms", [])
			if arms_h.size() < 3:
				continue
			var r_world: float = maxf(14.0, float((j_h.get("geom", {}) as Dictionary).get("r_outer", 11.0)) + 3.5)
			_rule_hint_batch.add_rule_hint_ring(j_h["pos"], r_world, 28, 0.0)
	elif tool_s in ["lanes_add", "lanes_remove", "one_way", "close_street", "pocket", "turn_arrows"]:
		for r_h in sim.roads:
			if not bool(r_h["isBuilt"]) or not sim.unlocked_regions.has(int(r_h["regionIndex"])):
				continue
			var rlen: float = float(r_h["lengthPx"])
			var s0: float = float(r_h.get("trimStart", 0.0)) + 2.0
			var s1: float = rlen - float(r_h.get("trimEnd", 0.0)) - 2.0
			if s1 - s0 >= 8.0:
				var sub_pts: PackedVector2Array = RoadGeom.slice_polyline(r_h["pts"], r_h["cum_len"], s0, s1)
				_rule_hint_batch.add_rule_hint_dash_polyline(sub_pts, 0.0)
	elif tool_s == "route":
		for f_h in sim.facilities:
			if not sim.unlocked_regions.has(int(f_h["regionIndex"])):
				continue
			if route_draft_from_id == "":
				if f_h["outputGood"] != null:
					_rule_hint_batch.add_rule_hint_sign_ring(f_h["pos"], 24, 0.0)
			elif String(f_h["id"]) != route_draft_from_id:
				_rule_hint_batch.add_rule_hint_sign_ring(f_h["pos"], 24, 0.0)

	if selected_route_id != "":
		var sel_rt: Dictionary = sim.get_route(selected_route_id)
		if not sel_rt.is_empty():
			for wp in sel_rt["waypoints"]:
				if sim.junction_map.has(String(wp)):
					_rule_hint_batch.add_rule_hint_dot(sim.junction_map[String(wp)]["pos"], 0.0)
			if not bool(sel_rt.get("sameWayBack", true)):
				for wp_b in sel_rt.get("waypointsBack", []):
					if sim.junction_map.has(String(wp_b)):
						_rule_hint_batch.add_rule_hint_dot(sim.junction_map[String(wp_b)]["pos"], 0.35)

	_rule_hint_batch.upload_to_mesh(_rule_hint_mesh)
	_rule_hint_node.visible = not _rule_hint_batch.is_empty()
	_rule_hint_node.queue_redraw()

func _compute_region_reveal_c0(reg_idx: int, world_pos: Vector2) -> Color:
	if reg_idx <= 0 or reg_idx >= sim.regions.size():
		return Color(0.0, world_pos.x, world_pos.y, 0.0)
	var reg: Dictionary = sim.regions[reg_idx]
	if not bool(reg["unlocked"]):
		return Color(0.0, world_pos.x, world_pos.y, 0.0)
	var unl_t: float = float(reg.get("unlockedAtRealSec", 0.0))
	if unl_t <= 0.001:
		return Color(0.0, world_pos.x, world_pos.y, 0.0)
	var rc: Vector2 = reg.get("center_vec", world_pos)
	var dist_delay: float = clampf(world_pos.distance_to(rc) * 0.0016, 0.0, 0.55)
	return Color(unl_t + dist_delay, world_pos.x, world_pos.y, 1.0)

func _rebuild_static_batches() -> void:
	_terrain_batch.clear()
	_water_batch.clear()
	_road_batch.clear()
	_shadow_batch.clear()
	_building_batch.clear()
	_cloud_veil_batch.clear()
	_cloud_puff_batch.clear()

	var is_dark: bool = dark_theme or sim.night_mode
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sim.current_map_id) ^ 0x51A7E2

	# 1. Region polygons (#F2F0E5 authentic warm parchment in day, subtle region borders)
	for reg in sim.regions:
		var unlocked: bool = bool(reg["unlocked"])
		var tint: Color = GameCatalog.parse_color(String(reg["fillColor"]), COL_BG)
		var base_col: Color = COL_BG.lerp(tint, 0.22 if unlocked else 0.08)
		if is_dark:
			base_col = Color("1E222B").lerp(tint.darkened(0.68), 0.20)
		var border_col := Color(0.22, 0.24, 0.29, 0.16 if unlocked else 0.28)
		if is_dark:
			border_col = Color(0.75, 0.78, 0.85, 0.14 if unlocked else 0.24)

		for pv in reg["poly_vecs"]:
			_terrain_batch.add_polygon_safe(pv, base_col)
			_terrain_batch.add_dashed_polyline(pv, 1.8 if unlocked else 2.2, border_col, 9.0, 7.0)

	# 2. Striped Agricultural Fields & Forest / Park Patches
	var p_idx: int = 0
	for p in sim.patches:
		p_idx += 1
		var reg_idx: int = int(p["regionIndex"])
		var unl: bool = sim.unlocked_regions.has(reg_idx)
		var kind_s := String(p["kind"])
		var pc := Vector2(float(p["x"]), float(p["y"]))
		var pw: float = float(p["w"])
		var ph: float = float(p["h"])
		var pang: float = float(p["angle"])

		var p_col := COL_GRASS
		if kind_s == "sawah" or (p_idx % 3 == 0 and kind_s != "jati"):
			p_col = Color("B8A47A") if (p_idx % 2 == 0) else Color("C9D8A6")
		elif kind_s == "jati":
			p_col = Color("DCE2C8")
		elif kind_s == "karst":
			p_col = Color("DFDACB")
		elif kind_s == "alun_alun":
			p_col = Color("C3D69B")
		if is_dark:
			p_col = p_col.darkened(0.64)
		p_col.a = 0.78 if unl else 0.30
		_terrain_batch.add_rect_rot(pc, pw, ph, pang, p_col)

		if unl and kind_s != "jati" and pw >= 28.0 and ph >= 18.0:
			var ux := Vector2(cos(pang), sin(pang))
			var uy := Vector2(-sin(pang), cos(pang))
			var stripe_col := Color(0.95, 0.94, 0.90, 0.55) if not is_dark else Color(0.28, 0.32, 0.38, 0.35)
			var step_y: float = 8.5
			var y_cur: float = -ph * 0.42
			while y_cur <= ph * 0.42:
				var a_pt: Vector2 = pc - ux * (pw * 0.46) + uy * y_cur
				var b_pt: Vector2 = pc + ux * (pw * 0.46) + uy * y_cur
				_terrain_batch.add_polyline(PackedVector2Array([a_pt, b_pt]), 1.1, stripe_col, false, false)
				y_cur += step_y

		if perf_preset != "battery" and (kind_s == "jati" or kind_s == "alun_alun" or p_idx % 2 == 1):
			var tree_count: int = clampi(int((pw * ph) / 210.0), 4, 26)
			if not unl:
				tree_count = maxi(2, tree_count / 2)
			var ux_t := Vector2(cos(pang), sin(pang))
			var uy_t := Vector2(-sin(pang), cos(pang))
			for _ti in range(tree_count):
				var tx: float = rng.randf_range(-pw * 0.48, pw * 0.48)
				var ty: float = rng.randf_range(-ph * 0.48, ph * 0.48)
				var tp: Vector2 = pc + ux_t * tx + uy_t * ty
				var tr_r: float = rng.randf_range(2.3, 4.2)
				var roll: float = rng.randf()
				var tcol: Color = COL_TREE_A
				if roll > 0.84:
					tcol = COL_TREE_RED
				elif roll > 0.66:
					tcol = COL_TREE_AUTUMN
				elif roll > 0.35:
					tcol = COL_TREE_B
				if is_dark:
					tcol = tcol.darkened(0.55)
				if not unl:
					tcol.a = 0.38
				else:
					_terrain_batch.add_circle(tp + Vector2(1.1, 1.4), tr_r, COL_SHADOW, 8)
				_terrain_batch.add_circle(tp, tr_r, tcol, 10)

	# 3. Water bodies & Rivers (#A9CDD8 / #86B5C6 with soft #DEDBCF banks + ripple dashes)
	var water_col := Color("3A6073") if is_dark else COL_WATER
	var deep_col := Color("2C4B5C") if is_dark else COL_WATER_DEEP
	var bank_col := Color("2A333D") if is_dark else Color("DED8C8")
	var ripple_col := Color(1.0, 1.0, 1.0, 0.28 if not is_dark else 0.12)
	for wb in sim.water_bodies:
		var pv: PackedVector2Array = wb["poly_vec"]
		_terrain_batch.add_polyline(pv, 5.5, bank_col, true, true)
		_water_batch.add_polygon_safe(pv, deep_col if String(wb["kind"]) == "ocean" else water_col)

	for rv in sim.rivers:
		var pts: PackedVector2Array = rv["pts"]
		var w: float = float(rv["widthPx"])
		_terrain_batch.add_polyline(pts, w + 4.8, bank_col, false, true)
		_water_batch.add_polyline(pts, w, water_col, false, true)
		if w >= 8.0:
			_water_batch.add_dashed_polyline(pts, 1.2, ripple_col, 11.0, 18.0, w * 0.18)

	# 4. PT KAI Southern/Central Java Railway Line
	var ballast_col := Color(0.76, 0.74, 0.69, 0.80) if not is_dark else Color(0.24, 0.26, 0.30, 0.80)
	var tie_col := Color(0.42, 0.38, 0.34, 0.72)
	var rail_col := Color(0.32, 0.35, 0.40, 0.90)
	for rl in sim.railways:
		var rpts: PackedVector2Array = rl["pts"]
		_terrain_batch.add_polyline(rpts, 7.6, ballast_col, false, true)
		_terrain_batch.add_dashed_polyline(rpts, 6.2, tie_col, 2.0, 4.8, 0.0)
		_terrain_batch.add_polyline(rpts, 2.0, rail_col, false, false)

	# 5 & 6. Multi-Pass Authentic RoadBed, Swept Junctions, Roundabouts, Pockets, Bridges & RoadPaint
	_build_roads_and_junctions_batches(is_dark)

	# 7. Town Houses & Commercial Blocks via authentic `city_building.gdshader` + `city_shadow.gdshader`
	#    Honors `CityRebuild` (`demolished`), per-building `roofColor` / `wallColor`, and `CityBoom` (`lastGrowSec`)!
	var skip_minor_houses: bool = perf_preset == "battery"
	var use_shadows: bool = perf_preset != "battery"
	var sh_target: TriBatch2D = _shadow_batch if use_shadows else null
	var town_roofs := [
		Color("6A6E7A"), Color("7E6358"), Color("8C6D53"),
		Color("596370"), Color("9E6B55"), Color("787B84")
	]
	var b_idx: int = 0
	for b in sim.buildings:
		b_idx += 1
		if bool(b.get("demolished", false)):
			continue
		if skip_minor_houses and (b_idx % 2 == 1) and String(b["kind"]) == "house":
			continue
		var b_reg: int = int(b["regionIndex"])
		var b_unl: bool = sim.unlocked_regions.has(b_reg)
		var b_pos := Vector2(float(b["x"]), float(b["y"]))
		var r_col: Color = town_roofs[b_idx % town_roofs.size()]
		if b.has("roofColor") and String(b["roofColor"]) != "":
			r_col = GameCatalog.parse_color(String(b["roofColor"]), r_col)
		var w_col := Color("E4DFD3")
		if b.has("wallColor") and String(b["wallColor"]) != "":
			w_col = GameCatalog.parse_color(String(b["wallColor"]), w_col)
		if is_dark:
			r_col = r_col.darkened(0.32)
			w_col = w_col.darkened(0.68)
		if not b_unl:
			r_col = r_col.lerp(COL_BG, 0.65)
			w_col = w_col.lerp(COL_BG, 0.65)
		var night_on_seed: float = float(b.get("nightOn", 0.14 + fmod(float(b_idx) * 0.173, 0.82)))
		var win_seed: float = clampf(night_on_seed, 0.05, 0.96) if b_unl else 0.0
		var b_grow: float = float(b.get("lastGrowSec", -999.0))
		var rev_c0: Color
		if b_unl and b_grow > 0.0:
			rev_c0 = Color(b_grow, b_pos.x, b_pos.y, -1.72)
		elif b_unl:
			rev_c0 = _compute_region_reveal_c0(b_reg, b_pos)
		else:
			rev_c0 = Color(0.0, b_pos.x, b_pos.y, 0.0)
		_building_batch.add_city_building_25d(
			b_pos,
			float(b["w"]),
			float(b["d"]),
			float(b["angle"]),
			float(b["h"]) * (0.88 if b_unl else 0.38),
			r_col,
			w_col,
			win_seed,
			rev_c0,
			sh_target if b_unl else null
		)

	# 8. Industrial Facilities (Physical `ParkingSpace` Apron + `wideGate` + Indoor `garage` Bays 5..8 + `ExitRoad` Slip Gate)
	var pad_fill_col := Color("2F3440") if is_dark else Color("E6E2D8")
	var pad_dash_col := Color("585E6B") if is_dark else Color("A9A59A")
	var f_idx: int = 0
	for f in sim.facilities:
		f_idx += 1
		var f_reg: int = int(f["regionIndex"])
		var f_unl: bool = sim.unlocked_regions.has(f_reg)
		var fp: Vector2 = f["pos"]
		var fk := String(f["kind"])
		var exp_scale: float = 1.24 if int(f["upgrades"].get("expand", 0)) > 0 else 1.0
		var lot: Dictionary = f.get("parkingLot", {})

		var lot_col := Color("DCD8CE") if not is_dark else Color("2E333E")
		var apron_col := Color("343741") if not is_dark else Color("23262F")
		var curb_lot_col := Color("A9A59B") if not is_dark else Color("181B22")
		if not f_unl:
			lot_col.a = 0.35
			apron_col.a = 0.32
			curb_lot_col.a = 0.32
		_terrain_batch.add_rect_rot(fp + Vector2(0, 2.5), 45.0 * exp_scale, 30.0 * exp_scale, 0.0, lot_col)

		var apron_c: Vector2 = lot.get("apronCenter", fp + Vector2(0, 10.6 * exp_scale))
		var apron_sz: Vector2 = lot.get("apronSize", Vector2(29.0 * exp_scale, 11.6 * exp_scale))
		_terrain_batch.add_rect_rot(apron_c, apron_sz.x + 1.8, apron_sz.y + 1.8, 0.0, curb_lot_col)
		_terrain_batch.add_rect_rot(apron_c, apron_sz.x, apron_sz.y, 0.0, apron_col)

		if f_unl and not lot.is_empty():
			# Physical Gate Throat (`wideGate` 2-lane vs single-lane turn-taking)
			var drv_pts: PackedVector2Array = lot.get("drivewayPts", PackedVector2Array())
			var drv_w: float = float(lot.get("drivewayWidth", 5.8 * exp_scale))
			if drv_pts.size() >= 2:
				_terrain_batch.add_smooth_strip(drv_pts, drv_w + 1.6, curb_lot_col, false, true)
				_terrain_batch.add_smooth_strip(drv_pts, drv_w, apron_col, false, true)
				if bool(lot.get("wideGate", false)):
					_terrain_batch.add_dashed_polyline(drv_pts, 0.85, Color(COL_LANE_MARK, 0.80), 2.4, 2.0, 0.0)
				# Gate threshold bar
				var g_base: Vector2 = lot.get("gateBase", apron_c + Vector2(0, apron_sz.y * 0.48))
				var g_col_mark := Color("F2B630", 0.88) if bool(lot.get("hasExitRoad", false)) else Color(COL_LANE_MARK, 0.72)
				_terrain_batch.add_rect_rot(g_base, drv_w * 0.90, 0.9, 0.0, g_col_mark)

			# Rear One-Way Slip Gate (`ExitRoad`) connecting apron to `farGatePos`
			if bool(lot.get("hasExitRoad", false)):
				var far_g: Vector2 = lot.get("farGatePos", fp + Vector2(15.0 * exp_scale, 3.2 * exp_scale))
				var slip_pts := PackedVector2Array([apron_c + Vector2((far_g.x - apron_c.x) * 0.35, -1.5 * exp_scale), far_g])
				_terrain_batch.add_smooth_strip(slip_pts, 5.2 * exp_scale, apron_col, false, true)
				var sl_dir: Vector2 = (far_g - slip_pts[0]).normalized()
				var sl_n := Vector2(-sl_dir.y, sl_dir.x)
				var sl_mid: Vector2 = slip_pts[0].lerp(far_g, 0.58)
				_terrain_batch.add_tri(sl_mid + sl_dir * 2.2, sl_mid - sl_dir * 1.2 - sl_n * 1.4, sl_mid - sl_dir * 1.2 + sl_n * 1.4, Color("F2B630", 0.92))

			# Outdoor Stalls `1..4` (`not bay["indoor"]`) + Indoor `garage` Portals `5..8` (`bay["indoor"]`)
			var mark_stall := Color(COL_LANE_MARK, 0.78)
			for bay in lot.get("bays", []):
				var b_pos_s: Vector2 = bay["pos"]
				var b_ang_s: float = float(bay["angle"])
				var ux_s := Vector2(cos(b_ang_s), sin(b_ang_s))
				var uy_s := Vector2(-ux_s.y, ux_s.x)
				if not bool(bay.get("indoor", false)):
					var hl_s: float = 3.2 * exp_scale
					var hw_s: float = 1.95 * exp_scale
					var u_box := PackedVector2Array([
						b_pos_s - ux_s * hl_s - uy_s * hw_s,
						b_pos_s + ux_s * hl_s - uy_s * hw_s,
						b_pos_s + ux_s * hl_s + uy_s * hw_s,
						b_pos_s - ux_s * hl_s + uy_s * hw_s
					])
					_terrain_batch.add_polyline(u_box, 0.72, mark_stall, false, false)
				else:
					# Indoor garage roller bay threshold (`5..8`) along building south wall
					_terrain_batch.add_rect_rot(b_pos_s + Vector2(0, 1.3 * exp_scale), 3.4 * exp_scale, 3.2 * exp_scale, 0.0, apron_col)
					_terrain_batch.add_rect_rot(b_pos_s + Vector2(0, 0.5 * exp_scale), 3.0 * exp_scale, 1.2 * exp_scale, 0.0, Color("1E2129"))
					_terrain_batch.add_rect_rot(b_pos_s + Vector2(0, 1.4 * exp_scale), 3.0 * exp_scale, 0.55 * exp_scale, 0.0, Color("F2B630"))

			# Authentic FactoryLook concrete storage beds (`#E6E2D8` pad + `#A9A59A` dashed perimeter)
			for pad in sim.get_facility_storage_pads(f):
				var p_pos: Vector2 = pad["pos"]
				var p_sz: Vector2 = pad["size"]
				var hw_p: float = p_sz.x * 0.5
				var hh_p: float = p_sz.y * 0.5
				_terrain_batch.add_rect_rot(p_pos, p_sz.x, p_sz.y, 0.0, pad_fill_col)
				var perim := PackedVector2Array([
					p_pos + Vector2(-hw_p, -hh_p),
					p_pos + Vector2(hw_p, -hh_p),
					p_pos + Vector2(hw_p, hh_p),
					p_pos + Vector2(-hw_p, hh_p),
					p_pos + Vector2(-hw_p, -hh_p)
				])
				_terrain_batch.add_dashed_polyline(perim, 0.58, pad_dash_col, 1.8, 1.3)

		var r_col := Color("3F8C7E")
		if fk == "supplier":
			r_col = Color("353B4D")
		elif fk == "station":
			r_col = Color("3B6E8C")
		elif fk == "harbour":
			r_col = Color("2F5D8A")
		elif fk == "market":
			r_col = Color("8C5B4B")
		var w_col := Color("EAE6DC") if not is_dark else Color("454B59")
		if not f_unl:
			r_col = r_col.lerp(COL_BG, 0.65)
			w_col = w_col.lerp(COL_BG, 0.65)

		var fh: float = 14.8 if f_unl else 6.5
		var fw: float = 22.5 * exp_scale
		var fd: float = 15.0 * exp_scale
		var hall_c: Vector2 = fp + Vector2(0, -2.5 * exp_scale)
		var last_grow: float = float(f.get("lastGrowSec", -999.0))
		var fac_c0: Color
		if f_unl and last_grow > 0.0:
			# Negative mode triggers elastic grow squeeze + golden GROW_GLOW in city_building.gdshader!
			fac_c0 = Color(last_grow, hall_c.x, hall_c.y, -1.72)
		elif f_unl:
			fac_c0 = _compute_region_reveal_c0(f_reg, hall_c)
		else:
			fac_c0 = Color(0.0, hall_c.x, hall_c.y, 0.0)

		_building_batch.add_city_building_25d(
			hall_c, fw, fd, 0.0, fh, r_col, w_col,
			0.28 + fmod(float(f_idx) * 0.19, 0.68) if f_unl else 0.0,
			fac_c0,
			sh_target if f_unl else null
		)
		# Parallel white roof skylight stripes extruded at roof peak height (`kind = 0`)
		if f_unl:
			var uv_sky := Vector2(fh * 1.14, 0.0)
			var sky_col := Color("D9ECE9") if fk == "factory" else Color("DCE1EA")
			for sy in [-3.2 * exp_scale, 2.6 * exp_scale]:
				var s0 := hall_c + Vector2(-fw * 0.36, sy - 1.1)
				var s1 := hall_c + Vector2(fw * 0.36, sy - 1.1)
				var s2 := hall_c + Vector2(fw * 0.36, sy + 1.1)
				var s3 := hall_c + Vector2(-fw * 0.36, sy + 1.1)
				_building_batch.add_quad_c0(s0, s1, s2, s3, sky_col, uv_sky, uv_sky, uv_sky, uv_sky, fac_c0, fac_c0, fac_c0, fac_c0)

	# 8b. Authentic Starter Town Depot (`depot.gd`: two-tone blue roof, #8FB2E3 ridge & #F2B630/#262B38 hazard apron)
	if not sim.depot.is_empty():
		var d_pos: Vector2 = sim.depot.get("pos", Vector2.ZERO)
		var d_ang: float = float(sim.depot.get("angle", 0.0))
		var d_ux := Vector2(cos(d_ang), sin(d_ang))
		var d_uy := Vector2(-sin(d_ang), cos(d_ang))
		var d_lot := Color("DCD8CE") if not is_dark else Color("2E333E")
		var d_apron := Color("343741") if not is_dark else Color("23262F")
		_terrain_batch.add_rect_rot(d_pos, 23.0, 17.0, d_ang, d_lot)
		_terrain_batch.add_rect_rot(d_pos + d_ux * 5.6, 9.6, 10.4, d_ang, d_apron)
		# Diagonal #F2B630 / #262B38 hazard stripes across the garage bay threshold
		var haz_base: Vector2 = d_pos + d_ux * 1.6
		_terrain_batch.add_rect_rot(haz_base, 1.9, 9.8, d_ang, Color("262B38"))
		for hi in range(-2, 3):
			var hc: Vector2 = haz_base + d_uy * (float(hi) * 1.9)
			_terrain_batch.add_rect_rot(hc, 1.5, 0.95, d_ang + 0.55, Color("F2B630"))
		# Dark #1E2129 garage door bay
		_terrain_batch.add_rect_rot(d_pos + d_ux * 0.4, 1.4, 7.6, d_ang, Color("1E2129"))

		var dh: float = 10.6
		var dw: float = 14.2
		var dd: float = 12.6
		var d_hall: Vector2 = d_pos - d_ux * 3.0
		var d_wall := Color("EAE6DC") if not is_dark else Color("454B59")
		var d_c0 := Color(0.0, d_hall.x, d_hall.y, 0.0)
		_building_batch.add_city_building_25d(
			d_hall, dw, dd, d_ang, dh, Color("355F9C"), d_wall, 0.42, d_c0, sh_target
		)
		var uv_dr := Vector2(dh * 1.14, 0.0)
		# Lighter south/front roof slope (#6E9AD8) + crisp #8FB2E3 ridge beam
		var r_a := d_hall - d_ux * (dw * 0.48)
		var r_b := d_hall + d_ux * (dw * 0.48)
		var r_c := r_b + d_uy * (dd * 0.46)
		var r_d := r_a + d_uy * (dd * 0.46)
		_building_batch.add_quad_c0(r_a, r_b, r_c, r_d, Color("6E9AD8"), uv_dr, uv_dr, uv_dr, uv_dr, d_c0, d_c0, d_c0, d_c0)
		var rg0 := d_hall - d_ux * (dw * 0.49) - d_uy * 0.65
		var rg1 := d_hall + d_ux * (dw * 0.49) - d_uy * 0.65
		var rg2 := d_hall + d_ux * (dw * 0.49) + d_uy * 0.65
		var rg3 := d_hall - d_ux * (dw * 0.49) + d_uy * 0.65
		_building_batch.add_quad_c0(rg0, rg1, rg2, rg3, Color("8FB2E3"), uv_dr, uv_dr, uv_dr, uv_dr, d_c0, d_c0, d_c0, d_c0)

	# 9. Soft Cloud Mist Veil + Authentic Drifting `cloud_puff.gdshader` Puffs over Locked Regions
	var puff_idx: int = 0
	for reg in sim.regions:
		if bool(reg["unlocked"]):
			continue
		var mist_fill := Color(0.97, 0.97, 0.95, 0.54) if not is_dark else Color(0.09, 0.11, 0.15, 0.58)
		var puff_col := Color(0.99, 0.99, 0.98, 0.44) if not is_dark else Color(0.15, 0.18, 0.24, 0.44)
		for pv in reg["poly_vecs"]:
			_cloud_veil_batch.add_polygon_safe(pv, mist_fill)
			var step_i: int = maxi(1, pv.size() / 16)
			for pi in range(0, pv.size(), step_i):
				puff_idx += 1
				var phase_p: float = float(puff_idx) * 1.37
				var gust_p: float = float(puff_idx) * 0.83
				_cloud_puff_batch.add_cloud_puff(pv[pi], 32.0 + float(puff_idx % 4) * 5.0, phase_p, gust_p, puff_col)

	_shadow_batch.upload_to_mesh(_shadow_mesh)
	_building_batch.upload_to_mesh(_building_mesh)
	_cloud_puff_batch.upload_to_mesh(_cloud_puff_mesh)

	_shadow_node.visible = use_shadows and _shadow_mesh.get_surface_count() > 0
	_cloud_puff_node.visible = cloud_shadows_enabled and perf_preset != "battery" and _cloud_puff_mesh.get_surface_count() > 0

	_terrain_node.queue_redraw()
	_water_node.queue_redraw()
	_road_node.queue_redraw()
	_shadow_node.queue_redraw()
	_building_node.queue_redraw()
	_cloud_veil_node.queue_redraw()
	_cloud_puff_node.queue_redraw()

func _slice_ground_intervals(s0: float, s1: float, excluded_spans: Array) -> Array:
	if s1 - s0 < 1.0:
		return []
	if excluded_spans.is_empty():
		return [[s0, s1]]
	var intervals: Array = [[s0, s1]]
	for sp in excluded_spans:
		var ex0: float = float(sp[0])
		var ex1: float = float(sp[1])
		var next_list: Array = []
		for iv in intervals:
			var a: float = float(iv[0])
			var b: float = float(iv[1])
			if ex1 <= a or ex0 >= b:
				next_list.append([a, b])
			else:
				if ex0 - a >= 1.0:
					next_list.append([a, ex0])
				if b - ex1 >= 1.0:
					next_list.append([ex1, b])
		intervals = next_list
	return intervals

func _extend_polyline_ends(pts: PackedVector2Array, ext_start: float, ext_end: float) -> PackedVector2Array:
	var n: int = pts.size()
	if n < 2 or (ext_start <= 0.01 and ext_end <= 0.01):
		return pts
	var out: PackedVector2Array = pts.duplicate()
	if ext_start > 0.01:
		var d0: Vector2 = (out[0] - out[1]).normalized()
		if d0.length_squared() > 0.001:
			out[0] = out[0] + d0 * ext_start
	if ext_end > 0.01:
		var dn: Vector2 = (out[n - 1] - out[n - 2]).normalized()
		if dn.length_squared() > 0.001:
			out[n - 1] = out[n - 1] + dn * ext_end
	return out


func _build_roads_and_junctions_batches(is_dark: bool) -> void:
	var lht: bool = sim.left_hand_traffic
	var bg_mute: Color = Color("161920") if is_dark else COL_BG
	var sidewalk_base := Color("2A2E38") if is_dark else COL_SIDEWALK
	var curb_base := Color("181B22") if is_dark else COL_CURB
	var asphalt_base := Color("2B2F3A") if is_dark else COL_ROAD
	var shadow_bed_col := Color(0.05, 0.06, 0.10, 0.14) if is_dark else Color(GameCatalog.COLOR_SHADOW, 0.08)
	var mark_col := Color(COL_LANE_MARK, 0.92 if not is_dark else 0.64)
	var mark_soft := Color(COL_LANE_MARK, 0.80 if not is_dark else 0.52)

	# Pass 5.0: Unbuilt Road Offers (blueprint corridors) + Bridge/Overpass Water & Ground Drop Shadows
	var shadow_bridge := Color(0.12, 0.16, 0.24, 0.28 if not is_dark else 0.42)
	for r in sim.roads:
		var r_unl: bool = sim.unlocked_regions.has(int(r["regionIndex"]))
		var pts: PackedVector2Array = r["pts"]
		var cum: PackedFloat32Array = r["cum_len"]
		var rw: float = float(r.get("widthPx", RoadGeom.get_road_width(r)))

		if not bool(r["isBuilt"]):
			if r_unl:
				var bp_fill := Color(0.27, 0.50, 0.82, 0.16)
				var bp_dash := Color(0.27, 0.50, 0.82, 0.55)
				_road_batch.add_smooth_strip(pts, rw * 0.82, bp_fill, false, true)
				_road_batch.add_dashed_polyline(pts, 1.1, bp_dash, 7.0, 5.5, -rw * 0.36)
				_road_batch.add_dashed_polyline(pts, 1.1, bp_dash, 7.0, 5.5, rw * 0.36)
			continue

		for sp in r.get("bridgeSpans", []):
			var b_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, float(sp[0]), float(sp[1]))
			if b_pts.size() >= 2:
				var sh_pts := PackedVector2Array()
				sh_pts.resize(b_pts.size())
				for i in range(b_pts.size()):
					sh_pts[i] = b_pts[i] + Vector2(3.6, 4.6)
				_road_batch.add_smooth_strip(sh_pts, rw + 6.4, shadow_bridge, false, false)

		if not hide_flyovers:
			for osp in r.get("overpassSpans", []):
				var o_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, float(osp[0]), float(osp[1]))
				if o_pts.size() >= 2:
					var osh_pts := PackedVector2Array()
					osh_pts.resize(o_pts.size())
					for i in range(o_pts.size()):
						osh_pts[i] = o_pts[i] + Vector2(4.4, 5.6)
					_road_batch.add_smooth_strip(osh_pts, rw + 7.2, shadow_bridge, false, false)

	# Pass 5.1: Authentic `RoadBed` 3 Concentric Rings (Contact Shadow -> Sidewalk -> Curb)
	var bed_rings: Array = []
	if perf_preset != "battery":
		bed_rings.append([
			RoadGeom.SIDEWALK + RoadGeom.CURB + RoadGeom.SHADOW_BAND,
			shadow_bed_col,
			Color(shadow_bed_col, shadow_bed_col.a * 0.45)
		])
	bed_rings.append([
		RoadGeom.SIDEWALK + RoadGeom.CURB,
		sidewalk_base,
		sidewalk_base.lerp(bg_mute, 0.62)
	])
	bed_rings.append([
		RoadGeom.CURB,
		curb_base,
		curb_base.lerp(bg_mute, 0.58)
	])

	for ring_def in bed_rings:
		var out_d: float = float(ring_def[0])
		var col_unl: Color = ring_def[1]
		var col_lck: Color = ring_def[2]
		var lane_stroke_w: float = RoadGeom.LANE_WIDTH + 2.0 * out_d

		for r in sim.roads:
			if not bool(r["isBuilt"]):
				continue
			var r_unl: bool = sim.unlocked_regions.has(int(r["regionIndex"]))
			var r_col: Color = col_unl if r_unl else col_lck
			var excl: Array = r.get("overpassSpans", []) if hide_flyovers else []
			if not excl.is_empty():
				var rlen_ex: float = float(r["lengthPx"])
				var bs0: float = maxf(0.0, float(r.get("trimStart", 0.0)) - 1.2)
				var bs1: float = minf(rlen_ex, rlen_ex - float(r.get("trimEnd", 0.0)) + 1.2)
				var rw_ex: float = float(r.get("widthPx", RoadGeom.get_road_width(r)))
				for iv in _slice_ground_intervals(bs0, bs1, excl):
					var iv_pts: PackedVector2Array = RoadGeom.slice_polyline(r["pts"], r["cum_len"], float(iv[0]), float(iv[1]))
					_road_batch.add_smooth_strip(iv_pts, rw_ex + 2.0 * out_d, r_col, false, false)
				continue

			for ld in r.get("lanesFwd", []):
				var is_pk: bool = bool(ld["is_pocket"])
				var e_pts: PackedVector2Array = _extend_polyline_ends(ld["pts"], 0.0 if is_pk else 2.0, 2.0)
				_road_batch.add_smooth_strip(e_pts, lane_stroke_w, r_col, false, false)

			for ld_b in r.get("lanesBwd", []):
				var is_pk_b: bool = bool(ld_b["is_pocket"])
				var eb_pts: PackedVector2Array = _extend_polyline_ends(ld_b["pts"], 0.0 if is_pk_b else 2.0, 2.0)
				_road_batch.add_smooth_strip(eb_pts, lane_stroke_w, r_col, false, false)

			if int(r["oneWay"]) == 0:
				var c_line: PackedVector2Array = r.get("centerLine", PackedVector2Array())
				if c_line.size() >= 2:
					var med_extra: float = (2.0 * RoadGeom.MEDIAN_ISLAND_HALF_W) if bool(r.get("medianShifted", false)) else 0.0
					var gap_w: float = 2.0 * RoadGeom.LANE_SEPARATION + med_extra + 2.0 * out_d
					_road_batch.add_smooth_strip(_extend_polyline_ends(c_line, 2.0, 2.0), gap_w, r_col, false, false)

		for j in sim.junctions:
			var j_unl: bool = sim.unlocked_regions.has(int(j["regionIndex"]))
			var j_col: Color = col_unl if j_unl else col_lck
			var jp: Vector2 = j["pos"]
			var geom: Dictionary = j.get("geom", {})
			var gkind := String(geom.get("kind", "empty"))
			if gkind == "roundabout" or gkind == "roundabout2":
				var r_out: float = float(geom["r_outer"])
				_road_batch.add_circle(jp, r_out + out_d, j_col, 36)
				for a in geom["arms"]:
					if a.has("flare_asphalt"):
						var fl_poly: PackedVector2Array = a["flare_asphalt"]
						_road_batch.add_polygon_safe(fl_poly, j_col)
						if out_d > 0.02:
							_road_batch.add_smooth_strip(fl_poly, 2.0 * out_d, j_col, true, false)
			elif gkind == "standard" and geom.has("plaza_poly"):
				var ppoly: PackedVector2Array = geom["plaza_poly"]
				if ppoly.size() >= 3:
					_road_batch.add_polygon_safe(ppoly, j_col)
					if out_d > 0.02:
						_road_batch.add_smooth_strip(ppoly, 2.0 * out_d, j_col, true, false)
			elif gkind == "culdesac":
				_road_batch.add_circle(jp, float(geom.get("radius", 5.0)) + out_d, j_col, 20)

	# Pass 5.2: Authentic `RoadSurface` + Per-Lane `LANE_WIDTH` Asphalt Layer
	for r in sim.roads:
		if not bool(r["isBuilt"]):
			continue
		var r_unl: bool = sim.unlocked_regions.has(int(r["regionIndex"]))
		var asph: Color = asphalt_base if r_unl else asphalt_base.lerp(bg_mute, 0.52)
		var excl: Array = r.get("overpassSpans", []) if hide_flyovers else []
		if not excl.is_empty():
			var rlen_ex: float = float(r["lengthPx"])
			var bs0: float = maxf(0.0, float(r.get("trimStart", 0.0)) - 2.0)
			var bs1: float = minf(rlen_ex, rlen_ex - float(r.get("trimEnd", 0.0)) + 2.0)
			var rw_ex: float = float(r.get("widthPx", RoadGeom.get_road_width(r)))
			for iv in _slice_ground_intervals(bs0, bs1, excl):
				var iv_pts: PackedVector2Array = RoadGeom.slice_polyline(r["pts"], r["cum_len"], float(iv[0]), float(iv[1]))
				_road_batch.add_smooth_strip(iv_pts, rw_ex, asph, false, false)
			continue

		for ld in r.get("lanesFwd", []):
			var is_pk: bool = bool(ld["is_pocket"])
			var e_pts: PackedVector2Array = _extend_polyline_ends(ld["pts"], 0.0 if is_pk else 2.2, 2.2)
			_road_batch.add_smooth_strip(e_pts, RoadGeom.LANE_WIDTH, asph, false, false)

		for ld_b in r.get("lanesBwd", []):
			var is_pk_b: bool = bool(ld_b["is_pocket"])
			var eb_pts: PackedVector2Array = _extend_polyline_ends(ld_b["pts"], 0.0 if is_pk_b else 2.2, 2.2)
			_road_batch.add_smooth_strip(eb_pts, RoadGeom.LANE_WIDTH, asph, false, false)

		if int(r["oneWay"]) == 0:
			var c_line: PackedVector2Array = r.get("centerLine", PackedVector2Array())
			if c_line.size() >= 2:
				var med_extra: float = (2.0 * RoadGeom.MEDIAN_ISLAND_HALF_W) if bool(r.get("medianShifted", false)) else 0.0
				var inner_gap_w: float = maxf(1.6, 2.0 * RoadGeom.LANE_SEPARATION - RoadGeom.LANE_WIDTH + med_extra + 1.4)
				_road_batch.add_smooth_strip(_extend_polyline_ends(c_line, 2.2, 2.2), inner_gap_w, asph, false, false)

	for j in sim.junctions:
		var j_unl: bool = sim.unlocked_regions.has(int(j["regionIndex"]))
		var asph: Color = asphalt_base if j_unl else asphalt_base.lerp(bg_mute, 0.52)
		var jp: Vector2 = j["pos"]
		var geom: Dictionary = j.get("geom", {})
		var gkind := String(geom.get("kind", "empty"))
		if gkind == "roundabout" or gkind == "roundabout2":
			var r_out: float = float(geom["r_outer"])
			_road_batch.add_circle(jp, r_out, asph, 36)
			for a in geom["arms"]:
				if a.has("flare_asphalt"):
					_road_batch.add_polygon_safe(a["flare_asphalt"], asph)
		elif gkind == "standard" and geom.has("plaza_poly"):
			_road_batch.add_polygon_safe(geom["plaza_poly"], asph)
		elif gkind == "culdesac":
			_road_batch.add_circle(jp, float(geom.get("radius", 5.0)), asph, 20)

	# Pass 5.3: Authentic `Roundabout` Central Island (`COL_CURB` -> `COL_SIDEWALK` -> `COL_GRASS`) & Splitter Islands
	for j in sim.junctions:
		var geom: Dictionary = j.get("geom", {})
		var gkind := String(geom.get("kind", "empty"))
		if gkind != "roundabout" and gkind != "roundabout2":
			continue
		var j_unl: bool = sim.unlocked_regions.has(int(j["regionIndex"]))
		var jp: Vector2 = j["pos"]
		var r_isl: float = float(geom["r_island"])
		var r_out: float = float(geom["r_outer"])

		var isl_curb := curb_base if j_unl else curb_base.lerp(bg_mute, 0.58)
		var apron_c := sidewalk_base if j_unl else sidewalk_base.lerp(bg_mute, 0.62)
		var isl_grass := (COL_GRASS if not is_dark else Color("2E3E2A"))
		if not j_unl:
			isl_grass = isl_grass.lerp(bg_mute, 0.58)

		_road_batch.add_circle(jp, r_isl + RoadGeom.CURB, isl_curb, 30)
		_road_batch.add_circle(jp, r_isl, apron_c, 28)
		_road_batch.add_circle(jp, maxf(2.4, r_isl - RoadGeom.SIDEWALK * 0.92), isl_grass, 28)

		if j_unl:
			if j.get("landmark", null) != null and r_isl >= 6.0:
				_road_batch.add_rect_rot(jp + Vector2(0.8, 1.0), 4.8, 4.8, PI * 0.25, COL_SHADOW)
				_road_batch.add_rect_rot(jp, 4.4, 4.4, PI * 0.25, Color("E8E3D6") if not is_dark else Color("6A7080"))
				_road_batch.add_circle(jp, 1.4, Color("D97A3E"), 10)
			elif r_isl >= 5.6:
				_road_batch.add_circle(jp + Vector2(-1.4, -1.0), 2.2, COL_TREE_B if not is_dark else COL_TREE_B.darkened(0.45), 10)
				_road_batch.add_circle(jp + Vector2(1.6, 1.2), 1.8, COL_TREE_AUTUMN if not is_dark else COL_TREE_AUTUMN.darkened(0.45), 10)

			for a in geom["arms"]:
				if int(a["one_way"]) == 0 and not bool(a["closed"]) and float(a["rlen"]) >= r_out + 24.0:
					var u_out: Vector2 = a["throat_out_dir"]
					var rn := Vector2(-u_out.y, u_out.x)
					var p_inner: Vector2 = jp + u_out * (r_out + 1.4)
					var p_tip: Vector2 = jp + u_out * (r_out + 8.4)
					var sp_hw: float = clampf(float(a["hw"]) * 0.18, 1.1, 2.0)
					_road_batch.add_tri(p_tip, p_inner - rn * (sp_hw + RoadGeom.CURB), p_inner + rn * (sp_hw + RoadGeom.CURB), isl_curb)
					_road_batch.add_tri(p_tip - u_out * 0.9, p_inner - rn * sp_hw + u_out * 0.4, p_inner + rn * sp_hw + u_out * 0.4, apron_c)

	# Pass 5.4: Update 1.9 River-Crossing Bridges & Grade-Separated Overpasses (with Hide Flyovers ghost mode!)
	for r in sim.roads:
		if not bool(r["isBuilt"]):
			continue
		var r_unl: bool = sim.unlocked_regions.has(int(r["regionIndex"]))
		var pts: PackedVector2Array = r["pts"]
		var cum: PackedFloat32Array = r["cum_len"]
		var rw: float = float(r.get("widthPx", RoadGeom.get_road_width(r)))
		var asph: Color = asphalt_base if r_unl else asphalt_base.lerp(bg_mute, 0.52)

		var b_spans: Array = r.get("bridgeSpans", [])
		if not b_spans.is_empty():
			var pier_dark := Color("948F83") if not is_dark else Color("323742")
			var pier_cap := Color("C8C2B4") if not is_dark else Color("505664")
			var deck_walk := Color("DFDBD0") if not is_dark else Color("434956")
			var parapet_top := Color("F5F2EA") if not is_dark else Color("6A7282")
			var parapet_in := Color(0.14, 0.15, 0.19, 0.52)
			if not r_unl:
				deck_walk = deck_walk.lerp(bg_mute, 0.5)
				parapet_top = parapet_top.lerp(bg_mute, 0.5)
				pier_cap = pier_cap.lerp(bg_mute, 0.5)

			for sp in b_spans:
				var s0: float = float(sp[0])
				var s1: float = float(sp[1])
				var span_len: float = s1 - s0
				var b_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, s0, s1)
				if b_pts.size() < 2:
					continue

				var pier_s_list: Array[float] = [s0, s1]
				if span_len >= 52.0:
					var n_mid: int = int(floor(span_len / 44.0))
					for mi in range(1, n_mid + 1):
						pier_s_list.append(lerpf(s0, s1, float(mi) / float(n_mid + 1)))
				for ps in pier_s_list:
					var pr_raw: Dictionary = RoadGeom.sample_polyline_raw(pts, cum, ps)
					var p_ang: float = atan2((pr_raw["dir"] as Vector2).y, (pr_raw["dir"] as Vector2).x)
					_road_batch.add_rect_rot(pr_raw["pos"], 4.8, rw + 7.2, p_ang, pier_dark)
					_road_batch.add_rect_rot(pr_raw["pos"], 3.4, rw + 6.0, p_ang, pier_cap)

				_road_batch.add_smooth_strip(b_pts, rw + 4.8, deck_walk, false, false)
				_road_batch.add_smooth_strip(b_pts, rw, asph, false, false)
				var rail_off: float = rw * 0.5 + 1.9
				var inner_off: float = rw * 0.5 + 0.95
				_road_batch.add_smooth_strip(b_pts, 1.35, parapet_top, false, false, -rail_off)
				_road_batch.add_smooth_strip(b_pts, 1.35, parapet_top, false, false, rail_off)
				_road_batch.add_smooth_strip(b_pts, 0.60, parapet_in, false, false, -inner_off)
				_road_batch.add_smooth_strip(b_pts, 0.60, parapet_in, false, false, inner_off)

		var o_spans: Array = r.get("overpassSpans", [])
		if not o_spans.is_empty():
			var ov_deck := Color("CFD4DC") if not is_dark else Color("49505E")
			var ov_rail := Color("ECEFF4") if not is_dark else Color("6F788A")
			var ghost_rail := Color(0.35, 0.58, 0.88, 0.36)
			for osp in o_spans:
				var os0: float = float(osp[0])
				var os1: float = float(osp[1])
				var o_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, os0, os1)
				if o_pts.size() < 2:
					continue
				var or_off: float = rw * 0.5 + 1.8
				if hide_flyovers:
					_road_batch.add_dashed_polyline(o_pts, 1.2, ghost_rail, 6.0, 5.0, -or_off)
					_road_batch.add_dashed_polyline(o_pts, 1.2, ghost_rail, 6.0, 5.0, or_off)
				else:
					_road_batch.add_smooth_strip(o_pts, rw + 4.4, ov_deck, false, false)
					_road_batch.add_smooth_strip(o_pts, rw, asph, false, false)
					_road_batch.add_smooth_strip(o_pts, 1.3, ov_rail, false, false, -or_off)
					_road_batch.add_smooth_strip(o_pts, 1.3, ov_rail, false, false, or_off)

	# Pass 5.5: Authentic `LaneMarkings` (Single Dashed/Solid Centerline, 45°-Hatched Median Islands, Halfway Lane Dividers & Periodic One-Way Arrows)
	var side_sign: float = -1.0 if lht else 1.0
	for r in sim.roads:
		if not bool(r["isBuilt"]) or not sim.unlocked_regions.has(int(r["regionIndex"])):
			continue
		var pts: PackedVector2Array = r["pts"]
		var cum: PackedFloat32Array = r["cum_len"]
		var rlen: float = float(r["lengthPx"])
		var rw: float = float(r.get("widthPx", RoadGeom.get_road_width(r)))
		var p_s0: float = float(r.get("trimStart", 0.0)) + 0.5
		var p_s1: float = rlen - float(r.get("trimEnd", 0.0)) - 0.5
		if p_s1 - p_s0 < 3.5:
			continue

		if bool(r["closed"]):
			var c_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, p_s0 + 1.2, p_s1 - 1.2)
			if c_pts.size() >= 2:
				var lawn_c := COL_GRASS if not is_dark else Color("2E3E2A")
				var path_c := COL_SIDEWALK if not is_dark else Color("454B58")
				_road_batch.add_smooth_strip(c_pts, rw * 0.80, lawn_c, false, false)
				_road_batch.add_smooth_strip(c_pts, rw * 0.28, path_c, false, false)
				for end_s in [p_s0 + 1.0, p_s1 - 1.0]:
					var b_raw: Dictionary = RoadGeom.sample_polyline_raw(pts, cum, end_s)
					var b_pos: Vector2 = b_raw["pos"]
					var b_rn: Vector2 = b_raw["right"]
					for bi in [-1, 0, 1]:
						var bp: Vector2 = b_pos + b_rn * (float(bi) * rw * 0.28)
						_road_batch.add_circle(bp, 1.35, Color("C8323A"), 8)
						_road_batch.add_circle(bp, 0.68, COL_LANE_MARK, 8)
			continue

		if hide_flyovers and not (r.get("overpassSpans", []) as Array).is_empty():
			continue

		var ow: int = int(r["oneWay"])
		var lf: int = maxi(1, int(r["lanesForward"]))
		var lb: int = maxi(1, int(r["lanesBackward"]))

		var j_u: Dictionary = sim.junction_map.get(String(r["from"]), {})
		var j_v: Dictionary = sim.junction_map.get(String(r["to"]), {})
		var u_ctrl := String(j_u.get("control", "none"))
		var v_ctrl := String(j_v.get("control", "none"))
		var u_multi: bool = ((j_u.get("geom", {}) as Dictionary).get("arms", []) as Array).size() >= 3 or u_ctrl == "lights"
		var v_multi: bool = ((j_v.get("geom", {}) as Dictionary).get("arms", []) as Array).size() >= 3 or v_ctrl == "lights"

		if ow == 0:
			var asym_shift: float = float(lf - lb) * 0.5 * RoadGeom.LANE_SPACING
			var div_off: float = -side_sign * asym_shift

			# 1. 45°-hatched median islands (`_fXJc_p73OuDT`) ONLY where `medianZones` exist
			for mz in r.get("medianZones", []):
				var l_m: PackedVector2Array = mz["left_pts"]
				var r_m: PackedVector2Array = mz["right_pts"]
				_road_batch.add_smooth_strip(l_m, RoadGeom.LINE_WIDTH, mark_col, false, false)
				_road_batch.add_smooth_strip(r_m, RoadGeom.LINE_WIDTH, mark_col, false, false)
				_add_hatched_median_island(l_m, r_m, mark_soft)

			# 2. Single white `#F2F0E5` centerline (solid within `CENTER_SOLID_DIST` of junctions, dashed in mid-block!)
			var single_zones: Array = r.get("centerSingleZones", [[p_s0, p_s1]])
			for sz in single_zones:
				var zs0: float = maxf(p_s0, float(sz[0]))
				var zs1: float = minf(p_s1, float(sz[1]))
				if zs1 - zs0 < 1.5:
					continue
				var solid_u: float = RoadGeom.CENTER_SOLID_DIST if (u_multi and absf(zs0 - p_s0) < 2.0 and zs1 - zs0 >= 22.0) else 0.0
				var solid_v: float = RoadGeom.CENTER_SOLID_DIST if (v_multi and absf(zs1 - p_s1) < 2.0 and zs1 - zs0 >= 22.0) else 0.0
				if solid_u > 0.0:
					var su_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, zs0, zs0 + solid_u)
					_road_batch.add_smooth_strip(su_pts, RoadGeom.LINE_WIDTH, mark_col, false, false, div_off)
				if solid_v > 0.0:
					var sv_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, zs1 - solid_v, zs1)
					_road_batch.add_smooth_strip(sv_pts, RoadGeom.LINE_WIDTH, mark_col, false, false, div_off)
				var mid_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, zs0 + solid_u + 0.8, zs1 - solid_v - 0.8)
				if mid_pts.size() >= 2:
					_road_batch.add_dashed_polyline(mid_pts, RoadGeom.LINE_WIDTH, mark_soft, RoadGeom.DASH, RoadGeom.GAP, div_off)

			# 3. Same-direction lane dividers (including turn pockets!) sampled halfway between adjacent lane polylines
			_add_direction_lane_dividers(r.get("lanesFwd", []), v_multi, mark_col, mark_soft)
			_add_direction_lane_dividers(r.get("lanesBwd", []), u_multi, mark_col, mark_soft)
		else:
			var ow_lanes: Array = r.get("lanesFwd" if ow > 0 else "lanesBwd", [])
			var approach_multi: bool = v_multi if ow > 0 else u_multi
			_add_direction_lane_dividers(ow_lanes, approach_multi, mark_col, mark_soft)
			if not ow_lanes.is_empty():
				var mid_lane: Dictionary = ow_lanes[ow_lanes.size() / 2]
				var ml_pts: PackedVector2Array = mid_lane["pts"]
				var ml_cum: PackedFloat32Array = mid_lane["cum_len"]
				var ml_len: float = ml_cum[ml_cum.size() - 1] if ml_cum.size() > 0 else 0.0
				if ml_len >= 18.0:
					var ow_raw: Dictionary = RoadGeom.sample_polyline_raw(ml_pts, ml_cum, ml_len * 0.5)
					var ow_dir: Vector2 = ow_raw["dir"]
					_add_lane_turn_arrow(ow_raw["pos"], ow_dir, Vector2(-ow_dir.y, ow_dir.x), false, true, false, mark_soft)

	# Pass 5.6: Junction Stop Bars, Yield Shark-Teeth, Roundabout Dividers & Authentic Turn Arrows
	for j in sim.junctions:
		if not sim.unlocked_regions.has(int(j["regionIndex"])):
			continue
		var jp: Vector2 = j["pos"]
		var ctrl := String(j["control"])
		var geom: Dictionary = j.get("geom", {})
		var gkind := String(geom.get("kind", "empty"))
		var arms: Array = geom.get("arms", [])

		if gkind == "roundabout" or gkind == "roundabout2":
			var r_isl: float = float(geom["r_island"])
			var r_out: float = float(geom["r_outer"])
			if gkind == "roundabout2":
				_road_batch.add_dashed_ring(jp, 0.5 * (r_isl + r_out), RoadGeom.LINE_WIDTH, mark_soft, 20, 0.52)
			for a in arms:
				if not bool(a["can_enter"]):
					continue
				_add_approach_control_and_arrows(j, a, "roundabout_yield", lht, mark_col, mark_soft)
		elif gkind == "standard" and (arms.size() >= 3 or ctrl == "lights"):
			var minor_ids: Array = j.get("yieldMinorEdgeIds", [])
			for a in arms:
				if not bool(a["can_enter"]):
					continue
				var line_mode := "none"
				if ctrl == "lights":
					line_mode = "stop_bar"
				elif ctrl == "yield" and minor_ids.has(String(a["edge_id"])):
					line_mode = "yield_teeth"
				_add_approach_control_and_arrows(j, a, line_mode, lht, mark_col, mark_soft)


func _add_hatched_median_island(left_pts: PackedVector2Array, right_pts: PackedVector2Array, col: Color) -> void:
	var n: int = mini(left_pts.size(), right_pts.size())
	if n < 2:
		return
	var acc: float = 0.0
	for i in range(1, n):
		var c_prev: Vector2 = 0.5 * (left_pts[i - 1] + right_pts[i - 1])
		var c_cur: Vector2 = 0.5 * (left_pts[i] + right_pts[i])
		acc += c_prev.distance_to(c_cur)
		if acc >= 2.5:
			acc = 0.0
			var w_gap: float = left_pts[i].distance_to(right_pts[i])
			if w_gap >= 0.9:
				var dir: Vector2 = (c_cur - c_prev).normalized()
				var a_pt: Vector2 = left_pts[i].lerp(right_pts[i], 0.12) - dir * (w_gap * 0.35)
				var b_pt: Vector2 = left_pts[i].lerp(right_pts[i], 0.88) + dir * (w_gap * 0.35)
				_road_batch.add_smooth_strip(PackedVector2Array([a_pt, b_pt]), RoadGeom.LINE_WIDTH * 0.95, col, false, false)


func _add_direction_lane_dividers(lanes_list: Array, solid_at_approach: bool, mark_col: Color, mark_soft: Color) -> void:
	var count: int = lanes_list.size()
	if count < 2:
		return
	var min_sep: float = RoadGeom.LANE_SPACING * 0.82
	for k in range(count - 1):
		var la: Dictionary = lanes_list[k]
		var lb_d: Dictionary = lanes_list[k + 1]
		var pts_a: PackedVector2Array = la["pts"]
		var cum_a: PackedFloat32Array = la["cum_len"]
		var len_a: float = cum_a[cum_a.size() - 1] if cum_a.size() > 0 else 0.0
		var pts_b: PackedVector2Array = lb_d["pts"]
		var cum_b: PackedFloat32Array = lb_d["cum_len"]
		var len_b: float = cum_b[cum_b.size() - 1] if cum_b.size() > 0 else 0.0
		if len_a < 3.0 or len_b < 3.0:
			continue

		# Align backward from the approach stop line (`end` of both lanes)
		var div_pts := PackedVector2Array()
		for bi in range(pts_b.size()):
			var rem_from_stop: float = len_b - cum_b[bi]
			var s_on_a: float = clampf(len_a - rem_from_stop, 0.0, len_a)
			var pa: Vector2 = RoadGeom.sample_polyline_raw(pts_a, cum_a, s_on_a)["pos"]
			var pb: Vector2 = pts_b[bi]
			if pa.distance_to(pb) >= min_sep:
				var mid_p: Vector2 = 0.5 * (pa + pb)
				if div_pts.is_empty() or div_pts[div_pts.size() - 1].distance_to(mid_p) > 0.10:
					div_pts.append(mid_p)

		if div_pts.size() < 2:
			continue
		var div_cum: PackedFloat32Array = RoadGeom.build_cum_lengths(div_pts)
		var div_len: float = div_cum[div_cum.size() - 1]
		var sol_d: float = minf(RoadGeom.LANE_SOLID_DIST, div_len * 0.55) if (solid_at_approach and div_len >= 12.0) else 0.0
		if div_len - sol_d >= 2.5:
			var dash_part: PackedVector2Array = RoadGeom.slice_polyline(div_pts, div_cum, 0.4, div_len - sol_d - 0.5)
			if dash_part.size() >= 2:
				_road_batch.add_dashed_polyline(dash_part, RoadGeom.LINE_WIDTH, mark_soft, RoadGeom.DASH, RoadGeom.GAP)
		if sol_d > 0.5:
			var sol_part: PackedVector2Array = RoadGeom.slice_polyline(div_pts, div_cum, div_len - sol_d, div_len)
			if sol_part.size() >= 2:
				_road_batch.add_smooth_strip(sol_part, RoadGeom.LINE_WIDTH, mark_col, false, false)


func _add_approach_control_and_arrows(
	_j: Dictionary,
	a: Dictionary,
	line_mode: String,
	lht: bool,
	mark_col: Color,
	mark_soft: Color
) -> void:
	var eid := String(a["edge_id"])
	if not sim.road_map.has(eid):
		return
	var r: Dictionary = sim.road_map[eid]
	var is_start: bool = bool(a["is_start"])
	var in_fwd: bool = not is_start
	var lanes_arr: Array = r.get("lanesFwd" if in_fwd else "lanesBwd", [])
	var lanes_in: int = lanes_arr.size()
	if lanes_in <= 0:
		return

	var p_th: Vector2 = a["throat_pos"]
	var u_out: Vector2 = a["throat_out_dir"]
	var in_dir: Vector2 = -u_out
	var in_right := Vector2(-in_dir.y, in_dir.x)

	# Compute exact arriving lane span from explicit per-lane endpoints
	var min_lat: float = 1e9
	var max_lat: float = -1e9
	var half_span: float = RoadGeom.LANE_WIDTH * 0.46
	for ld in lanes_arr:
		var lpts: PackedVector2Array = ld["pts"]
		if lpts.size() >= 1:
			var end_p: Vector2 = lpts[lpts.size() - 1]
			var lat_c: float = (end_p - p_th).dot(in_right)
			min_lat = minf(min_lat, lat_c - half_span)
			max_lat = maxf(max_lat, lat_c + half_span)
	if min_lat > max_lat:
		return

	if line_mode == "stop_bar":
		var bar_a: Vector2 = p_th + in_right * min_lat
		var bar_b: Vector2 = p_th + in_right * max_lat
		_road_batch.add_smooth_strip(PackedVector2Array([bar_a, bar_b]), RoadGeom.STOP_LINE_WIDTH, mark_col, false, false)
	elif line_mode == "yield_teeth" or line_mode == "roundabout_yield":
		var span_w: float = max_lat - min_lat
		var n_teeth: int = maxi(2, int(round(span_w / 2.2)))
		var step_w: float = span_w / float(n_teeth)
		var line_pos: Vector2 = p_th + (in_dir * 1.8 if line_mode == "roundabout_yield" else Vector2.ZERO)
		for ti in range(n_teeth):
			var c_lat: float = min_lat + (float(ti) + 0.5) * step_w
			var tc: Vector2 = line_pos + in_right * c_lat
			var tw: float = step_w * 0.34
			_road_batch.add_tri(tc + in_dir * 1.25, tc - in_dir * 0.72 - in_right * tw, tc - in_dir * 0.72 + in_right * tw, mark_col)
		if line_mode == "yield_teeth":
			var curb_lat: float = (min_lat - 2.4) if lht else (max_lat + 2.4)
			var sign_c: Vector2 = p_th - in_dir * 1.8 + in_right * curb_lat
			_road_batch.add_tri(sign_c + in_dir * 2.4, sign_c - in_dir * 1.7 - in_right * 2.2, sign_c - in_dir * 1.7 + in_right * 2.2, Color("C8323A"))
			_road_batch.add_tri(sign_c + in_dir * 1.25, sign_c - in_dir * 0.95 - in_right * 1.15, sign_c - in_dir * 0.95 + in_right * 1.15, Color("FAF7EE"))

	# Authentic `LaneMarkings` rule: draw turn arrows ONLY when `lanes_in > 1` or `custom_mask != 7`!
	var custom_mask: int = int(r.get("turnMaskForward" if in_fwd else "turnMaskBackward", 7))
	if lanes_in <= 1 and custom_mask == 7:
		return

	var turns: Dictionary = a.get("turns", {"left": false, "straight": true, "right": false})
	var t_l: bool = bool(turns.get("left", false))
	var t_s: bool = bool(turns.get("straight", true))
	var t_r: bool = bool(turns.get("right", false))
	if line_mode == "roundabout_yield":
		t_l = lht
		t_s = true
		t_r = not lht
	elif custom_mask != 7:
		t_l = (custom_mask & RoutePathfinder.TURN_LEFT) != 0
		t_s = (custom_mask & RoutePathfinder.TURN_STRAIGHT) != 0
		t_r = (custom_mask & RoutePathfinder.TURN_RIGHT) != 0

	var arrow_col: Color = Color("FFE066") if custom_mask != 7 else mark_soft
	# Note: `lanes_arr` is ordered `inner_k = 0 (inner/median)` .. `lanes_in - 1 (outer/kerbside)`!
	for inner_k in range(lanes_in):
		var ld_a: Dictionary = lanes_arr[inner_k]
		var l_pts: PackedVector2Array = ld_a["pts"]
		var l_cum: PackedFloat32Array = ld_a["cum_len"]
		var l_len: float = l_cum[l_cum.size() - 1] if l_cum.size() > 0 else 0.0
		if l_len < RoadGeom.ARROW_OFFSET + 6.0:
			continue
		var ar_raw: Dictionary = RoadGeom.sample_polyline_raw(l_pts, l_cum, l_len - RoadGeom.ARROW_OFFSET)
		var ar_dir: Vector2 = ar_raw["dir"]
		var ar_right: Vector2 = ar_raw["right"]

		var l_flag := t_l
		var s_flag := t_s
		var r_flag := t_r
		var is_outer_lane: bool = (inner_k == lanes_in - 1)
		var is_inner_lane: bool = (inner_k == 0)
		var is_dedicated_pocket: bool = bool(ld_a.get("is_pocket", false))
		if lanes_in >= 2 and line_mode != "roundabout_yield" and custom_mask == 7:
			if lht:
				if is_outer_lane:
					r_flag = false
					if is_dedicated_pocket and l_flag:
						s_flag = false
					elif not l_flag:
						s_flag = true
				elif is_inner_lane:
					l_flag = false
					if not r_flag:
						s_flag = true
				else:
					l_flag = false
					r_flag = false
					s_flag = true
			else:
				if is_outer_lane:
					l_flag = false
					if is_dedicated_pocket and r_flag:
						s_flag = false
					elif not r_flag:
						s_flag = true
				elif is_inner_lane:
					r_flag = false
					if not l_flag:
						s_flag = true
				else:
					l_flag = false
					r_flag = false
					s_flag = true
		if not l_flag and not s_flag and not r_flag:
			s_flag = true
		_add_lane_turn_arrow(ar_raw["pos"], ar_dir, ar_right, l_flag, s_flag, r_flag, arrow_col)


func _add_lane_turn_arrow(
	c: Vector2,
	dir: Vector2,
	right_n: Vector2,
	allow_left: bool,
	allow_straight: bool,
	allow_right: bool,
	col: Color
) -> void:
	var stem_end: float = 1.05 if allow_straight else 0.35
	_road_batch.add_smooth_strip(
		PackedVector2Array([c - dir * 2.35, c + dir * stem_end]),
		0.64, col, false, false
	)
	if allow_straight:
		_road_batch.add_tri(
			c + dir * 2.85,
			c + dir * 0.90 - right_n * 1.18,
			c + dir * 0.90 + right_n * 1.18,
			col
		)
	if allow_left:
		var p_branch: Vector2 = c + dir * 0.18
		var p_tip_base: Vector2 = c + dir * 0.62 - right_n * 1.38
		_road_batch.add_smooth_strip(PackedVector2Array([p_branch, p_tip_base]), 0.58, col, false, false)
		_road_batch.add_tri(
			c + dir * 0.75 - right_n * 2.55,
			p_tip_base + dir * 0.95,
			p_tip_base - dir * 0.88,
			col
		)
	if allow_right:
		var p_branch_r: Vector2 = c + dir * 0.18
		var p_tip_base_r: Vector2 = c + dir * 0.62 + right_n * 1.38
		_road_batch.add_smooth_strip(PackedVector2Array([p_branch_r, p_tip_base_r]), 0.58, col, false, false)
		_road_batch.add_tri(
			c + dir * 0.75 + right_n * 2.55,
			p_tip_base_r - dir * 0.88,
			p_tip_base_r + dir * 0.95,
			col
		)


func _is_agent_under_hidden_flyover(ag: Dictionary) -> bool:
	if not hide_flyovers or sim == null:
		return false
	var st := String(ag.get("state", ""))
	if st not in ["driving_outbound", "driving_return", "driving_to_depot", "driving_from_depot"]:
		return false
	var rt: Dictionary = sim.get_route(String(ag.get("routeId", "")))
	var path: Array = []
	if st == "driving_outbound":
		path = rt.get("forwardPath", [])
	elif st == "driving_return":
		path = rt.get("returnPath", [])
	else:
		path = ag.get("depotPath", [])
	var s_idx: int = int(ag.get("stepIndex", 0))
	if s_idx >= 0 and s_idx < path.size():
		var eid := String(path[s_idx].get("edgeId", ""))
		if sim.road_map.has(eid):
			return int(sim.road_map[eid].get("layer", 0)) > 0
	return false

static func _xform_truck_poly(center: Vector2, fwd: Vector2, side: Vector2, sc: float, pts_orig: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts_orig.size())
	for i in range(pts_orig.size()):
		var p: Vector2 = pts_orig[i]
		out[i] = center + fwd * (p.x * sc) + side * (p.y * sc)
	return out

static func _append_keylined_hull(batch: TriBatch2D, poly: PackedVector2Array, fill_col: Color, uv_scale: float = 0.72) -> void:
	batch.add_uv_keyline_poly(poly, TRUCK_INK, uv_scale)
	batch.add_polygon_safe(poly, fill_col)

func _rebuild_trucks_batches() -> void:
	_truck_batch.clear()
	_truck_ghost_batch.clear()
	if sim == null or camera == null:
		return
	var frustum: Rect2 = get_world_frustum()
	var blink_phase: bool = fmod(float(Time.get_ticks_msec()) * 0.0036, 1.0) < 0.55

	for ag in sim.agents:
		var st := String(ag.get("state", ""))
		if st not in ["driving_outbound", "driving_return", "driving_to_depot", "driving_from_depot", "at_depot", "entering_lot", "leaving_lot", "queuing_bay", "loading", "unloading"]:
			continue
		# Indoor garage bays (`bayIndex >= 4`, stalls `5..8`) tuck inside the building portal while docked
		if (st == "loading" or st == "unloading") and int(ag.get("bayIndex", 0)) >= 4:
			continue
		var ap: Vector2 = ag["pos"]
		if not frustum.has_point(ap):
			continue
		var under_hidden_flyover: bool = _is_agent_under_hidden_flyover(ag)
		var rtid := String(ag.get("routeId", ""))
		var route_hidden: bool = (overlay_mode == "routes" and hidden_route_ids.has(rtid))
		var is_ghost: bool = under_hidden_flyover or route_hidden
		var target_batch: TriBatch2D = _truck_ghost_batch if is_ghost else _truck_batch
		_append_truck_to_batch(target_batch, ag, blink_phase, is_ghost)

func _append_truck_to_batch(batch: TriBatch2D, ag: Dictionary, blink_phase: bool, is_ghost: bool) -> void:
	var m_id := String(ag.get("model", "hauler"))
	if not GameCatalog.TRUCKS.has(m_id):
		m_id = "hauler"
	var tdef: Dictionary = GameCatalog.TRUCKS[m_id]
	var units: Array[Dictionary] = GameCatalog.get_truck_units(m_id)
	var uposes: Array = ag.get("unitPoses", [])
	if uposes.size() != units.size():
		uposes = SimEngine._make_initial_unit_poses(m_id, ag["pos"], float(ag.get("heading", 0.0)))

	var rtid := String(ag.get("routeId", ""))
	var rt: Dictionary = sim.get_route(rtid)
	var cab_col: Color = rt.get("color", tdef["color"]) as Color
	var sc: float = GameCatalog.TRUCK_VIEW_SCALE

	var c_good := String(ag.get("cargoGood", ""))
	var c_qty: int = int(ag.get("cargoQty", 0))
	var has_cargo: bool = c_good != "" and c_qty > 0 and GameCatalog.GOODS.has(c_good)
	var g_slots: int = int(GameCatalog.GOODS[c_good]["slots"]) if has_cargo else 1
	var any_sz: bool = bool(tdef["any_size_per_trailer"])
	var exp_bonus_left: float = sim.get_agent_express_bonus_left(ag)
	var is_braking: bool = bool(ag.get("braking", false))
	var turn_sig: int = int(ag.get("turnSignal", 0))
	var blink_on: bool = (turn_sig != 0) and blink_phase and not is_ghost

	# Precompute per-trailer cargo unit distribution front-to-back (matching TruckModel.units)
	var units_per_tr: Array[int] = []
	var rem_units: int = c_qty
	for ui in range(1, units.size()):
		var sl_cap: int = int(units[ui]["slots"])
		var fit_max: int = 1 if any_sz else maxi(1, sl_cap / maxi(1, g_slots))
		var put: int = mini(rem_units, fit_max) if has_cargo else 0
		units_per_tr.append(put)
		rem_units = maxi(0, rem_units - put)

	# 1. Draw coupling drawbars first so hulls sit cleanly over hitches
	for ui in range(units.size() - 1, 0, -1):
		var cur_pose: Dictionary = uposes[ui]
		var prev_pose: Dictionary = uposes[ui - 1]
		var u_cur: Dictionary = units[ui]
		var u_prev: Dictionary = units[ui - 1]
		var cur_hl: float = (float(u_cur["rear"]) - float(u_cur["front"])) * 0.5 * sc
		var prev_hl: float = (float(u_prev["rear"]) - float(u_prev["front"])) * 0.5 * sc
		var cur_fwd := Vector2(cos(float(cur_pose["heading"])), sin(float(cur_pose["heading"])))
		var prev_fwd := Vector2(cos(float(prev_pose["heading"])), sin(float(prev_pose["heading"])))
		var hitch_front: Vector2 = (cur_pose["pos"] as Vector2) + cur_fwd * (cur_hl - 0.35)
		var hitch_rear: Vector2 = (prev_pose["pos"] as Vector2) - prev_fwd * (prev_hl - 0.35)
		batch.add_thick_line(hitch_front, hitch_rear, 1.35, TRUCK_INK)

	# 2. Draw trailers back-to-front so articulated overlaps layer authentically
	for ui in range(units.size() - 1, 0, -1):
		var tr_idx: int = ui - 1
		var up: Dictionary = uposes[ui]
		var tp: Vector2 = up["pos"]
		var tang: float = float(up["heading"])
		var tr_fwd := Vector2(cos(tang), sin(tang))
		var tr_side := Vector2(-tr_fwd.y, tr_fwd.x)
		var u_len_orig: float = float(units[ui]["rear"]) - float(units[ui]["front"])
		var hl: float = u_len_orig * 0.5

		if m_id == "lowloader":
			# Heavy bolstered flatbed deck (`#ECEEEA`) + side stake pockets
			var deck_poly := _xform_truck_poly(tp, tr_fwd, tr_side, sc, [
				Vector2(-hl, -8.2), Vector2(hl - 1.4, -8.2), Vector2(hl, -6.8),
				Vector2(hl, 6.8), Vector2(hl - 1.4, 8.2), Vector2(-hl, 8.2)
			])
			_append_keylined_hull(batch, deck_poly, TRUCK_TILE, 0.72)
			batch.add_rect_rot(tp + tr_side * (7.2 * sc), (u_len_orig - 3.0) * sc, 1.3 * sc, tang, cab_col.darkened(0.12))
			batch.add_rect_rot(tp - tr_side * (7.2 * sc), (u_len_orig - 3.0) * sc, 1.3 * sc, tang, cab_col.darkened(0.12))
			for bx in [-6.5, 0.0, 6.5]:
				batch.add_rect_rot(tp + tr_fwd * (bx * sc) + tr_side * (7.5 * sc), 1.8 * sc, 1.8 * sc, tang, TRUCK_INK)
				batch.add_rect_rot(tp + tr_fwd * (bx * sc) - tr_side * (7.5 * sc), 1.8 * sc, 1.8 * sc, tang, TRUCK_INK)
		elif m_id == "bulker":
			# Mineral hopper outer hull (`cab_col`) + recessed `TRUCK_HOPPER_WELL` (`#B4B9B3`)
			var hop_poly := _xform_truck_poly(tp, tr_fwd, tr_side, sc, [
				Vector2(-hl + 1.8, -9.4), Vector2(hl - 1.8, -9.4), Vector2(hl, -7.6),
				Vector2(hl, 7.6), Vector2(hl - 1.8, 9.4), Vector2(-hl + 1.8, 9.4),
				Vector2(-hl, 7.6), Vector2(-hl, -7.6)
			])
			_append_keylined_hull(batch, hop_poly, cab_col, 0.72)
			var well_rim := _xform_truck_poly(tp, tr_fwd, tr_side, sc, [
				Vector2(-hl + 3.6, -7.2), Vector2(hl - 3.6, -7.2),
				Vector2(hl - 3.6, 7.2), Vector2(-hl + 3.6, 7.2)
			])
			batch.add_polygon_safe(well_rim, TRUCK_INK.lightened(0.12))
			var well_in := _xform_truck_poly(tp, tr_fwd, tr_side, sc, [
				Vector2(-hl + 4.8, -6.2), Vector2(hl - 4.8, -6.2),
				Vector2(hl - 4.8, 6.2), Vector2(-hl + 4.8, 6.2)
			])
			batch.add_polygon_safe(well_in, TRUCK_HOPPER_WELL)
		else:
			# Standard `TRUCK_PAPER` (`#F6F5EF`) cargo trailer + route-color headboard
			var box_poly := _xform_truck_poly(tp, tr_fwd, tr_side, sc, [
				Vector2(-hl + 1.4, -9.2), Vector2(hl - 1.4, -9.2), Vector2(hl, -7.8),
				Vector2(hl, 7.8), Vector2(hl - 1.4, 9.2), Vector2(-hl + 1.4, 9.2),
				Vector2(-hl, 7.8), Vector2(-hl, -7.8)
			])
			_append_keylined_hull(batch, box_poly, TRUCK_PAPER, 0.72)
			batch.add_rect_rot(tp + tr_fwd * ((hl - 2.0) * sc), 2.4 * sc, 15.6 * sc, tang, cab_col)

		# Cargo ShapeGlyphs on trailer (`ShapeGlyphs.add_keylined` + `centered_offset`)
		var u_here: int = units_per_tr[tr_idx]
		if u_here > 0 and has_cargo:
			var g_ang: float = tang + ShapeGlyphs.truck_angle(c_good)
			if m_id == "bulker":
				var hop_offsets := [Vector2(9.2, -1.2), Vector2(0.0, 1.3), Vector2(-9.2, -0.9)]
				for bi in range(mini(u_here, 3)):
					var ho: Vector2 = hop_offsets[bi]
					var c_pt: Vector2 = tp + tr_fwd * (ho.x * sc) + tr_side * (ho.y * sc)
					ShapeGlyphs.add_keylined(batch, c_good, c_pt, 14.2 * sc, g_ang, Transform2D.IDENTITY, TRUCK_INK, colorblind_mode, true)
			elif m_id == "lowloader":
				var sz_ll: float = (21.5 if g_slots >= 2 else 17.5) * sc
				var c_ll: Vector2 = ShapeGlyphs.centered_offset(c_good, tp, sz_ll, g_slots, g_ang)
				ShapeGlyphs.add_keylined(batch, c_good, c_ll, sz_ll, g_ang, Transform2D.IDENTITY, TRUCK_INK, colorblind_mode, true)
			elif g_slots >= 2:
				var sz_lg: float = 22.0 * sc
				var c_lg: Vector2 = ShapeGlyphs.centered_offset(c_good, tp, sz_lg, 2, g_ang)
				ShapeGlyphs.add_keylined(batch, c_good, c_lg, sz_lg, g_ang, Transform2D.IDENTITY, TRUCK_INK, colorblind_mode, true)
			else:
				for si in range(mini(u_here, 2)):
					var slot_lx: float = 8.4 if si == 0 else -8.4
					var c_sm: Vector2 = tp + tr_fwd * (slot_lx * sc)
					ShapeGlyphs.add_keylined(batch, c_good, c_sm, 16.4 * sc, g_ang, Transform2D.IDENTITY, TRUCK_INK, colorblind_mode, true)

		# Authentic Express shrinking bonus bar along trailer flank
		if m_id == "express" and tr_idx == 0 and exp_bonus_left >= 0.0:
			var bar_len: float = (u_len_orig - 5.0) * sc
			var bar_c: Vector2 = tp - tr_side * (8.6 * sc)
			batch.add_rect_rot(bar_c, bar_len + 0.7, 1.18, tang, TRUCK_INK)
			if exp_bonus_left > 0.02:
				var fill_l: float = bar_len * clampf(exp_bonus_left, 0.0, 1.0)
				var fill_c: Vector2 = bar_c - tr_fwd * ((bar_len - fill_l) * 0.5)
				var exp_col := Color("FFD43B") if float(ag.get("expressBonusLocked", -1.0)) >= 0.0 else TRUCK_PAPER
				batch.add_rect_rot(fill_c, fill_l, 0.76, tang, exp_col)

		# Tail trailer brake lamps (`TRUCK_BRAKE_ON` / `TRUCK_BRAKE_OFF`) + rear turn blinker (`TRUCK_BLINKER`)
		if ui == units.size() - 1:
			var lamp_col: Color = TRUCK_BRAKE_ON if is_braking else TRUCK_BRAKE_OFF
			var rear_x: float = (-hl + 1.1) * sc
			batch.add_rect_rot(tp + tr_fwd * rear_x - tr_side * (6.2 * sc), 1.6 * sc, 2.8 * sc, tang, lamp_col)
			batch.add_rect_rot(tp + tr_fwd * rear_x + tr_side * (6.2 * sc), 1.6 * sc, 2.8 * sc, tang, lamp_col)
			if blink_on:
				var b_lat: float = (-7.8 if turn_sig < 0 else 7.8) * sc
				batch.add_circle(tp + tr_fwd * rear_x + tr_side * b_lat, 1.02, TRUCK_BLINKER, 8)

	# 3. Draw distinctive tractor cab (`unit[0]`) for each of the 5 models
	var cab_pose: Dictionary = uposes[0]
	var cab_pos: Vector2 = cab_pose["pos"]
	var cab_ang: float = float(cab_pose["heading"])
	var cab_fwd := Vector2(cos(cab_ang), sin(cab_ang))
	var cab_side := Vector2(-cab_fwd.y, cab_fwd.x)
	var cab_hl: float = (float(units[0]["rear"]) - float(units[0]["front"])) * 0.5

	if m_id == "lowloader":
		# Long-nose conventional prime mover + twin chrome exhaust stacks + front grille
		var ll_cab := _xform_truck_poly(cab_pos, cab_fwd, cab_side, sc, [
			Vector2(-cab_hl, -9.6), Vector2(1.5, -9.6), Vector2(3.0, -6.6),
			Vector2(cab_hl - 0.8, -6.2), Vector2(cab_hl, -4.4), Vector2(cab_hl, 4.4),
			Vector2(cab_hl - 0.8, 6.2), Vector2(3.0, 6.6), Vector2(1.5, 9.6), Vector2(-cab_hl, 9.6)
		])
		_append_keylined_hull(batch, ll_cab, cab_col, 0.72)
		batch.add_rect_rot(cab_pos + cab_fwd * (0.8 * sc), 3.6 * sc, 14.8 * sc, cab_ang, TRUCK_GLASS)
		batch.add_rect_rot(cab_pos + cab_fwd * ((cab_hl - 1.1) * sc), 1.8 * sc, 8.6 * sc, cab_ang, TRUCK_CHROME)
		batch.add_circle(cab_pos - cab_fwd * (2.6 * sc) - cab_side * (8.2 * sc), 1.8 * sc, TRUCK_CHROME, 8)
		batch.add_circle(cab_pos - cab_fwd * (2.6 * sc) + cab_side * (8.2 * sc), 1.8 * sc, TRUCK_CHROME, 8)
	elif m_id == "express":
		# Wedge bullet nose + swept visor glass + white V-chevron roof stripe
		var ex_cab := _xform_truck_poly(cab_pos, cab_fwd, cab_side, sc, [
			Vector2(-cab_hl, -9.0), Vector2(4.2, -9.0), Vector2(cab_hl, -5.0),
			Vector2(cab_hl, 5.0), Vector2(4.2, 9.0), Vector2(-cab_hl, 9.0)
		])
		_append_keylined_hull(batch, ex_cab, cab_col, 0.72)
		var ex_glass := _xform_truck_poly(cab_pos, cab_fwd, cab_side, sc, [
			Vector2(2.6, -7.2), Vector2(8.4, -4.2), Vector2(8.4, 4.2), Vector2(2.6, 7.2)
		])
		batch.add_polygon_safe(ex_glass, TRUCK_GLASS)
		var ex_chev := _xform_truck_poly(cab_pos, cab_fwd, cab_side, sc, [
			Vector2(-8.6, -5.8), Vector2(-1.6, 0.0), Vector2(-8.6, 5.8),
			Vector2(-5.2, 5.8), Vector2(1.8, 0.0), Vector2(-5.2, -5.8)
		])
		batch.add_polygon_safe(ex_chev, TRUCK_PAPER)
	elif m_id == "freighter":
		# Heavy cab-over + split twin windshields + roof wind deflector
		var fr_cab := _xform_truck_poly(cab_pos, cab_fwd, cab_side, sc, [
			Vector2(-cab_hl, -9.5), Vector2(cab_hl - 2.8, -9.5), Vector2(cab_hl, -6.8),
			Vector2(cab_hl, 6.8), Vector2(cab_hl - 2.8, 9.5), Vector2(-cab_hl, 9.5)
		])
		_append_keylined_hull(batch, fr_cab, cab_col, 0.72)
		batch.add_rect_rot(cab_pos + cab_fwd * (6.2 * sc) - cab_side * (4.3 * sc), 4.0 * sc, 6.8 * sc, cab_ang, TRUCK_GLASS)
		batch.add_rect_rot(cab_pos + cab_fwd * (6.2 * sc) + cab_side * (4.3 * sc), 4.0 * sc, 6.8 * sc, cab_ang, TRUCK_GLASS)
		var defl := _xform_truck_poly(cab_pos, cab_fwd, cab_side, sc, [
			Vector2(-8.8, -6.8), Vector2(1.2, -5.2), Vector2(1.2, 5.2), Vector2(-8.8, 6.8)
		])
		batch.add_polygon_safe(defl, cab_col.lightened(0.20))
	elif m_id == "bulker":
		# Rugged quarry tractor + chrome rear headache rack
		var bk_cab := _xform_truck_poly(cab_pos, cab_fwd, cab_side, sc, [
			Vector2(-cab_hl, -9.4), Vector2(cab_hl - 3.0, -9.4), Vector2(cab_hl, -6.6),
			Vector2(cab_hl, 6.6), Vector2(cab_hl - 3.0, 9.4), Vector2(-cab_hl, 9.4)
		])
		_append_keylined_hull(batch, bk_cab, cab_col, 0.72)
		batch.add_rect_rot(cab_pos + cab_fwd * (6.0 * sc), 4.2 * sc, 14.2 * sc, cab_ang, TRUCK_GLASS)
		batch.add_rect_rot(cab_pos - cab_fwd * ((cab_hl - 1.5) * sc), 2.2 * sc, 18.0 * sc, cab_ang, TRUCK_CHROME)
	else:
		# Hauler nimble cab-over + panoramic windshield
		var hl_cab := _xform_truck_poly(cab_pos, cab_fwd, cab_side, sc, [
			Vector2(-cab_hl, -9.1), Vector2(cab_hl - 3.2, -9.1), Vector2(cab_hl, -6.4),
			Vector2(cab_hl, 6.4), Vector2(cab_hl - 3.2, 9.1), Vector2(-cab_hl, 9.1)
		])
		_append_keylined_hull(batch, hl_cab, cab_col, 0.72)
		batch.add_rect_rot(cab_pos + cab_fwd * (6.0 * sc), 4.2 * sc, 13.8 * sc, cab_ang, TRUCK_GLASS)

	# Front headlamps & front turn blinker
	var hl_lat: float = (4.2 if m_id == "lowloader" else 5.4) * sc
	batch.add_rect_rot(cab_pos + cab_fwd * ((cab_hl - 0.8) * sc) - cab_side * hl_lat, 1.4 * sc, 2.4 * sc, cab_ang, TRUCK_HEADLAMP)
	batch.add_rect_rot(cab_pos + cab_fwd * ((cab_hl - 0.8) * sc) + cab_side * hl_lat, 1.4 * sc, 2.4 * sc, cab_ang, TRUCK_HEADLAMP)
	if blink_on:
		var f_lat: float = (-7.6 if turn_sig < 0 else 7.6) * sc
		batch.add_circle(cab_pos + cab_fwd * ((cab_hl - 1.4) * sc) + cab_side * f_lat, 1.02, TRUCK_BLINKER, 8)


class _StaticBatchLayer extends Node2D:
	var batch: TriBatch2D

	func _draw() -> void:
		if batch != null and not batch.is_empty():
			RenderingServer.canvas_item_add_triangle_array(
				get_canvas_item(), batch.indices, batch.verts, batch.colors, batch.uvs
			)


class _MeshBatchLayer extends Node2D:
	var mesh: ArrayMesh

	func _draw() -> void:
		if mesh != null and mesh.get_surface_count() > 0:
			draw_mesh(mesh, null)


class _WorldUnderlayDrawer extends Node2D:
	## Drawn BELOW `_truck_ghost_node` and `_truck_node` so active trucks stay bright above
	## the Update 1.10 map wash while concrete storage beds, trains/ships, and route lines sit underneath!
	var owner_view: MapView25D

	func _draw() -> void:
		if owner_view == null or owner_view.sim == null:
			return
		var sim: SimEngine = owner_view.sim
		var frustum: Rect2 = owner_view.get_world_frustum()
		var zoom_x: float = owner_view.camera.zoom.x
		var font: Font = owner_view._ui_font if owner_view._ui_font != null else ThemeDB.fallback_font
		var cb: bool = owner_view.colorblind_mode
		var is_dark: bool = owner_view.dark_theme or sim.night_mode

		# 1. Starter Town Depot Roof Truck Emblem (`depot.gd`)
		if not sim.depot.is_empty():
			var d_pos: Vector2 = sim.depot.get("pos", Vector2.ZERO)
			if frustum.has_point(d_pos):
				draw_circle(d_pos, 4.4, Color("F7F6F1"))
				draw_arc(d_pos, 4.4, 0.0, TAU, 20, Color("355F9C"), 1.1, true)
				draw_rect(Rect2(d_pos + Vector2(-2.6, -1.3), Vector2(3.4, 2.4)), Color("355F9C"), true)
				draw_rect(Rect2(d_pos + Vector2(1.0, -0.8), Vector2(1.7, 1.9)), Color("355F9C"), true)

		# 2. Concrete Storage Pad ShapeGlyphs (`factory_look.gd`: 22% watermark when empty, Lv0..Lv4 grids when stocked)
		for f in sim.facilities:
			if not sim.unlocked_regions.has(int(f["regionIndex"])):
				continue
			var fp: Vector2 = f["pos"]
			if not frustum.has_point(fp):
				continue
			for pad in sim.get_facility_storage_pads(f):
				_draw_storage_pad_contents(pad, cb, is_dark)

			var fk := String(f["kind"])
			if fk == "station" and sim.transport.rail_lines.is_empty() and bool(f["vehiclePresent"]):
				_draw_docked_train(f, cb)
			elif fk == "harbour" and sim.transport.ship_channels.is_empty() and bool(f["vehiclePresent"]):
				_draw_docked_ship(f, cb)

		# 2b. Active `ShipService` + River Barges + Movable 2.5D `BasculeBridges` + Active `TrainService`!
		_draw_active_maritime_and_bridges(sim, frustum, cb, is_dark)
		_draw_active_trains(sim, frustum, cb)

		# 3. Selected Road / Junction / Facility Highlights
		if owner_view.selected_road_id != "" and sim.road_map.has(owner_view.selected_road_id):
			var sr: Dictionary = sim.road_map[owner_view.selected_road_id]
			var sr_w: float = float(sr.get("widthPx", 14.0)) + 5.5
			draw_polyline(sr["pts"], Color(0.35, 0.58, 0.88, 0.45), sr_w, true)

		if owner_view.selected_junction_id != "" and sim.junction_map.has(owner_view.selected_junction_id):
			var sj: Dictionary = sim.junction_map[owner_view.selected_junction_id]
			_draw_selected_junction_bands_and_ring(sj, sim)

		if owner_view.selected_facility_id != "" and sim.facility_map.has(owner_view.selected_facility_id):
			var sf: Dictionary = sim.facility_map[owner_view.selected_facility_id]
			draw_arc(sf["pos"], 24.0, 0.0, TAU, 32, Color("F4C64A"), 3.4, true)
			_draw_facility_routes_highlight(sim, owner_view.selected_facility_id, frustum)

		if owner_view.route_draft_from_id != "" and sim.facility_map.has(owner_view.route_draft_from_id):
			var df: Dictionary = sim.facility_map[owner_view.route_draft_from_id]
			var pulse: float = 22.0 + 4.0 * sin(Time.get_ticks_msec() * 0.008)
			draw_arc(df["pos"], pulse, 0.0, TAU, 28, GameCatalog.status_color("good", cb), 3.4, true)

		# 4. Five Analytic Map Overlays + Authentic Update 1.10 Soft Map Wash!
		var mode := owner_view.overlay_mode
		if mode != "none":
			var wash_col := Color(0.09, 0.11, 0.15, 0.58) if is_dark else Color(0.95, 0.94, 0.90, 0.56)
			draw_rect(frustum, wash_col, true)
			if mode == "routes":
				_draw_routes_overlay(sim, font, frustum)
			elif mode == "traffic":
				_draw_traffic_heatmap(sim, frustum, cb)
			elif mode == "flow":
				_draw_goods_flow_sankey(sim, font, frustum, cb)
			elif mode == "buildings":
				_draw_buildings_overlay(sim, frustum, cb)
			elif mode == "demand":
				_draw_demand_overlay(sim, font, zoom_x, cb)
		elif owner_view.selected_route_id != "":
			_draw_single_route(sim, font, owner_view.selected_route_id, frustum)

		# 5. Authentic `RouteBreakMarks` (`#FBFAF6` halo + `#C8323A` fault road dashes)
		if mode == "none" or mode == "routes":
			_draw_route_break_roads(sim, frustum)

		# 6. Multi-Phase Corner Traffic Light Signal Heads
		for j in sim.junctions:
			if String(j["control"]) != "lights" or not j.has("light"):
				continue
			if not sim.unlocked_regions.has(int(j["regionIndex"])):
				continue
			var jp: Vector2 = j["pos"]
			if not frustum.has_point(jp):
				continue
			var geom_j: Dictionary = j.get("geom", {})
			var arms_j: Array = geom_j.get("arms", [])
			for a in arms_j:
				if not bool(a["can_enter"]):
					continue
				var eid_a := String(a["edge_id"])
				var sig_state: String = sim.get_arm_signal_state(j, eid_a)
				var lens_col: Color
				if sig_state == "green":
					lens_col = Color("3B9EFF") if cb else Color("4FB35E")
				elif sig_state == "yellow":
					lens_col = Color("F2AB37")
				else:
					lens_col = Color("AE3EC9") if cb else Color("D4383B")

				var p_th: Vector2 = a["throat_pos"]
				var in_dir: Vector2 = -(a["throat_out_dir"] as Vector2)
				var in_right := Vector2(-in_dir.y, in_dir.x)
				var hw_a: float = float(a["hw"])
				var curb_side: float = -(hw_a + 3.1) if sim.left_hand_traffic else (hw_a + 3.1)
				var sig_pos: Vector2 = p_th - in_dir * 1.4 + in_right * curb_side
				draw_circle(sig_pos + Vector2(0.5, 0.8), 3.6, Color(0, 0, 0, 0.22))
				draw_circle(sig_pos, 3.6, Color("23242B"))
				draw_circle(sig_pos, 2.45, lens_col)

		# 7. Night Headlight Cones ahead of active driving trucks
		if owner_view._night_blend > 0.12:
			for ag in sim.agents:
				var st := String(ag.get("state", ""))
				if st not in ["driving_outbound", "driving_return", "driving_to_depot", "driving_from_depot"]:
					continue
				if owner_view.overlay_mode == "routes" and owner_view.hidden_route_ids.has(String(ag["routeId"])):
					continue
				var cab_pos: Vector2 = ag["pos"]
				if not frustum.has_point(cab_pos):
					continue
				var ang: float = float(ag["heading"])
				var fwd := Vector2(cos(ang), sin(ang))
				var side := Vector2(-fwd.y, fwd.x)
				draw_colored_polygon(PackedVector2Array([
					cab_pos + fwd * 2.8,
					cab_pos + fwd * 27.0 + side * 9.8,
					cab_pos + fwd * 27.0 - side * 9.8
				]), Color(1.0, 0.95, 0.72, 0.24 * owner_view._night_blend))

	static func _pad_grid_dims(buf_lv: int, is_large: bool) -> Vector2i:
		match clampi(buf_lv, 0, 4):
			0:
				return Vector2i(2, 1) if is_large else Vector2i(2, 2)
			1:
				return Vector2i(2, 2) if is_large else Vector2i(4, 2)
			2:
				return Vector2i(3, 3) if is_large else Vector2i(5, 3)
			3:
				return Vector2i(3, 5) if is_large else Vector2i(6, 5)
			_:
				return Vector2i(3, 10) if is_large else Vector2i(6, 10)

	func _draw_storage_pad_contents(pad: Dictionary, cb: bool, is_dark: bool) -> void:
		var p_pos: Vector2 = pad["pos"]
		var p_sz: Vector2 = pad["size"]
		var role := String(pad["role"])
		var cnt: int = int(pad["count"])
		var buf_lv: int = int(pad["buffer_lv"])

		if role == "yard":
			var items: Array = pad["items"]
			if items.is_empty():
				var wm_col := Color(0.86, 0.88, 0.92, 0.20) if is_dark else Color(0.18, 0.20, 0.26, 0.20)
				ShapeGlyphs.draw_tinted(self, "block", p_pos, minf(p_sz.x, p_sz.y) * 0.56, wm_col)
				return
			var dims_y: Vector2i = _pad_grid_dims(buf_lv, false)
			var cols_y: int = dims_y.x
			var rows_y: int = dims_y.y
			var cell_w_y: float = (p_sz.x - 1.8) / float(cols_y)
			var cell_h_y: float = (p_sz.y - 1.4) / float(rows_y)
			var g_sz_y: float = clampf(minf(cell_w_y, cell_h_y) * 0.88, 1.5, 4.1)
			var show_y: int = mini(items.size(), cols_y * rows_y)
			for idx in range(show_y):
				var iy_g := String(items[idx])
				if not GameCatalog.GOODS.has(iy_g):
					continue
				var cx_i: int = idx % cols_y
				var cy_i: int = idx / cols_y
				var cell_c := Vector2(
					p_pos.x - (p_sz.x - 1.8) * 0.5 + (float(cx_i) + 0.5) * cell_w_y,
					p_pos.y - (p_sz.y - 1.4) * 0.5 + (float(cy_i) + 0.5) * cell_h_y
				)
				ShapeGlyphs.draw(self, iy_g, cell_c, g_sz_y, 0.0, MapView25D.TRUCK_INK, 0.42, Transform2D.IDENTITY, cb)
			return

		var gid := String(pad["good"])
		if gid == "" or not GameCatalog.GOODS.has(gid):
			return
		var is_large: bool = int(GameCatalog.GOODS[gid]["slots"]) >= 2
		if cnt <= 0:
			var wm_col2 := Color(0.86, 0.88, 0.92, 0.22) if is_dark else Color(0.18, 0.20, 0.26, 0.22)
			ShapeGlyphs.draw_tinted(self, gid, p_pos, minf(p_sz.x, p_sz.y) * 0.66, wm_col2)
			return

		var dims: Vector2i = _pad_grid_dims(buf_lv, is_large)
		var cols: int = dims.x
		var rows: int = dims.y
		var inner_w: float = maxf(2.0, p_sz.x - 1.8)
		var inner_h: float = maxf(2.0, p_sz.y - 1.4)
		var cell_w: float = inner_w / float(cols)
		var cell_h: float = inner_h / float(rows)
		var glyph_sz: float = clampf(minf(cell_w, cell_h) * (0.94 if is_large else 0.86), 1.4, 4.6)
		var show_n: int = mini(cnt, cols * rows)
		for i in range(show_n):
			var c_x: int = i % cols
			var c_y: int = i / cols
			var c_pt := Vector2(
				p_pos.x - inner_w * 0.5 + (float(c_x) + 0.5) * cell_w,
				p_pos.y - inner_h * 0.5 + (float(c_y) + 0.5) * cell_h
			)
			var adj_pt: Vector2 = ShapeGlyphs.centered_offset(gid, c_pt, glyph_sz, 2 if is_large else 1, 0.0)
			ShapeGlyphs.draw(self, gid, adj_pt, glyph_sz, 0.0, MapView25D.TRUCK_INK, 0.42, Transform2D.IDENTITY, cb)

	func _draw_docked_train(f: Dictionary, cb: bool) -> void:
		var fp: Vector2 = f["pos"]
		var up: Dictionary = f.get("upgrades", {})
		var tr_lv: int = clampi(int(up.get("trainLength", 0)), 0, 3)
		var n_wagons: int = 2 + tr_lv
		var wag_w: float = 10.6
		var wag_gap: float = 1.4
		var total_w: float = float(n_wagons) * wag_w + float(n_wagons) * wag_gap + 9.2
		var base_x: float = fp.x - total_w * 0.5
		var ty: float = fp.y + 13.0

		# Rail sleeper bed
		draw_line(Vector2(base_x - 4.0, ty + 3.2), Vector2(base_x + total_w + 4.0, ty + 3.2), Color("59564F"), 5.6)
		# Locomotive head on left
		var loco_r := Rect2(Vector2(base_x, ty), Vector2(9.2, 6.4))
		draw_rect(loco_r.grow(0.6), MapView25D.TRUCK_INK, true)
		draw_rect(loco_r, Color("F4C64A"), true)
		draw_rect(Rect2(loco_r.position + Vector2(1.2, 1.1), Vector2(2.6, 4.2)), MapView25D.TRUCK_GLASS, true)

		var vcargo: Array = f.get("vehicleCargo", [])
		for wi in range(n_wagons):
			var wx: float = base_x + 9.2 + wag_gap + float(wi) * (wag_w + wag_gap)
			draw_line(Vector2(wx - wag_gap, ty + 3.2), Vector2(wx, ty + 3.2), MapView25D.TRUCK_INK, 1.6)
			var wr := Rect2(Vector2(wx, ty + 0.3), Vector2(wag_w, 5.8))
			draw_rect(wr.grow(0.55), MapView25D.TRUCK_INK, true)
			draw_rect(wr, MapView25D.TRUCK_PAPER, true)
			draw_rect(Rect2(wr.position, Vector2(1.5, wr.size.y)), Color("3B6E8C"), true)
			for s in range(2):
				var c_idx: int = wi * 2 + s
				if c_idx < vcargo.size():
					var cg := String(vcargo[c_idx])
					if GameCatalog.GOODS.has(cg):
						var gpos := Vector2(wx + 3.3 + float(s) * 4.4, ty + 3.2)
						ShapeGlyphs.draw(self, cg, gpos, 3.6, ShapeGlyphs.truck_angle(cg), MapView25D.TRUCK_INK, 0.4, Transform2D.IDENTITY, cb)

	func _draw_docked_ship(f: Dictionary, cb: bool) -> void:
		var fp: Vector2 = f["pos"]
		var up: Dictionary = f.get("upgrades", {})
		var sh_lv: int = clampi(int(up.get("shipSize", 0)), 0, 3)
		var half_l: float = 22.0 + float(sh_lv) * 3.8
		var sc_c: Vector2 = fp + Vector2(2.0, 18.5)

		var hull := PackedVector2Array([
			sc_c + Vector2(-half_l, -4.2),
			sc_c + Vector2(half_l - 5.5, -4.2),
			sc_c + Vector2(half_l + 2.5, 0.0),
			sc_c + Vector2(half_l - 5.5, 4.2),
			sc_c + Vector2(-half_l, 4.2)
		])
		draw_colored_polygon(PackedVector2Array([
			hull[0] + Vector2(-0.8, -0.8), hull[1] + Vector2(0.5, -0.8),
			hull[2] + Vector2(1.0, 0.0), hull[3] + Vector2(0.5, 0.8), hull[4] + Vector2(-0.8, 0.8)
		]), MapView25D.TRUCK_INK)
		draw_colored_polygon(hull, Color("2F5D8A"))
		# Stern bridge superstructure
		var br := Rect2(sc_c + Vector2(-half_l + 2.2, -3.3), Vector2(7.6, 6.6))
		draw_rect(br.grow(0.5), MapView25D.TRUCK_INK, true)
		draw_rect(br, Color("FAF7EE"), true)
		draw_rect(Rect2(br.position + Vector2(4.6, 0.8), Vector2(2.0, 5.0)), Color("E8792F"), true)

		# Open cargo hold hatch + loaded `vehicleCargo` ShapeGlyphs
		var hold_r := Rect2(sc_c + Vector2(-half_l + 11.2, -3.1), Vector2(maxf(12.0, half_l * 2.0 - 19.5), 6.2))
		draw_rect(hold_r, Color("1E3B58"), true)
		var vcargo: Array = f.get("vehicleCargo", [])
		var cols_h: int = maxi(3, int(floor(hold_r.size.x / 4.2)))
		var show_h: int = mini(vcargo.size(), cols_h * 2)
		for hi in range(show_h):
			var cg := String(vcargo[hi])
			if not GameCatalog.GOODS.has(cg):
				continue
			var hx: int = hi % cols_h
			var hy: int = hi / cols_h
			var hp := Vector2(
				hold_r.position.x + (float(hx) + 0.5) * (hold_r.size.x / float(cols_h)),
				hold_r.position.y + (1.7 if show_h > cols_h else 3.1) + float(hy) * 2.9
			)
			ShapeGlyphs.draw(self, cg, hp, 3.2, 0.0, MapView25D.TRUCK_INK, 0.38, Transform2D.IDENTITY, cb)

	func _draw_active_maritime_and_bridges(sim: SimEngine, frustum: Rect2, cb: bool, is_dark: bool) -> void:
		var cull_rect: Rect2 = frustum.grow(42.0)
		var water_cut_col := Color("3A6073") if is_dark else MapView25D.COL_WATER

		# 1. Movable Bascule Bridges: cut open water channel first when span is lifting (`lift > 0.04`)
		for bb in sim.transport.bascule_bridges:
			var bp: Vector2 = bb["pos"]
			if not cull_rect.has_point(bp):
				continue
			var lift: float = float(bb.get("lift", 0.0))
			if lift > 0.04:
				var rd_id := String(bb["roadId"])
				var rw_b: float = float(sim.road_map.get(rd_id, {}).get("widthPx", 12.0))
				var r_ang: float = float(bb["roadAngle"])
				var fwd := Vector2(cos(r_ang), sin(r_ang))
				var side := Vector2(-fwd.y, fwd.x)
				var hs: float = float(bb.get("spanHalfLen", 8.5))
				var cut_w: float = (rw_b + 5.6) * 0.5
				draw_colored_polygon(PackedVector2Array([
					bp - fwd * hs - side * cut_w,
					bp + fwd * hs - side * cut_w,
					bp + fwd * hs + side * cut_w,
					bp - fwd * hs + side * cut_w
				]), water_cut_col)

		# 2. Active Cargo Ships & River Barges (with expanding V-wakes + cargo holds)
		for ch in sim.transport.ship_channels:
			for v in ch.get("vessels", []):
				if String(v.get("state", "")) == "cooldown":
					continue
				var vp: Vector2 = v["pos"]
				if not cull_rect.has_point(vp):
					continue
				var vang: float = float(v["angle"])
				var vfwd := Vector2(cos(vang), sin(vang))
				var vside := Vector2(-vfwd.y, vfwd.x)
				var vlen: float = float(v.get("length", 24.0))
				var vw: float = float(v.get("width", 6.8))
				var hl: float = vlen * 0.5
				var hw: float = vw * 0.5
				var spd: float = float(v.get("speed", 0.0))

				# Expanding white V-wake behind stern when moving
				if spd > 1.2:
					var w_alpha: float = clampf(spd / 20.0, 0.12, 0.36) * (0.55 if is_dark else 1.0)
					var stern: Vector2 = vp - vfwd * (hl + 0.6)
					var wake_l: float = clampf(spd * 0.85, 6.0, 18.0)
					draw_line(stern - vside * (hw * 0.65), stern - vfwd * wake_l - vside * (hw * 2.1), Color(1, 1, 1, w_alpha), 1.35, true)
					draw_line(stern + vside * (hw * 0.65), stern - vfwd * wake_l + vside * (hw * 2.1), Color(1, 1, 1, w_alpha), 1.35, true)
					var ripple_t: float = fmod(float(v.get("wakePhase", 0.0)), 1.0)
					var rp: Vector2 = stern - vfwd * (wake_l * (0.25 + 0.55 * ripple_t))
					draw_line(rp - vside * hw, rp + vside * hw, Color(1, 1, 1, w_alpha * (1.0 - ripple_t)), 1.0, true)

				var is_ship: bool = String(v.get("kind", "")) == "cargo_ship"
				var bow_len: float = 5.4 if is_ship else 2.6
				var hull_col: Color = v.get("hullColor", Color("2C4E72"))
				var deck_col: Color = v.get("deckColor", Color("D8CFC0"))

				var out_hull := PackedVector2Array([
					vp - vfwd * (hl + 0.65) - vside * (hw + 0.65),
					vp + vfwd * (hl - bow_len + 0.4) - vside * (hw + 0.65),
					vp + vfwd * (hl + 1.1),
					vp + vfwd * (hl - bow_len + 0.4) + vside * (hw + 0.65),
					vp - vfwd * (hl + 0.65) + vside * (hw + 0.65)
				])
				var in_hull := PackedVector2Array([
					vp - vfwd * hl - vside * hw,
					vp + vfwd * (hl - bow_len) - vside * hw,
					vp + vfwd * (hl + 0.3),
					vp + vfwd * (hl - bow_len) + vside * hw,
					vp - vfwd * hl + vside * hw
				])
				draw_colored_polygon(out_hull, MapView25D.TRUCK_INK)
				draw_colored_polygon(in_hull, hull_col)

				# Stern bridge / wheelhouse
				var br_c: Vector2 = vp - vfwd * (hl - 3.2)
				var br_hl: float = 2.4 if is_ship else 1.8
				var br_hw: float = hw * 0.78
				draw_colored_polygon(PackedVector2Array([
					br_c - vfwd * br_hl - vside * br_hw,
					br_c + vfwd * br_hl - vside * br_hw,
					br_c + vfwd * br_hl + vside * br_hw,
					br_c - vfwd * br_hl + vside * br_hw
				]), Color("FAF7EE"))
				if is_ship:
					draw_circle(br_c + vfwd * 0.8, 1.25, Color("E8792F"))

				# Recessed cargo hold + ShapeGlyphs
				var hold_c: Vector2 = vp + vfwd * 1.4
				var hold_hl: float = maxf(3.8, hl - 4.8)
				var hold_hw: float = hw * 0.72
				draw_colored_polygon(PackedVector2Array([
					hold_c - vfwd * hold_hl - vside * hold_hw,
					hold_c + vfwd * hold_hl - vside * hold_hw,
					hold_c + vfwd * hold_hl + vside * hold_hw,
					hold_c - vfwd * hold_hl + vside * hold_hw
				]), deck_col.darkened(0.32) if is_ship else deck_col)

				var vcargo: Array = v.get("cargo", [])
				var cols_v: int = maxi(2, int(floor((hold_hl * 2.0) / 3.4)))
				var show_v: int = mini(vcargo.size(), cols_v * 2)
				for ci in range(show_v):
					var cg := String(vcargo[ci])
					if not GameCatalog.GOODS.has(cg):
						continue
					var cx_i: int = ci % cols_v
					var cy_i: int = ci / cols_v
					var lx: float = -hold_hl + (float(cx_i) + 0.5) * ((hold_hl * 2.0) / float(cols_v))
					var ly: float = ((-0.38 if cy_i == 0 else 0.38) * hold_hw * 2.0) if show_v > cols_v else 0.0
					var gp: Vector2 = hold_c + vfwd * lx + vside * ly
					ShapeGlyphs.draw(self, cg, gp, 2.9, vang, MapView25D.TRUCK_INK, 0.36, Transform2D.IDENTITY, cb)

		# 3. Movable Bascule Bridges: draw 2.5D twin lifting deck leaves & approach barriers over passing ships!
		for bb in sim.transport.bascule_bridges:
			var bp: Vector2 = bb["pos"]
			if not cull_rect.has_point(bp):
				continue
			var lift: float = float(bb.get("lift", 0.0))
			var b_down: float = float(bb.get("barrierDown", 0.0))
			if lift <= 0.01 and b_down <= 0.01:
				continue
			var rd_id := String(bb["roadId"])
			var rw_b: float = float(sim.road_map.get(rd_id, {}).get("widthPx", 12.0))
			var r_ang: float = float(bb["roadAngle"])
			var fwd := Vector2(cos(r_ang), sin(r_ang))
			var side := Vector2(-fwd.y, fwd.x)
			var hs: float = float(bb.get("spanHalfLen", 8.5))
			var deck_hw: float = rw_b * 0.5 + 1.4

			if lift > 0.01:
				var tilt_ang: float = lift * 1.12 # up to ~64° open bascule leaves!
				var proj_l: float = hs * cos(tilt_ang)
				var z_lift := Vector2(0.0, -hs * sin(tilt_ang) * 0.82)
				var leaf_col := Color("4A5060") if not is_dark else Color("343946")
				var rail_col := Color("F5F2EA") if not is_dark else Color("7A8294")

				for dir_s in [-1.0, 1.0]:
					var hinge: Vector2 = bp + fwd * (dir_s * hs)
					var tip: Vector2 = hinge - fwd * (dir_s * proj_l) + z_lift
					var leaf_poly := PackedVector2Array([
						hinge - side * deck_hw,
						tip - side * deck_hw,
						tip + side * deck_hw,
						hinge + side * deck_hw
					])
					draw_colored_polygon(leaf_poly, leaf_col)
					draw_line(hinge - side * deck_hw, tip - side * deck_hw, rail_col, 1.5, true)
					draw_line(hinge + side * deck_hw, tip + side * deck_hw, rail_col, 1.5, true)
					# Counterweight trunnion pier
					draw_circle(hinge - side * (deck_hw + 1.6), 2.1, Color("23242B"))
					draw_circle(hinge + side * (deck_hw + 1.6), 2.1, Color("23242B"))

			if b_down > 0.02:
				var flash_a: bool = float(bb.get("flashPhase", 0.0)) < 0.5
				for dir_s in [-1.0, 1.0]:
					var stop_c: Vector2 = bp + fwd * (dir_s * (hs + 3.2))
					var post_p: Vector2 = stop_c + side * (dir_s * (deck_hw + 1.8))
					var arm_len: float = rw_b * 0.88 * b_down
					var arm_tip: Vector2 = post_p - side * (dir_s * arm_len) + Vector2(0.0, -(1.0 - b_down) * 5.0)
					draw_line(post_p, arm_tip, Color("FAF7EE"), 2.4, true)
					draw_line(post_p, post_p.lerp(arm_tip, 0.55), Color("D4383B"), 2.4, true)
					draw_circle(post_p, 2.2, Color("23242B"))
					draw_circle(post_p, 1.45, Color("FF2B3B") if flash_a else Color("6A1C24"))

	func _draw_active_trains(sim: SimEngine, frustum: Rect2, cb: bool) -> void:
		var cull_rect: Rect2 = frustum.grow(32.0)
		for ln in sim.transport.rail_lines:
			var tr: Dictionary = ln.get("train", {})
			if tr.is_empty() or String(tr.get("state", "")) == "cooldown":
				continue
			var poses: Array = tr.get("unitPoses", [])
			if poses.is_empty():
				continue

			# Draw couplers between locomotive & flatbed wagons
			for i in range(1, poses.size()):
				var p0: Vector2 = poses[i - 1]["pos"]
				var p1: Vector2 = poses[i]["pos"]
				if cull_rect.has_point(p0) or cull_rect.has_point(p1):
					draw_line(p0, p1, MapView25D.TRUCK_INK, 2.1, true)

			for pose in poses:
				var up: Vector2 = pose["pos"]
				if not cull_rect.has_point(up):
					continue
				var ang: float = float(pose["angle"])
				var fwd := Vector2(cos(ang), sin(ang))
				var side := Vector2(-fwd.y, fwd.x)
				var ulen: float = float(pose["len"])
				var hl: float = ulen * 0.5
				var hw: float = 3.35
				var pkind := String(pose["kind"])

				var out_p := PackedVector2Array([
					up - fwd * (hl + 0.55) - side * (hw + 0.55),
					up + fwd * (hl + 0.55) - side * (hw + 0.55),
					up + fwd * (hl + 0.55) + side * (hw + 0.55),
					up - fwd * (hl + 0.55) + side * (hw + 0.55)
				])
				draw_colored_polygon(out_p, MapView25D.TRUCK_INK)

				if pkind == "loco":
					var body_p := PackedVector2Array([
						up - fwd * hl - side * hw,
						up + fwd * (hl - 1.4) - side * hw,
						up + fwd * hl - side * (hw * 0.68),
						up + fwd * hl + side * (hw * 0.68),
						up + fwd * (hl - 1.4) + side * hw,
						up - fwd * hl + side * hw
					])
					draw_colored_polygon(body_p, Color("E8792F"))
					# Yellow safety nose stripe + dark cab glass + roof exhaust fan
					var cab_c: Vector2 = up + fwd * (hl - 3.1)
					draw_colored_polygon(PackedVector2Array([
						cab_c - fwd * 1.4 - side * (hw * 0.78),
						cab_c + fwd * 1.4 - side * (hw * 0.78),
						cab_c + fwd * 1.4 + side * (hw * 0.78),
						cab_c - fwd * 1.4 + side * (hw * 0.78)
					]), MapView25D.TRUCK_GLASS)
					draw_circle(up - fwd * 1.8, 1.45, Color("2B3442"))
					draw_circle(up + fwd * (hl - 0.5) - side * 1.6, 0.85, Color("FFF3C4"))
					draw_circle(up + fwd * (hl - 0.5) + side * 1.6, 0.85, Color("FFF3C4"))
				else:
					var wag_p := PackedVector2Array([
						up - fwd * hl - side * hw,
						up + fwd * hl - side * hw,
						up + fwd * hl + side * hw,
						up - fwd * hl + side * hw
					])
					draw_colored_polygon(wag_p, MapView25D.TRUCK_PAPER)
					# Blue bolster end beams
					for end_s in [-1.0, 1.0]:
						var bc: Vector2 = up + fwd * (end_s * (hl - 0.65))
						draw_line(bc - side * hw, bc + side * hw, Color("3B6E8C"), 1.3, true)
					# Draw up to `5 x 2 = 10` cargo glyphs on flatbed!
					var c_slice: Array = pose.get("cargo", [])
					for ci in range(mini(c_slice.size(), 10)):
						var cg := String(c_slice[ci])
						if not GameCatalog.GOODS.has(cg):
							continue
						var col_i: int = ci / 2
						var row_i: int = ci % 2
						var lx: float = (-2.0 + float(col_i)) * 2.05
						var ly: float = -1.35 if row_i == 0 else 1.35
						var gp: Vector2 = up + fwd * lx + side * ly
						ShapeGlyphs.draw(self, cg, gp, 2.35, ang + ShapeGlyphs.truck_angle(cg), MapView25D.TRUCK_INK, 0.34, Transform2D.IDENTITY, cb)

	func _draw_selected_junction_bands_and_ring(sj: Dictionary, sim: SimEngine) -> void:
		var jp: Vector2 = sj["pos"]
		var geom: Dictionary = sj.get("geom", {})
		var arms: Array = geom.get("arms", [])
		var r_ring: float = maxf(22.0, float(geom.get("r_outer", 14.0)) + 8.5)
		var ctrl := String(sj["control"])

		for i in range(arms.size()):
			var a_in: Dictionary = arms[i]
			if not bool(a_in["can_enter"]):
				continue
			var eid_in := String(a_in["edge_id"])
			if not sim.road_map.has(eid_in):
				continue
			var r_in: Dictionary = sim.road_map[eid_in]
			var in_fwd: bool = not bool(a_in["is_start"])
			var in_lanes: int = maxi(1, int(r_in["lanesForward"]) if in_fwd else int(r_in["lanesBackward"]))
			var v_in: Vector2 = -(a_in["out_dir"] as Vector2)
			var road_mask: int = int(r_in.get("turnMaskForward" if in_fwd else "turnMaskBackward", 7))

			for k in range(arms.size()):
				if k == i:
					continue
				var a_out: Dictionary = arms[k]
				if not bool(a_out["can_exit"]):
					continue
				var eid_out := String(a_out["edge_id"])
				if not sim.road_map.has(eid_out):
					continue
				var r_out: Dictionary = sim.road_map[eid_out]
				var out_fwd: bool = bool(a_out["is_start"])
				var t_bit: int = RoutePathfinder.classify_turn_bit(sim.junction_map, sim.road_map, eid_in, in_fwd, String(sj["id"]), eid_out, out_fwd)
				if (road_mask & t_bit) == 0:
					continue

				var out_lanes: int = maxi(1, int(r_out["lanesForward"]) if out_fwd else int(r_out["lanesBackward"]))
				var v_out: Vector2 = a_out["out_dir"]
				var tang: float = atan2(v_in.x * v_out.y - v_in.y * v_out.x, v_in.dot(v_out))
				var is_green_move: bool = (ctrl == "lights" and sim.is_movement_green_at_light(sj, eid_in, in_fwd, eid_out, out_fwd))

				var band_col: Color
				var alpha_b: float = 0.52 if is_green_move else (0.14 if ctrl == "lights" else 0.32)
				if absf(tang) <= deg_to_rad(38.0):
					band_col = Color(0.28, 0.70, 0.45, alpha_b)
				elif tang > 0.0:
					band_col = Color(0.90, 0.50, 0.22, alpha_b)
				else:
					band_col = Color(0.45, 0.48, 0.86, alpha_b)

				var chosen_in_l: int = 0
				if in_lanes >= 2:
					if sim.left_hand_traffic:
						chosen_in_l = (in_lanes - 1) if tang > deg_to_rad(38.0) else 0
					else:
						chosen_in_l = (in_lanes - 1) if tang < -deg_to_rad(38.0) else 0
				var chosen_out_l: int = mini(chosen_in_l, out_lanes - 1)
				var app_in: int = RoadGeom.get_effective_approach_lanes(r_in, in_fwd)
				var is_kerb_turn: bool = (tang < -deg_to_rad(38.0)) if sim.left_hand_traffic else (tang > deg_to_rad(38.0))
				var use_pk: bool = (app_in > in_lanes and chosen_in_l == 0 and is_kerb_turn)

				var c_pts: PackedVector2Array = RoadGeom.build_turn_connector_pts(
					sj, r_in, in_fwd, float(chosen_in_l), in_lanes,
					r_out, out_fwd, float(chosen_out_l), out_lanes, sim.left_hand_traffic, use_pk
				)
				if c_pts.size() >= 2:
					draw_polyline(c_pts, band_col, 2.9 if is_green_move else 2.1, true)

		draw_arc(jp, r_ring, 0.0, TAU, 40, Color(0.35, 0.56, 0.86, 0.88), 1.8, true)

	func _draw_facility_routes_highlight(sim: SimEngine, fac_id: String, frustum: Rect2) -> void:
		for rt in sim.routes:
			if String(rt["fromFacilityId"]) != fac_id and String(rt["toFacilityId"]) != fac_id:
				continue
			var col: Color = rt["color"]
			col.a = 0.88
			for st in rt["forwardPath"]:
				var eid := String(st["edgeId"])
				if not sim.road_map.has(eid):
					continue
				var r: Dictionary = sim.road_map[eid]
				if frustum.intersects(r["aabb"]):
					draw_polyline(r["pts"], Color("23242B"), 5.2, true)
					draw_polyline(r["pts"], col, 3.2, true)

	func _draw_single_route(sim: SimEngine, font: Font, route_id: String, frustum: Rect2) -> void:
		var rt: Dictionary = sim.get_route(route_id)
		if rt.is_empty():
			return
		var col: Color = rt["color"]
		col.a = 0.92
		for st in rt["forwardPath"]:
			var eid := String(st["edgeId"])
			if sim.road_map.has(eid):
				var r: Dictionary = sim.road_map[eid]
				if frustum.intersects(r["aabb"]):
					draw_polyline(r["pts"], Color("23242B"), 5.6, true)
					draw_polyline(r["pts"], col, 3.6, true)
		if not bool(rt.get("sameWayBack", true)):
			var ret_col := col.lightened(0.28)
			ret_col.a = 0.76
			for st_r in rt["returnPath"]:
				var eid_r := String(st_r["edgeId"])
				if sim.road_map.has(eid_r):
					var r_r: Dictionary = sim.road_map[eid_r]
					if frustum.intersects(r_r["aabb"]):
						draw_polyline(r_r["pts"], Color("23242B"), 3.8, true)
						draw_polyline(r_r["pts"], ret_col, 2.3, true)
		_draw_route_waypoint_pins(sim, font, rt, col)

	func _draw_route_waypoint_pins(sim: SimEngine, font: Font, rt: Dictionary, col: Color) -> void:
		var wps: Array = rt.get("waypoints", [])
		for wi in range(wps.size()):
			var jid := String(wps[wi])
			if sim.junction_map.has(jid):
				var wpos: Vector2 = sim.junction_map[jid]["pos"]
				draw_circle(wpos, 6.8, Color("23242B"))
				draw_circle(wpos, 5.2, col)
				draw_string(font, wpos + Vector2(-5.0, 3.2), str(wi + 1), HORIZONTAL_ALIGNMENT_CENTER, 10.0, 8, Color.WHITE)
		if not bool(rt.get("sameWayBack", true)):
			var wps_b: Array = rt.get("waypointsBack", [])
			var bcol := col.lightened(0.26)
			for bi in range(wps_b.size()):
				var bjid := String(wps_b[bi])
				if sim.junction_map.has(bjid):
					var bpos: Vector2 = sim.junction_map[bjid]["pos"] + Vector2(4.0, -4.0)
					draw_circle(bpos, 6.4, Color("23242B"))
					draw_circle(bpos, 4.8, bcol)
					draw_string(font, bpos + Vector2(-6.0, 3.0), "R%d" % (bi + 1), HORIZONTAL_ALIGNMENT_CENTER, 12.0, 7, Color("23242B"))

	func _draw_routes_overlay(sim: SimEngine, font: Font, frustum: Rect2) -> void:
		# Group visible routes per road edge so shared corridors alternate route colors cleanly!
		var edge_routes: Dictionary = {}
		var vis_routes: Array[Dictionary] = []
		for rt in sim.routes:
			var rtid := String(rt["id"])
			if owner_view.hidden_route_ids.has(rtid):
				continue
			vis_routes.append(rt)
			var seen_on_rt: Dictionary = {}
			for st in rt["forwardPath"]:
				var eid := String(st["edgeId"])
				if seen_on_rt.has(eid):
					continue
				seen_on_rt[eid] = true
				if not edge_routes.has(eid):
					edge_routes[eid] = []
				(edge_routes[eid] as Array).append(rt)
			if not bool(rt.get("sameWayBack", true)):
				for st_b in rt["returnPath"]:
					var eid_b := String(st_b["edgeId"])
					if seen_on_rt.has(eid_b):
						continue
					seen_on_rt[eid_b] = true
					if not edge_routes.has(eid_b):
						edge_routes[eid_b] = []
					(edge_routes[eid_b] as Array).append(rt)

		for eid in edge_routes.keys():
			if not sim.road_map.has(eid):
				continue
			var r: Dictionary = sim.road_map[eid]
			if not frustum.intersects(r["aabb"]):
				continue
			var pts: PackedVector2Array = r["pts"]
			if pts.size() < 2:
				continue
			var r_list: Array = edge_routes[eid]
			var has_sel: bool = false
			for rt_chk in r_list:
				if String(rt_chk["id"]) == owner_view.selected_route_id:
					has_sel = true
					break
			var line_w: float = 4.4 if has_sel else 3.2
			draw_polyline(pts, Color("23242B"), line_w + 2.0, true)
			if r_list.size() == 1:
				var c1: Color = r_list[0]["color"]
				c1.a = 0.96 if has_sel else 0.86
				draw_polyline(pts, c1, line_w, true)
			else:
				var cum: PackedFloat32Array = r["cum_len"]
				var tot_l: float = float(r["lengthPx"])
				var dash_l: float = 13.0
				var seg_idx: int = 0
				var s0: float = 0.0
				while s0 < tot_l - 0.5:
					var s1: float = minf(tot_l, s0 + dash_l)
					var sub: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, s0, s1)
					if sub.size() >= 2:
						var cm: Color = (r_list[seg_idx % r_list.size()] as Dictionary)["color"]
						cm.a = 0.95
						draw_polyline(sub, cm, line_w, true)
					s0 = s1
					seg_idx += 1

		for rt_w in vis_routes:
			_draw_route_waypoint_pins(sim, font, rt_w, rt_w["color"])

	func _draw_route_break_roads(sim: SimEngine, frustum: Rect2) -> void:
		var drawn_edges: Dictionary = {}
		for rt in sim.routes:
			var rtid := String(rt["id"])
			if owner_view.overlay_mode == "routes" and owner_view.hidden_route_ids.has(rtid):
				continue
			if String(rt.get("brokenReason", "")) == "":
				continue
			var b_eid := String(rt.get("brokenEdgeId", ""))
			if b_eid != "" and sim.road_map.has(b_eid) and not drawn_edges.has(b_eid):
				drawn_edges[b_eid] = true
				var br: Dictionary = sim.road_map[b_eid]
				if frustum.intersects(br["aabb"]):
					var pts: PackedVector2Array = br["pts"]
					var cum: PackedFloat32Array = br["cum_len"]
					var tot: float = float(br["lengthPx"])
					draw_polyline(pts, Color("FBFAF6"), 7.4, true)
					var s0: float = 0.0
					while s0 < tot - 0.5:
						var s1: float = minf(tot, s0 + 7.5)
						var dp: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, s0, s1)
						if dp.size() >= 2:
							draw_polyline(dp, Color("C8323A"), 4.4, true)
						s0 += 12.5
			else:
				var bp: Vector2 = rt.get("brokenPos", Vector2.INF)
				if bp.is_finite() and frustum.has_point(bp):
					var pr: float = 11.0 + 2.5 * sin(float(Time.get_ticks_msec()) * 0.009)
					draw_arc(bp, pr, 0.0, TAU, 24, Color("FBFAF6"), 4.6, true)
					draw_arc(bp, pr, 0.0, TAU, 24, Color("C8323A"), 2.6, true)

	func _draw_traffic_heatmap(sim: SimEngine, frustum: Rect2, colorblind: bool) -> void:
		for r in sim.roads:
			if not bool(r["isBuilt"]) or not sim.unlocked_regions.has(int(r["regionIndex"])):
				continue
			if not frustum.intersects(r["aabb"]):
				continue
			var cong: float = clampf(float(r["congestionEMA"]) / 1.15, 0.0, 1.0)
			var hcol: Color = GameCatalog.traffic_band_color(cong, colorblind, 0.88)
			draw_polyline(r["pts"], hcol, 7.2, true)

	func _draw_goods_flow_sankey(sim: SimEngine, font: Font, frustum: Rect2, cb: bool) -> void:
		var r_idx: int = 0
		for rt in sim.routes:
			var f_from: Dictionary = sim.facility_map.get(String(rt["fromFacilityId"]), {})
			if f_from.is_empty():
				continue
			var gid := String(rt.get("goodFilter", "any"))
			if gid == "any" or gid == "":
				var out_g = f_from.get("outputGood", null)
				gid = String(out_g) if out_g != null else ""
			if gid == "" or not GameCatalog.GOODS.has(gid):
				var reqs: Array = f_from.get("inputs", [])
				gid = String(reqs[0]["good"]) if not reqs.is_empty() else "dot"
			var gcol: Color = ShapeGlyphs.color_of(gid, cb)
			var fkey := "%s->%s->%s" % [String(rt["fromFacilityId"]), String(rt["toFacilityId"]), gid]
			var measured: float = 0.0
			if sim.flow_edges.has(fkey):
				measured = float((sim.flow_edges[fkey]["times"] as Array).size())
			var truck_cnt: int = (rt.get("activeTruckIds", []) as Array).size()
			var rate_pm: float = measured if measured > 0.1 else (float(truck_cnt) * 2.2)
			var width: float = clampf(3.0 + rate_pm * 0.75, 3.2, 11.0)
			var shift := Vector2(float((r_idx % 3) - 1) * 2.0, float((r_idx % 2) * 2 - 1) * 1.4)
			r_idx += 1

			var fpath: Array = rt["forwardPath"]
			if fpath.is_empty():
				continue
			var mid_step_idx: int = fpath.size() / 2
			var badge_pt := Vector2.ZERO
			var has_badge_pt := false

			for si in range(fpath.size()):
				var st: Dictionary = fpath[si]
				var eid := String(st["edgeId"])
				if not sim.road_map.has(eid):
					continue
				var rd: Dictionary = sim.road_map[eid]
				if not frustum.intersects(rd["aabb"]):
					continue
				var pts: PackedVector2Array = rd["pts"]
				if pts.size() < 2:
					continue
				var spts := PackedVector2Array()
				spts.resize(pts.size())
				for pi in range(pts.size()):
					spts[pi] = pts[pi] + shift
				draw_polyline(spts, Color("23242B"), width + 2.6, true)
				draw_polyline(spts, gcol, width, true)

				var p0: Vector2 = spts[0]
				var p1: Vector2 = spts[spts.size() - 1]
				if not bool(st.get("forward", true)):
					var tmp := p0
					p0 = p1
					p1 = tmp
				var seg_mid: Vector2 = p0.lerp(p1, 0.5)
				var dir: Vector2 = (p1 - p0).normalized()
				var nrm := Vector2(-dir.y, dir.x)
				draw_colored_polygon(PackedVector2Array([
					seg_mid + dir * 5.0,
					seg_mid - dir * 3.5 + nrm * 3.8,
					seg_mid - dir * 3.5 - nrm * 3.8
				]), Color("23242B"))
				draw_colored_polygon(PackedVector2Array([
					seg_mid + dir * 3.8,
					seg_mid - dir * 2.6 + nrm * 2.6,
					seg_mid - dir * 2.6 - nrm * 2.6
				]), gcol.lightened(0.35))

				if si == mid_step_idx:
					badge_pt = seg_mid
					has_badge_pt = true

			if has_badge_pt and frustum.has_point(badge_pt):
				var r_txt := "%.1f/min" % rate_pm
				var pw: float = 56.0
				var pr := Rect2(badge_pt.x - pw * 0.5, badge_pt.y - 9.0, pw, 17.0)
				draw_rect(Rect2(pr.position + Vector2(1.5, 2.0), pr.size), Color("23242B"), true)
				draw_rect(pr, Color("FAF7EE"), true)
				draw_rect(pr, Color("23242B"), false, 1.4)
				draw_string(font, pr.position + Vector2(4.0, 12.2), r_txt, HORIZONTAL_ALIGNMENT_LEFT, 40.0, 9, Color("23242B"))
				ShapeGlyphs.draw(self, gid, pr.position + Vector2(pw - 8.5, 8.5), 9.0, 0.0, MapView25D.TRUCK_INK, 0.45, Transform2D.IDENTITY, cb)

	func _draw_buildings_overlay(sim: SimEngine, frustum: Rect2, colorblind: bool) -> void:
		for f in sim.facilities:
			if not sim.unlocked_regions.has(int(f["regionIndex"])):
				continue
			var fp: Vector2 = f["pos"]
			if not frustum.has_point(fp):
				continue
			var sr := String(f["stalledReason"])
			var scol: Color = GameCatalog.status_color("good", colorblind)
			if sr == "missing_input":
				scol = GameCatalog.status_color("warn", colorblind)
			elif sr == "output_full":
				scol = GameCatalog.status_color("bad", colorblind)
			draw_arc(fp, 23.0, 0.0, TAU, 28, scol, 4.4, true)

	func _draw_demand_overlay(sim: SimEngine, font: Font, zoom_x: float, colorblind: bool) -> void:
		var goal_reg: Dictionary = sim.get_active_goal_region()
		if goal_reg.is_empty():
			return
		var rc: Vector2 = goal_reg["center_vec"]
		var inv_z: float = clampf(1.0 / maxf(0.4, zoom_x), 0.75, 1.55)
		var y_off: float = 28.0 * inv_z
		for g in goal_reg["goals"]:
			var gid := String(g["good"])
			var cur_v: float = float(g.get("currentPerMin", 0.0))
			var tgt_v: float = float(g["targetPerMin"])
			var ratio: float = clampf(cur_v / maxf(0.1, tgt_v), 0.0, 1.0)
			var lvl := "good" if ratio >= 0.99 else ("warn" if ratio >= 0.5 else "bad")
			var bar_col: Color = GameCatalog.status_color(lvl, colorblind)
			var box := Rect2(rc + Vector2(-72 * inv_z, y_off - 12 * inv_z), Vector2(144 * inv_z, 20 * inv_z))
			draw_rect(box, Color("FAF7EE"), true)
			draw_rect(box, Color("23242B"), false, 1.6)
			ShapeGlyphs.draw(self, gid, box.position + Vector2(12 * inv_z, box.size.y * 0.5), 13.0 * inv_z, 0.0, MapView25D.TRUCK_INK, 0.5, Transform2D.IDENTITY, colorblind)
			var txt := "%.1f / %.1f / min" % [cur_v, tgt_v]
			draw_string(font, box.position + Vector2(24 * inv_z, 14 * inv_z), txt, HORIZONTAL_ALIGNMENT_LEFT, 114 * inv_z, int(11 * inv_z), bar_col.darkened(0.12))
			y_off += 23.0 * inv_z


class _DynamicWorldDrawer extends Node2D:
	## Drawn ABOVE `_truck_node` for airborne `CargoFlights`, `TruckInspectorOverlay`,
	## `RouteBreakMarks` `!` pills, `FactoryLabel` badges (`"N stuck"`), `RegionGate`, and `RewardPopups`.
	var owner_view: MapView25D

	func _draw() -> void:
		if owner_view == null or owner_view.sim == null:
			return
		var sim: SimEngine = owner_view.sim
		var frustum: Rect2 = owner_view.get_world_frustum()
		var zoom_x: float = owner_view.camera.zoom.x
		var font: Font = owner_view._ui_font if owner_view._ui_font != null else ThemeDB.fallback_font
		var cb: bool = owner_view.colorblind_mode
		var is_dark: bool = owner_view.dark_theme or sim.night_mode
		var inv_z: float = clampf(1.0 / maxf(0.35, zoom_x), 0.65, 1.75)

		# 0. Active Rail-Road `LevelCrossings` (twin alternating red flashers + lowering red/white boom arms)
		_draw_rail_level_crossings(sim, frustum, is_dark)

		# 1. Authentic `CargoFlights` (`cargo_flights.gd`: parabolic hops + landing rings + crumble shards)
		_draw_cargo_flights(sim, frustum, cb)

		# 2. Authentic `TruckInspectorOverlay` (`#4B80CA` remaining path, `#4FB35E` ring, `#D4383B` blocking chain)
		if owner_view.selected_truck_id != "":
			_draw_selected_truck_overlay(sim, font, inv_z)

		# 3. Authentic `RouteBreakMarks` `!` Tag Pills (`One-way`, `No turn`, `No green`, `Closed`, `No road`)
		if owner_view.overlay_mode == "none" or owner_view.overlay_mode == "routes":
			_draw_route_break_pills(sim, font, frustum, inv_z)

		# 4. Precount stuck trucks per origin facility for `RouteBreakMarks` `"N stuck"` facility pills
		var stuck_by_fac: Dictionary = {}
		for ag_s in sim.agents:
			if String(ag_s.get("waitReason", "")) == "broken_route":
				var rt_s: Dictionary = sim.get_route(String(ag_s.get("routeId", "")))
				if not rt_s.is_empty():
					var fid_s := String(rt_s["fromFacilityId"])
					stuck_by_fac[fid_s] = int(stuck_by_fac.get(fid_s, 0)) + 1

		# 5. Authentic FactoryLabel Badges & Production/Demand Rings
		for f in sim.facilities:
			var fp: Vector2 = f["pos"]
			if not frustum.has_point(fp):
				continue
			if not sim.unlocked_regions.has(int(f["regionIndex"])):
				continue
			var stuck_cnt: int = int(stuck_by_fac.get(String(f["id"]), 0))
			_draw_facility_badge(f, sim, font, zoom_x, cb, stuck_cnt)

		# 6. Authentic RegionGate World Pins on Locked Regions (active gate delegated to WorldShows when enabled)
		var active_goal_reg: Dictionary = sim.get_active_goal_region()
		var active_goal_idx: int = int(active_goal_reg.get("index", -1)) if not active_goal_reg.is_empty() else -1
		for reg in sim.regions:
			var rc: Vector2 = reg["center_vec"]
			if not frustum.has_point(rc):
				continue
			if not bool(reg["unlocked"]):
				var is_next: bool = int(reg["index"]) == active_goal_idx
				if is_next and owner_view.interactive_gate_handled:
					continue
				_draw_region_gate_pin(reg, font, inv_z, is_next, cb)
			elif zoom_x < 0.78:
				var rcol := Color(0.18, 0.20, 0.24, 0.45) if not is_dark else Color(0.85, 0.88, 0.92, 0.40)
				draw_string(font, rc + Vector2(-70.0 * inv_z, 0.0), String(reg["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 140.0 * inv_z, int(12.0 * inv_z), rcol)

		# 7. Authentic RewardPopups (Dark Pill + Gold Coin + Bold +$50 / EXPRESS ×2!)
		for tst in sim.floating_toasts:
			var tp: Vector2 = tst["pos"] + Vector2(0.0, -float(tst["age"]) * 24.0)
			if not frustum.has_point(tp):
				continue
			_draw_reward_popup(tst, tp, font, inv_z)

	func _draw_rail_level_crossings(sim: SimEngine, frustum: Rect2, is_dark: bool) -> void:
		for cx in sim.transport.level_crossings:
			var cp: Vector2 = cx["pos"]
			if not frustum.has_point(cp):
				continue
			var rd_id := String(cx["roadId"])
			var rd: Dictionary = sim.road_map.get(rd_id, {})
			if rd.is_empty() or not bool(rd.get("isBuilt", true)) or not sim.unlocked_regions.has(int(rd.get("regionIndex", 0))):
				continue
			var rw: float = float(rd.get("widthPx", 10.0))
			var r_ang: float = float(cx["roadAngle"])
			var r_fwd := Vector2(cos(r_ang), sin(r_ang))
			var r_side := Vector2(-r_fwd.y, r_fwd.x)
			var down: float = float(cx.get("down", 0.0))
			var closed: bool = bool(cx.get("closed", false))
			var fphase: float = float(cx.get("flashPhase", 0.0))
			var mark_c := Color(MapView25D.COL_LANE_MARK, 0.86 if not is_dark else 0.58)

			for dir_s in [-1.0, 1.0]:
				var stop_c: Vector2 = cp + r_fwd * (dir_s * 5.6)
				# White stop bar across road approach
				draw_line(stop_c - r_side * (rw * 0.46), stop_c + r_side * (rw * 0.46), mark_c, 1.15, true)
				# Curb signal post + St. Andrew's crossbuck + twin alternating red LEDs
				var curb_sign: float = -dir_s if sim.left_hand_traffic else dir_s
				var post_p: Vector2 = stop_c + r_side * (curb_sign * (rw * 0.5 + 2.2))
				draw_circle(post_p + Vector2(0.4, 0.7), 2.3, Color(0, 0, 0, 0.24))
				draw_circle(post_p, 2.2, Color("23242B"))
				if closed or down > 0.04:
					var led_a_on: bool = fphase < 0.5
					draw_circle(post_p + Vector2(-0.75, 0.0), 0.95, Color("FF2B3B") if led_a_on else Color("5A1A20"))
					draw_circle(post_p + Vector2(0.75, 0.0), 0.95, Color("FF2B3B") if not led_a_on else Color("5A1A20"))
				else:
					draw_circle(post_p, 1.05, Color("FAF7EE"))

				# Lowering red-and-white striped boom barrier (`down: 0..1`)
				if down > 0.02:
					var full_arm: float = rw * 0.86
					var horiz_len: float = full_arm * down
					var z_up := Vector2(0.0, -(1.0 - down) * 5.8)
					var arm_end: Vector2 = post_p - r_side * (curb_sign * horiz_len) + z_up
					draw_line(post_p + Vector2(0, 0.9), arm_end + Vector2(0, 0.9), Color(0, 0, 0, 0.20), 2.4, true)
					draw_line(post_p, arm_end, Color("FAF7EE"), 2.3, true)
					for si in range(3):
						var t0: float = float(si) * 0.34
						var t1: float = minf(1.0, t0 + 0.19)
						draw_line(post_p.lerp(arm_end, t0), post_p.lerp(arm_end, t1), Color("D4383B"), 2.3, true)

	func _draw_cargo_flights(sim: SimEngine, frustum: Rect2, cb: bool) -> void:
		for fl in sim.cargo_flights:
			var fkind := String(fl.get("kind", "hop"))
			var gid := String(fl.get("good", ""))
			if gid == "" or not GameCatalog.GOODS.has(gid):
				continue
			if fkind == "hop":
				var p_from: Vector2 = fl["from"]
				var p_to: Vector2 = fl["to"]
				if not frustum.has_point(p_from) and not frustum.has_point(p_to):
					continue
				var dur: float = maxf(0.05, float(fl["dur"]))
				var k: float = clampf(float(fl["t"]) / dur, 0.0, 1.0)
				var ring_t: float = float(fl.get("ring", -1.0))
				if ring_t < 0.0:
					var u: float = k * k * (3.0 - 2.0 * k)
					var arc: float = 4.0 * k * (1.0 - k)
					var g_pos: Vector2 = p_from.lerp(p_to, u)
					var air_pos: Vector2 = g_pos + Vector2(0.0, -9.5 * arc)
					var spin: float = sin(k * PI) * 0.6
					ShapeGlyphs.draw_tinted(
						self, gid, g_pos + Vector2(0.8, 1.2),
						4.1 * (1.0 - 0.22 * arc),
						Color(0.0, 0.0, 0.0, 0.24 * (1.0 - 0.35 * arc)), spin
					)
					ShapeGlyphs.draw(
						self, gid, air_pos, 4.4 + 1.35 * arc,
						spin, MapView25D.TRUCK_INK, 0.52, Transform2D.IDENTITY, cb
					)
				elif ring_t <= 0.35:
					var rk: float = clampf(ring_t / 0.35, 0.0, 1.0)
					draw_arc(p_to, lerpf(2.2, 7.8, rk), 0.0, TAU, 20, Color(1.0, 1.0, 1.0, 0.86 * (1.0 - rk)), 1.5, true)
			elif fkind == "crumble":
				var cpos: Vector2 = fl["pos"]
				if not frustum.has_point(cpos):
					continue
				var dur_c: float = maxf(0.05, float(fl["dur"]))
				var kc: float = clampf(float(fl["t"]) / dur_c, 0.0, 1.0)
				if kc < 0.55:
					var fade_a: float = (1.0 - kc / 0.55) * 0.85
					ShapeGlyphs.draw_tinted(
						self, gid, cpos + Vector2(0.0, kc * 3.4),
						4.6 * (1.0 - kc * 0.45),
						Color(0.54, 0.53, 0.50, fade_a), float(fl.get("rot", 0.0))
					)
				var seed_i: int = int(fl.get("seed", 1337))
				for si in range(9):
					var h: float = float(((seed_i + si * 7919) % 1000)) / 1000.0
					var ang_s: float = TAU * (float(si) / 9.0) + h * 0.65
					var spd_s: float = 5.5 + h * 7.5
					var spos: Vector2 = cpos + Vector2(cos(ang_s), sin(ang_s)) * (spd_s * kc) + Vector2(0.0, 13.5 * kc * kc)
					var sz_s: float = (1.6 - kc * 1.1) * (0.75 + 0.4 * h)
					if sz_s > 0.25:
						var scol := Color("8B8780") if (si % 2 == 0) else Color("5C5955")
						scol.a = clampf(1.0 - kc, 0.0, 1.0)
						draw_rect(Rect2(spos - Vector2.ONE * (sz_s * 0.5), Vector2.ONE * sz_s), scol, true)

	func _draw_selected_truck_overlay(sim: SimEngine, font: Font, inv_z: float) -> void:
		var ag: Dictionary = sim.get_agent(owner_view.selected_truck_id)
		if ag.is_empty():
			owner_view.selected_truck_id = ""
			return

		# `#4B80CA` remaining trajectory polyline
		var rem_pts: PackedVector2Array = sim.get_agent_remaining_polyline(ag)
		if rem_pts.size() >= 2:
			draw_polyline(rem_pts, MapView25D.TRUCK_INK, 4.4, true)
			draw_polyline(rem_pts, Color("4B80CA"), 2.6, true)

		# `#4FB35E` pulsing inspector ring around selected truck
		var ap: Vector2 = ag["pos"]
		var pulse_r: float = 8.4 + 1.2 * sin(float(Time.get_ticks_msec()) * 0.008)
		draw_arc(ap, pulse_r, 0.0, TAU, 28, MapView25D.TRUCK_INK, 3.4, true)
		draw_arc(ap, pulse_r, 0.0, TAU, 28, Color("4FB35E"), 2.0, true)

		# `#D4383B` waiting / gridlock chain arrows
		var chain_info: Dictionary = sim.get_agent_blocking_chain(ag)
		var links: Array = chain_info.get("links", [])
		for lk in links:
			var p0: Vector2 = lk["fromPos"]
			var p1: Vector2 = lk["toPos"]
			draw_line(p0, p1, MapView25D.TRUCK_INK, 3.4, true)
			draw_line(p0, p1, Color("D4383B"), 2.0, true)
			var d: Vector2 = (p1 - p0).normalized()
			var n := Vector2(-d.y, d.x)
			var mid: Vector2 = p0.lerp(p1, 0.62)
			draw_colored_polygon(PackedVector2Array([
				mid + d * 4.2, mid - d * 2.8 + n * 3.0, mid - d * 2.8 - n * 3.0
			]), Color("D4383B"))
			draw_arc(p1, 6.2, 0.0, TAU, 20, Color("D4383B"), 1.8, true)

		if bool(chain_info.get("isGridlock", false)):
			var gp: Vector2 = chain_info.get("rootPos", ap) + Vector2(0.0, -14.0 * inv_z)
			var gw: float = 64.0 * inv_z
			var gh: float = 15.0 * inv_z
			var gr := Rect2(gp.x - gw * 0.5, gp.y - gh * 0.5, gw, gh)
			draw_rect(gr.grow(1.0), MapView25D.TRUCK_INK, true)
			draw_rect(gr, Color("D4383B"), true)
			draw_string(font, gr.position + Vector2(2.0, 11.2 * inv_z), "GRIDLOCK", HORIZONTAL_ALIGNMENT_CENTER, gw - 4.0, int(9.0 * inv_z), Color.WHITE)

	func _draw_route_break_pills(sim: SimEngine, font: Font, frustum: Rect2, inv_z: float) -> void:
		var sc: float = clampf(inv_z, 0.72, 1.32)
		var drawn_pos: Array[Vector2] = []
		for rt in sim.routes:
			var rtid := String(rt["id"])
			if owner_view.overlay_mode == "routes" and owner_view.hidden_route_ids.has(rtid):
				continue
			if String(rt.get("brokenReason", "")) == "":
				continue
			var bp: Vector2 = rt.get("brokenPos", Vector2.INF)
			if not bp.is_finite() or not frustum.has_point(bp):
				continue
			var dup := false
			for dp in drawn_pos:
				if dp.distance_to(bp) < 10.0:
					dup = true
					break
			if dup:
				continue
			drawn_pos.append(bp)

			var tag := String(rt.get("brokenTag", "Broken"))
			if tag == "":
				tag = "Broken"
			var pw: float = (26.0 + float(tag.length()) * 5.6) * sc
			var ph: float = 16.5 * sc
			var pr := Rect2(bp.x - pw * 0.5, bp.y - ph - 6.0 * sc, pw, ph)
			draw_rect(Rect2(pr.position + Vector2(1.4 * sc, 1.8 * sc), pr.size), MapView25D.TRUCK_INK, true)
			draw_rect(pr, Color("FBFAF6"), true)
			draw_rect(pr, Color("C8323A"), false, 1.5 * sc)
			var bang_c := Vector2(pr.position.x + 8.5 * sc, pr.position.y + ph * 0.5)
			draw_circle(bang_c, 5.4 * sc, Color("C8323A"))
			draw_string(font, bang_c + Vector2(-3.0 * sc, 3.6 * sc), "!", HORIZONTAL_ALIGNMENT_CENTER, 6.0 * sc, int(9.5 * sc), Color.WHITE)
			draw_string(font, Vector2(pr.position.x + 16.0 * sc, pr.position.y + 11.8 * sc), tag, HORIZONTAL_ALIGNMENT_LEFT, pw - 18.0 * sc, int(9.0 * sc), Color("C8323A"))

	func _draw_facility_badge(f: Dictionary, sim: SimEngine, font: Font, zoom_x: float, colorblind: bool, stuck_cnt: int = 0) -> void:
		var fp: Vector2 = f["pos"]
		var badge_pos: Vector2 = fp + Vector2(0, -4.5)
		var kind_s := String(f["kind"])
		var stalled := String(f["stalledReason"])

		draw_circle(badge_pos + Vector2(0, 1.5), 9.6, Color(0, 0, 0, 0.22))
		draw_circle(badge_pos, 9.6, Color("23242B"))
		draw_circle(badge_pos, 8.0, Color("FAF7EE"))

		if f["outputGood"] != null:
			var gid := String(f["outputGood"])
			var prog: float = clampf(float(f.get("prodProgress", 0.0)), 0.0, 1.0)
			if prog > 0.02:
				draw_arc(badge_pos, 8.8, -PI * 0.5, -PI * 0.5 + TAU * prog, 20, ShapeGlyphs.color_of(gid, colorblind), 2.0, true)
			ShapeGlyphs.draw(self, gid, badge_pos, 11.5, 0.0, Color.TRANSPARENT, 0.0, Transform2D.IDENTITY, colorblind)
		elif kind_s == "station":
			ItIcons.draw_upgrade_icon(self, "trainLength", badge_pos - Vector2(9, 9), Color("23242B"))
		elif kind_s == "harbour":
			ItIcons.draw_upgrade_icon(self, "shipSize", badge_pos - Vector2(9, 9), Color("23242B"))
		else:
			ItIcons.draw_overlay_icon(self, "demand", badge_pos, Color("23242B"))

		if stalled != "none":
			var warn_col: Color = GameCatalog.status_color("bad" if stalled == "output_full" else "warn", colorblind)
			draw_circle(badge_pos + Vector2(7.5, -7.5), 4.2, Color("23242B"))
			draw_circle(badge_pos + Vector2(7.5, -7.5), 3.0, warn_col)

		if stuck_cnt > 0:
			var st_txt := "%d stuck" % stuck_cnt
			var sw: float = 46.0
			var sr := Rect2(fp.x - sw * 0.5, badge_pos.y - 23.5, sw, 13.0)
			draw_rect(sr.grow(0.8), Color("23242B"), true)
			draw_rect(sr, Color("C8323A"), true)
			draw_string(font, sr.position + Vector2(2.0, 9.6), st_txt, HORIZONTAL_ALIGNMENT_CENTER, sw - 4.0, 8, Color.WHITE)

		if zoom_x >= 0.65:
			var short_nm: String = String(f["name"])
			if short_nm.length() > 20:
				short_nm = short_nm.substr(0, 18) + ".."
			var pill_w: float = clampf(float(short_nm.length()) * 5.6 + 14.0, 56.0, 124.0)
			var pill_r := Rect2(fp.x - pill_w * 0.5, fp.y + 15.5, pill_w, 14.5)
			var is_dark: bool = owner_view.dark_theme or sim.night_mode
			draw_rect(pill_r, Color("1E222B" if is_dark else "FAF7EE", 0.92), true)
			draw_rect(pill_r, Color("23242B"), false, 1.3)
			draw_string(font, Vector2(pill_r.position.x + 3.0, pill_r.position.y + 10.8), short_nm, HORIZONTAL_ALIGNMENT_CENTER, pill_w - 6.0, 9, Color("F2F0E5") if is_dark else Color("23242B"))

	func _draw_region_gate_pin(reg: Dictionary, font: Font, inv_z: float, is_next: bool, colorblind: bool) -> void:
		var rc: Vector2 = reg["center_vec"]
		var goals: Array = reg["goals"]
		var ring_r: float = 17.0 * inv_z

		if not is_next:
			draw_circle(rc, ring_r, Color("FAF7EE"))
			draw_arc(rc, ring_r, 0.0, TAU, 24, Color("23242B"), 2.2 * inv_z, true)
			draw_rect(Rect2(rc - Vector2(4.5 * inv_z, 1.0 * inv_z), Vector2(9.0 * inv_z, 7.0 * inv_z)), Color("23242B"), true)
			draw_arc(rc - Vector2(0, 1.5 * inv_z), 3.2 * inv_z, PI, TAU, 12, Color("23242B"), 1.8 * inv_z, true)
			var nm_box := Rect2(rc + Vector2(ring_r + 5.0 * inv_z, -11.0 * inv_z), Vector2(108.0 * inv_z, 22.0 * inv_z))
			draw_rect(nm_box, Color("FAF7EE"), true)
			draw_rect(nm_box, Color("23242B"), false, 1.6 * inv_z)
			draw_string(font, nm_box.position + Vector2(6.0 * inv_z, 15.0 * inv_z), String(reg["name"]), HORIZONTAL_ALIGNMENT_LEFT, 96.0 * inv_z, int(10.5 * inv_z), Color("23242B"))
			return

		var sum_pct: float = 0.0
		for g in goals:
			var ratio: float = clampf(float(g.get("currentPerMin", 0.0)) / maxf(0.1, float(g["targetPerMin"])), 0.0, 1.0)
			sum_pct += ratio
		var avg_pct: float = (sum_pct / float(maxi(1, goals.size())))

		draw_line(rc + Vector2(0, ring_r), rc + Vector2(0, ring_r + 18.0 * inv_z), Color("625F57"), 2.0 * inv_z)

		var ring_c: Vector2 = rc - Vector2(54.0 * inv_z, 0.0)
		draw_circle(ring_c, ring_r + 2.0 * inv_z, Color("FAF7EE"))
		draw_arc(ring_c, ring_r + 2.0 * inv_z, 0.0, TAU, 28, Color("23242B"), 2.0 * inv_z, true)
		var seg_n: int = maxi(1, goals.size())
		for gi in range(seg_n):
			var g_d: Dictionary = goals[gi]
			var a0: float = -PI * 0.5 + TAU * (float(gi) / float(seg_n)) + 0.08
			var a1: float = -PI * 0.5 + TAU * (float(gi + 1) / float(seg_n)) - 0.08
			var gr: float = clampf(float(g_d.get("currentPerMin", 0.0)) / maxf(0.1, float(g_d["targetPerMin"])), 0.0, 1.0)
			draw_arc(ring_c, ring_r - 2.2 * inv_z, a0, a1, 14, Color(0.14, 0.15, 0.18, 0.14), 3.6 * inv_z, true)
			if gr > 0.02:
				draw_arc(ring_c, ring_r - 2.2 * inv_z, a0, lerpf(a0, a1, gr), 14, ShapeGlyphs.color_of(String(g_d["good"]), colorblind), 3.6 * inv_z, true)
		draw_rect(Rect2(ring_c - Vector2(4.2 * inv_z, 0.5 * inv_z), Vector2(8.4 * inv_z, 6.8 * inv_z)), Color("23242B"), true)
		draw_arc(ring_c - Vector2(0, 1.2 * inv_z), 3.0 * inv_z, PI, TAU, 12, Color("23242B"), 1.7 * inv_z, true)

		var card_h: float = (26.0 + float(goals.size()) * 14.0) * inv_z
		var card_w: float = 118.0 * inv_z
		var card_r := Rect2(ring_c + Vector2(ring_r + 5.0 * inv_z, -card_h * 0.5), Vector2(card_w, card_h))
		draw_rect(Rect2(card_r.position + Vector2(2.5 * inv_z, 3.0 * inv_z), card_r.size), Color("23242B"), true)
		draw_rect(card_r, Color("FAF7EE"), true)
		draw_rect(card_r, Color("23242B"), false, 1.8 * inv_z)

		var reg_lbl := "REGION %d" % (int(reg["index"]) + 1)
		draw_string(font, card_r.position + Vector2(6.0 * inv_z, 13.5 * inv_z), reg_lbl, HORIZONTAL_ALIGNMENT_LEFT, 74.0 * inv_z, int(9.5 * inv_z), Color("23242B"))
		draw_string(font, card_r.position + Vector2(card_w - 36.0 * inv_z, 13.5 * inv_z), "%d%%" % int(round(avg_pct * 100.0)), HORIZONTAL_ALIGNMENT_RIGHT, 30.0 * inv_z, int(9.5 * inv_z), Color("625F57"))

		for gi in range(goals.size()):
			var g_d: Dictionary = goals[gi]
			var gid := String(g_d["good"])
			var cur_v: float = float(g_d.get("currentPerMin", 0.0))
			var tgt_v: float = float(g_d["targetPerMin"])
			var ratio: float = clampf(cur_v / maxf(0.1, tgt_v), 0.0, 1.0)
			var gy: float = card_r.position.y + (22.0 + float(gi) * 13.5) * inv_z
			ShapeGlyphs.draw(self, gid, Vector2(card_r.position.x + 9.5 * inv_z, gy), 9.5 * inv_z, 0.0, MapView25D.TRUCK_INK, 0.4, Transform2D.IDENTITY, colorblind)
			var bar_r := Rect2(card_r.position.x + 17.5 * inv_z, gy - 2.2 * inv_z, 46.0 * inv_z, 4.4 * inv_z)
			draw_rect(bar_r, Color(0.14, 0.15, 0.18, 0.14), true)
			draw_rect(Rect2(bar_r.position, Vector2(bar_r.size.x * ratio, bar_r.size.y)), ShapeGlyphs.color_of(gid, colorblind), true)
			var val_s := "%.1f/%.1f" % [cur_v, tgt_v]
			var vcol: Color = GameCatalog.status_color("good", colorblind) if ratio >= 0.99 else Color("23242B")
			draw_string(font, Vector2(bar_r.end.x + 3.0 * inv_z, gy + 3.5 * inv_z), val_s, HORIZONTAL_ALIGNMENT_RIGHT, 48.0 * inv_z, int(8.5 * inv_z), vcol)

	func _draw_reward_popup(tst: Dictionary, tp: Vector2, font: Font, inv_z: float) -> void:
		var raw_txt := String(tst["text"])
		var alpha: float = clampf(1.0 - float(tst["age"]) / 1.45, 0.0, 1.0)
		var sc: float = clampf(inv_z, 0.75, 1.35)

		var is_express: bool = raw_txt.begins_with("⚡+")
		if is_express or raw_txt.begins_with("+$"):
			var clean_txt: String = raw_txt.replace("⚡", "")
			var pw: float = (58.0 + float(maxi(0, clean_txt.length() - 4)) * 7.5) * sc
			var ph: float = 22.0 * sc
			var box := Rect2(tp.x - pw * 0.5, tp.y - ph * 0.5, pw, ph)

			draw_rect(box, Color(0.09, 0.12, 0.10, 0.93 * alpha), true)
			draw_rect(box, Color(1.0, 0.93, 0.70, 0.90 * alpha), false, 1.6 * sc)

			var coin_c := Vector2(box.position.x + 11.5 * sc, box.position.y + ph * 0.5)
			draw_circle(coin_c, 6.2 * sc, Color(0.78, 0.56, 0.11, alpha))
			draw_circle(coin_c, 4.4 * sc, Color(1.0, 0.84, 0.29, alpha))

			draw_string(font, Vector2(coin_c.x + 8.5 * sc, box.position.y + ph * 0.72), clean_txt, HORIZONTAL_ALIGNMENT_LEFT, pw - 22.0 * sc, int(12.5 * sc), Color(1.0, 0.84, 0.29, alpha))

			if is_express:
				var ex_w: float = 58.0 * sc
				var ex_r := Rect2(tp.x - ex_w * 0.5, box.position.y - 13.5 * sc, ex_w, 12.0 * sc)
				draw_rect(ex_r, Color(1.0, 0.98, 0.92, 0.96 * alpha), true)
				draw_rect(ex_r, Color(0.14, 0.15, 0.18, 0.90 * alpha), false, 1.2 * sc)
				draw_string(font, Vector2(ex_r.position.x + 2.0, ex_r.position.y + 9.2 * sc), "EXPRESS ×2", HORIZONTAL_ALIGNMENT_CENTER, ex_w - 4.0, int(8.0 * sc), Color(0.14, 0.15, 0.18, alpha))
		else:
			var c: Color = tst["color"]
			c.a = alpha
			draw_string(font, tp + Vector2(-46, 0), raw_txt, HORIZONTAL_ALIGNMENT_CENTER, 92.0, int(11.5 * sc), c)

