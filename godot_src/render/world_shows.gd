class_name WorldShows
extends Node2D

## Authentic Incremental Traffic v1.4.1 World Interactive & Cinematic Layer:
## 1. Interactive `RegionGate` (`OPEN` / `GROW` floating CTA + 60s hold ring + off-screen edge pointer)
## 2. In-world `RoadOfferSigns` (top-6 congestion-ranked corridors, 2-tap preview + clash `×` markers + purchase)
## 3. `RoadShow` (asphalt shockwave & dust puffs along newly built corridors)
## 4. `UnlockShow` (camera glide + cloud-dispersal puffs + staggered facility slam rings + 170 confetti ribbons)
## 5. `BoomShow` (camera skyline tour + multi-burst sky fireworks with `firework_pop`)

signal show_completed(info: Dictionary)
signal status_message(msg: String)

var sim: SimEngine
var camera: TouchCamera2D
var map_view: MapView25D
var sfx: SfxSynth

var preview_offer_id: String = ""
var suppress_cinematics: bool = false
var ui_blocked: bool = false

var _ui_font: Font
var _gate_hit_world := Rect2()
var _offer_hit_rects: Array[Dictionary] = [] # {id, rect, name, price}

# Active particle effects
var _dust_puffs: Array[Dictionary] = []      # {pos, vel, r0, r1, age, dur, col}
var _slam_rings: Array[Dictionary] = []      # {pos, delay, age, dur, col, playedSfx}
var _firework_shells: Array[Dictionary] = [] # {pos, delay, col}
var _firework_sparks: Array[Dictionary] = [] # {pos, vel, age, dur, col, size}
var _confetti: Array[Dictionary] = []        # screen-space {pos, vel, rot, rotSpd, col, size, age, dur}

var _fx_canvas: _WorldShowsFXLayer
var _last_gate_ready_key: String = ""

const CONFETTI_PALETTE := [
	Color("FF595E"), Color("FFCA3A"), Color("8AC926"),
	Color("1982C4"), Color("6A4C93"), Color("FF924C")
]

func setup(sim_engine: SimEngine, cam: TouchCamera2D, view: MapView25D, sfx_node: SfxSynth) -> void:
	sim = sim_engine
	camera = cam
	map_view = view
	sfx = sfx_node
	if map_view != null:
		map_view.interactive_gate_handled = true

	if ResourceLoader.exists("res://gui/theme_studies/fonts/Jost-Variable.ttf"):
		_ui_font = load("res://gui/theme_studies/fonts/Jost-Variable.ttf") as Font
	else:
		_ui_font = ThemeDB.fallback_font

	_fx_canvas = _WorldShowsFXLayer.new()
	_fx_canvas.layer = 14
	_fx_canvas.owner_shows = self
	add_child(_fx_canvas)

	if not sim.cinematic_unlock_triggered.is_connected(_on_cinematic_unlock):
		sim.cinematic_unlock_triggered.connect(_on_cinematic_unlock)
	if not sim.cinematic_boom_triggered.is_connected(_on_cinematic_boom):
		sim.cinematic_boom_triggered.connect(_on_cinematic_boom)
	if not sim.road_built_triggered.is_connected(_on_road_built):
		sim.road_built_triggered.connect(_on_road_built)

func _process(delta: float) -> void:
	if sim == null or camera == null:
		return

	# Chime `gate_ready` once whenever a RegionGate or Boomtown gate newly reaches 60s ready!
	var gate: Dictionary = sim.get_region_gate_state()
	if bool(gate.get("hasGate", false)) and bool(gate.get("isReady", false)):
		var gkey := "%s:%d:%d" % [sim.current_map_id, int(gate.get("regionIndex", -1)), sim.boomtown_level]
		if gkey != _last_gate_ready_key:
			_last_gate_ready_key = gkey
			if sfx != null and not suppress_cinematics:
				sfx.play_ui("gate_ready")
	elif not bool(gate.get("isReady", false)):
		_last_gate_ready_key = ""

	_step_particles(delta)
	queue_redraw()
	if _fx_canvas != null:
		_fx_canvas.queue_fx_redraw()

