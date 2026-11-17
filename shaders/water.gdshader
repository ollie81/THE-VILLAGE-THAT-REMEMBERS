shader_type spatial;
// Stylised flowing river water. Procedural ripples, no textures, one pass.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.36, 0.66, 0.7, 0.62);
uniform vec4 deep_color : source_color = vec4(0.1, 0.3, 0.42, 0.9);
uniform float flow_speed = 0.4;
uniform float night_factor = 0.0;

varying float edge;

void vertex() {
	VERTEX.y += sin(VERTEX.z * 0.6 + TIME * 1.3) * 0.03 + sin(VERTEX.x * 0.9 - TIME) * 0.02;
	edge = abs(UV.x - 0.5) * 2.0;
}

void fragment() {
	vec2 uv = UV * vec2(5.0, 60.0);
	float t = TIME * flow_speed;
	float r1 = sin(uv.y * 2.3 - t * 6.0 + sin(uv.x * 2.1 + t));
	float r2 = sin(uv.y * 4.1 - uv.x * 1.7 - t * 8.0);
	vec3 n = normalize(vec3(r2 * 0.07, 1.0, r1 * 0.1));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec4 c = mix(deep_color, shallow_color, smoothstep(0.35, 0.95, edge));
	ALBEDO = c.rgb * (1.0 - night_factor * 0.5);
	ALPHA = c.a;
	ROUGHNESS = 0.07;
	SPECULAR = 0.65;
	float sparkle = smoothstep(0.9, 1.0, r1 * r2);
	EMISSION = vec3(sparkle * 0.08 * (1.0 - night_factor));
}
