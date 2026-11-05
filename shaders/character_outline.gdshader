shader_type spatial;
// Inverted-hull outline drawn as a second pass on characters. The width
// grows with camera distance so it stays about the same on screen (roughly
// 1-2 pixels at the game's camera angle). Skin, small facial details, glasses and
// buckles get no outline.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

// World-space width per metre of camera distance.
uniform float width_per_metre = 0.0013;
uniform float darkness = 0.22;

void vertex() {
	int surface = int(UV.x + 0.5);
	float width = 0.0;
	// Skin is left unoutlined so noses, ears and fingers stay soft.
	if (surface != 0 && surface != 3 && surface != 5) {
		vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		width = clamp(-view_position.z * width_per_metre, 0.0009, 0.02);
	}
	VERTEX += NORMAL * width;
}

void fragment() {
	vec3 base = OUTPUT_IS_SRGB ? COLOR.rgb : pow(COLOR.rgb, vec3(2.2));
	ALBEDO = base * darkness;
}
