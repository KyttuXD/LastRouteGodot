shader_type spatial;

// One material for every painted floor/ceiling (or wall) of a chunk. The layer
// of the Texture2DArray rides in UV2.x and the surface response in COLOR
// (r = roughness, g = metallic, b = emission), so a whole chunk is two draw
// calls instead of one per tile kind.

uniform sampler2DArray tex : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
// Specular of dielectrics and of metal floors (MaterialLook): low by default, no glints.
uniform float specular_base = 0.18;
uniform float specular_metal = 0.32;

varying flat float v_layer;
varying vec3 v_params;

void vertex() {
	v_layer = UV2.x;
	v_params = COLOR.rgb;
}

void fragment() {
	vec3 c = texture(tex, vec3(UV, v_layer)).rgb;
	ALBEDO = c * tint;
	ROUGHNESS = v_params.x;
	METALLIC = v_params.y;
	SPECULAR = specular_base + (specular_metal - specular_base) * clamp(v_params.y / 0.18, 0.0, 1.0);
	EMISSION = c * v_params.z;
}
