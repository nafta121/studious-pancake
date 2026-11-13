// Authentic Incremental Traffic elastic city reveal & factory upgrade grow include
uniform float reveal_clock = 1000000.0;
uniform float grow_clock = 1000000.0;

const float REVEAL_FOOT_TIME = 0.3;
const float REVEAL_HEIGHT_DELAY = 0.04;
const float REVEAL_HEIGHT_TIME = 0.75;
const float REVEAL_VANISH_TIME = 0.25;
const float GROW_TIME = 0.9;
const float GROW_SQUEEZE_TIME = 0.3;
const float GONE_TIME = 0.15;
const float GROW_OVERSHOOT = 1.0;

float elastic_out(float e) {
	return e >= 1.0 ? 1.0 : pow(2.0, -10.0 * e) * sin((e * 10.0 - 0.75) * 2.0943951) + 1.0;
}

vec2 pop_up(float u) {
	if (u <= 0.0) {
		return vec2(0.0);
	}
	float a = clamp(u / REVEAL_FOOT_TIME, 0.0, 1.0) - 1.0;
	float c = 2.4;
	float foot = 1.0 + (c + 1.0) * a * a * a + c * a * a;
	float e = clamp((u - REVEAL_HEIGHT_DELAY) / REVEAL_HEIGHT_TIME, 0.0, 1.0);
	return vec2(foot, e <= 0.0 ? 0.0 : elastic_out(e));
}

vec2 reveal_scale(vec4 r) {
	if (r.w < -500.0) {
		return vec2(1.0 - smoothstep(0.0, GONE_TIME, grow_clock - r.x));
	}
	if (r.w < -0.5) {
		float x = -r.w - 1.0;
		float narrower = floor(x * 0.5);
		float f = x - 2.0 * narrower;
		float wide = 1.0 - narrower * 0.01;
		float g = grow_clock - r.x;
		if (f < 0.001) {
			return pop_up(g);
		}
		if (g <= 0.0) {
			return vec2(0.0);
		}
		float a = clamp(g / GROW_SQUEEZE_TIME, 0.0, 1.0) - 1.0;
		float spread = wide + (1.0 - wide) * (1.0 + 2.7 * a * a * a + 1.7 * a * a);
		float squeeze = 1.0 - 0.07 * sin(clamp(g / GROW_SQUEEZE_TIME, 0.0, 1.0) * 3.14159265);
		float k = elastic_out(clamp(g / GROW_TIME, 0.0, 1.0));
		return vec2(spread * squeeze, f + (1.0 - f) * min(k, 1.0) + GROW_OVERSHOOT * max(k - 1.0, 0.0));
	}
	if (r.w < 0.5) {
		return vec2(1.0);
	}
	vec2 pop = pop_up(reveal_clock - r.x);
	if (r.w > 1.5) {
		pop *= 1.0 - smoothstep(0.0, REVEAL_VANISH_TIME, reveal_clock - (r.w - 2.0));
	}
	return pop;
}

const float GROW_LINGER = 0.45;
const float GROW_LINGER_TIME = 15.0;

float grow_flash(vec4 r) {
	if (r.w > -0.5 || r.w < -500.0) {
		return 0.0;
	}
	float g = grow_clock - r.x;
	if (g <= 0.0) {
		return 0.0;
	}
	return max(1.0 - smoothstep(0.0, GROW_TIME * 1.3, g), GROW_LINGER * (1.0 - smoothstep(GROW_TIME, GROW_LINGER_TIME, g)));
}

vec2 reveal_vertex(vec2 v, vec4 r, vec2 pop) {
	return abs(r.w) < 0.5 ? v : r.yz + (v - r.yz) * pop.x;
}
