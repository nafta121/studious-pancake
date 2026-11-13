class_name ItIcons
extends RefCounted

## Authentic procedural vector icon & commodity glyph renderer ported from Incremental Traffic:
## - 44 ShapeGlyphs commodities (exact geometry, seams, rings, and colors)
## - RuleToolbar vector icons (Yield, Stop/Close, Lanes, Roundabout, Lights, One-Way, Roads, Route)
## - FactoryPanel UpgradeIcon glyphs (Speed, Rate, Expand, Buffer, Bays, Wide Gate, Exit Road, Train, Ship, Timetable)
## - OverlayBar 5 analytic icons, DayClock Sun/Moon, Heraldic TownCrest shields, and MiniTruck slot diagrams.

const DOT := Color("E0533D")
const WEDGE := Color("EFA42A")
const BLOCK := Color("2E6BB0")
const ORANGE := Color("E8792F")
const VIOLET := Color("8B5A9C")
const GREEN := Color("5F9B52")
const TEAL := Color("139E99")
const BROWN := Color("8E6A45")
const INK := Color("2B2F3A")
const SEAM := Color(0, 0, 0, 0.25)
const CIRCLE_STEPS := 28

const TRUCK_ANGLES := {
	"fish": PI, "bull": 0.0, "crab": 0.0, "bird": 0.0,
	"turtle": 0.0, "cart": 0.0, "bus": 0.0
}

const MADIUN_CRESTS := {
	"karisidenan_madiun": {"style": "hanse", "field": "A6533F", "charge": "6FA48D", "rim": "F4EFE4"},
	"kota_madiun": {"style": "coal", "field": "3A3C40", "charge": "EFA42A", "rim": "F4EFE4"},
	"kab_madiun": {"style": "wine", "field": "6E7787", "charge": "D8C98F", "rim": "F3F0E6"},
	"kab_magetan": {"style": "alpine", "field": "3F6A43", "charge": "F0EEE8", "rim": "F2F4F5"},
	"kab_ngawi": {"style": "heath", "field": "7E6A85", "charge": "D8D1C3", "rim": "EDEAE0"},
	"kab_ponorogo": {"style": "spa", "field": "9FCDB9", "charge": "3E4047", "rim": "3E4047"},
	"kab_pacitan": {"style": "riviera", "field": "2F6FA8", "charge": "E0895A", "rim": "F6F1E4"},
}

static var _shape_cache: Dictionary = {}
static var _outline_cache: Dictionary = {}

static func color_of(good: String) -> Color:
	return _get_shape(good)["main"]

static func truck_angle(good: String) -> float:
	return float(TRUCK_ANGLES.get(good, PI * 0.5))

static func draw_shape(ci: CanvasItem, good: String, center: Vector2, size: float, angle: float = 0.0, outline: Color = Color.TRANSPARENT, outline_px: float = 1.2) -> void:
	if size <= 0.5:
		return
	var s: Dictionary = _get_shape(good)
	var xf := Transform2D(angle, Vector2.ONE * (size / 100.0), 0.0, center)
	ci.draw_set_transform_matrix(xf)
	if outline.a > 0.0:
		var ow: float = outline_px * 100.0 / size
		for op in _get_outline_polys(good, ow):
			ci.draw_colored_polygon(op, outline)
	for part in s["parts"]:
		ci.draw_colored_polygon(part[0], part[1])
	for o in s["outlines"]:
		var closed: PackedVector2Array = (o as PackedVector2Array).duplicate()
		closed.append(o[0])
		ci.draw_polyline(closed, SEAM, 2.0)
	for seam in s["seams"]:
		ci.draw_line(seam[0], seam[1], seam[2], float(seam[3]))
	for ring in s["rings"]:
		ci.draw_arc(ring[0], float(ring[1]), 0.0, TAU, CIRCLE_STEPS, SEAM, 2.5)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

static func _get_outline_polys(good: String, width: float) -> Array:
	var w_key: int = maxi(1, roundi(width * 2.0))
	var key := "%s|%d" % [good, w_key]
	if not _outline_cache.has(key):
		var polys: Array = []
		for part in _get_shape(good)["parts"]:
			polys.append_array(Geometry2D.offset_polygon(part[0], float(w_key) * 0.5, Geometry2D.JOIN_ROUND))
		_outline_cache[key] = polys
	return _outline_cache[key]

