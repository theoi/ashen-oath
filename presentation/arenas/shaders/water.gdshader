shader_type spatial;
// Black crypt water: two drifting normal maps, sharp specular so lights and the moon
// glint off it, a fresnel sheen in the arena's soul colour, and more opacity at grazing
// angles. Cheap enough for the Compatibility renderer (no screen or depth reads).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 water_color : source_color = vec3(0.01, 0.02, 0.025);
uniform vec3 sheen_color : source_color = vec3(0.25, 0.6, 0.5);
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_scale = 0.12;
uniform float ripple_strength = 0.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * ripple_scale;
	vec3 a = texture(ripple_a, uv + TIME * vec2(0.011, 0.004)).rgb;
	vec3 b = texture(ripple_b, uv * 1.7 - TIME * vec2(0.006, 0.013)).rgb;
	NORMAL_MAP = normalize(mix(a, b, 0.5));
	NORMAL_MAP_DEPTH = ripple_strength;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = water_color;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	EMISSION = sheen_color * fresnel * 0.18;
	ALPHA = mix(opacity, 1.0, fresnel);
}
