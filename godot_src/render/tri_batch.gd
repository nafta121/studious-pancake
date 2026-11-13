class_name TriBatch2D
extends RefCounted

## Low-level RenderingServer & ArrayMesh triangle batcher for zero-overhead 2D/2.5D cartography on Android.
## Supports both fast `canvas_item_add_triangle_array` and GPU `CUSTOM0` (`ARRAY_CUSTOM_RGBA_FLOAT`)
## via `ArrayMesh` for authentic Incremental Traffic shaders (`city_building`, `city_shadow`,
## `cloud_puff`, and `rule_hints`).

var verts := PackedVector2Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var custom0 := PackedFloat32Array()
var indices := PackedInt32Array()
var has_custom0: bool = false

func clear() -> void:
	verts.clear()
	colors.clear()
	uvs.clear()
	custom0.clear()
	indices.clear()
	has_custom0 = false

func is_empty() -> bool:
	return indices.is_empty()

func _ensure_custom0() -> void:
	if has_custom0:
		return
	has_custom0 = true
	custom0.resize(verts.size() * 4)
	custom0.fill(0.0)

func _push_c0(c0: Color) -> void:
	if has_custom0:
		custom0.append(c0.r)
		custom0.append(c0.g)
		custom0.append(c0.b)
		custom0.append(c0.a)

func add_tri(a: Vector2, b: Vector2, c: Vector2, col: Color, uv_a := Vector2.ZERO, uv_b := Vector2.ZERO, uv_c := Vector2.ZERO) -> void:
	var base: int = verts.size()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	colors.append(col)
	colors.append(col)
	colors.append(col)
	uvs.append(uv_a)
	uvs.append(uv_b)
	uvs.append(uv_c)
	if has_custom0:
		for _i in range(3):
			_push_c0(Color(0, 0, 0, 0))
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)

func add_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color, uv_a := Vector2.ZERO, uv_b := Vector2.ZERO, uv_c := Vector2.ZERO, uv_d := Vector2.ZERO) -> void:
	var base: int = verts.size()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	verts.append(d)
	colors.append(col)
	colors.append(col)
	colors.append(col)
	colors.append(col)
	uvs.append(uv_a)
	uvs.append(uv_b)
	uvs.append(uv_c)
	uvs.append(uv_d)
	if has_custom0:
		for _i in range(4):
			_push_c0(Color(0, 0, 0, 0))
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 3)

func add_quad_c0(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2, c0_a: Color, c0_b: Color, c0_c: Color, c0_d: Color) -> void:
	_ensure_custom0()
	var base: int = verts.size()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	verts.append(d)
	colors.append(col)
	colors.append(col)
	colors.append(col)
	colors.append(col)
	uvs.append(uv_a)
	uvs.append(uv_b)
	uvs.append(uv_c)
	uvs.append(uv_d)
	_push_c0(c0_a)
	_push_c0(c0_b)
	_push_c0(c0_c)
	_push_c0(c0_d)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 3)

func add_rect_rot(center: Vector2, w: float, h: float, angle: float, col: Color, uv_val := Vector2.ZERO) -> void:
	var ux := Vector2(cos(angle), sin(angle)) * (w * 0.5)
	var uy := Vector2(-sin(angle), cos(angle)) * (h * 0.5)
	add_quad(center - ux - uy, center + ux - uy, center + ux + uy, center - ux + uy, col, uv_val, uv_val, uv_val, uv_val)

func add_circle(center: Vector2, radius: float, col: Color, segs: int = 16, uv_val := Vector2.ZERO) -> void:
	var base: int = verts.size()
	verts.append(center)
	colors.append(col)
	uvs.append(uv_val)
	_push_c0(Color(0, 0, 0, 0))
	for i in range(segs + 1):
		var a: float = TAU * float(i) / float(segs)
		verts.append(center + Vector2(cos(a), sin(a)) * radius)
		colors.append(col)
		uvs.append(uv_val)
		_push_c0(Color(0, 0, 0, 0))
	for i in range(1, segs + 1):
		indices.append(base)
		indices.append(base + i)
		indices.append(base + i + 1)

