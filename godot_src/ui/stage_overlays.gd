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
var _active_modal_kind: String = ""
var _submodal_from_title: bool = false
var _confirm_return_kind: String = ""
var _renaming_slot_id: String = ""
var _renaming_slot_label: String = ""
var _backdrop_press_pos := Vector2(-9999.0, -9999.0)
var _last_kb_h: int = -1

# Root containers
var _broken_banner: PanelContainer
var _broken_lbl: Label
var _broken_target_pos := Vector2.ZERO
var _broken_route_id: String = ""

var _reroute_card: PanelContainer
var _reroute_vbox: VBoxContainer
var _active_reroute_offer_id: String = ""
var _reroute_has_data: bool = false

var _modal_backdrop: ColorRect
var _modal_center: CenterContainer
var _modal_card: PanelContainer
var _modal_body: VBoxContainer

var _title_root: Control
var _title_scroll: ScrollContainer
var _title_main_card: PanelContainer
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

static func make_scroll_touch_friendly(root_node: Node) -> void:
	if root_node == null:
		return
	for ch in root_node.get_children():
		if ch is Control and not (ch is ScrollContainer):
			var c := ch as Control
			if c is LineEdit or c is HSlider or c is VSlider:
				pass
			elif c is BaseButton or c is PanelContainer or c is BoxContainer or c is GridContainer or c is FlowContainer or c is MarginContainer:
				c.mouse_filter = Control.MOUSE_FILTER_PASS
			elif c is Label or c is ColorRect or c is ProgressBar or c is HSeparator or c is VSeparator or c is TextureRect:
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		make_scroll_touch_friendly(ch)

static func _detach_and_free_children(box: Node) -> void:
	if box == null:
		return
	for i in range(box.get_child_count() - 1, -1, -1):
		var ch := box.get_child(i)
		box.remove_child(ch)
		ch.queue_free()

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

func is_loading_open() -> bool:
	return _loading_layer != null and _loading_layer.visible

func is_new_game_subpanel_open() -> bool:
	return is_title_open and _title_subpanel != null and _title_subpanel.visible

func close_new_game_subpanel() -> void:
	if _title_subpanel != null:
		_title_subpanel.visible = false

func close_reroute_panel() -> bool:
	if _reroute_has_data:
		_reroute_has_data = false
		if _reroute_card != null:
			_reroute_card.visible = false
		return true
	return false

func is_screen_point_over_overlay(pt: Vector2) -> bool:
	if is_title_open or is_modal_open or is_loading_open():
		return true
	if _broken_banner != null and _broken_banner.visible and _broken_banner.get_global_rect().has_point(pt):
		return true
	if _reroute_card != null and _reroute_card.visible and _reroute_card.get_global_rect().has_point(pt):
		return true
	return false

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

func _make_btn(txt: String, bg: Color = COL_PARCHMENT, fg: Color = COL_INK, border: Color = COL_INK, font_sz: int = 15, min_h: float = 44.0) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(42.0 if txt.length() <= 2 else 0.0, maxf(40.0, min_h))
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
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _style_line_edit(le: LineEdit, sz: int = 14) -> void:
	le.custom_minimum_size = Vector2(0, 42)
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
	_broken_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_broken_lbl.clip_text = true
	hb.add_child(_broken_lbl)
	var show_btn := _make_btn("Tampilkan", COL_RED, Color.WHITE, COL_INK, 12, 40.0)
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
	_reroute_card.custom_minimum_size = Vector2(300, 0)
	_reroute_card.add_theme_stylebox_override("panel", _style_box(COL_PARCHMENT, COL_GREEN, 2, 14, 12))
	_reroute_vbox = VBoxContainer.new()
	_reroute_vbox.add_theme_constant_override("separation", 6)
	_reroute_card.add_child(_reroute_vbox)
	add_child(_reroute_card)

func _build_modal_shell() -> void:
	_modal_backdrop = ColorRect.new()
	_modal_backdrop.visible = false
	_modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_backdrop.color = Color(0.08, 0.10, 0.14, 0.62)
	_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.gui_input.connect(_on_modal_scrim_gui_input)
	add_child(_modal_backdrop)

	_modal_center = CenterContainer.new()
	_modal_center.visible = false
	_modal_center.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_center.gui_input.connect(_on_modal_scrim_gui_input)
	add_child(_modal_center)

	_modal_card = PanelContainer.new()
	_modal_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_card.custom_minimum_size = Vector2(420, 0)
	_modal_card.add_theme_stylebox_override("panel", _style_box(COL_PARCHMENT, COL_INK, 3, 16, 18))
	_modal_body = VBoxContainer.new()
	_modal_body.add_theme_constant_override("separation", 10)
	_modal_card.add_child(_modal_body)
	_modal_center.add_child(_modal_card)

