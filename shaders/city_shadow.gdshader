shader_type canvas_item;
render_mode unshaded;

// Authentic Incremental Traffic ground shadow projection shader with elastic reveal_scale
uniform vec2 sun_offset = vec2(0.0);

#include "res://shaders/city_reveal.gdshaderinc"

void vertex() {
	vec2 pop = reveal_scale(CUSTOM0);
	VERTEX = reveal_vertex(VERTEX, CUSTOM0, pop);
	VERTEX += sun_offset * UV.x * pop.y * UV.y;
}

void fragment() {
	COLOR = COLOR;
}