func add_ring(center: Vector2, r_inner: float, r_outer: float, col: Color, segs: int = 20) -> void:
	for i in range(segs):
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		add_quad(center + d0 * r_inner, center + d0 * r_outer, center + d1 * r_outer, center + d1 * r_inner, col)

func add_polygon_safe(poly: PackedVector2Array, col: Color) -> void:
	if poly.size() < 3:
		return
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	if not tris.is_empty():
		var base: int = verts.size()
		for p in poly:
			verts.append(p)
			colors.append(col)
			uvs.append(Vector2.ZERO)
			_push_c0(Color(0, 0, 0, 0))
		for idx in tris:
			indices.append(base + idx)
	else:
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= float(poly.size())
		for i in range(poly.size()):
			add_tri(c, poly[i], poly[(i + 1) % poly.size()], col)

func add_arc_strip(center: Vector2, radius: float, width: float, a_start: float, a_end: float, col: Color, segs: int = 16) -> void:
	if absf(a_end - a_start) < 0.001 or segs < 1:
		return
	var r_in: float = maxf(0.1, radius - width * 0.5)
	var r_out: float = radius + width * 0.5
	var steps: int = maxi(2, segs)
	for i in range(steps):
		var a0: float = lerpf(a_start, a_end, float(i) / float(steps))
		var a1: float = lerpf(a_start, a_end, float(i + 1) / float(steps))
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		add_quad(center + d0 * r_in, center + d0 * r_out, center + d1 * r_out, center + d1 * r_in, col)

func add_dashed_ring(center: Vector2, radius: float, width: float, col: Color, dash_count: int = 16, duty: float = 0.52) -> void:
	var step_ang: float = TAU / float(maxi(4, dash_count))
	var dash_ang: float = step_ang * clampf(duty, 0.15, 0.85)
	for i in range(maxi(4, dash_count)):
		var a0: float = float(i) * step_ang
		add_arc_strip(center, radius, width, a0, a0 + dash_ang, col, 3)

func add_smooth_strip(pts: PackedVector2Array, width: float, col: Color, closed_loop: bool = false, round_caps: bool = false, lateral_offset: float = 0.0) -> void:
	var clean := PackedVector2Array()
	for p in pts:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.05:
			clean.append(p)
	if closed_loop and clean.size() >= 3 and clean[0].distance_to(clean[clean.size() - 1]) <= 0.1:
		clean.remove_at(clean.size() - 1)
	var n: int = clean.size()
	if n < 2:
		return

	var seg_normals: Array[Vector2] = []
	var seg_count: int = n if closed_loop else (n - 1)
	for i in range(seg_count):
		var a: Vector2 = clean[i]
		var b: Vector2 = clean[(i + 1) % n]
		var d: Vector2 = b - a
		var l: float = d.length()
		if l < 0.0001:
			seg_normals.append(Vector2(0.0, 1.0))
		else:
			seg_normals.append(Vector2(-d.y / l, d.x / l))

	var hw: float = width * 0.5
	var base: int = verts.size()
	for i in range(n):
		var nrm: Vector2
		var stretch: float = 1.0
		if not closed_loop and i == 0:
			nrm = seg_normals[0]
		elif not closed_loop and i == n - 1:
			nrm = seg_normals[seg_count - 1]
		else:
			var n_prev: Vector2 = seg_normals[(i - 1 + seg_count) % seg_count]
			var n_curr: Vector2 = seg_normals[i % seg_count]
			var sum_n: Vector2 = n_prev + n_curr
			if sum_n.length_squared() < 0.001:
				nrm = n_curr
				stretch = 1.0
			else:
				nrm = sum_n.normalized()
				stretch = minf(2.0, 1.0 / maxf(0.5, nrm.dot(n_curr)))
		var center_p: Vector2 = clean[i] + nrm * (lateral_offset * stretch)
		var off: Vector2 = nrm * (hw * stretch)
		verts.append(center_p - off)
		verts.append(center_p + off)
		colors.append(col)
		colors.append(col)
		uvs.append(Vector2.ZERO)
		uvs.append(Vector2.ZERO)
		_push_c0(Color(0, 0, 0, 0))
		_push_c0(Color(0, 0, 0, 0))

	for i in range(seg_count):
		var i0: int = base + i * 2
		var i1: int = base + ((i + 1) % n) * 2
		indices.append(i0)
		indices.append(i0 + 1)
		indices.append(i1 + 1)
		indices.append(i0)
		indices.append(i1 + 1)
		indices.append(i1)

	if round_caps and not closed_loop:
		var c0: Vector2 = clean[0] + seg_normals[0] * lateral_offset
		var c1: Vector2 = clean[n - 1] + seg_normals[seg_count - 1] * lateral_offset
		add_circle(c0, hw, col, 10)
		add_circle(c1, hw, col, 10)