static func _get_shape(good: String) -> Dictionary:
	if not _shape_cache.has(good):
		_shape_cache[good] = _build_shape(good)
	return _shape_cache[good]

static func _base_prim(id: String) -> Dictionary:
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
			return {"poly": _drop_poly(), "seams": [[Vector2(-14, 4), Vector2(14, 4)]], "color": ORANGE}
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
	return {"poly": _circle(Vector2.ZERO, 26.0), "seams": [], "color": DOT}

static func _stamp_prim(s: Dictionary, id: String, x: float, y: float, k: float = 1.0, deg: float = 0.0, color: Color = Color.TRANSPARENT, with_seams: bool = true, with_outline: bool = false) -> void:
	var b: Dictionary = _base_prim(id)
	var xf := Transform2D(deg_to_rad(deg), Vector2(k, k), 0.0, Vector2(x, y))
	var poly: PackedVector2Array = xf * (b["poly"] as PackedVector2Array)
	s["parts"].append([poly, b["color"] if color.a == 0.0 else color])
	if with_seams:
		for seam in b["seams"]:
			s["seams"].append([xf * seam[0], xf * seam[1], SEAM, 3.0 * k])
	if with_outline:
		s["outlines"].append(poly)

static func _add_part(s: Dictionary, poly: PackedVector2Array, color: Color) -> void:
	s["parts"].append([poly, color])

static func _add_seam(s: Dictionary, a: Vector2, b: Vector2, color: Color = SEAM, width: float = 3.0) -> void:
	s["seams"].append([a, b, color, width])

static func _add_eye(s: Dictionary, c: Vector2, r: float) -> void:
	_add_part(s, _circle(c, r), SEAM)

static func _add_wheel(s: Dictionary, c: Vector2, r: float) -> void:
	_add_part(s, _circle(c, r), DOT)
	s["rings"].append([c, r])

