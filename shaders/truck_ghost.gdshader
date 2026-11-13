shader_type canvas_item;
render_mode unshaded;

// Authentic Incremental Traffic v1.4.1 truck_ghost.gdshader
// Luminance greyscale + 0.8 alpha for trucks passing beneath hidden flyovers or belonging to dimmed routes.

uniform vec3 grey = vec3(0.62, 0.63, 0.66);
uniform float contrast = 0.35;
uniform float alpha = 0.8;

void fragment() {
	float l = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(grey + (l - 0.5) * contrast, COLOR.a * alpha);
}
