class_name ShapeGlyphs
extends RefCounted

## 100% Authentic Port of Incremental Traffic v1.4.1 `gd_src/content/cargo/shape_glyphs.gd`
## Renders all 44 commodity glyphs across CanvasItems and cached TriBatch2D stamps,
## including `box_center` large-cargo optical centering, `truck_angle`, world outlines,
## UV-normal screen-space keylines (`truck_part.gdshader`), and Okabe-Ito colour-blind remapping.

const DOT := Color("E0533D")
const WEDGE := Color("EFA42A")
const BLOCK := Color("2E6BB0")
const ORANGE := Color("E8792F")
const VIOLET := Color("8B5A9C")
const GREEN := Color("5F9B52")
const TEAL := Color("139E99")
const BROWN := Color("8E6A45")
const INK := Color("2B2F3A")
const SEAM := Color(0.0, 0.0, 0.0, 0.25)

const SEGMENTS := 28
const DEFAULT_TRUCK_ANGLE := PI * 0.5
const TRUCK_ANGLES := {
	"fish": PI,
	"bull": 0.0,
	"crab": 0.0,
	"bird": 0.0,
	"turtle": 0.0,
	"cart": 0.0,
	"bus": 0.0
}

static var _shape_cache: Dictionary = {}
static var _offset_cache: Dictionary = {}
static var _batch_cache: Dictionary = {}
static var _silhouette_cache: Dictionary = {}

static func remap_colorblind(col: Color, colorblind: bool) -> Color:
	if not colorblind:
		return col
	if col.is_equal_approx(DOT):
		return Color("D55E00")
	if col.is_equal_approx(GREEN):
		return Color("0072B2")
	if col.is_equal_approx(WEDGE):
		return Color("F0E442")
	if col.is_equal_approx(VIOLET):
		return Color("CC79A7")
	if col.is_equal_approx(TEAL):
		return Color("56B4E9")
	return col

static func truck_angle(good: String) -> float:
	return float(TRUCK_ANGLES.get(good, DEFAULT_TRUCK_ANGLE))

static func box_center(good: String) -> Vector2:
	return _shape(good)["center"]

static func centered_offset(good: String, center: Vector2, size: float, slots: int = 1, angle: float = DEFAULT_TRUCK_ANGLE) -> Vector2:
	if slots < 2:
		return center
	return center - (box_center(good) * (size / 100.0)).rotated(angle)

static func color_of(good: String, colorblind: bool = false) -> Color:
	return remap_colorblind(_shape(good)["main"], colorblind)

static func draw(
	ci: CanvasItem,
	good: String,
	center: Vector2,
	size: float,
	angle: float = 0.0,
	outline: Color = Color.TRANSPARENT,
	outline_px: float = 1.0,
	base: Transform2D = Transform2D.IDENTITY,
	colorblind: bool = false
) -> void:
	if size <= 0.4:
		return
	var xf := base * Transform2D(angle, Vector2.ONE * (size / 100.0), 0.0, center)
	ci.draw_set_transform_matrix(xf)
	if outline.a > 0.0:
		for p in _offset_polys(good, outline_px * 100.0 / size):
			ci.draw_colored_polygon(p, outline)
	var s: Dictionary = _shape(good)
	for part in s["parts"]:
		ci.draw_colored_polygon(part[0], remap_colorblind(part[1], colorblind))
	for o in s["outlines"]:
		var closed: PackedVector2Array = (o as PackedVector2Array).duplicate()
		closed.append(o[0])
		ci.draw_polyline(closed, SEAM, 2.0)
	for seam in s["seams"]:
		ci.draw_line(seam[0], seam[1], seam[2], float(seam[3]))
	for ring in s["rings"]:
		ci.draw_arc(ring[0], float(ring[1]), 0.0, TAU, SEGMENTS, SEAM, 2.5)
	ci.draw_set_transform_matrix(base)