func add_polyline(pts: PackedVector2Array, width: float, col: Color, closed_loop: bool = false, round_caps: bool = true) -> void:
	add_smooth_strip(pts, width, col, closed_loop, round_caps, 0.0)

func add_dashed_polyline(pts: PackedVector2Array, width: float, col: Color, dash_len: float = 9.0, gap_len: float = 8.0, lateral_offset: float = 0.0) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	var hw: float = width * 0.5
	var cycle: float = dash_len + gap_len
	var dist_acc: float = 0.0
	for i in range(n - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d: Vector2 = b - a
		var seg_l: float = d.length()
		if seg_l < 0.1:
			continue
		var dir: Vector2 = d / seg_l
		var right_n := Vector2(-dir.y, dir.x)
		var base_a: Vector2 = a + right_n * lateral_offset
		var s: float = 0.0
		while s < seg_l - 0.05:
			var phase: float = fposmod(dist_acc + s, cycle)
			if phase < dash_len - 0.05:
				var draw_l: float = minf(dash_len - phase, seg_l - s)
				if draw_l > 0.4:
					var p0: Vector2 = base_a + dir * s
					var p1: Vector2 = base_a + dir * (s + draw_l)
					var w_n: Vector2 = right_n * hw
					add_quad(p0 - w_n, p0 + w_n, p1 + w_n, p1 - w_n, col)
				s += maxf(0.5, draw_l + gap_len)
			else:
				s += maxf(0.5, cycle - phase)
		dist_acc += seg_l

## Authentic ground shadow quad for `city_shadow.gdshader` (`CUSTOM0 = (reveal_t, center.x, center.y, mode)`)
func add_city_shadow_25d(center: Vector2, w: float, d: float, angle: float, height: float, shadow_col: Color, reveal_c0 := Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var ux := Vector2(cos(angle), sin(angle)) * (w * 0.5)
	var uy := Vector2(-sin(angle), cos(angle)) * (d * 0.5)
	var b0: Vector2 = center - ux - uy
	var b1: Vector2 = center + ux - uy
	var b2: Vector2 = center + ux + uy
	var b3: Vector2 = center - ux + uy
	var c0 := Color(reveal_c0.r, center.x, center.y, reveal_c0.a)
	var uv_base := Vector2(height, 0.0)
	var uv_cast := Vector2(height, 1.0)
	var corners: Array[Vector2] = [b0, b1, b2, b3]
	add_quad_c0(b0, b1, b2, b3, shadow_col, uv_cast, uv_cast, uv_cast, uv_cast, c0, c0, c0, c0)
	for i in range(4):
		var ca: Vector2 = corners[i]
		var cb: Vector2 = corners[(i + 1) % 4]
		add_quad_c0(ca, cb, cb, ca, shadow_col, uv_base, uv_base, uv_cast, uv_cast, c0, c0, c0, c0)

## Authentic 2.5D building geometry for `city_building.gdshader`:
## - `UV.x` = height `h`
## - `UV.y` = `kind * 100.0 + param` (0=roof, 1=wall base, 2=wall top, 4=night window glow)
## - `CUSTOM0` = `(reveal_time, center.x, center.y, mode)`
func add_city_building_25d(center: Vector2, w: float, d: float, angle: float, height: float, roof_col: Color, wall_col: Color, window_seed: float = 0.0, reveal_c0 := Color(0.0, 0.0, 0.0, 0.0), shadow_batch: TriBatch2D = null) -> void:
	var ux := Vector2(cos(angle), sin(angle)) * (w * 0.5)
	var uy := Vector2(-sin(angle), cos(angle)) * (d * 0.5)
	var b0: Vector2 = center - ux - uy
	var b1: Vector2 = center + ux - uy
	var b2: Vector2 = center + ux + uy
	var b3: Vector2 = center - ux + uy
	var c0 := Color(reveal_c0.r, center.x, center.y, reveal_c0.a)

	if shadow_batch != null:
		shadow_batch.add_city_shadow_25d(center, w, d, angle, height, Color(0.14, 0.16, 0.24, 0.19), reveal_c0)

	var corners: Array[Vector2] = [b0, b1, b2, b3]
	for i in range(4):
		var c_a: Vector2 = corners[i]
		var c_b: Vector2 = corners[(i + 1) % 4]
		var edge_v: Vector2 = (c_b - c_a).normalized()
		var out_n := Vector2(edge_v.y, -edge_v.x)
		var ang_param: float = fposmod(atan2(out_n.y, out_n.x), TAU)
		var uv_base := Vector2(0.0, 100.0 + ang_param)
		var uv_top := Vector2(height, 200.0 + ang_param)
		add_quad_c0(c_a, c_b, c_b, c_a, wall_col, uv_base, uv_base, uv_top, uv_top, c0, c0, c0, c0)

	# Extruded roof quad (kind = 0) + crisp architectural inner ridge/lantern
	var uv_roof := Vector2(height, 0.0)
	add_quad_c0(b0, b1, b2, b3, roof_col, uv_roof, uv_roof, uv_roof, uv_roof, c0, c0, c0, c0)
	var in0: Vector2 = center + (b0 - center) * 0.78
	var in1: Vector2 = center + (b1 - center) * 0.78
	var in2: Vector2 = center + (b2 - center) * 0.78
	var in3: Vector2 = center + (b3 - center) * 0.78
	var uv_peak := Vector2(height * 1.11, 0.0)
	add_quad_c0(in0, in1, in2, in3, roof_col.lightened(0.11), uv_peak, uv_peak, uv_peak, uv_peak, c0, c0, c0, c0)

	# Warm night skylight / window lantern (kind = 4, visible smoothly as night > 0)
	if window_seed > 0.05 and w >= 7.0 and d >= 7.0:
		var sk0: Vector2 = center + (b0 - center) * 0.36
		var sk1: Vector2 = center + (b1 - center) * 0.36
		var sk2: Vector2 = center + (b2 - center) * 0.36
		var sk3: Vector2 = center + (b3 - center) * 0.36
		var intensity: float = clampf(window_seed * 99.0, 15.0, 98.0)
		var uv_win := Vector2(height * 1.13, 400.0 + intensity)
		var win_col := Color(1.0, 0.87, 0.54, 0.92)
		add_quad_c0(sk0, sk1, sk2, sk3, win_col, uv_win, uv_win, uv_win, uv_win, c0, c0, c0, c0)

## Legacy wrapper mapped directly to `add_city_building_25d`
func add_extruded_box_25d(center: Vector2, w: float, d: float, angle: float, height: float, roof_col: Color, wall_col: Color, window_seed: float = 0.0, reveal_c0 := Color(0.0, 0.0, 0.0, 0.0), shadow_batch: TriBatch2D = null) -> void:
	add_city_building_25d(center, w, d, angle, height, roof_col, wall_col, window_seed, reveal_c0, shadow_batch)

## Authentic drifting cloud puff quad for `cloud_puff.gdshader`
func add_cloud_puff(center: Vector2, radius: float, phase: float, gust_phase: float, col: Color) -> void:
	var r_vec := Vector2(radius, radius)
	var a := center + Vector2(-r_vec.x, -r_vec.y)
	var b := center + Vector2(r_vec.x, -r_vec.y)
	var c := center + Vector2(r_vec.x, r_vec.y)
	var d := center + Vector2(-r_vec.x, r_vec.y)
	var c0 := Color(radius, phase, gust_phase, 0.0)
	add_quad_c0(a, b, c, d, col, Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0), c0, c0, c0, c0)

## Authentic `rule_hints.gdshader` primitives (KIND_DOT=0, KIND_RING=1, KIND_SIGN_RING=2, KIND_DASH=3)
func add_rule_hint_dot(center: Vector2, group_id: float = 0.0) -> void:
	var c0 := Color(0.0, 0.0, group_id, 0.0)
	add_quad_c0(center, center, center, center, Color.WHITE, Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0), c0, c0, c0, c0)

