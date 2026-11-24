shader_type spatial;
// Recolors the KayKit gradient atlas into the cold, desaturated "stylized grim" palette,
// adds world-space grime and darker wall bases, and lets chosen atlas cells glow
// (candle flames, lantern glass) in a single shared material per pack.
render_mode diffuse_lambert;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.82, 0.86, 0.95);
uniform float desaturate : hint_range(0.0, 1.0) = 0.6;
uniform float brightness = 0.85;
uniform float contrast = 1.15;
uniform vec3 grime_color : source_color = vec3(0.05, 0.045, 0.05);
uniform float grime_amount : hint_range(0.0, 1.0) = 0.45;
uniform sampler2D grime_noise : filter_linear_mipmap, repeat_enable;
uniform float grime_scale = 0.07;
uniform float rim_strength = 0.35;
// Bit (row * 8 + column) of the 8x4 atlas grid marks a glowing cell.
uniform int glow_cells = 0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.55, 0.2);
uniform float glow_energy = 3.0;

varying vec3 world_pos;
varying float wall_factor;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wall_factor = 1.0 - abs(world_normal.y);
}

void fragment() {
	vec3 base = texture(atlas, UV).rgb;
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 col = mix(base, vec3(luma), desaturate);
	col = clamp((col - 0.5) * contrast + 0.5, 0.0, 1.0) * tint * brightness;
	vec2 noise_uv = world_pos.xz * grime_scale + vec2(world_pos.y * 0.8, world_pos.y * 1.3) * grime_scale;
	float n = texture(grime_noise, noise_uv).r;
	float low = (1.0 - smoothstep(0.0, 1.6, world_pos.y)) * wall_factor;
	float grime = clamp(grime_amount * smoothstep(0.25, 0.85, n) + low * 0.45, 0.0, 0.92);
	col = mix(col, grime_color, grime);
	ivec2 cell = clamp(ivec2(floor(UV * vec2(8.0, 4.0))), ivec2(0), ivec2(7, 3));
	if (((glow_cells >> (cell.y * 8 + cell.x)) & 1) == 1) {
		col = glow_color * 0.25;
		EMISSION = glow_color * glow_energy * (0.5 + luma);
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	RIM = rim_strength;
	RIM_TINT = 0.7;
}
