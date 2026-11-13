shader_type canvas_item;
render_mode unshaded;

// Authentic Incremental Traffic v1.4.1 truck_part.gdshader
// Expands screen-space keylines via UV offset and applies ghost desaturation under hidden flyovers / dimmed routes.

uniform bool ghost = false;
uniform vec3 grey = vec3(0.62, 0.63, 0.66);
uniform float contrast = 0.35;
uniform float alpha = 0.8;
uniform float min_world_px = 0.26;
uniform float max_world_px = 0.85;

float screen_px(mat4 canvas_m, mat4 model_m) {
	return 1.0 / max(0.0001, length((canvas_m * model_m)[0].xy));
}

void vertex() {
	VERTEX += UV * clamp(screen_px(CANVAS_MATRIX, MODEL_MATRIX), min_world_px, max_world_px);
}

void fragment() {
	if (ghost) {
		float l = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
		COLOR = vec4(grey + (l - 0.5) * contrast, COLOR.a * alpha);
	}
}
