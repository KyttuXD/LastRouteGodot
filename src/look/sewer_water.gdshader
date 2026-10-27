shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Shallow, murky flowing sewer water. COLOR.r / COLOR.b say whether the
// channel runs along x or z, so the ripples drift downstream in both channels
// of the main cross. Stays matte-ish (MaterialLook: no mirror sheen).
uniform vec3 deep_color : source_color = vec3(0.17, 0.27, 0.20);
uniform vec3 foam_color : source_color = vec3(0.50, 0.60, 0.44);
uniform float flow_speed = 0.55;
uniform float alpha = 0.9;

float ripple(vec2 p) {
	return sin(p.x * 3.1 + sin(p.y * 1.7)) * 0.5 + sin(p.y * 4.3 - p.x * 0.9) * 0.5;
}

void fragment() {
	vec2 flow = vec2(COLOR.r, COLOR.b);
	vec2 p = UV - flow * TIME * flow_speed;
	float r = ripple(p * 1.3) * 0.5 + ripple(p * 2.7 + 4.0) * 0.5;
	float foam = smoothstep(0.55, 0.95, r);
	ALBEDO = mix(deep_color, foam_color, foam * 0.75);
	// a wet sheen so lamps and torchlight glint on the moving surface
	ROUGHNESS = mix(0.32, 0.5, foam);
	SPECULAR = 0.45;
	ALPHA = alpha;
}
