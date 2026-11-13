// Authentic Incremental Traffic v1.4.1 ground noise & parchment grain include
// Adapted with scale = 520.0 (2600.0 * 0.20 UNIT_SCALE) for Karesidenan Madiun world coordinates.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float strength = 1.0;
uniform float scale = 520.0;
uniform vec3 meadow = vec3(0.86, 0.90, 0.76);
uniform vec3 sand = vec3(0.96, 0.92, 0.83);
uniform float meadow_amount = 0.55;
uniform float sand_amount = 0.45;
uniform float grain = 0.025;

vec3 ground_color(vec3 base, vec2 w) {
	float n = texture(noise_tex, w / scale).r;
	float fine = texture(noise_tex, w / (scale * 0.21) + vec2(0.37, 0.11)).r;
	base = mix(base, meadow, smoothstep(0.50, 0.78, n) * meadow_amount * strength);
	base = mix(base, sand, smoothstep(0.42, 0.18, n) * sand_amount * strength);
	return base * (1.0 - grain * strength * fine);
}
