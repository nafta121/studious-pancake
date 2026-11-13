class_name AndroidHUD
extends CanvasLayer

## Authentic Incremental Traffic "Sticker" HUD & Modal Suite for Godot 4.7.2 Android.
## Uses original gui/theme.tres + gui/theme_dark.tres, Jost-Variable.ttf, title_logo.png,
## 26 UI WAVs, and exact 5-Zone HUD layout (MoneyDisplay, GoalsPanel, RuleToolbar,
## Overview/Trucks PrimaryButtons, OverlayBar + DayClock + SpeedControls, FactoryPanel,
## and Overview 5-min Cash Graph), with dynamic Landscape & Portrait scaling.

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
var current_drawer: String = "" # "", "facility", "junction", "road", "routes", "trucks", "offers", "goals", "maps", "overlays", "settings"

var _theme_light: Theme
var _theme_dark: Theme
var _logo_tex: Texture2D
var _ui_font: Font

var _root: Control

# Zone 1: Top-Center MoneyDisplay Pill
var _money_pill: PanelContainer
var _crest_widget: _CrestWidget
var _town_btn: Button
var _cash_btn: Button
var _profit_lbl: Label

# Zone 2: Top-Right Collapsible GoalsPanel + Mini Goal Pill
var _goals_collapsed: bool = false
var _goals_card: PanelContainer
var _goals_header_lbl: Label
var _goals_sub_lbl: Label
var _goals_rings_row: HBoxContainer
var _goals_hold_lbl: Label
var _goals_hold_bar: ProgressBar
var _goals_mini_pill: PanelContainer
var _goals_mini_ring: _MiniGoalRingWidget
var _goals_mini_btn: Button

# Zone 3: Left-Center Vertical RuleToolbar + Floating Lane Subbar
var _rule_vbox: VBoxContainer
var _tool_btns: Dictionary = {}
var _lane_subbar: PanelContainer
var _lane_sub_btns: Dictionary = {}

# Zone 4: Bottom-Left PrimaryButtons (Overview & Trucks)
var _bottom_left_row: HBoxContainer
var _overview_btn: Button
var _trucks_btn: Button
var _route_hint_pill: PanelContainer
var _route_hint_lbl: Label

# Zone 5: Bottom-Right Strip (OverlayBar + Bell/Options + DayClock + SpeedControls)
var _overlay_track: PanelContainer
var _overlay_btns: Dictionary = {}
var _overlay_card: PanelContainer
var _overlay_card_title: Label
var _overlay_card_desc: Label
var _overlay_card_body: VBoxContainer

var _right_ctrl_row: HBoxContainer
var _bell_btn: Button
var _bell_icon: _BellWidget
var _clock_btn: Button
var _clock_icon: _SunMoonWidget
var _clock_lbl: Label
var _speed_btns: Dictionary = {}

var _day_popover: PanelContainer
var _day_hour_lbl: Label
var _day_slider: HSlider
var _day_run_chk: CheckBox
var _day_dark_chk: CheckBox

# Contextual Left Inspector (FactoryPanel / Junction / Road / Offers)
var _inspector_panel: PanelContainer
var _inspector_title: Label
var _inspector_status_pill: PanelContainer
var _inspector_status_lbl: Label
var _inspector_sub: Label
var _inspector_scroll: ScrollContainer
var _inspector_body: VBoxContainer
var _fac_show_incoming: bool = false
var _fac_swap_route_id: String = ""
var _fac_swap_target_model: String = "freighter"

# Centered Wide Modal (Overview / Trucks / Maps / Settings)
var _modal_panel: PanelContainer
var _modal_title: Label
var _modal_summary: Label
var _modal_graph: _CashGraphWidget
var _modal_tabs: TabContainer
var _tab_routes_vbox: VBoxContainer
var _tab_trucks_vbox: VBoxContainer
var _tab_maps_vbox: VBoxContainer
var _tab_opts_vbox: VBoxContainer
var _overview_swap_route_id: String = ""

# Floating Toast Banner
var _banner_panel: PanelContainer
var _banner_label: Label
var _banner_timer: float = 0.0

var _ui_refresh_timer: float = 0.0
var _last_win_size := Vector2i.ZERO
var _last_vp_size := Vector2.ZERO

func setup(sim_engine: SimEngine, view_node: MapView25D) -> void:
	layer = 15
	sim = sim_engine
	map_view = view_node
	sim.day_clock_01 = 0.375 # 09:00 default morning light
	sim.banner_notify.connect(_on_sim_banner)

	if ResourceLoader.exists("res://gui/theme.tres"):
		_theme_light = load("res://gui/theme.tres") as Theme
	if ResourceLoader.exists("res://gui/theme_dark.tres"):
		_theme_dark = load("res://gui/theme_dark.tres") as Theme
	if ResourceLoader.exists("res://assets/ui/title_logo.png"):
		_logo_tex = load("res://assets/ui/title_logo.png") as Texture2D
	if ResourceLoader.exists("res://gui/theme_studies/fonts/Jost-Variable.ttf"):
		_ui_font = load("res://gui/theme_studies/fonts/Jost-Variable.ttf") as Font
	else:
		_ui_font = ThemeDB.fallback_font

	_build_shell()
	_apply_styles()
	_layout_responsive()
	refresh_top_bar()
	_refresh_goals_panel()

func _status_col(key: StringName, fallback: Color) -> Color:
	var th: Theme = _root.theme if _root and _root.theme else _theme_light
	if th != null and th.has_color(key, &"Status"):
		return th.get_color(key, &"Status")
	return fallback

