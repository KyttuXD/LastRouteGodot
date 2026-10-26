shader_type canvas_item;

// Full-screen pixel-art grade for the "reference look": block-resolution
// sampling, ordered dithering into a limited tone ladder, a plum/brass grade
// and a heavy vignette. Drawn on a CanvasLayer below the HUD, so UI stays crisp.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
// Virtual resolution of the pixel grid (screen is sampled once per block).
uniform vec2 grid = vec2(427.0, 240.0);
// Tone levels per channel after dithering; lower = chunkier palette.
uniform float levels = 20.0;
uniform float dither = 0.5;
uniform float vignette = 0.62;
uniform float vignette_soft = 0.9;
uniform vec3 shadow_tint : source_color = vec3(0.050, 0.014, 0.034);
uniform vec3 mid_tint : source_color = vec3(0.62, 0.45, 0.34);
uniform float grade_amount = 0.55;
uniform float saturation = 1.04;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	// 4x4 Bayer matrix, normalised to 0..1
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
			3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return m[i] / 16.0;
}

void fragment() {
	vec2 cell = floor(SCREEN_UV * grid);
	vec2 uv = (cell + 0.5) / grid;
	// Four taps inside the block keep thin lines stable while the camera moves.
	vec2 q = 0.25 / grid;
	vec3 c = texture(screen_tex, uv + vec2(-q.x, -q.y)).rgb
		+ texture(screen_tex, uv + vec2(q.x, -q.y)).rgb
		+ texture(screen_tex, uv + vec2(-q.x, q.y)).rgb
		+ texture(screen_tex, uv + vec2(q.x, q.y)).rgb;
	c *= 0.25;

	// Colour grade: blacks lean plum, midtones lean brass, saturation held.
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, c * (vec3(1.0) + mid_tint * 0.55), grade_amount * smoothstep(0.02, 0.35, l));
	c += shadow_tint * (1.0 - smoothstep(0.0, 0.20, l)) * grade_amount;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, saturation);

	// Ordered dither, then quantise to the tone ladder.
	float d = (bayer4(cell) - 0.5) * dither;
	c = floor(c * levels + 0.5 + d) / levels;

	// Vignette in screen space.
	vec2 v = SCREEN_UV - 0.5;
	v.x *= 1.05;
	float vig = smoothstep(vignette, vignette - vignette_soft * 0.6, length(v));
	c *= mix(0.18, 1.0, vig);

	COLOR = vec4(c, 1.0);
}
