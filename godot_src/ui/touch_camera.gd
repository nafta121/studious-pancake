class_name TouchCamera2D
extends Camera2D

## Android multi-touch pinch-to-zoom & inertial pan Camera2D controller.

signal world_tapped(world_pos: Vector2)

const MIN_ZOOM: float = 0.28
const MAX_ZOOM: float = 2.35

var world_bounds := Rect2(0.0, 0.0, 1600.0, 1200.0)

var _touches: Dictionary = {} # finger_index -> Vector2 screen pos
var _prev_pinch_dist: float = 0.0
var _pan_velocity := Vector2.ZERO
var _tap_start_pos := Vector2.ZERO
var _tap_start_msec: int = 0
var _tap_moved: bool = false
var _last_tap_msec: int = 0
var _last_tap_screen := Vector2.ZERO

func focus_map(initial_view: Dictionary, bounds: Dictionary) -> void:
	world_bounds = Rect2(
		float(bounds.get("minX", 0.0)) - 140.0,
		float(bounds.get("minY", 0.0)) - 140.0,
		(float(bounds.get("maxX", 1500.0)) - float(bounds.get("minX", 0.0))) + 280.0,
		(float(bounds.get("maxY", 1100.0)) - float(bounds.get("minY", 0.0))) + 280.0
	)
	global_position = Vector2(float(initial_view.get("x", 700.0)), float(initial_view.get("y", 500.0)))
	var z: float = clampf(float(initial_view.get("zoom", 0.72)), MIN_ZOOM, MAX_ZOOM)
	# Automatically fit portrait mobile screens comfortably
	var vp: Vector2 = get_viewport_rect().size
	if vp.x > 0.0 and vp.x < vp.y:
		z = clampf(z * 0.74, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	_pan_velocity = Vector2.ZERO
	_clamp_to_bounds()

func pan_to_world(target: Vector2, min_z: float = -1.0) -> void:
	global_position = target
	if min_z > 0.0 and zoom.x < min_z:
		var nz: float = clampf(min_z, MIN_ZOOM, MAX_ZOOM)
		zoom = Vector2(nz, nz)
	_pan_velocity = Vector2.ZERO
	_clamp_to_bounds()

func _process(delta: float) -> void:
	if _touches.is_empty() and _pan_velocity.length_squared() > 4.0:
		global_position += _pan_velocity * delta
		_pan_velocity *= exp(-7.5 * delta)
		_clamp_to_bounds()
	elif not _touches.is_empty():
		_pan_velocity = _pan_velocity.lerp(Vector2.ZERO, minf(1.0, delta * 12.0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() == 1:
				_tap_start_pos = st.position
				_tap_start_msec = Time.get_ticks_msec()
				_tap_moved = false
				_pan_velocity = Vector2.ZERO
			elif _touches.size() == 2:
				_tap_moved = true
				var pts: Array = _touches.values()
				_prev_pinch_dist = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
		else:
			var was_single: bool = _touches.size() == 1 and _touches.has(st.index)
			_touches.erase(st.index)
			_prev_pinch_dist = 0.0
			if was_single and not _tap_moved:
				var dt_ms: int = Time.get_ticks_msec() - _tap_start_msec
				if dt_ms < 380 and st.position.distance_to(_tap_start_pos) < 16.0:
					if Time.get_ticks_msec() - _last_tap_msec < 280 and st.position.distance_to(_last_tap_screen) < 28.0:
						_zoom_around_screen_point(st.position, 1.38)
						_last_tap_msec = 0
					else:
						_last_tap_msec = Time.get_ticks_msec()
						_last_tap_screen = st.position
						world_tapped.emit(screen_to_world(st.position))

	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if sd.position.distance_to(_tap_start_pos) > 12.0:
			_tap_moved = true

		if _touches.size() == 1:
			var world_delta: Vector2 = -sd.relative / maxf(0.15, zoom.x)
			global_position += world_delta
			_pan_velocity = world_delta / maxf(0.008, get_process_delta_time()) * 0.35
			_pan_velocity = _pan_velocity.limit_length(1800.0)
			_clamp_to_bounds()
		elif _touches.size() >= 2:
			var keys: Array = _touches.keys()
			var p0: Vector2 = _touches[keys[0]]
			var p1: Vector2 = _touches[keys[1]]
			var dist: float = p0.distance_to(p1)
			var mid: Vector2 = (p0 + p1) * 0.5
			if _prev_pinch_dist > 8.0 and dist > 8.0:
				var factor: float = dist / _prev_pinch_dist
				_zoom_around_screen_point(mid, factor)
			_prev_pinch_dist = dist

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_around_screen_point(mb.position, 1.14)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_around_screen_point(mb.position, 1.0 / 1.14)

func screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp_center: Vector2 = get_viewport_rect().size * 0.5
	return global_position + (screen_pos - vp_center) / maxf(0.15, zoom.x)

func _zoom_around_screen_point(screen_pos: Vector2, factor: float) -> void:
	var before_world: Vector2 = screen_to_world(screen_pos)
	var new_z: float = clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_z, new_z)
	var after_world: Vector2 = screen_to_world(screen_pos)
	global_position += before_world - after_world
	_clamp_to_bounds()

func _clamp_to_bounds() -> void:
	global_position.x = clampf(global_position.x, world_bounds.position.x, world_bounds.end.x)
	global_position.y = clampf(global_position.y, world_bounds.position.y, world_bounds.end.y)
