shader_type spatial;
// Grounding under a fighter for the high fight camera: a soft pool of light in the
// fighter's rim colour with a dark contact shadow at the centre, so dark fighters separate
// from dark floors. Not a target marker: no hard edge.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 glow_color : source_color = vec3(0.6, 0.7, 0.9);
uniform float glow_alpha = 0.38;
uniform float shadow_alpha = 0.7;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float glow = (1.0 - smoothstep(0.15, 1.0, r)) * glow_alpha;
	float shadow = (1.0 - smoothstep(0.0, 0.38, r)) * shadow_alpha;
	float a = shadow + glow * (1.0 - shadow);
	ALBEDO = mix(glow_color, vec3(0.0), shadow / max(a, 0.0001));
	ALPHA = a * fade;
}
