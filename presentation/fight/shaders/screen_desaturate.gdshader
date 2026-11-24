shader_type canvas_item;
// Full-screen desaturate and darken (awakening camera moment). Glowing VFX stay bright
// because highlights are kept above `keep`.
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float keep = 0.75;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float hot = smoothstep(keep, keep + 0.2, max(c.r, max(c.g, c.b)));
	vec3 grey = vec3(l) * (1.0 - 0.35 * amount);
	COLOR = vec4(mix(c, mix(grey, c, hot), amount), 1.0);
}
