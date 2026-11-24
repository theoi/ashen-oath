shader_type canvas_item;
// Darkens the screen edges toward black; drawn under the HUD.

uniform float strength : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec2 p = (SCREEN_UV - 0.5) * vec2(1.25, 1.0);
	float edge = smoothstep(0.35, 0.95, length(p) * 1.25);
	COLOR = vec4(0.0, 0.0, 0.0, edge * strength);
}
