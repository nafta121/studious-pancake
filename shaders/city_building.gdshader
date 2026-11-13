shader_type canvas_item;
render_mode unshaded;

// Authentic Incremental Traffic 2.5D city building shader with analytic backface discard,
// directional sun/shadow shading (#363D55), night window glow, and elastic reveal/grow pop!
uniform vec2 cam_center = vec2(0.0);
uniform float cam_zoom = 1.0;
uniform float lean_scale = 0.0;
uniform vec2 sun_dir = vec2(1.0, 0.0);
uniform float sunlit = 1.0;
uniform float night = 0.0;
uniform vec4 shadow_color : source_color = vec4(0.21, 0.24, 0.33, 1.0);

const vec3 GROW_GLOW = vec3(1.0, 0.9, 0.55);

varying float v_hide;

#include "res://shaders/city_reveal.gdshaderinc"

void vertex() {
	vec2 pop = reveal_scale(CUSTOM0);
	VERTEX = reveal_vertex(VERTEX, CUSTOM0, pop);
	float h = UV.x * pop.y;
	float kind = floor(UV.y / 100.0 + 0.0001);
	float param = UV.y - kind * 100.0;
	if (kind > 2.5 && kind < 3.5) {
		param *= pop.x;
	}
	vec2 lean = (VERTEX - cam_center) * cam_zoom * lean_scale;
	vec2 top = lean * h;
	v_hide = 0.0;
	if (kind < 0.5) {
		VERTEX += top;
	} else if (kind < 2.5) {
		vec2 n = vec2(cos(param), sin(param));
		VERTEX += kind < 1.5 ? vec2(0.0) : top;
		v_hide = dot(n, lean) > 0.0 ? 1.0 : 0.0;
		float lit = dot(n, sun_dir) * sunlit;
		float k = 0.16 + 0.24 * (1.0 - lit) * 0.5 + 0.12 * night;
		COLOR.rgb = mix(COLOR.rgb, shadow_color.rgb, k);
	} else if (kind < 3.5) {
		VERTEX += top + sun_dir * param;
		COLOR.a *= sunlit;
	} else {
		VERTEX += top;
		COLOR.a *= night * (0.5 + 0.4 * param / 99.0);
	}
	// Subtle dusk/night ambient tint on roofs & walls so day/night transition feels cohesive
	if (kind < 3.5 && night > 0.001) {
		COLOR.rgb *= mix(vec3(1.0), vec3(0.46, 0.52, 0.70), night * 0.72);
	}
	COLOR.rgb = mix(COLOR.rgb, GROW_GLOW, 0.55 * grow_flash(CUSTOM0));
}

void fragment() {
	if (v_hide > 0.5) {
		discard;
	}
	COLOR = COLOR;
}
