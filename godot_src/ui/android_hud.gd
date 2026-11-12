class_name AndroidHUD
extends CanvasLayer

## Tactile Cartography adaptive Portrait & Landscape HUD for Godot 4 Android.
## Built 100% programmatically with StyleBoxFlat for crisp DPI scaling and zero texture overhead.

signal tool_changed(tool_id: String)
signal overlay_changed(mode_id: String)
signal map_selected(map_id: String)
signal perf_preset_changed(preset_id: String)
signal theme_toggled(is_dark: bool)
signal focus_world_requested(world_pos: Vector2)

var sim: SimEngine
var map_view: MapView25D

var dark_mode: bool = false
var perf_preset: String = "balanced"
var current_drawer: String = "" # "", "facility", "junction", "road", "routes", "offers", "goals", "maps", "overlays", "settings"

var _root: Control
var _top_bar: PanelContainer
var _bottom_bar: PanelContainer
var _drawer_panel: PanelContainer
var _banner_panel: PanelContainer
var _banner_label: Label
var _banner_timer: float = 0.0

var _map_btn: Button
var _cash_btn: Button
var _goal_btn: Button
var _speed_btns: Dictionary = {}
var _night_btn: Button
var _fps_label: Label
var _broken_btn: Button

var _tool_btns: Dictionary = {}
var _drawer_title: Label
var _drawer_body: VBoxContainer

var _ui_refresh_timer: float = 0.0
var _last_vp_size := Vector2.ZERO

func setup(sim_engine: SimEngine, view_node: MapView25D) -> void:
	layer = 15
	sim = sim_engine
	map_view = view_node
	sim.banner_notify.connect(_on_sim_banner)

	_build_shell()
	_apply_styles()
	_layout_responsive()
	refresh_top_bar()

func _build_shell() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# === TOP TELEMETRY BAR ===
	_top_bar = PanelContainer.new()
	_root.add_child(_top_bar)

	var top_scroll := ScrollContainer.new()
	top_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	top_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_top_bar.add_child(top_scroll)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	top_scroll.add_child(top_row)

	_map_btn = _make_btn("🗺️ Peta", func(): open_drawer("maps"), 38)
	top_row.add_child(_map_btn)

	_cash_btn = _make_btn("$3,500", func(): open_drawer("routes"), 38)
	top_row.add_child(_cash_btn)

	_goal_btn = _make_btn("🎯 Target", func(): open_drawer("goals"), 38)
	top_row.add_child(_goal_btn)

	for sp in [0, 1, 2, 4]:
		var lbl := "⏸" if sp == 0 else ("%d×" % sp)
		var sb := _make_btn(lbl, func(): _set_speed(sp), 38, 40)
		_speed_btns[sp] = sb
		top_row.add_child(sb)

	_night_btn = _make_btn("☀️", func(): _toggle_night(), 38, 42)
	top_row.add_child(_night_btn)

	_broken_btn = _make_btn("⚠️ Rute Putus!", func(): _jump_broken_route(), 38)
	_broken_btn.visible = false
	top_row.add_child(_broken_btn)

	_fps_label = Label.new()
	_fps_label.text = "60 FPS"
	_fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fps_label.add_theme_font_size_override("font_size", 12)
	top_row.add_child(_fps_label)

	# === FLOATING STATUS BANNER ===
	_banner_panel = PanelContainer.new()
	_banner_panel.visible = false
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner_panel)

	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 13)
	_banner_panel.add_child(_banner_label)

	# === CONTEXTUAL INSPECTOR / MANAGER DRAWER ===
	_drawer_panel = PanelContainer.new()
	_drawer_panel.visible = false
	_root.add_child(_drawer_panel)

	var drawer_vbox := VBoxContainer.new()
	drawer_vbox.add_theme_constant_override("separation", 6)
	_drawer_panel.add_child(drawer_vbox)

	var header_row := HBoxContainer.new()
	drawer_vbox.add_child(header_row)

	_drawer_title = Label.new()
	_drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_title.add_theme_font_size_override("font_size", 15)
	header_row.add_child(_drawer_title)

	var close_btn := _make_btn("✕", func(): close_drawer(), 34, 38)
	header_row.add_child(close_btn)

	var drawer_scroll := ScrollContainer.new()
	drawer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drawer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	drawer_vbox.add_child(drawer_scroll)

	_drawer_body = VBoxContainer.new()
	_drawer_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_body.add_theme_constant_override("separation", 6)
	drawer_scroll.add_child(_drawer_body)

	# === BOTTOM THUMB-ZONE ENGINEERING TOOLBAR ===
	_bottom_bar = PanelContainer.new()
	_root.add_child(_bottom_bar)

	var bot_scroll := ScrollContainer.new()
	bot_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_bottom_bar.add_child(bot_scroll)

	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 6)
	bot_scroll.add_child(bot_row)

	var tools_spec := [
		["pan", "✋ Geser"],
		["route", "🚚 Rute+"],
		["fleet_ui", "📋 Armada"],
		["yield", "⚠️ Yield"],
		["roundabout", "🔄 Bundaran"],
		["lights", "🚦 Lampu"],
		["lanes_add", "➕ Lajur+"],
		["lanes_remove", "➖ Lajur−"],
		["one_way", "➡️ Searah"],
		["close_street", "🌳 Tutup"],
		["offers_ui", "🛣️ Tol/Baru"],
		["overlays_ui", "👁️ Overlay"],
		["settings_ui", "⚙️ Opsi"],
	]
	for spec in tools_spec:
		var tid := String(spec[0])
		var tlabel := String(spec[1])
		var tb := _make_btn(tlabel, func(): _on_toolbar_pressed(tid), 44)
		_tool_btns[tid] = tb
		bot_row.add_child(tb)

	_highlight_active_tool("pan")
	_highlight_speed(1)

