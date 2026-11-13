class_name StageOverlays
extends CanvasLayer

## Authentic Incremental Traffic v1.4.1 Stage Flow, Multi-Slot Save/Load, CityCode,
## LoadingRoundabout, RegionOpenPopup, RoadReroutePanel, and BrokenRouteBanner.
## Responsive across both Android Landscape and Portrait viewports.

signal title_visibility_changed(is_open: bool)
signal map_load_requested(map_id: String, load_save: bool, city_code: String)
signal toast_requested(msg: String)

const B32_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

const COL_PARCHMENT := Color("FAF7EE")
const COL_CARD_BG := Color("F2F0E5")
const COL_INK := Color("23242B")
const COL_MUTED := Color("625F57")
const COL_GREEN := Color("2B8A3E")
const COL_BLUE := Color("2B6CB0")
const COL_AMBER := Color("D9480F")
const COL_RED := Color("C8323A")

var sim: SimEngine
var camera: TouchCamera2D
var map_view: MapView25D
var hud: CanvasLayer
var sfx: SfxSynth

var is_title_open: bool = false
var is_modal_open: bool = false

var _font: Font
var _saved_speed_before_pause: int = 1

# Root containers
var _broken_banner: PanelContainer
var _broken_lbl: Label
var _broken_target_pos := Vector2.ZERO
var _broken_route_id: String = ""

var _reroute_card: PanelContainer
var _reroute_vbox: VBoxContainer
var _active_reroute_offer_id: String = ""

var _modal_backdrop: ColorRect
var _modal_center: CenterContainer
var _modal_card: PanelContainer
var _modal_body: VBoxContainer

var _title_root: Control
var _title_subpanel: PanelContainer
var _title_sub_vbox: VBoxContainer
var _title_continue_btn: Button
var _title_code_lbl: Label
var _newgame_selected_map: String = "karisidenan_madiun"
var _newgame_lht: bool = true
var _newgame_seed: int = 4721
var _preview_drawer: _CityPreviewMinimap
var _code_edit: LineEdit

var _loading_layer: ColorRect
var _loading_roundabout: _LoadingRoundaboutWidget
var _loading_lbl: Label
var _loading_timer: float = 0.0
var _loading_dur: float = 0.0
var _loading_mid_called: bool = false
var _loading_on_mid: Callable = Callable()

var _fx_drawer: _OverlayStarsDrawer
var _homing_stars: Array[Dictionary] = []

static func encode_city_code(map_idx: int, lht: bool, seed_val: int) -> String:
	var m_bits: int = clampi(map_idx, 0, 15) & 0xF
	var l_bit: int = 1 if lht else 0
	var s_bits: int = abs(seed_val) & 0xFFFFFF
	var packed_hi: int = (m_bits << 1) | l_bit # 5 bits -> 1st char
	var chars: Array[String] = []
	chars.append(B32_ALPHABET[packed_hi & 31])
	var tmp: int = s_bits
	for _i in range(5):
		chars.append(B32_ALPHABET[tmp & 31])
		tmp >>= 5
	# Salt + checksum across remaining 6 chars (`MADIUN` signature + CRC)
	var tag := "MDN16"
	for ti in range(5):
		var idx: int = B32_ALPHABET.find(tag[ti])
		chars.append(B32_ALPHABET[maxi(0, idx)])
	var csum: int = 7
	for c in chars:
		csum = (csum * 33 + B32_ALPHABET.find(c)) & 31
	chars.append(B32_ALPHABET[csum])
	var raw := "".join(chars)
	return "%s-%s-%s" % [raw.substr(0, 4), raw.substr(4, 4), raw.substr(8, 4)]

static func decode_city_code(code_str: String, max_maps: int = 7) -> Dictionary:
	var clean := code_str.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if clean.length() != 12:
		return {"valid": false}
	var vals: Array[int] = []
	for i in range(12):
		var idx: int = B32_ALPHABET.find(clean[i])
		if idx < 0:
			return {"valid": false}
		vals.append(idx)
	var csum: int = 7
	for i in range(11):
		csum = (csum * 33 + vals[i]) & 31
	if vals[11] != csum:
		return {"valid": false}
	var map_idx: int = clampi((vals[0] >> 1) & 0xF, 0, maxi(0, max_maps - 1))
	var lht: bool = (vals[0] & 1) != 0
	var s_val: int = 0
	for i in range(4, -1, -1):
		s_val = (s_val << 5) | vals[1 + i]
	return {
		"valid": true,
		"mapIndex": map_idx,
		"lht": lht,
		"seed": s_val
	}

func setup(sim_engine: SimEngine, cam: TouchCamera2D, view: MapView25D, hud_node: CanvasLayer, sfx_node: SfxSynth) -> void:
	layer = 24
	sim = sim_engine
	camera = cam
	map_view = view
	hud = hud_node
	sfx = sfx_node

	if ResourceLoader.exists("res://gui/theme_studies/fonts/Jost-Variable.ttf"):
		_font = load("res://gui/theme_studies/fonts/Jost-Variable.ttf") as Font
	else:
		_font = ThemeDB.fallback_font

	_build_broken_route_banner()
	_build_reroute_panel()
	_build_modal_shell()
	_build_title_stage()
	_build_loading_roundabout()

	_fx_drawer = _OverlayStarsDrawer.new()
	_fx_drawer.owner_ov = self
	_fx_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fx_drawer)

	if not sim.road_built_triggered.is_connected(_on_road_built_triggered):
		sim.road_built_triggered.connect(_on_road_built_triggered)

	get_viewport().size_changed.connect(_on_viewport_resized)
	_refresh_city_code_from_sim()
	_on_viewport_resized()

func _refresh_city_code_from_sim() -> void:
	if sim == null:
		return
	var midx: int = 0
	for i in range(sim.maps_list.size()):
		if String(sim.maps_list[i]["id"]) == sim.current_map_id:
			midx = i
			break
	if sim.current_city_code == "":
		sim.current_city_code = encode_city_code(midx, sim.left_hand_traffic, _newgame_seed)
	if _title_code_lbl != null:
		_title_code_lbl.text = "Kode Kota: " + sim.current_city_code

