class_name MapView25D
extends Node2D

## Mobile-optimized 2.5D world renderer for Karesidenan Madiun.
## Static terrain, roads, water, and 2.5D buildings are cached in GPU triangle arrays;
## dynamic micro-agents, signals, and 5 overlays use frustum culling for locked 60-120 FPS.

var sim: SimEngine
var camera: Camera2D

var overlay_mode: String = "routes" # routes | traffic | flow | buildings | demand
var dark_theme: bool = false
var perf_preset: String = "balanced" # battery | balanced | ultra

var selected_facility_id: String = ""
var selected_junction_id: String = ""
var selected_road_id: String = ""
var selected_route_id: String = ""
var route_draft_from_id: String = ""
var active_tool: String = "pan"

var _terrain_node: Node2D
var _water_node: Node2D
var _road_node: Node2D
var _extrude_node: Node2D
var _dynamic_node: Node2D

var _water_mat: ShaderMaterial
var _extrude_mat: ShaderMaterial

var _terrain_batch := TriBatch2D.new()
var _water_batch := TriBatch2D.new()
var _road_batch := TriBatch2D.new()
var _extrude_batch := TriBatch2D.new()

var _night_blend: float = 0.0
var _static_dirty: bool = true

func setup(sim_engine: SimEngine, cam: Camera2D) -> void:
	sim = sim_engine
	camera = cam
	sim.map_static_dirty.connect(_on_static_dirty)

	_terrain_node = _StaticBatchLayer.new()
	(_terrain_node as _StaticBatchLayer).batch = _terrain_batch
	_water_node = _StaticBatchLayer.new()
	(_water_node as _StaticBatchLayer).batch = _water_batch
	_road_node = _StaticBatchLayer.new()
	(_road_node as _StaticBatchLayer).batch = _road_batch
	_extrude_node = _StaticBatchLayer.new()
	(_extrude_node as _StaticBatchLayer).batch = _extrude_batch
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
	_extrude_mat.set_shader_parameter("lean_strength", 0.00035 if perf_preset == "battery" else 0.00056)
	_extrude_mat.set_shader_parameter("night_blend", _night_blend)
	_extrude_mat.set_shader_parameter("day_clock", sim.day_clock_01)

	_water_mat.set_shader_parameter("night_blend", _night_blend)
	_water_mat.set_shader_parameter("shimmer_amp", 0.02 if perf_preset == "battery" else 0.075)

	var bg_day := Color("#232933") if dark_theme else Color("#efe8da")
	var bg_night := Color("#121722")
	RenderingServer.set_default_clear_color(bg_day.lerp(bg_night, _night_blend))

	_dynamic_node.queue_redraw()

func get_world_frustum() -> Rect2:
	var vp_size: Vector2 = get_viewport_rect().size
	var half_world: Vector2 = (vp_size * 0.5) / maxf(0.15, camera.zoom.x)
	var margin := Vector2(90.0, 90.0)
	return Rect2(camera.global_position - half_world - margin, (half_world + margin) * 2.0)