## Draws a flat solid-colored silhouette onto a CanvasItem (for empty storage-pad watermarks, CargoFlights shadows & crumble fade)
static func draw_tinted(
	ci: CanvasItem,
	good: String,
	center: Vector2,
	size: float,
	col: Color,
	angle: float = 0.0,
	base: Transform2D = Transform2D.IDENTITY
) -> void:
	if size <= 0.4 or col.a <= 0.005:
		return
	var xf := base * Transform2D(angle, Vector2.ONE * (size / 100.0), 0.0, center)
	ci.draw_set_transform_matrix(xf)
	var s: Dictionary = _shape(good)
	for part in s["parts"]:
		ci.draw_colored_polygon(part[0], col)
	ci.draw_set_transform_matrix(base)

## Stamps a cached `TriBatch2D` with optional world-space polygon outline (`outline_px` in target world units)
static func add_to_batch(
	batch: TriBatch2D,
	good: String,
	center: Vector2,
	size: float,
	angle: float = 0.0,
	base: Transform2D = Transform2D.IDENTITY,
	outline: Color = Color.TRANSPARENT,
	outline_px: float = 1.0,
	colorblind: bool = false
) -> void:
	if size <= 0.4:
		return
	var tpl: TriBatch2D = _template_batch(good, outline, outline_px * 100.0 / size, colorblind)
	batch.stamp(tpl, base * Transform2D(angle, Vector2.ONE * (size / 100.0), 0.0, center))

## Stamps a cached `TriBatch2D` with both a crisp world keyline AND UV-normal expansion for `truck_part.gdshader`!
static func add_keylined(
	batch: TriBatch2D,
	good: String,
	center: Vector2,
	size: float,
	angle: float = 0.0,
	base: Transform2D = Transform2D.IDENTITY,
	outline: Color = Color("1D2128"),
	colorblind: bool = false,
	uv_expand: bool = false
) -> void:
	if size <= 0.4:
		return
	var tpl: TriBatch2D = _keylined_batch(good, outline, colorblind, uv_expand)
	batch.stamp(tpl, base * Transform2D(angle, Vector2.ONE * (size / 100.0), 0.0, center))

## Stamps a flat solid-colored silhouette (used for empty storage-pad watermarks, drop shadows & crumble particles)
static func add_tinted(
	batch: TriBatch2D,
	good: String,
	center: Vector2,
	size: float,
	color: Color,
	angle: float = 0.0,
	base: Transform2D = Transform2D.IDENTITY
) -> void:
	if size <= 0.4 or color.a <= 0.005:
		return
	var tpl: TriBatch2D = _silhouette_batch(good)
	batch.stamp(tpl, base * Transform2D(angle, Vector2.ONE * (size / 100.0), 0.0, center), color)

static func _template_batch(good: String, outline: Color, width_100: float, colorblind: bool) -> TriBatch2D:
	var key: String = "%s|cb%d" % [good, 1 if colorblind else 0]
	if outline.a > 0.0:
		key += "|%s|%d" % [outline.to_html(), roundi(width_100 * 2.0)]
	if _batch_cache.has(key):
		return _batch_cache[key]
	var g := TriBatch2D.new()
	if outline.a > 0.0:
		for p in _offset_polys(good, width_100):
			g.add_polygon_safe(p, outline)
	var s: Dictionary = _shape(good)
	for part in s["parts"]:
		g.add_polygon_safe(part[0], remap_colorblind(part[1], colorblind))
	for o in s["outlines"]:
		g.add_polyline(o, 2.0, SEAM, true, false)
	for seam in s["seams"]:
		var pts := PackedVector2Array([seam[0], seam[1]])
		g.add_polyline(pts, float(seam[3]), seam[2], false, false)
	for ring in s["rings"]:
		var r_c: Vector2 = ring[0]
		var r_rad: float = float(ring[1])
		g.add_ring(r_c, maxf(0.2, r_rad - 1.25), r_rad + 1.25, SEAM, SEGMENTS)
	_batch_cache[key] = g
	return g

