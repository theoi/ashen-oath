shader_type spatial;
// Telegraph glow over a grave-vent grate: a square that brightens from the rim inward and
// pulses faster as eruption nears, plus a bright border so the danger zone reads at any
// distance and against any floor. `charge` (0..1) is set from the sim tick.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.3, 1.0, 0.55);
uniform float charge = 0.0;
uniform float energy = 1.6;
// Faint border while dormant so players learn where the vents are.
uniform float idle = 0.15;

void fragment() {
	vec2 p = abs(UV - 0.5) * 2.0;
	float edge = max(p.x, p.y);
	float bars = 0.6 + 0.4 * step(0.5, fract(UV.x * 6.0));
	float pulse = 0.75 + 0.25 * sin(TIME * (6.0 + 18.0 * charge));
	float fill = smoothstep(1.0 - charge * 1.2, 1.0 - charge * 1.2 + 0.25, edge) * (1.0 - smoothstep(0.92, 1.0, edge));
	float border = smoothstep(0.84, 0.9, edge) * (1.0 - smoothstep(0.96, 1.0, edge));
	float lit = fill * bars + border * 1.4;
	ALBEDO = color * energy;
	float dormant = border * idle * (0.8 + 0.2 * sin(TIME * 1.3 + UV.x * 3.0));
	ALPHA = clamp(max(lit * clamp(charge * 1.5, 0.0, 1.0) * pulse, dormant), 0.0, 1.0);
}