func _make_btn(txt: String, cb: Callable, min_h: int = 42, min_w: int = 0, wrap_text: bool = false) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(float(min_w), float(min_h))
	b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE
	if wrap_text:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	return b

func _style_box(bg: Color, border: Color, radius: int = 10, pad_h: int = 10, pad_v: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = float(pad_h)
	sb.content_margin_right = float(pad_h)
	sb.content_margin_top = float(pad_v)
	sb.content_margin_bottom = float(pad_v)
	return sb

func _apply_styles() -> void:
	var panel_bg := Color(0.12, 0.15, 0.20, 0.94) if dark_mode else Color(0.98, 0.96, 0.92, 0.95)
	var border_col := Color("#364152") if dark_mode else Color("#cfc5b2")
	var txt_col := Color("#f1f5f9") if dark_mode else Color("#1e242c")

	var bar_sb := _style_box(panel_bg, border_col, 12, 8, 6)
	_top_bar.add_theme_stylebox_override("panel", bar_sb)
	_bottom_bar.add_theme_stylebox_override("panel", bar_sb)
	_drawer_panel.add_theme_stylebox_override("panel", _style_box(panel_bg, border_col, 14, 12, 10))
	_banner_panel.add_theme_stylebox_override("panel", _style_box(Color(0.11, 0.14, 0.19, 0.92), Color("#2c7be5"), 10, 12, 6))

	_drawer_title.add_theme_color_override("font_color", txt_col)
	_fps_label.add_theme_color_override("font_color", Color("#37b24d") if not dark_mode else Color("#69db7c"))
	_banner_label.add_theme_color_override("font_color", Color("#f8f9fa"))

	var btn_bg := Color("#27303f") if dark_mode else Color("#eee7d8")
	var btn_hover := Color("#323d50") if dark_mode else Color("#e3dac7")
	var btn_dis_bg := Color("#1c222d") if dark_mode else Color("#dfd8c8")
	var dis_txt_col := Color("#64748b") if dark_mode else Color("#7c7669")
	var btn_sb := _style_box(btn_bg, border_col, 9, 10, 5)
	var btn_hov_sb := _style_box(btn_hover, border_col, 9, 10, 5)
	var btn_dis_sb := _style_box(btn_dis_bg, border_col, 9, 10, 5)

	for b in _get_all_buttons(_root):
		b.add_theme_stylebox_override("normal", btn_sb)
		b.add_theme_stylebox_override("hover", btn_hov_sb)
		b.add_theme_stylebox_override("disabled", btn_dis_sb)
		b.add_theme_stylebox_override("pressed", _style_box(Color("#2c7be5"), Color("#1958b5"), 9, 10, 5))
		b.add_theme_color_override("font_color", txt_col)
		b.add_theme_color_override("font_hover_color", txt_col)
		b.add_theme_color_override("font_disabled_color", dis_txt_col)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)

	_highlight_active_tool(map_view.active_tool if map_view else "pan")
	_highlight_speed(sim.speed_multiplier if sim else 1)
	if _broken_btn:
		_broken_btn.add_theme_stylebox_override("normal", _style_box(Color("#c92a2a"), Color("#ff8787"), 9, 10, 5))
		_broken_btn.add_theme_color_override("font_color", Color.WHITE)