func _style_box(bg: Color, border: Color, bw: int = 2, radius: int = 12, pad: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = maxi(6, pad - 2)
	sb.content_margin_bottom = maxi(6, pad - 2)
	return sb

func _make_btn(txt: String, bg: Color = COL_PARCHMENT, fg: Color = COL_INK, border: Color = COL_INK, font_sz: int = 15, min_h: float = 42.0) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", font_sz)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.42))
	b.add_theme_stylebox_override("normal", _style_box(bg, border, 2, 10, 12))
	b.add_theme_stylebox_override("hover", _style_box(bg.lightened(0.06), border, 2, 10, 12))
	b.add_theme_stylebox_override("pressed", _style_box(bg.darkened(0.08), border, 2, 10, 12))
	b.add_theme_stylebox_override("disabled", _style_box(Color(bg, 0.55), Color(border, 0.35), 1, 10, 12))
	return b

func _make_lbl(txt: String, sz: int = 15, col: Color = COL_INK, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = align
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _style_line_edit(le: LineEdit, sz: int = 14) -> void:
	le.add_theme_font_override("font", _font)
	le.add_theme_font_size_override("font_size", sz)
	le.add_theme_color_override("font_color", COL_INK)
	le.add_theme_color_override("font_placeholder_color", COL_MUTED)
	le.add_theme_color_override("caret_color", COL_INK)
	le.add_theme_stylebox_override("normal", _style_box(Color.WHITE, COL_INK, 2, 8, 10))
	le.add_theme_stylebox_override("focus", _style_box(Color.WHITE, COL_GREEN, 2, 8, 10))

func _build_broken_route_banner() -> void:
	_broken_banner = PanelContainer.new()
	_broken_banner.visible = false
	_broken_banner.add_theme_stylebox_override("panel", _style_box(Color("FFF5F5"), COL_RED, 2, 18, 10))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	_broken_lbl = _make_lbl("⚠ 1 Rute Terputus", 13, COL_RED)
	hb.add_child(_broken_lbl)
	var show_btn := _make_btn("Tampilkan", COL_RED, Color.WHITE, COL_INK, 12, 30.0)
	show_btn.pressed.connect(func():
		if camera != null and _broken_target_pos.is_finite():
			camera.fly_to_world(_broken_target_pos, 1.35, 0.72)
		if map_view != null and _broken_route_id != "":
			map_view.selected_route_id = _broken_route_id
	)
	hb.add_child(show_btn)
	_broken_banner.add_child(hb)
	add_child(_broken_banner)

func _build_reroute_panel() -> void:
	_reroute_card = PanelContainer.new()
	_reroute_card.visible = false
	_reroute_card.custom_minimum_size = Vector2(310, 0)
	_reroute_card.add_theme_stylebox_override("panel", _style_box(COL_PARCHMENT, COL_GREEN, 2, 14, 12))
	_reroute_vbox = VBoxContainer.new()
	_reroute_vbox.add_theme_constant_override("separation", 6)
	_reroute_card.add_child(_reroute_vbox)
	add_child(_reroute_card)

func _build_modal_shell() -> void:
	_modal_backdrop = ColorRect.new()
	_modal_backdrop.visible = false
	_modal_backdrop.color = Color(0.08, 0.10, 0.14, 0.62)
	_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_modal_backdrop)

	_modal_center = CenterContainer.new()
	_modal_center.visible = false
	_modal_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_modal_center)

	_modal_card = PanelContainer.new()
	_modal_card.custom_minimum_size = Vector2(420, 0)
	_modal_card.add_theme_stylebox_override("panel", _style_box(COL_PARCHMENT, COL_INK, 3, 16, 18))
	_modal_body = VBoxContainer.new()
	_modal_body.add_theme_constant_override("separation", 10)
	_modal_card.add_child(_modal_body)
	_modal_center.add_child(_modal_card)

func _build_title_stage() -> void:
	_title_root = Control.new()
	_title_root.visible = false
	_title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_title_root)

	var shade := ColorRect.new()
	shade.color = Color(0.10, 0.12, 0.16, 0.36)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_root.add_child(shade)

	var margin := MarginContainer.new()
	margin.name = "TitleMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_title_root.add_child(margin)

	var flow := BoxContainer.new()
	flow.name = "TitleFlow"
	flow.add_theme_constant_override("separation", 20)
	margin.add_child(flow)

	# Left / Top Main Title Card
	var main_card := PanelContainer.new()
	main_card.custom_minimum_size = Vector2(340, 0)
	main_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	main_card.add_theme_stylebox_override("panel", _style_box(COL_PARCHMENT, COL_INK, 3, 18, 20))
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)

	# Mini animated roundabout emblem + Title
	var hdr_hb := HBoxContainer.new()
	hdr_hb.add_theme_constant_override("separation", 12)
	var mini_rb := _LoadingRoundaboutWidget.new()
	mini_rb.compact_emblem = true
	mini_rb.custom_minimum_size = Vector2(54, 54)
	hdr_hb.add_child(mini_rb)

	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tv.add_child(_make_lbl("INCREMENTAL TRAFFIC", 22, COL_INK))
	tv.add_child(_make_lbl("KARESIDENAN MADIUN · ANDROID EDITION", 11, COL_AMBER))
	hdr_hb.add_child(tv)
	mv.add_child(hdr_hb)

	_title_code_lbl = _make_lbl("Kode Kota: ----", 12, COL_MUTED)
	mv.add_child(_title_code_lbl)

	_title_continue_btn = _make_btn("▶  Lanjutkan Permainan", COL_GREEN, Color.WHITE, COL_INK, 16, 46.0)
	_title_continue_btn.pressed.connect(_on_title_continue)
	mv.add_child(_title_continue_btn)

	var new_btn := _make_btn("🗺  Permainan Baru & Kode Kota", COL_CARD_BG, COL_INK, COL_INK, 15, 44.0)
	new_btn.pressed.connect(_populate_title_new_game_subpanel)
	mv.add_child(new_btn)

	var load_btn := _make_btn("💾  Muat Simpanan (Multi-Slot)", COL_CARD_BG, COL_INK, COL_INK, 15, 44.0)
	load_btn.pressed.connect(func(): show_save_load_menu(true))
	mv.add_child(load_btn)

	var opt_btn := _make_btn("⚙  Pengaturan Audio & Grafis", COL_CARD_BG, COL_INK, COL_INK, 15, 44.0)
	opt_btn.pressed.connect(func(): show_audio_options_modal())
	mv.add_child(opt_btn)

	var quit_btn := _make_btn("✕  Keluar", COL_PARCHMENT, COL_RED, COL_RED, 14, 38.0)
	quit_btn.pressed.connect(func():
		if sim != null:
			sim.save_to_disk()
		if sfx != null:
			sfx.shutdown()
		get_tree().quit()
	)
	mv.add_child(quit_btn)

	main_card.add_child(mv)
	flow.add_child(main_card)

	# Right / Bottom Subpanel (New Game Map Selector + `CityPreview` Minimap + `CityCode`)
	_title_subpanel = PanelContainer.new()
	_title_subpanel.visible = false
	_title_subpanel.custom_minimum_size = Vector2(360, 0)
	_title_subpanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_subpanel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_subpanel.add_theme_stylebox_override("panel", _style_box(COL_PARCHMENT, COL_INK, 3, 18, 16))
	_title_sub_vbox = VBoxContainer.new()
	_title_sub_vbox.add_theme_constant_override("separation", 8)
	_title_subpanel.add_child(_title_sub_vbox)
	flow.add_child(_title_subpanel)

