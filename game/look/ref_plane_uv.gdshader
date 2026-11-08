shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Arch and pilaster blocks (RefDecor): the wall's own pixel texture mapped from each face's own plane, so brick, tile
// and paper courses stay level and continuous on rotated and sloped arches (no triplanar blending, no stretch), and
// match the wall faces (RefSurfaceMesh.add_wall): u runs along the wall in metres, v counts storeys from the floor.
// RefDecor.plane_uv mirrors this for the wall_themes check; keep the two in step.

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float room_height = 4.0;
uniform float tiers = 1.0;
uniform float roughness_value = 0.92;
uniform float specular_value = 0.18;
uniform float metallic_value = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec2 uv;
	if (abs(n.y) > 0.95) {
		uv = world_pos.xz;
	} else {
		vec3 along = normalize(cross(vec3(0.0, 1.0, 0.0), n));
		float y = world_pos.y - NODE_POSITION_WORLD.y;
		uv = vec2(dot(world_pos, along), tiers * (1.0 - y / room_height));
	}
	vec4 texel = texture(albedo_tex, uv);
	ALBEDO = texel.rgb * tint.rgb;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	METALLIC = metallic_value;
}
