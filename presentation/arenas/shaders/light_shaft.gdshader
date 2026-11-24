shader_type spatial;
// Additive light shaft (moonlight through a broken roof or window) on an open cylinder.
// Fades at silhouette edges and both ends, with a slow drifting dust shimmer.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.55, 0.65, 0.9);
uniform float intensity = 0.12;

void fragment() {
	float facing = pow(abs(dot(NORMAL, VIEW)), 2.0);
	float ends = smoothstep(0.0, 0.2, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));
	float dust = 0.75 + 0.25 * sin(TIME * 0.4 + UV.x * 25.0 + UV.y * 6.0);
	ALBEDO = color;
	ALPHA = clamp(intensity * facing * ends * dust, 0.0, 1.0);
}