func _build_shell() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _theme_light != null:
		_root.theme = _theme_light
	add_child(_root)

	# === ZONE 1: TOP-CENTER MONEY DISPLAY PILL ===
	_money_pill = PanelContainer.new()
	_root.add_child(_money_pill)

	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 10)
	money_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_money_pill.add_child(money_row)

	_crest_widget = _CrestWidget.new()
	_crest_widget.custom_minimum_size = Vector2(22, 26)
	money_row.add_child(_crest_widget)

	_town_btn = Button.new()
	_town_btn.theme_type_variation = &"QuietButton"
	_town_btn.focus_mode = Control.FOCUS_NONE
	_town_btn.text = "Karesidenan Madiun ▾"
	_town_btn.pressed.connect(func(): open_drawer("maps"))
	money_row.add_child(_town_btn)

	var vsep := VSeparator.new()
	money_row.add_child(vsep)

	_cash_btn = Button.new()
	_cash_btn.flat = true
	_cash_btn.focus_mode = Control.FOCUS_NONE
	_cash_btn.add_theme_font_size_override("font_size", 22)
	_cash_btn.text = "$3,500"
	_cash_btn.pressed.connect(func(): open_drawer("routes"))
	money_row.add_child(_cash_btn)

	_profit_lbl = Label.new()
	_profit_lbl.theme_type_variation = &"MonoLabel"
	_profit_lbl.text = "▲ +$0 / min"
	money_row.add_child(_profit_lbl)

	# === ZONE 2: TOP-RIGHT GOALS PANEL & MINI PILL ===
	_goals_card = PanelContainer.new()
	_goals_card.theme_type_variation = &"WindowPanel"
	_root.add_child(_goals_card)

	var g_col := VBoxContainer.new()
	g_col.add_theme_constant_override("separation", 6)
	_goals_card.add_child(g_col)

	var g_head := HBoxContainer.new()
	g_head.add_theme_constant_override("separation", 6)
	g_col.add_child(g_head)

	var g_titles := VBoxContainer.new()
	g_titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g_titles.add_theme_constant_override("separation", 1)
	g_head.add_child(g_titles)

	_goals_header_lbl = Label.new()
	_goals_header_lbl.add_theme_font_size_override("font_size", 13)
	_goals_header_lbl.clip_text = true
	_goals_header_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_goals_header_lbl.text = "GOALS FOR REGION 2"
	g_titles.add_child(_goals_header_lbl)

	_goals_sub_lbl = Label.new()
	_goals_sub_lbl.theme_type_variation = &"CaptionLabel"
	_goals_sub_lbl.add_theme_font_size_override("font_size", 11)
	_goals_sub_lbl.clip_text = true
	_goals_sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_goals_sub_lbl.text = "Deliveries to any market count"
	g_titles.add_child(_goals_sub_lbl)

	var collapse_btn := Button.new()
	collapse_btn.theme_type_variation = &"QuietButton"
	collapse_btn.focus_mode = Control.FOCUS_NONE
	collapse_btn.text = "−"
	collapse_btn.custom_minimum_size = Vector2(28, 26)
	collapse_btn.pressed.connect(func():
		_goals_collapsed = true
		_layout_responsive()
	)
	g_head.add_child(collapse_btn)

	_goals_rings_row = HBoxContainer.new()
	_goals_rings_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_goals_rings_row.add_theme_constant_override("separation", 8)
	g_col.add_child(_goals_rings_row)

	_goals_hold_lbl = Label.new()
	_goals_hold_lbl.theme_type_variation = &"CaptionLabel"
	_goals_hold_lbl.add_theme_font_size_override("font_size", 11)
	_goals_hold_lbl.text = "Meet every goal at once for 30 s"
	g_col.add_child(_goals_hold_lbl)

	_goals_hold_bar = ProgressBar.new()
	_goals_hold_bar.min_value = 0.0
	_goals_hold_bar.max_value = SimEngine.HOLD_REQUIRED_SEC
	_goals_hold_bar.show_percentage = false
	_goals_hold_bar.custom_minimum_size = Vector2(0, 7)
	g_col.add_child(_goals_hold_bar)

	# Mini pill when collapsed or in Portrait mode
	_goals_mini_pill = PanelContainer.new()
	_goals_mini_pill.visible = false
	_root.add_child(_goals_mini_pill)

	var gm_row := HBoxContainer.new()
	gm_row.add_theme_constant_override("separation", 6)
	_goals_mini_pill.add_child(gm_row)

	_goals_mini_ring = _MiniGoalRingWidget.new()
	_goals_mini_ring.custom_minimum_size = Vector2(22, 22)
	gm_row.add_child(_goals_mini_ring)

	_goals_mini_btn = Button.new()
	_goals_mini_btn.theme_type_variation = &"QuietButton"
	_goals_mini_btn.focus_mode = Control.FOCUS_NONE
	_goals_mini_btn.text = "Region 2 ▾"
	_goals_mini_btn.pressed.connect(func():
		var vp := get_viewport().get_visible_rect().size
		if vp.x < vp.y:
			open_drawer("goals")
		else:
			_goals_collapsed = false
			_layout_responsive()
	)
	gm_row.add_child(_goals_mini_btn)

	# === ZONE 3: LEFT-CENTER VERTICAL RULE TOOLBAR ===
	_rule_vbox = VBoxContainer.new()
	_rule_vbox.add_theme_constant_override("separation", 6)
	_root.add_child(_rule_vbox)

	var rule_specs := [
		["yield", "Yield"],
		["close_street", "Stop"],
		["lanes_add", "Lanes"],
		["roundabout", "Roundabout"],
		["lights", "Lights"],
		["offers_ui", "Roads"],
	]
	for spec in rule_specs:
		var tid := String(spec[0])
		var tlbl := String(spec[1])
		var tb := Button.new()
		tb.theme_type_variation = &"ToolButton"
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.custom_minimum_size = Vector2(68, 58)
		tb.set_meta(&"sfx", "") # Handled explicitly for tool_select / tool_deselect
		tb.pressed.connect(func(): _on_rule_card_tapped(tid))
		var face := _ToolCardFace.new()
		face.tool_id = tid
		face.caption = tlbl
		face.font_ref = _ui_font
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		tb.add_child(face)
		_tool_btns[tid] = tb
		_rule_vbox.add_child(tb)

	# Floating Lane Mode Subbar when Lanes is active
	_lane_subbar = PanelContainer.new()
	_lane_subbar.theme_type_variation = &"SegmentTrack"
	_lane_subbar.visible = false
	_root.add_child(_lane_subbar)

	var lsub_row := HBoxContainer.new()
	lsub_row.add_theme_constant_override("separation", 3)
	_lane_subbar.add_child(lsub_row)

	for lspec in [["lanes_add", "+ Add lane"], ["lanes_remove", "− Remove lane"], ["one_way", "One-way"], ["close_street", "Close street"]]:
		var lid := String(lspec[0])
		var sb := Button.new()
		sb.theme_type_variation = &"SegmentButton"
		sb.toggle_mode = true
		sb.focus_mode = Control.FOCUS_NONE
		sb.text = String(lspec[1])
		sb.custom_minimum_size = Vector2(0, 36)
		sb.pressed.connect(func():
			map_view.active_tool = lid
			_sync_tool_highlights()
			tool_changed.emit(lid)
		)
		_lane_sub_btns[lid] = sb
		lsub_row.add_child(sb)

	# === ZONE 4: BOTTOM-LEFT PRIMARY BUTTONS (Overview & Trucks) ===
	_bottom_left_row = HBoxContainer.new()
	_bottom_left_row.add_theme_constant_override("separation", 8)
	_root.add_child(_bottom_left_row)

	_overview_btn = Button.new()
	_overview_btn.theme_type_variation = &"PrimaryButton"
	_overview_btn.focus_mode = Control.FOCUS_NONE
	_overview_btn.text = "Overview"
	_overview_btn.custom_minimum_size = Vector2(104, 46)
	_overview_btn.pressed.connect(func():
		if current_drawer == "routes":
			close_drawer()
		else:
			open_drawer("routes")
	)
	_bottom_left_row.add_child(_overview_btn)

	_trucks_btn = Button.new()
	_trucks_btn.theme_type_variation = &"PrimaryButton"
	_trucks_btn.focus_mode = Control.FOCUS_NONE
	_trucks_btn.text = "Trucks"
	_trucks_btn.custom_minimum_size = Vector2(88, 46)
	_trucks_btn.pressed.connect(func():
		if current_drawer == "trucks":
			close_drawer()
		else:
			open_drawer("trucks")
	)
	_bottom_left_row.add_child(_trucks_btn)

	# Route tap-to-connect helper pill
	_route_hint_pill = PanelContainer.new()
	_route_hint_pill.visible = false
	_root.add_child(_route_hint_pill)

	var rh_row := HBoxContainer.new()
	rh_row.add_theme_constant_override("separation", 8)
	_route_hint_pill.add_child(rh_row)

	_route_hint_lbl = Label.new()
	_route_hint_lbl.text = "Tap destination building to open route"
	rh_row.add_child(_route_hint_lbl)

	var rh_cancel := Button.new()
	rh_cancel.theme_type_variation = &"QuietButton"
	rh_cancel.focus_mode = Control.FOCUS_NONE
	rh_cancel.text = "Cancel"
	rh_cancel.pressed.connect(func(): _on_toolbar_pressed("pan"))
	rh_row.add_child(rh_cancel)

	# === ZONE 5: BOTTOM-RIGHT OVERLAY BAR + BELL + DAY CLOCK + SPEED CONTROLS ===
	_overlay_track = PanelContainer.new()
	_overlay_track.theme_type_variation = &"SegmentTrack"
	_root.add_child(_overlay_track)

	var ov_row := HBoxContainer.new()
	ov_row.add_theme_constant_override("separation", 2)
	_overlay_track.add_child(ov_row)

	for ov_id in ["routes", "traffic", "flow", "buildings", "demand"]:
		var m_id := String(ov_id)
		var ob := Button.new()
		ob.theme_type_variation = &"SegmentButton"
		ob.toggle_mode = true
		ob.focus_mode = Control.FOCUS_NONE
		ob.custom_minimum_size = Vector2(38, 38)
		ob.pressed.connect(func(): _toggle_overlay_mode(m_id))
		var ic := _OverlayIconFace.new()
		ic.mode_id = m_id
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ob.add_child(ic)
		_overlay_btns[m_id] = ob
		ov_row.add_child(ob)

	_overlay_card = PanelContainer.new()
	_overlay_card.theme_type_variation = &"WindowPanel"
	_overlay_card.visible = false
	_overlay_card.custom_minimum_size = Vector2(270, 0)
	_root.add_child(_overlay_card)

	var ovc_col := VBoxContainer.new()
	ovc_col.add_theme_constant_override("separation", 6)
	_overlay_card.add_child(ovc_col)

	var ovc_head := HBoxContainer.new()
	ovc_col.add_child(ovc_head)
	_overlay_card_title = Label.new()
	_overlay_card_title.theme_type_variation = &"CardTitleLabel"
	_overlay_card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ovc_head.add_child(_overlay_card_title)

	var ovc_close := Button.new()
	ovc_close.theme_type_variation = &"QuietButton"
	ovc_close.focus_mode = Control.FOCUS_NONE
	ovc_close.text = "×"
	ovc_close.pressed.connect(func(): _toggle_overlay_mode(map_view.overlay_mode))
	ovc_head.add_child(ovc_close)

	_overlay_card_desc = Label.new()
	_overlay_card_desc.theme_type_variation = &"CaptionLabel"
	_overlay_card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_card_desc.custom_minimum_size = Vector2(238, 0)
	ovc_col.add_child(_overlay_card_desc)

	_overlay_card_body = VBoxContainer.new()
	_overlay_card_body.add_theme_constant_override("separation", 4)
	ovc_col.add_child(_overlay_card_body)

	# Right Control Row: Bell/Options + DayClock + Speed Pills
	_right_ctrl_row = HBoxContainer.new()
	_right_ctrl_row.add_theme_constant_override("separation", 6)
	_root.add_child(_right_ctrl_row)

	_bell_btn = Button.new()
	_bell_btn.theme_type_variation = &"ToolButton"
	_bell_btn.focus_mode = Control.FOCUS_NONE
	_bell_btn.custom_minimum_size = Vector2(44, 46)
	_bell_btn.pressed.connect(func():
		if _bell_icon.has_alert:
			_jump_broken_route()
		elif current_drawer == "settings":
			close_drawer()
		else:
			open_drawer("settings")
	)
	_bell_icon = _BellWidget.new()
	_bell_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bell_btn.add_child(_bell_icon)
	_right_ctrl_row.add_child(_bell_btn)

	_clock_btn = Button.new()
	_clock_btn.theme_type_variation = &"ToolButton"
	_clock_btn.focus_mode = Control.FOCUS_NONE
	_clock_btn.custom_minimum_size = Vector2(88, 46)
	_clock_btn.pressed.connect(func():
		_day_popover.visible = not _day_popover.visible
		if sim.sfx:
			sim.sfx.play_ui("panel_open" if _day_popover.visible else "panel_close")
	)
	var clk_face := HBoxContainer.new()
	clk_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	clk_face.alignment = BoxContainer.ALIGNMENT_CENTER
	clk_face.add_theme_constant_override("separation", 5)
	clk_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_btn.add_child(clk_face)

	_clock_icon = _SunMoonWidget.new()
	_clock_icon.custom_minimum_size = Vector2(18, 18)
	clk_face.add_child(_clock_icon)

	_clock_lbl = Label.new()
	_clock_lbl.theme_type_variation = &"MonoLabel"
	_clock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_lbl.text = "09:00"
	clk_face.add_child(_clock_lbl)
	_right_ctrl_row.add_child(_clock_btn)

	for sp in [0, 1, 2, 4]:
		var sb := Button.new()
		sb.theme_type_variation = &"ToolButton"
		sb.toggle_mode = true
		sb.focus_mode = Control.FOCUS_NONE
		sb.custom_minimum_size = Vector2(44, 46)
		sb.text = "||" if sp == 0 else ("%dx" % sp)
		sb.set_meta(&"sfx", "")
		sb.pressed.connect(func(): _set_speed(sp))
		_speed_btns[sp] = sb
		_right_ctrl_row.add_child(sb)

	# Day & Night Popover Card (DayClock._panel)
	_day_popover = PanelContainer.new()
	_day_popover.theme_type_variation = &"WindowPanel"
	_day_popover.visible = false
	_day_popover.custom_minimum_size = Vector2(280, 0)
	_root.add_child(_day_popover)

	var dp_col := VBoxContainer.new()
	dp_col.add_theme_constant_override("separation", 8)
	_day_popover.add_child(dp_col)

	var dp_head := HBoxContainer.new()
	dp_col.add_child(dp_head)
	var dp_title := Label.new()
	dp_title.theme_type_variation = &"CardTitleLabel"
	dp_title.text = "Day and night"
	dp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dp_head.add_child(dp_title)
	var dp_close := Button.new()
	dp_close.theme_type_variation = &"QuietButton"
	dp_close.focus_mode = Control.FOCUS_NONE
	dp_close.text = "×"
	dp_close.pressed.connect(func(): _day_popover.visible = false)
	dp_head.add_child(dp_close)

	var hr_row := HBoxContainer.new()
	dp_col.add_child(hr_row)
	var hr_cap := Label.new()
	hr_cap.text = "Time of day"
	hr_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr_row.add_child(hr_cap)
	_day_hour_lbl = Label.new()
	_day_hour_lbl.theme_type_variation = &"MonoLabel"
	_day_hour_lbl.text = "09:00"
	hr_row.add_child(_day_hour_lbl)

	_day_slider = HSlider.new()
	_day_slider.min_value = 0.0
	_day_slider.max_value = 24.0
	_day_slider.step = 0.25
	_day_slider.value = 9.0
	_day_slider.value_changed.connect(func(v: float):
		sim.day_clock_01 = fposmod(v / 24.0, 1.0)
		sim.night_mode = (v < 5.3 or v > 18.8)
		map_view._static_dirty = true
		refresh_top_bar()
	)
	dp_col.add_child(_day_slider)

	_day_run_chk = CheckBox.new()
	_day_run_chk.focus_mode = Control.FOCUS_NONE
	_day_run_chk.text = "Time passes automatically"
	_day_run_chk.toggled.connect(func(on: bool): sim.auto_day_night = on)
	dp_col.add_child(_day_run_chk)

	_day_dark_chk = CheckBox.new()
	_day_dark_chk.focus_mode = Control.FOCUS_NONE
	_day_dark_chk.text = "Dark Sticker UI theme"
	_day_dark_chk.toggled.connect(func(on: bool):
		dark_mode = on
		_apply_styles()
		theme_toggled.emit(dark_mode)
	)
	dp_col.add_child(_day_dark_chk)

	# === LEFT-DOCKED CONTEXTUAL INSPECTOR (FactoryPanel / Junction / Road / Offers) ===
	_inspector_panel = PanelContainer.new()
	_inspector_panel.theme_type_variation = &"WindowPanel"
	_inspector_panel.visible = false
	_root.add_child(_inspector_panel)

	var ins_col := VBoxContainer.new()
	ins_col.add_theme_constant_override("separation", 8)
	_inspector_panel.add_child(ins_col)

	var ins_head := HBoxContainer.new()
	ins_head.add_theme_constant_override("separation", 8)
	ins_col.add_child(ins_head)

	_inspector_title = Label.new()
	_inspector_title.theme_type_variation = &"CardTitleLabel"
	_inspector_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_title.clip_text = true
	ins_head.add_child(_inspector_title)

	_inspector_status_pill = PanelContainer.new()
	_inspector_status_pill.visible = false
	ins_head.add_child(_inspector_status_pill)
	_inspector_status_lbl = Label.new()
	_inspector_status_lbl.add_theme_font_size_override("font_size", 12)
	_inspector_status_pill.add_child(_inspector_status_lbl)

	var ins_close := Button.new()
	ins_close.theme_type_variation = &"ToolButton"
	ins_close.focus_mode = Control.FOCUS_NONE
	ins_close.text = "×"
	ins_close.custom_minimum_size = Vector2(36, 36)
	ins_close.pressed.connect(func(): close_drawer())
	ins_head.add_child(ins_close)

	_inspector_sub = Label.new()
	_inspector_sub.theme_type_variation = &"CaptionLabel"
	_inspector_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ins_col.add_child(_inspector_sub)

	_inspector_scroll = ScrollContainer.new()
	_inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ins_col.add_child(_inspector_scroll)

	_inspector_body = VBoxContainer.new()
	_inspector_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_body.add_theme_constant_override("separation", 8)
	_inspector_scroll.add_child(_inspector_body)

	# === CENTERED WIDE OVERVIEW MODAL (Overview / Trucks / Maps / Options) ===
	_modal_panel = PanelContainer.new()
	_modal_panel.theme_type_variation = &"WindowPanel"
	_modal_panel.visible = false
	_root.add_child(_modal_panel)

	var mod_col := VBoxContainer.new()
	mod_col.add_theme_constant_override("separation", 8)
	_modal_panel.add_child(mod_col)

	var mod_head := HBoxContainer.new()
	mod_head.add_theme_constant_override("separation", 12)
	mod_col.add_child(mod_head)

	_modal_title = Label.new()
	_modal_title.theme_type_variation = &"HeaderLabel"
	_modal_title.clip_text = true
	_modal_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_title.text = "Overview"
	mod_head.add_child(_modal_title)

	_modal_summary = Label.new()
	_modal_summary.theme_type_variation = &"MonoLabel"
	_modal_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_summary.size_flags_stretch_ratio = 2.2
	_modal_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_summary.clip_text = true
	mod_head.add_child(_modal_summary)

	var mod_close := Button.new()
	mod_close.theme_type_variation = &"ToolButton"
	mod_close.focus_mode = Control.FOCUS_NONE
	mod_close.text = "×"
	mod_close.custom_minimum_size = Vector2(36, 36)
	mod_close.pressed.connect(func(): close_drawer())
	mod_head.add_child(mod_close)

	_modal_graph = _CashGraphWidget.new()
	_modal_graph.font_ref = _ui_font
	_modal_graph.custom_minimum_size = Vector2(0, 92)
	mod_col.add_child(_modal_graph)

	_modal_tabs = TabContainer.new()
	_modal_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mod_col.add_child(_modal_tabs)

	_tab_routes_vbox = _make_tab_scroll("Routes")
	_tab_trucks_vbox = _make_tab_scroll("Trucks")
	_tab_maps_vbox = _make_tab_scroll("Maps (7)")
	_tab_opts_vbox = _make_tab_scroll("Options")

	_modal_tabs.tab_changed.connect(func(idx: int):
		if idx == 0:
			current_drawer = "routes"
		elif idx == 1:
			current_drawer = "trucks"
		elif idx == 2:
			current_drawer = "maps"
		elif idx == 3:
			current_drawer = "settings"
		_populate_modal_tabs()
	)

	# === FLOATING TOAST BANNER ===
	_banner_panel = PanelContainer.new()
	_banner_panel.visible = false
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner_panel)

	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_panel.add_child(_banner_label)

	_sync_tool_highlights()
	_sync_speed_highlights()