static func _keylined_batch(good: String, outline: Color, colorblind: bool, uv_expand: bool) -> TriBatch2D:
	var key := "%s|%s|cb%d|uv%d|wide" % [good, outline.to_html(), 1 if colorblind else 0, 1 if uv_expand else 0]
	if _batch_cache.has(key):
		return _batch_cache[key]
	var g := TriBatch2D.new()
	var s: Dictionary = _shape(good)
	if uv_expand:
		for part in s["parts"]:
			g.add_uv_keyline_poly(part[0], outline, 0.56)
	else:
		for p in _offset_polys(good, 7.5):
			g.add_polygon_safe(p, outline)
	g.stamp(_template_batch(good, Color.TRANSPARENT, 0.0, colorblind))
	_batch_cache[key] = g
	return g

static func _silhouette_batch(good: String) -> TriBatch2D:
	if _silhouette_cache.has(good):
		return _silhouette_cache[good]
	var g := TriBatch2D.new()
	var s: Dictionary = _shape(good)
	for part in s["parts"]:
		g.add_polygon_safe(part[0], Color.WHITE)
	_silhouette_cache[good] = g
	return g

static func _offset_polys(good: String, width_100: float) -> Array:
	var w_step: int = maxi(1, roundi(width_100 * 2.0))
	var key := "%s|%d" % [good, w_step]
	if not _offset_cache.has(key):
		var polys: Array = []
		for part in _shape(good)["parts"]:
			polys.append_array(Geometry2D.offset_polygon(part[0], float(w_step) * 0.5, Geometry2D.JOIN_ROUND))
		_offset_cache[key] = polys
	return _offset_cache[key]

static func _shape(good: String) -> Dictionary:
	if not _shape_cache.has(good):
		_shape_cache[good] = _build(good)
	return _shape_cache[good]

static func _base(id: String) -> Dictionary:
	match id:
		"dot":
			return {"poly": _circle(Vector2.ZERO, 34.0), "seams": [], "color": DOT}
		"wedge":
			return {"poly": PackedVector2Array([Vector2(0, -34), Vector2(36, 30), Vector2(-36, 30)]), "seams": [], "color": WEDGE}
		"block":
			return {"poly": _rect(-32, -32, 64, 64), "seams": [], "color": BLOCK}
		"capsule":
			return {"poly": _round_rect(-44, -22, 88, 44, 22.0), "seams": [[Vector2(0, -16), Vector2(0, 16)]], "color": DOT}
		"diamond":
			return {"poly": PackedVector2Array([Vector2(0, -42), Vector2(36, 0), Vector2(0, 42), Vector2(-36, 0)]), "seams": [[Vector2(-28, 0), Vector2(28, 0)]], "color": WEDGE}
		"bar":
			return {"poly": _rect(-22, -44, 44, 88), "seams": [[Vector2(-16, 0), Vector2(16, 0)]], "color": BLOCK}
		"drop":
			return {"poly": _drop(), "seams": [[Vector2(-14, 4), Vector2(14, 4)]], "color": ORANGE}
		"pebble":
			return {"poly": _round_rect(-32, -32, 64, 64, 22.0), "seams": [[Vector2(-20, 20), Vector2(20, -20)]], "color": VIOLET}
		"shield":
			var p := PackedVector2Array([Vector2(-32, -36), Vector2(32, -36), Vector2(32, 2)])
			p.append_array(_quad_bez(Vector2(32, 2), Vector2(32, 28), Vector2(0, 42)))
			p.append_array(_quad_bez(Vector2(0, 42), Vector2(-32, 28), Vector2(-32, 2)))
			return {"poly": p, "seams": [[Vector2(-24, -6), Vector2(24, -6)]], "color": GREEN}
		"moon":
			var clipped := Geometry2D.clip_polygons(_circle(Vector2.ZERO, 34.0), _circle(Vector2(18, -10), 28.0))
			return {"poly": clipped[0], "seams": [], "color": DOT}
		"chevron":
			return {"poly": PackedVector2Array([Vector2(0, -34), Vector2(36, 30), Vector2(0, 4), Vector2(-36, 30)]), "seams": [], "color": WEDGE}
		"dome":
			return {"poly": _arc(Vector2(0, 10), 36.0, PI, TAU), "seams": [], "color": DOT}
	return {}

