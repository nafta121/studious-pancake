shader_type canvas_item;
render_mode unshaded;

// Authentic Incremental Traffic river & ocean ripple shader adapted for GLES3 Android:
// combines zoom-aware flowing dash streaks (river_ripples.gdshader) with gentle water shimmer.
uniform float night_blend : hint_range(0.0, 1.0) = 0.0;
uniform float shimmer_amp : hint_range(0.0, 0.25) = 0.08;
uniform float fade_zoom : hint_range(0.05, 0.5) = 0.14;

varying vec2 v_world;
varying float v_zoom_fade;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float z = length(CANVAS_MATRIX[0].xy);
	v_zoom_fade = clamp((z - fade_zoom) / max(0.05, fade_zoom), 0.0, 1.0);
}

void fragment() {
	float wave1 = sin(v_world.x * 0.045 + v_world.y * 0.032 - TIME * 1.65);
	float wave2 = cos(v_world.x * 0.028 - v_world.y * 0.051 + TIME * 1.15);
	float crest = smoothstep(0.55, 0.96, 0.5 * (wave1 + wave2));

	// Flowing current ripple dashes inspired by river_ripples.gdshader
	vec2 flow_uv = vec2(v_world.x * 0.055 - v_world.y * 0.038 - TIME * 0.85, v_world.x * 0.038 + v_world.y * 0.055);
	float lane = floor(flow_uv.y * 1.6);
	float dash = smoothstep(0.76, 0.94, sin(flow_uv.x * 2.2 + lane * 2.1)) * smoothstep(0.38, 0.12, abs(fract(flow_uv.y * 1.6) - 0.5));

	vec3 base_rgb = COLOR.rgb * mix(vec3(1.0), vec3(0.32, 0.42, 0.60), night_blend);
	vec3 crest_rgb = mix(vec3(0.91, 0.97, 1.0), vec3(0.46, 0.62, 0.82), night_blend);
	float k = clamp((crest * shimmer_amp * 2.0) + dash * 0.16 * v_zoom_fade, 0.0, 0.45);
	COLOR = vec4(mix(base_rgb, crest_rgb, k), COLOR.a);
}
