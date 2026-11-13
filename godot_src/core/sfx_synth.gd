class_name SfxSynth
extends Node

## Authentic Incremental Traffic UI & World Sound Engine:
## - Loads and wires all 26 original WAV effects (`res://sounds/ui/*.wav`) including
##   `gate_ready`, `gate_press`, `street_roll`, `building_slam`, `popup_row`, `star_ring`, and `yay`.
## - Synthesizes zero-footprint 16-bit PCM `AudioStreamWAV` clips for active rail level crossings
##   (`crossing_bell`), train departures (`train_depart`), harbour ship horns (`ship_horn`),
##   BoomShow fireworks (`firework_pop`), traffic jam horns (`truck_honk`), and gentle ambient wind/city hum.
## - Supports 5 volume channels (`Master`, `UI`, `Ambience`, `Trucks`, `Delivery`), priority gating,
##   cooldowns, pitch jitter, clean exit teardown, and Android tactile haptics.

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
	"street_roll": [-11.0, UNGATED, 0.06, 0.08],
	"building_slam": [-6.5, UNGATED, 0.08, 0.06],
	"popup_row": [-7.0, UNGATED, 0.05, 0.0],
	"yay": [-2.0, UNGATED, 1.0, 0.0],
	"star_ring": [-8.0, UNGATED, 0.05, 0.06],
	# Procedural world clips (synthesized into 16-bit PCM on boot)
	"crossing_bell": [-12.0, UNGATED, 0.45, 0.02],
	"train_depart": [-10.0, UNGATED, 2.5, 0.03],
	"ship_horn": [-9.5, UNGATED, 3.0, 0.02],
	"firework_pop": [-8.0, UNGATED, 0.09, 0.12],
	"truck_honk": [-13.0, UNGATED, 1.8, 0.08],
}

const VOICES := 14

var muted: bool = false
var haptics_enabled: bool = true
var master_volume: float = 1.0
var ui_volume: float = 1.0
var ambience_volume: float = 0.65
var trucks_volume: float = 0.75
var delivery_volume: float = 1.0
var money_popup_sound: bool = true

var _shutting_down: bool = false
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _amb_player: AudioStreamPlayer
var _cursor: int = 0
var _last_msec: Dictionary = {}
var _queued: Dictionary = {}
var _flush_pending: bool = false
var _honk_accum: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		muted = true
		return

	for id in SOUNDS.keys():
		var path: String = DIR + String(id) + ".wav"
		if ResourceLoader.exists(path):
			_streams[id] = load(path)

	_synthesize_world_streams()

	for _i in range(VOICES):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	if _streams.has("_ambience_loop"):
		_amb_player = AudioStreamPlayer.new()
		_amb_player.stream = _streams["_ambience_loop"]
		_amb_player.volume_db = -28.0
		add_child(_amb_player)

	if get_tree() != null and not get_tree().node_added.is_connected(_hook_control):
		get_tree().node_added.connect(_hook_control)
	if get_tree() != null and get_tree().root != null:
		_hook_subtree(get_tree().root)

func _synthesize_world_streams() -> void:
	var sr: int = 22050
	# 1. Metallic rail-crossing bell (dual partials 880 Hz + 1328 Hz + 2110 Hz with fast decay)
	_streams["crossing_bell"] = _make_pcm_wav(sr, 0.34, func(t: float) -> float:
		var env: float = exp(-t * 11.5)
		return env * (0.55 * sin(TAU * 912.0 * t) + 0.32 * sin(TAU * 1385.0 * t) + 0.13 * sin(TAU * 2240.0 * t))
	)
	# 2. Train dual-chime diesel horn (330 Hz + 415 Hz + 494 Hz warm chord)
	_streams["train_depart"] = _make_pcm_wav(sr, 0.52, func(t: float) -> float:
		var att: float = clampf(t / 0.05, 0.0, 1.0)
		var rel: float = clampf((0.52 - t) / 0.12, 0.0, 1.0)
		var s: float = 0.44 * sin(TAU * 311.0 * t) + 0.34 * sin(TAU * 392.0 * t) + 0.22 * sin(TAU * 466.0 * t)
		return att * rel * tanh(s * 1.5) * 0.72
	)
	# 3. Deep harbour ship horn (110 Hz + 165 Hz brassy low fundamental)
	_streams["ship_horn"] = _make_pcm_wav(sr, 0.72, func(t: float) -> float:
		var att: float = clampf(t / 0.09, 0.0, 1.0)
		var rel: float = clampf((0.72 - t) / 0.18, 0.0, 1.0)
		var s: float = 0.58 * sin(TAU * 108.0 * t) + 0.28 * sin(TAU * 216.0 * t) + 0.14 * sin(TAU * 162.0 * t)
		return att * rel * tanh(s * 1.7) * 0.75
	)
	# 4. Crisp firework burst pop
	_streams["firework_pop"] = _make_pcm_wav(sr, 0.22, func(t: float) -> float:
		var env: float = exp(-t * 22.0)
		var n: float = sin(TAU * (240.0 - 140.0 * t) * t) * 0.65 + sin(t * 43758.5453) * 0.35
		return env * n * 0.80
	)
	# 5. Short polite two-tone truck horn
	_streams["truck_honk"] = _make_pcm_wav(sr, 0.19, func(t: float) -> float:
		var env: float = clampf(t / 0.02, 0.0, 1.0) * clampf((0.19 - t) / 0.04, 0.0, 1.0)
		return env * (0.55 * sin(TAU * 420.0 * t) + 0.45 * sin(TAU * 525.0 * t)) * 0.60
	)
	# 6. Soft seamless 2.0s warm breeze / city hum loop
	var amb_wav: AudioStreamWAV = _make_pcm_wav(sr, 2.0, func(t: float) -> float:
		var w: float = 0.5 + 0.5 * sin(TAU * 0.5 * t)
		return (0.45 * sin(TAU * 72.0 * t) + 0.30 * sin(TAU * 108.0 * t) + 0.25 * sin(TAU * 144.0 * t)) * (0.12 + 0.06 * w)
	)
	amb_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	amb_wav.loop_begin = 0
	amb_wav.loop_end = int(2.0 * float(sr))
	_streams["_ambience_loop"] = amb_wav