static func _stamp_base(s: Dictionary, id: String, x: float, y: float, k: float = 1.0, deg: float = 0.0, col: Color = Color.TRANSPARENT, seams: bool = true, outline: bool = false) -> void:
	var b: Dictionary = _base(id)
	var xf := Transform2D(deg_to_rad(deg), Vector2(k, k), 0.0, Vector2(x, y))
	var poly: PackedVector2Array = xf * (b["poly"] as PackedVector2Array)
	s["parts"].append([poly, b["color"] if col.a == 0.0 else col])
	if seams:
		for seam in b["seams"]:
			s["seams"].append([xf * seam[0], xf * seam[1], SEAM, 3.0 * k])
	if outline:
		s["outlines"].append(poly)

static func _add(s: Dictionary, poly: PackedVector2Array, col: Color) -> void:
	s["parts"].append([poly, col])

static func _seam(s: Dictionary, a: Vector2, b: Vector2, col: Color = SEAM, width: float = 3.0) -> void:
	s["seams"].append([a, b, col, width])

static func _eye(s: Dictionary, c: Vector2, r: float) -> void:
	_add(s, _circle(c, r), SEAM)

static func _wheel(s: Dictionary, c: Vector2, r: float) -> void:
	_add(s, _circle(c, r), DOT)
	s["rings"].append([c, r])

