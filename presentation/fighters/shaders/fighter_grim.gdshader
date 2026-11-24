shader_type spatial;
// "Stylized grim" restyle of a KayKit character atlas (8 x 4 colour cells): cold,
// desaturated recolour, per-cell tint overrides, a strong rim light, glowing cells
// (ember seams, lantern glass, eyes), a hit flash and an optional shade/ember look
// (Oath-Shade). One material instance per fighter so flashes stay per fighter.
render_mode diffuse_lambert, cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
// Per-cell tint (rgb multiplies the recoloured cell, a = how much of the original
// saturation the cell keeps). 8 x 4 texels, one per atlas cell.
uniform sampler2D cell_tints : filter_nearest;
uniform vec3 tint : source_color = vec3(0.86, 0.88, 0.95);
uniform float desaturate : hint_range(0.0, 1.0) = 0.55;
uniform float brightness = 0.9;
uniform float contrast = 1.12;
uniform float rim_strength = 0.6;
uniform vec3 rim_color : source_color = vec3(0.65, 0.75, 1.0);
// Bit (row * 8 + column) of the atlas grid marks a glowing cell.
uniform int glow_cells = 0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.45, 0.12);
uniform float glow_energy = 2.5;
uniform float glow_pulse = 0.0;
// Hit / armour / parry flash (presentation only).
uniform vec3 flash_color : source_color = vec3(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
// Shade look: darkens the body to smoky black with ember fresnel (Oath-Shade).
uniform float shade_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 shade_edge : source_color = vec3(1.0, 0.35, 0.08);

void fragment() {
	vec3 base = texture(atlas, UV).rgb;
	ivec2 cell = clamp(ivec2(floor(UV * vec2(8.0, 4.0))), ivec2(0), ivec2(7, 3));
	vec4 cell_tint = texelFetch(cell_tints, cell, 0);
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 col = mix(vec3(luma), base, mix(1.0 - desaturate, 1.0, cell_tint.a));
	col = clamp((col - 0.5) * contrast + 0.5, 0.0, 1.0) * tint * cell_tint.rgb * brightness;
	vec3 emission = vec3(0.0);
	if (((glow_cells >> (cell.y * 8 + cell.x)) & 1) == 1) {
		float pulse = 1.0 + glow_pulse * sin(TIME * 7.0 + luma * 6.0) * 0.35;
		col = mix(col, glow_color * 0.3, 0.7);
		emission = glow_color * glow_energy * (0.45 + luma) * pulse;
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	if (shade_amount > 0.0) {
		col = mix(col, vec3(0.02, 0.018, 0.025), shade_amount * 0.92);
		emission += shade_edge * fres * 2.2 * shade_amount;
	}
	emission += rim_color * fres * rim_strength * 0.35;
	// The flash reads as a rim-weighted glow so the model keeps its shape.
	emission += flash_color * flash_amount * (0.35 + 1.6 * fres);
	ALBEDO = mix(col, flash_color, flash_amount * 0.25);
	EMISSION = emission;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	RIM = rim_strength;
	RIM_TINT = 0.2;
}
