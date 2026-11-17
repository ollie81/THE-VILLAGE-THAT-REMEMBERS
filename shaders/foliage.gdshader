shader_type spatial;
render_mode cull_disabled;
// Leaves of the real tree models: cut-out (alpha scissor) and swaying in
// the wind, more at the top of the tree. Weather sets wind_strength.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_cut = 0.45;
uniform float wind_strength = 0.012;
uniform float wind_speed = 1.3;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float gust = sin(TIME * wind_speed + world.x * 0.21 + world.z * 0.17) + 0.4 * sin(TIME * wind_speed * 2.3 + world.z * 0.5);
	VERTEX.x += gust * wind_strength * h;
	VERTEX.z += gust * wind_strength * h * 0.6;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.9;
}