static func _build_shape(good: String) -> Dictionary:
	var s := {"parts": [], "seams": [], "rings": [], "outlines": []}
	match good:
		"dot", "wedge", "block", "capsule", "diamond", "bar", "drop", "pebble", "shield", "moon", "chevron", "dome":
			_stamp_prim(s, good, 0, 0)
		"heart":
			_add_part(s, _circle(Vector2(-17, -12), 19.0), ORANGE)
			_add_part(s, _circle(Vector2(17, -12), 19.0), ORANGE)
			_add_part(s, PackedVector2Array([Vector2(-34.5, -5), Vector2(34.5, -5), Vector2(0, 40)]), ORANGE)
			_add_seam(s, Vector2(0, -22), Vector2(0, -2))
		"star":
			_add_part(s, PackedVector2Array([Vector2(0, -44), Vector2(11, -14), Vector2(42, -14), Vector2(17, 6), Vector2(27, 38), Vector2(0, 19), Vector2(-27, 38), Vector2(-17, 6), Vector2(-42, -14), Vector2(-11, -14)]), WEDGE)
			_add_seam(s, Vector2(-10, 4), Vector2(10, 4))
		"leaf":
			var p := PackedVector2Array([Vector2(0, -44)])
			p.append_array(_quad_bez(Vector2(0, -44), Vector2(40, 0), Vector2(0, 44)))
			p.append_array(_quad_bez(Vector2(0, 44), Vector2(-40, 0), Vector2(0, -44)))
			p.remove_at(p.size() - 1)
			_add_part(s, p, ORANGE)
			_add_seam(s, Vector2(-14, 14), Vector2(14, -14))
		"bullet":
			var p := PackedVector2Array([Vector2(-22, 44)])
			p.append_array(_arc(Vector2(0, -20), 22.0, PI, TAU))
			p.append(Vector2(22, 44))
			_add_part(s, p, VIOLET)
			_add_seam(s, Vector2(-16, 8), Vector2(16, 8))
		"trefoil":
			for c in [Vector2(0, -16), Vector2(-18, 13), Vector2(18, 13)]:
				_add_part(s, _circle(c, 21.0), DOT)
			_add_part(s, _circle(Vector2(0, 4), 16.0), DOT)
		"gem":
			_add_part(s, PackedVector2Array([Vector2(-38, -12), Vector2(-20, -34), Vector2(20, -34), Vector2(38, -12), Vector2(0, 40)]), GREEN)
		"arrow":
			_stamp_prim(s, "bar", 0, 16, 0.65, 0, GREEN, false)
			_stamp_prim(s, "chevron", 0, -14, 0.9, 0, GREEN, false)
		"wave":
			_stamp_prim(s, "moon", -4, 4, 1.0, 0, ORANGE, false)
			_stamp_prim(s, "drop", 16, -12, 0.5, 45, ORANGE, false)
		"swirl":
			_stamp_prim(s, "moon", -10, 0, 0.75, 0, DOT, false)
			_stamp_prim(s, "moon", 10, 0, 0.75, 180, DOT, false)
		"acorn":
			_stamp_prim(s, "shield", 0, 12, 0.82, 0, TEAL, false)
			_add_part(s, _rect(-3, -46, 6, 12), BROWN)
			_stamp_prim(s, "capsule", 0, -20, 0.85, 0, BROWN, false)
		"helmet":
			_stamp_prim(s, "moon", 0, -20, 1.0, -61, DOT, false)
			_stamp_prim(s, "shield", 0, 14, 0.8, 0, INK, false)
			_add_seam(s, Vector2(-18, 10), Vector2(18, 10), Color(1, 1, 1, 0.3), 4.0)
		"fish":
			_stamp_prim(s, "chevron", 32, 0, 0.5, -90)
			_stamp_prim(s, "capsule", -8, 0, 0.8)
			_add_eye(s, Vector2(-30, -4), 3.5)
		"mushroom":
			_stamp_prim(s, "bar", 0, 24, 0.42)
			_stamp_prim(s, "dome", 0, -6)
		"paddle":
			_stamp_prim(s, "bar", 0, 26, 0.42)
			_stamp_prim(s, "pebble", 0, -16, 0.7)
		"standard":
			_stamp_prim(s, "bar", 0, 26, 0.42)
			_stamp_prim(s, "shield", 0, -14, 0.7)
		"kite":
			_stamp_prim(s, "chevron", 0, 24, 0.55)
			_stamp_prim(s, "diamond", 0, -14, 0.65, 0, Color.TRANSPARENT, true, true)
		"bull":
			_stamp_prim(s, "dome", 0, 12, 0.95)
			_stamp_prim(s, "moon", 0, -14, 0.75, -61, Color.TRANSPARENT, true, true)
			_add_eye(s, Vector2(-10, 6), 3.5)
			_add_eye(s, Vector2(10, 6), 3.5)
		"imp":
			_stamp_prim(s, "pebble", 0, 14, 0.78, 0, Color.TRANSPARENT, false)
			_stamp_prim(s, "chevron", 0, -14, 0.72)
			_add_eye(s, Vector2(-9, 16), 3.5)
			_add_eye(s, Vector2(9, 16), 3.5)
		"candle":
			_stamp_prim(s, "block", 0, 24, 0.55)
			_stamp_prim(s, "drop", 0, -16, 0.7)
		"eclipse":
			_stamp_prim(s, "moon", 0, 0)
			_add_wheel(s, Vector2(18, -10), 14.0)
		"propeller":
			for a in [0.0, 120.0, 240.0]:
				var at := Vector2(0, -23).rotated(deg_to_rad(a))
				_stamp_prim(s, "drop", at.x, at.y, 0.5, a + 180.0)
		"cart":
			_add_part(s, _rect(-44, -26, 88, 34), BLOCK)
			_add_seam(s, Vector2(0, -20), Vector2(0, 2))
			_add_part(s, _circle(Vector2(-24, 16), 13.0), DOT)
			_add_part(s, _circle(Vector2(24, 16), 13.0), DOT)
		"bus":
			_stamp_prim(s, "capsule", 0, -6)
			_add_wheel(s, Vector2(-24, 20), 11.0)
			_add_wheel(s, Vector2(24, 20), 11.0)
		"rocket":
			_stamp_prim(s, "chevron", 0, 30, 0.8)
			_add_part(s, _rect(-11, -18, 22, 52), BLOCK)
			_add_part(s, PackedVector2Array([Vector2(0, -48), Vector2(18, -18), Vector2(-18, -18)]), WEDGE)
		"lighthouse":
			_stamp_prim(s, "bar", -14, 20, 0.55)
			_stamp_prim(s, "wedge", 7, -18, 0.6, -90)
			_add_part(s, _circle(Vector2(-14, -18), 12.0), DOT)
		"bird":
			_stamp_prim(s, "shield", -4.3, 8.3, 0.56, 45, Color.TRANSPARENT, false)
			_stamp_prim(s, "drop", 27, -6, 0.3, 90, Color.TRANSPARENT, false)
			_stamp_prim(s, "dot", 10, -6, 0.55)
			_add_eye(s, Vector2(14, -11), 3.0)
		"turtle":
			_stamp_prim(s, "capsule", 2, 18, 0.85, 0, Color.TRANSPARENT, false)
			_stamp_prim(s, "dot", -36, 12, 0.3)
			_stamp_prim(s, "dome", 4, 6, 0.9, 0, GREEN)
			_add_eye(s, Vector2(-38, 9), 2.5)
		"crab":
			_stamp_prim(s, "moon", -30, -16, 0.45, -61)
			_stamp_prim(s, "moon", 30, -16, 0.45, -61)
			_stamp_prim(s, "dome", 0, 14, 0.85, 0, Color.TRANSPARENT, false, true)
			_add_eye(s, Vector2(-9, 8), 3.5)
			_add_eye(s, Vector2(9, 8), 3.5)
		"fir":
			_stamp_prim(s, "bar", 0, 28, 0.34, 0, Color.TRANSPARENT, false)
			_stamp_prim(s, "chevron", 0, 10, 0.95)
			_stamp_prim(s, "wedge", 0, -24, 0.55)
		"owl":
			_stamp_prim(s, "pebble", 0, 6, 1.0, 0, Color.TRANSPARENT, false)
			_add_wheel(s, Vector2(-13, -6), 10.0)
			_add_wheel(s, Vector2(13, -6), 10.0)
			_stamp_prim(s, "diamond", 0, 14, 0.2, 0, Color.TRANSPARENT, false)
		"rabbit":
			_stamp_prim(s, "capsule", -12, -26, 0.42, 90, Color.TRANSPARENT, false)
			_stamp_prim(s, "capsule", 12, -26, 0.42, 90, Color.TRANSPARENT, false)
			_stamp_prim(s, "pebble", 0, 18, 0.8, 0, Color.TRANSPARENT, false)
			_add_wheel(s, Vector2(0, 22), 6.0)
		"cat":
			_stamp_prim(s, "wedge", -24, -24, 0.36, -25)
			_stamp_prim(s, "wedge", 24, -24, 0.36, 25)
			_stamp_prim(s, "pebble", 0, 8, 0.95, 0, Color.TRANSPARENT, false)
			_stamp_prim(s, "wedge", 0, 14, 0.2, 180)
		_:
			_add_part(s, _circle(Vector2.ZERO, 28.0), DOT)
	s["main"] = _dominant_color(s["parts"])
	return s

