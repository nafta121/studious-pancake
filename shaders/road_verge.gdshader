shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/city_ground.gdshaderinc"

uniform sampler2D hill_tex : filter_linear;
uniform vec2 hill_origin = vec2(0.0);
uniform vec2 hill_size = vec2(0.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	COLOR.rgb = ground_color(COLOR.rgb, world);
	if (hill_size.x > 0.0) {
		vec4 h = texture(hill_tex, (world - hill_origin) / hill_size);
		COLOR.rgb = mix(COLOR.rgb, h.rgb, h.a);
	}
}
