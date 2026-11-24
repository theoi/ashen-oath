shader_type spatial;
// Ground decal for telegraphs and target circles: a circle or capsule (2D SDF in the
// quad's plane) with a bright rim and a fill that grows from the edge toward the centre
// as the hit approaches (fill 0..1). Unshaded, additive-ish, drawn just above the floor.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.12, 0.08, 0.85);
// Half extents of the quad in metres (x along the capsule, y across).
uniform vec2 half_size = vec2(1.0, 1.0);
// Capsule half segment length (0 = circle) and radius, metres.
uniform float half_length = 0.0;
uniform float radius = 1.0;
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float rim_width = 0.08;
// 1 = just a thin ring (range rings), 0 = telegraph with fill.
uniform float ring_only = 0.0;
uniform float pulse = 0.0;

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * half_size;
	vec2 q = vec2(max(abs(p.x) - half_length, 0.0), p.y);
	float d = length(q) - radius;
	if (d > 0.0) {
		discard;
	}
	float inside = -d;
	float rim = 1.0 - smoothstep(0.0, rim_width, inside);
	float a = rim;
	if (ring_only < 0.5) {
		// The fill eats inward from the rim: everything within fill * radius of the edge.
		float filled = 1.0 - smoothstep(fill * radius - 0.03, fill * radius + 0.03, inside);
		a = max(rim, 0.28 + 0.3 * filled);
		a = max(a, filled * 0.55);
	}
	a *= color.a * (1.0 + pulse * 0.3 * sin(TIME * 18.0));
	ALBEDO = color.rgb * (1.2 + rim * 1.5);
	ALPHA = clamp(a, 0.0, 1.0);
}
