// Shared stylised character shading.
// UV.x  = surface type (SkinnedMeshTool.Surface): 0 skin, 1 cloth, 2 leather,
//         3 metal, 4 hair, 5 detail, 6 straw.
// UV.y, UV2.xy = rest-pose position, so patterns stay glued to the body.
// COLOR = authored sRGB base colour.

varying vec3 v_rest;
varying float v_surface;

uniform vec3 shadow_tint : source_color = vec3(0.62, 0.66, 0.86);
uniform float pattern_strength = 1.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	v_rest = vec3(UV2.x, UV2.y, UV.y);
	v_surface = UV.x;
}

void fragment() {
	// Vertex colours are sRGB. Linear renderers need them converted; the
	// Compatibility renderer (web, OpenGL) already works in sRGB.
	vec3 base = OUTPUT_IS_SRGB ? COLOR.rgb : srgb_to_linear(COLOR.rgb);
	int surface = int(v_surface + 0.5);
	// Fine patterns fade out with distance so they never shimmer.
	float pixel = length(fwidth(v_rest));
	float fine = (1.0 - smoothstep(0.0012, 0.006, pixel)) * pattern_strength;
	float medium = (1.0 - smoothstep(0.006, 0.03, pixel)) * pattern_strength;
	float rough = 0.85;
	float spec = 0.2;
	vec3 p = v_rest;

	if (surface == 0) {
		// Skin: very soft mottling, slightly warmer in the creases.
		float mottle = vnoise(p * 55.0) - 0.5;
		base *= 1.0 + mottle * 0.04 * medium;
		// Slightly richer skin tone in the mid-tones.
		base = mix(vec3(dot(base, vec3(0.3, 0.59, 0.11))), base, 1.08);
		rough = 0.62;
		spec = 0.32;
	} else if (surface == 1) {
		// Woven cloth with soft folds.
		float weave = sin((p.x + p.z) * 1300.0) * sin(p.y * 1300.0);
		float threads = vnoise(p * vec3(320.0, 40.0, 320.0)) - 0.5;
		// Gentle horizontal creases, like fabric bunching around limbs.
		float folds = vnoise(p * vec3(9.0, 26.0, 9.0));
		base *= 1.0 + (weave * 0.04 + threads * 0.05) * fine;
		base *= mix(1.0, 0.93 + folds * 0.1, medium);
		rough = 0.92;
		spec = 0.12;
	} else if (surface == 2) {
		// Leather: pebbled grain, scuffed lighter patches, stitched edges read
		// as darker seams.
		float grain = vnoise(p * 260.0) - 0.5;
		float wear = smoothstep(0.55, 0.85, vnoise(p * 18.0));
		base *= 1.0 + grain * 0.12 * fine;
		base = mix(base, base * 1.35, wear * 0.35 * medium);
		rough = 0.5;
		spec = 0.42;
	} else if (surface == 3) {
		rough = 0.28;
		spec = 0.85;
	} else if (surface == 4) {
		// Hair: strands run mostly vertically, with soft clumps.
		float strands = vnoise(vec3(p.x * 420.0, p.y * 18.0, p.z * 420.0)) - 0.5;
		float clumps = vnoise(vec3(p.x * 60.0, p.y * 6.0, p.z * 60.0)) - 0.5;
		base *= 1.0 + (strands * 0.28 * fine + clumps * 0.22 * medium);
		rough = 0.45;
		spec = 0.5;
	} else if (surface == 6) {
		// Straw: woven diagonal bands.
		float weave = sin((p.x + p.y) * 600.0) * sin((p.z - p.y) * 600.0);
		base *= 1.0 + weave * 0.1 * fine + (vnoise(p * 90.0) - 0.5) * 0.12 * medium;
		rough = 0.85;
		spec = 0.15;
	}
	ALBEDO = base;
	// Only used by the engine's ambient terms; direct light is in light().
	ROUGHNESS = rough;
	SPECULAR = spec * 0.5;
}

// Soft, slightly painterly lighting: a gentle terminator, cool tinted
// shadows, warm light bleeding through skin at the shadow edge, a fabric
// sheen and small stylised highlights. Cheap enough for mobile.
void light() {
	int surface = int(v_surface + 0.5);
	float ndl = dot(NORMAL, LIGHT);
	// Soft terminator, but energy close to normal Lambert so colours don't
	// blow out in sunlight.
	float soft = smoothstep(-0.12, 0.42, ndl);
	float wrap = clamp((ndl + 0.6) / 1.6, 0.0, 1.0);
	float lit = clamp(ndl, 0.0, 1.0) * 0.78 + 0.18;
	vec3 shade = mix(shadow_tint * 0.32 * wrap, vec3(lit), soft);
	vec3 light_color = LIGHT_COLOR * ATTENUATION / PI;
	vec3 diffuse = light_color * shade;
	if (surface == 0) {
		float edge = soft * (1.0 - soft) * 4.0;
		diffuse += light_color * vec3(0.5, 0.14, 0.06) * edge * 0.14;
	}
	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim_amount = surface == 1 ? 0.2 : (surface == 4 ? 0.12 : 0.06);
	diffuse += light_color * pow(facing, 3.0) * rim_amount * soft;
	DIFFUSE_LIGHT += diffuse;

	// Highlight size and strength per surface.
	float gloss = 12.0;
	float strength = 0.02;
	if (surface == 0) { gloss = 18.0; strength = 0.06; }
	else if (surface == 2) { gloss = 32.0; strength = 0.22; }
	else if (surface == 3) { gloss = 70.0; strength = 0.9; }
	else if (surface == 4) { gloss = 40.0; strength = 0.05; }
	else if (surface == 5) { gloss = 60.0; strength = 0.25; }
	vec3 half_vector = normalize(LIGHT + VIEW);
	float nh = clamp(dot(NORMAL, half_vector), 0.0, 1.0);
	float highlight = pow(nh, gloss) * (gloss + 8.0) / 24.0;
	if (surface == 4) {
		// A soft band highlight on hair.
		highlight = smoothstep(0.9, 0.99, nh) * 0.6;
	}
	SPECULAR_LIGHT += light_color * highlight * strength * soft;
}
