class_name TouchCamera2D
extends Camera2D

## Android multi-touch pinch-to-zoom, inertial pan, smooth quintic fly-to,
## and cinematic waypoint tour Camera2D controller.

signal world_tapped(world_pos: Vector2)
signal manual_pan_started()

const MIN_ZOOM: float = 0.28
const MAX_ZOOM: float = 2.35

var world_bounds := Rect2(0.0, 0.0, 1600.0, 1200.0)
var cinematic_locked: bool = false
var title_orbit_active: bool = false
var title_orbit_center := Vector2.ZERO
var title_orbit_radius: float = 48.0
var _title_orbit_angle: float = 0.0

var _touches: Dictionary = {} # finger_index -> Vector2 screen pos
var _prev_pinch_dist: float = 0.0
var _pan_velocity := Vector2.ZERO
var _tap_start_pos := Vector2.ZERO
var _tap_start_msec: int = 0
var _tap_moved: bool = false
var _last_tap_msec: int = 0
var _last_tap_screen := Vector2.ZERO

# Quintic smooth fly-to state
var _fly_active: bool = false
var _fly_elapsed: float = 0.0
var _fly_dur: float = 0.85
var _fly_from_pos := Vector2.ZERO
var _fly_to_pos := Vector2.ZERO
var _fly_from_zoom: float = 1.0
var _fly_to_zoom: float = 1.0

# Cinematic waypoint tour (`UnlockShow` / `BoomShow`)
var _tour_waypoints: Array = []
var _tour_index: int = -1
var _tour_hold_left: float = 0.0
var _tour_on_done: Callable = Callable()

static func _quintic_in_out(t: float) -> float:
	var u: float = clampf(t, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)