func _make_tab_scroll(tab_title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_title
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_modal_tabs.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	sc.add_child(vb)
	return vb

func _apply_styles() -> void:
	if _root == null:
		return
	if dark_mode and _theme_dark != null:
		_root.theme = _theme_dark
	elif _theme_light != null:
		_root.theme = _theme_light
	if _day_dark_chk != null:
		_day_dark_chk.set_pressed_no_signal(dark_mode)
	_sync_tool_highlights()
	_sync_speed_highlights()
	refresh_top_bar()
	_refresh_goals_panel()

func _layout_responsive() -> void:
	if _root == null or get_tree() == null:
		return

	# Switch root content_scale_size cleanly between Landscape (1152x648) and Portrait (480x960)
	var win_sz: Vector2i = get_tree().root.size
	if win_sz.x > 0 and win_sz.y > 0 and win_sz != _last_win_size:
		_last_win_size = win_sz
		var target_scale := Vector2i(480, 960) if win_sz.x < win_sz.y else Vector2i(1152, 648)
		if get_tree().root.content_scale_size != target_scale:
			get_tree().root.content_scale_size = target_scale

	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1152, 648)
	_last_vp_size = vp

	var pad_l: float = 14.0
	var pad_r: float = 14.0
	var pad_t: float = 12.0
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

	var is_portrait: bool = vp.x < vp.y

	# 1. Top-Center MoneyDisplay
	_money_pill.reset_size()
	var mp_sz: Vector2 = _money_pill.get_combined_minimum_size()
	mp_sz.x = clampf(mp_sz.x, 280.0, vp.x - pad_l - pad_r)
	mp_sz.y = maxf(46.0, mp_sz.y)
	if is_portrait:
		_money_pill.position = Vector2(pad_l, pad_t)
		_money_pill.size = Vector2(vp.x - pad_l - pad_r, 46.0)
	else:
		_money_pill.position = Vector2((vp.x - mp_sz.x) * 0.5, pad_t)
		_money_pill.size = mp_sz

	# Route hint pill right under MoneyDisplay
	_route_hint_pill.reset_size()
	var rh_sz: Vector2 = _route_hint_pill.get_combined_minimum_size()
	_route_hint_pill.position = Vector2((vp.x - rh_sz.x) * 0.5, _money_pill.position.y + _money_pill.size.y + 6.0)
	_route_hint_pill.size = rh_sz

	# 2. Top-Right GoalsPanel vs Mini Pill
	if is_portrait:
		_goals_card.visible = false
		_goals_mini_pill.visible = true
		_goals_mini_pill.reset_size()
		var gm_sz := _goals_mini_pill.get_combined_minimum_size()
		_goals_mini_pill.position = Vector2(vp.x - pad_r - gm_sz.x, _money_pill.position.y + _money_pill.size.y + 6.0)
		_goals_mini_pill.size = gm_sz
	else:
		_goals_card.visible = not _goals_collapsed
		_goals_mini_pill.visible = _goals_collapsed
		if _goals_card.visible:
			var gc_w: float = 276.0
			_goals_card.reset_size()
			var gc_h: float = maxf(138.0, _goals_card.get_combined_minimum_size().y)
			_goals_card.position = Vector2(vp.x - pad_r - gc_w - 4.0, pad_t)
			_goals_card.size = Vector2(gc_w, gc_h)
		else:
			_goals_mini_pill.reset_size()
			var gm_sz2 := _goals_mini_pill.get_combined_minimum_size()
			_goals_mini_pill.position = Vector2(vp.x - pad_r - gm_sz2.x - 4.0, pad_t)
			_goals_mini_pill.size = gm_sz2

	# 3. Left-Center Vertical RuleToolbar
	for k in _tool_btns.keys():
		var tb: Button = _tool_btns[k]
		tb.custom_minimum_size = Vector2(58, 48) if is_portrait else Vector2(72, 56)
	_rule_vbox.reset_size()
	var rv_sz: Vector2 = _rule_vbox.get_combined_minimum_size()
	if is_portrait:
		_rule_vbox.visible = not _inspector_panel.visible and not _modal_panel.visible
		_rule_vbox.position = Vector2(pad_l, _money_pill.position.y + _money_pill.size.y + 10.0)
	else:
		_rule_vbox.visible = not _modal_panel.visible
		_rule_vbox.position = Vector2(pad_l, maxf(pad_t + 54.0, (vp.y - rv_sz.y) * 0.5 - 12.0))
	_rule_vbox.size = rv_sz

	_lane_subbar.reset_size()
	var ls_sz := _lane_subbar.get_combined_minimum_size()
	_lane_subbar.position = Vector2(_rule_vbox.position.x + rv_sz.x + 8.0, _rule_vbox.position.y + 110.0)
	_lane_subbar.size = ls_sz

	# 4 & 5. Bottom-Left (Overview/Trucks) & Bottom-Right (OverlayBar + DayClock + SpeedControls)
	_overview_btn.custom_minimum_size = Vector2(82, 42) if is_portrait else Vector2(104, 46)
	_trucks_btn.custom_minimum_size = Vector2(72, 42) if is_portrait else Vector2(88, 46)
	_bottom_left_row.reset_size()
	var bl_sz := _bottom_left_row.get_combined_minimum_size()
	_bottom_left_row.position = Vector2(pad_l, vp.y - pad_b - bl_sz.y)
	_bottom_left_row.size = bl_sz

	_clock_btn.visible = not is_portrait
	for sp_k in _speed_btns.keys():
		(_speed_btns[sp_k] as Button).custom_minimum_size = Vector2(38, 42) if is_portrait else Vector2(44, 46)
	_bell_btn.custom_minimum_size = Vector2(40, 42) if is_portrait else Vector2(44, 46)

	_right_ctrl_row.reset_size()
	var rc_sz := _right_ctrl_row.get_combined_minimum_size()
	_right_ctrl_row.position = Vector2(vp.x - pad_r - rc_sz.x - 4.0, vp.y - pad_b - rc_sz.y)
	_right_ctrl_row.size = rc_sz

	_overlay_track.reset_size()
	var ov_sz := _overlay_track.get_combined_minimum_size()
	if is_portrait:
		_overlay_track.position = Vector2(vp.x - pad_r - ov_sz.x - 4.0, _right_ctrl_row.position.y - ov_sz.y - 6.0)
	else:
		_overlay_track.position = Vector2(_right_ctrl_row.position.x - ov_sz.x - 14.0, vp.y - pad_b - ov_sz.y)
	_overlay_track.size = ov_sz

	_overlay_card.reset_size()
	var ovc_sz := _overlay_card.get_combined_minimum_size()
	ovc_sz.x = clampf(ovc_sz.x, 260.0, minf(284.0, vp.x - pad_l - pad_r))
	ovc_sz.y = clampf(ovc_sz.y, 76.0, 260.0)
	_overlay_card.position = Vector2(maxf(pad_l, _overlay_track.position.x + _overlay_track.size.x - ovc_sz.x), _overlay_track.position.y - ovc_sz.y - 8.0)
	_overlay_card.size = ovc_sz

	_day_popover.reset_size()
	var dp_sz := _day_popover.get_combined_minimum_size()
	_day_popover.position = Vector2(vp.x - pad_r - dp_sz.x - 4.0, _right_ctrl_row.position.y - dp_sz.y - 8.0)
	_day_popover.size = dp_sz

	# 6. Inspector Panel (FactoryPanel docked left in Landscape like game_trucks.webp; bottom sheet in Portrait!)
	if is_portrait:
		var sheet_h: float = clampf(vp.y * 0.62, 340.0, vp.y - 160.0)
		_inspector_panel.position = Vector2(pad_l, _overlay_track.position.y - sheet_h - 8.0)
		_inspector_panel.size = Vector2(vp.x - pad_l - pad_r - 4.0, sheet_h)
	else:
		var ins_x: float = _rule_vbox.position.x + rv_sz.x + 10.0
		var ins_w: float = minf(396.0, vp.x * 0.40)
		var ins_h: float = _bottom_left_row.position.y - pad_t - 10.0
		_inspector_panel.position = Vector2(ins_x, pad_t)
		_inspector_panel.size = Vector2(ins_w, maxf(260.0, ins_h))

	# 7. Centered Wide Overview Modal (matching game_routes.webp!)
	_modal_summary.visible = not is_portrait
	if is_portrait:
		var mod_h: float = vp.y - (_money_pill.position.y + _money_pill.size.y) - (_bottom_left_row.size.y + pad_b) - 18.0
		_modal_panel.position = Vector2(pad_l, _money_pill.position.y + _money_pill.size.y + 8.0)
		_modal_panel.size = Vector2(vp.x - pad_l - pad_r - 4.0, maxf(320.0, mod_h))
		_modal_graph.custom_minimum_size = Vector2(0, 68)
	else:
		var mod_w: float = minf(980.0, vp.x - pad_l - pad_r - 24.0)
		var mod_top: float = _money_pill.position.y + _money_pill.size.y + 10.0
		var mod_bot: float = _bottom_left_row.position.y - 10.0
		_modal_panel.position = Vector2((vp.x - mod_w) * 0.5, mod_top)
		_modal_panel.size = Vector2(mod_w, maxf(280.0, mod_bot - mod_top))
		_modal_graph.custom_minimum_size = Vector2(0, 88)

	# 8. Toast Banner
	var bw: float = minf(420.0, vp.x - pad_l - pad_r - 4.0)
	_banner_panel.position = Vector2((vp.x - bw) * 0.5, _money_pill.position.y + _money_pill.size.y + 8.0)
	_banner_panel.size = Vector2(bw, 36.0)

func _process(delta: float) -> void:
	if sim == null:
		return
	var win_sz: Vector2i = get_tree().root.size
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if win_sz != _last_win_size or vp != _last_vp_size:
		_layout_responsive()

	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner_panel.visible = false

	_ui_refresh_timer += delta
	if _ui_refresh_timer >= 0.35:
		_ui_refresh_timer = 0.0
		refresh_top_bar()
		_refresh_goals_panel()
		if _modal_panel.visible:
			_refresh_modal_header_and_graph()
		elif _inspector_panel.visible and current_drawer == "facility":
			_update_facility_live_widgets()

func show_toast_banner(msg: String, duration: float = 2.6) -> void:
	if msg == "" or (_modal_panel != null and _modal_panel.visible):
		return
	_banner_label.text = msg
	_banner_panel.visible = true
	_banner_timer = duration

func _on_sim_banner(title: String, subtitle: String, _accent: Color) -> void:
	show_toast_banner("%s — %s" % [title, subtitle], 3.8)

func refresh_top_bar() -> void:
	if sim == null or _root == null:
		return
	_crest_widget.map_id = sim.current_map_id
	_crest_widget.queue_redraw()

	var map_nm := String(sim.map_def.get("name", "Karesidenan Madiun"))
	var paren_idx: int = map_nm.find(" (")
	if paren_idx > 0:
		map_nm = map_nm.substr(0, paren_idx)
	map_nm = map_nm.replace(" Terpadu", "")
	var is_portrait: bool = get_viewport().get_visible_rect().size.x < get_viewport().get_visible_rect().size.y
	if is_portrait and map_nm.length() > 16:
		map_nm = map_nm.replace("Kabupaten ", "Kab. ")
	_town_btn.text = map_nm + " ▾"

	_cash_btn.text = GameCatalog.fmt_cash(sim.cash)

	var net_min: int = sim.get_revenue_per_min() - sim.get_upkeep_per_min()
	if net_min >= 0:
		_profit_lbl.text = "▲ +%s / min" % GameCatalog.fmt_cash(net_min)
		_profit_lbl.add_theme_color_override("font_color", _status_col(&"good", Color("2C7442")))
	else:
		_profit_lbl.text = "▼ %s / min" % GameCatalog.fmt_cash(net_min)
		_profit_lbl.add_theme_color_override("font_color", _status_col(&"bad", Color("C2412F")))

	# DayClock HH:MM readout
	var total_mins: int = int(round(fposmod(sim.day_clock_01, 1.0) * 1440.0)) % 1440
	var hh: int = total_mins / 60
	var mm: int = (total_mins % 60) / 15 * 15
	var clk_txt := "%02d:%02d" % [hh, mm]
	_clock_lbl.text = clk_txt
	_day_hour_lbl.text = clk_txt
	_clock_icon.is_night = sim.night_mode
	_clock_icon.queue_redraw()
	_day_run_chk.set_pressed_no_signal(sim.auto_day_night)

	# Broken route alert indicator on Bell button
	var has_broken: bool = false
	for rt in sim.routes:
		if String(rt["brokenReason"]) != "":
			has_broken = true
			break
	if _bell_icon.has_alert != has_broken:
		_bell_icon.has_alert = has_broken
		_bell_icon.queue_redraw()

	_route_hint_pill.visible = (map_view != null and map_view.active_tool == "route")
	if _route_hint_pill.visible:
		if map_view.route_draft_from_id == "":
			_route_hint_lbl.text = "Tap origin building on map"
		else:
			var fnm: String = String(sim.facility_map.get(map_view.route_draft_from_id, {}).get("name", "Origin"))
			_route_hint_lbl.text = "From %s → tap destination building" % fnm

