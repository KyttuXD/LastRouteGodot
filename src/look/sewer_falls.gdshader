shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// The waterfall from the first sewer into the collector (docs/SEWERS.md): a sheet
// of murky water pouring straight down, streaks racing down it, frothing white
// toward the bottom where it hits the pool. Unshaded so it reads in the dark.
uniform vec3 water_color : source_color = vec3(0.26, 0.36, 0.30);
uniform vec3 froth_color : source_color = vec3(0.78, 0.84, 0.78);
uniform float speed = 2.4;

float streak(vec2 p) {
	return fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = vec2(UV.x * 18.0, UV.y * 3.0 - TIME * speed);
	float s = streak(vec2(p.x, p.y * 2.0)) * 0.6 + streak(vec2(p.x * 0.5 + 3.0, p.y)) * 0.4;
	float froth = smoothstep(0.55, 1.0, UV.y) * 0.7 + smoothstep(0.75, 0.95, s) * 0.4;
	ALBEDO = mix(water_color, froth_color, clamp(froth, 0.0, 1.0));
	// thin at the edges of the sheet, solid in the middle
	float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x);
	ALPHA = edge * mix(0.55, 0.9, s);
}