func _build_loading_roundabout() -> void:
	_loading_layer = ColorRect.new()
	_loading_layer.visible = false
	_loading_layer.color = Color("1A1D24")
	_loading_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_loading_layer)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(cc)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	_loading_roundabout = _LoadingRoundaboutWidget.new()
	_loading_roundabout.custom_minimum_size = Vector2(168, 168)
	vb.add_child(_loading_roundabout)
	_loading_lbl = _make_lbl("Memuat Jaringan Jalan Karesidenan...", 16, COL_PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_loading_lbl)
	cc.add_child(vb)

func _on_viewport_resized() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var is_portrait: bool = vp.y > vp.x

	if _title_root != null:
		var flow := _title_root.get_node_or_null("TitleMargin/TitleFlow") as BoxContainer
		if flow != null:
			flow.vertical = is_portrait
			flow.alignment = BoxContainer.ALIGNMENT_CENTER

	if _modal_card != null:
		var target_w: float = clampf(vp.x - 32.0, 310.0, 520.0)
		_modal_card.custom_minimum_size = Vector2(target_w, 0)

	if _broken_banner != null:
		var bw: float = minf(vp.x - 24.0, 360.0)
		_broken_banner.position = Vector2((vp.x - bw) * 0.5, 66.0 if not is_portrait else 104.0)

	if _reroute_card != null:
		var rw: float = minf(vp.x - 24.0, 340.0)
		_reroute_card.custom_minimum_size = Vector2(rw, 0)
		if is_portrait:
			_reroute_card.position = Vector2((vp.x - rw) * 0.5, vp.y - 250.0)
		else:
			_reroute_card.position = Vector2(vp.x - rw - 18.0, vp.y - 235.0)

func _process(delta: float) -> void:
	if sim == null:
		return

	# Step `LoadingRoundabout` transition if active
	if _loading_layer != null and _loading_layer.visible:
		_loading_timer += delta
		if not _loading_mid_called and _loading_timer >= _loading_dur * 0.45:
			_loading_mid_called = true
			if _loading_on_mid.is_valid():
				_loading_on_mid.call()
		if _loading_timer >= _loading_dur:
			_loading_layer.visible = false
		return

	# Step homing star trails from `RegionOpenPopup`
	if not _homing_stars.is_empty():
		var i: int = _homing_stars.size() - 1
		while i >= 0:
			var st: Dictionary = _homing_stars[i]
			st["age"] = float(st["age"]) + delta
			var k: float = clampf(float(st["age"]) / maxf(0.1, float(st["dur"])), 0.0, 1.0)
			if k >= 1.0:
				if sfx != null:
					sfx.play_ui("star_ring", 0.96 + float(i % 4) * 0.06)
				_homing_stars.remove_at(i)
			else:
				var u: float = k * k * (3.0 - 2.0 * k)
				var p0: Vector2 = st["from"]
				var p1: Vector2 = st["to"]
				var mid: Vector2 = p0.lerp(p1, 0.5) + (st["arc"] as Vector2)
				st["pos"] = ((1.0 - u) * (1.0 - u)) * p0 + (2.0 * (1.0 - u) * u) * mid + (u * u) * p1
			i -= 1
		_fx_drawer.queue_redraw()

	# Refresh `BrokenRouteBanner` during active gameplay
	_update_broken_route_banner()

func _update_broken_route_banner() -> void:
	if _broken_banner == null or sim == null:
		return
	if is_title_open or is_modal_open:
		_broken_banner.visible = false
		return
	var broken_cnt: int = 0
	var first_rt: Dictionary = {}
	for rt in sim.routes:
		if String(rt.get("brokenReason", "")) != "":
			broken_cnt += 1
			if first_rt.is_empty():
				first_rt = rt
	if broken_cnt <= 0:
		_broken_banner.visible = false
		return
	_broken_route_id = String(first_rt["id"])
	_broken_target_pos = first_rt.get("brokenPos", Vector2.ZERO)
	if not _broken_target_pos.is_finite():
		var f_from: Dictionary = sim.facility_map.get(String(first_rt.get("fromFacilityId", "")), {})
		_broken_target_pos = f_from.get("pos", Vector2.ZERO)
	var tag := String(first_rt.get("brokenTag", "Putus"))
	_broken_lbl.text = "⚠ %d Rute Terputus (%s)" % [broken_cnt, tag]
	_broken_banner.visible = true

# === TITLE STAGE & LOADING TRANSITION ===

func show_title_stage() -> void:
	close_modal(false)
	_reroute_card.visible = false
	is_title_open = true
	_title_root.visible = true
	_title_subpanel.visible = false
	if hud != null:
		hud.visible = false
	if camera != null:
		camera.title_orbit_center = camera.global_position
		camera.title_orbit_active = true
	var slots: Array[Dictionary] = sim.list_save_slots()
	_title_continue_btn.text = "▶  Lanjutkan (%s)" % String(sim.map_def.get("name", "Madiun"))
	if not slots.is_empty():
		_title_continue_btn.text = "▶  Lanjutkan (%s)" % String(slots[0].get("label", slots[0].get("mapName", "Simpanan")))
	_refresh_city_code_from_sim()
	_on_viewport_resized()
	title_visibility_changed.emit(true)

func hide_title_stage() -> void:
	if not is_title_open:
		return
	is_title_open = false
	_title_root.visible = false
	_title_subpanel.visible = false
	if camera != null:
		camera.title_orbit_active = false
	if hud != null:
		hud.visible = true
	title_visibility_changed.emit(false)

func _on_title_continue() -> void:
	var slots: Array[Dictionary] = sim.list_save_slots()
	if not slots.is_empty():
		var latest_id := String(slots[0]["slotId"])
		play_loading_transition("Memuat %s..." % String(slots[0].get("label", "Kota")), func():
			sim.load_named_slot(latest_id)
			if camera != null:
				camera.focus_map(sim.map_def["initialView"], sim.map_def["boundsWorld"])
				camera.apply_camera_meta(sim.camera_meta)
			hide_title_stage()
		)
	else:
		hide_title_stage()