static func _build(good: String) -> Dictionary:
	var s := {"parts": [], "seams": [], "rings": [], "outlines": []}
	match good:
		"dot", "wedge", "block", "capsule", "diamond", "bar", "drop", "pebble", "shield", "moon", "chevron", "dome":
			_stamp_base(s, good, 0, 0)
		"heart":
			_add(s, _circle(Vector2(-17, -12), 19.0), ORANGE)
			_add(s, _circle(Vector2(17, -12), 19.0), ORANGE)
			_add(s, PackedVector2Array([Vector2(-34.5, -5), Vector2(34.5, -5), Vector2(0, 40)]), ORANGE)
			_seam(s, Vector2(0, -22), Vector2(0, -2))
		"star":
			_add(s, PackedVector2Array([Vector2(0, -44), Vector2(11, -14), Vector2(42, -14), Vector2(17, 6), Vector2(27, 38), Vector2(0, 19), Vector2(-27, 38), Vector2(-17, 6), Vector2(-42, -14), Vector2(-11, -14)]), WEDGE)
			_seam(s, Vector2(-10, 4), Vector2(10, 4))
		"leaf":
			var p := PackedVector2Array([Vector2(0, -44)])
			p.append_array(_quad_bez(Vector2(0, -44), Vector2(40, 0), Vector2(0, 44)))
			p.append_array(_quad_bez(Vector2(0, 44), Vector2(-40, 0), Vector2(0, -44)))
			p.remove_at(p.size() - 1)
			_add(s, p, ORANGE)
			_seam(s, Vector2(-14, 14), Vector2(14, -14))
		"bullet":
			var p := PackedVector2Array([Vector2(-22, 44)])
			p.append_array(_arc(Vector2(0, -20), 22.0, PI, TAU))
			p.append(Vector2(22, 44))
			_add(s, p, VIOLET)
			_seam(s, Vector2(-16, 8), Vector2(16, 8))
		"trefoil":
			for c in [Vector2(0, -16), Vector2(-18, 13), Vector2(18, 13)]:
				_add(s, _circle(c, 21.0), DOT)
			_add(s, _circle(Vector2(0, 4), 16.0), DOT)
		"gem":
			_add(s, PackedVector2Array([Vector2(-38, -12), Vector2(-20, -34), Vector2(20, -34), Vector2(38, -12), Vector2(0, 40)]), GREEN)
		"arrow":
			_stamp_base(s, "bar", 0, 16, 0.65, 0, GREEN, false)
			_stamp_base(s, "chevron", 0, -14, 0.9, 0, GREEN, false)
		"wave":
			_stamp_base(s, "moon", -4, 4, 1.0, 0, ORANGE, false)
			_stamp_base(s, "drop", 16, -12, 0.5, 45, ORANGE, false)
		"swirl":
			_stamp_base(s, "moon", -10, 0, 0.75, 0, DOT, false)
			_stamp_base(s, "moon", 10, 0, 0.75, 180, DOT, false)
		"acorn":
			_stamp_base(s, "shield", 0, 12, 0.82, 0, TEAL, false)
			_add(s, _rect(-3, -46, 6, 12), BROWN)
			_stamp_base(s, "capsule", 0, -20, 0.85, 0, BROWN, false)
		"helmet":
			_stamp_base(s, "moon", 0, -20, 1.0, -61, DOT, false)
			_stamp_base(s, "shield", 0, 14, 0.8, 0, INK, false)
			_seam(s, Vector2(-18, 10), Vector2(18, 10), Color(1, 1, 1, 0.3), 4.0)
		"fish":
			_stamp_base(s, "chevron", 32, 0, 0.5, -90)
			_stamp_base(s, "capsule", -8, 0, 0.8)
			_eye(s, Vector2(-30, -4), 3.5)
		"mushroom":
			_stamp_base(s, "bar", 0, 24, 0.42)
			_stamp_base(s, "dome", 0, -6)
		"paddle":
			_stamp_base(s, "bar", 0, 26, 0.42)
			_stamp_base(s, "pebble", 0, -16, 0.7)
		"standard":
			_stamp_base(s, "bar", 0, 26, 0.42)
			_stamp_base(s, "shield", 0, -14, 0.7)
		"kite":
			_stamp_base(s, "chevron", 0, 24, 0.55)
			_stamp_base(s, "diamond", 0, -14, 0.65, 0, Color.TRANSPARENT, true, true)
		"bull":
			_stamp_base(s, "dome", 0, 12, 0.95)
			_stamp_base(s, "moon", 0, -14, 0.75, -61, Color.TRANSPARENT, true, true)
			_eye(s, Vector2(-10, 6), 3.5)
			_eye(s, Vector2(10, 6), 3.5)
		"imp":
			_stamp_base(s, "pebble", 0, 14, 0.78, 0, Color.TRANSPARENT, false)
			_stamp_base(s, "chevron", 0, -14, 0.72)
			_eye(s, Vector2(-9, 16), 3.5)
			_eye(s, Vector2(9, 16), 3.5)
		"candle":
			_stamp_base(s, "block", 0, 24, 0.55)
			_stamp_base(s, "drop", 0, -16, 0.7)
		"eclipse":
			_stamp_base(s, "moon", 0, 0)
			_wheel(s, Vector2(18, -10), 14.0)
		"propeller":
			for a in [0.0, 120.0, 240.0]:
				var at := Vector2(0, -23).rotated(deg_to_rad(a))
				_stamp_base(s, "drop", at.x, at.y, 0.5, a + 180.0)
		"cart":
			_add(s, _rect(-44, -26, 88, 34), BLOCK)
			_seam(s, Vector2(0, -20), Vector2(0, 2))
			_add(s, _circle(Vector2(-24, 16), 13.0), DOT)
			_add(s, _circle(Vector2(24, 16), 13.0), DOT)
		"bus":
			_stamp_base(s, "capsule", 0, -6)
			_wheel(s, Vector2(-24, 20), 11.0)
			_wheel(s, Vector2(24, 20), 11.0)
		"rocket":
			_stamp_base(s, "chevron", 0, 30, 0.8)
			_add(s, _rect(-11, -18, 22, 52), BLOCK)
			_add(s, PackedVector2Array([Vector2(0, -48), Vector2(18, -18), Vector2(-18, -18)]), WEDGE)
		"lighthouse":
			_stamp_base(s, "bar", -14, 20, 0.55)
			_stamp_base(s, "wedge", 7, -18, 0.6, -90)
			_add(s, _circle(Vector2(-14, -18), 12.0), DOT)
		"bird":
			_stamp_base(s, "shield", -4.3, 8.3, 0.56, 45, Color.TRANSPARENT, false)
			_stamp_base(s, "drop", 27, -6, 0.3, 90, Color.TRANSPARENT, false)
			_stamp_base(s, "dot", 10, -6, 0.55)
			_eye(s, Vector2(14, -11), 3.0)
		"turtle":
			_stamp_base(s, "capsule", 2, 18, 0.85, 0, Color.TRANSPARENT, false)
			_stamp_base(s, "dot", -36, 12, 0.3)
			_stamp_base(s, "dome", 4, 6, 0.9, 0, GREEN)
			_eye(s, Vector2(-38, 9), 2.5)
		"crab":
			_stamp_base(s, "moon", -30, -16, 0.45, -61)
			_stamp_base(s, "moon", 30, -16, 0.45, -61)
			_stamp_base(s, "dome", 0, 14, 0.85, 0, Color.TRANSPARENT, false, true)
			_eye(s, Vector2(-9, 8), 3.5)
			_eye(s, Vector2(9, 8), 3.5)
		"fir":
			_stamp_base(s, "bar", 0, 28, 0.34, 0, Color.TRANSPARENT, false)
			_stamp_base(s, "chevron", 0, 10, 0.95)
			_stamp_base(s, "wedge", 0, -24, 0.55)
		"owl":
			_stamp_base(s, "pebble", 0, 6, 1.0, 0, Color.TRANSPARENT, false)
			_wheel(s, Vector2(-13, -6), 10.0)
			_wheel(s, Vector2(13, -6), 10.0)
			_stamp_base(s, "diamond", 0, 14, 0.2, 0, Color.TRANSPARENT, false)
		"rabbit":
			_stamp_base(s, "capsule", -12, -26, 0.42, 90, Color.TRANSPARENT, false)
			_stamp_base(s, "capsule", 12, -26, 0.42, 90, Color.TRANSPARENT, false)
			_stamp_base(s, "pebble", 0, 18, 0.8, 0, Color.TRANSPARENT, false)
			_wheel(s, Vector2(0, 22), 6.0)
		"cat":
			_stamp_base(s, "wedge", -24, -24, 0.36, -25)
			_stamp_base(s, "wedge", 24, -24, 0.36, 25)
			_stamp_base(s, "pebble", 0, 8, 0.95, 0, Color.TRANSPARENT, false)
			_stamp_base(s, "wedge", 0, 14, 0.2, 180)
		_:
			_add(s, _circle(Vector2.ZERO, 26.0), Color.MAGENTA)
	s["main"] = _dominant_color(s["parts"])
	s["center"] = _box(s["parts"]).get_center()
	return s