func add_rule_hint_ring(center: Vector2, world_radius: float, segs: int = 28, group_id: float = 0.0) -> void:
	var c0_in := Color(1.0, -1.0, group_id, 0.0)
	var c0_out := Color(1.0, 1.0, group_id, 0.0)
	for i in range(segs):
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		add_quad_c0(center, center, center, center, Color.WHITE, Vector2(a0, world_radius), Vector2(a0, world_radius), Vector2(a1, world_radius), Vector2(a1, world_radius), c0_in, c0_out, c0_out, c0_in)

func add_rule_hint_sign_ring(center: Vector2, segs: int = 24, group_id: float = 0.0) -> void:
	var c0_in := Color(2.0, -1.0, group_id, 0.0)
	var c0_out := Color(2.0, 1.0, group_id, 0.0)
	for i in range(segs):
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		add_quad_c0(center, center, center, center, Color.WHITE, Vector2(a0, 0.0), Vector2(a0, 0.0), Vector2(a1, 0.0), Vector2(a1, 0.0), c0_in, c0_out, c0_out, c0_in)

func add_rule_hint_dash_polyline(pts: PackedVector2Array, group_id: float = 0.0) -> void:
	if pts.size() < 2:
		return
	var c0_l := Color(3.0, -1.0, group_id, 0.0)
	var c0_r := Color(3.0, 1.0, group_id, 0.0)
	var dist_acc: float = 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg_l: float = a.distance_to(b)
		if seg_l < 0.2:
			continue
		var dir: Vector2 = (b - a) / seg_l
		var n_ang: float = atan2(dir.x, -dir.y)
		var d0: float = dist_acc
		var d1: float = dist_acc + seg_l
		add_quad_c0(a, a, b, b, Color.WHITE, Vector2(d0, n_ang), Vector2(d0, n_ang), Vector2(d1, n_ang), Vector2(d1, n_ang), c0_l, c0_r, c0_r, c0_l)
		dist_acc = d1

func commit_to_canvas_item(ci: RID) -> void:
	RenderingServer.canvas_item_clear(ci)
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci, indices, verts, colors, uvs)

func upload_to_mesh(mesh: ArrayMesh) -> void:
	if mesh == null:
		return
	mesh.clear_surfaces()
	if indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags: int = 0
	if has_custom0 and custom0.size() == verts.size() * 4:
		arrays[Mesh.ARRAY_CUSTOM0] = custom0
		flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)

func commit_mesh_to_canvas_item(ci: RID, mesh: ArrayMesh) -> void:
	RenderingServer.canvas_item_clear(ci)
	if mesh == null:
		return
	upload_to_mesh(mesh)
	if mesh.get_surface_count() > 0:
		RenderingServer.canvas_item_add_mesh(ci, mesh.get_rid())