func _on_modal_scrim_gui_input(event: InputEvent) -> void:
	if not is_modal_open:
		return
	if event is InputEventScreenTouch:
		_modal_center.accept_event()
		var st := event as InputEventScreenTouch
		if st.pressed:
			_backdrop_press_pos = st.position
		elif st.position.distance_to(_backdrop_press_pos) <= 22.0:
			_backdrop_press_pos = Vector2(-9999.0, -9999.0)
			if _modal_card == null or not _modal_card.get_global_rect().has_point(st.position):
				_on_modal_scrim_tapped()
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		_modal_center.accept_event()
	elif event is InputEventMouseButton:
		_modal_center.accept_event()
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_backdrop_press_pos = mb.position
			elif mb.position.distance_to(_backdrop_press_pos) <= 22.0:
				_backdrop_press_pos = Vector2(-9999.0, -9999.0)
				if _modal_card == null or not _modal_card.get_global_rect().has_point(mb.position):
					_on_modal_scrim_tapped()

func _on_modal_scrim_tapped() -> void:
	if not is_modal_open:
		return
	if _active_modal_kind == "region_open" and _modal_card != null:
		var card_center: Vector2 = _modal_card.global_position + _modal_card.size * 0.5
		_spawn_homing_stars(card_center, Vector2(96.0, 32.0), 7, COL_GREEN)
		close_modal(true)
		return
	close_modal(not is_title_open)

func _build_title_stage() -> void:
	_title_root = Control.new()
	_title_root.visible = false
	_title_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_title_root)

	var shade := ColorRect.new()
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.color = Color(0.10, 0.12, 0.16, 0.36)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_root.add_child(shade)

	var margin := MarginContainer.new()
	margin.name = "TitleMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_title_root.add_child(margin)

	_title_scroll = ScrollContainer.new()
	_title_scroll.name = "TitleScroll"
	_title_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_title_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_title_scroll)

	var t_center := CenterContainer.new()
	t_center.name = "TitleCenter"
	t_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t_center.mouse_filter = Control.MOUSE_FILTER_PASS
	_title_scroll.add_child(t_center)

	var flow := BoxContainer.new()
	flow.name = "TitleFlow"
	flow.add_theme_constant_override("separation", 18)
	t_center.add_child(flow)

	# Left / Top Main Title Card
	_title_main_card = PanelContainer.new()
	_title_main_card.custom_minimum_size = Vector2(320, 0)
	_title_main_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_main_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_main_card.add_theme_stylebox_override("panel", _style_box(COL_PARCHMENT, COL_INK, 3, 18, 20))
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)

	# Mini animated roundabout emblem + Title
	var hdr_hb := HBoxContainer.new()
	hdr_hb.add_theme_constant_override("separation", 12)
	var mini_rb := _LoadingRoundaboutWidget.new()
	mini_rb.compact_emblem = true
	mini_rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	var quit_btn := _make_btn("✕  Keluar", COL_PARCHMENT, COL_RED, COL_RED, 14, 42.0)
	quit_btn.pressed.connect(func():
		if sim != null:
			sim.save_to_disk()
		if sfx != null:
			sfx.shutdown()
		get_tree().quit()
	)
	mv.add_child(quit_btn)

	_title_main_card.add_child(mv)
	flow.add_child(_title_main_card)

	# Right / Bottom Subpanel (New Game Map Selector + `CityPreview` Minimap + `CityCode`)
	_title_subpanel = PanelContainer.new()
	_title_subpanel.visible = false
	_title_subpanel.custom_minimum_size = Vector2(320, 0)
	_title_subpanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_subpanel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_subpanel.add_theme_stylebox_override("panel", _style_box(COL_PARCHMENT, COL_INK, 3, 18, 16))
	_title_sub_vbox = VBoxContainer.new()
	_title_sub_vbox.add_theme_constant_override("separation", 8)
	_title_subpanel.add_child(_title_sub_vbox)
	flow.add_child(_title_subpanel)
	make_scroll_touch_friendly(_title_scroll)

func _build_loading_roundabout() -> void:
	_loading_layer = ColorRect.new()
	_loading_layer.visible = false
	_loading_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_layer.color = Color("1A1D24")
	_loading_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_layer.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch or ev is InputEventScreenDrag or ev is InputEventMouseButton:
			_loading_layer.accept_event()
	)
	add_child(_loading_layer)

	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(cc)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	_loading_roundabout = _LoadingRoundaboutWidget.new()
	_loading_roundabout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_roundabout.custom_minimum_size = Vector2(168, 168)
	vb.add_child(_loading_roundabout)
	_loading_lbl = _make_lbl("Memuat Jaringan Jalan Karesidenan...", 16, COL_PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_loading_lbl)
	cc.add_child(vb)

func _compute_safe_margins(vp: Vector2) -> Vector4:
	var pad_l: float = 14.0
	var pad_t: float = 12.0
	var pad_r: float = 14.0
	var pad_b: float = 14.0
	if OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var win: Vector2i = DisplayServer.window_get_size()
		if win.x > 0 and win.y > 0 and safe.size.x > 0:
			var sx: float = vp.x / float(win.x)
			var sy: float = vp.y / float(win.y)
			pad_l = maxf(12.0, float(safe.position.x) * sx)
			pad_t = maxf(10.0, float(safe.position.y) * sy)
			pad_r = maxf(12.0, float(win.x - safe.end.x) * sx)
			pad_b = maxf(12.0, float(win.y - safe.end.y) * sy)
	return Vector4(pad_l, pad_t, pad_r, pad_b)