func _refresh_goals_panel() -> void:
	if sim == null or _goals_rings_row == null:
		return
	var greg: Dictionary = sim.get_active_goal_region()
	if greg.is_empty():
		return

	var unl: bool = bool(greg["unlocked"])
	var r_num: int = int(greg["index"]) + 1
	if not unl:
		_goals_header_lbl.text = "GOALS FOR REGION %d" % r_num
		_goals_sub_lbl.text = "%s · Deliveries to market" % String(greg["name"])
	else:
		_goals_header_lbl.text = "BOOMTOWN LEVEL %d" % (sim.boomtown_level + 1)
		_goals_sub_lbl.text = "Whole region · Deliveries to market"

	var goals: Array = greg["goals"]
	while _goals_rings_row.get_child_count() > goals.size():
		var ch := _goals_rings_row.get_child(_goals_rings_row.get_child_count() - 1)
		_goals_rings_row.remove_child(ch)
		ch.queue_free()
	while _goals_rings_row.get_child_count() < goals.size():
		var gw := _GoalRingWidget.new()
		gw.font_ref = _ui_font
		_goals_rings_row.add_child(gw)

	var sum_pct: float = 0.0
	for i in range(goals.size()):
		var g: Dictionary = goals[i]
		var gw := _goals_rings_row.get_child(i) as _GoalRingWidget
		gw.good_id = String(g["good"])
		gw.cur_rate = float(g.get("currentPerMin", 0.0))
		gw.target_rate = float(g["targetPerMin"])
		gw.ink_col = _status_col(&"text", Color("23242B"))
		gw.muted_col = _status_col(&"text_muted", Color("625F57"))
		gw.good_col = _status_col(&"good", Color("2C7442"))
		gw.queue_redraw()
		sum_pct += clampf(gw.cur_rate / maxf(0.1, gw.target_rate), 0.0, 1.0)

	var hold_s: float = float(greg.get("holdSeconds", 0.0))
	_goals_hold_bar.value = hold_s
	if hold_s > 0.2:
		_goals_hold_lbl.text = "Holding all goals: %d / %d s" % [int(round(hold_s)), int(SimEngine.HOLD_REQUIRED_SEC)]
	else:
		_goals_hold_lbl.text = "Meet every goal at once for %d s" % int(SimEngine.HOLD_REQUIRED_SEC)

	var avg_pct: float = sum_pct / float(maxi(1, goals.size()))
	_goals_mini_ring.progress = avg_pct
	_goals_mini_ring.queue_redraw()
	_goals_mini_btn.text = ("Region %d (%d%%) ▾" % [r_num, int(round(avg_pct * 100.0))]) if not unl else ("Boomtown Lv.%d ▾" % (sim.boomtown_level + 1))

# === SPEED, OVERLAY & RULE TOOLBAR CONTROLS ===

func _set_speed(sp: int) -> void:
	var was: int = sim.speed_multiplier
	sim.speed_multiplier = sp
	if sim.sfx:
		if sp == 0:
			sim.sfx.play_ui("pause")
		elif was == 0:
			sim.sfx.play_ui("resume")
		else:
			var pitches := {1: 1.0, 2: 1.12, 4: 1.26}
			sim.sfx.play_ui("speed", float(pitches.get(sp, 1.0)))
	_sync_speed_highlights()

func _sync_speed_highlights() -> void:
	if sim == null:
		return
	for k in _speed_btns.keys():
		var sb: Button = _speed_btns[k]
		sb.set_pressed_no_signal(int(k) == sim.speed_multiplier)

func _toggle_overlay_mode(mode_id: String) -> void:
	if map_view.overlay_mode == mode_id:
		map_view.overlay_mode = "none"
	else:
		map_view.overlay_mode = mode_id
	overlay_changed.emit(map_view.overlay_mode)
	_sync_overlay_bar()

func _sync_overlay_bar() -> void:
	var cur := map_view.overlay_mode if map_view else "none"
	for k in _overlay_btns.keys():
		var b: Button = _overlay_btns[k]
		b.set_pressed_no_signal(String(k) == cur)
		b.get_child(0).queue_redraw()

	_overlay_card.visible = (cur != "none")
	if not _overlay_card.visible:
		return

	for ch in _overlay_card_body.get_children():
		ch.queue_free()

	var titles := {
		"routes": "Trucks & Routes",
		"traffic": "Traffic",
		"flow": "Goods flow",
		"buildings": "Buildings",
		"demand": "Demand"
	}
	var descs := {
		"routes": "Active logistics routes across Karesidenan Madiun. Untick a route to dim its trucks.",
		"traffic": "Every road colored by how long trucks are held up.",
		"flow": "Every supply link, as wide as the goods it delivers per minute.",
		"buildings": "Live operational status of every supplier, factory, station, and harbour.",
		"demand": "Current delivery rate per minute against the next regional goal."
	}
	_overlay_card_title.text = String(titles.get(cur, "Overlay"))
	_overlay_card_desc.text = String(descs.get(cur, ""))

	if cur == "traffic":
		_overlay_card_body.add_child(_make_legend_chip(Color("4FB35E"), "Flowing smoothly"))
		_overlay_card_body.add_child(_make_legend_chip(Color("F2C230"), "Slow / queuing"))
		_overlay_card_body.add_child(_make_legend_chip(Color("C8323A"), "Jammed"))
	elif cur == "buildings":
		_overlay_card_body.add_child(_make_legend_chip(Color("3E9E50"), "Working"))
		_overlay_card_body.add_child(_make_legend_chip(Color("E09A2A"), "Waiting for input"))
		_overlay_card_body.add_child(_make_legend_chip(Color("D0393F"), "Output storage full"))
	elif cur == "demand":
		_overlay_card_body.add_child(_make_legend_chip(Color("3E9E50"), "Goal met"))
		_overlay_card_body.add_child(_make_legend_chip(Color("E09A2A"), "Halfway there"))
		_overlay_card_body.add_child(_make_legend_chip(Color("D0393F"), "Below target"))
	elif cur == "routes":
		for i in range(mini(6, sim.routes.size())):
			var rt: Dictionary = sim.routes[i]
			var rtid := String(rt["id"])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var chk := CheckBox.new()
			chk.focus_mode = Control.FOCUS_NONE
			chk.set_pressed_no_signal(not map_view.hidden_route_ids.has(rtid))
			chk.toggled.connect(func(on: bool):
				if on:
					map_view.hidden_route_ids.erase(rtid)
				else:
					map_view.hidden_route_ids[rtid] = true
			)
			row.add_child(chk)
			var bar := ColorRect.new()
			bar.color = rt["color"]
			bar.custom_minimum_size = Vector2(5, 18)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(bar)
			var lbl := Label.new()
			lbl.text = String(rt["name"])
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = true
			row.add_child(lbl)
			_overlay_card_body.add_child(row)
	_layout_responsive()

