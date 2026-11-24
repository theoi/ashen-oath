shader_type spatial;
// Recolors the KayKit gradient atlas into the cold, desaturated "stylized grim" palette and
// dirties it: blotchy world-space grime, per-stone value breakup so the stonework stops
// looking clean, damp rising from the floor, soot staining the upper walls, vertical drip
// streaks, sparse old blood-dark stains on the floor and a darkening falloff away from the
// fight area (the fighters' light pool). Chosen atlas cells glow (flames, lantern glass) or
// take the blood-dark tone (banners). One shared material per KayKit pack. For the fixed
// high gameplay camera it also cuts camera-side walls down and dithers out occluders.
render_mode diffuse_lambert, cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.82, 0.86, 0.95);
uniform float desaturate : hint_range(0.0, 1.0) = 0.6;
uniform float brightness = 0.85;
uniform float contrast = 1.15;
uniform sampler2D grime_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grime_color : source_color = vec3(0.05, 0.045, 0.05);
uniform float grime_amount : hint_range(0.0, 1.0) = 0.45;
uniform float grime_scale = 0.07;
// Per-stone value jitter (0 = clean, uniform stones).
uniform float breakup = 0.0;
// Damp darkening and tint rising from the floor up the walls.
uniform vec3 damp_color : source_color = vec3(0.03, 0.04, 0.035);
uniform float damp_amount : hint_range(0.0, 1.0) = 0.45;
uniform float damp_height = 1.6;
// Soot staining walls from soot_start up.
uniform vec3 soot_color : source_color = vec3(0.015, 0.012, 0.012);
uniform float soot_amount : hint_range(0.0, 1.0) = 0.0;
uniform float soot_start = 2.5;
// Vertical drip streaks on walls.
uniform float streak_amount : hint_range(0.0, 1.0) = 0.0;
// Sparse dark stains on floors.
uniform vec3 stain_color : source_color = vec3(0.12, 0.015, 0.012);
uniform float stain_amount : hint_range(0.0, 1.0) = 0.0;
// Darkening away from the fight area: xy = centre (x, z), z = inner radius, w = outer radius.
uniform vec4 pool = vec4(0.0, 0.0, 8.0, 18.0);
uniform float pool_darken : hint_range(0.0, 1.0) = 0.0;
uniform float rim_strength = 0.35;
// Bit (row * 8 + column) of the 8x4 atlas grid marks a glowing cell.
uniform int glow_cells = 0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.55, 0.2);
uniform float glow_energy = 3.0;
// Cells recoloured to the stain (blood-dark) tone, e.g. banner cloth.
uniform int stain_cells = 0;
// Gameplay-camera cutaway: fragments outside any of these floor edges (xy = a point on the
// edge, zw = outward normal, in x-z) and above the ragged cut height are removed, so the
// camera-side walls drop to low broken stubs. Back faces then show as a dark solid cap.
uniform vec4 cut_edges[8];
uniform int cut_edge_count = 0;
uniform float cut_height = 1.0;
uniform vec3 cap_color : source_color = vec3(0.06, 0.058, 0.062);
// Occluder fade: anything above the floor between the camera and these points (xyz world,
// w = radius in metres, 0 = unused) dithers down to occluder_alpha.
uniform vec4 occluder_targets[4];
uniform float occluder_alpha = 0.25;

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	if (cut_edge_count > 0) {
		float ragged = cut_height + (texture(grime_noise, vec2(world_pos.x + world_pos.z, world_pos.y) * 0.21).r - 0.5) * 0.7;
		if (world_pos.y > ragged) {
			for (int i = 0; i < cut_edge_count; i++) {
				if (dot(world_pos.xz - cut_edges[i].xy, cut_edges[i].zw) > -0.02) {
					discard;
				}
			}
		}
	}
	if (world_pos.y > 0.3) {
		float keep = 1.0;
		for (int i = 0; i < 4; i++) {
			vec4 t = occluder_targets[i];
			if (t.w <= 0.0) {
				continue;
			}
			vec3 tv = (VIEW_MATRIX * vec4(t.xyz, 1.0)).xyz;
			if (-VERTEX.z < -tv.z - t.w * 0.5) {
				vec2 a = VERTEX.xy / -VERTEX.z;
				vec2 b = tv.xy / -tv.z;
				float d = length(a - b) / (t.w / -tv.z);
				keep = min(keep, mix(occluder_alpha, 1.0, smoothstep(0.75, 1.15, d)));
			}
		}
		if (keep < 1.0) {
			// 4x4 ordered dither: cheap stable transparency without sorting.
			ivec2 q = ivec2(FRAGCOORD.xy) % 4;
			float threshold = (BAYER[q.x + q.y * 4] + 0.5) / 16.0;
			if (threshold >= keep) {
				discard;
			}
		}
	}
	vec3 base = texture(atlas, UV).rgb;
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 col = mix(base, vec3(luma), desaturate);
	col = clamp((col - 0.5) * contrast + 0.5, 0.0, 1.0) * tint * brightness;

	float wall = 1.0 - abs(world_normal.y);
	float up = clamp(world_normal.y, 0.0, 1.0);
	// Planar coordinates along the surface: x-z on floors, along-wall + height on walls.
	vec2 along = abs(world_normal.x) > abs(world_normal.z) ? world_pos.zy : world_pos.xy;
	vec2 surface = mix(world_pos.xz, along, step(0.5, wall));

	// Uneven stones: a value jitter per ~0.7 m cell.
	float stone = hash12(floor(surface * 1.4 + 17.0));
	col *= 1.0 - breakup * stone;

	// Blotchy grime at two scales.
	float n_large = texture(grime_noise, surface * grime_scale).r;
	float n_fine = texture(grime_noise, surface * grime_scale * 5.3 + 0.37).r;
	float grime = smoothstep(0.3, 0.85, n_large * 0.7 + n_fine * 0.45);
	col = mix(col, grime_color, grime_amount * grime);

	// Damp rising from the floor, ragged at its top edge.
	float tide = damp_height * (0.75 + 0.5 * n_fine);
	float damp = (1.0 - smoothstep(0.0, tide, world_pos.y)) * wall + up * 0.12;
	col = mix(col, col * damp_color * 6.0, damp_amount * clamp(damp, 0.0, 1.0));

	// Drip streaks: noise stretched vertically, strongest just under ledges.
	float streak = texture(grime_noise, vec2(surface.x * 1.7, world_pos.y * 0.08)).r;
	streak = smoothstep(0.55, 0.8, streak) * wall;
	col = mix(col, grime_color, streak_amount * streak);

	// Soot climbing the upper walls.
	float soot = smoothstep(soot_start, soot_start + 3.0, world_pos.y + n_large * 1.5) * wall;
	col = mix(col, soot_color, soot_amount * soot);

	// Old stains pooled on the floor, kept sparse.
	float stain = smoothstep(0.78, 0.86, texture(grime_noise, surface * 0.11 + 5.1).r) * up;
	col = mix(col, stain_color * (0.6 + 0.4 * n_fine), stain_amount * stain);

	// Fight-area light pool: everything further out sinks into darkness.
	float dist = length(world_pos.xz - pool.xy);
	col *= 1.0 - pool_darken * smoothstep(pool.z, pool.w, dist);

	ivec2 cell = clamp(ivec2(floor(UV * vec2(8.0, 4.0))), ivec2(0), ivec2(7, 3));
	int bit = cell.y * 8 + cell.x;
	if (((stain_cells >> bit) & 1) == 1) {
		col = stain_color * (0.5 + luma) * (1.0 - 0.4 * grime);
	}
	if (((glow_cells >> bit) & 1) == 1) {
		col = glow_color * 0.25;
		EMISSION = glow_color * glow_energy * (0.5 + luma);
	}
	if (!FRONT_FACING) {
		col = cap_color;
		EMISSION = vec3(0.0);
	}
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15 + 0.25 * damp_amount * clamp(damp, 0.0, 1.0);
	RIM = rim_strength;
	RIM_TINT = 0.7;
}