func _on_viewport_resized() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	var is_portrait: bool = vp.y > vp.x
	var pads: Vector4 = _compute_safe_margins(vp)
	var pad_l: float = pads.x
	var pad_t: float = pads.y
	var pad_r: float = pads.z
	var pad_b: float = pads.w
	var kb_px: float = 0.0
	if OS.has_feature("mobile"):
		var win_h: int = maxi(1, DisplayServer.window_get_size().y)
		kb_px = float(DisplayServer.virtual_keyboard_get_height()) * (vp.y / float(win_h))

	if _title_root != null:
		var margin := _title_root.get_node_or_null("TitleMargin") as MarginContainer
		if margin != null:
			margin.add_theme_constant_override("margin_left", int(round(maxf(14.0, pad_l))))
			margin.add_theme_constant_override("margin_right", int(round(maxf(14.0, pad_r))))
			margin.add_theme_constant_override("margin_top", int(round(maxf(14.0, pad_t))))
			margin.add_theme_constant_override("margin_bottom", int(round(maxf(14.0, pad_b + kb_px))))
		var flow := _title_root.get_node_or_null("TitleMargin/TitleScroll/TitleCenter/TitleFlow") as BoxContainer
		if flow != null:
			flow.vertical = is_portrait
			flow.alignment = BoxContainer.ALIGNMENT_CENTER
		var avail_title_w: float = maxf(280.0, vp.x - maxf(28.0, pad_l + pad_r) - 12.0)
		if _title_main_card != null:
			_title_main_card.custom_minimum_size = Vector2(minf(360.0, avail_title_w), 0)
		if _title_subpanel != null:
			_title_subpanel.custom_minimum_size = Vector2(minf(390.0 if not is_portrait else 420.0, avail_title_w), 0)

	if _modal_center != null:
		_modal_center.offset_bottom = -kb_px
	if _modal_card != null:
		var target_w: float = clampf(vp.x - pad_l - pad_r - 12.0, 290.0, 500.0)
		_modal_card.custom_minimum_size = Vector2(target_w, 0)

	_layout_floating_cards(vp, is_portrait, pad_l, pad_t, pad_r, pad_b)

func _layout_floating_cards(vp: Vector2, is_portrait: bool, pad_l: float, pad_t: float, pad_r: float, pad_b: float) -> void:
	if _broken_banner != null:
		_broken_banner.reset_size()
		var b_min: Vector2 = _broken_banner.get_combined_minimum_size()
		var bw: float = clampf(b_min.x, 220.0, vp.x - pad_l - pad_r - 8.0)
		var by: float = (pad_t + 96.0) if is_portrait else (pad_t + 54.0)
		_broken_banner.size = Vector2(bw, maxf(46.0, b_min.y))
		_broken_banner.position = Vector2((vp.x - bw) * 0.5, by)

	if _reroute_card != null:
		var rw: float = minf(vp.x - pad_l - pad_r - 8.0, 340.0)
		_reroute_card.custom_minimum_size = Vector2(rw, 0)
		_reroute_card.reset_size()
		var r_sz: Vector2 = _reroute_card.get_combined_minimum_size()
		var rh: float = maxf(110.0, r_sz.y)
		var bottom_hud_clearance: float = (pad_b + 106.0) if is_portrait else (pad_b + 60.0)
		var ry: float = clampf(vp.y - bottom_hud_clearance - rh, pad_t + 62.0, maxf(pad_t + 62.0, vp.y - pad_b - rh - 4.0))
		var rx: float = (vp.x - rw) * 0.5 if is_portrait else (vp.x - pad_r - rw - 4.0)
		_reroute_card.position = Vector2(rx, ry)
		_reroute_card.size = Vector2(rw, rh)

func _is_hud_blocking_floating_cards() -> bool:
	if hud == null:
		return false
	if hud.has_method("is_modal_open") and bool(hud.call("is_modal_open")):
		return true
	if hud.has_method("is_inspector_open") and bool(hud.call("is_inspector_open")):
		return true
	return false

func _process(delta: float) -> void:
	if sim == null:
		return

	if OS.has_feature("mobile"):
		var kb_now: int = DisplayServer.virtual_keyboard_get_height()
		if kb_now != _last_kb_h:
			_last_kb_h = kb_now
			_on_viewport_resized()

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

	# Sync `RoadReroutePanel` & `BrokenRouteBanner` visibility so Layer 24 never collides over HUD modals/drawers
	if _reroute_card != null:
		var allow_reroute: bool = _reroute_has_data and not is_title_open and not is_modal_open and not is_loading_open() and not _is_hud_blocking_floating_cards()
		if _reroute_card.visible != allow_reroute:
			_reroute_card.visible = allow_reroute
			if allow_reroute:
				_on_viewport_resized()

	_update_broken_route_banner()

func _update_broken_route_banner() -> void:
	if _broken_banner == null or sim == null:
		return
	if is_title_open or is_modal_open or is_loading_open() or _is_hud_blocking_floating_cards():
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
	var new_txt := "⚠ %d Rute Terputus (%s)" % [broken_cnt, tag]
	var was_vis: bool = _broken_banner.visible
	if _broken_lbl.text != new_txt:
		_broken_lbl.text = new_txt
	_broken_banner.visible = true
	if not was_vis:
		_on_viewport_resized()