func focus_map(initial_view: Dictionary, bounds: Dictionary) -> void:
	cancel_cinematic_tour(false)
	_fly_active = false
	world_bounds = Rect2(
		float(bounds.get("minX", 0.0)) - 140.0,
		float(bounds.get("minY", 0.0)) - 140.0,
		(float(bounds.get("maxX", 1500.0)) - float(bounds.get("minX", 0.0))) + 280.0,
		(float(bounds.get("maxY", 1100.0)) - float(bounds.get("minY", 0.0))) + 280.0
	)
	global_position = Vector2(float(initial_view.get("x", 700.0)), float(initial_view.get("y", 500.0)))
	var z: float = clampf(float(initial_view.get("zoom", 0.72)), MIN_ZOOM, MAX_ZOOM)
	var vp: Vector2 = get_viewport_rect().size
	if vp.x > 0.0 and vp.x < vp.y:
		z = clampf(z * 0.74, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	_pan_velocity = Vector2.ZERO
	_clamp_to_bounds()

func pan_to_world(target: Vector2, min_z: float = -1.0) -> void:
	cancel_cinematic_tour(false)
	_fly_active = false
	global_position = target
	if min_z > 0.0 and zoom.x < min_z:
		var nz: float = clampf(min_z, MIN_ZOOM, MAX_ZOOM)
		zoom = Vector2(nz, nz)
	_pan_velocity = Vector2.ZERO
	_clamp_to_bounds()

func fly_to_world(target_pos: Vector2, target_zoom: float = -1.0, dur: float = 0.95) -> void:
	_pan_velocity = Vector2.ZERO
	_fly_from_pos = global_position
	_fly_to_pos = Vector2(
		clampf(target_pos.x, world_bounds.position.x, world_bounds.end.x),
		clampf(target_pos.y, world_bounds.position.y, world_bounds.end.y)
	)
	_fly_from_zoom = zoom.x
	if target_zoom > 0.0:
		_fly_to_zoom = clampf(target_zoom, MIN_ZOOM, MAX_ZOOM)
	else:
		_fly_to_zoom = zoom.x
	_fly_dur = maxf(0.08, dur)
	_fly_elapsed = 0.0
	_fly_active = true

func start_cinematic_tour(waypoints: Array, on_done: Callable = Callable()) -> void:
	if waypoints.is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	_touches.clear()
	_pan_velocity = Vector2.ZERO
	cinematic_locked = true
	_tour_waypoints = waypoints.duplicate()
	_tour_on_done = on_done
	_tour_index = -1
	_advance_tour_waypoint()

func cancel_cinematic_tour(invoke_callback: bool = true) -> void:
	var cb: Callable = _tour_on_done
	cinematic_locked = false
	_tour_waypoints.clear()
	_tour_index = -1
	_tour_hold_left = 0.0
	_tour_on_done = Callable()
	_fly_active = false
	if invoke_callback and cb.is_valid():
		cb.call()

func _advance_tour_waypoint() -> void:
	_tour_index += 1
	if _tour_index >= _tour_waypoints.size():
		cancel_cinematic_tour(true)
		return
	var wp: Dictionary = _tour_waypoints[_tour_index]
	var t_pos: Vector2 = wp.get("pos", global_position)
	var t_zoom: float = float(wp.get("zoom", -1.0))
	var fly_s: float = maxf(0.12, float(wp.get("flySec", 0.72)))
	_tour_hold_left = maxf(0.05, float(wp.get("holdSec", 0.45)))
	fly_to_world(t_pos, t_zoom, fly_s)

func export_camera_meta() -> Dictionary:
	return {
		"x": snappedf(global_position.x, 0.1),
		"y": snappedf(global_position.y, 0.1),
		"zoom": snappedf(zoom.x, 0.001)
	}

func apply_camera_meta(meta: Dictionary) -> void:
	if meta.is_empty():
		return
	if meta.has("x") and meta.has("y"):
		global_position = Vector2(float(meta["x"]), float(meta["y"]))
	if meta.has("zoom"):
		var z: float = clampf(float(meta["zoom"]), MIN_ZOOM, MAX_ZOOM)
		zoom = Vector2(z, z)
	_pan_velocity = Vector2.ZERO
	_fly_active = false
	_clamp_to_bounds()

func _process(delta: float) -> void:
	if title_orbit_active and not cinematic_locked and not _fly_active:
		_title_orbit_angle = fmod(_title_orbit_angle + delta * 0.22, TAU)
		global_position = title_orbit_center + Vector2(cos(_title_orbit_angle), sin(_title_orbit_angle) * 0.65) * title_orbit_radius
		_clamp_to_bounds()
		return

	if _fly_active:
		_fly_elapsed += delta
		var t: float = clampf(_fly_elapsed / maxf(0.05, _fly_dur), 0.0, 1.0)
		var e: float = _quintic_in_out(t)
		global_position = _fly_from_pos.lerp(_fly_to_pos, e)
		var z_cur: float = lerpf(_fly_from_zoom, _fly_to_zoom, e)
		zoom = Vector2(z_cur, z_cur)
		_clamp_to_bounds()
		if t >= 1.0:
			_fly_active = false
			if cinematic_locked and _tour_index >= 0 and _tour_index < _tour_waypoints.size():
				var wp_done: Dictionary = _tour_waypoints[_tour_index]
				if wp_done.has("onArrive") and (wp_done["onArrive"] as Callable).is_valid():
					(wp_done["onArrive"] as Callable).call()
		return

	if cinematic_locked:
		_tour_hold_left -= delta
		if _tour_hold_left <= 0.0:
			_advance_tour_waypoint()
		return

	if _touches.is_empty() and _pan_velocity.length_squared() > 4.0:
		global_position += _pan_velocity * delta
		_pan_velocity *= exp(-7.5 * delta)
		_clamp_to_bounds()
	elif not _touches.is_empty():
		_pan_velocity = _pan_velocity.lerp(Vector2.ZERO, minf(1.0, delta * 12.0))

func _unhandled_input(event: InputEvent) -> void:
	if cinematic_locked or title_orbit_active:
		return

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_fly_active = false
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
		_fly_active = false
		_touches[sd.index] = sd.position
		if not _tap_moved and sd.position.distance_to(_tap_start_pos) > 12.0:
			_tap_moved = true
			manual_pan_started.emit()

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
				_fly_active = false
				_zoom_around_screen_point(mb.position, 1.14)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_fly_active = false
				_zoom_around_screen_point(mb.position, 1.0 / 1.14)

func screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp_center: Vector2 = get_viewport_rect().size * 0.5
	return global_position + (screen_pos - vp_center) / maxf(0.15, zoom.x)

func world_to_screen(world_pos: Vector2) -> Vector2:
	var vp_center: Vector2 = get_viewport_rect().size * 0.5
	return vp_center + (world_pos - global_position) * maxf(0.15, zoom.x)

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
