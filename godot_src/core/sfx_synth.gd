class_name SfxSynth
extends Node

## Zero-asset-bloat procedural PCM synthesizer for Godot 4 Android.
## Pre-renders lightweight 16-bit WAV buffers in <10 ms (tap, coin, express, warn,
## and Javanese Pelog/Slendro pentatonic region-unlock fanfare) + Android haptics.

var muted: bool = false
var haptics_enabled: bool = true

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _player_cursor: int = 0

func _ready() -> void:
	# Skip audio generation when running headless without audio server
	if DisplayServer.get_name() == "headless":
		muted = true
		return
	_streams["tap"] = _make_tone_sequence([{"freq": 540.0, "dur": 0.032, "amp": 0.22}])
	_streams["coin"] = _make_tone_sequence([
		{"freq": 784.0, "dur": 0.055, "amp": 0.20},
		{"freq": 1046.5, "dur": 0.085, "amp": 0.22}
	])
	_streams["express"] = _make_tone_sequence([
		{"freq": 880.0, "dur": 0.048, "amp": 0.22},
		{"freq": 1174.6, "dur": 0.055, "amp": 0.24},
		{"freq": 1568.0, "dur": 0.110, "amp": 0.24}
	])
	_streams["warn"] = _make_tone_sequence([
		{"freq": 230.0, "dur": 0.080, "amp": 0.24},
		{"freq": 175.0, "dur": 0.110, "amp": 0.22}
	])
	# Javanese Pelog/Slendro saron chime for unlocking Karesidenan Madiun regions!
	_streams["unlock"] = _make_tone_sequence([
		{"freq": 523.25, "dur": 0.11, "amp": 0.26},
		{"freq": 587.33, "dur": 0.11, "amp": 0.26},
		{"freq": 698.46, "dur": 0.12, "amp": 0.28},
		{"freq": 783.99, "dur": 0.13, "amp": 0.28},
		{"freq": 1046.50, "dur": 0.26, "amp": 0.30}
	])

	for i in range(6):
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)

func _make_tone_sequence(notes: Array) -> AudioStreamWAV:
	var mix_rate: int = 22050
	var total_samples: int = 0
	for n in notes:
		total_samples += int(float(n["dur"]) * float(mix_rate))

	var pcm := PackedByteArray()
	pcm.resize(total_samples * 2)
	var write_idx: int = 0
	var phase: float = 0.0

	for n in notes:
		var freq: float = float(n["freq"])
		var dur: float = float(n["dur"])
		var amp: float = float(n["amp"])
		var count: int = int(dur * float(mix_rate))
		for s in range(count):
			var t01: float = float(s) / float(maxi(1, count))
			var env: float = minf(1.0, t01 * 14.0) * pow(1.0 - t01, 1.45)
			phase += TAU * freq / float(mix_rate)
			var sample_f: float = (sin(phase) * 0.82 + sin(phase * 2.0) * 0.18) * amp * env
			var s16: int = clampi(int(sample_f * 32767.0), -32768, 32767)
			pcm[write_idx] = s16 & 0xFF
			pcm[write_idx + 1] = (s16 >> 8) & 0xFF
			write_idx += 2

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = pcm
	return wav

func _play(key: String, pitch: float = 1.0) -> void:
	if muted or _players.is_empty() or not _streams.has(key):
		return
	var p: AudioStreamPlayer = _players[_player_cursor]
	_player_cursor = (_player_cursor + 1) % _players.size()
	p.stream = _streams[key]
	p.pitch_scale = pitch
	p.play()

func tap(haptic_ms: int = 14) -> void:
	_play("tap", randf_range(0.96, 1.05))
	if haptics_enabled and OS.has_feature("mobile") and haptic_ms > 0:
		Input.vibrate_handheld(haptic_ms)

func coin(is_express: bool = false) -> void:
	_play("express" if is_express else "coin", randf_range(0.98, 1.03))

func warn() -> void:
	_play("warn", 1.0)
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(28)

func unlock_region() -> void:
	_play("unlock", 1.0)
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(55)
