shader_type spatial;
// Weapon with molten cracks (Aldric's sword): cellular crack lines in the mesh's own
// space glow ember-hot over the recoloured atlas. Rigid weapons sit under a
// BoneAttachment3D, so object-space cracks stay fixed on the blade.
render_mode diffuse_lambert, cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.8, 0.82, 0.9);
uniform float desaturate : hint_range(0.0, 1.0) = 0.7;
uniform float brightness = 0.75;
uniform vec3 crack_color : source_color = vec3(1.0, 0.38, 0.08);
uniform float crack_energy = 3.0;
uniform float crack_scale = 9.0;
uniform float crack_width = 0.08;
// Only parts above this local height crack (the blade, not the grip).
uniform float crack_min_y = 0.3;
// 0..1 extra heat (Oathkeeper's ignited blade), also widens the cracks.
uniform float ignite : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
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
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 col = mix(base, vec3(luma), desaturate) * tint * brightness;
	float edge = voronoi_edge(local_pos * vec3(crack_scale, crack_scale * 0.45, crack_scale));
	float width = crack_width * (1.0 + ignite * 1.5);
	float crack = (1.0 - smoothstep(0.0, width, edge)) * smoothstep(crack_min_y - 0.05, crack_min_y + 0.05, local_pos.y);
	float pulse = 0.8 + 0.2 * sin(TIME * 5.0 + local_pos.y * 9.0);
	vec3 heat = crack_color * crack_energy * (crack * pulse + ignite * 0.35 * smoothstep(crack_min_y, crack_min_y + 0.2, local_pos.y));
	ALBEDO = mix(mix(col, crack_color * 0.2, crack), flash_color, flash_amount * 0.25);
	EMISSION = heat + flash_color * 0.6 * flash_amount;
	ROUGHNESS = 0.45;
	METALLIC = 0.6;
	SPECULAR = 0.5;
	RIM = 0.4;
}
