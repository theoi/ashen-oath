shader_type spatial;
// Spectral fire column from a grave vent, on an open cylinder. Tongues of flame scroll
// upward through a noise texture; `intensity` (0..1) is set from the sim tick.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 core_color : source_color = vec3(0.75, 1.0, 0.85);
uniform vec3 edge_color : source_color = vec3(0.2, 0.9, 0.5);
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float intensity = 0.0;
uniform float energy = 2.5;

void fragment() {
	float h = 1.0 - UV.y;
	float n = texture(noise, vec2(UV.x * 2.0, UV.y * 0.8 + TIME * 1.6)).r;
	float n2 = texture(noise, vec2(UV.x * 3.0 + 0.37, UV.y * 1.3 + TIME * 2.3)).r;
	float tongue = smoothstep(h * 1.1 - 0.05, h * 1.1 + 0.35, (n + n2) * 0.5 + 0.25);
	float facing = abs(dot(NORMAL, VIEW));
	vec3 col = mix(edge_color, core_color, smoothstep(0.5, 1.0, facing) * (1.0 - h));
	ALBEDO = col * energy;
	ALPHA = clamp(tongue * intensity * (0.35 + 0.65 * facing) * smoothstep(0.0, 0.08, h), 0.0, 1.0);
}
