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

	# 5 & 6. Multi-Pass Authentic Incremental Traffic RoadBed, Swept Junctions, Roundabouts, Update 1.9 Bridges & RoadPaint
	_build_roads_and_junctions_batches(is_dark)

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

func _build_roads_and_junctions_batches(is_dark: bool) -> void:
	var lht: bool = sim.left_hand_traffic
	var sidewalk_base := Color("2A2E38") if is_dark else COL_SIDEWALK
	var curb_base := Color("181B22") if is_dark else COL_CURB
	var asphalt_base := Color("2B2F3A") if is_dark else COL_ROAD
	var mark_col := Color(COL_LANE_MARK, 0.90 if not is_dark else 0.62)
	var mark_soft := Color(COL_LANE_MARK, 0.76 if not is_dark else 0.50)

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
				_road_batch.add_dashed_polyline(pts, 1.3, bp_dash, 7.5, 6.0, -rw * 0.36)
				_road_batch.add_dashed_polyline(pts, 1.3, bp_dash, 7.5, 6.0, rw * 0.36)
			continue

		for sp in r.get("bridgeSpans", []):
			var b_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, float(sp[0]), float(sp[1]))
			if b_pts.size() >= 2:
				var sh_pts := PackedVector2Array()
				sh_pts.resize(b_pts.size())
				for i in range(b_pts.size()):
					sh_pts[i] = b_pts[i] + Vector2(3.6, 4.6)
				_road_batch.add_smooth_strip(sh_pts, rw + 6.4, shadow_bridge, false, false)

		for osp in r.get("overpassSpans", []):
			var o_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, float(osp[0]), float(osp[1]))
			if o_pts.size() >= 2:
				var osh_pts := PackedVector2Array()
				osh_pts.resize(o_pts.size())
				for i in range(o_pts.size()):
					osh_pts[i] = o_pts[i] + Vector2(4.4, 5.6)
				_road_batch.add_smooth_strip(osh_pts, rw + 7.2, shadow_bridge, false, false)

	# Pass 5.1a: Continuous Sidewalk Layer (roads + swept junction fillets + roundabout outer rings)
	var bg_mute: Color = Color("161920") if is_dark else COL_BG
	for r in sim.roads:
		if not bool(r["isBuilt"]):
			continue
		var r_unl: bool = sim.unlocked_regions.has(int(r["regionIndex"]))
		var sw_c: Color = sidewalk_base if r_unl else sidewalk_base.lerp(bg_mute, 0.62)
		var rw: float = float(r.get("widthPx", RoadGeom.get_road_width(r)))
		var rlen: float = float(r["lengthPx"])
		var bed_s0: float = maxf(0.0, float(r.get("trimStart", 0.0)) - 1.8)
		var bed_s1: float = minf(rlen, rlen - float(r.get("trimEnd", 0.0)) + 1.8)
		if bed_s1 - bed_s0 >= 1.0:
			var bed_pts: PackedVector2Array = RoadGeom.slice_polyline(r["pts"], r["cum_len"], bed_s0, bed_s1)
			_road_batch.add_smooth_strip(bed_pts, rw + 4.8, sw_c, false, false)

	for j in sim.junctions:
		var j_unl: bool = sim.unlocked_regions.has(int(j["regionIndex"]))
		var sw_c: Color = sidewalk_base if j_unl else sidewalk_base.lerp(bg_mute, 0.62)
		var jp: Vector2 = j["pos"]
		var geom: Dictionary = j.get("geom", {})
		var gkind := String(geom.get("kind", "empty"))
		if gkind == "roundabout" or gkind == "roundabout2":
			var r_out: float = float(geom["r_outer"])
			_road_batch.add_circle(jp, r_out + 2.8, sw_c, 32)
			for a in geom["arms"]:
				if a.has("flare_sidewalk"):
					_road_batch.add_polygon_safe(a["flare_sidewalk"], sw_c)
		elif gkind == "standard" and geom.has("swept_sidewalk"):
			_road_batch.add_polygon_safe(geom["swept_sidewalk"], sw_c)
		elif gkind == "culdesac":
			_road_batch.add_circle(jp, float(geom.get("radius", 5.0)) + 2.5, sw_c, 18)

	# Pass 5.1b: Continuous Curb Layer (roads + swept junction curbs + roundabout outer curbs)
	for r in sim.roads:
		if not bool(r["isBuilt"]):
			continue
		var r_unl: bool = sim.unlocked_regions.has(int(r["regionIndex"]))
		var cb_c: Color = curb_base if r_unl else curb_base.lerp(bg_mute, 0.58)
		var rw: float = float(r.get("widthPx", RoadGeom.get_road_width(r)))
		var rlen: float = float(r["lengthPx"])
		var bed_s0: float = maxf(0.0, float(r.get("trimStart", 0.0)) - 1.8)
		var bed_s1: float = minf(rlen, rlen - float(r.get("trimEnd", 0.0)) + 1.8)
		if bed_s1 - bed_s0 >= 1.0:
			var bed_pts: PackedVector2Array = RoadGeom.slice_polyline(r["pts"], r["cum_len"], bed_s0, bed_s1)
			_road_batch.add_smooth_strip(bed_pts, rw + 2.1, cb_c, false, false)

	for j in sim.junctions:
		var j_unl: bool = sim.unlocked_regions.has(int(j["regionIndex"]))
		var cb_c: Color = curb_base if j_unl else curb_base.lerp(bg_mute, 0.58)
		var jp: Vector2 = j["pos"]
		var geom: Dictionary = j.get("geom", {})
		var gkind := String(geom.get("kind", "empty"))
		if gkind == "roundabout" or gkind == "roundabout2":
			var r_out: float = float(geom["r_outer"])
			_road_batch.add_circle(jp, r_out + 1.2, cb_c, 32)
			for a in geom["arms"]:
				if a.has("flare_curb"):
					_road_batch.add_polygon_safe(a["flare_curb"], cb_c)
		elif gkind == "standard" and geom.has("swept_curb"):
			_road_batch.add_polygon_safe(geom["swept_curb"], cb_c)
		elif gkind == "culdesac":
			_road_batch.add_circle(jp, float(geom.get("radius", 5.0)) + 1.1, cb_c, 18)

	# Pass 5.2: Unified Monolithic Asphalt Surface (zero curb seams across intersections or roundabouts!)
	for r in sim.roads:
		if not bool(r["isBuilt"]):
			continue
		var r_unl: bool = sim.unlocked_regions.has(int(r["regionIndex"]))
		var asph: Color = asphalt_base if r_unl else asphalt_base.lerp(bg_mute, 0.52)
		var rw: float = float(r.get("widthPx", RoadGeom.get_road_width(r)))
		var rlen: float = float(r["lengthPx"])
		var bed_s0: float = maxf(0.0, float(r.get("trimStart", 0.0)) - 1.8)
		var bed_s1: float = minf(rlen, rlen - float(r.get("trimEnd", 0.0)) + 1.8)
		if bed_s1 - bed_s0 >= 1.0:
			var bed_pts: PackedVector2Array = RoadGeom.slice_polyline(r["pts"], r["cum_len"], bed_s0, bed_s1)
			_road_batch.add_smooth_strip(bed_pts, rw, asph, false, false)

	for j in sim.junctions:
		var j_unl: bool = sim.unlocked_regions.has(int(j["regionIndex"]))
		var asph: Color = asphalt_base if j_unl else asphalt_base.lerp(bg_mute, 0.52)
		var jp: Vector2 = j["pos"]
		var geom: Dictionary = j.get("geom", {})
		var gkind := String(geom.get("kind", "empty"))
		if gkind == "roundabout" or gkind == "roundabout2":
			var r_out: float = float(geom["r_outer"])
			_road_batch.add_circle(jp, r_out, asph, 34)
			for a in geom["arms"]:
				if a.has("flare_asphalt"):
					_road_batch.add_polygon_safe(a["flare_asphalt"], asph)
		elif gkind == "standard" and geom.has("swept_asphalt"):
			_road_batch.add_polygon_safe(geom["swept_asphalt"], asph)
		elif gkind == "culdesac":
			_road_batch.add_circle(jp, float(geom.get("radius", 5.0)), asph, 18)

	# Pass 5.3: Roundabout Central Landscaped Islands & Approach Splitter Islands
	for j in sim.junctions:
		var geom: Dictionary = j.get("geom", {})
		var gkind := String(geom.get("kind", "empty"))
		if gkind != "roundabout" and gkind != "roundabout2":
			continue
		var j_unl: bool = sim.unlocked_regions.has(int(j["regionIndex"]))
		var jp: Vector2 = j["pos"]
		var r_isl: float = float(geom["r_island"])
		var r_out: float = float(geom["r_outer"])

		var apron_c := Color("EAE6DA") if not is_dark else Color("494F5C")
		var isl_curb := Color("ACA79B") if not is_dark else Color("2E333E")
		var isl_grass := Color("6E9953") if not is_dark else Color("33492D")
		if not j_unl:
			apron_c = apron_c.lerp(COL_BG, 0.55)
			isl_curb = isl_curb.lerp(COL_BG, 0.55)
			isl_grass = isl_grass.lerp(COL_BG, 0.55)

		# Crisp outer paved truck-apron + stone curb + landscaped green island
		_road_batch.add_circle(jp, r_isl + 1.5, apron_c, 28)
		_road_batch.add_circle(jp, r_isl + 0.4, isl_curb, 26)
		_road_batch.add_circle(jp, maxf(2.4, r_isl - 0.8), isl_grass, 26)

		if j_unl:
			if j.get("landmark", null) != null and r_isl >= 5.6:
				# Subtle Tugu / Bundaran monument plinth at landmark roundabouts (e.g. Bundaran Taman / Serayu)
				_road_batch.add_rect_rot(jp + Vector2(0.8, 1.0), 4.8, 4.8, PI * 0.25, COL_SHADOW)
				_road_batch.add_rect_rot(jp, 4.4, 4.4, PI * 0.25, Color("E8E3D6") if not is_dark else Color("6A7080"))
				_road_batch.add_circle(jp, 1.4, Color("D97A3E"), 10)
			elif r_isl >= 5.2:
				_road_batch.add_circle(jp + Vector2(-1.3, -0.9), 2.1, COL_TREE_B if not is_dark else COL_TREE_B.darkened(0.45), 10)
				_road_batch.add_circle(jp + Vector2(1.5, 1.1), 1.7, COL_TREE_AUTUMN if not is_dark else COL_TREE_AUTUMN.darkened(0.45), 10)

			# Triangular splitter islands on two-way roundabout arms
			for a in geom["arms"]:
				if int(a["one_way"]) == 0 and not bool(a["closed"]) and float(a["rlen"]) >= r_out + 24.0:
					var u_out: Vector2 = a["throat_out_dir"]
					var rn := Vector2(-u_out.y, u_out.x)
					var p_inner: Vector2 = jp + u_out * (r_out + 1.4)
					var p_tip: Vector2 = jp + u_out * (r_out + 8.6)
					var sp_hw: float = clampf(float(a["hw"]) * 0.22, 1.2, 2.3)
					_road_batch.add_tri(p_tip, p_inner - rn * (sp_hw + 0.5), p_inner + rn * (sp_hw + 0.5), apron_c)
					_road_batch.add_tri(p_tip - u_out * 1.1, p_inner - rn * sp_hw + u_out * 0.5, p_inner + rn * sp_hw + u_out * 0.5, isl_curb)

	# Pass 5.4: Update 1.9 River-Crossing Bridges (strictly over river spans!) & Grade-Separated Overpasses
	for r in sim.roads:
		if not bool(r["isBuilt"]):
			continue
		var r_unl: bool = sim.unlocked_regions.has(int(r["regionIndex"]))
		var pts: PackedVector2Array = r["pts"]
		var cum: PackedFloat32Array = r["cum_len"]
		var rw: float = float(r.get("widthPx", RoadGeom.get_road_width(r)))
		var asph: Color = asphalt_base if r_unl else asphalt_base.lerp(COL_BG, 0.52)

		var b_spans: Array = r.get("bridgeSpans", [])
		if not b_spans.is_empty():
			var pier_dark := Color("948F83") if not is_dark else Color("323742")
			var pier_cap := Color("C8C2B4") if not is_dark else Color("505664")
			var deck_walk := Color("DFDBD0") if not is_dark else Color("434956")
			var parapet_top := Color("F5F2EA") if not is_dark else Color("6A7282")
			var parapet_in := Color(0.14, 0.15, 0.19, 0.52)
			if not r_unl:
				deck_walk = deck_walk.lerp(COL_BG, 0.5)
				parapet_top = parapet_top.lerp(COL_BG, 0.5)
				pier_cap = pier_cap.lerp(COL_BG, 0.5)

			for sp in b_spans:
				var s0: float = float(sp[0])
				var s1: float = float(sp[1])
				var span_len: float = s1 - s0
				var b_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, s0, s1)
				if b_pts.size() < 2:
					continue

				# Bank abutment piers at s0 & s1 + intermediate river piers on wide Bengawan/Kali crossings
				var pier_s_list: Array[float] = [s0, s1]
				if span_len >= 52.0:
					var n_mid: int = int(floor(span_len / 44.0))
					for mi in range(1, n_mid + 1):
						pier_s_list.append(lerpf(s0, s1, float(mi) / float(n_mid + 1)))
				for ps in pier_s_list:
					var pr_raw: Dictionary = RoadGeom.sample_polyline_raw(pts, cum, ps)
					var p_ang: float = atan2((pr_raw["dir"] as Vector2).y, (pr_raw["dir"] as Vector2).x)
					_road_batch.add_rect_rot(pr_raw["pos"], 4.8, rw + 8.6, p_ang, pier_dark)
					_road_batch.add_rect_rot(pr_raw["pos"], 3.4, rw + 7.4, p_ang, pier_cap)

				# Bridge concrete sidewalk deck + roadways + crisp left/right raised stone parapet rails
				_road_batch.add_smooth_strip(b_pts, rw + 5.8, deck_walk, false, false)
				_road_batch.add_smooth_strip(b_pts, rw, asph, false, false)
				var rail_off: float = rw * 0.5 + 2.2
				var inner_off: float = rw * 0.5 + 1.15
				_road_batch.add_smooth_strip(b_pts, 1.55, parapet_top, false, false, -rail_off)
				_road_batch.add_smooth_strip(b_pts, 1.55, parapet_top, false, false, rail_off)
				_road_batch.add_smooth_strip(b_pts, 0.70, parapet_in, false, false, -inner_off)
				_road_batch.add_smooth_strip(b_pts, 0.70, parapet_in, false, false, inner_off)

		var o_spans: Array = r.get("overpassSpans", [])
		if not o_spans.is_empty():
			var ov_deck := Color("CFD4DC") if not is_dark else Color("49505E")
			var ov_rail := Color("ECEFF4") if not is_dark else Color("6F788A")
			for osp in o_spans:
				var os0: float = float(osp[0])
				var os1: float = float(osp[1])
				var o_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, os0, os1)
				if o_pts.size() < 2:
					continue
				_road_batch.add_smooth_strip(o_pts, rw + 5.0, ov_deck, false, false)
				_road_batch.add_smooth_strip(o_pts, rw, asph, false, false)
				var or_off: float = rw * 0.5 + 2.0
				_road_batch.add_smooth_strip(o_pts, 1.4, ov_rail, false, false, -or_off)
				_road_batch.add_smooth_strip(o_pts, 1.4, ov_rail, false, false, or_off)

	# Pass 5.5: Strictly Trimmed RoadPaint Markings, Closed-Street Plazas, Stop/Yield Bars & Turn Arrows
	for r in sim.roads:
		if not bool(r["isBuilt"]) or not sim.unlocked_regions.has(int(r["regionIndex"])):
			continue
		var pts: PackedVector2Array = r["pts"]
		var cum: PackedFloat32Array = r["cum_len"]
		var rlen: float = float(r["lengthPx"])
		var rw: float = float(r.get("widthPx", RoadGeom.get_road_width(r)))
		var p_s0: float = float(r.get("trimStart", 0.0)) + 0.6
		var p_s1: float = rlen - float(r.get("trimEnd", 0.0)) - 0.6
		if p_s1 - p_s0 < 4.0:
			continue

		if bool(r["closed"]):
			# Authentic pedestrianized park street (trimmed cleanly outside junctions!)
			var c_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, p_s0 + 1.5, p_s1 - 1.5)
			if c_pts.size() >= 2:
				var lawn_c := COL_GRASS if not is_dark else COL_GRASS.darkened(0.55)
				var path_c := COL_SIDEWALK if not is_dark else Color("454B58")
				_road_batch.add_smooth_strip(c_pts, rw * 0.78, lawn_c, false, false)
				_road_batch.add_smooth_strip(c_pts, rw * 0.28, path_c, false, false)
				for end_s in [p_s0 + 1.2, p_s1 - 1.2]:
					var b_raw: Dictionary = RoadGeom.sample_polyline_raw(pts, cum, end_s)
					var b_pos: Vector2 = b_raw["pos"]
					var b_rn: Vector2 = b_raw["right"]
					for bi in [-1, 0, 1]:
						var bp: Vector2 = b_pos + b_rn * (float(bi) * rw * 0.28)
						_road_batch.add_circle(bp, 1.45, Color("C8323A"), 8)
						_road_batch.add_circle(bp, 0.75, COL_LANE_MARK, 8)
			continue

		var ow: int = int(r["oneWay"])
		var lf: int = maxi(1, int(r["lanesForward"]))
		var lb: int = maxi(1, int(r["lanesBackward"]))
		var m_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, p_s0, p_s1)
		if m_pts.size() < 2:
			continue

		var j_u: Dictionary = sim.junction_map.get(String(r["from"]), {})
		var j_v: Dictionary = sim.junction_map.get(String(r["to"]), {})
		var u_multi: bool = ((j_u.get("geom", {}) as Dictionary).get("arms", []) as Array).size() >= 3 or String(j_u.get("control", "")) == "lights"
		var v_multi: bool = ((j_v.get("geom", {}) as Dictionary).get("arms", []) as Array).size() >= 3 or String(j_v.get("control", "")) == "lights"

		if ow == 0:
			var tot_l: int = lf + lb
			var asym_shift: float = float(lf - lb) * 0.5 * RoadGeom.LANE_WIDTH
			var div_off: float = asym_shift if not lht else -asym_shift

			if String(r["roadClass"]) == "toll" or tot_l >= 4:
				# Double solid arterial/highway median line + hatched gore chevron near signalized junctions!
				_road_batch.add_smooth_strip(m_pts, 0.82, mark_col, false, false, div_off - 0.62)
				_road_batch.add_smooth_strip(m_pts, 0.82, mark_col, false, false, div_off + 0.62)
				if p_s1 - p_s0 >= 44.0:
					if String(j_u.get("control", "")) == "lights":
						_add_hatched_median_gore(pts, cum, p_s0 + 1.0, p_s0 + 15.5, div_off, mark_soft)
					if String(j_v.get("control", "")) == "lights":
						_add_hatched_median_gore(pts, cum, p_s1 - 15.5, p_s1 - 1.0, div_off, mark_soft)
			else:
				# Two-lane road: solid pre-junction throat centerline + crisp dashed mid-block centerline
				var solid_u: float = 11.0 if (u_multi and p_s1 - p_s0 >= 30.0) else 0.0
				var solid_v: float = 11.0 if (v_multi and p_s1 - p_s0 >= 30.0) else 0.0
				if solid_u > 0.0:
					var su_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, p_s0, p_s0 + solid_u)
					_road_batch.add_smooth_strip(su_pts, 1.05, mark_col, false, false, div_off)
				if solid_v > 0.0:
					var sv_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, p_s1 - solid_v, p_s1)
					_road_batch.add_smooth_strip(sv_pts, 1.05, mark_col, false, false, div_off)
				var mid_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, p_s0 + solid_u + 1.5, p_s1 - solid_v - 1.5)
				if mid_pts.size() >= 2:
					_road_batch.add_dashed_polyline(mid_pts, 1.02, mark_soft, 6.2, 6.8, div_off)

			# Same-direction multi-lane dashed dividers (turning solid right before traffic lights!)
			if lf > 1:
				var sol_end: float = 10.5 if (v_multi and p_s1 - p_s0 >= 28.0) else 0.0
				var lf_dash_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, p_s0 + 1.0, p_s1 - sol_end - 1.0)
				var lf_sol_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, p_s1 - sol_end, p_s1) if sol_end > 0.0 else PackedVector2Array()
				for k in range(lf - 1):
					var lat_a: float = RoadGeom.get_lane_lateral_offset(0, float(k), lf, lb, lht)
					var lat_b: float = RoadGeom.get_lane_lateral_offset(0, float(k + 1), lf, lb, lht)
					var b_lat: float = 0.5 * (lat_a + lat_b)
					if lf_dash_pts.size() >= 2:
						_road_batch.add_dashed_polyline(lf_dash_pts, 0.90, mark_soft, 5.4, 6.4, b_lat)
					if lf_sol_pts.size() >= 2:
						_road_batch.add_smooth_strip(lf_sol_pts, 0.95, mark_col, false, false, b_lat)

			if lb > 1:
				var sol_start: float = 10.5 if (u_multi and p_s1 - p_s0 >= 28.0) else 0.0
				var lb_dash_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, p_s0 + sol_start + 1.0, p_s1 - 1.0)
				var lb_sol_pts: PackedVector2Array = RoadGeom.slice_polyline(pts, cum, p_s0, p_s0 + sol_start) if sol_start > 0.0 else PackedVector2Array()
				for k in range(lb - 1):
					# Note: backward direction has opposite right_vec, so negate lateral offset relative to forward pts!
					var lat_a: float = -RoadGeom.get_lane_lateral_offset(0, float(k), lb, lf, lht)
					var lat_b: float = -RoadGeom.get_lane_lateral_offset(0, float(k + 1), lb, lf, lht)
					var b_lat: float = 0.5 * (lat_a + lat_b)
					if lb_dash_pts.size() >= 2:
						_road_batch.add_dashed_polyline(lb_dash_pts, 0.90, mark_soft, 5.4, 6.4, b_lat)
					if lb_sol_pts.size() >= 2:
						_road_batch.add_smooth_strip(lb_sol_pts, 0.95, mark_col, false, false, b_lat)
		else:
			# One-way road lane dividers + crisp one-way chevrons
			var lanes_ow: int = lf if ow > 0 else lb
			var sign_ow: float = 1.0 if ow > 0 else -1.0
			for k in range(lanes_ow - 1):
				var lat_a: float = sign_ow * RoadGeom.get_lane_lateral_offset(ow, float(k), lanes_ow, lanes_ow, lht)
				var lat_b: float = sign_ow * RoadGeom.get_lane_lateral_offset(ow, float(k + 1), lanes_ow, lanes_ow, lht)
				_road_batch.add_dashed_polyline(m_pts, 0.90, mark_soft, 5.4, 6.4, 0.5 * (lat_a + lat_b))
			var mid_s: float = 0.5 * (p_s0 + p_s1)
			var ow_raw: Dictionary = RoadGeom.sample_polyline_raw(pts, cum, mid_s)
			var ow_dir: Vector2 = (ow_raw["dir"] as Vector2) * sign_ow
			_add_lane_turn_arrow(ow_raw["pos"], ow_dir, Vector2(-ow_dir.y, ow_dir.x), false, true, false, mark_col)

	# Pass 5.6: Junction Stop Bars, Yield Shark-Teeth, Roundabout Dashed Dividers & Approach Turn Arrows
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
				_road_batch.add_dashed_ring(jp, 0.5 * (r_isl + r_out), 1.0, mark_soft, 18, 0.48)
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