func _step_particles(delta: float) -> void:
	var i: int = _dust_puffs.size() - 1
	while i >= 0:
		var p: Dictionary = _dust_puffs[i]
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= float(p["dur"]):
			_dust_puffs.remove_at(i)
		else:
			p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		i -= 1

	i = _slam_rings.size() - 1
	while i >= 0:
		var sr: Dictionary = _slam_rings[i]
		if float(sr["delay"]) > 0.0:
			sr["delay"] = float(sr["delay"]) - delta
			if float(sr["delay"]) <= 0.0 and not bool(sr["playedSfx"]):
				sr["playedSfx"] = true
				if sfx != null and not suppress_cinematics:
					sfx.play_ui("building_slam")
		else:
			sr["age"] = float(sr["age"]) + delta
			if float(sr["age"]) >= float(sr["dur"]):
				_slam_rings.remove_at(i)
		i -= 1

	i = _firework_shells.size() - 1
	while i >= 0:
		var sh: Dictionary = _firework_shells[i]
		sh["delay"] = float(sh["delay"]) - delta
		if float(sh["delay"]) <= 0.0:
			_explode_firework(sh["pos"], sh["col"])
			_firework_shells.remove_at(i)
		i -= 1

	i = _firework_sparks.size() - 1
	while i >= 0:
		var sp: Dictionary = _firework_sparks[i]
		sp["age"] = float(sp["age"]) + delta
		if float(sp["age"]) >= float(sp["dur"]):
			_firework_sparks.remove_at(i)
		else:
			var vel: Vector2 = sp["vel"]
			vel.y += 26.0 * delta
			vel *= exp(-1.6 * delta)
			sp["vel"] = vel
			sp["pos"] = (sp["pos"] as Vector2) + vel * delta
		i -= 1

	i = _confetti.size() - 1
	while i >= 0:
		var cf: Dictionary = _confetti[i]
		cf["age"] = float(cf["age"]) + delta
		if float(cf["age"]) >= float(cf["dur"]):
			_confetti.remove_at(i)
		else:
			var v_cf: Vector2 = cf["vel"]
			v_cf.y += 280.0 * delta
			v_cf.x += sin(float(cf["age"]) * 6.5 + float(cf["phase"])) * 42.0 * delta
			cf["vel"] = v_cf
			cf["pos"] = (cf["pos"] as Vector2) + v_cf * delta
			cf["rot"] = float(cf["rot"]) + float(cf["rotSpd"]) * delta
		i -= 1

func try_handle_world_tap(world_pos: Vector2) -> bool:
	if sim == null or camera == null or ui_blocked:
		return false

	# 1. Check interactive `RegionGate` world card / button
	if _gate_hit_world.size.x > 1.0 and _gate_hit_world.grow(6.0).has_point(world_pos):
		var gate: Dictionary = sim.get_region_gate_state()
		if bool(gate.get("hasGate", false)):
			if bool(gate.get("isReady", false)):
				if sfx != null:
					sfx.play_ui("gate_press")
				sim.trigger_ready_region_or_boom()
			else:
				var rem: int = maxi(1, int(ceil(SimEngine.HOLD_REQUIRED_SEC - float(gate.get("holdSeconds", 0.0)))))
				if sfx != null:
					sfx.tap()
				status_message.emit("Pertahankan target %s selama %d dtk lagi untuk %s!" % [
					String(gate.get("title", "Wilayah")), rem, String(gate.get("buttonText", "OPEN"))
				])
			return true

	# 2. Check in-world `RoadOfferSigns` (2-tap preview -> purchase!)
	for entry in _offer_hit_rects:
		var r_rect: Rect2 = entry["rect"]
		if r_rect.grow(5.0).has_point(world_pos):
			var oid := String(entry["id"])
			if preview_offer_id != oid:
				preview_offer_id = oid
				if sfx != null:
					sfx.tap(10)
				status_message.emit("Pratinjau %s (%s) — ketuk rambu sekali lagi untuk membangun!" % [
					String(entry["name"]), GameCatalog.fmt_cash(int(entry["price"]))
				])
			else:
				var msg: String = sim.purchase_road_offer(oid)
				preview_offer_id = ""
				if msg != "":
					status_message.emit(msg)
			return true

	if preview_offer_id != "":
		preview_offer_id = ""
	return false

