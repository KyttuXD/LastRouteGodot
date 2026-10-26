shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

// Glossy-floor reflection of a lamp: a vertical-looking streak that always
// lies on the floor along the line from the lamp's foot toward the camera,
// the way a wet floor mirrors a light source.

uniform sampler2D streak_tex : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.26, 1.0);
uniform float length_m = 2.6;
uniform float width_m = 0.75;
uniform float fade_distance = 16.0;

varying float vis;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 f = CAMERA_POSITION_WORLD - center;
	float d = length(f.xz);
	f.y = 0.0;
	f = normalize(f + vec3(0.0001));
	vec3 r = vec3(-f.z, 0.0, f.x);
	// quad spans -1..1 on x and z in local space
	float along = (VERTEX.z * 0.5 + 0.5) * length_m;
	vec3 world = center + r * VERTEX.x * width_m * 0.5 + f * along;
	vis = clamp(1.0 - d / fade_distance, 0.0, 1.0) * clamp(d / 1.5, 0.0, 1.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec4 t = texture(streak_tex, UV);
	ALBEDO = tint.rgb * t.rgb;
	ALPHA = t.a * vis;
}