func _populate_title_new_game_subpanel() -> void:
	for ch in _title_sub_vbox.get_children():
		ch.queue_free()
	_title_subpanel.visible = true
	_newgame_selected_map = sim.current_map_id
	_newgame_lht = sim.left_hand_traffic

	var top_hb := HBoxContainer.new()
	var hdr := _make_lbl("Pilih Peta Wilayah atau Kode Kota", 16, COL_INK)
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hb.add_child(hdr)
	var cls_b := _make_btn("✕", COL_CARD_BG, COL_INK, COL_INK, 13, 32.0)
	cls_b.pressed.connect(func(): _title_subpanel.visible = false)
	top_hb.add_child(cls_b)
	_title_sub_vbox.add_child(top_hb)

	# Map selector buttons in compact ScrollContainer
	var map_scroll := ScrollContainer.new()
	map_scroll.custom_minimum_size = Vector2(0, 118)
	var map_vb := VBoxContainer.new()
	map_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_vb.add_theme_constant_override("separation", 5)
	for i in range(sim.maps_list.size()):
		var m: Dictionary = sim.maps_list[i]
		var mid := String(m["id"])
		var is_sel: bool = (mid == _newgame_selected_map)
		var mb := _make_btn(
			("%s  —  %s" % [String(m["name"]), String(m.get("subtitle", ""))]),
			COL_GREEN if is_sel else COL_CARD_BG,
			Color.WHITE if is_sel else COL_INK,
			COL_INK,
			13,
			36.0
		)
		var captured_i: int = i
		mb.pressed.connect(func():
			_newgame_selected_map = mid
			if _preview_drawer != null:
				_preview_drawer.set_map_dict(sim.maps_list[captured_i])
			_update_newgame_code_field()
		)
		map_vb.add_child(mb)
	map_scroll.add_child(map_vb)
	_title_sub_vbox.add_child(map_scroll)

	# Authentic `CityPreview` Vector Minimap!
	_preview_drawer = _CityPreviewMinimap.new()
	_preview_drawer.custom_minimum_size = Vector2(0, 112)
	for m_init in sim.maps_list:
		if String(m_init["id"]) == _newgame_selected_map:
			_preview_drawer.set_map_dict(m_init)
			break
	_title_sub_vbox.add_child(_preview_drawer)

	# LHT / RHT toggle + `CityCode` input
	var rule_hb := HBoxContainer.new()
	rule_hb.add_theme_constant_override("separation", 8)
	var lht_btn := _make_btn("Lajur Kiri (Indonesia)" if _newgame_lht else "Lajur Kanan (RHT)", COL_CARD_BG, COL_INK, COL_INK, 12, 34.0)
	lht_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lht_btn.pressed.connect(func():
		_newgame_lht = not _newgame_lht
		lht_btn.text = "Lajur Kiri (Indonesia)" if _newgame_lht else "Lajur Kanan (RHT)"
		_update_newgame_code_field()
	)
	rule_hb.add_child(lht_btn)

	var rnd_btn := _make_btn("🎲 Kode Acak", COL_CARD_BG, COL_INK, COL_INK, 12, 34.0)
	rnd_btn.pressed.connect(func():
		_newgame_seed = randi() & 0xFFFFFF
		_update_newgame_code_field()
	)
	rule_hb.add_child(rnd_btn)
	_title_sub_vbox.add_child(rule_hb)

	var code_hb := HBoxContainer.new()
	code_hb.add_theme_constant_override("separation", 6)
	code_hb.add_child(_make_lbl("CityCode:", 13, COL_MUTED))
	_code_edit = LineEdit.new()
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_line_edit(_code_edit, 14)
	_code_edit.placeholder_text = "XXXX-XXXX-XXXX"
	_code_edit.text_changed.connect(_on_city_code_typed)
	code_hb.add_child(_code_edit)
	_title_sub_vbox.add_child(code_hb)
	_update_newgame_code_field()

	var start_btn := _make_btn("🚀  Mulai Permainan Baru ($500)", COL_GREEN, Color.WHITE, COL_INK, 15, 44.0)
	start_btn.pressed.connect(func():
		var final_code: String = _code_edit.text.strip_edges().to_upper()
		play_loading_transition("Membangun %s..." % _newgame_selected_map, func():
			sim.left_hand_traffic = _newgame_lht
			sim.current_city_code = final_code
			map_load_requested.emit(_newgame_selected_map, false, final_code)
			hide_title_stage()
		)
	)
	_title_sub_vbox.add_child(start_btn)

func _update_newgame_code_field() -> void:
	if _code_edit == null or sim == null:
		return
	var midx: int = 0
	for i in range(sim.maps_list.size()):
		if String(sim.maps_list[i]["id"]) == _newgame_selected_map:
			midx = i
			break
	_code_edit.text = encode_city_code(midx, _newgame_lht, _newgame_seed)

func _on_city_code_typed(new_txt: String) -> void:
	if sim == null:
		return
	var dec: Dictionary = decode_city_code(new_txt, sim.maps_list.size())
	if bool(dec.get("valid", false)):
		var midx: int = int(dec["mapIndex"])
		_newgame_selected_map = String(sim.maps_list[midx]["id"])
		_newgame_lht = bool(dec["lht"])
		_newgame_seed = int(dec["seed"])
		if _preview_drawer != null:
			_preview_drawer.set_map_dict(sim.maps_list[midx])

func play_loading_transition(label_text: String, on_midpoint: Callable, dur: float = 0.68) -> void:
	_loading_lbl.text = label_text
	_loading_dur = maxf(0.18, dur)
	_loading_timer = 0.0
	_loading_mid_called = false
	_loading_on_mid = on_midpoint
	_loading_roundabout.lht = sim.left_hand_traffic if sim != null else true
	_loading_layer.visible = true

# === PAUSE MENU, MULTI-SLOT SAVE/LOAD & 5-CHANNEL AUDIO ===

func _open_modal_base(pause_sim: bool = true) -> void:
	for ch in _modal_body.get_children():
		ch.queue_free()
	if pause_sim and not is_modal_open and sim != null:
		_saved_speed_before_pause = sim.speed_multiplier
		sim.speed_multiplier = 0
	is_modal_open = true
	_modal_backdrop.visible = true
	_modal_center.visible = true
	_broken_banner.visible = false
	if sfx != null:
		sfx.play_ui("panel_open")
	_on_viewport_resized()