func _on_road_built(info: Dictionary) -> void:
	preview_offer_id = ""
	var off: Dictionary = info.get("offer", {})
	if off.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for eid in off.get("edgeIds", []):
		var r: Dictionary = sim.road_map.get(String(eid), {})
		if r.is_empty():
			continue
		var pts: PackedVector2Array = r["pts"]
		var cum: PackedFloat32Array = r["cum_len"]
		var tot: float = float(r["lengthPx"])
		var s: float = 0.0
		while s <= tot:
			var p: Vector2 = RoadGeom.sample_polyline_raw(pts, cum, s)["pos"]
			for _k in range(2):
				var ang: float = rng.randf_range(0.0, TAU)
				_dust_puffs.append({
					"pos": p + Vector2(cos(ang), sin(ang)) * rng.randf_range(1.0, 4.5),
					"vel": Vector2(cos(ang), sin(ang)) * rng.randf_range(5.0, 14.0),
					"r0": 3.0,
					"r1": rng.randf_range(9.5, 15.5),
					"age": 0.0,
					"dur": rng.randf_range(0.45, 0.85),
					"col": Color(0.95, 0.93, 0.86, 0.72)
				})
			s += 14.0
	var spos: Vector2 = off.get("signPos", Vector2.ZERO)
	_slam_rings.append({
		"pos": spos,
		"delay": 0.0,
		"age": 0.0,
		"dur": 0.65,
		"col": Color("F4C64A"),
		"playedSfx": true
	})

func _on_cinematic_unlock(info: Dictionary) -> void:
	if suppress_cinematics:
		show_completed.emit(info)
		return
	var center: Vector2 = info.get("center", camera.global_position)
	var accent: Color = info.get("accent", Color("2B8A3E"))
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in range(28):
		var ang: float = TAU * (float(i) / 28.0) + rng.randf_range(-0.08, 0.08)
		var dist: float = rng.randf_range(18.0, 85.0)
		_dust_puffs.append({
			"pos": center + Vector2(cos(ang), sin(ang)) * dist,
			"vel": Vector2(cos(ang), sin(ang)) * rng.randf_range(18.0, 38.0),
			"r0": 8.0,
			"r1": rng.randf_range(22.0, 36.0),
			"age": 0.0,
			"dur": rng.randf_range(0.75, 1.35),
			"col": Color(0.98, 0.97, 0.94, 0.78)
		})

	var facs: Array = info.get("facilities", [])
	for fi in range(facs.size()):
		var f: Dictionary = facs[fi]
		_slam_rings.append({
			"pos": f["pos"],
			"delay": 0.22 + float(fi) * 0.14,
			"age": 0.0,
			"dur": 0.58,
			"col": accent,
			"playedSfx": false
		})

	spawn_screen_confetti(170)
	if sfx != null:
		sfx.play_ui("confetti_pop")
		sfx.play_ui("unlock_fanfare")

	var waypoints := [{
		"pos": center,
		"zoom": clampf(camera.zoom.x, 0.68, 1.05),
		"flySec": 0.78,
		"holdSec": 0.72
	}]
	camera.start_cinematic_tour(waypoints, func():
		show_completed.emit(info)
	)

