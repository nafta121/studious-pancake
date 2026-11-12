class_name TriBatch2D
extends RefCounted

## Low-level RenderingServer triangle batcher for zero-overhead 2D/2.5D cartography on Android.

var verts := PackedVector2Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()

func clear() -> void:
	verts.clear()
	colors.clear()
	uvs.clear()
	indices.clear()

func is_empty() -> bool:
	return indices.is_empty()

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
	for i in range(segs + 1):
		var a: float = TAU * float(i) / float(segs)
		verts.append(center + Vector2(cos(a), sin(a)) * radius)
		colors.append(col)
		uvs.append(uv_val)
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
		for idx in tris:
			indices.append(base + idx)
	else:
		# Fallback centroid fan if GIS ring has a self-touching pinch vertex
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= float(poly.size())
		for i in range(poly.size()):
			add_tri(c, poly[i], poly[(i + 1) % poly.size()], col)

func add_polyline(pts: PackedVector2Array, width: float, col: Color, closed_loop: bool = false, round_caps: bool = true) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	var hw: float = width * 0.5
	var count: int = n if closed_loop else n - 1
	for i in range(count):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var d: Vector2 = b - a
		var l: float = d.length()
		if l < 0.001:
			continue
		var nrm := Vector2(-d.y / l, d.x / l) * hw
		add_quad(a - nrm, a + nrm, b + nrm, b - nrm, col)
		if round_caps and i > 0:
			add_circle(a, hw, col, 8)
	if round_caps and not closed_loop:
		add_circle(pts[0], hw, col, 8)
		add_circle(pts[n - 1], hw, col, 8)

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

func add_extruded_box_25d(center: Vector2, w: float, d: float, angle: float, height: float, roof_col: Color, wall_col: Color, window_seed: float = 0.0) -> void:
	var ux := Vector2(cos(angle), sin(angle)) * (w * 0.5)
	var uy := Vector2(-sin(angle), cos(angle)) * (d * 0.5)
	var b0: Vector2 = center - ux - uy
	var b1: Vector2 = center + ux - uy
	var b2: Vector2 = center + ux + uy
	var b3: Vector2 = center - ux + uy

	# Subtle ground ambient shadow anchored at UV.x = 0.0
	var sun_off := Vector2(3.2, 4.2) * clampf(height / 16.0, 0.5, 1.8)
	var shadow_col := Color(0.05, 0.07, 0.10, 0.16)
	add_quad(b0 + sun_off, b1 + sun_off, b2 + sun_off, b3 + sun_off, shadow_col)

	var corners: Array[Vector2] = [b0, b1, b2, b3]
	var sun_dir := Vector2(-0.62, -0.78)
	var uv_ground := Vector2(0.0, 0.0)
	var uv_top := Vector2(height, 0.0)

	# Four extruded walls connecting ground UV(0,0) to roof UV(height, 0) with directional sun shading
	for i in range(4):
		var c_a: Vector2 = corners[i]
		var c_b: Vector2 = corners[(i + 1) % 4]
		var edge_v: Vector2 = (c_b - c_a).normalized()
		var out_n := Vector2(edge_v.y, -edge_v.x)
		var lit: float = clampf(0.76 + 0.24 * out_n.dot(sun_dir), 0.56, 1.04)
		var shaded_wall := Color(wall_col.r * lit, wall_col.g * lit, wall_col.b * lit, wall_col.a)
		add_quad(c_a, c_b, c_b, c_a, shaded_wall, uv_ground, uv_ground, uv_top, uv_top)

		# Night window band along wider walls
		if window_seed > 0.05 and c_a.distance_to(c_b) >= 7.5 and height >= 9.0:
			var p_wa: Vector2 = c_a.lerp(c_b, 0.22)
			var p_wb: Vector2 = c_a.lerp(c_b, 0.78)
			var uv_w0 := Vector2(height * 0.35, window_seed)
			var uv_w1 := Vector2(height * 0.76, window_seed)
			var win_day := wall_col.darkened(0.24)
			add_quad(p_wa, p_wb, p_wb, p_wa, win_day, uv_w0, uv_w0, uv_w1, uv_w1)

	# Extruded roof quad + crisp roof rim highlight
	add_quad(b0, b1, b2, b3, roof_col, uv_top, uv_top, uv_top, uv_top)
	var in0: Vector2 = center + (b0 - center) * 0.80
	var in1: Vector2 = center + (b1 - center) * 0.80
	var in2: Vector2 = center + (b2 - center) * 0.80
	var in3: Vector2 = center + (b3 - center) * 0.80
	var uv_peak := Vector2(height * 1.12, 0.0)
	add_quad(in0, in1, in2, in3, roof_col.lightened(0.11), uv_peak, uv_peak, uv_peak, uv_peak)

func commit_to_canvas_item(ci: RID) -> void:
	RenderingServer.canvas_item_clear(ci)
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci, indices, verts, colors, uvs)