func _make_legend_chip(col: Color, txt: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	var c := ColorRect.new()
	c.color = col
	c.custom_minimum_size = Vector2(20, 8)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(c)
	var l := Label.new()
	l.text = txt
	r.add_child(l)
	return r

func _on_rule_card_tapped(tid: String) -> void:
	if tid == "offers_ui":
		if current_drawer == "offers":
			close_drawer()
		else:
			open_drawer("offers")
		_sync_tool_highlights()
		return

	var cur := map_view.active_tool
	var is_lane_group: bool = tid == "lanes_add" and cur in ["lanes_add", "lanes_remove", "one_way"]
	if cur == tid or is_lane_group:
		if sim.sfx:
			sim.sfx.play_ui("tool_deselect")
		_on_toolbar_pressed("pan")
	else:
		if sim.sfx:
			sim.sfx.play_ui("tool_select")
		_on_toolbar_pressed(tid)

func _on_toolbar_pressed(tid: String) -> void:
	if tid == "fleet_ui":
		open_drawer("routes")
		return
	if tid == "offers_ui":
		open_drawer("offers")
		return
	if tid == "overlays_ui":
		_toggle_overlay_mode("routes")
		return
	if tid == "settings_ui":
		open_drawer("settings")
		return

	map_view.active_tool = tid
	if tid != "route":
		map_view.route_draft_from_id = ""
	_sync_tool_highlights()
	refresh_top_bar()
	_layout_responsive()
	tool_changed.emit(tid)

func _sync_tool_highlights() -> void:
	if map_view == null:
		return
	var cur := map_view.active_tool
	var lane_active: bool = cur in ["lanes_add", "lanes_remove", "one_way"]
	for k in _tool_btns.keys():
		var tb: Button = _tool_btns[k]
		if k == "lanes_add":
			tb.set_pressed_no_signal(lane_active)
		elif k == "offers_ui":
			tb.set_pressed_no_signal(current_drawer == "offers")
		else:
			tb.set_pressed_no_signal(cur == String(k))
		tb.get_child(0).queue_redraw()

	_lane_subbar.visible = lane_active
	for lk in _lane_sub_btns.keys():
		(_lane_sub_btns[lk] as Button).set_pressed_no_signal(cur == String(lk))

func _jump_broken_route() -> void:
	for rt in sim.routes:
		if String(rt["brokenReason"]) != "":
			var f_from: Dictionary = sim.facility_map.get(String(rt["fromFacilityId"]), {})
			if not f_from.is_empty():
				focus_world_requested.emit(f_from["pos"])
			map_view.selected_route_id = String(rt["id"])
			open_drawer("routes")
			show_toast_banner("Broken route: " + String(rt["brokenReason"]), 3.2)
			return

# === DRAWER & MODAL ROUTING ===

func open_drawer(kind: String) -> void:
	var was_open: bool = current_drawer != ""
	current_drawer = kind
	_day_popover.visible = false

	if kind in ["routes", "trucks", "maps", "settings"]:
		_inspector_panel.visible = false
		_banner_panel.visible = false
		_modal_panel.visible = true
		var tab_idx: int = 0
		if kind == "trucks":
			tab_idx = 1
		elif kind == "maps":
			tab_idx = 2
		elif kind == "settings":
			tab_idx = 3
		_modal_tabs.current_tab = tab_idx
		_refresh_modal_header_and_graph()
		_populate_modal_tabs()
	else:
		_modal_panel.visible = false
		_inspector_panel.visible = true
		_populate_drawer()

	if sim.sfx and not was_open:
		sim.sfx.play_ui("panel_open")
	_sync_tool_highlights()
	_layout_responsive()

func close_drawer() -> void:
	var was_open: bool = current_drawer != ""
	current_drawer = ""
	_inspector_panel.visible = false
	_modal_panel.visible = false
	if sim.sfx and was_open:
		sim.sfx.play_ui("panel_close")
	_sync_tool_highlights()
	_layout_responsive()

func _populate_drawer() -> void:
	if current_drawer in ["routes", "trucks", "maps", "settings"]:
		_refresh_modal_header_and_graph()
		_populate_modal_tabs()
		return

	for ch in _inspector_body.get_children():
		ch.queue_free()
	_inspector_status_pill.visible = false

	if current_drawer == "facility":
		_build_authentic_factory_panel()
	elif current_drawer == "junction":
		_build_authentic_junction_panel()
	elif current_drawer == "road":
		_build_authentic_road_panel()
	elif current_drawer == "offers":
		_build_authentic_offers_panel()
	elif current_drawer == "goals":
		_build_authentic_goals_sheet()

# === 1. AUTHENTIC FACTORY PANEL (matching game_trucks.webp!) ===

var _live_fac_ring: _FactoryFlowRingWidget = null

func _build_authentic_factory_panel() -> void:
	var fid := map_view.selected_facility_id
	if not sim.facility_map.has(fid):
		close_drawer()
		return
	var f: Dictionary = sim.facility_map[fid]
	var kind_s := String(f["kind"])

	_inspector_title.text = String(f["name"])

	# Status Pill (• Running / • Waiting / • Output full)
	_inspector_status_pill.visible = true
	var stalled := String(f["stalledReason"])
	var pill_sb := StyleBoxFlat.new()
	pill_sb.set_corner_radius_all(999)
	pill_sb.content_margin_left = 10.0
	pill_sb.content_margin_right = 10.0
	pill_sb.content_margin_top = 2.0
	pill_sb.content_margin_bottom = 2.0
	if stalled == "output_full":
		pill_sb.bg_color = Color(0.76, 0.25, 0.18, 0.16)
		_inspector_status_lbl.text = "• Output full"
		_inspector_status_lbl.add_theme_color_override("font_color", _status_col(&"bad", Color("C2412F")))
	elif stalled == "missing_input":
		pill_sb.bg_color = Color(0.88, 0.60, 0.16, 0.20)
		_inspector_status_lbl.text = "• Waiting for input"
		_inspector_status_lbl.add_theme_color_override("font_color", _status_col(&"warn", Color("8F5A00")))
	else:
		pill_sb.bg_color = Color(0.17, 0.45, 0.26, 0.15)
		_inspector_status_lbl.text = "• Working"
		_inspector_status_lbl.add_theme_color_override("font_color", _status_col(&"good", Color("2C7442")))
	_inspector_status_pill.add_theme_stylebox_override("panel", pill_sb)

	# Subtitle recipe + Madiun heritage note
	var recipe_s := String(f["localContext"])
	if f["outputGood"] != null:
		var out_g := String(f["outputGood"])
		var gdef: Dictionary = GameCatalog.GOODS[out_g]
		if kind_s == "supplier":
			recipe_s = "Supplier · Produces %s (%s) · %s" % [String(gdef["name"]), String(gdef["local"]), recipe_s]
		elif kind_s == "factory":
			var in_parts: Array[String] = []
			for inp in gdef["inputs"]:
				in_parts.append("%d %s" % [int(inp["qty"]), String(GameCatalog.GOODS[String(inp["good"])]["name"])])
			recipe_s = "%s → %s (%s)" % [" + ".join(in_parts), String(gdef["name"]), String(gdef["local"])]
	_inspector_sub.text = recipe_s

	# Custom In -> Circular Ring -> Out Widget (matching _y0ar3x8pESeh in factory_panel.gd!)
	_live_fac_ring = null
	if f["outputGood"] != null:
		var ring_w := _FactoryFlowRingWidget.new()
		ring_w.font_ref = _ui_font
		_live_fac_ring = ring_w
		_inspector_body.add_child(ring_w)
		_update_facility_live_widgets()
	else:
		var hub_card := PanelContainer.new()
		hub_card.theme_type_variation = &"CardPanel"
		var hub_lbl := Label.new()
		hub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hub_lbl.text = "Regional Market / Export Hub — Pays full cash value on every delivered cargo unit and counts toward Regional Unlock Goals!"
		hub_card.add_child(hub_lbl)
		_inspector_body.add_child(hub_card)

	_inspector_body.add_child(HSeparator.new())

	# Royal-Blue SectionLabel: Upgrades + 2-Column Card Grid!
	var up_head := HBoxContainer.new()
	var up_badge := Label.new()
	up_badge.theme_type_variation = &"SectionLabel"
	up_badge.text = "Upgrades"
	up_head.add_child(up_badge)
	_inspector_body.add_child(up_head)

	var up_grid := GridContainer.new()
	up_grid.columns = 2
	up_grid.add_theme_constant_override("h_separation", 8)
	up_grid.add_theme_constant_override("v_separation", 8)
	_inspector_body.add_child(up_grid)

	for up in sim.get_facility_upgrades(f):
		var track := String(up["track"])
		var locked := String(up["locked"])
		var ucard := PanelContainer.new()
		ucard.theme_type_variation = &"CardPanel"
		ucard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ucol := VBoxContainer.new()
		ucol.add_theme_constant_override("separation", 5)
		ucard.add_child(ucol)

		var utop := HBoxContainer.new()
		utop.add_theme_constant_override("separation", 5)
		ucol.add_child(utop)

		var uic := _UpgradeIconWidget.new()
		uic.track = track
		uic.col = _status_col(&"text_muted", Color("625F57"))
		utop.add_child(uic)

		var unm := Label.new()
		unm.text = _short_upgrade_title(track)
		unm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unm.clip_text = true
		utop.add_child(unm)

		var dots := _LevelDotsWidget.new()
		dots.level = int(up["level"])
		dots.max_level = mini(8, int(up["max"]))
		dots.accent_col = _status_col(&"accent", Color("8F5F00"))
		dots.ink_col = _status_col(&"text", Color("23242B"))
		utop.add_child(dots)

		var udesc := Label.new()
		udesc.theme_type_variation = &"CaptionLabel"
		udesc.add_theme_font_size_override("font_size", 11)
		udesc.text = String(up["desc"])
		udesc.clip_text = true
		ucol.add_child(udesc)

		var ubtn := Button.new()
		ubtn.theme_type_variation = &"PrimaryButton"
		ubtn.focus_mode = Control.FOCUS_NONE
		ubtn.custom_minimum_size = Vector2(0, 36)
		ubtn.text = locked if locked != "" else GameCatalog.fmt_cash(int(up["price"]))
		ubtn.disabled = (locked != "")
		ubtn.set_meta(&"sfx", "")
		ubtn.pressed.connect(func():
			if sim.buy_facility_upgrade(fid, track):
				if sim.sfx:
					sim.sfx.play_ui("purchase")
				_populate_drawer()
		)
		ucol.add_child(ubtn)
		up_grid.add_child(ucard)

	_inspector_body.add_child(HSeparator.new())

	# Royal-Blue SectionLabel: Routes + SegmentTrack (Outgoing | Incoming)
	var out_rts: Array = []
	var in_rts: Array = []
	for rt in sim.routes:
		if String(rt["fromFacilityId"]) == fid:
			out_rts.append(rt)
		elif String(rt["toFacilityId"]) == fid:
			in_rts.append(rt)

	var rt_head := HBoxContainer.new()
	rt_head.add_theme_constant_override("separation", 8)
	var rt_badge := Label.new()
	rt_badge.theme_type_variation = &"SectionLabel"
	rt_badge.text = "Routes"
	rt_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rt_head.add_child(rt_badge)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt_head.add_child(spacer)

	var seg_track := PanelContainer.new()
	seg_track.theme_type_variation = &"SegmentTrack"
	var seg_row := HBoxContainer.new()
	seg_row.add_theme_constant_override("separation", 2)
	seg_track.add_child(seg_row)

	var btn_out := Button.new()
	btn_out.theme_type_variation = &"SegmentButton"
	btn_out.toggle_mode = true
	btn_out.focus_mode = Control.FOCUS_NONE
	btn_out.text = "Outgoing %d" % out_rts.size()
	btn_out.set_pressed_no_signal(not _fac_show_incoming)
	btn_out.pressed.connect(func():
		_fac_show_incoming = false
		_populate_drawer()
	)
	seg_row.add_child(btn_out)

	var btn_in := Button.new()
	btn_in.theme_type_variation = &"SegmentButton"
	btn_in.toggle_mode = true
	btn_in.focus_mode = Control.FOCUS_NONE
	btn_in.text = "Incoming %d" % in_rts.size()
	btn_in.set_pressed_no_signal(_fac_show_incoming)
	btn_in.pressed.connect(func():
		_fac_show_incoming = true
		_populate_drawer()
	)
	seg_row.add_child(btn_in)
	rt_head.add_child(seg_track)
	_inspector_body.add_child(rt_head)

	# "+ Open route to..." button
	if f["outputGood"] != null and not _fac_show_incoming:
		var open_rt_btn := Button.new()
		open_rt_btn.focus_mode = Control.FOCUS_NONE
		open_rt_btn.text = "+ Open route from " + String(f["name"])
		open_rt_btn.custom_minimum_size = Vector2(0, 38)
		open_rt_btn.pressed.connect(func():
			map_view.active_tool = "route"
			map_view.route_draft_from_id = fid
			close_drawer()
			refresh_top_bar()
			show_toast_banner("Tap destination factory, station, or harbour on the map!", 3.0)
		)
		_inspector_body.add_child(open_rt_btn)

	var shown_rts: Array = in_rts if _fac_show_incoming else out_rts
	if shown_rts.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.theme_type_variation = &"CaptionLabel"
		empty_lbl.text = "No incoming routes yet." if _fac_show_incoming else "No outgoing routes yet. Tap '+ Open route' above!"
		_inspector_body.add_child(empty_lbl)
	else:
		for rt in shown_rts:
			_inspector_body.add_child(_build_route_card_for_factory(rt, _fac_show_incoming))

func _short_upgrade_title(track: String) -> String:
	var m := {
		"speed": "Speed", "rate": "Rate", "expand": "Expand",
		"buffer": "Buffers", "bays": "Bays", "wideGate": "Wide gate",
		"exitRoad": "Exit road", "trainLength": "Train", "shipSize": "Ship", "timetable": "Timetable"
	}
	return String(m.get(track, track.capitalize()))

func _build_route_card_for_factory(rt: Dictionary, is_incoming: bool) -> PanelContainer:
	var rtid := String(rt["id"])
	var m_id := String(rt["truckModel"])
	var m_def: Dictionary = GameCatalog.TRUCKS[m_id]
	var cnt: int = (rt["activeTruckIds"] as Array).size()
	var g_id: String = String(rt["goodFilter"])
	if g_id == "any":
		var ff: Dictionary = sim.facility_map.get(String(rt["fromFacilityId"]), {})
		if ff.get("outputGood", null) != null:
			g_id = String(ff["outputGood"])

	var peer_fac: Dictionary = sim.facility_map.get(String(rt["fromFacilityId"] if is_incoming else rt["toFacilityId"]), {})
	var peer_nm := ("from " if is_incoming else "to ") + String(peer_fac.get("name", "Hub"))

	var rcard := PanelContainer.new()
	rcard.theme_type_variation = &"CardPanel"
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 6)
	rcard.add_child(rcol)

	# Row 1: [GoodGlyph | to Destination | MiniTruck × N]
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 6)
	rcol.add_child(r1)

	if GameCatalog.GOODS.has(g_id):
		var gg := _GoodGlyphWidget.new()
		gg.good_id = g_id
		gg.custom_minimum_size = Vector2(18, 18)
		r1.add_child(gg)

	var dest_lbl := Label.new()
	dest_lbl.text = peer_nm
	dest_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dest_lbl.clip_text = true
	r1.add_child(dest_lbl)

	var mt_top := _MiniTruckWidget.new()
	mt_top.model_id = m_id
	mt_top.cab_col = rt["color"]
	mt_top.good_id = g_id if GameCatalog.GOODS.has(g_id) else ""
	r1.add_child(mt_top)

	var cnt_top := Label.new()
	cnt_top.theme_type_variation = &"MonoLabel"
	cnt_top.text = "× %d" % cnt
	r1.add_child(cnt_top)

	# Row 2: [-]  N × [Model Swap Pill ▾]  [+ $price PrimaryButton]
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	rcol.add_child(r2)

	var minus_b := Button.new()
	minus_b.theme_type_variation = &"ToolButton"
	minus_b.focus_mode = Control.FOCUS_NONE
	minus_b.text = "−"
	minus_b.custom_minimum_size = Vector2(34, 34)
	minus_b.disabled = (cnt <= 0)
	minus_b.set_meta(&"sfx", "sell")
	minus_b.pressed.connect(func():
		sim.remove_truck_from_route(rtid)
		_populate_drawer()
	)
	r2.add_child(minus_b)

	var swap_toggle := Button.new()
	swap_toggle.focus_mode = Control.FOCUS_NONE
	swap_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swap_toggle.custom_minimum_size = Vector2(0, 34)
	swap_toggle.text = "%d × %s ▾" % [cnt, String(m_def["name"])]
	swap_toggle.pressed.connect(func():
		_fac_swap_route_id = "" if _fac_swap_route_id == rtid else rtid
		if _fac_swap_target_model == m_id:
			_fac_swap_target_model = "freighter" if m_id != "freighter" else "hauler"
		_populate_drawer()
	)
	r2.add_child(swap_toggle)

	var nxt_p: int = sim.get_next_truck_price(m_id)
	var plus_b := Button.new()
	plus_b.theme_type_variation = &"PrimaryButton"
	plus_b.focus_mode = Control.FOCUS_NONE
	plus_b.custom_minimum_size = Vector2(88, 34)
	plus_b.text = "+ " + GameCatalog.fmt_cash(nxt_p)
	plus_b.set_meta(&"sfx", "purchase")
	plus_b.pressed.connect(func():
		sim.add_truck_to_route(rtid, false)
		_populate_drawer()
	)
	r2.add_child(plus_b)

	# Expandable Swap All Trucks Net-Cost Calculator (matching game_trucks.webp!)
	if _fac_swap_route_id == rtid:
		var sw_cap := Label.new()
		sw_cap.theme_type_variation = &"CaptionLabel"
		sw_cap.text = "Swap all %d trucks to another model" % cnt
		rcol.add_child(sw_cap)

		var m_grid := GridContainer.new()
		m_grid.columns = 2
		m_grid.add_theme_constant_override("h_separation", 6)
		m_grid.add_theme_constant_override("v_separation", 6)
		rcol.add_child(m_grid)

		for cand_m in GameCatalog.TRUCK_ORDER:
			var cdef: Dictionary = GameCatalog.TRUCKS[cand_m]
			var has_lic: bool = sim.unlocked_licenses.has(cand_m)
			var mb := Button.new()
			mb.toggle_mode = true
			mb.focus_mode = Control.FOCUS_NONE
			mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mb.custom_minimum_size = Vector2(0, 46)
			mb.set_pressed_no_signal(_fac_swap_target_model == cand_m)
			var tag := "current" if cand_m == m_id else (("%d km/h · %d slots" % [int(cdef["speed_kmh"]), int(cdef["slot_cap"])]) if has_lic else ("Licence " + GameCatalog.fmt_cash(int(cdef["license_price"]))))
			mb.text = "%s\n%s" % [String(cdef["name"]), tag]
			mb.pressed.connect(func():
				_fac_swap_target_model = cand_m
				_populate_drawer()
			)
			m_grid.add_child(mb)

		if _fac_swap_target_model != m_id:
			var q: Dictionary = sim.quote_route_model_swap(rtid, _fac_swap_target_model)
			var net: int = int(q["netCost"])
			var quote_row := HBoxContainer.new()
			quote_row.add_theme_constant_override("separation", 8)
			var qlbl := Label.new()
			qlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			qlbl.text = ("Net -" + GameCatalog.fmt_cash(net)) if net >= 0 else ("Refund +" + GameCatalog.fmt_cash(-net))
			qlbl.add_theme_color_override("font_color", _status_col(&"good" if net <= 0 else &"text", Color("23242B")))
			quote_row.add_child(qlbl)

			var exec_swap := Button.new()
			exec_swap.theme_type_variation = &"PrimaryButton"
			exec_swap.focus_mode = Control.FOCUS_NONE
			exec_swap.text = "Swap all %d" % cnt
			exec_swap.pressed.connect(func():
				if sim.apply_route_model_swap(rtid, _fac_swap_target_model):
					if sim.sfx:
						sim.sfx.play_ui("purchase")
					_fac_swap_route_id = ""
					_populate_drawer()
			)
			quote_row.add_child(exec_swap)
			rcol.add_child(quote_row)

	# Bottom quick actions: Edit path / Waypoints & Retire
	var r3 := HBoxContainer.new()
	var wp_btn := Button.new()
	wp_btn.theme_type_variation = &"QuietButton"
	wp_btn.focus_mode = Control.FOCUS_NONE
	wp_btn.text = "Edit path (%d WP)" % (rt["waypoints"] as Array).size()
	wp_btn.pressed.connect(func():
		map_view.selected_route_id = rtid
		show_toast_banner("Route highlighted! Tap any road junction to add/remove a waypoint.", 3.0)
	)
	r3.add_child(wp_btn)

	var spc := Control.new()
	spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r3.add_child(spc)

	var ret_btn := Button.new()
	ret_btn.theme_type_variation = &"QuietButton"
	ret_btn.focus_mode = Control.FOCUS_NONE
	ret_btn.text = "Retire"
	ret_btn.add_theme_color_override("font_color", _status_col(&"bad", Color("C2412F")))
	ret_btn.set_meta(&"sfx", "remove")
	ret_btn.pressed.connect(func():
		sim.delete_route(rtid)
		_populate_drawer()
	)
	r3.add_child(ret_btn)
	rcol.add_child(r3)

	return rcard