func _on_cinematic_boom(info: Dictionary) -> void:
	if suppress_cinematics:
		show_completed.emit(info)
		return
	var center: Vector2 = info.get("center", camera.global_position)
	var grown: Array = info.get("grownPoints", [])
	var spawned: Array = info.get("spawnedFacilities", [])

	var fw_colors := [Color("FFD43B"), Color("FF6B6B"), Color("4DABF7"), Color("69DB7C"), Color("FFA94D"), Color("DA77F2")]
	for bi in range(6):
		var anchor: Vector2 = center
		if not grown.is_empty():
			anchor = grown[bi % grown.size()]
		var offset := Vector2(cos(float(bi) * 1.15) * 34.0, sin(float(bi) * 1.15) * 24.0 - 18.0)
		_firework_shells.append({
			"pos": anchor + offset,
			"delay": 0.12 + float(bi) * 0.24,
			"col": fw_colors[bi % fw_colors.size()]
		})

	for sf in spawned:
		_slam_rings.append({
			"pos": sf["pos"],
			"delay": 0.35,
			"age": 0.0,
			"dur": 0.65,
			"col": Color("D9480F"),
			"playedSfx": false
		})

	spawn_screen_confetti(110)
	var waypoints: Array = [{
		"pos": center,
		"zoom": clampf(camera.zoom.x, 0.74, 1.08),
		"flySec": 0.68,
		"holdSec": 0.65
	}]
	if not spawned.is_empty():
		waypoints.append({
			"pos": spawned[0]["pos"],
			"zoom": 1.05,
			"flySec": 0.58,
			"holdSec": 0.48
		})
	camera.start_cinematic_tour(waypoints, func():
		show_completed.emit(info)
	)

func _explode_firework(world_pos: Vector2, col: Color) -> void:
	if sfx != null and not suppress_cinematics:
		sfx.play_firework_pop()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(34):
		var ang: float = TAU * (float(i) / 34.0) + rng.randf_range(-0.09, 0.09)
		var spd: float = rng.randf_range(16.0, 48.0)
		_firework_sparks.append({
			"pos": world_pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"age": 0.0,
			"dur": rng.randf_range(0.55, 1.05),
			"col": col.lightened(rng.randf_range(0.0, 0.28)),
			"size": rng.randf_range(1.6, 3.0)
		})

