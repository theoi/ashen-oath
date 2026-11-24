shader_type spatial;
// Additive column of fire or soul-light for effect visuals: soft view-facing edges,
// upward-scrolling flicker, fading toward the top. `fade` fades the whole column out.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform float intensity = 2.2;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float flicker_speed = 9.0;

void fragment() {
	float height = 1.0 - UV.y;
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.4);
	float n = 0.5 + 0.5 * sin(UV.x * 37.7 + TIME * 2.0) * sin(UV.y * 11.0 - TIME * flicker_speed + UV.x * 18.8);
	float tongues = smoothstep(0.0, 0.9, 1.0 - height + n * 0.45);
	float a = edge * tongues * smoothstep(0.0, 0.08, 1.0 - UV.y) * fade;
	ALBEDO = mix(color.rgb, vec3(1.0, 0.95, 0.8), (1.0 - height) * 0.35 * n) * intensity;
	ALPHA = clamp(a * color.a, 0.0, 1.0);
}
