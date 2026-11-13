shader_type canvas_item;
render_mode unshaded;

// Authentic Incremental Traffic drifting cloud puff shader for locked perimeter regions
uniform float clock = 0.0;
uniform float swell = 0.09;
uniform float wander = 42.0;
uniform vec2 gust = vec2(65.0, 30.0);

void vertex() {
	float phase = CUSTOM0.y;
	float grow = 1.7 + sin(clock * 0.37 + phase) + 0.7 * sin(clock * 0.61 + phase * 2.3);
	VERTEX += UV * CUSTOM0.x * swell * grow;
	VERTEX += vec2(sin(clock * 0.27 + phase * 1.7), cos(clock * 0.21 + phase * 3.1)) * wander;
	VERTEX += gust * sin(clock * 0.2 + CUSTOM0.z);
}

void fragment() {
	float d = length(UV);
	COLOR.a *= clamp((1.0 - d) / max(0.02, fwidth(d)) + 0.5, 0.0, 1.0);
}