static func _dominant_color(parts: Array) -> Color:
	var best: float = -1.0
	var col: Color = DOT
	for part in parts:
		var p: PackedVector2Array = part[0]
		var sum: float = 0.0
		for i in range(p.size()):
			sum += p[i].cross(p[(i + 1) % p.size()])
		var area: float = absf(sum) * 0.5
		if area > best:
			best = area
			col = part[1]
	return col

static func _drop_poly() -> PackedVector2Array:
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
	for i in range(CIRCLE_STEPS):
		out.append(c + Vector2.from_angle(TAU * float(i) / float(CIRCLE_STEPS)) * r)
	return out

static func _arc(c: Vector2, r: float, from: float, to: float) -> PackedVector2Array:
	var steps: int = maxi(2, ceili(absf(to - from) / TAU * float(CIRCLE_STEPS)))
	var out := PackedVector2Array()
	for i in range(steps + 1):
		out.append(c + Vector2.from_angle(lerpf(from, to, float(i) / float(steps))) * r)
	return out

static func _quad_bez(a: Vector2, b: Vector2, c: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, 9):
		var t: float = float(i) / 8.0
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out

# === AUTHENTIC RULE TOOLBAR VECTOR ICONS (RuleEditor.draw_tool_icon) ===

static func draw_tool_icon(ci: CanvasItem, tool_id: String, c: Vector2, r: float, alpha: float = 1.0) -> void:
	var red := Color(Color("C8323A"), alpha)
	var white := Color(Color.WHITE, alpha)
	var blue := Color(Color("4B80CA"), alpha)
	var road := Color(Color("3C3F4A"), alpha)

	match tool_id:
		"yield":
			var pts := PackedVector2Array([c + Vector2(0, r * 0.95), c + Vector2(r, -r * 0.72), c + Vector2(-r, -r * 0.72)])
			ci.draw_colored_polygon(pts, white)
			pts.append(pts[0])
			ci.draw_polyline(pts, red, 2.8, true)
		"close_street", "stop":
			var oct := PackedVector2Array()
			for i in range(8):
				oct.append(c + Vector2.from_angle(TAU * float(i) / 8.0 + PI / 8.0) * (r * 0.96))
			ci.draw_colored_polygon(oct, red)
			ci.draw_rect(Rect2(c - Vector2(r * 0.52, r * 0.16), Vector2(r * 1.04, r * 0.32)), white)
		"lights":
			ci.draw_rect(Rect2(c - Vector2(r * 0.54, r * 1.18), Vector2(r * 1.08, r * 2.36)), Color(Color("23242B"), alpha))
			var cols := [Color("C8323A"), Color("F2AB37"), Color("4FB35E")]
			for i in range(3):
				ci.draw_circle(c + Vector2(0, float(i - 1) * r * 0.74), r * 0.30, Color(cols[i], alpha))
		"roundabout":
			ci.draw_circle(c, r * 1.06, blue)
			for i in range(3):
				var from: float = -PI * 0.5 - float(i) * TAU / 3.0
				var to: float = from - TAU / 3.0 + 0.52
				ci.draw_arc(c, r * 0.58, to, from, 12, white, 2.3, true)
				var tip: Vector2 = c + Vector2.from_angle(to) * r * 0.58
				var along := Vector2.from_angle(to - PI * 0.5)
				var side := Vector2.from_angle(to) * r * 0.24
				ci.draw_colored_polygon(PackedVector2Array([tip + along * r * 0.3, tip + side, tip - side]), white)
		"lanes", "lanes_add", "lanes_remove":
			ci.draw_rect(Rect2(c - Vector2(r * 0.92, r * 1.12), Vector2(r * 1.84, r * 2.24)), road)
			for i in range(3):
				var y: float = -r * 0.96 + float(i) * r * 0.74
				ci.draw_line(c + Vector2(0, y), c + Vector2(0, y + r * 0.44), white, 2.0)
		"one_way":
			ci.draw_rect(Rect2(c - Vector2(r * 1.12, r * 0.68), Vector2(r * 2.24, r * 1.36)), blue)
			ci.draw_line(c - Vector2(r * 0.80, 0.0), c + Vector2(r * 0.28, 0.0), white, r * 0.34)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.90, 0.0), c + Vector2(r * 0.22, -r * 0.48), c + Vector2(r * 0.22, r * 0.48)]), white)
		"offers_ui", "roads":
			var bend := PackedVector2Array()
			for i in range(9):
				var s: float = float(i) / 8.0
				bend.append(c + Vector2(-r * 0.85 + s * r * 1.45, r * 1.05 - s * r * 2.1 + sin(s * PI) * r * 0.45))
			ci.draw_polyline(bend, road, r * 0.85, true)
			for i in range(4):
				ci.draw_line(bend[i * 2], bend[i * 2 + 1], white, 1.5)
			var badge: Vector2 = c + Vector2(r * 0.65, r * 0.65)
			ci.draw_circle(badge, r * 0.48, blue)
			ci.draw_line(badge - Vector2(r * 0.26, 0), badge + Vector2(r * 0.26, 0), white, 2.0)
			ci.draw_line(badge - Vector2(0, r * 0.26), badge + Vector2(0, r * 0.26), white, 2.0)
		"route":
			ci.draw_line(c + Vector2(-r * 0.85, r * 0.65), c + Vector2(r * 0.85, -r * 0.65), blue, 2.8, true)
			ci.draw_circle(c + Vector2(-r * 0.80, r * 0.60), r * 0.34, Color("E0533D"))
			ci.draw_circle(c + Vector2(r * 0.80, -r * 0.60), r * 0.38, Color("4FB35E"))