func _get_all_buttons(node: Node) -> Array[Button]:
	var res: Array[Button] = []
	for ch in node.get_children():
		if ch is Button:
			res.append(ch as Button)
		res.append_array(_get_all_buttons(ch))
	return res

func _layout_responsive() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(960, 540)
	_last_vp_size = vp

	# Safe area margins for Android camera cutouts & gesture bars
	var pad_left: float = 8.0
	var pad_right: float = 8.0
	var pad_top: float = 8.0
	var pad_bot: float = 8.0
	if OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var win: Vector2i = DisplayServer.window_get_size()
		if win.x > 0 and win.y > 0 and safe.size.x > 0:
			var sx: float = vp.x / float(win.x)
			var sy: float = vp.y / float(win.y)
			pad_left = maxf(8.0, float(safe.position.x) * sx)
			pad_top = maxf(8.0, float(safe.position.y) * sy)
			pad_right = maxf(8.0, float(win.x - safe.end.x) * sx)
			pad_bot = maxf(8.0, float(win.y - safe.end.y) * sy)

	_top_bar.position = Vector2(pad_left, pad_top)
	_top_bar.size = Vector2(vp.x - pad_left - pad_right, 50.0)

	var bot_h: float = 58.0
	_bottom_bar.position = Vector2(pad_left, vp.y - pad_bot - bot_h)
	_bottom_bar.size = Vector2(vp.x - pad_left - pad_right, bot_h)

	_banner_panel.position = Vector2(maxf(pad_left, vp.x * 0.5 - 190.0), pad_top + 56.0)
	_banner_panel.size = Vector2(minf(380.0, vp.x - pad_left - pad_right), 34.0)

	var is_portrait: bool = vp.x < vp.y
	if is_portrait:
		var dh: float = clampf(vp.y * 0.45, 220.0, 420.0)
		_drawer_panel.position = Vector2(pad_left, _bottom_bar.position.y - dh - 6.0)
		_drawer_panel.size = Vector2(vp.x - pad_left - pad_right, dh)
	else:
		var dw: float = minf(365.0, vp.x * 0.44)
		var avail_h: float = _bottom_bar.position.y - (_top_bar.position.y + _top_bar.size.y) - 12.0
		_drawer_panel.position = Vector2(vp.x - pad_right - dw, _top_bar.position.y + _top_bar.size.y + 6.0)
		_drawer_panel.size = Vector2(dw, maxf(180.0, avail_h))

func _process(delta: float) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp != _last_vp_size:
		_layout_responsive()

	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner_panel.visible = false

	_ui_refresh_timer += delta
	if _ui_refresh_timer >= 0.35:
		_ui_refresh_timer = 0.0
		refresh_top_bar()
		if current_drawer in ["facility", "goals", "routes"]:
			_populate_drawer()

func show_toast_banner(msg: String, duration: float = 2.6) -> void:
	_banner_label.text = msg
	_banner_panel.visible = true
	_banner_timer = duration

func _on_sim_banner(title: String, subtitle: String, _accent: Color) -> void:
	show_toast_banner("%s — %s" % [title, subtitle], 3.8)

func refresh_top_bar() -> void:
	if sim == null:
		return
	var map_short := String(sim.map_def.get("name", "Madiun"))
	if map_short.length() > 20:
		map_short = map_short.substr(0, 18) + ".."
	_map_btn.text = "🗺️ " + map_short

	var net_min: int = sim.get_revenue_per_min() - sim.get_upkeep_per_min()
	var sign_s := "+" if net_min >= 0 else ""
	_cash_btn.text = "%s (%s%s/m)" % [GameCatalog.fmt_cash(sim.cash), sign_s, GameCatalog.fmt_cash(net_min)]

	var greg: Dictionary = sim.get_active_goal_region()
	if not greg.is_empty():
		var hold_i: int = int(round(float(greg["holdSeconds"])))
		if not bool(greg["unlocked"]):
			_goal_btn.text = "🎯 %s (%ds/30s)" % [String(greg["name"]), hold_i]
		else:
			_goal_btn.text = "🏆 Boomtown Lv.%d (%ds)" % [sim.boomtown_level, hold_i]

	_night_btn.text = "🌙" if sim.night_mode else "☀️"
	_fps_label.text = "%d FPS · 🚛%d" % [Engine.get_frames_per_second(), sim.agents.size()]

	var has_broken: bool = false
	for rt in sim.routes:
		if String(rt["brokenReason"]) != "":
			has_broken = true
			break
	_broken_btn.visible = has_broken

