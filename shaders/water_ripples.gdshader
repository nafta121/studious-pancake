shader_type canvas_item;
render_mode unshaded;

// Lightweight mobile fragment shimmer for Bengawan Solo, Kali Madiun & Samudra Hindia.
uniform float night_blend : hint_range(0.0, 1.0) = 0.0;
uniform float shimmer_amp : hint_range(0.0, 0.25) = 0.07;

varying vec2 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float wave1 = sin(v_world.x * 0.045 + v_world.y * 0.032 - TIME * 1.65);
	float wave2 = cos(v_world.x * 0.028 - v_world.y * 0.051 + TIME * 1.15);
	float crest = smoothstep(0.55, 0.96, 0.5 * (wave1 + wave2));
	vec3 base_rgb = COLOR.rgb * mix(vec3(1.0), vec3(0.32, 0.42, 0.60), night_blend);
	vec3 crest_rgb = mix(vec3(0.86, 0.95, 1.0), vec3(0.42, 0.58, 0.78), night_blend);
	COLOR = vec4(mix(base_rgb, crest_rgb, crest * shimmer_amp * 2.2), COLOR.a);
}
