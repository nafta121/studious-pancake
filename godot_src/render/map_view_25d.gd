class_name MapView25D
extends Node2D

## Authentic Incremental Traffic 2.5D cartographic world renderer for Karesidenan Madiun.
## Combines CONST world palette (#F2F0E5 parchment, #A9CDD8 rivers, #3C3F4A asphalt,
## striped fields, scattered green/autumn trees, FactoryLook aprons + skylights,
## ShapeGlyphs articulated trailers, FactoryLabel + RegionGate pins, and RewardPopups)
## with GPU-cached TriBatch2D static layers for locked 60-120 FPS on Android.

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

var sim: SimEngine
var camera: Camera2D

var overlay_mode: String = "none" # none | routes | traffic | flow | buildings | demand
var dark_theme: bool = false
var perf_preset: String = "balanced" # battery | balanced | ultra

var selected_facility_id: String = ""
var selected_junction_id: String = ""
var selected_road_id: String = ""
var selected_route_id: String = ""
var route_draft_from_id: String = ""
var active_tool: String = "pan"
var hidden_route_ids: Dictionary = {} # route_id -> true (for OverlayBar Network filter)

var _terrain_node: Node2D
var _water_node: Node2D
var _road_node: Node2D
var _extrude_node: Node2D
var _cloud_node: Node2D
var _dynamic_node: Node2D

var _water_mat: ShaderMaterial
var _extrude_mat: ShaderMaterial

var _terrain_batch := TriBatch2D.new()
var _water_batch := TriBatch2D.new()
var _road_batch := TriBatch2D.new()
var _extrude_batch := TriBatch2D.new()
var _cloud_batch := TriBatch2D.new()

var _night_blend: float = 0.0
var _static_dirty: bool = true
var _ui_font: Font

func setup(sim_engine: SimEngine, cam: Camera2D) -> void:
	sim = sim_engine
	camera = cam
	sim.map_static_dirty.connect(_on_static_dirty)
	if ResourceLoader.exists("res://gui/theme_studies/fonts/Jost-Variable.ttf"):
		_ui_font = load("res://gui/theme_studies/fonts/Jost-Variable.ttf") as Font
	else:
		_ui_font = ThemeDB.fallback_font

	_terrain_node = _StaticBatchLayer.new()
	(_terrain_node as _StaticBatchLayer).batch = _terrain_batch
	_water_node = _StaticBatchLayer.new()
	(_water_node as _StaticBatchLayer).batch = _water_batch
	_road_node = _StaticBatchLayer.new()
	(_road_node as _StaticBatchLayer).batch = _road_batch
	_extrude_node = _StaticBatchLayer.new()
	(_extrude_node as _StaticBatchLayer).batch = _extrude_batch
	_cloud_node = _StaticBatchLayer.new()
	(_cloud_node as _StaticBatchLayer).batch = _cloud_batch
	_dynamic_node = _DynamicWorldDrawer.new()
	(_dynamic_node as _DynamicWorldDrawer).owner_view = self

	var water_shader := load("res://shaders/water_ripples.gdshader") as Shader
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = water_shader
	_water_node.material = _water_mat

	var extrude_shader := load("res://shaders/extrude_25d.gdshader") as Shader
	_extrude_mat = ShaderMaterial.new()
	_extrude_mat.shader = extrude_shader
	_extrude_node.material = _extrude_mat

	add_child(_terrain_node)
	add_child(_water_node)
	add_child(_road_node)
	add_child(_extrude_node)
	add_child(_cloud_node)
	add_child(_dynamic_node)

	_static_dirty = true

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

func _process(delta: float) -> void:
	if sim == null or camera == null:
		return
	if _static_dirty:
		_rebuild_static_batches()
		_static_dirty = false

	var target_night: float = 1.0 if sim.night_mode else 0.0
	_night_blend = lerpf(_night_blend, target_night, minf(1.0, delta * 4.5))

	_extrude_mat.set_shader_parameter("cam_center", camera.global_position)
	_extrude_mat.set_shader_parameter("cam_zoom", camera.zoom.x)
	_extrude_mat.set_shader_parameter("lean_strength", 0.00032 if perf_preset == "battery" else 0.00050)
	_extrude_mat.set_shader_parameter("night_blend", _night_blend)
	_extrude_mat.set_shader_parameter("day_clock", sim.day_clock_01)

	_water_mat.set_shader_parameter("night_blend", _night_blend)
	_water_mat.set_shader_parameter("shimmer_amp", 0.015 if perf_preset == "battery" else 0.055)

	var bg_day := Color("20242C") if dark_theme else COL_BG
	var bg_night := Color("121620")
	RenderingServer.set_default_clear_color(bg_day.lerp(bg_night, _night_blend))

	_dynamic_node.queue_redraw()

func get_world_frustum() -> Rect2:
	var vp_size: Vector2 = get_viewport_rect().size
	var half_world: Vector2 = (vp_size * 0.5) / maxf(0.15, camera.zoom.x)
	var margin := Vector2(110.0, 110.0)
	return Rect2(camera.global_position - half_world - margin, (half_world + margin) * 2.0)