func _set_speed(sp: int) -> void:
	sim.speed_multiplier = sp
	if sim.sfx:
		sim.sfx.tap(10)
	_highlight_speed(sp)

func _highlight_speed(sp: int) -> void:
	var border_col := Color("#364152") if dark_mode else Color("#cfc5b2")
	var normal_bg := Color("#27303f") if dark_mode else Color("#eee7d8")
	var txt_col := Color("#f1f5f9") if dark_mode else Color("#1e242c")
	for k in _speed_btns.keys():
		var b: Button = _speed_btns[k]
		if int(k) == sp:
			b.add_theme_stylebox_override("normal", _style_box(Color("#2c7be5"), Color("#1864ab"), 9, 8, 5))
			b.add_theme_color_override("font_color", Color.WHITE)
		else:
			b.add_theme_stylebox_override("normal", _style_box(normal_bg, border_col, 9, 8, 5))
			b.add_theme_color_override("font_color", txt_col)

func _toggle_night() -> void:
	sim.night_mode = not sim.night_mode
	sim.auto_day_night = false
	if sim.sfx:
		sim.sfx.tap(12)
	refresh_top_bar()

func _jump_broken_route() -> void:
	for rt in sim.routes:
		if String(rt["brokenReason"]) != "":
			var f_from: Dictionary = sim.facility_map.get(String(rt["fromFacilityId"]), {})
			if not f_from.is_empty():
				focus_world_requested.emit(f_from["pos"])
			map_view.selected_route_id = String(rt["id"])
			open_drawer("routes")
			show_toast_banner("Rute bermasalah: " + String(rt["brokenReason"]), 3.2)
			return

func _on_toolbar_pressed(tid: String) -> void:
	if sim.sfx:
		sim.sfx.tap(12)
	if tid == "fleet_ui":
		open_drawer("routes")
		return
	if tid == "offers_ui":
		open_drawer("offers")
		return
	if tid == "overlays_ui":
		open_drawer("overlays")
		return
	if tid == "settings_ui":
		open_drawer("settings")
		return

	map_view.active_tool = tid
	if tid != "route":
		map_view.route_draft_from_id = ""
	_highlight_active_tool(tid)
	tool_changed.emit(tid)

	var hints := {
		"pan": "Mode Geser & Inspeksi: ketuk pabrik, simpang, atau jalan",
		"route": "Buat Rute Baru: ketuk Fasilitas Asal lalu ketuk Fasilitas Tujuan",
		"yield": "Ketuk simpang ≥3 lengan untuk pasang/lepas rambu Yield ($0)",
		"roundabout": "Ketuk simpang untuk bangun Bundaran ($10k) atau upgrade 2 Lajur ($16k)",
		"lights": "Ketuk simpang untuk pasang/atur Lampu Lalu Lintas ($1,000)",
		"lanes_add": "Ketuk ruas jalan untuk menambah lajur (+1 lajur per arah)",
		"lanes_remove": "Ketuk ruas jalan untuk mengurangi lajur (refund 50%)",
		"one_way": "Ketuk ruas jalan untuk ubah Satu Arah / Dua Arah ($0)",
		"close_street": "Ketuk ruas jalan untuk menutup jadi taman kota ($3,200)"
	}
	if hints.has(tid):
		show_toast_banner(String(hints[tid]), 2.4)

func _highlight_active_tool(tid: String) -> void:
	var border_col := Color("#364152") if dark_mode else Color("#cfc5b2")
	var normal_bg := Color("#27303f") if dark_mode else Color("#eee7d8")
	var txt_col := Color("#f1f5f9") if dark_mode else Color("#1e242c")
	for k in _tool_btns.keys():
		var b: Button = _tool_btns[k]
		if String(k) == tid:
			b.add_theme_stylebox_override("normal", _style_box(Color("#0ca678"), Color("#087f5b"), 9, 10, 5))
			b.add_theme_color_override("font_color", Color.WHITE)
		else:
			b.add_theme_stylebox_override("normal", _style_box(normal_bg, border_col, 9, 10, 5))
			b.add_theme_color_override("font_color", txt_col)

func open_drawer(kind: String) -> void:
	current_drawer = kind
	_drawer_panel.visible = true
	_populate_drawer()
	_apply_styles()

func close_drawer() -> void:
	current_drawer = ""
	_drawer_panel.visible = false

func _clear_drawer_body() -> void:
	for ch in _drawer_body.get_children():
		ch.queue_free()