func spawn_screen_confetti(count: int = 170) -> void:
	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 10.0:
		vp = Vector2(1280.0, 720.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in range(count):
		var from_left: bool = rng.randf() < 0.5
		var start_p := Vector2(
			rng.randf_range(0.05 * vp.x, 0.95 * vp.x),
			rng.randf_range(-40.0, vp.y * 0.18)
		)
		var vx: float = rng.randf_range(-130.0, 130.0) + (45.0 if from_left else -45.0)
		var vy: float = rng.randf_range(55.0, 210.0)
		_confetti.append({
			"pos": start_p,
			"vel": Vector2(vx, vy),
			"rot": rng.randf_range(0.0, TAU),
			"rotSpd": rng.randf_range(-7.5, 7.5),
			"phase": rng.randf_range(0.0, TAU),
			"col": CONFETTI_PALETTE[rng.randi() % CONFETTI_PALETTE.size()],
			"size": Vector2(rng.randf_range(7.0, 12.0), rng.randf_range(4.0, 7.0)),
			"age": 0.0,
			"dur": rng.randf_range(1.6, 2.7)
		})

func _draw() -> void:
	_gate_hit_world = Rect2()
	_offer_hit_rects.clear()
	if sim == null or camera == null or map_view == null:
		return

	var frustum: Rect2 = map_view.get_world_frustum()
	var zoom_x: float = camera.zoom.x
	var inv_z: float = clampf(1.0 / maxf(0.35, zoom_x), 0.65, 1.68)
	var font: Font = _ui_font if _ui_font != null else ThemeDB.fallback_font
	var cb: bool = map_view.colorblind_mode

	if map_view.overlay_mode == "none" and map_view.active_tool in ["pan", "lanes_add", "lanes_remove"]:
		_draw_road_offer_signs(frustum, font, inv_z)

	_draw_interactive_region_gate(frustum, font, inv_z, cb)
	_draw_world_particles(frustum)

func _draw_road_offer_signs(frustum: Rect2, font: Font, inv_z: float) -> void:
	var offers: Array[Dictionary] = sim.get_ranked_road_offers(6)
	if offers.is_empty():
		return

	if preview_offer_id != "":
		for off_p in offers:
			if String(off_p["id"]) == preview_offer_id:
				for eid in off_p.get("edgeIds", []):
					var rd: Dictionary = sim.road_map.get(String(eid), {})
					if not rd.is_empty():
						var rw: float = float(rd.get("widthPx", 12.0))
						draw_polyline(rd["pts"], Color(0.96, 0.78, 0.29, 0.42), rw + 5.0, true)
						draw_polyline(rd["pts"], Color("2B8A3E"), 2.8, true)
				for cl_id in off_p.get("clashes", []):
					for other_off in sim.road_offers:
						if String(other_off["id"]) == String(cl_id) and not bool(other_off.get("purchased", false)):
							var cp: Vector2 = other_off.get("signPos", Vector2.ZERO)
							if frustum.has_point(cp):
								var cr: float = 9.0 * inv_z
								draw_circle(cp, cr + 1.5 * inv_z, Color("FAF7EE"))
								draw_circle(cp, cr, Color("C8323A"))
								var d: float = 4.2 * inv_z
								draw_line(cp + Vector2(-d, -d), cp + Vector2(d, d), Color.WHITE, 2.0 * inv_z, true)
								draw_line(cp + Vector2(-d, d), cp + Vector2(d, -d), Color.WHITE, 2.0 * inv_z, true)
				break

	var sc: float = clampf(inv_z, 0.72, 1.32)
	for off in offers:
		var spos: Vector2 = off.get("signPos", Vector2.ZERO)
		if not frustum.has_point(spos):
			continue
		var oid := String(off["id"])
		var pr: int = int(off.get("price", sim.get_road_offer_price(off)))
		var can_afford: bool = sim.cash >= pr
		var is_prev: bool = (oid == preview_offer_id)

		var pr_txt: String = ("BANGUN " if is_prev else "🛣 ") + GameCatalog.fmt_cash(pr)
		var pw: float = (22.0 + float(pr_txt.length()) * 6.2) * sc
		var ph: float = 20.0 * sc
		var box := Rect2(spos.x - pw * 0.5, spos.y - ph * 0.5, pw, ph)
		_offer_hit_rects.append({
			"id": oid,
			"rect": box,
			"name": String(off.get("name", "Jalan Baru")),
			"price": pr
		})

		draw_line(Vector2(spos.x, box.end.y), Vector2(spos.x, box.end.y + 6.5 * sc), Color("23242B"), 2.0 * sc)
		draw_rect(Rect2(box.position + Vector2(1.8 * sc, 2.2 * sc), box.size), Color(0, 0, 0, 0.25), true)
		var bg_c: Color = Color("2B8A3E") if is_prev else (Color("FAF7EE") if can_afford else Color("E5E2D9"))
		var bd_c: Color = Color("FFD43B") if is_prev else (Color("2B8A3E") if can_afford else Color("7A776E"))
		var tx_c: Color = Color.WHITE if is_prev else (Color("23242B") if can_afford else Color("6E6B63"))
		draw_rect(box, bg_c, true)
		draw_rect(box, bd_c, false, 1.9 * sc)
		draw_string(font, Vector2(box.position.x + 4.0 * sc, box.position.y + 14.2 * sc), pr_txt, HORIZONTAL_ALIGNMENT_CENTER, pw - 8.0 * sc, int(10.5 * sc), tx_c)

func _draw_interactive_region_gate(frustum: Rect2, font: Font, inv_z: float, cb: bool) -> void:
	var gate: Dictionary = sim.get_region_gate_state()
	if not bool(gate.get("hasGate", false)):
		return
	var rc: Vector2 = gate["pos"]
	var is_boom: bool = bool(gate["isBoom"])
	if is_boom:
		rc += Vector2(0.0, -44.0)
	if not frustum.has_point(rc):
		return

	var is_ready: bool = bool(gate["isReady"])
	var hold_01: float = float(gate["hold01"])
	var goals: Array = gate.get("goals", [])
	var accent: Color = gate.get("accent", Color("2B8A3E"))
	var sc: float = clampf(inv_z, 0.72, 1.42)
	var pulse: float = (1.0 + 0.06 * sin(float(Time.get_ticks_msec()) * 0.008)) if is_ready else 1.0

	var card_w: float = 138.0 * sc
	var card_h: float = (44.0 + float(goals.size()) * 13.5) * sc
	var card_r := Rect2(rc.x - card_w * 0.5, rc.y - card_h * 0.5, card_w, card_h)
	_gate_hit_world = card_r

	if is_ready:
		var glow_r := card_r.grow(5.5 * sc * pulse)
		draw_rect(glow_r, Color(accent.r, accent.g, accent.b, 0.28), true)

	draw_rect(Rect2(card_r.position + Vector2(2.5 * sc, 3.2 * sc), card_r.size), Color("23242B"), true)
	draw_rect(card_r, Color("FAF7EE"), true)
	draw_rect(card_r, accent if is_ready else Color("23242B"), false, (2.4 if is_ready else 1.8) * sc)

	var ring_c := card_r.position + Vector2(14.5 * sc, 14.5 * sc)
	var ring_r: float = 8.8 * sc
	draw_arc(ring_c, ring_r, 0.0, TAU, 20, Color(0.14, 0.15, 0.18, 0.16), 2.8 * sc, true)
	if hold_01 > 0.01:
		draw_arc(ring_c, ring_r, -PI * 0.5, -PI * 0.5 + TAU * hold_01, 20, accent, 2.8 * sc, true)
	draw_circle(ring_c, 3.2 * sc, accent if is_ready else Color("23242B"))

	var title_s := String(gate.get("title", "Region"))
	draw_string(font, card_r.position + Vector2(27.0 * sc, 15.0 * sc), title_s, HORIZONTAL_ALIGNMENT_LEFT, card_w - 32.0 * sc, int(9.8 * sc), Color("23242B"))
	var hold_lbl := "SIAP!" if is_ready else ("%ds / 60s" % int(floor(float(gate.get("holdSeconds", 0.0)))))
	draw_string(font, card_r.position + Vector2(27.0 * sc, 25.0 * sc), hold_lbl, HORIZONTAL_ALIGNMENT_LEFT, card_w - 32.0 * sc, int(8.2 * sc), accent if is_ready else Color("625F57"))

	for gi in range(goals.size()):
		var gd: Dictionary = goals[gi]
		var gid := String(gd["good"])
		var cur_v: float = float(gd.get("currentPerMin", 0.0))
		var tgt_v: float = float(gd["targetPerMin"])
		var ratio: float = clampf(cur_v / maxf(0.1, tgt_v), 0.0, 1.0)
		var gy: float = card_r.position.y + (34.0 + float(gi) * 13.0) * sc
		ShapeGlyphs.draw(self, gid, Vector2(card_r.position.x + 11.0 * sc, gy), 9.2 * sc, 0.0, MapView25D.TRUCK_INK, 0.38, Transform2D.IDENTITY, cb)
		var bar_r := Rect2(card_r.position.x + 20.0 * sc, gy - 2.4 * sc, 58.0 * sc, 4.8 * sc)
		draw_rect(bar_r, Color(0.14, 0.15, 0.18, 0.14), true)
		draw_rect(Rect2(bar_r.position, Vector2(bar_r.size.x * ratio, bar_r.size.y)), ShapeGlyphs.color_of(gid, cb), true)
		var vs := "%.1f/%.0f" % [cur_v, tgt_v]
		draw_string(font, Vector2(bar_r.end.x + 4.0 * sc, gy + 3.4 * sc), vs, HORIZONTAL_ALIGNMENT_RIGHT, 50.0 * sc, int(8.4 * sc), Color("23242B"))

	if is_ready:
		var btn_txt := "🔓 " + String(gate.get("buttonText", "OPEN")) + " SEKARANG!"
		var bw: float = (card_w - 14.0 * sc) * pulse
		var bh: float = 18.5 * sc * pulse
		var btn_r := Rect2(rc.x - bw * 0.5, card_r.end.y - 4.0 * sc, bw, bh)
		_gate_hit_world = card_r.merge(btn_r)
		draw_rect(Rect2(btn_r.position + Vector2(1.5 * sc, 2.0 * sc), btn_r.size), Color("23242B"), true)
		draw_rect(btn_r, accent, true)
		draw_rect(btn_r, Color("FAF7EE"), false, 1.5 * sc)
		draw_string(font, Vector2(btn_r.position.x + 4.0 * sc, btn_r.position.y + 13.2 * sc), btn_txt, HORIZONTAL_ALIGNMENT_CENTER, bw - 8.0 * sc, int(9.8 * sc), Color.WHITE)

func _draw_world_particles(frustum: Rect2) -> void:
	var cull: Rect2 = frustum.grow(48.0)
	for p in _dust_puffs:
		var pos: Vector2 = p["pos"]
		if not cull.has_point(pos):
			continue
		var k: float = clampf(float(p["age"]) / maxf(0.05, float(p["dur"])), 0.0, 1.0)
		var r: float = lerpf(float(p["r0"]), float(p["r1"]), 1.0 - (1.0 - k) * (1.0 - k))
		var c: Color = p["col"]
		c.a *= (1.0 - k)
		draw_circle(pos, r, c)

	for sr in _slam_rings:
		if float(sr["delay"]) > 0.0:
			continue
		var spos: Vector2 = sr["pos"]
		if not cull.has_point(spos):
			continue
		var ks: float = clampf(float(sr["age"]) / maxf(0.05, float(sr["dur"])), 0.0, 1.0)
		var rs: float = lerpf(8.0, 38.0, ks)
		var cs: Color = sr["col"]
		cs.a = (1.0 - ks) * 0.90
		draw_arc(spos, rs, 0.0, TAU, 28, cs, lerpf(4.2, 1.2, ks), true)

	for sp in _firework_sparks:
		var fpos: Vector2 = sp["pos"]
		if not cull.has_point(fpos):
			continue
		var kf: float = clampf(float(sp["age"]) / maxf(0.05, float(sp["dur"])), 0.0, 1.0)
		var cf: Color = sp["col"]
		cf.a = 1.0 - kf * kf
		var sz: float = float(sp["size"]) * (1.0 - 0.45 * kf)
		draw_circle(fpos, sz, cf)


class _WorldShowsFXLayer extends CanvasLayer:
	var owner_shows: WorldShows
	var _pointer_btn: Button
	var _confetti_drawer: _ConfettiDrawer

	func _ready() -> void:
		_confetti_drawer = _ConfettiDrawer.new()
		_confetti_drawer.owner_shows = owner_shows
		_confetti_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_confetti_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_confetti_drawer)

		_pointer_btn = Button.new()
		_pointer_btn.visible = false
		_pointer_btn.custom_minimum_size = Vector2(186, 40)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("2B8A3E")
		sb.border_color = Color("FAF7EE")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(20)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		_pointer_btn.add_theme_stylebox_override("normal", sb)
		_pointer_btn.add_theme_stylebox_override("hover", sb)
		_pointer_btn.add_theme_stylebox_override("pressed", sb)
		_pointer_btn.add_theme_color_override("font_color", Color.WHITE)
		_pointer_btn.add_theme_font_size_override("font_size", 14)
		_pointer_btn.pressed.connect(_on_pointer_pressed)
		add_child(_pointer_btn)

	func queue_fx_redraw() -> void:
		if _confetti_drawer != null:
			_confetti_drawer.owner_shows = owner_shows
			_confetti_drawer.queue_redraw()

	func _on_pointer_pressed() -> void:
		if owner_shows == null or owner_shows.sim == null or owner_shows.camera == null:
			return
		var gate: Dictionary = owner_shows.sim.get_region_gate_state()
		if bool(gate.get("hasGate", false)):
			var gp: Vector2 = gate["pos"]
			if bool(gate.get("isBoom", false)):
				gp += Vector2(0.0, -44.0)
			owner_shows.camera.fly_to_world(gp, 0.92, 0.72)

	func _process(_delta: float) -> void:
		if owner_shows == null or owner_shows.sim == null or owner_shows.camera == null or owner_shows.map_view == null:
			_pointer_btn.visible = false
			return
		if owner_shows.ui_blocked:
			_pointer_btn.visible = false
			return
		var gate: Dictionary = owner_shows.sim.get_region_gate_state()
		if not bool(gate.get("hasGate", false)) or not bool(gate.get("isReady", false)):
			_pointer_btn.visible = false
			return
		var gp: Vector2 = gate["pos"]
		if bool(gate.get("isBoom", false)):
			gp += Vector2(0.0, -44.0)
		var frustum: Rect2 = owner_shows.map_view.get_world_frustum()
		if frustum.has_point(gp):
			_pointer_btn.visible = false
			return

		var vp: Vector2 = get_viewport().get_visible_rect().size
		var scr: Vector2 = owner_shows.camera.world_to_screen(gp)
		var dir: Vector2 = (scr - vp * 0.5).normalized()
		var arrow := "→"
		if absf(dir.y) > absf(dir.x):
			arrow = "↓" if dir.y > 0.0 else "↑"
		else:
			arrow = "→" if dir.x > 0.0 else "←"
		_pointer_btn.text = "%s %s SIAP! %s" % [
			"🚀" if bool(gate["isBoom"]) else "🔓",
			String(gate.get("buttonText", "OPEN")),
			arrow
		]
		var bx: float = clampf(scr.x - _pointer_btn.size.x * 0.5, 16.0, maxf(16.0, vp.x - _pointer_btn.size.x - 16.0))
		var by: float = clampf(scr.y - _pointer_btn.size.y * 0.5, 68.0, maxf(68.0, vp.y - _pointer_btn.size.y - 78.0))
		_pointer_btn.position = Vector2(bx, by)
		_pointer_btn.visible = true


class _ConfettiDrawer extends Control:
	var owner_shows: WorldShows

	func _draw() -> void:
		if owner_shows == null or owner_shows._confetti.is_empty():
			return
		var cid: RID = get_canvas_item()
		for cf in owner_shows._confetti:
			var pos: Vector2 = cf["pos"]
			var sz: Vector2 = cf["size"]
			var rot: float = float(cf["rot"])
			var k: float = clampf(float(cf["age"]) / maxf(0.1, float(cf["dur"])), 0.0, 1.0)
			var col: Color = cf["col"]
			col.a = clampf(1.0 - maxf(0.0, (k - 0.72) / 0.28), 0.0, 1.0)
			var flutter: float = 0.35 + 0.65 * absf(cos(rot * 1.7))
			var xform := Transform2D(rot, pos)
			RenderingServer.canvas_item_add_set_transform(cid, xform)
			draw_rect(Rect2(-sz.x * 0.5, -sz.y * flutter * 0.5, sz.x, sz.y * flutter), col, true)
		RenderingServer.canvas_item_add_set_transform(cid, Transform2D.IDENTITY)
