shader_type spatial;
// Chains of ash around a rooted fighter's feet: a ring of dark iron links with ember glints,
// drawn flat on the floor.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 link_color : source_color = vec3(0.08, 0.07, 0.07);
uniform vec3 ember_color : source_color = vec3(1.0, 0.42, 0.1);
uniform float links = 14.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x) / TAU + 0.5;
	// Slow crawl so the chains look like they are tightening.
	float t = fract(a * links + TIME * 0.15);
	float id = floor(a * links + TIME * 0.15);
	bool face_on = mod(id, 2.0) < 1.0;
	// Each link is an oval outline; alternate links are seen edge-on (a thin bar).
	vec2 q = vec2((t - 0.5) * 2.0, (r - 0.68) / 0.11);
	float oval = length(q * vec2(1.0, face_on ? 1.0 : 2.6));
	float link = face_on ? smoothstep(0.32, 0.18, abs(oval - 0.72)) : smoothstep(0.75, 0.55, oval);
	float glint = pow(max(0.0, sin(id * 12.9898 + TIME * 3.0)), 12.0) * link;
	float haze = smoothstep(0.95, 0.55, r) * smoothstep(0.35, 0.6, r) * 0.25;
	ALBEDO = mix(link_color, ember_color, glint * 0.8 + link * 0.12);
	ALPHA = clamp(link * 0.9 + haze, 0.0, 1.0) * fade;
}
