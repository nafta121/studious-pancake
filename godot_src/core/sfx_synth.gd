class_name SfxSynth
extends Node

## Authentic Incremental Traffic UI sound engine using the original 26 WAV effects
## (res://sounds/ui/*.wav) with priority gating, cooldowns, pitch jitter, auto-button hooks,
## and Android tactile haptics.

const DIR := "res://sounds/ui/"
const UNGATED := -1

const SOUNDS := {
	"click": [-6.0, 0, 0.03, 0.04],
	"tick": [-8.0, 0, 0.03, 0.04],
	"confirm": [-5.0, 0, 0.05, 0.0],
	"tool_select": [-5.0, 1, 0.05, 0.03],
	"tool_deselect": [-6.0, 1, 0.05, 0.03],
	"edit": [-7.0, 1, 0.04, 0.04],
	"pause": [-6.0, 1, 0.05, 0.0],
	"resume": [-6.0, 1, 0.05, 0.0],
	"speed": [-7.0, 1, 0.05, 0.0],
	"panel_open": [-9.0, 2, 0.08, 0.03],
	"panel_close": [-9.0, 2, 0.08, 0.03],
	"place": [-4.0, 2, 0.04, 0.05],
	"remove": [-4.0, 2, 0.04, 0.05],
	"refused": [-5.0, 3, 0.15, 0.0],
	"purchase": [-3.0, 3, 0.10, 0.0],
	"sell": [-4.0, 3, 0.10, 0.0],
	"route_opened": [-4.0, 4, 0.30, 0.0],
	"delivery": [-11.0, UNGATED, 0.15, 0.06],
	"delivery_bonus": [-6.0, UNGATED, 0.25, 0.03],
	"gate_ready": [-3.0, UNGATED, 1.0, 0.0],
	"gate_press": [-4.0, UNGATED, 0.30, 0.0],
	"street_roll": [-13.0, UNGATED, 0.06, 0.08],
	"building_slam": [-7.0, UNGATED, 0.08, 0.06],
	"popup_row": [-7.0, UNGATED, 0.05, 0.0],
	"yay": [-2.0, UNGATED, 1.0, 0.0],
	"star_ring": [-8.0, UNGATED, 0.05, 0.06],
}

const VOICES := 12

var muted: bool = false
var haptics_enabled: bool = true

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _cursor: int = 0
var _last_msec: Dictionary = {}
var _queued: Dictionary = {}
var _flush_pending: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		muted = true
		return

	for id in SOUNDS.keys():
		var path: String = DIR + String(id) + ".wav"
		if ResourceLoader.exists(path):
			_streams[id] = load(path)

	for _i in range(VOICES):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	get_tree().node_added.connect(_hook_control)
	_hook_subtree(get_tree().root)

func play_ui(id: String, pitch: float = 1.0) -> void:
	if muted or _players.is_empty() or not SOUNDS.has(id) or not _streams.has(id):
		return
	_queued[id] = pitch
	if not _flush_pending:
		_flush_pending = true
		_flush_queued.call_deferred()

func _flush_queued() -> void:
	_flush_pending = false
	if muted or _players.is_empty():
		_queued.clear()
		return
	var top: int = UNGATED
	for id in _queued.keys():
		top = maxi(top, int(SOUNDS[id][1]))
	var now: int = Time.get_ticks_msec()
	for id in _queued.keys():
		var spec: Array = SOUNDS[id]
		var prio: int = int(spec[1])
		if prio != UNGATED and prio < top:
			continue
		var cooldown_ms: float = float(spec[2]) * 1000.0
		if float(now - int(_last_msec.get(id, -100000))) < cooldown_ms:
			continue
		_last_msec[id] = now
		var p: AudioStreamPlayer = _players[_cursor]
		_cursor = (_cursor + 1) % _players.size()
		var base_pitch: float = float(_queued[id])
		var jitter: float = float(spec[3])
		p.stream = _streams[id]
		p.volume_db = float(spec[0])
		p.pitch_scale = base_pitch * (1.0 + randf_range(-jitter, jitter))
		p.play()
	_queued.clear()

func _hook_subtree(node: Node) -> void:
	_hook_control(node)
	for child in node.get_children():
		_hook_subtree(child)

func _hook_control(node: Node) -> void:
	if not (node is Control) or node.has_meta(&"_sfx_hooked"):
		return
	if node is BaseButton:
		node.set_meta(&"_sfx_hooked", true)
		(node as BaseButton).pressed.connect(_on_button_pressed.bind(node as BaseButton))
		if node is OptionButton:
			(node as OptionButton).item_selected.connect(func(_idx: int): play_ui("tick"))
	elif node is TabContainer:
		node.set_meta(&"_sfx_hooked", true)
		(node as TabContainer).tab_clicked.connect(func(_tab: int): play_ui("tick"))
	elif node is Slider:
		node.set_meta(&"_sfx_hooked", true)
		(node as Slider).drag_ended.connect(func(changed: bool):
			if changed:
				play_ui("tick")
		)

func _on_button_pressed(b: BaseButton) -> void:
	if b.has_meta(&"sfx"):
		var custom_id := String(b.get_meta(&"sfx"))
		if custom_id != "":
			play_ui(custom_id)
		return
	if b is CheckBox or b is CheckButton or (b is Button and (b as Button).theme_type_variation == &"SegmentButton"):
		play_ui("tick")
	elif b is Button and (b as Button).theme_type_variation == &"PrimaryButton":
		play_ui("confirm")
	else:
		play_ui("click")

func tap(haptic_ms: int = 12) -> void:
	play_ui("click")
	if haptics_enabled and OS.has_feature("mobile") and haptic_ms > 0:
		Input.vibrate_handheld(haptic_ms)

func coin(is_express: bool = false) -> void:
	play_ui("delivery_bonus" if is_express else "delivery")

func warn() -> void:
	play_ui("refused")
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(26)

func unlock_region() -> void:
	play_ui("gate_ready")
	play_ui("yay")
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(55)