# === AUTHENTIC UPGRADE ICONS (FactoryPanel.UpgradeIcon.draw_icon) ===

static func draw_upgrade_icon(ci: CanvasItem, track: String, origin: Vector2, c: Color) -> void:
	var w: float = 1.8
	ci.draw_set_transform(origin, 0.0, Vector2.ONE)
	match track:
		"speed":
			ci.draw_arc(Vector2(9, 12), 7.0, PI, TAU, 16, c, w, true)
			ci.draw_line(Vector2(9, 12), Vector2(13, 7), c, w, true)
		"rate":
			ci.draw_line(Vector2(9, 16), Vector2(9, 5), c, w, true)
			ci.draw_polyline(PackedVector2Array([Vector2(5, 9), Vector2(9, 4), Vector2(13, 9)]), c, w, true)
		"expand":
			for p in [
				[Vector2(2, 7), Vector2(2, 2), Vector2(7, 2)],
				[Vector2(11, 2), Vector2(16, 2), Vector2(16, 7)],
				[Vector2(2, 11), Vector2(2, 16), Vector2(7, 16)],
				[Vector2(11, 16), Vector2(16, 16), Vector2(16, 11)]
			]:
				ci.draw_polyline(PackedVector2Array(p), c, w, true)
		"buffer":
			for r in [Rect2(3, 11, 5, 5), Rect2(10, 11, 5, 5), Rect2(6.5, 5, 5, 5)]:
				ci.draw_rect(r, c, false, w * 0.85)
		"bays":
			for x in [2.0, 7.0, 12.0, 17.0]:
				ci.draw_line(Vector2(x, 3), Vector2(x, 16), c, 1.6)
			ci.draw_rect(Rect2(3.5, 8, 2, 6), c)
		"wideGate", "exitRoad":
			ci.draw_line(Vector2(5, 16), Vector2(5, 3), c, w, true)
			ci.draw_polyline(PackedVector2Array([Vector2(2, 6), Vector2(5, 3), Vector2(8, 6)]), c, w, true)
			ci.draw_line(Vector2(13, 2), Vector2(13, 15), c, w, true)
			ci.draw_polyline(PackedVector2Array([Vector2(10, 12), Vector2(13, 15), Vector2(16, 12)]), c, w, true)
		"trainLength":
			ci.draw_rect(Rect2(3, 2, 12, 11), c, false, 1.6)
			ci.draw_line(Vector2(3, 8), Vector2(15, 8), c, 1.6)
			ci.draw_line(Vector2(6, 16), Vector2(7.5, 13), c, 1.6)
			ci.draw_line(Vector2(12, 16), Vector2(10.5, 13), c, 1.6)
		"shipSize":
			ci.draw_polyline(PackedVector2Array([Vector2(1, 10), Vector2(17, 10), Vector2(14, 15), Vector2(4, 15), Vector2(1, 10)]), c, 1.6, true)
			ci.draw_rect(Rect2(6, 4, 6, 6), c, false, 1.6)
		"timetable":
			ci.draw_arc(Vector2(9, 9), 7.0, 0.0, TAU, 20, c, 1.6, true)
			ci.draw_polyline(PackedVector2Array([Vector2(9, 4.5), Vector2(9, 9), Vector2(12.5, 11)]), c, 1.6, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# === AUTHENTIC OVERLAY BAR 5 ICONS (OverlayBar.Icon._draw) ===

static func draw_overlay_icon(ci: CanvasItem, mode_id: String, c: Vector2, ink: Color) -> void:
	match mode_id:
		"routes":
			ci.draw_line(c + Vector2(-10, 7), c + Vector2(10, -7), ink, 2.0, true)
			ci.draw_circle(c + Vector2(2, -1.5), 6.0, Color("4FB35E"))
			ci.draw_circle(c + Vector2(2, -1.5), 3.2, ink)
		"traffic":
			var cols := [Color("4FB35E"), Color("F2C230"), Color("C8323A")]
			for i in range(3):
				var y: float = -6.5 + float(i) * 6.5
				ci.draw_line(c + Vector2(-9.5, y), c + Vector2(9.5, y), cols[i], 2.8)
		"flow":
			for i in range(3):
				var y: float = -6.5 + float(i) * 6.5
				var w: float = 1.4 + float(i) * 1.4
				ci.draw_line(c + Vector2(-9.5, y), c + Vector2(4.5, y), ink, w)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(9.5, y), c + Vector2(3.8, y - 3.2), c + Vector2(3.8, y + 3.2)]), ink)
		"buildings":
			ci.draw_rect(Rect2(c + Vector2(-8.5, -4.5), Vector2(13, 12)), ink, false, 2.0)
			ci.draw_rect(Rect2(c + Vector2(-5.5, -8.5), Vector2(5, 4)), ink)
			ci.draw_circle(c + Vector2(6.5, -5.5), 4.2, Color("3E9E50"))
		"demand":
			var hs := [7.5, 13.0, 17.0]
			for i in range(3):
				var h: float = float(hs[i])
				ci.draw_rect(Rect2(c + Vector2(-9.5 + float(i) * 7.0, 8.5 - h), Vector2(4.8, h)), ink)