func _add_info_label(txt: String, muted_tone: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	var col := (Color("#94a3b8") if dark_mode else Color("#525d6b")) if muted_tone else (Color("#f1f5f9") if dark_mode else Color("#1e242c"))
	l.add_theme_color_override("font_color", col)
	_drawer_body.add_child(l)
	return l

func _populate_drawer() -> void:
	_clear_drawer_body()
	if current_drawer == "facility":
		_build_facility_drawer()
	elif current_drawer == "junction":
		_build_junction_drawer()
	elif current_drawer == "road":
		_build_road_drawer()
	elif current_drawer == "routes":
		_build_routes_drawer()
	elif current_drawer == "offers":
		_build_offers_drawer()
	elif current_drawer == "goals":
		_build_goals_drawer()
	elif current_drawer == "maps":
		_build_maps_drawer()
	elif current_drawer == "overlays":
		_build_overlays_drawer()
	elif current_drawer == "settings":
		_build_settings_drawer()
	_apply_styles()

func _build_facility_drawer() -> void:
	var fid := map_view.selected_facility_id
	if not sim.facility_map.has(fid):
		close_drawer()
		return
	var f: Dictionary = sim.facility_map[fid]
	_drawer_title.text = String(f["name"])
	_add_info_label(String(f["localContext"]), true)

	var cap: int = sim.get_capacity_slots(f)
	var kind_s := String(f["kind"])
	if f["outputGood"] != null:
		var gid := String(f["outputGood"])
		var gdef: Dictionary = GameCatalog.GOODS[gid]
		_add_info_label("Output: %s (%s · %s/unit) — Stok: %d / %d slot" % [
			String(gdef["name"]), String(gdef["local"]), GameCatalog.fmt_cash(int(gdef["value"])), int(f["outputBuffer"]), cap
		])
	if not (f["acceptedGoods"] as Array).is_empty():
		var parts: Array[String] = []
		for ag_id in f["acceptedGoods"]:
			var gs := String(ag_id)
			var g_nm: String = GameCatalog.GOODS[gs]["name"] if GameCatalog.GOODS.has(gs) else gs
			if kind_s == "factory":
				parts.append("%s (%d)" % [g_nm, int(f["inputBuffers"].get(gs, 0))])
			else:
				parts.append(g_nm)
		_add_info_label("Menerima: " + ", ".join(parts))

	_add_info_label("Dermaga Aktif: %d / %d Bay" % [int(f["occupiedBays"]), sim.get_total_bays(f)], true)

	var start_rt_btn := _make_btn("🚚 Buat Rute Pengiriman dari Sini", func():
		map_view.active_tool = "route"
		map_view.route_draft_from_id = fid
		_highlight_active_tool("route")
		close_drawer()
		show_toast_banner("Sekarang ketuk Fasilitas Tujuan di peta!", 3.0)
	, 40, 0, true)
	_drawer_body.add_child(start_rt_btn)

	for up in sim.get_facility_upgrades(f):
		var track := String(up["track"])
		var locked := String(up["locked"])
		var btn_txt: String
		if locked != "":
			btn_txt = "%s Lv.%d/%d (%s) — %s" % [String(up["label"]), int(up["level"]), int(up["max"]), locked, String(up["desc"])]
		else:
			btn_txt = "⬆️ %s Lv.%d→%d (%s)\n%s" % [String(up["label"]), int(up["level"]), int(up["level"]) + 1, GameCatalog.fmt_cash(int(up["price"])), String(up["desc"])]
		var ub := _make_btn(btn_txt, func():
			if sim.buy_facility_upgrade(fid, track):
				_populate_drawer()
				_apply_styles()
		, 52, 0, true)
		ub.disabled = locked != ""
		_drawer_body.add_child(ub)

func _build_junction_drawer() -> void:
	var jid := map_view.selected_junction_id
	if not sim.junction_map.has(jid):
		close_drawer()
		return
	var j: Dictionary = sim.junction_map[jid]
	_drawer_title.text = String(j.get("name", "Simpang Jalan"))
	if j.get("landmark", null) != null:
		_add_info_label("📍 Landmark: " + String(j["landmark"]), true)
	_add_info_label("Koordinat Nyata: %.4f° LS, %.4f° BT · Kendali: %s" % [
		absf(float(j["lat"])), float(j["lon"]), String(j["control"]).to_upper()
	], true)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_drawer_body.add_child(row)

	row.add_child(_make_btn("⚠️ Yield ($0)", func():
		show_toast_banner(sim.apply_junction_control(jid, "yield"))
		_populate_drawer()
		_apply_styles()
	, 42))
	row.add_child(_make_btn("🔄 Bundaran", func():
		show_toast_banner(sim.apply_junction_control(jid, "roundabout"))
		_populate_drawer()
		_apply_styles()
	, 42))
	row.add_child(_make_btn("🚦 Lampu ($1k)", func():
		show_toast_banner(sim.apply_junction_control(jid, "lights"))
		_populate_drawer()
		_apply_styles()
	, 42))

	if String(j["control"]) == "lights" and j.has("light"):
		var lt: Dictionary = j["light"]
		_add_info_label("Pengaturan Fase Lampu Teraktuasi:")

		var lbl_a := _add_info_label("Hijau Fase A: %d detik" % int(lt["phaseAGreen"]))
		var sl_a := HSlider.new()
		sl_a.min_value = 4.0
		sl_a.max_value = 40.0
		sl_a.step = 1.0
		sl_a.value = float(lt["phaseAGreen"])
		sl_a.value_changed.connect(func(v: float):
			lt["phaseAGreen"] = v
			lbl_a.text = "Hijau Fase A: %d detik" % int(v)
		)
		_drawer_body.add_child(sl_a)

		var lbl_b := _add_info_label("Hijau Fase B: %d detik" % int(lt["phaseBGreen"]))
		var sl_b := HSlider.new()
		sl_b.min_value = 4.0
		sl_b.max_value = 40.0
		sl_b.step = 1.0
		sl_b.value = float(lt["phaseBGreen"])
		sl_b.value_changed.connect(func(v: float):
			lt["phaseBGreen"] = v
			lbl_b.text = "Hijau Fase B: %d detik" % int(v)
		)
		_drawer_body.add_child(sl_b)

		var sensor_btn := _make_btn("Sensor Celah Otomatis: %s" % ("AKTIF" if bool(lt["actuated"]) else "MATI"), func():
			lt["actuated"] = not bool(lt["actuated"])
			_populate_drawer()
			_apply_styles()
		, 38, 0, true)
		_drawer_body.add_child(sensor_btn)

		var rem_btn := _make_btn("🗑️ Bongkar Lampu (+$500)", func():
			sim.remove_traffic_lights(jid)
			_populate_drawer()
			_apply_styles()
		, 38, 0, true)
		_drawer_body.add_child(rem_btn)

func _build_road_drawer() -> void:
	var rid := map_view.selected_road_id
	if not sim.road_map.has(rid):
		close_drawer()
		return
	var r: Dictionary = sim.road_map[rid]
	_drawer_title.text = String(r["name"])
	_add_info_label("Kelas: %s · Lajur: %d/arah · Kepadatan: %d%%" % [
		String(r["roadClass"]).to_upper(), int(r["lanesForward"]), int(round(float(r["congestionEMA"]) * 100.0))
	], true)

	_drawer_body.add_child(_make_btn("➕ Tambah Lajur Jalan", func():
		show_toast_banner(sim.modify_road_lanes(rid, 1))
		_populate_drawer()
		_apply_styles()
	, 42, 0, true))
	_drawer_body.add_child(_make_btn("➖ Kurangi Lajur (Refund 50%)", func():
		show_toast_banner(sim.modify_road_lanes(rid, -1))
		_populate_drawer()
		_apply_styles()
	, 42, 0, true))
	_drawer_body.add_child(_make_btn("➡️ Ubah Arah (Dua Arah / Satu Arah $0)", func():
		show_toast_banner(sim.cycle_road_one_way(rid))
		_populate_drawer()
		_apply_styles()
	, 42, 0, true))
	var close_lbl := "🔓 Buka Kembali Jalan ($0)" if bool(r["closed"]) else "🌳 Tutup Jalan Jadi Taman ($3,200)"
	_drawer_body.add_child(_make_btn(close_lbl, func():
		show_toast_banner(sim.toggle_close_street(rid))
		_populate_drawer()
		_apply_styles()
	, 42, 0, true))

func _build_routes_drawer() -> void:
	_drawer_title.text = "Armada & Rute (%d Truk)" % sim.agents.size()
	_add_info_label("Pendapatan: +%s/mnt · Biaya Armada: -%s/mnt" % [
		GameCatalog.fmt_cash(sim.get_revenue_per_min()), GameCatalog.fmt_cash(sim.get_upkeep_per_min())
	], true)

	var new_btn := _make_btn("➕ Buat Rute Baru (Ketuk 2 Gedung di Peta)", func():
		_on_toolbar_pressed("route")
		close_drawer()
	, 42, 0, true)
	_drawer_body.add_child(new_btn)

	if sim.routes.is_empty():
		_add_info_label("Belum ada rute aktif. Tekan Rute+ untuk menghubungkan Supplier ke Pabrik/Stasiun.")
		return

	for rt in sim.routes:
		var rtid := String(rt["id"])
		var m_id := String(rt["truckModel"])
		var m_def: Dictionary = GameCatalog.TRUCKS[m_id]
		var cnt: int = (rt["activeTruckIds"] as Array).size()
		var g_txt := String(rt["goodFilter"]).to_upper()
		var head := "🚛 %s [%s] · %d× %s" % [String(rt["name"]), g_txt, cnt, String(m_def["name"])]
		_add_info_label(head)
		if String(rt["brokenReason"]) != "":
			_add_info_label("⚠️ " + String(rt["brokenReason"]), false)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		_drawer_body.add_child(row)

		var nxt_p: int = sim.get_next_truck_price(m_id)
		row.add_child(_make_btn("+Truk (%s)" % GameCatalog.fmt_cash(nxt_p), func():
			sim.add_truck_to_route(rtid, false)
			_populate_drawer()
			_apply_styles()
		, 38))
		row.add_child(_make_btn("−Truk", func():
			sim.remove_truck_from_route(rtid)
			_populate_drawer()
			_apply_styles()
		, 38))
		row.add_child(_make_btn("Pilih/WP", func():
			map_view.selected_route_id = rtid
			show_toast_banner("Rute dipilih! Ketuk simpang mana pun di peta untuk tambah/lepas Waypoint.", 3.0)
			_populate_drawer()
			_apply_styles()
		, 38))
		row.add_child(_make_btn("🗑️", func():
			sim.delete_route(rtid)
			_populate_drawer()
			_apply_styles()
		, 38, 38))

		# Model Swap Net Cost Calculator when route is selected
		if map_view.selected_route_id == rtid:
			_add_info_label("Kalkulator Tukar-Tambah Model Armada:", true)
			for cand_m in GameCatalog.TRUCK_ORDER:
				if cand_m == m_id:
					continue
				var q: Dictionary = sim.quote_route_model_swap(rtid, cand_m)
				var net: int = int(q["netCost"])
				var cdef: Dictionary = GameCatalog.TRUCKS[cand_m]
				var net_s: String = ("Net -" + GameCatalog.fmt_cash(net)) if net >= 0 else ("Refund +" + GameCatalog.fmt_cash(-net))
				var swap_b := _make_btn("⇄ %s (%d km/j) · %s" % [String(cdef["name"]), int(cdef["speed_kmh"]), net_s], func():
					if sim.apply_route_model_swap(rtid, cand_m):
						_populate_drawer()
						_apply_styles()
				, 38, 0, true)
				_drawer_body.add_child(swap_b)

func _build_offers_drawer() -> void:
	_drawer_title.text = "Proyek Jalan Raya & Tol Baru"
	_add_info_label("Pembangunan jalan tol, bypass, dan JLS sesuai tata ruang nyata Karesidenan Madiun:", true)
	if sim.road_offers.is_empty():
		_add_info_label("Tidak ada proyek jalan tambahan pada peta ini.")
		return
	for off in sim.road_offers:
		var oid := String(off["id"])
		var bought: bool = bool(off["purchased"])
		var reg_ok: bool = sim.unlocked_regions.has(int(off["regionIndex"]))
		_add_info_label("🛣️ " + String(off["name"]))
		_add_info_label(String(off["subtitle"]), true)
		var btn_lbl: String
		if bought:
			btn_lbl = "✅ Sudah Beroperasi"
		elif not reg_ok:
			btn_lbl = "🔒 Buka Wilayah Terkait Lebih Dulu"
		else:
			btn_lbl = "Bangun Sekarang (%s)" % GameCatalog.fmt_cash(int(off["price"]))
		var ob := _make_btn(btn_lbl, func():
			show_toast_banner(sim.purchase_road_offer(oid))
			_populate_drawer()
			_apply_styles()
		, 42, 0, true)
		ob.disabled = bought or (not reg_ok)
		_drawer_body.add_child(ob)

func _build_goals_drawer() -> void:
	_drawer_title.text = "Progresi Wilayah Karesidenan"
	_add_info_label("Pertahankan target pengiriman selama 30 detik beruntun untuk membuka Kabupaten/Kota berikutnya:", true)
	for reg in sim.regions:
		var unl: bool = bool(reg["unlocked"])
		var status := "✅ TERBUKA" if unl else ("⏳ TAHAN %ds/30s" % int(round(float(reg["holdSeconds"]))))
		_add_info_label("%s — %s [%s]" % [String(reg["name"]), String(reg["subtitle"]), status])
		for g in reg["goals"]:
			var gid := String(g["good"])
			var gdef: Dictionary = GameCatalog.GOODS[gid]
			_add_info_label("   • %s (%s): %.1f / %.1f unit/mnt" % [
				String(gdef["name"]), String(gdef["local"]), float(g.get("currentPerMin", 0.0)), float(g["targetPerMin"])
			], true)
		var jump_b := _make_btn("📍 Lihat " + String(reg["name"]), func():
			focus_world_requested.emit(reg["center_vec"])
		, 36, 0, true)
		_drawer_body.add_child(jump_b)

func _build_maps_drawer() -> void:
	_drawer_title.text = "Pilih Peta Karesidenan Madiun (7 Peta)"
	_add_info_label("Seluruh batas wilayah, sungai, rel KA, dan jaringan jalan diolah dari geometri WGS84 dunia nyata:", true)
	for m in sim.maps_list:
		var mid := String(m["id"])
		var active: bool = mid == sim.current_map_id
		var prefix := "🟢 " if active else "🗺️ "
		var title_s := "%s%s (%s)\n%s" % [prefix, String(m["name"]), String(m["badge"]), String(m["subtitle"])]
		var mb := _make_btn(title_s, func():
			close_drawer()
			map_selected.emit(mid)
		, 58, 0, true)
		_drawer_body.add_child(mb)

func _build_overlays_drawer() -> void:
	_drawer_title.text = "Lima Mode Overlay Analitik"
	var modes := [
		["routes", "🚛 Jaringan Rute & Waypoint"],
		["traffic", "🚦 Heatmap Kemacetan Jalan"],
		["flow", "📊 Diagram Aliran Barang (Sankey)"],
		["buildings", "🏭 Status & Efisiensi Pabrik"],
		["demand", "🎯 Permintaan Pasar & Target Wilayah"],
	]
	for ms in modes:
		var mid := String(ms[0])
		var active: bool = map_view.overlay_mode == mid
		var b := _make_btn(("✓ " if active else "") + String(ms[1]), func():
			map_view.overlay_mode = mid
			overlay_changed.emit(mid)
			_populate_drawer()
			_apply_styles()
		, 42, 0, true)
		_drawer_body.add_child(b)

func _build_settings_drawer() -> void:
	_drawer_title.text = "Optimalisasi Android & Opsi"
	_add_info_label("Preset Performa GPU/CPU Android:", true)

	for pr in [["battery", "🔋 Hemat Baterai (30 FPS)"], ["balanced", "⚡ Seimbang Android (60 FPS)"], ["ultra", "🚀 Ultra Smooth (120 FPS)"]]:
		var pid := String(pr[0])
		var pb := _make_btn(("✓ " if perf_preset == pid else "") + String(pr[1]), func():
			perf_preset = pid
			perf_preset_changed.emit(pid)
			_populate_drawer()
			_apply_styles()
		, 40, 0, true)
		_drawer_body.add_child(pb)

	_drawer_body.add_child(_make_btn("🛣️ Sisi Kemudi: %s" % ("Lajur Kiri (Indonesia)" if sim.left_hand_traffic else "Lajur Kanan"), func():
		sim.left_hand_traffic = not sim.left_hand_traffic
		_populate_drawer()
		_apply_styles()
	, 40, 0, true))

	_drawer_body.add_child(_make_btn("🎨 Tema Peta: %s" % ("Slate Gelap" if dark_mode else "Kertas Kartografi Terang"), func():
		dark_mode = not dark_mode
		theme_toggled.emit(dark_mode)
		_populate_drawer()
		_apply_styles()
	, 40, 0, true))

	_drawer_body.add_child(_make_btn("🌅 Siklus Siang/Malam Otomatis: %s" % ("AKTIF" if sim.auto_day_night else "MANUAL"), func():
		sim.auto_day_night = not sim.auto_day_night
		_populate_drawer()
		_apply_styles()
	, 40, 0, true))

	_drawer_body.add_child(_make_btn("🔊 Efek Suara: %s" % ("MATI" if sim.sfx.muted else "AKTIF"), func():
		sim.sfx.muted = not sim.sfx.muted
		_populate_drawer()
		_apply_styles()
	, 40, 0, true))

	_drawer_body.add_child(_make_btn("🔄 Reset Progres Peta Ini", func():
		sim.reset_current_map()
		close_drawer()
		show_toast_banner("Peta direset ke kondisi awal.", 2.5)
	, 40, 0, true))