static func _dominant_color(parts: Array) -> Color:
	var best := 0.0
	var col: Color = parts[0][1]
	for part in parts:
		var a := _area(part[0])
		if a > best:
			best = a
			col = part[1]
	return col

static func _box(parts: Array) -> Rect2:
	var box := Rect2(parts[0][0][0], Vector2.ZERO)
	for part in parts:
		for p in part[0]:
			box = box.expand(p)
	return box

static func _area(p: PackedVector2Array) -> float:
	var sum := 0.0
	for i in range(p.size()):
		sum += p[i].cross(p[(i + 1) % p.size()])
	return absf(sum) * 0.5

static func _drop() -> PackedVector2Array:
	var c := Vector2(0, 12.7)
	var from := (Vector2(25, -2) - c).angle()
	var p := PackedVector2Array([Vector2(0, -44)])
	p.append_array(_arc(c, 29.0, from, PI - from))
	return p

static func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])

static func _round_rect(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.append_array(_arc(Vector2(x + w - r, y + r), r, -PI * 0.5, 0.0))
	p.append_array(_arc(Vector2(x + w - r, y + h - r), r, 0.0, PI * 0.5))
	p.append_array(_arc(Vector2(x + r, y + h - r), r, PI * 0.5, PI))
	p.append_array(_arc(Vector2(x + r, y + r), r, PI, PI * 1.5))
	return p

static func _circle(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(SEGMENTS):
		out.append(c + Vector2.from_angle(TAU * float(i) / float(SEGMENTS)) * r)
	return out

static func _arc(c: Vector2, r: float, from: float, to: float) -> PackedVector2Array:
	var steps := maxi(2, ceili(absf(to - from) / TAU * float(SEGMENTS)))
	var out := PackedVector2Array()
	for i in range(steps + 1):
		out.append(c + Vector2.from_angle(lerpf(from, to, float(i) / float(steps))) * r)
	return out

static func _quad_bez(a: Vector2, b: Vector2, c: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, 9):
		var t := float(i) / 8.0
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out