func _rebuild_static_batches() -> void:
	_terrain_batch.clear()
	_water_batch.clear()
	_road_batch.clear()
	_extrude_batch.clear()

	var is_dark: bool = dark_theme or sim.night_mode

	# 1. Region polygons (unlocked crisp vs locked misted)
	for reg in sim.regions:
		var unlocked: bool = bool(reg["unlocked"])
		var base_col: Color = GameCatalog.parse_color(String(reg["fillColor"]), Color("#efe8da"))
		if is_dark:
			base_col = base_col.darkened(0.66)
		if not unlocked:
			base_col = base_col.lerp(Color("#1b212c") if is_dark else Color("#dfd8ca"), 0.62)
		var accent_col: Color = GameCatalog.parse_color(String(reg["accentColor"]), Color("#495057"))
		var border_col: Color = accent_col.lerp(Color("#6c757d"), 0.45 if unlocked else 0.72)
		border_col.a = 0.65 if unlocked else 0.35

		for pv in reg["poly_vecs"]:
			_terrain_batch.add_polygon_safe(pv, base_col)
			_terrain_batch.add_polyline(pv, 2.2 if unlocked else 1.4, border_col, true, false)

	# 2. Ecological & Cultural Terrain Patches (Sawah, Hutan Jati Saradan, Kars Gunungsewu, Alun-Alun)
	for p in sim.patches:
		var reg_idx: int = int(p["regionIndex"])
		var unl: bool = sim.unlocked_regions.has(reg_idx)
		var kind_s := String(p["kind"])
		var p_col := Color("#c8deab")
		if kind_s == "jati":
			p_col = Color("#a8c995")
		elif kind_s == "karst":
			p_col = Color("#d2cab8")
		elif kind_s == "alun_alun":
			p_col = Color("#9fd18b")
		if is_dark:
			p_col = p_col.darkened(0.62)
		p_col.a = 0.52 if unl else 0.20
		_terrain_batch.add_rect_rot(
			Vector2(float(p["x"]), float(p["y"])),
			float(p["w"]),
			float(p["h"]),
			float(p["angle"]),
			p_col
		)

	# 3. Water bodies (Samudra Hindia, Telaga Sarangan, Telaga Ngebel) & Rivers (Bengawan Solo, Kali Madiun, Kali Grindulu)
	var water_col := Color("#427aa1") if is_dark else Color("#6baed6")
	var bank_col := Color("#2f4858") if is_dark else Color("#c9bfa9")
	for wb in sim.water_bodies:
		var pv: PackedVector2Array = wb["poly_vec"]
		_terrain_batch.add_polyline(pv, 6.0, bank_col, true, true)
		_water_batch.add_polygon_safe(pv, water_col.darkened(0.08 if String(wb["kind"]) == "ocean" else 0.0))

	for rv in sim.rivers:
		var pts: PackedVector2Array = rv["pts"]
		var w: float = float(rv["widthPx"])
		_terrain_batch.add_polyline(pts, w + 4.5, bank_col, false, true)
		_water_batch.add_polyline(pts, w, water_col, false, true)

	# 4. PT KAI Southern/Central Java Railway Line (crossties + dual rails)
	var tie_col := Color(0.36, 0.30, 0.24, 0.65)
	var rail_col := Color(0.45, 0.49, 0.54, 0.85)
	for rl in sim.railways:
		var rpts: PackedVector2Array = rl["pts"]
		_terrain_batch.add_dashed_polyline(rpts, 6.8, tie_col, 2.4, 5.2, 0.0)
		_terrain_batch.add_polyline(rpts, 2.2, rail_col, false, false)

	# 5. Roads, Bridges, Unpurchased Road Offer Blueprints & Closed-Street Parks
	for r in sim.roads:
		var r_unl: bool = sim.unlocked_regions.has(int(r["regionIndex"]))
		var pts: PackedVector2Array = r["pts"]
		var lanes_total: int = int(r["lanesForward"]) + int(r["lanesBackward"])
		if int(r["oneWay"]) != 0:
			lanes_total = maxi(int(r["lanesForward"]), int(r["lanesBackward"]))
		var width: float = float(lanes_total) * 5.0 + 3.6

		if not bool(r["isBuilt"]):
			if r_unl:
				_road_batch.add_dashed_polyline(pts, width * 0.72, Color(0.18, 0.52, 0.86, 0.38), 10.0, 8.0)
			continue

		var curb_col := Color("#1a1e24") if is_dark else Color("#beb5a4")
		var asphalt := Color("#39404a") if not is_dark else Color("#2d3440")
		if String(r["roadClass"]) == "toll":
			asphalt = Color("#2f3b4c")
		elif String(r["roadClass"]) == "national":
			asphalt = Color("#343b46")
		if not r_unl:
			asphalt = asphalt.lerp(Color("#cfc8b8"), 0.58)
			curb_col.a = 0.35

		if bool(r["isBridge"]):
			_road_batch.add_polyline(pts, width + 6.4, Color("#d48b45") if r_unl else Color("#b8b0a0"), false, false)
		_road_batch.add_polyline(pts, width + 2.4, curb_col, false, true)
		_road_batch.add_polyline(pts, width, asphalt, false, true)

		if bool(r["closed"]):
			_road_batch.add_dashed_polyline(pts, width * 0.65, Color("#4ea854"), 7.0, 5.0)
			continue

		if r_unl:
			if int(r["oneWay"]) == 0:
				var center_col := Color("#f2cc60") if String(r["roadClass"]) == "national" or String(r["roadClass"]) == "toll" else Color(0.92, 0.92, 0.90, 0.68)
				_road_batch.add_dashed_polyline(pts, 1.15, center_col, 7.5, 7.5, 0.0)
			else:
				_add_one_way_chevrons(pts, int(r["oneWay"]) == 1)

	# 6. Junction Geometry (Asphalt pads, 1L & 2L Roundabouts, Yield triangles)
	for j in sim.junctions:
		var j_unl: bool = sim.unlocked_regions.has(int(j["regionIndex"]))
		var jp: Vector2 = j["pos"]
		var ctrl := String(j["control"])
		var pad_col := Color("#343b46") if j_unl else Color("#bab3a4")
		if ctrl == "roundabout" or ctrl == "roundabout2":
			var outer_r: float = 19.5 if ctrl == "roundabout2" else 15.0
			var island_r: float = 6.8
			_road_batch.add_circle(jp, outer_r + 2.0, Color("#beb5a4"), 20)
			_road_batch.add_circle(jp, outer_r, pad_col, 20)
			if ctrl == "roundabout2":
				_road_batch.add_ring(jp, 12.2, 13.3, Color(0.95, 0.85, 0.45, 0.75), 18)
			_road_batch.add_circle(jp, island_r + 1.4, Color("#ded6c6"), 16)
			_road_batch.add_circle(jp, island_r, Color("#5aa454"), 16)
		else:
			_road_batch.add_circle(jp, 7.6, pad_col, 12)
			if ctrl == "yield" and j_unl:
				_road_batch.add_tri(jp + Vector2(0, -6.2), jp + Vector2(5.6, 4.4), jp + Vector2(-5.6, 4.4), Color("#e03131"))
				_road_batch.add_tri(jp + Vector2(0, -3.4), jp + Vector2(3.1, 2.8), jp + Vector2(-3.1, 2.8), Color("#fff9db"))

	# 7. 2.5D Extruded City Buildings & Industrial Facilities (1 GPU draw call!)
	var skip_minor_houses: bool = perf_preset == "battery"
	var b_idx: int = 0
	for b in sim.buildings:
		b_idx += 1
		if skip_minor_houses and (b_idx % 2 == 1) and String(b["kind"]) == "house":
			continue
		var b_unl: bool = sim.unlocked_regions.has(int(b["regionIndex"]))
		var r_col := Color(String(b["roofColor"]))
		var w_col := Color(String(b["wallColor"]))
		if not b_unl:
			r_col = r_col.lerp(Color("#cfc8b8"), 0.65)
			w_col = w_col.lerp(Color("#d8d1c3"), 0.65)
		var win_seed: float = (0.12 + fmod(float(b_idx) * 0.173, 0.82)) if b_unl else 0.0
		_extrude_batch.add_extruded_box_25d(
			Vector2(float(b["x"]), float(b["y"])),
			float(b["w"]),
			float(b["d"]),
			float(b["angle"]),
			float(b["h"]) * (1.0 if b_unl else 0.45),
			r_col,
			w_col,
			win_seed
		)

	var f_idx: int = 0
	for f in sim.facilities:
		f_idx += 1
		var f_unl: bool = sim.unlocked_regions.has(int(f["regionIndex"]))
		var fp: Vector2 = f["pos"]
		var r_col: Color = f["roof_val"]
		var w_col: Color = (f["color_val"] as Color).lightened(0.28)
		if not f_unl:
			r_col = r_col.lerp(Color("#c5beb0"), 0.68)
			w_col = w_col.lerp(Color("#d2cbc0"), 0.68)
		var exp_scale: float = 1.25 if int(f["upgrades"].get("expand", 0)) > 0 else 1.0
		# Concrete industrial lot pad on terrain batch
		_terrain_batch.add_rect_rot(fp, 30.0 * exp_scale, 24.0 * exp_scale, 0.0, Color(0.45, 0.46, 0.48, 0.36 if f_unl else 0.15))
		_extrude_batch.add_extruded_box_25d(
			fp,
			22.0 * exp_scale,
			17.0 * exp_scale,
			0.0,
			16.5 if f_unl else 7.0,
			r_col,
			w_col,
			0.25 + float(f_idx) * 0.13 if f_unl else 0.0
		)

	_terrain_node.queue_redraw()
	_water_node.queue_redraw()
	_road_node.queue_redraw()
	_extrude_node.queue_redraw()

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
	_road_batch.add_tri(c + dir * 5.2, c - dir * 3.6 + nrm * 3.8, c - dir * 3.6 - nrm * 3.8, Color("#74c0fc"))


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
		var font: Font = ThemeDB.fallback_font

		# 1. Selected / Hovered Highlights & Route Creator Preview
		if owner_view.selected_road_id != "" and sim.road_map.has(owner_view.selected_road_id):
			var sr: Dictionary = sim.road_map[owner_view.selected_road_id]
			draw_polyline(sr["pts"], Color(0.18, 0.55, 0.98, 0.55), 14.0, true)

		if owner_view.selected_junction_id != "" and sim.junction_map.has(owner_view.selected_junction_id):
			var sj: Dictionary = sim.junction_map[owner_view.selected_junction_id]
			draw_arc(sj["pos"], 18.0, 0.0, TAU, 28, Color("#2c7be5"), 2.8, true)

		if owner_view.selected_facility_id != "" and sim.facility_map.has(owner_view.selected_facility_id):
			var sf: Dictionary = sim.facility_map[owner_view.selected_facility_id]
			draw_arc(sf["pos"], 22.0, 0.0, TAU, 28, Color("#f59f00"), 3.0, true)

		if owner_view.route_draft_from_id != "" and sim.facility_map.has(owner_view.route_draft_from_id):
			var df: Dictionary = sim.facility_map[owner_view.route_draft_from_id]
			var pulse: float = 20.0 + 4.0 * sin(Time.get_ticks_msec() * 0.008)
			draw_arc(df["pos"], pulse, 0.0, TAU, 28, Color("#00a878"), 3.2, true)

		# 2. Five Analytic Map Overlays
		var mode := owner_view.overlay_mode
		if mode == "routes":
			_draw_routes_overlay(sim, frustum)
		elif mode == "traffic":
			_draw_traffic_heatmap(sim, frustum)
		elif mode == "flow":
			_draw_goods_flow_sankey(sim)
		elif mode == "buildings":
			_draw_buildings_overlay(sim, frustum)
		elif mode == "demand":
			_draw_demand_overlay(sim, font, zoom_x)

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
			var col_a := Color("#e03131")
			var col_b := Color("#e03131")
			if ph == 0:
				col_a = Color("#37b24d") if stg == "green" else (Color("#f59f00") if stg == "yellow" else Color("#e03131"))
			else:
				col_b = Color("#37b24d") if stg == "green" else (Color("#f59f00") if stg == "yellow" else Color("#e03131"))
			draw_circle(jp + Vector2(-5.2, -5.2), 3.1, Color("#14171c"))
			draw_circle(jp + Vector2(-5.2, -5.2), 2.2, col_a)
			draw_circle(jp + Vector2(5.2, 5.2), 3.1, Color("#14171c"))
			draw_circle(jp + Vector2(5.2, 5.2), 2.2, col_b)

		# 4. Station Cargo Trains & Harbour Ships (Pelabuhan Tamperan)
		for f in sim.facilities:
			if not sim.unlocked_regions.has(int(f["regionIndex"])):
				continue
			var fp: Vector2 = f["pos"]
			if not frustum.has_point(fp):
				continue
			var fk := String(f["kind"])
			if fk == "station" and bool(f["vehiclePresent"]):
				draw_rect(Rect2(fp + Vector2(-20, 12), Vector2(40, 6.5)), Color("#364fc7"), true)
				draw_rect(Rect2(fp + Vector2(-17, 13.2), Vector2(10, 4.0)), Color("#ffd43b"), true)
			elif fk == "harbour" and bool(f["vehiclePresent"]):
				var hull := PackedVector2Array([
					fp + Vector2(-24, 15), fp + Vector2(20, 15),
					fp + Vector2(26, 22), fp + Vector2(-20, 22)
				])
				draw_colored_polygon(hull, Color("#1c7ed6"))
				draw_rect(Rect2(fp + Vector2(-12, 11), Vector2(18, 5)), Color("#f08c00"), true)

		# 5. Articulated Multi-Trailer Trucks + Cargo Shapes + Night Headlight Cones
		for ag in sim.agents:
			var st := String(ag["state"])
			if st != "driving_outbound" and st != "driving_return":
				continue
			var ap: Vector2 = ag["pos"]
			if not frustum.has_point(ap):
				continue
			_draw_articulated_truck(ag, owner_view._night_blend)

		# 6. Facility Badges, Geometric Commodity Icons, Bay Pips & Stalled Warnings
		for f in sim.facilities:
			var fp: Vector2 = f["pos"]
			if not frustum.has_point(fp):
				continue
			var f_unl: bool = sim.unlocked_regions.has(int(f["regionIndex"]))
			if not f_unl:
				continue
			_draw_facility_badge(f, sim, font, zoom_x)

		# 7. Locked Region Shields & Landmark Labels
		var inv_z: float = clampf(1.0 / maxf(0.35, zoom_x), 0.55, 1.85)
		for reg in sim.regions:
			var rc: Vector2 = reg["center_vec"]
			if not bool(reg["unlocked"]):
				draw_circle(rc, 18.0 * inv_z, Color(0.14, 0.17, 0.22, 0.86))
				draw_arc(rc, 18.0 * inv_z, 0.0, TAU, 24, Color(String(reg["accentColor"])), 2.4 * inv_z)
				draw_string(font, rc + Vector2(-58.0 * inv_z, -24.0 * inv_z), "🔒 " + String(reg["name"]), HORIZONTAL_ALIGNMENT_CENTER, 116.0 * inv_z, int(13.0 * inv_z), Color("#f8f9fa"))
			elif zoom_x < 0.85:
				draw_string(font, rc + Vector2(-65.0 * inv_z, 0.0), String(reg["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 130.0 * inv_z, int(12.0 * inv_z), Color(0.20, 0.24, 0.30, 0.55) if not owner_view.dark_theme else Color(0.85, 0.88, 0.92, 0.45))

		if zoom_x >= 0.72 and owner_view.perf_preset != "battery":
			for j in sim.junctions:
				if not sim.unlocked_regions.has(int(j["regionIndex"])):
					continue
				if j.get("landmark", null) != null and frustum.has_point(j["pos"]):
					var lm := String(j["landmark"])
					var jp: Vector2 = j["pos"]
					draw_string(font, jp + Vector2(-55, 19), lm, HORIZONTAL_ALIGNMENT_CENTER, 110.0, 10, Color(0.18, 0.21, 0.26, 0.82) if not (owner_view.dark_theme or sim.night_mode) else Color(0.88, 0.91, 0.96, 0.82))

		# 8. Floating Revenue / Expense Toasts
		for tst in sim.floating_toasts:
			var tp: Vector2 = tst["pos"] + Vector2(0.0, -float(tst["age"]) * 22.0)
			if not frustum.has_point(tp):
				continue
			var alpha: float = clampf(1.0 - float(tst["age"]) / 1.45, 0.0, 1.0)
			var c: Color = tst["color"]
			c.a = alpha
			draw_string(font, tp + Vector2(-42, 0), String(tst["text"]), HORIZONTAL_ALIGNMENT_CENTER, 84.0, 12, c)

	func _draw_routes_overlay(sim: SimEngine, frustum: Rect2) -> void:
		var idx: int = 0
		for rt in sim.routes:
			var is_sel: bool = String(rt["id"]) == owner_view.selected_route_id
			var col: Color = rt["color"]
			col.a = 0.88 if is_sel else 0.48
			var w: float = 3.4 if is_sel else 2.0
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
			var hcol: Color = Color("#2f9e44").lerp(Color("#f59f00"), clampf(cong / 0.6, 0.0, 1.0))
			if cong > 0.6:
				hcol = Color("#f59f00").lerp(Color("#e03131"), clampf((cong - 0.6) / 0.6, 0.0, 1.0))
			hcol.a = 0.72
			draw_polyline(r["pts"], hcol, 6.5, true)

	func _draw_goods_flow_sankey(sim: SimEngine) -> void:
		for fk in sim.flow_edges.keys():
			var fe: Dictionary = sim.flow_edges[fk]
			var f_a: Dictionary = sim.facility_map.get(String(fe["fromId"]), {})
			var f_b: Dictionary = sim.facility_map.get(String(fe["toId"]), {})
			if f_a.is_empty() or f_b.is_empty():
				continue
			var rate: float = float((fe["times"] as Array).size())
			var width: float = clampf(2.0 + rate * 0.65, 2.5, 16.0)
			var gcol: Color = GameCatalog.GOODS[String(fe["good"])]["color"]
			gcol.a = 0.74
			var pa: Vector2 = f_a["pos"]
			var pb: Vector2 = f_b["pos"]
			draw_line(pa, pb, gcol, width, true)
			var mid: Vector2 = pa.lerp(pb, 0.55)
			var dir: Vector2 = (pb - pa).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([mid + dir * (width * 1.1 + 4.0), mid - dir * 4.0 + nrm * (width * 0.9 + 3.0), mid - dir * 4.0 - nrm * (width * 0.9 + 3.0)]), gcol.lightened(0.18))

	func _draw_buildings_overlay(sim: SimEngine, frustum: Rect2) -> void:
		for f in sim.facilities:
			if not sim.unlocked_regions.has(int(f["regionIndex"])):
				continue
			var fp: Vector2 = f["pos"]
			if not frustum.has_point(fp):
				continue
			var sr := String(f["stalledReason"])
			var scol := Color("#2f9e44")
			if sr == "missing_input":
				scol = Color("#f59f00")
			elif sr == "output_full":
				scol = Color("#e03131")
			draw_arc(fp, 22.0, 0.0, TAU, 24, scol, 3.6, true)

	func _draw_demand_overlay(sim: SimEngine, font: Font, zoom_x: float) -> void:
		var goal_reg: Dictionary = sim.get_active_goal_region()
		if goal_reg.is_empty():
			return
		var rc: Vector2 = goal_reg["center_vec"]
		var inv_z: float = clampf(1.0 / maxf(0.4, zoom_x), 0.7, 1.6)
		var y_off: float = 16.0 * inv_z
		for g in goal_reg["goals"]:
			var gid := String(g["good"])
			var gdef: Dictionary = GameCatalog.GOODS[gid]
			var txt := "%s: %.1f / %.1f /mnt" % [String(gdef["name"]), float(g.get("currentPerMin", 0.0)), float(g["targetPerMin"])]
			draw_rect(Rect2(rc + Vector2(-68 * inv_z, y_off - 12 * inv_z), Vector2(136 * inv_z, 17 * inv_z)), Color(0.11, 0.14, 0.18, 0.88), true)
			draw_string(font, rc + Vector2(-64 * inv_z, y_off), txt, HORIZONTAL_ALIGNMENT_CENTER, 128 * inv_z, int(11 * inv_z), gdef["color"].lightened(0.25))
			y_off += 20.0 * inv_z

	func _draw_articulated_truck(ag: Dictionary, night_blend: float) -> void:
		var tdef: Dictionary = GameCatalog.TRUCKS[String(ag["model"])]
		var cab_pos: Vector2 = ag["pos"]
		var cab_ang: float = float(ag["heading"])
		var cab_col: Color = tdef["color"]

		# Night headlight cone
		if night_blend > 0.12:
			var fwd := Vector2(cos(cab_ang), sin(cab_ang))
			var side := Vector2(-fwd.y, fwd.x)
			var cone := PackedVector2Array([
				cab_pos + fwd * 4.0,
				cab_pos + fwd * 28.0 + side * 10.5,
				cab_pos + fwd * 28.0 - side * 10.5
			])
			draw_colored_polygon(cone, Color(1.0, 0.94, 0.68, 0.24 * night_blend))

		# Draw trailers back-to-front
		var t_poses: Array = ag["trailerPoses"]
		var c_good := String(ag["cargoGood"])
		var has_cargo: bool = c_good != "" and int(ag["cargoQty"]) > 0
		var cargo_col: Color = GameCatalog.GOODS[c_good]["color"] if has_cargo else Color.WHITE

		for ti in range(t_poses.size() - 1, -1, -1):
			var tp: Vector2 = t_poses[ti]["pos"]
			var tang: float = float(t_poses[ti]["heading"])
			var lead_p: Vector2 = cab_pos if ti == 0 else t_poses[ti - 1]["pos"]
			draw_line(tp, lead_p, Color("#212529"), 1.4)
			_draw_rot_box(tp, 7.6, 4.2, tang, Color("#e9ecef") if not owner_view.dark_theme else Color("#ced4da"))
			if has_cargo:
				_draw_good_glyph(tp, 2.1, c_good, cargo_col)

		# Draw tractor cab
		_draw_rot_box(cab_pos, float(tdef["cab_len"]) * 0.72, 4.4, cab_ang, cab_col)
		var windshield: Vector2 = cab_pos + Vector2(cos(cab_ang), sin(cab_ang)) * 1.6
		_draw_rot_box(windshield, 2.0, 3.3, cab_ang, Color("#182232"))

	func _draw_rot_box(c: Vector2, length: float, width: float, ang: float, col: Color) -> void:
		var ux := Vector2(cos(ang), sin(ang)) * (length * 0.5)
		var uy := Vector2(-sin(ang), cos(ang)) * (width * 0.5)
		draw_colored_polygon(PackedVector2Array([c - ux - uy, c + ux - uy, c + ux + uy, c - ux + uy]), col)

	func _draw_facility_badge(f: Dictionary, sim: SimEngine, font: Font, zoom_x: float) -> void:
		var fp: Vector2 = f["pos"]
		var badge_pos: Vector2 = fp + Vector2(0, -4.0)
		var kind_s := String(f["kind"])
		draw_circle(badge_pos, 8.2, Color("#1b1f27"))
		draw_circle(badge_pos, 6.9, Color("#fbf9f5"))

		if f["outputGood"] != null:
			var gid := String(f["outputGood"])
			_draw_good_glyph(badge_pos, 4.6, gid, GameCatalog.GOODS[gid]["color"])
		elif kind_s == "station":
			draw_rect(Rect2(badge_pos - Vector2(4.2, 3.0), Vector2(8.4, 6.0)), Color("#364fc7"), true)
		elif kind_s == "harbour":
			draw_circle(badge_pos, 4.2, Color("#1c7ed6"))
		else:
			draw_circle(badge_pos, 4.2, Color("#2f9e44"))

		# Bay occupancy pips & output buffer count
		var total_bays: int = mini(6, sim.get_total_bays(f))
		var occ: int = int(f["occupiedBays"])
		var start_x: float = fp.x - float(total_bays - 1) * 2.2
		for bi in range(total_bays):
			var pcol := Color("#f59f00") if bi < occ else Color(0.2, 0.24, 0.3, 0.55)
			draw_circle(Vector2(start_x + float(bi) * 4.4, fp.y + 11.5), 1.6, pcol)

		if String(f["stalledReason"]) != "none":
			var warn_col := Color("#e03131") if String(f["stalledReason"]) == "output_full" else Color("#f59f00")
			draw_circle(fp + Vector2(11.5, -10.5), 4.2, warn_col)

		if zoom_x >= 0.62:
			var short_nm: String = String(f["name"])
			if short_nm.length() > 22:
				short_nm = short_nm.substr(0, 20) + ".."
			var lbl_col := Color("#1c2026") if not (owner_view.dark_theme or sim.night_mode) else Color("#f1f3f5")
			draw_string(font, fp + Vector2(-58, 22), short_nm, HORIZONTAL_ALIGNMENT_CENTER, 116.0, 10, lbl_col)

	func _draw_good_glyph(c: Vector2, r: float, gid: String, col: Color) -> void:
		if gid == "dot" or gid == "pebble" or gid == "moon":
			draw_circle(c, r, col)
		elif gid == "wedge" or gid == "chevron" or gid == "rocket" or gid == "arrow":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.85), c + Vector2(-r, r * 0.85)]), col)
		elif gid == "diamond" or gid == "gem" or gid == "star" or gid == "shield":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)
		else:
			draw_rect(Rect2(c - Vector2(r, r * 0.72), Vector2(r * 2.0, r * 1.44)), col, true)