# === TITLE STAGE & LOADING TRANSITION ===

func show_title_stage() -> void:
	close_modal(false)
	_reroute_has_data = false
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
	_detach_and_free_children(_title_sub_vbox)
	_title_subpanel.visible = true
	_newgame_selected_map = sim.current_map_id
	_newgame_lht = sim.left_hand_traffic

	var top_hb := HBoxContainer.new()
	top_hb.add_theme_constant_override("separation", 8)
	var hdr := _make_lbl("Pilih Peta Wilayah atau Kode Kota", 15, COL_INK)
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.clip_text = true
	top_hb.add_child(hdr)
	var cls_b := _make_btn("✕", COL_CARD_BG, COL_INK, COL_INK, 14, 42.0)
	cls_b.pressed.connect(func(): _title_subpanel.visible = false)
	top_hb.add_child(cls_b)
	_title_sub_vbox.add_child(top_hb)

	# Map selector buttons in touch-scrollable ScrollContainer
	var map_scroll := ScrollContainer.new()
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_scroll.custom_minimum_size = Vector2(0, 128)
	var map_vb := VBoxContainer.new()
	map_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_vb.add_theme_constant_override("separation", 6)
	var map_btns: Dictionary = {}
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
			42.0
		)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.clip_text = true
		map_btns[mid] = mb
		var captured_i: int = i
		mb.pressed.connect(func():
			_newgame_selected_map = mid
			for k_id in map_btns.keys():
				var btn_ref: Button = map_btns[k_id]
				var active_now: bool = (String(k_id) == _newgame_selected_map)
				var bg_c: Color = COL_GREEN if active_now else COL_CARD_BG
				var fg_c: Color = Color.WHITE if active_now else COL_INK
				btn_ref.add_theme_color_override("font_color", fg_c)
				btn_ref.add_theme_color_override("font_hover_color", fg_c)
				btn_ref.add_theme_color_override("font_pressed_color", fg_c)
				btn_ref.add_theme_stylebox_override("normal", _style_box(bg_c, COL_INK, 2, 10, 12))
				btn_ref.add_theme_stylebox_override("hover", _style_box(bg_c.lightened(0.06), COL_INK, 2, 10, 12))
				btn_ref.add_theme_stylebox_override("pressed", _style_box(bg_c.darkened(0.08), COL_INK, 2, 10, 12))
			if _preview_drawer != null:
				_preview_drawer.set_map_dict(sim.maps_list[captured_i])
			_update_newgame_code_field()
		)
		map_vb.add_child(mb)
	map_scroll.add_child(map_vb)
	make_scroll_touch_friendly(map_scroll)
	_title_sub_vbox.add_child(map_scroll)

	# Authentic `CityPreview` Vector Minimap!
	_preview_drawer = _CityPreviewMinimap.new()
	_preview_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_drawer.custom_minimum_size = Vector2(0, 110)
	for m_init in sim.maps_list:
		if String(m_init["id"]) == _newgame_selected_map:
			_preview_drawer.set_map_dict(m_init)
			break
	_title_sub_vbox.add_child(_preview_drawer)

	# LHT / RHT toggle + `CityCode` input
	var rule_hb := HBoxContainer.new()
	rule_hb.add_theme_constant_override("separation", 8)
	var lht_btn := _make_btn("Lajur Kiri (ID)" if _newgame_lht else "Lajur Kanan (RHT)", COL_CARD_BG, COL_INK, COL_INK, 12, 42.0)
	lht_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lht_btn.clip_text = true
	lht_btn.pressed.connect(func():
		_newgame_lht = not _newgame_lht
		lht_btn.text = "Lajur Kiri (ID)" if _newgame_lht else "Lajur Kanan (RHT)"
		_update_newgame_code_field()
	)
	rule_hb.add_child(lht_btn)

	var rnd_btn := _make_btn("🎲 Acak", COL_CARD_BG, COL_INK, COL_INK, 12, 42.0)
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

	var start_btn := _make_btn("🚀  Mulai Permainan Baru ($500)", COL_GREEN, Color.WHITE, COL_INK, 15, 46.0)
	start_btn.clip_text = true
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
	make_scroll_touch_friendly(_title_scroll)
	_on_viewport_resized()

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

# === PAUSE MENU, MULTI-SLOT SAVE/LOAD, CONFIRMATION & 5-CHANNEL AUDIO ===

func _open_modal_base(pause_sim: bool = true, modal_kind: String = "modal") -> void:
	_detach_and_free_children(_modal_body)
	if pause_sim and not is_modal_open and sim != null:
		_saved_speed_before_pause = sim.speed_multiplier
		sim.speed_multiplier = 0
	is_modal_open = true
	_active_modal_kind = modal_kind
	_backdrop_press_pos = Vector2(-9999.0, -9999.0)
	_modal_backdrop.visible = true
	_modal_center.visible = true
	_broken_banner.visible = false
	if camera != null:
		camera.reset_touch_state()
		camera.clear_double_tap()
	if sfx != null:
		sfx.play_ui("panel_open")
	_on_viewport_resized()

