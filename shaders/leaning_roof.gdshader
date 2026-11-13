shader_type canvas_item;
render_mode unshaded;

// Authentic Incremental Traffic leaning_roof.gdshader for rotated facility roof details
uniform vec2 cam_center = vec2(0.0);
uniform float cam_zoom = 1.0;
uniform float lean_scale = 0.0;
uniform float fixed_height = -1.0;

void vertex() {
	float h = fixed_height < 0.0 ? UV.x : fixed_height;
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vec2 lean = (world - cam_center) * cam_zoom * lean_scale * h;
	mat2 basis = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
	if (abs(determinant(basis)) > 0.000001) {
		VERTEX += inverse(basis) * lean;
	}
}
