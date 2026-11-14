shader_type spatial;
// Textured ground: real grass, dirt-path and cobblestone photo textures
// (Poly Haven, CC0) blended per vertex. COLOR.rgb is the old hand-picked tint
// (it keeps meadows, forest floor, sand and rock apart); UV2.x = cobble weight,
// UV2.y = dirt weight; grass is what's left. Textures are mapped in world
// space so tiles line up across the whole map.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D cobble_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float grass_scale = 0.16;
uniform float dirt_scale = 0.3;
uniform float cobble_scale = 0.32;
uniform float tint_strength = 0.32;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	// Two scales of grass break up visible tiling.
	vec3 grass = texture(grass_albedo, p * grass_scale).rgb;
	grass = mix(grass, texture(grass_albedo, p * grass_scale * 0.23 + vec2(0.37, 0.71)).rgb, 0.35);
	vec3 dirt = texture(dirt_albedo, p * dirt_scale).rgb;
	vec3 cobble = texture(cobble_albedo, p * cobble_scale).rgb;
	float c = clamp(UV2.x, 0.0, 1.0);
	float d = clamp(UV2.y, 0.0, 1.0) * (1.0 - c);
	float g = 1.0 - c - d;
	// The vertex tint, normalised around mid-grey so it shifts hue and
	// brightness without flattening the photo detail.
	vec3 tint = mix(vec3(1.0), COLOR.rgb * 1.9, tint_strength * (g + d * 0.6));
	grass *= vec3(0.8, 0.9, 0.7);
	ALBEDO = (grass * g + dirt * d + cobble * c) * tint;
	vec3 n_g = texture(grass_normal, p * grass_scale).rgb;
	vec3 n_d = texture(dirt_normal, p * dirt_scale).rgb;
	vec3 n_c = texture(cobble_normal, p * cobble_scale).rgb;
	NORMAL_MAP = n_g * g + n_d * d + n_c * c;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = mix(0.95, 0.82, c);
	SPECULAR = 0.25;
}
