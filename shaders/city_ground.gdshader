shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/city_ground.gdshaderinc"

uniform vec2 origin = vec2(0.0);
uniform vec2 size = vec2(1.0);

void fragment() {
	COLOR.rgb = ground_color(COLOR.rgb, origin + UV * size);
}
