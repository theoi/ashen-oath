shader_type spatial;
// Murky crypt water: two drifting normal maps, a sharp specular so lights and the moon glint
// off it, a fresnel sheen in the arena's soul colour, drifting scum and silt murk_patches, and
// more opacity at grazing angles. Cheap enough for the Compatibility renderer (no screen or
// depth reads).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 water_color : source_color = vec3(0.01, 0.02, 0.025);
uniform vec3 sheen_color : source_color = vec3(0.25, 0.6, 0.5);
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_scale = 0.12;
uniform float ripple_strength = 0.35;
uniform sampler2D murk_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 murk_color : source_color = vec3(0.03, 0.035, 0.025);
uniform float murk : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * ripple_scale;
	vec3 a = texture(ripple_a, uv + TIME * vec2(0.011, 0.004)).rgb;
	vec3 b = texture(ripple_b, uv * 1.7 - TIME * vec2(0.006, 0.013)).rgb;
	float scum = texture(murk_noise, world_pos.xz * 0.09 + TIME * vec2(0.002, 0.001)).r;
	float silt = texture(murk_noise, world_pos.xz * 0.37 - TIME * vec2(0.004, 0.003)).r;
	float murk_patch = smoothstep(0.45, 0.75, scum * 0.75 + silt * 0.4) * murk;
	NORMAL_MAP = normalize(mix(mix(a, b, 0.5), vec3(0.5, 0.5, 1.0), murk_patch * 0.7));
	NORMAL_MAP_DEPTH = ripple_strength;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(water_color, murk_color * (0.6 + 0.6 * silt), murk_patch);
	ROUGHNESS = mix(0.06, 0.5, murk_patch);
	METALLIC = 0.0;
	SPECULAR = mix(0.7, 0.25, murk_patch);
	EMISSION = sheen_color * fresnel * 0.14 * (1.0 - murk_patch);
	ALPHA = mix(mix(opacity, 1.0, fresnel), 1.0, murk_patch * 0.8);
}
