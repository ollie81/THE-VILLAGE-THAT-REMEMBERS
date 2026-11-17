shader_type sky;
// Stylised gradient sky with a sun disc, moon and stars.
// Colours are driven by DayNightCycle; nothing here samples textures.

uniform vec4 top_color : source_color = vec4(0.25, 0.48, 0.85, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.7, 0.82, 0.92, 1.0);
uniform vec4 ground_color : source_color = vec4(0.3, 0.33, 0.3, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform float star_intensity = 0.0;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color.rgb, top_color.rgb, pow(clamp(h, 0.0, 1.0), 0.55));
	} else {
		col = mix(horizon_color.rgb, ground_color.rgb, clamp(-h * 5.0, 0.0, 1.0));
	}

	vec3 sun_dir = normalize(sun_direction);
	float sun_dot = max(dot(dir, sun_dir), 0.0);
	float sun_visible = smoothstep(-0.15, 0.05, sun_dir.y);
	col += sun_color.rgb * pow(sun_dot, 10.0) * 0.35 * sun_visible;
	col += sun_color.rgb * smoothstep(0.9993, 0.9996, sun_dot) * 8.0 * sun_visible;

	if (!AT_CUBEMAP_PASS) {
		vec3 moon_dir = normalize(moon_direction);
		float moon_dot = max(dot(dir, moon_dir), 0.0);
		float moon_visible = smoothstep(-0.05, 0.1, moon_dir.y) * star_intensity;
		col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9990, 0.9993, moon_dot) * 1.6 * moon_visible;
		col += vec3(0.3, 0.38, 0.55) * pow(moon_dot, 40.0) * 0.25 * moon_visible;

		vec3 cell = dir * 140.0;
		vec3 id = floor(cell);
		float d = length(fract(cell) - 0.5);
		float star = step(0.9965, hash(id)) * smoothstep(0.32, 0.0, d);
		star *= 0.6 + 0.4 * hash(id + 3.1);
		col += vec3(star) * star_intensity * smoothstep(0.0, 0.25, h) * 1.4;
	}
	COLOR = col;
}
