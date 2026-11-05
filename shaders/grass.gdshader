shader_type spatial;
// Two-sided grass blades with a gentle, cheap wind sway.
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float wind_strength = 0.12;
uniform float wind_speed = 1.6;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * wind_speed + world.x * 0.35 + world.z * 0.27) * wind_strength * VERTEX.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.5;
}

void fragment() {
	// Vertex colours are authored in sRGB.
	ALBEDO = OUTPUT_IS_SRGB ? COLOR.rgb : pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.95;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