func _rebuild_static_batches() -> void:
	_terrain_batch.clear()
	_water_batch.clear()
	_road_batch.clear()
	_extrude_batch.clear()
	_cloud_batch.clear()

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

	# 2. Striped Agricultural Fields & Forest / Park Patches (like game_town-wide.webp)
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

		# Furrow stripes on agricultural fields (matching game_town-wide.webp!)
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

		# Scattered circular trees on forest/park/jati patches (zero runtime CPU cost!)
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

	# 5. Roads (#3C3F4A asphalt, #A9A59B curbs, #F2F0E5 crisp lane markings)
	for r in sim.roads:
		var r_unl: bool = sim.unlocked_regions.has(int(r["regionIndex"]))
		var pts: PackedVector2Array = r["pts"]
		var lanes_total: int = int(r["lanesForward"]) + int(r["lanesBackward"])
		if int(r["oneWay"]) != 0:
			lanes_total = maxi(int(r["lanesForward"]), int(r["lanesBackward"]))
		var width: float = float(lanes_total) * 5.2 + 3.8

		if not bool(r["isBuilt"]):
			if r_unl:
				_road_batch.add_dashed_polyline(pts, width * 0.74, Color(0.29, 0.50, 0.79, 0.45), 9.0, 7.0)
			continue

		var sidewalk_c := Color("2A2E38") if is_dark else COL_SIDEWALK
		var curb_c := Color("181B22") if is_dark else COL_CURB
		var asphalt := Color("2B2F3A") if is_dark else COL_ROAD
		if not r_unl:
			asphalt = asphalt.lerp(COL_BG, 0.52)
			curb_c.a = 0.35
			sidewalk_c.a = 0.25

		if bool(r["isBridge"]):
			_road_batch.add_polyline(pts, width + 6.8, Color("C9BFA9") if not is_dark else Color("49505C"), false, false)
			_road_batch.add_polyline(pts, width + 4.8, Color("5A5E6B"), false, false)
		else:
			_road_batch.add_polyline(pts, width + 4.6, sidewalk_c, false, true)
		_road_batch.add_polyline(pts, width + 2.0, curb_c, false, true)
		_road_batch.add_polyline(pts, width, asphalt, false, true)

		if bool(r["closed"]):
			_road_batch.add_dashed_polyline(pts, width * 0.65, COL_TREE_A, 7.0, 5.0)
			continue

		if r_unl:
			if int(r["oneWay"]) == 0:
				var mark_col := Color(COL_LANE_MARK, 0.85 if not is_dark else 0.55)
				_road_batch.add_dashed_polyline(pts, 1.2, mark_col, 7.0, 7.5, 0.0)
			else:
				_add_one_way_chevrons(pts, int(r["oneWay"]) == 1)

	# 6. Junction Geometry (Asphalt pads, Roundabouts with green islands, Yield triangles)
	for j in sim.junctions:
		var j_unl: bool = sim.unlocked_regions.has(int(j["regionIndex"]))
		var jp: Vector2 = j["pos"]
		var ctrl := String(j["control"])
		var pad_col := (Color("2B2F3A") if is_dark else COL_ROAD) if j_unl else COL_ROAD.lerp(COL_BG, 0.52)
		if ctrl == "roundabout" or ctrl == "roundabout2":
			var outer_r: float = 20.0 if ctrl == "roundabout2" else 15.5
			var island_r: float = 6.8
			_road_batch.add_circle(jp, outer_r + 2.2, COL_CURB, 22)
			_road_batch.add_circle(jp, outer_r, pad_col, 22)
			if ctrl == "roundabout2":
				_road_batch.add_ring(jp, 12.4, 13.5, Color(COL_LANE_MARK, 0.78), 20)
			_road_batch.add_circle(jp, island_r + 1.5, COL_SIDEWALK, 18)
			_road_batch.add_circle(jp, island_r, COL_TREE_A, 18)
		else:
			_road_batch.add_circle(jp, 7.8, pad_col, 14)
			if ctrl == "yield" and j_unl:
				_road_batch.add_tri(jp + Vector2(0, -6.4), jp + Vector2(5.8, 4.5), jp + Vector2(-5.8, 4.5), Color("C8323A"))
				_road_batch.add_tri(jp + Vector2(0, -3.5), jp + Vector2(3.2, 2.8), jp + Vector2(-3.2, 2.8), Color.WHITE)

	# 7. Town Houses & Commercial Blocks (authentic muted slate, terracotta & sand roofs from game_town-wide.webp)
	var skip_minor_houses: bool = perf_preset == "battery"
	var town_roofs := [
		Color("6A6E7A"), Color("7E6358"), Color("8C6D53"),
		Color("596370"), Color("9E6B55"), Color("787B84")
	]
	var b_idx: int = 0
	for b in sim.buildings:
		b_idx += 1
		if skip_minor_houses and (b_idx % 2 == 1) and String(b["kind"]) == "house":
			continue
		var b_unl: bool = sim.unlocked_regions.has(int(b["regionIndex"]))
		var r_col: Color = town_roofs[b_idx % town_roofs.size()]
		var w_col := Color("E4DFD3") if not is_dark else Color("3B404C")
		if not b_unl:
			r_col = r_col.lerp(COL_BG, 0.65)
			w_col = w_col.lerp(COL_BG, 0.65)
		var win_seed: float = (0.12 + fmod(float(b_idx) * 0.173, 0.82)) if b_unl else 0.0
		_extrude_batch.add_extruded_box_25d(
			Vector2(float(b["x"]), float(b["y"])),
			float(b["w"]),
			float(b["d"]),
			float(b["angle"]),
			float(b["h"]) * (0.85 if b_unl else 0.38),
			r_col,
			w_col,
			win_seed
		)

	# 8. Industrial Facilities (FactoryLook: concrete pad + dark asphalt bay apron + white bay lines + Teal/Ink/Brick roof + skylights!)
	var f_idx: int = 0
	for f in sim.facilities:
		f_idx += 1
		var f_unl: bool = sim.unlocked_regions.has(int(f["regionIndex"]))
		var fp: Vector2 = f["pos"]
		var fk := String(f["kind"])
		var exp_scale: float = 1.24 if int(f["upgrades"].get("expand", 0)) > 0 else 1.0

		# Concrete lot + dark asphalt truck loading apron with white bay markings (matching game_town-wide.webp!)
		var lot_col := Color("DCD8CE") if not is_dark else Color("2E333E")
		var apron_col := Color("343741") if not is_dark else Color("23262F")
		if not f_unl:
			lot_col.a = 0.35
			apron_col.a = 0.32
		_terrain_batch.add_rect_rot(fp + Vector2(0, 3.0), 36.0 * exp_scale, 30.0 * exp_scale, 0.0, lot_col)
		_terrain_batch.add_rect_rot(fp + Vector2(0, 10.5 * exp_scale), 28.0 * exp_scale, 11.0 * exp_scale, 0.0, apron_col)
		if f_unl:
			var bays_vis: int = clampi(sim.get_total_bays(f), 2, 6)
			for bi in range(bays_vis + 1):
				var bx: float = fp.x - 11.0 * exp_scale + (22.0 * exp_scale) * (float(bi) / float(bays_vis))
				_terrain_batch.add_polyline(
					PackedVector2Array([Vector2(bx, fp.y + 6.5 * exp_scale), Vector2(bx, fp.y + 14.5 * exp_scale)]),
					1.0, Color(COL_LANE_MARK, 0.72), false, false
				)

		# Authentic FactoryLook roof colors: Teal #3F8C7E (factories), Dark Ink #353B4D (suppliers), Brick/Slate (stations/harbours)
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

		var fh: float = 14.5 if f_unl else 6.5
		var fw: float = 25.0 * exp_scale
		var fd: float = 15.5 * exp_scale
		var hall_c: Vector2 = fp + Vector2(0, -2.5 * exp_scale)
		_extrude_batch.add_extruded_box_25d(
			hall_c, fw, fd, 0.0, fh, r_col, w_col,
			0.25 + float(f_idx) * 0.13 if f_unl else 0.0
		)
		# Parallel white roof skylight stripes extruded at roof peak height!
		if f_unl:
			var uv_sky := Vector2(fh * 1.14, 0.0)
			var sky_col := Color("D9ECE9") if fk == "factory" else Color("DCE1EA")
			for sy in [-3.2 * exp_scale, 2.6 * exp_scale]:
				var s0 := hall_c + Vector2(-fw * 0.36, sy - 1.1)
				var s1 := hall_c + Vector2(fw * 0.36, sy - 1.1)
				var s2 := hall_c + Vector2(fw * 0.36, sy + 1.1)
				var s3 := hall_c + Vector2(-fw * 0.36, sy + 1.1)
				_extrude_batch.add_quad(s0, s1, s2, s3, sky_col, uv_sky, uv_sky, uv_sky, uv_sky)

	# 9. Soft Cloud Mist Veil over Locked Regions (matching right side of game_trucks.webp!)
	for reg in sim.regions:
		if bool(reg["unlocked"]):
			continue
		var mist_fill := Color(0.97, 0.97, 0.95, 0.56) if not is_dark else Color(0.09, 0.11, 0.15, 0.58)
		var puff_col := Color(0.99, 0.99, 0.98, 0.42) if not is_dark else Color(0.13, 0.16, 0.22, 0.42)
		for pv in reg["poly_vecs"]:
			_cloud_batch.add_polygon_safe(pv, mist_fill)
			var step_i: int = maxi(1, pv.size() / 18)
			for pi in range(0, pv.size(), step_i):
				_cloud_batch.add_circle(pv[pi], 26.0, puff_col, 14)

	_terrain_node.queue_redraw()
	_water_node.queue_redraw()
	_road_node.queue_redraw()
	_extrude_node.queue_redraw()
	_cloud_node.queue_redraw()