func close_modal(resume_sim: bool = true) -> void:
	if not is_modal_open:
		return
	is_modal_open = false
	_active_modal_kind = ""
	_renaming_slot_id = ""
	_backdrop_press_pos = Vector2(-9999.0, -9999.0)
	_modal_backdrop.visible = false
	_modal_center.visible = false
	if camera != null:
		camera.reset_touch_state()
		camera.clear_double_tap()
	if resume_sim and sim != null and not is_title_open:
		sim.speed_multiplier = _saved_speed_before_pause if _saved_speed_before_pause > 0 else 1
	if sfx != null:
		sfx.play_ui("panel_close")

func handle_modal_back() -> bool:
	if not is_modal_open:
		return false
	match _active_modal_kind:
		"confirm":
			if _confirm_return_kind == "pause":
				show_pause_menu()
			elif _confirm_return_kind == "saveload":
				show_save_load_menu(_submodal_from_title)
			else:
				close_modal(not is_title_open)
		"saveload":
			if _renaming_slot_id != "":
				_renaming_slot_id = ""
				show_save_load_menu(_submodal_from_title)
			elif _submodal_from_title:
				close_modal(false)
			else:
				show_pause_menu()
		"audio":
			if _submodal_from_title:
				close_modal(false)
			else:
				show_pause_menu()
		"region_open":
			if _modal_card != null:
				var card_center: Vector2 = _modal_card.global_position + _modal_card.size * 0.5
				_spawn_homing_stars(card_center, Vector2(96.0, 32.0), 7, COL_GREEN)
			close_modal(true)
		_:
			close_modal(not is_title_open)
	return true