# === DAY CLOCK SUN / MOON & BELL / GEAR ===

static func draw_sun_moon(ci: CanvasItem, c: Vector2, is_night: bool) -> void:
	if is_night:
		var clipped := Geometry2D.clip_polygons(_circle(c, 7.0), _circle(c + Vector2(3.5, -2.5), 6.0))
		for part in clipped:
			ci.draw_colored_polygon(part, Color("8C93C9"))
	else:
		var col := Color("E8A33A")
		ci.draw_circle(c, 4.5, col)
		for i in range(8):
			var d := Vector2.from_angle(TAU * float(i) / 8.0)
			ci.draw_line(c + d * 6.4, c + d * 8.6, col, 1.6, true)

static func draw_bell_icon(ci: CanvasItem, c: Vector2, ink: Color, has_alert: bool = false) -> void:
	var dome := _arc(c + Vector2(0, -1), 6.0, PI, TAU)
	dome.append(c + Vector2(7.5, 5.0))
	dome.append(c + Vector2(-7.5, 5.0))
	ci.draw_colored_polygon(dome, ink)
	ci.draw_circle(c + Vector2(0, 7.2), 2.2, ink)
	if has_alert:
		ci.draw_circle(c + Vector2(6.5, -5.5), 4.0, Color("C8323A"))