func _add_one_way_chevrons(pts: PackedVector2Array, forward: bool) -> void:
	if pts.size() < 2:
		return
	var mid_i: int = pts.size() / 2
	var a: Vector2 = pts[maxi(0, mid_i - 1)]
	var b: Vector2 = pts[mini(pts.size() - 1, mid_i)]
	var dir: Vector2 = (b - a).normalized()
	if not forward:
		dir = -dir
	var nrm := Vector2(-dir.y, dir.x)
	var c: Vector2 = a.lerp(b, 0.5)
	_road_batch.add_tri(c + dir * 5.0, c - dir * 3.4 + nrm * 3.6, c - dir * 3.4 - nrm * 3.6, COL_LANE_MARK)


class _StaticBatchLayer extends Node2D:
	var batch: TriBatch2D

	func _draw() -> void:
		if batch != null and not batch.is_empty():
			RenderingServer.canvas_item_add_triangle_array(
				get_canvas_item(), batch.indices, batch.verts, batch.colors, batch.uvs
			)


class _DynamicWorldDrawer extends Node2D:
	var owner_view: MapView25D

	func _draw() -> void:
		if owner_view == null or owner_view.sim == null:
			return
		var sim: SimEngine = owner_view.sim
		var frustum: Rect2 = owner_view.get_world_frustum()
		var zoom_x: float = owner_view.camera.zoom.x
		var font: Font = owner_view._ui_font if owner_view._ui_font != null else ThemeDB.fallback_font

		# 1. Selected / Hovered Highlights & Route Creator Preview
		if owner_view.selected_road_id != "" and sim.road_map.has(owner_view.selected_road_id):
			var sr: Dictionary = sim.road_map[owner_view.selected_road_id]
			draw_polyline(sr["pts"], Color(0.96, 0.78, 0.29, 0.65), 14.0, true)

		if owner_view.selected_junction_id != "" and sim.junction_map.has(owner_view.selected_junction_id):
			var sj: Dictionary = sim.junction_map[owner_view.selected_junction_id]
			draw_arc(sj["pos"], 18.0, 0.0, TAU, 28, Color("F4C64A"), 3.2, true)

		if owner_view.selected_facility_id != "" and sim.facility_map.has(owner_view.selected_facility_id):
			var sf: Dictionary = sim.facility_map[owner_view.selected_facility_id]
			draw_arc(sf["pos"], 24.0, 0.0, TAU, 32, Color("F4C64A"), 3.4, true)
			# Highlight routes belonging to the selected facility (just like game_trucks.webp!)
			_draw_facility_routes_highlight(sim, owner_view.selected_facility_id, frustum)

		if owner_view.route_draft_from_id != "" and sim.facility_map.has(owner_view.route_draft_from_id):
			var df: Dictionary = sim.facility_map[owner_view.route_draft_from_id]
			var pulse: float = 22.0 + 4.0 * sin(Time.get_ticks_msec() * 0.008)
			draw_arc(df["pos"], pulse, 0.0, TAU, 28, Color("4FB35E"), 3.4, true)

		# 2. Five Analytic Map Overlays (from OverlayBar)
		var mode := owner_view.overlay_mode
		if mode == "routes":
			_draw_routes_overlay(sim, frustum)
		elif mode == "traffic":
			_draw_traffic_heatmap(sim, frustum)
		elif mode == "flow":
			_draw_goods_flow_sankey(sim, font, frustum)
		elif mode == "buildings":
			_draw_buildings_overlay(sim, frustum)
		elif mode == "demand":
			_draw_demand_overlay(sim, font, zoom_x)
		elif owner_view.selected_route_id != "":
			_draw_single_route(sim, owner_view.selected_route_id, frustum)

		# 3. Live Traffic Light Signal Heads
		for j in sim.junctions:
			if String(j["control"]) != "lights" or not j.has("light"):
				continue
			var jp: Vector2 = j["pos"]
			if not frustum.has_point(jp):
				continue
			var lt: Dictionary = j["light"]
			var stg := String(lt["stage"])
			var ph: int = int(lt["currentPhase"])
			var col_a := Color("C8323A")
			var col_b := Color("C8323A")
			if ph == 0:
				col_a = Color("4FB35E") if stg == "green" else (Color("F2AB37") if stg == "yellow" else Color("C8323A"))
			else:
				col_b = Color("4FB35E") if stg == "green" else (Color("F2AB37") if stg == "yellow" else Color("C8323A"))
			draw_circle(jp + Vector2(-5.2, -5.2), 3.3, Color("23242B"))
			draw_circle(jp + Vector2(-5.2, -5.2), 2.3, col_a)
			draw_circle(jp + Vector2(5.2, 5.2), 3.3, Color("23242B"))
			draw_circle(jp + Vector2(5.2, 5.2), 2.3, col_b)

		# 4. Station Cargo Trains & Harbour Ships (Pelabuhan Tamperan)
		for f in sim.facilities:
			if not sim.unlocked_regions.has(int(f["regionIndex"])):
				continue
			var fp: Vector2 = f["pos"]
			if not frustum.has_point(fp):
				continue
			var fk := String(f["kind"])
			if fk == "station" and bool(f["vehiclePresent"]):
				draw_rect(Rect2(fp + Vector2(-21, 13), Vector2(42, 6.8)), Color("23242B"), true)
				draw_rect(Rect2(fp + Vector2(-20, 13.8), Vector2(40, 5.2)), Color("3B6E8C"), true)
				draw_rect(Rect2(fp + Vector2(-17, 14.4), Vector2(10, 4.0)), Color("F4C64A"), true)
			elif fk == "harbour" and bool(f["vehiclePresent"]):
				var hull := PackedVector2Array([
					fp + Vector2(-24, 15), fp + Vector2(20, 15),
					fp + Vector2(26, 22), fp + Vector2(-20, 22)
				])
				draw_colored_polygon(hull, Color("2F5D8A"))
				draw_rect(Rect2(fp + Vector2(-12, 11), Vector2(18, 5)), Color("E8792F"), true)

		# 5. Physical Cargo Stockpile Dots on Loading Aprons + Articulated Trucks (TruckView)
		for ag in sim.agents:
			var st := String(ag["state"])
			if st != "driving_outbound" and st != "driving_return":
				continue
			var ap: Vector2 = ag["pos"]
			if not frustum.has_point(ap):
				continue
			_draw_articulated_truck(ag, sim, owner_view._night_blend)

		# 6. Authentic FactoryLabel Badges & Production/Demand Rings
		for f in sim.facilities:
			var fp: Vector2 = f["pos"]
			if not frustum.has_point(fp):
				continue
			if not sim.unlocked_regions.has(int(f["regionIndex"])):
				continue
			_draw_facility_badge(f, sim, font, zoom_x)

		# 7. Authentic RegionGate World Pins on Active Locked Region (matching game_trucks.webp!)
		var inv_z: float = clampf(1.0 / maxf(0.35, zoom_x), 0.65, 1.75)
		var active_goal_reg: Dictionary = sim.get_active_goal_region()
		var active_goal_idx: int = int(active_goal_reg.get("index", -1)) if not active_goal_reg.is_empty() else -1
		for reg in sim.regions:
			var rc: Vector2 = reg["center_vec"]
			if not frustum.has_point(rc):
				continue
			if not bool(reg["unlocked"]):
				var is_next: bool = int(reg["index"]) == active_goal_idx
				_draw_region_gate_pin(reg, font, inv_z, is_next)
			elif zoom_x < 0.78:
				var rcol := Color(0.18, 0.20, 0.24, 0.45) if not (owner_view.dark_theme or sim.night_mode) else Color(0.85, 0.88, 0.92, 0.40)
				draw_string(font, rc + Vector2(-70.0 * inv_z, 0.0), String(reg["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 140.0 * inv_z, int(12.0 * inv_z), rcol)

		# 8. Authentic RewardPopups (Dark Pill + Gold Coin + Bold +$50 / EXPRESS ×2!)
		for tst in sim.floating_toasts:
			var tp: Vector2 = tst["pos"] + Vector2(0.0, -float(tst["age"]) * 24.0)
			if not frustum.has_point(tp):
				continue
			_draw_reward_popup(tst, tp, font, inv_z)

	func _draw_facility_routes_highlight(sim: SimEngine, fac_id: String, frustum: Rect2) -> void:
		for rt in sim.routes:
			if String(rt["fromFacilityId"]) != fac_id and String(rt["toFacilityId"]) != fac_id:
				continue
			var col: Color = rt["color"]
			col.a = 0.85
			for st in rt["forwardPath"]:
				var eid := String(st["edgeId"])
				if not sim.road_map.has(eid):
					continue
				var r: Dictionary = sim.road_map[eid]
				if frustum.intersects(r["aabb"]):
					draw_polyline(r["pts"], Color("23242B"), 5.2, true)
					draw_polyline(r["pts"], col, 3.2, true)

	func _draw_single_route(sim: SimEngine, route_id: String, frustum: Rect2) -> void:
		var rt: Dictionary = sim.get_route(route_id)
		if rt.is_empty():
			return
		var col: Color = rt["color"]
		col.a = 0.90
		for st in rt["forwardPath"]:
			var eid := String(st["edgeId"])
			if sim.road_map.has(eid):
				var r: Dictionary = sim.road_map[eid]
				if frustum.intersects(r["aabb"]):
					draw_polyline(r["pts"], Color("23242B"), 5.6, true)
					draw_polyline(r["pts"], col, 3.6, true)
		for wp in rt["waypoints"]:
			if sim.junction_map.has(String(wp)):
				var wpos: Vector2 = sim.junction_map[String(wp)]["pos"]
				draw_circle(wpos, 6.2, Color("23242B"))
				draw_circle(wpos, 4.6, col)
				draw_circle(wpos, 2.0, Color.WHITE)

	func _draw_routes_overlay(sim: SimEngine, frustum: Rect2) -> void:
		var idx: int = 0
		for rt in sim.routes:
			var rtid := String(rt["id"])
			if owner_view.hidden_route_ids.has(rtid):
				continue
			var is_sel: bool = rtid == owner_view.selected_route_id
			var col: Color = rt["color"]
			col.a = 0.92 if is_sel else 0.72
			var w: float = 3.8 if is_sel else 2.4
			var lat_shift: float = float((idx % 3) - 1) * 2.2
			idx += 1
			for st in rt["forwardPath"]:
				var eid := String(st["edgeId"])
				if not sim.road_map.has(eid):
					continue
				var r: Dictionary = sim.road_map[eid]
				if not frustum.intersects(r["aabb"]):
					continue
				var pts: PackedVector2Array = r["pts"]
				if pts.size() >= 2:
					var shifted := PackedVector2Array()
					shifted.resize(pts.size())
					for i in range(pts.size()):
						shifted[i] = pts[i] + Vector2(lat_shift, lat_shift * 0.6)
					draw_polyline(shifted, col, w, true)
			for wp in rt["waypoints"]:
				if sim.junction_map.has(String(wp)):
					var wpos: Vector2 = sim.junction_map[String(wp)]["pos"]
					draw_circle(wpos, 5.5, col)
					draw_circle(wpos, 2.5, Color.WHITE)

	func _draw_traffic_heatmap(sim: SimEngine, frustum: Rect2) -> void:
		for r in sim.roads:
			if not bool(r["isBuilt"]) or not sim.unlocked_regions.has(int(r["regionIndex"])):
				continue
			if not frustum.intersects(r["aabb"]):
				continue
			var cong: float = clampf(float(r["congestionEMA"]), 0.0, 1.2)
			var hcol: Color = Color("4FB35E").lerp(Color("F2C230"), clampf(cong / 0.6, 0.0, 1.0))
			if cong > 0.6:
				hcol = Color("F2C230").lerp(Color("C8323A"), clampf((cong - 0.6) / 0.6, 0.0, 1.0))
			hcol.a = 0.80
			draw_polyline(r["pts"], hcol, 6.8, true)

	func _draw_goods_flow_sankey(sim: SimEngine, font: Font, frustum: Rect2) -> void:
		var r_idx: int = 0
		for rt in sim.routes:
			var f_from: Dictionary = sim.facility_map.get(String(rt["fromFacilityId"]), {})
			if f_from.is_empty():
				continue
			var gid := String(rt.get("goodFilter", "any"))
			if gid == "any" or gid == "":
				var out_g = f_from.get("outputGood", null)
				gid = String(out_g) if out_g != null else ""
			if gid == "":
				var reqs: Array = f_from.get("inputs", [])
				gid = String(reqs[0]["good"]) if not reqs.is_empty() else "grain"
			var gcol: Color = ItIcons.color_of(gid)
			var fkey := "%s->%s:%s" % [String(rt["fromFacilityId"]), String(rt["toFacilityId"]), gid]
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

				# Directional chevron arrow along segment
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
				ItIcons.draw_shape(self, gid, pr.position + Vector2(pw - 8.5, 8.5), 9.0)

	func _draw_buildings_overlay(sim: SimEngine, frustum: Rect2) -> void:
		for f in sim.facilities:
			if not sim.unlocked_regions.has(int(f["regionIndex"])):
				continue
			var fp: Vector2 = f["pos"]
			if not frustum.has_point(fp):
				continue
			var sr := String(f["stalledReason"])
			var scol := Color("3E9E50")
			if sr == "missing_input":
				scol = Color("E09A2A")
			elif sr == "output_full":
				scol = Color("D0393F")
			draw_arc(fp, 23.0, 0.0, TAU, 28, scol, 4.0, true)

	func _draw_demand_overlay(sim: SimEngine, font: Font, zoom_x: float) -> void:
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
			var bar_col := Color("3E9E50") if ratio >= 0.99 else (Color("E09A2A") if ratio >= 0.5 else Color("D0393F"))
			var box := Rect2(rc + Vector2(-72 * inv_z, y_off - 12 * inv_z), Vector2(144 * inv_z, 20 * inv_z))
			draw_rect(box, Color("FAF7EE"), true)
			draw_rect(box, Color("23242B"), false, 1.6)
			ItIcons.draw_shape(self, gid, box.position + Vector2(12 * inv_z, box.size.y * 0.5), 13.0 * inv_z)
			var txt := "%.1f / %.1f / min" % [cur_v, tgt_v]
			draw_string(font, box.position + Vector2(24 * inv_z, 14 * inv_z), txt, HORIZONTAL_ALIGNMENT_LEFT, 114 * inv_z, int(11 * inv_z), bar_col.darkened(0.15))
			y_off += 23.0 * inv_z

	func _draw_articulated_truck(ag: Dictionary, sim: SimEngine, night_blend: float) -> void:
		var tdef: Dictionary = GameCatalog.TRUCKS[String(ag["model"])]
		var cab_pos: Vector2 = ag["pos"]
		var cab_ang: float = float(ag["heading"])
		var rtid := String(ag["routeId"])
		var greyed: bool = (owner_view.overlay_mode == "routes" and owner_view.hidden_route_ids.has(rtid))
		var rt: Dictionary = sim.get_route(rtid)
		var cab_col: Color = Color("8A8F98") if greyed else (rt.get("color", tdef["color"]) as Color)

		# Night headlight cone
		if night_blend > 0.12 and not greyed:
			var fwd := Vector2(cos(cab_ang), sin(cab_ang))
			var side := Vector2(-fwd.y, fwd.x)
			var cone := PackedVector2Array([
				cab_pos + fwd * 4.0,
				cab_pos + fwd * 29.0 + side * 10.5,
				cab_pos + fwd * 29.0 - side * 10.5
			])
			draw_colored_polygon(cone, Color(1.0, 0.95, 0.72, 0.25 * night_blend))

		# Draw trailers back-to-front (TruckView: #1D2128 keyline + #F6F5EF paper box + ShapeGlyphs cargo!)
		var t_poses: Array = ag["trailerPoses"]
		var c_good := String(ag["cargoGood"])
		var has_cargo: bool = c_good != "" and int(ag["cargoQty"]) > 0
		var paper_col := Color("D5D7DC") if greyed else Color("F6F5EF")
		var ink_col := Color("1D2128")

		for ti in range(t_poses.size() - 1, -1, -1):
			var tp: Vector2 = t_poses[ti]["pos"]
			var tang: float = float(t_poses[ti]["heading"])
			var lead_p: Vector2 = cab_pos if ti == 0 else t_poses[ti - 1]["pos"]
			draw_line(tp, lead_p, ink_col, 1.6)
			_draw_rot_box(tp, 8.4, 5.0, tang, ink_col)
			_draw_rot_box(tp, 7.2, 3.8, tang, paper_col)
			if has_cargo and not greyed:
				ItIcons.draw_shape(self, c_good, tp, 3.8, tang + ItIcons.truck_angle(c_good))

		# Tractor cab with dark ink outline & glass windshield
		var cab_l: float = float(tdef["cab_len"]) * 0.74
		_draw_rot_box(cab_pos, cab_l + 1.2, 5.2, cab_ang, ink_col)
		_draw_rot_box(cab_pos, cab_l, 4.0, cab_ang, cab_col)
		var windshield: Vector2 = cab_pos + Vector2(cos(cab_ang), sin(cab_ang)) * 1.5
		_draw_rot_box(windshield, 1.9, 3.1, cab_ang, Color("2B3442"))

	func _draw_rot_box(c: Vector2, length: float, width: float, ang: float, col: Color) -> void:
		var ux := Vector2(cos(ang), sin(ang)) * (length * 0.5)
		var uy := Vector2(-sin(ang), cos(ang)) * (width * 0.5)
		draw_colored_polygon(PackedVector2Array([c - ux - uy, c + ux - uy, c + ux + uy, c - ux + uy]), col)

	func _draw_facility_badge(f: Dictionary, sim: SimEngine, font: Font, zoom_x: float) -> void:
		var fp: Vector2 = f["pos"]
		var badge_pos: Vector2 = fp + Vector2(0, -4.5)
		var kind_s := String(f["kind"])
		var stalled := String(f["stalledReason"])

		# Crisp white paper circular medallion with #23242B ink rim & live progress arc
		draw_circle(badge_pos + Vector2(0, 1.5), 9.6, Color(0, 0, 0, 0.22))
		draw_circle(badge_pos, 9.6, Color("23242B"))
		draw_circle(badge_pos, 8.0, Color("FAF7EE"))

		if f["outputGood"] != null:
			var gid := String(f["outputGood"])
			var prog: float = clampf(float(f.get("prodProgress", 0.0)), 0.0, 1.0)
			if prog > 0.02:
				draw_arc(badge_pos, 8.8, -PI * 0.5, -PI * 0.5 + TAU * prog, 20, ItIcons.color_of(gid), 2.0, true)
			ItIcons.draw_shape(self, gid, badge_pos, 11.5)
			# Physical cargo dots on apron for buffered output
			var buf_n: int = mini(6, int(f.get("outputBuffer", 0)))
			for bi in range(buf_n):
				var sp_pos := fp + Vector2(-10.0 + float(bi) * 4.0, 9.5)
				ItIcons.draw_shape(self, gid, sp_pos, 4.2)
		elif kind_s == "station":
			ItIcons.draw_upgrade_icon(self, "trainLength", badge_pos - Vector2(9, 9), Color("23242B"))
		elif kind_s == "harbour":
			ItIcons.draw_upgrade_icon(self, "shipSize", badge_pos - Vector2(9, 9), Color("23242B"))
		else:
			ItIcons.draw_overlay_icon(self, "demand", badge_pos, Color("23242B"))

		# Status dot if waiting/full (like game_town-wide.webp)
		if stalled != "none":
			var warn_col := Color("C2412F") if stalled == "output_full" else Color("E09A2A")
			draw_circle(badge_pos + Vector2(7.5, -7.5), 4.2, Color("23242B"))
			draw_circle(badge_pos + Vector2(7.5, -7.5), 3.0, warn_col)

		# Upright FactoryLabel sticker pill when zoomed in
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

	func _draw_region_gate_pin(reg: Dictionary, font: Font, inv_z: float, is_next: bool) -> void:
		var rc: Vector2 = reg["center_vec"]
		var goals: Array = reg["goals"]
		var ring_r: float = 17.0 * inv_z

		if not is_next:
			# Compact locked pin for future regions
			draw_circle(rc, ring_r, Color("FAF7EE"))
			draw_arc(rc, ring_r, 0.0, TAU, 24, Color("23242B"), 2.2 * inv_z, true)
			draw_rect(Rect2(rc - Vector2(4.5 * inv_z, 1.0 * inv_z), Vector2(9.0 * inv_z, 7.0 * inv_z)), Color("23242B"), true)
			draw_arc(rc - Vector2(0, 1.5 * inv_z), 3.2 * inv_z, PI, TAU, 12, Color("23242B"), 1.8 * inv_z, true)
			var nm_box := Rect2(rc + Vector2(ring_r + 5.0 * inv_z, -11.0 * inv_z), Vector2(108.0 * inv_z, 22.0 * inv_z))
			draw_rect(nm_box, Color("FAF7EE"), true)
			draw_rect(nm_box, Color("23242B"), false, 1.6 * inv_z)
			draw_string(font, nm_box.position + Vector2(6.0 * inv_z, 15.0 * inv_z), String(reg["name"]), HORIZONTAL_ALIGNMENT_LEFT, 96.0 * inv_z, int(10.5 * inv_z), Color("23242B"))
			return

		# Full authentic RegionGate card (matching REGION 5 in game_trucks.webp!)
		var sum_pct: float = 0.0
		for g in goals:
			var ratio: float = clampf(float(g.get("currentPerMin", 0.0)) / maxf(0.1, float(g["targetPerMin"])), 0.0, 1.0)
			sum_pct += ratio
		var avg_pct: float = (sum_pct / float(maxi(1, goals.size())))

		# Stem line down to ground
		draw_line(rc + Vector2(0, ring_r), rc + Vector2(0, ring_r + 18.0 * inv_z), Color("625F57"), 2.0 * inv_z)

		# Left circular multi-arc ring + lock glyph
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
				draw_arc(ring_c, ring_r - 2.2 * inv_z, a0, lerpf(a0, a1, gr), 14, ItIcons.color_of(String(g_d["good"])), 3.6 * inv_z, true)
		draw_rect(Rect2(ring_c - Vector2(4.2 * inv_z, 0.5 * inv_z), Vector2(8.4 * inv_z, 6.8 * inv_z)), Color("23242B"), true)
		draw_arc(ring_c - Vector2(0, 1.2 * inv_z), 3.0 * inv_z, PI, TAU, 12, Color("23242B"), 1.7 * inv_z, true)

		# Right white card with goal bars
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
			ItIcons.draw_shape(self, gid, Vector2(card_r.position.x + 9.5 * inv_z, gy), 9.5 * inv_z)
			var bar_r := Rect2(card_r.position.x + 17.5 * inv_z, gy - 2.2 * inv_z, 46.0 * inv_z, 4.4 * inv_z)
			draw_rect(bar_r, Color(0.14, 0.15, 0.18, 0.14), true)
			draw_rect(Rect2(bar_r.position, Vector2(bar_r.size.x * ratio, bar_r.size.y)), ItIcons.color_of(gid), true)
			var val_s := "%.1f/%.1f" % [cur_v, tgt_v]
			var vcol := Color("2C7442") if ratio >= 0.99 else Color("23242B")
			draw_string(font, Vector2(bar_r.end.x + 3.0 * inv_z, gy + 3.5 * inv_z), val_s, HORIZONTAL_ALIGNMENT_RIGHT, 48.0 * inv_z, int(8.5 * inv_z), vcol)

	func _draw_reward_popup(tst: Dictionary, tp: Vector2, font: Font, inv_z: float) -> void:
		var raw_txt := String(tst["text"])
		var alpha: float = clampf(1.0 - float(tst["age"]) / 1.45, 0.0, 1.0)
		var sc: float = clampf(inv_z, 0.75, 1.35)

		# Authentic RewardPopups dark pill + gold coin for delivery payouts (+$50, ⚡+$100)
		var is_express: bool = raw_txt.begins_with("⚡+")
		if is_express or raw_txt.begins_with("+$"):
			var clean_txt: String = raw_txt.replace("⚡", "")
			var pw: float = (58.0 + float(maxi(0, clean_txt.length() - 4)) * 7.5) * sc
			var ph: float = 22.0 * sc
			var box := Rect2(tp.x - pw * 0.5, tp.y - ph * 0.5, pw, ph)

			# Pill background + warm cream rim (exact RewardPopups colors!)
			draw_rect(box, Color(0.09, 0.12, 0.10, 0.93 * alpha), true)
			draw_rect(box, Color(1.0, 0.93, 0.70, 0.90 * alpha), false, 1.6 * sc)

			# Gold coin on the left
			var coin_c := Vector2(box.position.x + 11.5 * sc, box.position.y + ph * 0.5)
			draw_circle(coin_c, 6.2 * sc, Color(0.78, 0.56, 0.11, alpha))
			draw_circle(coin_c, 4.4 * sc, Color(1.0, 0.84, 0.29, alpha))

			# Bold gold +$50 text on the right
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
