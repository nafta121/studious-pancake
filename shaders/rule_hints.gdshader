shader_type canvas_item;

const float KIND_DOT = 0.0;
const float KIND_RING = 1.0;
const float KIND_SIGN_RING = 2.0;
const float KIND_DASH = 3.0;

uniform vec4 under_color = vec4(1.0);
uniform vec4 over_color = vec4(0.18, 0.52, 0.96, 1.0);
uniform vec4 hidden = vec4(-1.0);

uniform float period = 2.4;
uniform float ring_speed = 10.0;
uniform float dash_speed = 22.0;
uniform float sign_px = 22.0;
uniform float sign_max_scale = 3.0;
uniform float sign_size = 14.0;

const float RING_HALF = 1.75;
const float SIGN_RING_HALF = 2.0;
const float DASH_HALF = 1.1;
const float DOT_RADIUS = 11.0;

const float RING_PERIOD = 13.0;
const float RING_DASH = 7.0;
const float DASH_PERIOD = 18.0;
const float DASH_ON = 6.0;

varying flat float v_kind;
varying vec2 v_at;
varying flat vec2 v_ring;

void vertex() {
	float kind = CUSTOM0.x;
	float side = CUSTOM0.y;
	float px = max(1.0, 1.0 / length((CANVAS_MATRIX * MODEL_MATRIX)[0].xy));
	v_kind = kind;
	v_ring = vec2(0.0);
	if (any(equal(vec4(CUSTOM0.z), hidden))) {
		VERTEX = vec2(0.0);
		v_at = vec2(0.0);
	} else if (kind == KIND_DOT) {
		v_at = UV * (DOT_RADIUS + 1.0);
		VERTEX += v_at * px;
	} else if (kind == KIND_RING) {
		vec2 dir = vec2(cos(UV.x), sin(UV.x));
		float r = UV.y / px + 6.0;
		float across = side * (RING_HALF + 1.0);
		VERTEX += dir * (UV.y + (6.0 + across) * px);
		v_at = vec2(UV.x, across);
		v_ring = vec2(max(1.0, floor(TAU * r / RING_PERIOD)), r);
	} else if (kind == KIND_SIGN_RING) {
		vec2 dir = vec2(cos(UV.x), sin(UV.x));
		float s = clamp(px * sign_px / (sign_size * 2.0), 1.0, sign_max_scale);
		float across = side * (SIGN_RING_HALF + 1.0);
		VERTEX += dir * ((sign_size + 4.0) * s + across * px);
		v_at = vec2(UV.x, across);
	} else {
		float across = side * (DASH_HALF + 1.0);
		VERTEX += vec2(cos(UV.y), sin(UV.y)) * across * px;
		v_at = vec2(UV.x / px, across);
	}
}

float cover(float d, float half_w) {
	return clamp(half_w - abs(d) + 0.5, 0.0, 1.0);
}

void fragment() {
	float breath = 0.5 + 0.5 * sin(TIME / period * TAU);
	float under = 0.0;
	float over = 0.0;
	if (v_kind == KIND_DOT) {
		float d = length(v_at);
		under = cover(d, DOT_RADIUS) * (0.35 + 0.35 * breath);
		over = cover(d, 6.4 + 1.6 * breath) * (0.45 + 0.45 * breath);
	} else if (v_kind == KIND_RING) {
		float u = v_at.x / TAU * v_ring.x - TIME * ring_speed * v_ring.x / (TAU * v_ring.y);
		if (fract(u) < RING_DASH / RING_PERIOD) {
			under = cover(v_at.y, RING_HALF) * 0.45;
			over = cover(v_at.y, 0.9) * 0.8;
		}
	} else if (v_kind == KIND_SIGN_RING) {
		under = cover(v_at.y, SIGN_RING_HALF) * (0.35 + 0.35 * breath);
		over = cover(v_at.y, 1.0) * (0.45 + 0.45 * breath);
	} else if (fract((v_at.x - TIME * dash_speed) / DASH_PERIOD) < DASH_ON / DASH_PERIOD) {
		over = cover(v_at.y, DASH_HALF) * 0.7;
	}

	float a = over + under * (1.0 - over);
	if (a <= 0.0) {
		discard;
	}
	COLOR = vec4((over_color.rgb * over + under_color.rgb * under * (1.0 - over)) / a, a);
}