func show_confirm_modal(title_txt: String, body_txt: String, confirm_lbl: String, on_confirm: Callable, return_modal_kind: String = "") -> void:
	_confirm_return_kind = return_modal_kind
	_open_modal_base(not is_title_open, "confirm")

	_modal_body.add_child(_make_lbl("⚠  " + title_txt, 18, COL_RED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_modal_body.add_child(_make_lbl(body_txt, 14, COL_INK, HORIZONTAL_ALIGNMENT_LEFT, true))

	var act_hb := HBoxContainer.new()
	act_hb.add_theme_constant_override("separation", 10)
	var cancel_b := _make_btn("Batal", COL_CARD_BG, COL_INK, COL_INK, 14, 44.0)
	cancel_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_b.pressed.connect(func():
		handle_modal_back()
	)
	act_hb.add_child(cancel_b)

	var ok_b := _make_btn(confirm_lbl, COL_RED, Color.WHITE, COL_INK, 14, 44.0)
	ok_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok_b.clip_text = true
	ok_b.pressed.connect(func():
		var should_resume: bool = (return_modal_kind == "" and not is_title_open)
		close_modal(should_resume)
		if on_confirm.is_valid():
			on_confirm.call()
	)
	act_hb.add_child(ok_b)
	_modal_body.add_child(act_hb)

func show_pause_menu() -> void:
	_open_modal_base(true, "pause")
	_refresh_city_code_from_sim()

	var hdr_hb := HBoxContainer.new()
	hdr_hb.add_theme_constant_override("separation", 8)
	var t_lbl := _make_lbl("⏸  Menu Jeda (Paused)", 19, COL_INK)
	t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_lbl.clip_text = true
	hdr_hb.add_child(t_lbl)
	var resume_top := _make_btn("▶ Lanjut", COL_GREEN, Color.WHITE, COL_INK, 14, 42.0)
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
	cc_lbl.clip_text = true
	cc_hb.add_child(cc_lbl)
	var cp_btn := _make_btn("Salin Kode", COL_CARD_BG, COL_INK, COL_INK, 12, 42.0)
	cp_btn.pressed.connect(func():
		DisplayServer.clipboard_set(sim.current_city_code)
		toast_requested.emit("CityCode disalin: " + sim.current_city_code)
	)
	cc_hb.add_child(cp_btn)
	_modal_body.add_child(cc_hb)

	var save_mgr_btn := _make_btn("💾  Simpan / Muat Slot Permainan", COL_BLUE, Color.WHITE, COL_INK, 15, 44.0)
	save_mgr_btn.clip_text = true
	save_mgr_btn.pressed.connect(func():
		_renaming_slot_id = ""
		show_save_load_menu(false)
	)
	_modal_body.add_child(save_mgr_btn)

	var audio_btn := _make_btn("🔊  Pengaturan Audio 5-Kanal", COL_CARD_BG, COL_INK, COL_INK, 15, 44.0)
	audio_btn.clip_text = true
	audio_btn.pressed.connect(func(): show_audio_options_modal())
	_modal_body.add_child(audio_btn)

	var reset_btn := _make_btn("↺  Ulangi Kota Ini dari Awal ($500)", COL_CARD_BG, COL_AMBER, COL_AMBER, 14, 44.0)
	reset_btn.clip_text = true
	reset_btn.pressed.connect(func():
		var map_nm := String(sim.map_def.get("name", "Kota"))
		show_confirm_modal(
			"Ulangi %s?" % map_nm,
			"Seluruh rute, armada truk, dan progres pada peta %s akan direset kembali ke modal awal $500." % map_nm,
			"Ya, Ulangi ($500)",
			func():
				play_loading_transition("Mengatur ulang %s..." % map_nm, func():
					sim.reset_current_map()
					sim.speed_multiplier = 1
					if camera != null:
						camera.focus_map(sim.map_def["initialView"], sim.map_def["boundsWorld"])
				),
			"pause"
		)
	)
	_modal_body.add_child(reset_btn)

	var title_btn := _make_btn("🏠  Kembali ke Layar Judul (Title Stage)", COL_CARD_BG, COL_INK, COL_INK, 14, 44.0)
	title_btn.clip_text = true
	title_btn.pressed.connect(func():
		if camera != null and not camera.title_orbit_active and not camera.cinematic_locked:
			sim.camera_meta = camera.export_camera_meta()
		sim.save_to_disk()
		show_title_stage()
	)
	_modal_body.add_child(title_btn)

func show_save_load_menu(from_title: bool = false) -> void:
	_submodal_from_title = from_title
	_open_modal_base(not from_title, "saveload")

	var hdr_hb := HBoxContainer.new()
	hdr_hb.add_theme_constant_override("separation", 8)
	var t_lbl := _make_lbl("💾  Manajer Simpanan (RunSave v4)", 17, COL_INK)
	t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_lbl.clip_text = true
	hdr_hb.add_child(t_lbl)
	var back_b := _make_btn("Tutup" if from_title else "← Kembali", COL_CARD_BG, COL_INK, COL_INK, 13, 42.0)
	back_b.pressed.connect(func():
		_renaming_slot_id = ""
		if from_title:
			close_modal(false)
		else:
			show_pause_menu()
	)
	hdr_hb.add_child(back_b)
	_modal_body.add_child(hdr_hb)

	# Save New Slot row (when in active game, kept OUTSIDE ScrollContainer so drag-scroll never hits LineEdit)
	if not from_title:
		var new_hb := HBoxContainer.new()
		new_hb.add_theme_constant_override("separation", 6)
		var slot_in := LineEdit.new()
		slot_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_in.placeholder_text = "Nama simpanan baru..."
		slot_in.text = "%s - %s" % [String(sim.map_def.get("name", "Madiun")), GameCatalog.fmt_cash(sim.cash)]
		_style_line_edit(slot_in, 13)
		new_hb.add_child(slot_in)
		var sv_btn := _make_btn("+ Simpan", COL_GREEN, Color.WHITE, COL_INK, 13, 42.0)
		sv_btn.pressed.connect(func():
			if camera != null and not camera.title_orbit_active and not camera.cinematic_locked:
				sim.camera_meta = camera.export_camera_meta()
			var nm: String = slot_in.text.strip_edges()
			if nm == "":
				nm = "Slot Karesidenan"
			if sim.save_named_slot(nm):
				_renaming_slot_id = ""
				toast_requested.emit("Tersimpan: " + nm)
				show_save_load_menu(false)
		)
		new_hb.add_child(sv_btn)
		_modal_body.add_child(new_hb)

	# Dedicated Rename Bar (kept OUTSIDE ScrollContainer when renaming a specific slot)
	if _renaming_slot_id != "":
		var rn_bar := PanelContainer.new()
		rn_bar.add_theme_stylebox_override("panel", _style_box(COL_CARD_BG, COL_BLUE, 2, 10, 8))
		var rn_hb := HBoxContainer.new()
		rn_hb.add_theme_constant_override("separation", 6)
		var rn_edit := LineEdit.new()
		rn_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rn_edit.text = _renaming_slot_label
		rn_edit.placeholder_text = "Nama slot..."
		_style_line_edit(rn_edit, 13)
		rn_hb.add_child(rn_edit)
		var rn_save := _make_btn("Simpan", COL_BLUE, Color.WHITE, COL_INK, 12, 42.0)
		var target_sid := _renaming_slot_id
		rn_save.pressed.connect(func():
			var nn := rn_edit.text.strip_edges()
			if nn != "" and sim.rename_save_slot(target_sid, nn):
				toast_requested.emit("Nama slot diperbarui: " + nn)
			_renaming_slot_id = ""
			show_save_load_menu(from_title)
		)
		rn_hb.add_child(rn_save)
		var rn_cancel := _make_btn("Batal", COL_PARCHMENT, COL_INK, COL_INK, 12, 42.0)
		rn_cancel.pressed.connect(func():
			_renaming_slot_id = ""
			show_save_load_menu(from_title)
		)
		rn_hb.add_child(rn_cancel)
		rn_bar.add_child(rn_hb)
		_modal_body.add_child(rn_bar)

	var slots: Array[Dictionary] = sim.list_save_slots()
	var vp_h: float = get_viewport().get_visible_rect().size.y
	var kb_h: float = 0.0
	if OS.has_feature("mobile"):
		var win_h: int = maxi(1, DisplayServer.window_get_size().y)
		kb_h = float(DisplayServer.virtual_keyboard_get_height()) * (vp_h / float(win_h))
	var chrome_h: float = 190.0 + (56.0 if not from_title else 0.0) + (64.0 if _renaming_slot_id != "" else 0.0)
	var sc_h: float = clampf(vp_h - kb_h - chrome_h, 120.0, 260.0)

	var sc := ScrollContainer.new()
	sc.name = "SaveSlotsScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, sc_h)
	var sl_vb := VBoxContainer.new()
	sl_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl_vb.add_theme_constant_override("separation", 8)

	if slots.is_empty():
		sl_vb.add_child(_make_lbl("Belum ada berkas simpanan. Buat simpanan baru di atas!", 13, COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER, true))
	else:
		for sl in slots:
			var sid := String(sl["slotId"])
			var slot_lbl := String(sl.get("label", sid))
			var row_p := PanelContainer.new()
			row_p.add_theme_stylebox_override("panel", _style_box(COL_CARD_BG, COL_BLUE if _renaming_slot_id == sid else COL_INK, 1, 10, 10))
			var rvb := VBoxContainer.new()
			rvb.add_theme_constant_override("separation", 5)

			var nm_lbl := _make_lbl(slot_lbl, 15, COL_INK)
			nm_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm_lbl.clip_text = true
			rvb.add_child(nm_lbl)

			var meta_s := "%s · Kas %s · Boom Lv.%d · v%d" % [
				String(sl.get("mapName", sl.get("mapId", ""))),
				GameCatalog.fmt_cash(int(sl.get("cash", 0))),
				int(sl.get("boomLevel", 0)),
				int(sl.get("version", 4))
			]
			var meta_lbl := _make_lbl(meta_s, 11, COL_MUTED)
			meta_lbl.clip_text = true
			rvb.add_child(meta_lbl)

			var act_hb := HBoxContainer.new()
			act_hb.add_theme_constant_override("separation", 6)
			var ld_b := _make_btn("Muat", COL_GREEN, Color.WHITE, COL_INK, 13, 42.0)
			ld_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ld_b.pressed.connect(func():
				close_modal(false)
				play_loading_transition("Memuat %s..." % slot_lbl, func():
					if sim.load_named_slot(sid):
						if camera != null:
							camera.focus_map(sim.map_def["initialView"], sim.map_def["boundsWorld"])
							camera.apply_camera_meta(sim.camera_meta)
						sim.speed_multiplier = 1
						hide_title_stage()
						toast_requested.emit("Simpanan dimuat: " + slot_lbl)
				)
			)
			act_hb.add_child(ld_b)

			var rn_b := _make_btn("Ubah Nama", COL_PARCHMENT, COL_INK, COL_INK, 12, 42.0)
			rn_b.pressed.connect(func():
				_renaming_slot_id = sid
				_renaming_slot_label = slot_lbl
				show_save_load_menu(from_title)
			)
			act_hb.add_child(rn_b)

			var dl_b := _make_btn("Hapus", COL_PARCHMENT, COL_RED, COL_RED, 12, 42.0)
			dl_b.pressed.connect(func():
				show_confirm_modal(
					"Hapus Simpanan?",
					"Hapus berkas simpanan '%s' secara permanen?" % slot_lbl,
					"Hapus Slot",
					func():
						sim.delete_save_slot(sid)
						show_save_load_menu(from_title),
					"saveload"
				)
			)
			act_hb.add_child(dl_b)

			rvb.add_child(act_hb)
			row_p.add_child(rvb)
			sl_vb.add_child(row_p)

	sc.add_child(sl_vb)
	make_scroll_touch_friendly(sc)
	_modal_body.add_child(sc)

func show_audio_options_modal() -> void:
	var was_title: bool = is_title_open
	_submodal_from_title = was_title
	_open_modal_base(not was_title, "audio")

	var hdr_hb := HBoxContainer.new()
	hdr_hb.add_theme_constant_override("separation", 8)
	var t_lbl := _make_lbl("🔊  Mixer Audio Asli (5 Kanal)", 17, COL_INK)
	t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_lbl.clip_text = true
	hdr_hb.add_child(t_lbl)
	var cls_b := _make_btn("Selesai", COL_GREEN, Color.WHITE, COL_INK, 13, 42.0)
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
		["Truk & Kereta", sfx.trucks_volume, func(v: float): sfx.set_volumes(sfx.master_volume, sfx.ui_volume, sfx.delivery_volume, sfx.ambience_volume, v)],
		["Koin Pengiriman", sfx.delivery_volume, func(v: float): sfx.set_volumes(sfx.master_volume, sfx.ui_volume, v, sfx.ambience_volume, sfx.trucks_volume)],
	]
	for ch_def in channels:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := _make_lbl(String(ch_def[0]), 13, COL_INK)
		l.custom_minimum_size = Vector2(118, 0)
		l.clip_text = true
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(ch_def[1])
		sl.custom_minimum_size = Vector2(80, 38)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pct := _make_lbl("%d%%" % int(round(sl.value * 100.0)), 12, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		pct.custom_minimum_size = Vector2(40, 0)
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
	coin_chk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coin_chk.custom_minimum_size = Vector2(0, 44)
	coin_chk.button_pressed = sfx.money_popup_sound
	coin_chk.add_theme_font_override("font", _font)
	coin_chk.add_theme_font_size_override("font_size", 13)
	coin_chk.add_theme_color_override("font_color", COL_INK)
	coin_chk.toggled.connect(func(on: bool): sfx.money_popup_sound = on)
	_modal_body.add_child(coin_chk)

# === REGION OPEN / BOOMTOWN CELEBRATION POPUP (`RegionOpenPopup`) ===

func show_region_open_popup(info: Dictionary) -> void:
	if info.is_empty():
		return
	_open_modal_base(true, "region_open")
	if sfx != null:
		sfx.play_ui("popup_row")

	var is_boom: bool = String(info.get("kind", "")) == "boom"
	var accent: Color = Color("D9480F") if is_boom else info.get("accent", COL_GREEN)
	var hdr_txt: String = ("🚀  BOOMTOWN LEVEL %d!" % int(info.get("boomLevel", 1))) if is_boom else ("🔓  WILAYAH BARU TERBUKA!")
	var sub_txt: String = (
		"Populasi tumbuh ke %s jiwa! Permintaan ekspor pasar naik +3/mnt." % String.num_int64(int(info.get("population", sim.town_population)))
		if is_boom else "%s — %s" % [String(info.get("name", "")), String(info.get("subtitle", ""))]
	)

	_modal_body.add_child(_make_lbl(hdr_txt, 20, accent, HORIZONTAL_ALIGNMENT_CENTER, true))
	_modal_body.add_child(_make_lbl(sub_txt, 14, COL_INK, HORIZONTAL_ALIGNMENT_CENTER, true))

	# "NEW" Commodity / Boosted Goods Cards with ShapeGlyphs!
	var goods_list: Array = info.get("boostedGoods" if is_boom else "newGoods", [])
	if not goods_list.is_empty():
		var g_hdr := _make_lbl("Komoditas Unggulan:" if is_boom else "Komoditas & Industri Baru:", 13, COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER, true)
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
			g_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	ok_btn.clip_text = true
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
		_reroute_has_data = false
		_reroute_card.visible = false
		return

	_detach_and_free_children(_reroute_vbox)
	_active_reroute_offer_id = String(off["id"])
	_reroute_has_data = true

	var top_hb := HBoxContainer.new()
	top_hb.add_theme_constant_override("separation", 8)
	var ttl := _make_lbl("🛣  %s Dibuka!" % String(off.get("name", "Jalan Baru")), 14, COL_GREEN)
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ttl.clip_text = true
	top_hb.add_child(ttl)
	var x_btn := _make_btn("✕", COL_CARD_BG, COL_INK, COL_INK, 13, 42.0)
	x_btn.pressed.connect(func(): close_reroute_panel())
	top_hb.add_child(x_btn)
	_reroute_vbox.add_child(top_hb)

	_reroute_vbox.add_child(_make_lbl("%d rute dapat melewati koridor baru ini:" % routes_arr.size(), 12, COL_MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	var r_scroll := ScrollContainer.new()
	r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r_scroll.custom_minimum_size = Vector2(0, minf(138.0, float(routes_arr.size()) * 46.0))
	var r_list_vb := VBoxContainer.new()
	r_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_list_vb.add_theme_constant_override("separation", 6)

	for i in range(routes_arr.size()):
		var r_info: Dictionary = routes_arr[i]
		var rid := String(r_info["routeId"])
		var r_row := HBoxContainer.new()
		r_row.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(10, 20)
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

		var use_b := _make_btn("✓ Aktif" if bool(r_info.get("usesAlready", false)) else "Lewatkan", COL_CARD_BG, COL_GREEN, COL_GREEN, 12, 40.0)
		use_b.disabled = bool(r_info.get("usesAlready", false))
		use_b.pressed.connect(func():
			if sim.reroute_over_offer(rid, _active_reroute_offer_id):
				use_b.text = "✓ Aktif"
				use_b.disabled = true
				toast_requested.emit("Rute dialihkan lewat " + String(off.get("name", "koridor baru")))
		)
		r_row.add_child(use_b)
		r_list_vb.add_child(r_row)

	r_scroll.add_child(r_list_vb)
	make_scroll_touch_friendly(r_scroll)
	_reroute_vbox.add_child(r_scroll)

	var all_btn := _make_btn("⚡ Lewatkan Semua Rute (%d)" % routes_arr.size(), COL_GREEN, Color.WHITE, COL_INK, 13, 44.0)
	all_btn.clip_text = true
	all_btn.pressed.connect(func():
		var n_ok: int = sim.reroute_all_over_offer(_active_reroute_offer_id)
		close_reroute_panel()
		toast_requested.emit("%d rute dialihkan ke %s!" % [n_ok, String(off.get("name", "jalan baru"))])
	)
	_reroute_vbox.add_child(all_btn)

	_reroute_card.visible = not is_title_open and not is_modal_open and not is_loading_open() and not _is_hud_blocking_floating_cards()
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
