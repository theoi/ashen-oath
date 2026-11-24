shader_type spatial;
// The orange channel-break gauge over a channelling boss (design-lost-ark §5.8): a billboard
// bar with a dark frame, an orange fill that drains left to right, and a white burst when
// it breaks.
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform float fill : hint_range(0.0, 1.0) = 1.0;
// 0 = whole; rises to 1 as the gauge shatters.
uniform float broken : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec3 fill_color : source_color = vec3(1.0, 0.5, 0.08);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	float border = 0.08;
	bool frame = uv.x < border * 0.3 || uv.x > 1.0 - border * 0.3 || uv.y < border * 2.5 || uv.y > 1.0 - border * 2.5;
	float x = (uv.x - border * 0.3) / (1.0 - border * 0.6);
	vec3 col = vec3(0.05, 0.03, 0.02);
	float a = 0.85;
	if (frame) {
		col = vec3(0.35, 0.2, 0.08);
		a = 1.0;
	} else if (x < fill) {
		float shine = 0.75 + 0.25 * sin(TIME * 9.0 - x * 18.0);
		col = fill_color * shine * (1.15 - 0.3 * uv.y);
		a = 1.0;
	}
	// Shatter: the bar flashes white and breaks into pieces that fall away.
	float piece = floor(uv.x * 9.0);
	float drop = broken * (0.5 + 0.5 * fract(sin(piece * 78.233) * 43758.5));
	if (broken > 0.0 && fract(uv.x * 9.0) < drop * 0.9) {
		discard;
	}
	col = mix(col, vec3(1.0, 0.9, 0.7), clamp(1.0 - broken * 3.0, 0.0, 1.0) * step(0.001, broken));
	ALBEDO = col;
	ALPHA = a * alpha * (1.0 - broken);
}
