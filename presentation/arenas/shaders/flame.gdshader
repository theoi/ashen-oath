shader_type spatial;
// Camera-facing additive candle/torch flame drawn procedurally on a quad, flickering with
// a per-instance phase taken from its world position (works in a MultiMesh).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.85, 0.55);
uniform vec3 edge_color : source_color = vec3(1.0, 0.35, 0.06);
uniform float energy = 2.2;

varying float phase;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	phase = origin.x * 3.1 + origin.z * 5.7 + origin.y * 1.3;
	float flicker = 1.0 + 0.12 * sin(TIME * 13.0 + phase) + 0.08 * sin(TIME * 23.0 + phase * 1.7);
	VERTEX.y *= flicker;
	VERTEX.x += sin(TIME * 6.0 + phase) * 0.12 * (UV.y < 0.5 ? 1.0 : 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float t = 1.0 - UV.y;
	float x = abs(UV.x - 0.5) * 2.0;
	float width = 0.95 * sqrt(clamp(t * 3.0, 0.0, 1.0)) * (1.0 - t) + 0.03;
	float body = 1.0 - smoothstep(width * 0.45, width, x);
	body *= smoothstep(0.0, 0.08, t);
	float core = (1.0 - smoothstep(0.0, width * 0.5, x)) * (1.0 - smoothstep(0.15, 0.6, t));
	ALBEDO = mix(edge_color, core_color, core) * energy;
	ALPHA = body;
}