func _add_hatched_median_gore(pts: PackedVector2Array, cum: PackedFloat32Array, s0: float, s1: float, lat_off: float, col: Color) -> void:
	var s_cur: float = s0 + 1.5
	while s_cur < s1 - 1.2:
		var raw: Dictionary = RoadGeom.sample_polyline_raw(pts, cum, s_cur)
		var c: Vector2 = (raw["pos"] as Vector2) + (raw["right"] as Vector2) * lat_off
		var d: Vector2 = raw["dir"]
		var rn: Vector2 = raw["right"]
		_road_batch.add_smooth_strip(
			PackedVector2Array([c - rn * 1.15 - d * 0.9, c + rn * 1.15 + d * 0.9]),
			0.75, col, false, false
		)
		s_cur += 2.8

func _add_approach_control_and_arrows(
	j: Dictionary,
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
	var in_fwd: bool = not is_start # Entering J moves toward from-node if is_start, else toward to-node
	var ow: int = int(r["oneWay"])
	var lanes_in: int = maxi(1, int(r["lanesForward"]) if in_fwd else int(r["lanesBackward"]))
	var lanes_opp: int = maxi(1, int(r["lanesBackward"]) if in_fwd else int(r["lanesForward"]))

	var p_th: Vector2 = a["throat_pos"]
	var u_out: Vector2 = a["throat_out_dir"]
	var in_dir: Vector2 = -u_out # Unit vector pointing INTO junction J
	var in_right := Vector2(-in_dir.y, in_dir.x)

	var lat_outer: float = RoadGeom.get_lane_lateral_offset(ow, 0.0, lanes_in, lanes_opp, lht)
	var lat_inner: float = RoadGeom.get_lane_lateral_offset(ow, float(lanes_in - 1), lanes_in, lanes_opp, lht)
	var half_span: float = RoadGeom.LANE_WIDTH * 0.46
	var min_lat: float = minf(lat_outer, lat_inner) - half_span
	var max_lat: float = maxf(lat_outer, lat_inner) + half_span

	if line_mode == "stop_bar":
		# Crisp solid white stop bar strictly across incoming lanes (exact match to game_stop.webp!)
		var bar_a: Vector2 = p_th + in_right * min_lat
		var bar_b: Vector2 = p_th + in_right * max_lat
		_road_batch.add_smooth_strip(PackedVector2Array([bar_a, bar_b]), 1.85, mark_col, false, false)
	elif line_mode == "yield_teeth" or line_mode == "roundabout_yield":
		# Crisp white shark-teeth yield line across incoming lanes
		var span_w: float = max_lat - min_lat
		var n_teeth: int = maxi(2, int(round(span_w / 2.6)))
		var step_w: float = span_w / float(n_teeth)
		var line_pos: Vector2 = p_th + (in_dir * 2.2 if line_mode == "roundabout_yield" else Vector2.ZERO)
		for ti in range(n_teeth):
			var c_lat: float = min_lat + (float(ti) + 0.5) * step_w
			var tc: Vector2 = line_pos + in_right * c_lat
			var tw: float = step_w * 0.36
			_road_batch.add_tri(tc + in_dir * 1.45, tc - in_dir * 0.85 - in_right * tw, tc - in_dir * 0.85 + in_right * tw, mark_col)
		if line_mode == "yield_teeth":
			# Neat roadside Yield sign on the outer curb (never blocking the roadway!)
			var curb_lat: float = (min_lat - 2.6) if lht else (max_lat + 2.6)
			var sign_c: Vector2 = p_th - in_dir * 2.0 + in_right * curb_lat
			_road_batch.add_tri(sign_c + in_dir * 2.7, sign_c - in_dir * 1.9 - in_right * 2.5, sign_c - in_dir * 1.9 + in_right * 2.5, Color("C8323A"))
			_road_batch.add_tri(sign_c + in_dir * 1.4, sign_c - in_dir * 1.1 - in_right * 1.3, sign_c - in_dir * 1.1 + in_right * 1.3, Color("FAF7EE"))

	# Paint crisp lane turn arrows behind the stop/yield line on approaches with room
	var rlen: float = float(a["rlen"])
	var trim: float = float(a["trim"])
	if rlen - trim < 23.0:
		return
	var turns: Dictionary = a.get("turns", {"left": false, "straight": true, "right": false})
	var t_l: bool = bool(turns.get("left", false))
	var t_s: bool = bool(turns.get("straight", true))
	var t_r: bool = bool(turns.get("right", false))
	if line_mode == "roundabout_yield":
		# Entering roundabout deflects left in LHT, right in RHT
		t_l = lht
		t_s = true
		t_r = not lht

	var s_arrow: float = (trim + 8.2) if is_start else (rlen - trim - 8.2)
	var raw_ar: Dictionary = RoadGeom.sample_polyline_raw(r["pts"], r["cum_len"], s_arrow)
	var ar_dir: Vector2 = -(raw_ar["dir"] as Vector2) if is_start else (raw_ar["dir"] as Vector2)
	var ar_right := Vector2(-ar_dir.y, ar_dir.x)
	var ar_center_road: Vector2 = raw_ar["pos"]

	for li in range(lanes_in):
		var lat_l: float = RoadGeom.get_lane_lateral_offset(ow, float(li), lanes_in, lanes_opp, lht)
		var lane_c: Vector2 = ar_center_road + ar_right * lat_l
		var l_flag := t_l
		var s_flag := t_s
		var r_flag := t_r
		if lanes_in >= 2 and line_mode != "roundabout_yield":
			if lht:
				# Lane 0 = leftmost curb lane, Lane lanes_in-1 = rightmost inner lane
				if li == 0:
					r_flag = false
					if not l_flag:
						s_flag = true
				elif li == lanes_in - 1:
					l_flag = false
					if not r_flag:
						s_flag = true
				else:
					l_flag = false
					r_flag = false
					s_flag = true
			else:
				if li == 0:
					l_flag = false
					if not r_flag:
						s_flag = true
				elif li == lanes_in - 1:
					r_flag = false
					if not l_flag:
						s_flag = true
				else:
					l_flag = false
					r_flag = false
					s_flag = true
		if not l_flag and not s_flag and not r_flag:
			s_flag = true
		_add_lane_turn_arrow(lane_c, ar_dir, ar_right, l_flag, s_flag, r_flag, mark_soft)

func _add_lane_turn_arrow(
	c: Vector2,
	dir: Vector2,
	right_n: Vector2,
	allow_left: bool,
	allow_straight: bool,
	allow_right: bool,
	col: Color
) -> void:
	var stem_end: float = 1.2 if allow_straight else 0.4
	_road_batch.add_smooth_strip(
		PackedVector2Array([c - dir * 2.7, c + dir * stem_end]),
		0.86, col, false, false
	)
	if allow_straight:
		_road_batch.add_tri(
			c + dir * 3.3,
			c + dir * 1.0 - right_n * 1.45,
			c + dir * 1.0 + right_n * 1.45,
			col
		)
	if allow_left:
		var p_branch: Vector2 = c + dir * 0.2
		var p_tip_base: Vector2 = c + dir * 0.7 - right_n * 1.65
		_road_batch.add_smooth_strip(PackedVector2Array([p_branch, p_tip_base]), 0.78, col, false, false)
		_road_batch.add_tri(
			c + dir * 0.85 - right_n * 3.1,
			p_tip_base + dir * 1.15,
			p_tip_base - dir * 1.05,
			col
		)
	if allow_right:
		var p_branch_r: Vector2 = c + dir * 0.2
		var p_tip_base_r: Vector2 = c + dir * 0.7 + right_n * 1.65
		_road_batch.add_smooth_strip(PackedVector2Array([p_branch_r, p_tip_base_r]), 0.78, col, false, false)
		_road_batch.add_tri(
			c + dir * 0.85 + right_n * 3.1,
			p_tip_base_r - dir * 1.05,
			p_tip_base_r + dir * 1.15,
			col
		)


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

		# 1. Active Rule-Hint Rings (rule_hints.gdshader style) & Selected Junction Lane-Connector Bands
		var tool_s := owner_view.active_tool
		if tool_s == "yield" or tool_s == "roundabout" or tool_s == "lights":
			var rot_phase: float = float(Time.get_ticks_msec()) * 0.0012
			for j_hint in sim.junctions:
				if not sim.unlocked_regions.has(int(j_hint["regionIndex"])):
					continue
				var jhp: Vector2 = j_hint["pos"]
				if not frustum.has_point(jhp):
					continue
				var arms_h: Array = (j_hint.get("geom", {}) as Dictionary).get("arms", [])
				if arms_h.size() < 3:
					continue
				var hr: float = maxf(18.0, float((j_hint.get("geom", {}) as Dictionary).get("r_outer", 12.0)) + 5.5)
				for di in range(10):
					var a0: float = rot_phase + TAU * (float(di) / 10.0)
					draw_arc(jhp, hr, a0, a0 + TAU * 0.052, 5, Color(0.33, 0.56, 0.88, 0.62), 1.8, true)

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

		# 3. Authentic Corner-Mounted Circular Traffic Light Signal Heads (matching game_stop.webp & game_lights.webp!)
		for j in sim.junctions:
			if String(j["control"]) != "lights" or not j.has("light"):
				continue
			if not sim.unlocked_regions.has(int(j["regionIndex"])):
				continue
			var jp: Vector2 = j["pos"]
			if not frustum.has_point(jp):
				continue
			var lt: Dictionary = j["light"]
			var stg := String(lt["stage"])
			var ph: int = int(lt["currentPhase"])
			var geom_j: Dictionary = j.get("geom", {})
			var arms_j: Array = geom_j.get("arms", [])
			for a in arms_j:
				if not bool(a["can_enter"]):
					continue
				var eid_a := String(a["edge_id"])
				var arm_phase: int = sim.get_edge_phase_at_junction(j, eid_a)
				var lens_col := Color("D4383B")
				if arm_phase == ph:
					lens_col = Color("4FB35E") if stg == "green" else (Color("F2AB37") if stg == "yellow" else Color("D4383B"))
				var p_th: Vector2 = a["throat_pos"]
				var in_dir: Vector2 = -(a["throat_out_dir"] as Vector2)
				var in_right := Vector2(-in_dir.y, in_dir.x)
				var hw_a: float = float(a["hw"])
				var curb_side: float = -(hw_a + 3.1) if sim.left_hand_traffic else (hw_a + 3.1)
				var sig_pos: Vector2 = p_th - in_dir * 1.4 + in_right * curb_side
				draw_circle(sig_pos + Vector2(0.5, 0.8), 3.6, Color(0, 0, 0, 0.22))
				draw_circle(sig_pos, 3.6, Color("23242B"))
				draw_circle(sig_pos, 2.45, lens_col)

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

	func _draw_selected_junction_bands_and_ring(sj: Dictionary, sim: SimEngine) -> void:
		var jp: Vector2 = sj["pos"]
		var geom: Dictionary = sj.get("geom", {})
		var arms: Array = geom.get("arms", [])
		var r_ring: float = maxf(22.0, float(geom.get("r_outer", 14.0)) + 8.5)
		var ctrl := String(sj["control"])
		var active_ph: int = int((sj.get("light", {}) as Dictionary).get("currentPhase", 0)) if ctrl == "lights" else -1

		# Translucent colored lane-connector bands across the junction (matching steam_u17_lane_bands.png & game_lights.webp!)
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
			var is_green_arm: bool = (ctrl == "lights" and sim.get_edge_phase_at_junction(sj, eid_in) == active_ph)

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
				var out_lanes: int = maxi(1, int(r_out["lanesForward"]) if out_fwd else int(r_out["lanesBackward"]))
				var v_out: Vector2 = a_out["out_dir"]
				var tang: float = atan2(v_in.x * v_out.y - v_in.y * v_out.x, v_in.dot(v_out))

				var band_col: Color
				var alpha_b: float = 0.46 if is_green_arm else (0.18 if ctrl == "lights" else 0.30)
				if absf(tang) <= deg_to_rad(38.0):
					band_col = Color(0.28, 0.70, 0.45, alpha_b) # Straight: emerald green
				elif tang > 0.0:
					band_col = Color(0.90, 0.50, 0.22, alpha_b) # Right: warm orange
				else:
					band_col = Color(0.45, 0.48, 0.86, alpha_b) # Left: periwinkle blue

				var chosen_in_l: int = 0
				if in_lanes >= 2:
					if sim.left_hand_traffic:
						chosen_in_l = (in_lanes - 1) if tang > deg_to_rad(38.0) else 0
					else:
						chosen_in_l = (in_lanes - 1) if tang < -deg_to_rad(38.0) else 0
				var chosen_out_l: int = mini(chosen_in_l, out_lanes - 1)

				var c_pts: PackedVector2Array = RoadGeom.build_turn_connector_pts(
					sj, r_in, in_fwd, float(chosen_in_l), in_lanes,
					r_out, out_fwd, float(chosen_out_l), out_lanes, sim.left_hand_traffic
				)
				if c_pts.size() >= 2:
					draw_polyline(c_pts, band_col, 2.8 if is_green_arm else 2.2, true)

		# Crisp thin blue inspection ring (exact match to steam_u17_lane_bands.png & game_lights.webp!)
		draw_arc(jp, r_ring, 0.0, TAU, 40, Color(0.35, 0.56, 0.86, 0.88), 1.8, true)

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