# === HERALDIC TOWN CREST (TownCrest._draw) ===

static func draw_town_crest(ci: CanvasItem, map_id: String, box: Rect2) -> void:
	var spec: Dictionary = MADIUN_CRESTS.get(map_id, MADIUN_CRESTS["karisidenan_madiun"])
	var s: float = minf(box.size.x / 100.0, box.size.y / 120.0)
	var origin: Vector2 = box.position + (box.size - Vector2(100.0, 120.0) * s) * 0.5
	ci.draw_set_transform(origin, 0.0, Vector2(s, s))

	var shield := PackedVector2Array([Vector2(6, 6), Vector2(94, 6), Vector2(94, 60)])
	for i in range(1, 9):
		shield.append(_cubic_bez(Vector2(94, 60), Vector2(94, 92), Vector2(70, 108), Vector2(50, 116), float(i) / 8.0))
	for i in range(1, 9):
		shield.append(_cubic_bez(Vector2(50, 116), Vector2(30, 108), Vector2(6, 92), Vector2(6, 60), float(i) / 8.0))

	var field_col := Color(String(spec["field"]))
	var charge_col := Color(String(spec["charge"]))
	var rim_col := Color(String(spec["rim"]))

	ci.draw_colored_polygon(shield, field_col)
	match String(spec["style"]):
		"hanse":
			ci.draw_rect(Rect2(38, 50, 24, 42), charge_col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(50, 14), Vector2(38, 50), Vector2(62, 50)]), charge_col)
		"coal":
			ci.draw_rect(Rect2(28, 26, 10, 66), charge_col)
			ci.draw_arc(Vector2(62, 62), 18.0, 0.0, TAU, 24, charge_col, 7.0, true)
			ci.draw_line(Vector2(62, 44), Vector2(62, 80), charge_col, 5.0)
			ci.draw_line(Vector2(44, 62), Vector2(80, 62), charge_col, 5.0)
		"wine":
			ci.draw_rect(Rect2(30, 40, 40, 52), charge_col)
			for x in [26.0, 45.0, 64.0]:
				ci.draw_rect(Rect2(x, 30, 10, 14), charge_col)
			ci.draw_rect(Rect2(45, 70, 10, 22), rim_col)
		"alpine":
			ci.draw_rect(Rect2(41, 52, 18, 40), charge_col)
			ci.draw_circle(Vector2(50, 42), 12.5, charge_col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(50, 18), Vector2(45, 32), Vector2(55, 32)]), charge_col)
		"heath":
			ci.draw_rect(Rect2(44, 52, 12, 40), charge_col)
			for to in [Vector2(22, 22), Vector2(78, 22), Vector2(22, 78), Vector2(78, 78)]:
				ci.draw_line(Vector2(50, 50), to, charge_col, 7.0)
		"spa":
			ci.draw_rect(Rect2(22, 66, 56, 26), charge_col)
			var dome := _arc(Vector2(50, 66), 20.0, PI, TAU)
			ci.draw_colored_polygon(dome, charge_col)
			ci.draw_rect(Rect2(48, 34, 4, 14), charge_col)
		"riviera":
			ci.draw_rect(Rect2(42, 30, 16, 62), charge_col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(38, 30), Vector2(50, 16), Vector2(62, 30)]), charge_col)
			ci.draw_rect(Rect2(46, 40, 8, 10), rim_col)

	var rim_poly := shield.duplicate()
	rim_poly.append(shield[0])
	ci.draw_polyline(rim_poly, rim_col, 5.0, true)
	ci.draw_polyline(rim_poly, Color("23242B"), 2.2, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _cubic_bez(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return a * (u * u * u) + b * (3.0 * u * u * t) + c * (3.0 * u * t * t) + d * (t * t * t)

# === MINI ARTICULATED TRUCK DIAGRAM (TruckIcon._draw) ===

static func draw_mini_truck(ci: CanvasItem, model_id: String, origin: Vector2, height: float = 14.0, cab_col: Color = Color("3B82F6"), good_id: String = "") -> float:
	var tdef: Dictionary = GameCatalog.TRUCKS.get(model_id, GameCatalog.TRUCKS["hauler"])
	var trailers: Array = tdef["trailers"]
	var h: float = height
	var x: float = origin.x
	var y: float = origin.y
	var paper := Color("F6F5EF")
	var ink := Color("1D2128")

	for ti in range(trailers.size() - 1, -1, -1):
		var slots: int = int(trailers[ti])
		var tw: float = maxf(h * 1.05, float(slots) * (h * 0.62))
		var r := Rect2(x, y, tw, h)
		ci.draw_rect(r, paper, true)
		ci.draw_rect(r, ink, false, 1.4)
		if good_id != "" and GameCatalog.GOODS.has(good_id):
			var g_slots: int = int(GameCatalog.GOODS[good_id]["slots"])
			var fit: int = 1 if bool(tdef["any_size_per_trailer"]) else maxi(0, slots / g_slots)
			for si in range(fit):
				var gx: float = x + tw * (float(si) + 0.5) / float(maxi(1, fit))
				draw_shape(ci, good_id, Vector2(gx, y + h * 0.5), h * 0.62)
		x += tw + 2.0

	# Tractor cab facing right
	var cw: float = h * 0.78
	var cab_r := Rect2(x, y + h * 0.08, cw, h * 0.84)
	ci.draw_rect(cab_r, cab_col, true)
	ci.draw_rect(Rect2(x + cw * 0.55, y + h * 0.20, cw * 0.34, h * 0.60), Color("2B3442"), true)
	ci.draw_rect(cab_r, ink, false, 1.4)
	return (x + cw) - origin.x
