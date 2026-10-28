shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

// Deep, murky flowing sewer water (docs/SEWERS.md). COLOR.r / COLOR.b say
// whether the channel runs along x or z, so the ripples drift downstream in both
// channels of the main cross. The depth buffer gives how much water lies
// between the surface and the bed or trench wall behind it: shallow edges stay
// see-through and greenish, the middle of the channel goes dark and opaque.
uniform vec3 shallow_color : source_color = vec3(0.22, 0.32, 0.24);
uniform vec3 deep_color : source_color = vec3(0.03, 0.06, 0.05);
uniform vec3 foam_color : source_color = vec3(0.50, 0.60, 0.44);
uniform float flow_speed = 0.55;
uniform float depth_fade = 0.75;   // metres of water until it reads as fully deep
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

float ripple(vec2 p) {
	return sin(p.x * 3.1 + sin(p.y * 1.7)) * 0.5 + sin(p.y * 4.3 - p.x * 0.9) * 0.5;
}

void fragment() {
	vec2 flow = vec2(COLOR.r, COLOR.b);
	vec2 p = UV - flow * TIME * flow_speed;
	float r = ripple(p * 1.3) * 0.5 + ripple(p * 2.7 + 4.0) * 0.5;
	float foam = smoothstep(0.6, 0.95, r);

	// Linear distance from the camera to what is behind the water, minus the
	// distance to the water surface itself: the thickness of water in view.
	float scene_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	behind.xyz /= behind.w;
	float thickness = max(VERTEX.z - behind.z, 0.0);
	float deep = clamp(thickness / depth_fade, 0.0, 1.0);

	vec3 body = mix(shallow_color, deep_color, deep);
	ALBEDO = mix(body, foam_color, foam * 0.55 * (1.0 - deep * 0.5));
	// a wet sheen so lamps and torchlight glint on the moving surface
	ROUGHNESS = mix(0.3, 0.5, foam);
	SPECULAR = 0.45;
	ALPHA = mix(0.55, 0.96, deep);
}