static func _make_pcm_wav(sample_rate: int, duration_sec: float, gen: Callable) -> AudioStreamWAV:
	var count: int = maxi(64, int(round(float(sample_rate) * duration_sec)))
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / float(sample_rate)
		var v: float = clampf(float(gen.call(t)), -1.0, 1.0)
		var s16: int = clampi(int(round(v * 32767.0)), -32768, 32767)
		data.encode_s16(i * 2, s16)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data
	return wav

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		shutdown()

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	muted = true
	_flush_pending = false
	_queued.clear()
	if is_inside_tree() and get_tree() != null and get_tree().node_added.is_connected(_hook_control):
		get_tree().node_added.disconnect(_hook_control)
	if _amb_player != null and is_instance_valid(_amb_player):
		_amb_player.stop()
		_amb_player.stream = null
	_amb_player = null
	for p in _players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_players.clear()
	_streams.clear()

func set_volumes(master_v: float, ui_v: float, delivery_v: float = 1.0, amb_v: float = -1.0, trk_v: float = -1.0) -> void:
	master_volume = clampf(master_v, 0.0, 1.0)
	ui_volume = clampf(ui_v, 0.0, 1.0)
	delivery_volume = clampf(delivery_v, 0.0, 1.0)
	if amb_v >= 0.0:
		ambience_volume = clampf(amb_v, 0.0, 1.0)
	if trk_v >= 0.0:
		trucks_volume = clampf(trk_v, 0.0, 1.0)

func update_world_ambience(dt: float, zoom_x: float, jammed_trucks: int, active_trucks: int, paused: bool) -> void:
	if _shutting_down or muted or _amb_player == null:
		if _amb_player != null and _amb_player.playing:
			_amb_player.stop()
		return
	var amb_gain: float = master_volume * ambience_volume * (0.35 if paused else 1.0)
	if amb_gain <= 0.01:
		if _amb_player.playing:
			_amb_player.stop()
	else:
		var traffic_boost: float = clampf(float(active_trucks) / 30.0, 0.0, 1.0) * trucks_volume * 0.45
		_amb_player.volume_db = -27.0 + linear_to_db(clampf(amb_gain + traffic_boost * 0.25, 0.02, 1.2))
		if not _amb_player.playing:
			_amb_player.play()

	if not paused and jammed_trucks >= 3 and zoom_x >= 0.85 and trucks_volume > 0.05:
		_honk_accum += dt
		if _honk_accum >= 4.2:
			_honk_accum = 0.0
			play_ui("truck_honk", randf_range(0.92, 1.10))
	else:
		_honk_accum = maxf(0.0, _honk_accum - dt * 0.5)

func _channel_gain_for(id: String) -> float:
	if id == "delivery" or id == "delivery_bonus":
		if not money_popup_sound:
			return 0.0
		return master_volume * delivery_volume
	if id in ["crossing_bell", "train_depart", "ship_horn", "truck_honk"]:
		return master_volume * trucks_volume
	return master_volume * ui_volume

const SOUND_ALIASES := {
	"road_confirm": "street_roll",
	"route_confirm": "route_opened",
	"confetti_pop": "popup_row",
	"unlock_fanfare": "yay",
}

func play_ui(id: String, pitch: float = 1.0) -> void:
	if SOUND_ALIASES.has(id):
		id = String(SOUND_ALIASES[id])
	if _shutting_down or muted or master_volume <= 0.001 or _players.is_empty() or not SOUNDS.has(id) or not _streams.has(id):
		return
	if _channel_gain_for(id) <= 0.001:
		return
	_queued[id] = pitch
	if not _flush_pending:
		_flush_pending = true
		_flush_queued.call_deferred()

func _flush_queued() -> void:
	_flush_pending = false
	if _shutting_down or muted or master_volume <= 0.001 or _players.is_empty():
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
		var chan_gain: float = _channel_gain_for(String(id))
		if chan_gain <= 0.001:
			continue
		_last_msec[id] = now
		var p: AudioStreamPlayer = _players[_cursor]
		_cursor = (_cursor + 1) % _players.size()
		var base_pitch: float = float(_queued[id])
		var jitter: float = float(spec[3])
		p.stop()
		p.stream = _streams[id]
		p.volume_db = float(spec[0]) + linear_to_db(chan_gain)
		p.pitch_scale = base_pitch * (1.0 + randf_range(-jitter, jitter))
		p.play()
	_queued.clear()

func _hook_subtree(node: Node) -> void:
	_hook_control(node)
	for child in node.get_children():
		_hook_subtree(child)

func _hook_control(node: Node) -> void:
	if _shutting_down or not (node is Control) or node.has_meta(&"_sfx_hooked"):
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
	if _shutting_down or not is_instance_valid(b):
		return
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
	play_ui("yay")
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(55)

func play_crossing_bell(_world_pos: Vector2 = Vector2.ZERO) -> void:
	play_ui("crossing_bell")

func play_train_depart() -> void:
	play_ui("train_depart")

func play_ship_horn() -> void:
	play_ui("ship_horn")

func play_firework_pop() -> void:
	play_ui("firework_pop")