func close_modal(resume_sim: bool = true) -> void:
	if not is_modal_open:
		return
	is_modal_open = false
	_modal_backdrop.visible = false
	_modal_center.visible = false
	if resume_sim and sim != null and not is_title_open:
		sim.speed_multiplier = _saved_speed_before_pause if _saved_speed_before_pause > 0 else 1
	if sfx != null:
		sfx.play_ui("panel_close")

func show_pause_menu() -> void:
	_open_modal_base(true)
	_refresh_city_code_from_sim()

	var hdr_hb := HBoxContainer.new()
	var t_lbl := _make_lbl("⏸  Menu Jeda (Paused)", 20, COL_INK)
	t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_hb.add_child(t_lbl)
	var resume_top := _make_btn("▶ Lanjut", COL_GREEN, Color.WHITE, COL_INK, 14, 36.0)
	resume_top.pressed.connect(func(): close_modal(true))
	hdr_hb.add_child(resume_top)
	_modal_body.add_child(hdr_hb)

	var stat_txt := "%s  ·  Kas %s  ·  Populasi %s jiwa  ·  Boom Lv.%d" % [
		String(sim.map_def.get("name", "Madiun")),
		GameCatalog.fmt_cash(sim.cash),
		String.num_int64(sim.town_population),
		sim.boomtown_level
	]
	_modal_body.add_child(_make_lbl(stat_txt, 13, COL_MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	# CityCode copy bar
	var cc_hb := HBoxContainer.new()
	cc_hb.add_theme_constant_override("separation", 8)
	var cc_lbl := _make_lbl("CityCode: " + sim.current_city_code, 13, COL_INK)
	cc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc_hb.add_child(cc_lbl)
	var cp_btn := _make_btn("Salin Kode", COL_CARD_BG, COL_INK, COL_INK, 12, 32.0)
	cp_btn.pressed.connect(func():
		DisplayServer.clipboard_set(sim.current_city_code)
		toast_requested.emit("CityCode disalin: " + sim.current_city_code)
	)
	cc_hb.add_child(cp_btn)
	_modal_body.add_child(cc_hb)

	var save_mgr_btn := _make_btn("💾  Simpan / Muat Slot Permainan", COL_BLUE, Color.WHITE, COL_INK, 15, 44.0)
	save_mgr_btn.pressed.connect(func(): show_save_load_menu(false))
	_modal_body.add_child(save_mgr_btn)

	var audio_btn := _make_btn("🔊  Pengaturan Audio 5-Kanal", COL_CARD_BG, COL_INK, COL_INK, 15, 42.0)
	audio_btn.pressed.connect(func(): show_audio_options_modal())
	_modal_body.add_child(audio_btn)

	var reset_btn := _make_btn("↺  Ulangi Kota Ini dari Awal ($500)", COL_CARD_BG, COL_AMBER, COL_AMBER, 14, 40.0)
	reset_btn.pressed.connect(func():
		close_modal(false)
		play_loading_transition("Mengatur ulang %s..." % String(sim.map_def.get("name", "Kota")), func():
			sim.reset_current_map()
			sim.speed_multiplier = 1
			if camera != null:
				camera.focus_map(sim.map_def["initialView"], sim.map_def["boundsWorld"])
		)
	)
	_modal_body.add_child(reset_btn)

	var title_btn := _make_btn("🏠  Kembali ke Layar Judul (Title Stage)", COL_CARD_BG, COL_INK, COL_INK, 14, 40.0)
	title_btn.pressed.connect(func():
		if camera != null:
			sim.camera_meta = camera.export_camera_meta()
		sim.save_to_disk()
		show_title_stage()
	)
	_modal_body.add_child(title_btn)

func show_save_load_menu(from_title: bool = false) -> void:
	_open_modal_base(not from_title)

	var hdr_hb := HBoxContainer.new()
	var t_lbl := _make_lbl("💾  Manajer Simpanan (RunSave v4)", 18, COL_INK)
	t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_hb.add_child(t_lbl)
	var back_b := _make_btn("Tutup", COL_CARD_BG, COL_INK, COL_INK, 13, 34.0)
	back_b.pressed.connect(func():
		if from_title:
			close_modal(false)
		else:
			show_pause_menu()
	)
	hdr_hb.add_child(back_b)
	_modal_body.add_child(hdr_hb)

	# Save New Slot row (when in active game)
	if not from_title:
		var new_hb := HBoxContainer.new()
		new_hb.add_theme_constant_override("separation", 6)
		var slot_in := LineEdit.new()
		slot_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_in.placeholder_text = "Nama simpanan baru (mis. Madiun Malam)..."
		slot_in.text = "%s - %s" % [String(sim.map_def.get("name", "Madiun")), GameCatalog.fmt_cash(sim.cash)]
		_style_line_edit(slot_in, 13)
		new_hb.add_child(slot_in)
		var sv_btn := _make_btn("+ Simpan", COL_GREEN, Color.WHITE, COL_INK, 13, 38.0)
		sv_btn.pressed.connect(func():
			if camera != null:
				sim.camera_meta = camera.export_camera_meta()
			var nm: String = slot_in.text.strip_edges()
			if nm == "":
				nm = "Slot Karesidenan"
			if sim.save_named_slot(nm):
				toast_requested.emit("Tersimpan: " + nm)
				show_save_load_menu(false)
		)
		new_hb.add_child(sv_btn)
		_modal_body.add_child(new_hb)

	var slots: Array[Dictionary] = sim.list_save_slots()
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 250)
	var sl_vb := VBoxContainer.new()
	sl_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl_vb.add_theme_constant_override("separation", 8)

	if slots.is_empty():
		sl_vb.add_child(_make_lbl("Belum ada berkas simpanan. Buat simpanan baru di atas!", 13, COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER, true))
	else:
		for sl in slots:
			var sid := String(sl["slotId"])
			var row_p := PanelContainer.new()
			row_p.add_theme_stylebox_override("panel", _style_box(COL_CARD_BG, COL_INK, 1, 10, 10))
			var rvb := VBoxContainer.new()
			rvb.add_theme_constant_override("separation", 4)

			var edit_nm := LineEdit.new()
			edit_nm.text = String(sl.get("label", sid))
			_style_line_edit(edit_nm, 14)
			rvb.add_child(edit_nm)

			var meta_s := "%s · Kas %s · Boom Lv.%d · v%d" % [
				String(sl.get("mapName", sl.get("mapId", ""))),
				GameCatalog.fmt_cash(int(sl.get("cash", 0))),
				int(sl.get("boomLevel", 0)),
				int(sl.get("version", 4))
			]
			rvb.add_child(_make_lbl(meta_s, 11, COL_MUTED))

			var act_hb := HBoxContainer.new()
			act_hb.add_theme_constant_override("separation", 6)
			var ld_b := _make_btn("Muat", COL_GREEN, Color.WHITE, COL_INK, 12, 32.0)
			ld_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ld_b.pressed.connect(func():
				close_modal(false)
				play_loading_transition("Memuat %s..." % edit_nm.text, func():
					if sim.load_named_slot(sid):
						if camera != null:
							camera.focus_map(sim.map_def["initialView"], sim.map_def["boundsWorld"])
							camera.apply_camera_meta(sim.camera_meta)
						sim.speed_multiplier = 1
						hide_title_stage()
						toast_requested.emit("Simpanan dimuat: " + edit_nm.text)
				)
			)
			act_hb.add_child(ld_b)

			var rn_b := _make_btn("Ubah Nama", COL_PARCHMENT, COL_INK, COL_INK, 12, 32.0)
			rn_b.pressed.connect(func():
				var nn := edit_nm.text.strip_edges()
				if nn != "" and sim.rename_save_slot(sid, nn):
					toast_requested.emit("Nama slot diperbarui")
					show_save_load_menu(from_title)
			)
			act_hb.add_child(rn_b)

			var dl_b := _make_btn("Hapus", COL_PARCHMENT, COL_RED, COL_RED, 12, 32.0)
			dl_b.pressed.connect(func():
				sim.delete_save_slot(sid)
				show_save_load_menu(from_title)
			)
			act_hb.add_child(dl_b)

			rvb.add_child(act_hb)
			row_p.add_child(rvb)
			sl_vb.add_child(row_p)

	sc.add_child(sl_vb)
	_modal_body.add_child(sc)

func show_audio_options_modal() -> void:
	var was_title: bool = is_title_open
	_open_modal_base(not was_title)

	var hdr_hb := HBoxContainer.new()
	var t_lbl := _make_lbl("🔊  Mixer Audio Asli (5 Kanal)", 18, COL_INK)
	t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_hb.add_child(t_lbl)
	var cls_b := _make_btn("Selesai", COL_GREEN, Color.WHITE, COL_INK, 13, 34.0)
	cls_b.pressed.connect(func():
		if was_title:
			close_modal(false)
		else:
			show_pause_menu()
	)
	hdr_hb.add_child(cls_b)
	_modal_body.add_child(hdr_hb)

	if sfx == null:
		return

	var channels := [
		["Master Volume", sfx.master_volume, func(v: float): sfx.set_volumes(v, sfx.ui_volume, sfx.delivery_volume, sfx.ambience_volume, sfx.trucks_volume)],
		["Efek UI & Rambu", sfx.ui_volume, func(v: float): sfx.set_volumes(sfx.master_volume, v, sfx.delivery_volume, sfx.ambience_volume, sfx.trucks_volume)],
		["Ambience Kota", sfx.ambience_volume, func(v: float): sfx.set_volumes(sfx.master_volume, sfx.ui_volume, sfx.delivery_volume, v, sfx.trucks_volume)],
		["Truk, Kereta & Kapal", sfx.trucks_volume, func(v: float): sfx.set_volumes(sfx.master_volume, sfx.ui_volume, sfx.delivery_volume, sfx.ambience_volume, v)],
		["Koin Pengiriman", sfx.delivery_volume, func(v: float): sfx.set_volumes(sfx.master_volume, sfx.ui_volume, v, sfx.ambience_volume, sfx.trucks_volume)],
	]
	for ch_def in channels:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := _make_lbl(String(ch_def[0]), 13, COL_INK)
		l.custom_minimum_size = Vector2(145, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(ch_def[1])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pct := _make_lbl("%d%%" % int(round(sl.value * 100.0)), 12, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		pct.custom_minimum_size = Vector2(42, 0)
		var setter: Callable = ch_def[2]
		sl.value_changed.connect(func(val: float):
			setter.call(val)
			pct.text = "%d%%" % int(round(val * 100.0))
		)
		row.add_child(sl)
		row.add_child(pct)
		_modal_body.add_child(row)

	var coin_chk := CheckButton.new()
	coin_chk.text = "Bunyi Koin Saat Kargo Tiba (Delivery Ding)"
	coin_chk.button_pressed = sfx.money_popup_sound
	coin_chk.add_theme_font_override("font", _font)
	coin_chk.add_theme_color_override("font_color", COL_INK)
	coin_chk.toggled.connect(func(on: bool): sfx.money_popup_sound = on)
	_modal_body.add_child(coin_chk)

# === REGION OPEN / BOOMTOWN CELEBRATION POPUP (`RegionOpenPopup`) ===

func show_region_open_popup(info: Dictionary) -> void:
	if info.is_empty():
		return
	_open_modal_base(true)
	if sfx != null:
		sfx.play_ui("popup_row")

	var is_boom: bool = String(info.get("kind", "")) == "boom"
	var accent: Color = Color("D9480F") if is_boom else info.get("accent", COL_GREEN)
	var hdr_txt: String = ("🚀  BOOMTOWN LEVEL %d!" % int(info.get("boomLevel", 1))) if is_boom else ("🔓  WILAYAH BARU TERBUKA!")
	var sub_txt: String = (
		"Populasi tumbuh ke %s jiwa! Permintaan ekspor pasar naik +3/mnt." % String.num_int64(int(info.get("population", sim.town_population)))
		if is_boom else "%s — %s" % [String(info.get("name", "")), String(info.get("subtitle", ""))]
	)

	_modal_body.add_child(_make_lbl(hdr_txt, 20, accent, HORIZONTAL_ALIGNMENT_CENTER))
	_modal_body.add_child(_make_lbl(sub_txt, 14, COL_INK, HORIZONTAL_ALIGNMENT_CENTER, true))

	# "NEW" Commodity / Boosted Goods Cards with ShapeGlyphs!
	var goods_list: Array = info.get("boostedGoods" if is_boom else "newGoods", [])
	if not goods_list.is_empty():
		var g_hdr := _make_lbl("Komoditas Unggulan:" if is_boom else "Komoditas & Industri Baru:", 13, COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		_modal_body.add_child(g_hdr)
		var g_flow := HFlowContainer.new()
		g_flow.alignment = FlowContainer.ALIGNMENT_CENTER
		g_flow.add_theme_constant_override("h_separation", 8)
		g_flow.add_theme_constant_override("v_separation", 8)
		for g_item in goods_list:
			var gid := String(g_item)
			if not GameCatalog.GOODS.has(gid):
				continue
			var gdef: Dictionary = GameCatalog.GOODS[gid]
			var pill := PanelContainer.new()
			pill.add_theme_stylebox_override("panel", _style_box(COL_CARD_BG, accent, 2, 10, 8))
			var phb := HBoxContainer.new()
			phb.add_theme_constant_override("separation", 6)
			var g_icon := _GlyphBadgeControl.new()
			g_icon.good_id = gid
			g_icon.custom_minimum_size = Vector2(22, 22)
			phb.add_child(g_icon)
			var tag_prefix := "+3/mnt " if is_boom else "NEW · "
			phb.add_child(_make_lbl(tag_prefix + String(gdef.get("name", gid)), 12, COL_INK))
			pill.add_child(phb)
			g_flow.add_child(pill)
		_modal_body.add_child(g_flow)

	var facs_arr: Array = info.get("spawnedFacilities" if is_boom else "facilities", [])
	if not facs_arr.is_empty():
		var f_names: Array[String] = []
		for fi in range(mini(4, facs_arr.size())):
			f_names.append(String(facs_arr[fi].get("name", "Fasilitas")))
		var f_summary := "Fasilitas aktif: " + ", ".join(f_names)
		if facs_arr.size() > 4:
			f_summary += " (+%d lainnya)" % (facs_arr.size() - 4)
		_modal_body.add_child(_make_lbl(f_summary, 12, COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER, true))

	var ok_btn := _make_btn("✨  Lanjutkan Ekspansi!", accent, Color.WHITE, COL_INK, 15, 44.0)
	ok_btn.pressed.connect(func():
		var card_center: Vector2 = _modal_card.global_position + _modal_card.size * 0.5
		_spawn_homing_stars(card_center, Vector2(96.0, 32.0), 7, accent)
		close_modal(true)
	)
	_modal_body.add_child(ok_btn)

func _spawn_homing_stars(from_scr: Vector2, to_scr: Vector2, count: int, col: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(count):
		_homing_stars.append({
			"from": from_scr + Vector2(rng.randf_range(-36.0, 36.0), rng.randf_range(-16.0, 16.0)),
			"to": to_scr,
			"pos": from_scr,
			"arc": Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-110.0, -35.0)),
			"age": -float(i) * 0.05,
			"dur": 0.55 + float(i) * 0.04,
			"col": col.lightened(0.22)
		})

# === ROAD REROUTE PANEL (`RoadReroutePanel` on `road_built_triggered`) ===

func _on_road_built_triggered(info: Dictionary) -> void:
	show_road_reroute_panel(info)

func show_road_reroute_panel(info: Dictionary) -> void:
	if _reroute_card == null or sim == null:
		return
	var routes_arr: Array = info.get("routes", [])
	var off: Dictionary = info.get("offer", {})
	if routes_arr.is_empty() or off.is_empty():
		_reroute_card.visible = false
		return

	for ch in _reroute_vbox.get_children():
		ch.queue_free()
	_active_reroute_offer_id = String(off["id"])

	var top_hb := HBoxContainer.new()
	var ttl := _make_lbl("🛣  %s Dibuka!" % String(off.get("name", "Jalan Baru")), 14, COL_GREEN)
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hb.add_child(ttl)
	var x_btn := _make_btn("✕", COL_CARD_BG, COL_INK, COL_INK, 12, 28.0)
	x_btn.pressed.connect(func(): _reroute_card.visible = false)
	top_hb.add_child(x_btn)
	_reroute_vbox.add_child(top_hb)

	_reroute_vbox.add_child(_make_lbl("%d rute dapat melewati koridor baru ini:" % routes_arr.size(), 12, COL_MUTED))

	var show_n: int = mini(3, routes_arr.size())
	for i in range(show_n):
		var r_info: Dictionary = routes_arr[i]
		var rid := String(r_info["routeId"])
		var r_row := HBoxContainer.new()
		r_row.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(10, 18)
		swatch.color = r_info.get("color", COL_BLUE)
		r_row.add_child(swatch)

		var saved_s: float = float(r_info.get("savedSec", 0.0))
		var r_txt := String(r_info.get("name", rid))
		if bool(r_info.get("usesAlready", false)):
			r_txt += " (Otomatis)"
		elif saved_s >= 0.5:
			r_txt += " (-%.0f dtk)" % saved_s
		var rl := _make_lbl(r_txt, 12, COL_INK)
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rl.clip_text = true
		r_row.add_child(rl)

		var use_b := _make_btn("Lewatkan", COL_CARD_BG, COL_GREEN, COL_GREEN, 11, 28.0)
		use_b.disabled = bool(r_info.get("usesAlready", false))
		use_b.pressed.connect(func():
			if sim.reroute_over_offer(rid, _active_reroute_offer_id):
				use_b.text = "✓ Aktif"
				use_b.disabled = true
				toast_requested.emit("Rute dialihkan lewat " + String(off.get("name", "koridor baru")))
		)
		r_row.add_child(use_b)
		_reroute_vbox.add_child(r_row)

	var all_btn := _make_btn("⚡ Lewatkan Semua Rute (%d)" % routes_arr.size(), COL_GREEN, Color.WHITE, COL_INK, 13, 36.0)
	all_btn.pressed.connect(func():
		var n_ok: int = sim.reroute_all_over_offer(_active_reroute_offer_id)
		_reroute_card.visible = false
		toast_requested.emit("%d rute dialihkan ke %s!" % [n_ok, String(off.get("name", "jalan baru"))])
	)
	_reroute_vbox.add_child(all_btn)

	_reroute_card.visible = true
	_on_viewport_resized()


# === CUSTOM VECTOR WIDGETS (`LoadingRoundabout`, `CityPreview`, `GlyphBadge`, `HomingStars`) ===

class _LoadingRoundaboutWidget extends Control:
	## Authentic 18-truck orbiting 2-lane roundabout spinner (`loading_roundabout.gd`).
	var compact_emblem: bool = false
	var lht: bool = true
	var _phase: float = 0.0

	const PALETTE := [
		Color("E8590C"), Color("2B8A3E"), Color("1971C2"),
		Color("F08C00"), Color("9C36B5"), Color("C92A2A")
	]

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_phase = fmod(_phase + delta * 1.15, TAU)
			queue_redraw()

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r_outer: float = minf(size.x, size.y) * 0.44
		var r_island: float = r_outer * 0.42
		var dir_sign: float = 1.0 if lht else -1.0

		# Curb + 2-lane Asphalt Ring + Central Grass Island
		draw_circle(c, r_outer + (2.0 if compact_emblem else 4.0), Color("A9A59B"))
		draw_circle(c, r_outer, Color("3C3F4A"))
		draw_arc(c, (r_outer + r_island) * 0.5, 0.0, TAU, 28, Color("F2F0E5", 0.55), 1.2, true)
		draw_circle(c, r_island + 1.8, Color("E2DED2"))
		draw_circle(c, r_island, Color("8EB867"))

		var truck_count: int = 8 if compact_emblem else 18
		var cid: RID = get_canvas_item()
		for i in range(truck_count):
			var lane_outer: bool = (i % 2 == 0)
			var r_lane: float = lerpf(r_island, r_outer, 0.74 if lane_outer else 0.30)
			var spd_mul: float = 0.85 if lane_outer else 1.18
			var ang: float = float(i) * (TAU / float(truck_count)) + _phase * spd_mul * dir_sign
			var pos: Vector2 = c + Vector2(cos(ang), sin(ang)) * r_lane
			var heading: float = ang + (PI * 0.5 if lht else -PI * 0.5)
			var t_len: float = (5.5 if compact_emblem else 9.6)
			var t_w: float = (3.2 if compact_emblem else 5.2)
			var col: Color = PALETTE[i % PALETTE.size()]

			RenderingServer.canvas_item_add_set_transform(cid, Transform2D(heading, pos))
			draw_rect(Rect2(-t_len * 0.5 - 0.7, -t_w * 0.5 - 0.7, t_len + 1.4, t_w + 1.4), Color("1D2128"), true)
			draw_rect(Rect2(-t_len * 0.5, -t_w * 0.5, t_len * 0.62, t_w), Color("F6F5EF"), true)
			draw_rect(Rect2(t_len * 0.14, -t_w * 0.46, t_len * 0.36, t_w * 0.92), col, true)
		RenderingServer.canvas_item_add_set_transform(cid, Transform2D.IDENTITY)


class _CityPreviewMinimap extends Control:
	## Authentic vector minimap preview (`city_preview.gd`) rendering rivers, water, and roads of the selected preset!
	var _map_dict: Dictionary = {}

	func set_map_dict(md: Dictionary) -> void:
		_map_dict = md
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("EAE6DA"), true)
		draw_rect(r, Color("23242B"), false, 1.5)
		if _map_dict.is_empty():
			return

		var bw: Dictionary = _map_dict.get("boundsWorld", {"minX": -500, "maxX": 500, "minY": -400, "maxY": 400})
		var min_p := Vector2(float(bw.get("minX", -500.0)), float(bw.get("minY", -400.0)))
		var max_p := Vector2(float(bw.get("maxX", 500.0)), float(bw.get("maxY", 400.0)))
		var span: Vector2 = (max_p - min_p).max(Vector2(10.0, 10.0))
		var pad := Vector2(10.0, 10.0)
		var avail: Vector2 = (size - pad * 2.0).max(Vector2(20.0, 20.0))
		var sc: float = minf(avail.x / span.x, avail.y / span.y) * RoadGeom.UNIT_SCALE * 5.0
		# Compute true bounds directly from junctions for tight fit
		var j_list: Array = _map_dict.get("junctions", [])
		if not j_list.is_empty():
			var jmin := Vector2(INF, INF)
			var jmax := Vector2(-INF, -INF)
			for j in j_list:
				var jp := Vector2(float(j["x"]), float(j["y"]))
				jmin = jmin.min(jp)
				jmax = jmax.max(jp)
			min_p = jmin - Vector2(80, 80)
			max_p = jmax + Vector2(80, 80)
			span = (max_p - min_p).max(Vector2(10.0, 10.0))
			sc = minf(avail.x / span.x, avail.y / span.y)

		var ofs: Vector2 = (size - span * sc) * 0.5

		for rv in _map_dict.get("rivers", []):
			var rpts := PackedVector2Array()
			for pt in rv.get("points", []):
				rpts.append(ofs + (Vector2(float(pt[0]), float(pt[1])) - min_p) * sc)
			if rpts.size() >= 2:
				draw_polyline(rpts, Color("86B5C6"), 2.4, true)

		var j_pos_map: Dictionary = {}
		for j in j_list:
			j_pos_map[String(j["id"])] = ofs + (Vector2(float(j["x"]), float(j["y"])) - min_p) * sc

		for rd in _map_dict.get("roads", []):
			if not bool(rd.get("isBuilt", true)):
				continue
			var pts_raw: Array = rd.get("points", [])
			var dpts := PackedVector2Array()
			if pts_raw.size() >= 2:
				for pt in pts_raw:
					dpts.append(ofs + (Vector2(float(pt[0]), float(pt[1])) - min_p) * sc)
			else:
				var pa: Variant = j_pos_map.get(String(rd.get("from", "")), null)
				var pb: Variant = j_pos_map.get(String(rd.get("to", "")), null)
				if pa != null and pb != null:
					dpts.append(pa)
					dpts.append(pb)
			if dpts.size() >= 2:
				draw_polyline(dpts, Color("3C3F4A"), 1.5, true)

		for fac in _map_dict.get("facilities", []):
			var fp: Vector2 = ofs + (Vector2(float(fac["x"]), float(fac["y"])) - min_p) * sc
			draw_circle(fp, 2.3, Color("D9480F") if int(fac.get("regionIndex", 0)) == 0 else Color("2B8A3E"))


class _GlyphBadgeControl extends Control:
	var good_id: String = "dot"

	func _draw() -> void:
		if GameCatalog.GOODS.has(good_id):
			ShapeGlyphs.draw(self, good_id, size * 0.5, minf(size.x, size.y) * 0.78, 0.0, Color("1D2128"), 0.55)


class _OverlayStarsDrawer extends Control:
	var owner_ov: StageOverlays

	func _draw() -> void:
		if owner_ov == null or owner_ov._homing_stars.is_empty():
			return
		for st in owner_ov._homing_stars:
			if float(st["age"]) < 0.0:
				continue
			var p: Vector2 = st["pos"]
			var c: Color = st["col"]
			draw_circle(p, 7.5, Color(c.r, c.g, c.b, 0.35))
			draw_circle(p, 4.2, Color.WHITE)