func _update_facility_live_widgets() -> void:
	if _live_fac_ring == null or not is_instance_valid(_live_fac_ring):
		return
	var fid := map_view.selected_facility_id
	if not sim.facility_map.has(fid):
		return
	var f: Dictionary = sim.facility_map[fid]
	if f["outputGood"] == null:
		return
	var out_g := String(f["outputGood"])
	var gdef: Dictionary = GameCatalog.GOODS[out_g]
	var cap: int = sim.get_capacity_slots(f)
	_live_fac_ring.is_source = (String(f["kind"]) == "supplier")
	_live_fac_ring.out_good = out_g
	_live_fac_ring.out_count = int(f["outputBuffer"])
	_live_fac_ring.out_cap = cap
	_live_fac_ring.progress = float(f.get("prodProgress", 0.0))
	_live_fac_ring.ring_col = ItIcons.color_of(out_g)
	_live_fac_ring.ink_col = _status_col(&"text", Color("23242B"))
	_live_fac_ring.muted_col = _status_col(&"text_muted", Color("625F57"))
	_live_fac_ring.panel_col = _status_col(&"panel", Color("FAF7EE"))
	_live_fac_ring.bad_col = _status_col(&"bad", Color("C2412F"))
	if _live_fac_ring.is_source:
		_live_fac_ring.rate_text = "%d / min" % sim.get_supplier_rate_per_min(f)
		_live_fac_ring.inputs_data = []
	else:
		_live_fac_ring.rate_text = "%.1f / min" % sim.get_factory_output_per_min(f)
		var rows: Array = []
		for inp in gdef["inputs"]:
			var ig := String(inp["good"])
			rows.append({
				"good": ig,
				"need": int(inp["qty"]),
				"count": int(f["inputBuffers"].get(ig, 0)),
				"cap": cap
			})
		_live_fac_ring.inputs_data = rows
	_live_fac_ring.update_min_height()
	_live_fac_ring.queue_redraw()

# === 2. AUTHENTIC JUNCTION, ROAD, OFFERS & GOALS INSPECTORS ===

func _build_authentic_junction_panel() -> void:
	var jid := map_view.selected_junction_id
	if not sim.junction_map.has(jid):
		close_drawer()
		return
	var j: Dictionary = sim.junction_map[jid]
	_inspector_title.text = String(j.get("name", "Junction"))
	var lm_txt: String = ("Landmark: " + String(j["landmark"]) + " · ") if j.get("landmark", null) != null else ""
	_inspector_sub.text = "%s%.4f° S, %.4f° E · Control: %s" % [lm_txt, absf(float(j["lat"])), float(j["lon"]), String(j["control"]).to_upper()]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_inspector_body.add_child(row)

	for cspec in [["yield", "Yield ($0)"], ["roundabout", "Roundabout"], ["lights", "Lights ($1k)"]]:
		var cid := String(cspec[0])
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(cspec[1])
		b.pressed.connect(func():
			show_toast_banner(sim.apply_junction_control(jid, cid))
			_populate_drawer()
		)
		row.add_child(b)

	if String(j["control"]) == "lights" and j.has("light"):
		var lt: Dictionary = j["light"]
		var lcard := PanelContainer.new()
		lcard.theme_type_variation = &"CardPanel"
		var lcol := VBoxContainer.new()
		lcol.add_theme_constant_override("separation", 6)
		lcard.add_child(lcol)

		var badge := Label.new()
		badge.theme_type_variation = &"SectionLabel"
		badge.text = "Traffic light timing"
		lcol.add_child(badge)

		var la := Label.new()
		la.text = "Phase A green: %d s" % int(lt["phaseAGreen"])
		lcol.add_child(la)
		var sa := HSlider.new()
		sa.min_value = 4.0
		sa.max_value = 40.0
		sa.step = 1.0
		sa.value = float(lt["phaseAGreen"])
		sa.value_changed.connect(func(v: float):
			lt["phaseAGreen"] = v
			la.text = "Phase A green: %d s" % int(v)
		)
		lcol.add_child(sa)

		var lb := Label.new()
		lb.text = "Phase B green: %d s" % int(lt["phaseBGreen"])
		lcol.add_child(lb)
		var sb := HSlider.new()
		sb.min_value = 4.0
		sb.max_value = 40.0
		sb.step = 1.0
		sb.value = float(lt["phaseBGreen"])
		sb.value_changed.connect(func(v: float):
			lt["phaseBGreen"] = v
			lb.text = "Phase B green: %d s" % int(v)
		)
		lcol.add_child(sb)

		var act_chk := CheckBox.new()
		act_chk.focus_mode = Control.FOCUS_NONE
		act_chk.text = "Actuated gap sensor (switches early when empty)"
		act_chk.set_pressed_no_signal(bool(lt["actuated"]))
		act_chk.toggled.connect(func(on: bool): lt["actuated"] = on)
		lcol.add_child(act_chk)

		var rem := Button.new()
		rem.theme_type_variation = &"QuietButton"
		rem.focus_mode = Control.FOCUS_NONE
		rem.text = "Remove traffic lights (+$500 refund)"
		rem.add_theme_color_override("font_color", _status_col(&"bad", Color("C2412F")))
		rem.pressed.connect(func():
			sim.remove_traffic_lights(jid)
			_populate_drawer()
		)
		lcol.add_child(rem)
		_inspector_body.add_child(lcard)

func _build_authentic_road_panel() -> void:
	var rid := map_view.selected_road_id
	if not sim.road_map.has(rid):
		close_drawer()
		return
	var r: Dictionary = sim.road_map[rid]
	_inspector_title.text = String(r["name"])
	_inspector_sub.text = "Class: %s · %d lanes/dir · Congestion: %d%%" % [
		String(r["roadClass"]).to_upper(), int(r["lanesForward"]), int(round(float(r["congestionEMA"]) * 100.0))
	]

	for act in [
		["+ Add lane (both directions)", func(): show_toast_banner(sim.modify_road_lanes(rid, 1)); _populate_drawer(), true],
		["− Remove lane (50% refund)", func(): show_toast_banner(sim.modify_road_lanes(rid, -1)); _populate_drawer(), false],
		["⇄ Cycle Two-way / One-way ($0)", func(): show_toast_banner(sim.cycle_road_one_way(rid)); _populate_drawer(), false],
		["Reopen street ($0)" if bool(r["closed"]) else "Close street into pedestrian park ($3,200)", func(): show_toast_banner(sim.toggle_close_street(rid)); _populate_drawer(), false],
	]:
		var b := Button.new()
		if bool(act[2]):
			b.theme_type_variation = &"PrimaryButton"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 42)
		b.text = String(act[0])
		b.pressed.connect(act[1] as Callable)
		_inspector_body.add_child(b)

func _build_authentic_offers_panel() -> void:
	_inspector_title.text = "New Roads & Toll Corridors"
	_inspector_sub.text = "Real-world Karesidenan Madiun tollways, ring roads, and JLS southern coastal links:"
	if sim.road_offers.is_empty():
		var none := Label.new()
		none.text = "No extra road projects on this map."
		_inspector_body.add_child(none)
		return
	for off in sim.road_offers:
		var oid := String(off["id"])
		var bought: bool = bool(off["purchased"])
		var reg_ok: bool = sim.unlocked_regions.has(int(off["regionIndex"]))
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanel"
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		card.add_child(col)
		var t := Label.new()
		t.text = String(off["name"])
		col.add_child(t)
		var sub := Label.new()
		sub.theme_type_variation = &"CaptionLabel"
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.text = String(off["subtitle"])
		col.add_child(sub)
		var b := Button.new()
		b.theme_type_variation = &"PrimaryButton"
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = bought or (not reg_ok)
		b.text = "Built" if bought else (("Locked (Region %d)" % (int(off["regionIndex"]) + 1)) if not reg_ok else ("Build " + GameCatalog.fmt_cash(int(off["price"]))))
		b.pressed.connect(func():
			show_toast_banner(sim.purchase_road_offer(oid))
			_populate_drawer()
		)
		col.add_child(b)
		_inspector_body.add_child(card)

func _build_authentic_goals_sheet() -> void:
	_inspector_title.text = "Regional Goals"
	_inspector_sub.text = "Deliver goods to any station, harbour, or market and hold all goals for 30 s:"
	for reg in sim.regions:
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanel"
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		card.add_child(col)
		var unl: bool = bool(reg["unlocked"])
		var hd := Label.new()
		hd.text = "Region %d: %s — %s" % [int(reg["index"]) + 1, String(reg["name"]), "OPEN" if unl else ("HOLD %ds/30s" % int(round(float(reg["holdSeconds"]))))]
		col.add_child(hd)
		for g in reg["goals"]:
			var gid := String(g["good"])
			var gdef: Dictionary = GameCatalog.GOODS[gid]
			var gl := Label.new()
			gl.theme_type_variation = &"CaptionLabel"
			gl.text = "• %s (%s): %.1f / %.1f / min" % [String(gdef["name"]), String(gdef["local"]), float(g.get("currentPerMin", 0.0)), float(g["targetPerMin"])]
			col.add_child(gl)
		var jb := Button.new()
		jb.theme_type_variation = &"QuietButton"
		jb.focus_mode = Control.FOCUS_NONE
		jb.text = "Show on map →"
		jb.pressed.connect(func():
			focus_world_requested.emit(reg["center_vec"])
			close_drawer()
		)
		col.add_child(jb)
		_inspector_body.add_child(card)

# === 3. AUTHENTIC OVERVIEW MODAL (matching game_routes.webp!) ===

func _refresh_modal_header_and_graph() -> void:
	if sim == null or _modal_summary == null:
		return
	var inc: int = sim.get_revenue_per_min()
	var upk: int = sim.get_upkeep_per_min()
	var prof: int = inc - upk
	var p_sign := "+" if prof >= 0 else ""
	_modal_summary.text = "%s   income %s / min · upkeep %s / min · profit %s%s / min   %d trucks" % [
		GameCatalog.fmt_cash(sim.cash),
		GameCatalog.fmt_cash(inc),
		GameCatalog.fmt_cash(upk),
		p_sign, GameCatalog.fmt_cash(prof),
		sim.agents.size()
	]
	_modal_graph.history = sim.cash_history
	_modal_graph.cur_cash = sim.cash
	_modal_graph.line_col = _status_col(&"good", Color("2C7442"))
	_modal_graph.ink_col = _status_col(&"text_muted", Color("625F57"))
	_modal_graph.bg_col = _status_col(&"panel", Color("FAF7EE")).darkened(0.03)
	_modal_graph.queue_redraw()

func _populate_modal_tabs() -> void:
	var tab: int = _modal_tabs.current_tab
	if tab == 0:
		_modal_title.text = "Overview"
		_modal_graph.visible = true
		_build_overview_routes_tab()
	elif tab == 1:
		_modal_title.text = "Trucks & Licences"
		_modal_graph.visible = false
		_build_overview_trucks_tab()
	elif tab == 2:
		_modal_title.text = "Karesidenan Madiun Maps"
		_modal_graph.visible = false
		_build_overview_maps_tab()
	else:
		_modal_title.text = "Android & Options"
		_modal_graph.visible = false
		_build_overview_options_tab()

