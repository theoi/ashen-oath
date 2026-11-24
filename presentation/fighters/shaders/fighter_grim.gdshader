shader_type spatial;
// "Stylized grim" restyle of a KayKit character atlas (8 x 4 colour cells): cold,
// desaturated recolour, per-cell tint overrides, grime and wear, a strong coloured rim
// for silhouette separation in dark arenas, glowing cells (ember seams, lantern glass,
// eyes), a hit flash and an optional shade/ember look (Oath-Shade). One material
// instance per fighter so flashes stay per fighter.
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
// Grime: dark patches that gather toward the feet. Needs the rest-pose position that
// FighterModel bakes into CUSTOM0 (skinned positions would make the dirt swim).
uniform float grime = 0.0;
uniform vec3 grime_color : source_color = vec3(0.07, 0.06, 0.05);
uniform float grime_scale = 5.0;
// Wear: pale scratches on raised edges.
uniform float wear = 0.0;
// Glowing cracks (Aldric's Oathfire under his armour) on the cells in crack_cells.
uniform int crack_cells = 0;
uniform vec3 crack_color : source_color = vec3(1.0, 0.35, 0.06);
uniform float crack_energy = 2.5;
uniform float crack_scale = 4.0;
uniform float crack_width = 0.06;
// Fraction of cell borders that crack open (0..1).
uniform float crack_density = 0.5;
// Bit (row * 8 + column) of the atlas grid marks a glowing cell.
uniform int glow_cells = 0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.45, 0.12);
uniform float glow_energy = 2.5;
uniform float glow_pulse = 0.0;
// Hit / armour / parry flash (presentation only).
uniform vec3 flash_color : source_color = vec3(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
// Ash dissolve on death (0 = whole, 1 = gone): the body burns away from the head down
// with an ember edge.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dissolve_edge : source_color = vec3(1.0, 0.45, 0.12);
// Shade look: darkens the body to smoky black with ember fresnel (Oath-Shade).
uniform float shade_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 shade_edge : source_color = vec3(1.0, 0.35, 0.08);

varying vec3 rest_pos;

void vertex() {
	rest_pos = CUSTOM0.xyz;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return noise(p) * 0.55 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.15;
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

// Distance to the nearest cell border of a 3D Voronoi pattern.
float voronoi_edge(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 r = g + hash3(cell + g) - f;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void fragment() {
	vec3 base = texture(atlas, UV).rgb;
	ivec2 cell = clamp(ivec2(floor(UV * vec2(8.0, 4.0))), ivec2(0), ivec2(7, 3));
	vec4 cell_tint = texelFetch(cell_tints, cell, 0);
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 col = mix(vec3(luma), base, mix(1.0 - desaturate, 1.0, cell_tint.a));
	col = clamp((col - 0.5) * contrast + 0.5, 0.0, 1.0) * tint * cell_tint.rgb * brightness;
	float rough = 0.85;
	bool glowing = ((glow_cells >> (cell.y * 8 + cell.x)) & 1) == 1;
	if (grime > 0.0 && !glowing) {
		float n = fbm(rest_pos * grime_scale);
		// Dirt climbs from the boots (rest y ~ 0) and fades by the chest.
		float low = 1.0 - smoothstep(0.0, 1.6, rest_pos.y);
		float dirt = smoothstep(0.5, 0.78, n + low * 0.35) * grime;
		col = mix(col, grime_color, dirt * 0.75);
		rough = mix(rough, 1.0, dirt);
		float scratch = smoothstep(0.82, 0.9, noise(rest_pos * grime_scale * vec3(9.0, 1.2, 9.0)));
		col += vec3(0.08, 0.08, 0.09) * scratch * wear * (1.0 - dirt);
	}
	vec3 emission = vec3(0.0);
	if (((crack_cells >> (cell.y * 8 + cell.x)) & 1) == 1) {
		float edge = voronoi_edge(rest_pos * crack_scale);
		// Only some borders crack open, so the armour reads as fractured, not tiled.
		float open = smoothstep(0.92 - crack_density, 1.0 - crack_density, noise(rest_pos * crack_scale * 0.7));
		float crack = (1.0 - smoothstep(0.0, crack_width, edge)) * open;
		float flicker = 0.75 + 0.25 * sin(TIME * 4.0 + rest_pos.y * 11.0);
		col = mix(col, crack_color * 0.15, crack);
		emission += crack_color * crack_energy * crack * flicker;
	}
	if (glowing) {
		float pulse = 1.0 + glow_pulse * sin(TIME * 7.0 + luma * 6.0) * 0.35;
		col = mix(col, glow_color * 0.3, 0.7);
		emission = glow_color * glow_energy * (0.45 + luma) * pulse;
	}
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);
	// A wide falloff: from the high fight camera the silhouette edges are thin.
	float rim = pow(1.0 - facing, 1.4);
	if (shade_amount > 0.0) {
		// Smoke drifting over the body breaks the ember edge into licks of flame.
		float smoke = fbm(rest_pos * 3.0 + vec3(0.0, -TIME * 0.8, 0.0));
		col = mix(col, vec3(0.015, 0.013, 0.02), shade_amount * 0.95);
		float edge = pow(1.0 - facing, 4.0) * smoothstep(0.35, 0.7, smoke);
		emission += shade_edge * edge * 2.4 * shade_amount;
	}
	// A coloured rim that does not depend on scene lights keeps the silhouette readable
	// against dark arenas.
	emission += rim_color * rim * rim_strength * 0.7;
	// The flash reads as a rim-weighted glow so the model keeps its shape.
	emission += flash_color * flash_amount * (0.35 + 1.6 * fres);
	if (dissolve > 0.0) {
		// Burns from the top: higher rest positions go first, noise breaks the line.
		float n = fbm(rest_pos * 6.0) * 0.6 + (1.0 - clamp(rest_pos.y / 2.2, 0.0, 1.0)) * 0.4;
		float cut = dissolve * 1.15;
		if (n < cut) {
			discard;
		}
		float edge = 1.0 - smoothstep(0.0, 0.07, n - cut);
		col = mix(col, vec3(0.03), smoothstep(0.0, 0.5, dissolve));
		emission += dissolve_edge * edge * 4.0;
	}
	ALBEDO = mix(col, flash_color, flash_amount * 0.25);
	EMISSION = emission;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
	RIM = rim_strength;
	RIM_TINT = 0.6;
}
