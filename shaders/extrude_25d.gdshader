shader_type canvas_item;
render_mode unshaded;

// Clean-room 2.5D radial camera-lean vertex extrusion shader for Android GLES3.
// UV.x = extrusion height in world units (0.0 for ground base / shadow, >0.0 for roof/top).
// UV.y = window schedule seed (0.0 for solid roof/wall, >0.05 for night-lit windows).

uniform vec2 cam_center = vec2(700.0, 500.0);
uniform float cam_zoom = 1.0;
uniform float lean_strength = 0.00052;
uniform float night_blend : hint_range(0.0, 1.0) = 0.0;
uniform float day_clock : hint_range(0.0, 1.0) = 0.35;

varying float v_window_seed;

void vertex() {
	float h = UV.x;
	v_window_seed = UV.y;
	if (h > 0.001) {
		vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
		float z_clamped = clamp(cam_zoom, 0.30, 2.40);
		vec2 lean_offset = (world_pos - cam_center) * (z_clamped * lean_strength * h);
		// Clamp maximum lean so buildings near extreme screen edges stay readable on ultrawide Android screens
		float max_lean = h * 1.15;
		float len_off = length(lean_offset);
		if (len_off > max_lean && len_off > 0.0001) {
			lean_offset = lean_offset * (max_lean / len_off);
		}
		VERTEX += lean_offset;
	}
}

void fragment() {
	vec4 col = COLOR;
	if (night_blend > 0.001) {
		// Cool slate moonlight tint on roofs & walls
		vec3 night_tinted = col.rgb * mix(vec3(1.0), vec3(0.36, 0.43, 0.58), night_blend);
		if (v_window_seed > 0.05) {
			// Scheduled apartment/factory warm amber window glow
			float pulse = step(0.18, fract(v_window_seed * 7.31 + day_clock * 0.5));
			vec3 warm_glow = vec3(1.0, 0.84, 0.44);
			night_tinted = mix(night_tinted, warm_glow, night_blend * (0.55 + 0.40 * pulse));
		}
		col.rgb = night_tinted;
	}
	COLOR = col;
}