func _build_overview_routes_tab() -> void:
	for ch in _tab_routes_vbox.get_children():
		ch.queue_free()

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	var hint := Label.new()
	hint.theme_type_variation = &"CaptionLabel"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Open new routes by tapping a building or '+ Open new route'. Swap model trades all trucks on a route in for another."
	top_bar.add_child(hint)

	var new_rt := Button.new()
	new_rt.theme_type_variation = &"PrimaryButton"
	new_rt.focus_mode = Control.FOCUS_NONE
	new_rt.text = "+ Open new route"
	new_rt.pressed.connect(func():
		close_drawer()
		_on_toolbar_pressed("route")
	)
	top_bar.add_child(new_rt)
	_tab_routes_vbox.add_child(top_bar)

	if sim.routes.is_empty():
		var emp := Label.new()
		emp.text = "No active routes yet."
		_tab_routes_vbox.add_child(emp)
		return

	for rt in sim.routes:
		var rtid := String(rt["id"])
		var m_id := String(rt["truckModel"])
		var cnt: int = (rt["activeTruckIds"] as Array).size()
		var g_id := String(rt["goodFilter"])
		if g_id == "any":
			var ff: Dictionary = sim.facility_map.get(String(rt["fromFacilityId"]), {})
			if ff.get("outputGood", null) != null:
				g_id = String(ff["outputGood"])

		var row_card := PanelContainer.new()
		row_card.theme_type_variation = &"CardPanel"
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		row_card.add_child(vbox)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var bar := ColorRect.new()
		bar.color = rt["color"]
		bar.custom_minimum_size = Vector2(6, 26)
		row.add_child(bar)

		if GameCatalog.GOODS.has(g_id):
			var gg := _GoodGlyphWidget.new()
			gg.good_id = g_id
			gg.custom_minimum_size = Vector2(20, 20)
			row.add_child(gg)

		var nm := Label.new()
		var f_from_nm: String = String(sim.facility_map.get(String(rt["fromFacilityId"]), {}).get("name", ""))
		var f_to_nm: String = String(sim.facility_map.get(String(rt["toFacilityId"]), {}).get("name", ""))
		nm.text = "%s → %s" % [f_from_nm, f_to_nm]
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		row.add_child(nm)

		var mt := _MiniTruckWidget.new()
		mt.model_id = m_id
		mt.cab_col = rt["color"]
		mt.good_id = g_id if GameCatalog.GOODS.has(g_id) else ""
		row.add_child(mt)

		var fl_lbl := Label.new()
		fl_lbl.theme_type_variation = &"MonoLabel"
		fl_lbl.text = "× %d" % cnt
		row.add_child(fl_lbl)

		var upk_rt: int = cnt * int(GameCatalog.TRUCKS[m_id]["upkeep_min"])
		var stat_lbl := Label.new()
		stat_lbl.theme_type_variation = &"MonoLabel"
		stat_lbl.text = "-%s/m" % GameCatalog.fmt_cash(upk_rt)
		stat_lbl.add_theme_color_override("font_color", _status_col(&"text_muted", Color("625F57")))
		row.add_child(stat_lbl)

		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 5)
		row.add_child(actions)

		var sw_b := Button.new()
		sw_b.focus_mode = Control.FOCUS_NONE
		sw_b.text = "Swap model"
		sw_b.pressed.connect(func():
			_overview_swap_route_id = "" if _overview_swap_route_id == rtid else rtid
			_build_overview_routes_tab()
		)
		actions.add_child(sw_b)

		var nxt_p: int = sim.get_next_truck_price(m_id)
		var buy_b := Button.new()
		buy_b.theme_type_variation = &"PrimaryButton"
		buy_b.focus_mode = Control.FOCUS_NONE
		buy_b.text = "Buy " + GameCatalog.fmt_cash(nxt_p)
		buy_b.set_meta(&"sfx", "purchase")
		buy_b.pressed.connect(func():
			sim.add_truck_to_route(rtid, false)
			_refresh_modal_header_and_graph()
			_build_overview_routes_tab()
		)
		actions.add_child(buy_b)

		var sell_b := Button.new()
		sell_b.focus_mode = Control.FOCUS_NONE
		sell_b.text = "Sell"
		sell_b.disabled = (cnt <= 0)
		sell_b.set_meta(&"sfx", "sell")
		sell_b.pressed.connect(func():
			sim.remove_truck_from_route(rtid)
			_refresh_modal_header_and_graph()
			_build_overview_routes_tab()
		)
		actions.add_child(sell_b)

		var show_b := Button.new()
		show_b.focus_mode = Control.FOCUS_NONE
		show_b.text = "Show"
		show_b.pressed.connect(func():
			var f0: Dictionary = sim.facility_map.get(String(rt["fromFacilityId"]), {})
			if not f0.is_empty():
				focus_world_requested.emit(f0["pos"])
			map_view.selected_route_id = rtid
			close_drawer()
		)
		actions.add_child(show_b)

		var ret_b := Button.new()
		ret_b.focus_mode = Control.FOCUS_NONE
		ret_b.text = "Retire"
		ret_b.set_meta(&"sfx", "remove")
		ret_b.pressed.connect(func():
			sim.delete_route(rtid)
			_refresh_modal_header_and_graph()
			_build_overview_routes_tab()
		)
		actions.add_child(ret_b)

		if _overview_swap_route_id == rtid:
			var sw_row := HBoxContainer.new()
			sw_row.add_theme_constant_override("separation", 6)
			for cand_m in GameCatalog.TRUCK_ORDER:
				if cand_m == m_id:
					continue
				var q: Dictionary = sim.quote_route_model_swap(rtid, cand_m)
				var net: int = int(q["netCost"])
				var cdef: Dictionary = GameCatalog.TRUCKS[cand_m]
				var sb := Button.new()
				sb.focus_mode = Control.FOCUS_NONE
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.text = "⇄ %s (%s)" % [String(cdef["name"]), ("-" + GameCatalog.fmt_cash(net)) if net >= 0 else ("+" + GameCatalog.fmt_cash(-net))]
				sb.pressed.connect(func():
					if sim.apply_route_model_swap(rtid, cand_m):
						if sim.sfx:
							sim.sfx.play_ui("purchase")
						_overview_swap_route_id = ""
						_refresh_modal_header_and_graph()
						_build_overview_routes_tab()
				)
				sw_row.add_child(sb)
			vbox.add_child(sw_row)

		_tab_routes_vbox.add_child(row_card)

func _build_overview_trucks_tab() -> void:
	for ch in _tab_trucks_vbox.get_children():
		ch.queue_free()

	var is_portrait: bool = get_viewport().get_visible_rect().size.x < get_viewport().get_visible_rect().size.y
	var grid := GridContainer.new()
	grid.columns = 1 if is_portrait else 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_tab_trucks_vbox.add_child(grid)

	for m_id in GameCatalog.TRUCK_ORDER:
		var tdef: Dictionary = GameCatalog.TRUCKS[m_id]
		var unlocked: bool = sim.unlocked_licenses.has(m_id)
		var owned: int = sim.get_owned_count_by_model(m_id)
		var nxt_p: int = sim.get_next_truck_price(m_id)

		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanel"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		card.add_child(col)

		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		col.add_child(head)

		var title := Label.new()
		title.theme_type_variation = &"CardTitleLabel"
		title.text = String(tdef["name"])
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)

		var mt := _MiniTruckWidget.new()
		mt.model_id = m_id
		mt.cab_col = tdef["color"]
		mt.truck_h = 18.0
		head.add_child(mt)

		var sub := Label.new()
		sub.theme_type_variation = &"CaptionLabel"
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.text = String(tdef["subtitle"])
		col.add_child(sub)

		var stats := Label.new()
		stats.theme_type_variation = &"MonoLabel"
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats.text = "%d km/h · %d slots · upkeep $%d/min · owned: %d · next: %s" % [
			int(tdef["speed_kmh"]), int(tdef["slot_cap"]), int(tdef["upkeep_min"]), owned, GameCatalog.fmt_cash(nxt_p)
		]
		col.add_child(stats)

		if unlocked:
			var ok_lbl := Label.new()
			ok_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ok_lbl.text = "✓ Licence active — assign on any route in Overview or Factory panel"
			ok_lbl.add_theme_color_override("font_color", _status_col(&"good", Color("2C7442")))
			col.add_child(ok_lbl)
		else:
			var lic_p: int = int(tdef["license_price"])
			var lb := Button.new()
			lb.theme_type_variation = &"PrimaryButton"
			lb.focus_mode = Control.FOCUS_NONE
			lb.text = "Unlock Licence — " + GameCatalog.fmt_cash(lic_p)
			lb.pressed.connect(func():
				if sim.buy_license(m_id):
					_refresh_modal_header_and_graph()
					_build_overview_trucks_tab()
			)
			col.add_child(lb)

		grid.add_child(card)

func _build_overview_maps_tab() -> void:
	for ch in _tab_maps_vbox.get_children():
		ch.queue_free()

	# Authentic Incremental Traffic Title Logo Banner!
	if _logo_tex != null:
		var logo_box := VBoxContainer.new()
		logo_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		logo_box.alignment = BoxContainer.ALIGNMENT_CENTER
		logo_box.add_theme_constant_override("separation", 2)
		var tex_r := TextureRect.new()
		tex_r.texture = _logo_tex
		tex_r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_r.custom_minimum_size = Vector2(0, 62)
		logo_box.add_child(tex_r)
		var ed_lbl := Label.new()
		ed_lbl.theme_type_variation = &"CaptionLabel"
		ed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ed_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ed_lbl.text = "EDISI KARESIDENAN MADIUN — 7 Peta Dunia Nyata (Geometri WGS84 Asli)"
		logo_box.add_child(ed_lbl)
		_tab_maps_vbox.add_child(logo_box)

	var is_portrait: bool = get_viewport().get_visible_rect().size.x < get_viewport().get_visible_rect().size.y
	var grid := GridContainer.new()
	grid.columns = 1 if is_portrait else 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_tab_maps_vbox.add_child(grid)

	for m in sim.maps_list:
		var mid := String(m["id"])
		var active: bool = (mid == sim.current_map_id)
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanel"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		card.add_child(col)

		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		col.add_child(h)

		var cr := _CrestWidget.new()
		cr.map_id = mid
		cr.custom_minimum_size = Vector2(28, 34)
		h.add_child(cr)

		var tbox := VBoxContainer.new()
		tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := Label.new()
		t.theme_type_variation = &"CardTitleLabel"
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.text = String(m["name"])
		tbox.add_child(t)
		var bdg := Label.new()
		bdg.theme_type_variation = &"CaptionLabel"
		bdg.clip_text = true
		bdg.text = String(m["badge"])
		tbox.add_child(bdg)
		h.add_child(tbox)

		var sub := Label.new()
		sub.theme_type_variation = &"CaptionLabel"
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.text = String(m["subtitle"])
		col.add_child(sub)

		var play_b := Button.new()
		play_b.theme_type_variation = &"PrimaryButton" if not active else &"Button"
		play_b.focus_mode = Control.FOCUS_NONE
		play_b.clip_text = true
		play_b.disabled = active
		play_b.text = "✓ Currently Playing" if active else ("Play " + String(m["name"]))
		play_b.pressed.connect(func():
			close_drawer()
			map_selected.emit(mid)
		)
		col.add_child(play_b)
		grid.add_child(card)

func _build_overview_options_tab() -> void:
	for ch in _tab_opts_vbox.get_children():
		ch.queue_free()

	var p_card := PanelContainer.new()
	p_card.theme_type_variation = &"CardPanel"
	var p_col := VBoxContainer.new()
	p_col.add_theme_constant_override("separation", 8)
	p_card.add_child(p_col)

	var p_lbl := Label.new()
	p_lbl.theme_type_variation = &"CardTitleLabel"
	p_lbl.text = "Android Frame Pacing & GPU Optimization"
	p_col.add_child(p_lbl)

	var seg := PanelContainer.new()
	seg.theme_type_variation = &"SegmentTrack"
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 4)
	seg.add_child(srow)
	for pr in [["battery", "Battery Saver (30 FPS)"], ["balanced", "Balanced (60 FPS)"], ["ultra", "Ultra Smooth (120 FPS)"]]:
		var pid := String(pr[0])
		var b := Button.new()
		b.theme_type_variation = &"SegmentButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = String(pr[1])
		b.set_pressed_no_signal(perf_preset == pid)
		b.pressed.connect(func():
			perf_preset = pid
			perf_preset_changed.emit(pid)
			_build_overview_options_tab()
		)
		srow.add_child(b)
	p_col.add_child(seg)
	_tab_opts_vbox.add_child(p_card)

	var opt_card := PanelContainer.new()
	opt_card.theme_type_variation = &"CardPanel"
	var o_col := VBoxContainer.new()
	o_col.add_theme_constant_override("separation", 8)
	opt_card.add_child(o_col)

	var chk_lht := CheckBox.new()
	chk_lht.focus_mode = Control.FOCUS_NONE
	chk_lht.text = "Left-hand traffic (Indonesian National Road Standard)"
	chk_lht.set_pressed_no_signal(sim.left_hand_traffic)
	chk_lht.toggled.connect(func(on: bool): sim.left_hand_traffic = on)
	o_col.add_child(chk_lht)

	var chk_dark := CheckBox.new()
	chk_dark.focus_mode = Control.FOCUS_NONE
	chk_dark.text = "Dark Sticker UI & Slate Map Theme"
	chk_dark.set_pressed_no_signal(dark_mode)
	chk_dark.toggled.connect(func(on: bool):
		dark_mode = on
		_apply_styles()
		theme_toggled.emit(dark_mode)
	)
	o_col.add_child(chk_dark)

	var chk_sfx := CheckBox.new()
	chk_sfx.focus_mode = Control.FOCUS_NONE
	chk_sfx.text = "Original Incremental Traffic UI Sound Effects (26 WAVs)"
	chk_sfx.set_pressed_no_signal(not sim.sfx.muted)
	chk_sfx.toggled.connect(func(on: bool): sim.sfx.muted = not on)
	o_col.add_child(chk_sfx)

	var rst_btn := Button.new()
	rst_btn.focus_mode = Control.FOCUS_NONE
	rst_btn.text = "Reset Progress on Current Map"
	rst_btn.pressed.connect(func():
		sim.reset_current_map()
		close_drawer()
		show_toast_banner("Map reset to starting state.", 2.5)
	)
	o_col.add_child(rst_btn)
	_tab_opts_vbox.add_child(opt_card)


# ============================================================================
# CUSTOM VECTOR WIDGETS (100% Authentic Incremental Traffic Procedural Controls)
# ============================================================================

class _CrestWidget extends Control:
	var map_id: String = "karisidenan_madiun"
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		ItIcons.draw_town_crest(self, map_id, Rect2(Vector2.ZERO, size))


class _GoodGlyphWidget extends Control:
	var good_id: String = "dot"
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		ItIcons.draw_shape(self, good_id, size * 0.5, minf(size.x, size.y) * 0.90)


class _ToolCardFace extends Control:
	var tool_id: String = "yield"
	var caption: String = "Yield"
	var font_ref: Font
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var b := get_parent() as Button
		var pressed: bool = b != null and b.button_pressed
		var ink := Color("23242B") if pressed else b.get_theme_color(&"font_color", &"ToolButton")
		var r: float = minf(size.x, size.y) * 0.23
		ItIcons.draw_tool_icon(self, tool_id, Vector2(size.x * 0.5, size.y * 0.37), r)
		var f: Font = font_ref if font_ref != null else ThemeDB.fallback_font
		draw_string(f, Vector2(2.0, size.y - 6.0), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4.0, 11, ink)


class _OverlayIconFace extends Control:
	var mode_id: String = "routes"
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var b := get_parent() as Button
		var ink := b.get_theme_color(&"font_pressed_color" if (b and b.button_pressed) else &"font_color", &"SegmentButton")
		ItIcons.draw_overlay_icon(self, mode_id, size * 0.5, ink)


class _SunMoonWidget extends Control:
	var is_night: bool = false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		ItIcons.draw_sun_moon(self, size * 0.5, is_night)


class _BellWidget extends Control:
	var has_alert: bool = false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var b := get_parent() as Button
		var ink := b.get_theme_color(&"font_color", &"ToolButton") if b else Color("23242B")
		ItIcons.draw_bell_icon(self, size * 0.5, ink, has_alert)


class _GoalRingWidget extends Control:
	var good_id: String = "dot"
	var cur_rate: float = 0.0
	var target_rate: float = 4.0
	var font_ref: Font
	var ink_col := Color("23242B")
	var muted_col := Color("625F57")
	var good_col := Color("2C7442")

	func _init() -> void:
		custom_minimum_size = Vector2(54, 70)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 22.0)
		var r: float = 17.5
		var ratio: float = clampf(cur_rate / maxf(0.1, target_rate), 0.0, 1.0)
		var met: bool = cur_rate + 0.05 >= target_rate
		var arc_col: Color = good_col if met else ItIcons.color_of(good_id)

		draw_arc(c, r, 0.0, TAU, 28, Color(ink_col, 0.14), 4.0, true)
		if ratio > 0.01:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * ratio, 28, arc_col, 4.0, true)
		ItIcons.draw_shape(self, good_id, c, 17.0)

		if met:
			var chk_c := c + Vector2(12.5, -12.5)
			draw_circle(chk_c, 6.0, good_col)
			draw_polyline(PackedVector2Array([chk_c + Vector2(-2.8, 0.2), chk_c + Vector2(-0.6, 2.5), chk_c + Vector2(3.2, -2.2)]), Color.WHITE, 1.8, true)

		var f: Font = font_ref if font_ref != null else ThemeDB.fallback_font
		draw_string(f, Vector2(0, 52), "%.1f" % cur_rate, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, good_col if met else ink_col)
		draw_string(f, Vector2(0, 65), "of %d / min" % int(round(target_rate)), HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, muted_col)


class _MiniGoalRingWidget extends Control:
	var progress: float = 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.40
		draw_arc(c, r, 0.0, TAU, 20, Color(0.14, 0.15, 0.18, 0.18), 3.0, true)
		if progress > 0.01:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 20, Color("2C7442"), 3.0, true)


class _UpgradeIconWidget extends Control:
	var track: String = "speed"
	var col := Color("625F57")
	func _init() -> void:
		custom_minimum_size = Vector2(18, 18)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		ItIcons.draw_upgrade_icon(self, track, Vector2.ZERO, col)


class _LevelDotsWidget extends Control:
	var level: int = 0
	var max_level: int = 5
	var accent_col := Color("8F5F00")
	var ink_col := Color("23242B")
	func _init() -> void:
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _get_minimum_size() -> Vector2:
		return Vector2(float(maxi(1, max_level)) * 7.0, 8.0)
	func _draw() -> void:
		for i in range(max_level):
			var c: Color = accent_col if i < level else Color(ink_col, 0.18)
			draw_circle(Vector2(3.5 + float(i) * 7.0, 4.0), 2.5, c)


class _MiniTruckWidget extends Control:
	var model_id: String = "hauler"
	var cab_col := Color("3B82F6")
	var good_id: String = ""
	var truck_h: float = 13.0
	func _init() -> void:
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _get_minimum_size() -> Vector2:
		var tdef: Dictionary = GameCatalog.TRUCKS.get(model_id, GameCatalog.TRUCKS["hauler"])
		var w: float = truck_h * 0.85
		for s in tdef["trailers"]:
			w += maxf(truck_h * 1.05, float(int(s)) * (truck_h * 0.62)) + 2.0
		return Vector2(w + 2.0, truck_h + 2.0)
	func _draw() -> void:
		ItIcons.draw_mini_truck(self, model_id, Vector2(1.0, 1.0), truck_h, cab_col, good_id)


class _FactoryFlowRingWidget extends Control:
	## Authentic port of _y0ar3x8pESeh from original factory_panel.gd!
	const RING_R := 26.0
	const ROW_H := 22.0

	var is_source: bool = false
	var inputs_data: Array = []
	var out_good: String = "dot"
	var out_count: int = 0
	var out_cap: int = 4
	var progress: float = 0.0
	var rate_text: String = "8.0 / min"
	var font_ref: Font
	var ring_col := Color("E0533D")
	var ink_col := Color("23242B")
	var muted_col := Color("625F57")
	var panel_col := Color("FAF7EE")
	var bad_col := Color("C2412F")

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		update_min_height()

	func update_min_height() -> void:
		var n: int = maxi(1, inputs_data.size())
		custom_minimum_size = Vector2(0, maxf(RING_R * 2.0 + 28.0, 22.0 + float(n) * ROW_H))

	func _draw() -> void:
		var f: Font = font_ref if font_ref != null else ThemeDB.fallback_font
		var col_w: float = maxf(60.0, (size.x - RING_R * 2.0 - 52.0) * 0.5)
		var cx: float = size.x * 0.5
		var cy: float = RING_R + 8.0

		var in_head := "Grows" if is_source else "In · small"
		draw_string(f, Vector2(0, 12), in_head, HORIZONTAL_ALIGNMENT_LEFT, col_w, 12, muted_col)

		if is_source:
			ItIcons.draw_shape(self, out_good, Vector2(10, 34), 16.0)
			draw_string(f, Vector2(24, 39), "from its land", HORIZONTAL_ALIGNMENT_LEFT, col_w - 24.0, 12, muted_col)
		else:
			for i in range(inputs_data.size()):
				var d: Dictionary = inputs_data[i]
				_draw_pile_bar(f, Vector2(0, 20.0 + float(i) * ROW_H), col_w, String(d["good"]), int(d["count"]), int(d["cap"]), false)

		draw_string(f, Vector2(col_w + 6.0, cy + 5.0), "→", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, muted_col)
		draw_string(f, Vector2(size.x - col_w - 18.0, cy + 5.0), "→", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, muted_col)

		var rc := Vector2(cx, cy)
		draw_arc(rc, RING_R, 0.0, TAU, 40, Color(ink_col, 0.13), 5.5, true)
		if progress > 0.01:
			draw_arc(rc, RING_R, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 40, ring_col, 5.5, true)
		ItIcons.draw_shape(self, out_good, rc, 20.0)
		draw_string(f, Vector2(cx - 42.0, cy + RING_R + 17.0), rate_text, HORIZONTAL_ALIGNMENT_CENTER, 84.0, 12, muted_col)

		var out_x: float = size.x - col_w
		var out_sz_lbl := "large" if int(GameCatalog.GOODS.get(out_good, {"slots": 1})["slots"]) > 1 else "small"
		draw_string(f, Vector2(out_x, 12), "Out · " + out_sz_lbl, HORIZONTAL_ALIGNMENT_LEFT, col_w, 12, muted_col)
		_draw_pile_bar(f, Vector2(out_x, 20.0), col_w, out_good, out_count, out_cap, true)

	func _draw_pile_bar(f: Font, at: Vector2, w: float, gid: String, cnt: int, cap: int, is_out: bool) -> void:
		ItIcons.draw_shape(self, gid, at + Vector2(8.0, ROW_H * 0.5), 14.0)
		var tw: float = 38.0
		var bar_r := Rect2(at.x + 20.0, at.y + ROW_H * 0.5 - 3.5, maxf(10.0, w - 20.0 - tw), 7.0)
		draw_rect(bar_r, Color(ink_col, 0.13), true)
		var full: bool = is_out and cnt >= cap
		var fill_c: Color = bad_col if full else ink_col
		var ratio: float = clampf(float(cnt) / maxf(1.0, float(cap)), 0.0, 1.0)
		draw_rect(Rect2(bar_r.position, Vector2(bar_r.size.x * ratio, bar_r.size.y)), fill_c, true)
		if cap > 1 and cap <= 15:
			for si in range(1, cap):
				var sx: float = bar_r.position.x + bar_r.size.x * (float(si) / float(cap))
				draw_line(Vector2(sx, bar_r.position.y), Vector2(sx, bar_r.end.y), panel_col, 1.4)
		draw_string(f, Vector2(bar_r.end.x + 3.0, at.y + ROW_H * 0.5 + 4.5), "%d/%d" % [cnt, cap], HORIZONTAL_ALIGNMENT_RIGHT, tw - 3.0, 11, fill_c)


class _CashGraphWidget extends Control:
	## Authentic 5-minute Cash Area Graph from Overview (game_routes.webp)!
	var history: Array[int] = [3500]
	var cur_cash: int = 3500
	var font_ref: Font
	var line_col := Color("2C7442")
	var ink_col := Color("625F57")
	var bg_col := Color("F1ECE0")

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		draw_rect(box, bg_col, true)
		draw_rect(box, Color(ink_col, 0.18), false, 1.2)

		var pts_val: Array[int] = history.duplicate()
		pts_val.append(cur_cash)
		if pts_val.size() < 2:
			pts_val.append(cur_cash)

		var min_v: int = pts_val[0]
		var max_v: int = pts_val[0]
		for v in pts_val:
			min_v = mini(min_v, v)
			max_v = maxi(max_v, v)
		var span: float = maxf(200.0, float(max_v - min_v))

		var pad_l: float = 64.0
		var pad_r: float = 12.0
		var pad_t: float = 10.0
		var pad_b: float = 12.0
		var gw: float = maxf(20.0, size.x - pad_l - pad_r)
		var gh: float = maxf(20.0, size.y - pad_t - pad_b)

		var line_pts := PackedVector2Array()
		var fill_pts := PackedVector2Array()
		fill_pts.append(Vector2(pad_l, pad_t + gh))
		for i in range(pts_val.size()):
			var x: float = pad_l + gw * (float(i) / float(pts_val.size() - 1))
			var y_norm: float = float(pts_val[i] - min_v) / span
			var y: float = pad_t + gh * (1.0 - y_norm)
			var pt := Vector2(x, y)
			line_pts.append(pt)
			fill_pts.append(pt)
		fill_pts.append(Vector2(pad_l + gw, pad_t + gh))

		if fill_pts.size() >= 3:
			draw_colored_polygon(fill_pts, Color(line_col, 0.16))
		if line_pts.size() >= 2:
			draw_polyline(line_pts, line_col, 2.2, true)

		var f: Font = font_ref if font_ref != null else ThemeDB.fallback_font
		draw_string(f, Vector2(6.0, pad_t + 9.0), GameCatalog.fmt_cash(max_v), HORIZONTAL_ALIGNMENT_LEFT, 56.0, 11, ink_col)
		draw_string(f, Vector2(6.0, size.y - 6.0), GameCatalog.fmt_cash(min_v), HORIZONTAL_ALIGNMENT_LEFT, 56.0, 11, ink_col)
		draw_string(f, Vector2(size.x - 68.0, size.y - 6.0), "last 5:00", HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 11, ink_col)
