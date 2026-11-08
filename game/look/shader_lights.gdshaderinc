// Shader-computed lights for the chunk surfaces (docs/SHADER_LIGHTS.md).
//
// Included by ref_surface_lit.gdshader ONLY. It is used when a GPU's engine light path is broken (Apple's legacy OpenGL 4.1
// driver on Intel Macs lights nothing beyond about a metre): the flashlight cone and the lamp pool are computed here with
// Godot's own spot / omni formulas and added to the surface as EMISSION. Every number below has a twin in
// shader_lights.gd (ShaderLights); tests/validate_shader_lights.gd parses this file and compares them, so edit both.
//
// Lights arrive as plain vec4 uniforms (no uniform arrays, no global parameters: Godot 4.7 has no array globals, and a
// missing global would break the shared surface shader on every device).

const float SL_FLASH_DECAY = 1.0;        // the SpotLight3D's range attenuation (its default)
const float SL_LAMP_DECAY = 1.6;         // LampField's omni_attenuation
const float SL_STOREY = 4.0;             // StoreyLayers.STOREY
const float SL_BAND_OFFSET = 0.05;       // a floor lies on its storey's lower bound, a ceiling just under the upper one
const float SL_CLIP_R = 6.0;             // the wall-behind clip only darkens fragments this close to the beam's hit point
const float SL_CLIP_FADE = 2.0;
const float SL_CLIP_LO = -0.5;           // behind the hit plane by this much: fully clipped
const float SL_CLIP_HI = -0.2;           // by this much: not clipped

// x = flashlight gain, y = lamp gain (engine light units -> this shader's units; see docs/SHADER_LIGHTS.md, Calibration)
uniform vec2 sl_gain = vec2(2.1, 2.1);
uniform vec4 sl_flash_a = vec4(0.0, 0.0, 0.0, 16.0);        // xyz position, w range
uniform vec4 sl_flash_b = vec4(0.0, 0.0, -1.0, 0.8660254);  // xyz direction, w cos(spot angle)
uniform vec4 sl_flash_c = vec4(0.0, 0.0, 0.0, 1.4);         // rgb linear colour * energy (0 = off), w angle attenuation
uniform vec4 sl_flash_plane = vec4(0.0, 0.0, 1.0, 0.0);     // xyz normal facing the light, w = n . point on the hit surface
uniform vec4 sl_flash_hit = vec4(0.0);                      // xyz hit point, w = 1 when the clip is active
uniform vec4 sl_lamp_pos0 = vec4(0.0, 0.0, 0.0, 1.0);       // xyz position, w range
uniform vec4 sl_lamp_pos1 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sl_lamp_pos2 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sl_lamp_pos3 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sl_lamp_pos4 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sl_lamp_pos5 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sl_lamp_pos6 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sl_lamp_pos7 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sl_lamp_col0 = vec4(0.0);                      // rgb linear colour * unscaled energy * fade (0 = off)
uniform vec4 sl_lamp_col1 = vec4(0.0);
uniform vec4 sl_lamp_col2 = vec4(0.0);
uniform vec4 sl_lamp_col3 = vec4(0.0);
uniform vec4 sl_lamp_col4 = vec4(0.0);
uniform vec4 sl_lamp_col5 = vec4(0.0);
uniform vec4 sl_lamp_col6 = vec4(0.0);
uniform vec4 sl_lamp_col7 = vec4(0.0);

// Godot's get_omni_attenuation (scene.glsl): a quartic window over the range times distance ^ -decay.
float sl_att(float d, float range, float decay) {
	float nd = d / range;
	nd *= nd;
	nd *= nd;
	nd = max(1.0 - nd, 0.0);
	nd *= nd;
	return nd * pow(max(d, 0.0001), -decay);
}

// StoreyLayers: a light lights the structure of storeys with its own parity and nothing of the neighbouring ones.
bool sl_in_band(float y, float src_y) {
	float ds = floor((y + SL_BAND_OFFSET) / SL_STOREY) - floor(src_y / SL_STOREY);
	return mod(ds, 2.0) < 0.5;
}

vec3 sl_lamp(vec4 pos, vec4 col, vec3 wpos, vec3 wnor) {
	if (col.r + col.g + col.b <= 0.0 || !sl_in_band(wpos.y, pos.y)) {
		return vec3(0.0);
	}
	vec3 rel = pos.xyz - wpos;
	float d = length(rel);
	if (d >= pos.w) {
		return vec3(0.0);
	}
	return col.rgb * (sl_gain.y * sl_att(d, pos.w, SL_LAMP_DECAY) * max(dot(wnor, rel / max(d, 0.0001)), 0.0));
}

vec3 sl_beam(vec3 wpos, vec3 wnor) {
	vec3 fc = sl_flash_c.rgb;
	if (fc.r + fc.g + fc.b <= 0.0 || !sl_in_band(wpos.y, sl_flash_a.y)) {
		return vec3(0.0);
	}
	vec3 rel = sl_flash_a.xyz - wpos;
	float d = length(rel);
	if (d >= sl_flash_a.w) {
		return vec3(0.0);
	}
	vec3 L = rel / max(d, 0.0001);
	float scos = max(dot(-L, sl_flash_b.xyz), sl_flash_b.w);
	float rim = max(0.0001, (1.0 - scos) / (1.0 - sl_flash_b.w));
	float cone = 1.0 - pow(rim, sl_flash_c.w);
	float s = dot(sl_flash_plane.xyz, wpos) - sl_flash_plane.w;
	float clip = smoothstep(SL_CLIP_LO, SL_CLIP_HI, s);
	clip = mix(1.0, clip, sl_flash_hit.w * (1.0 - smoothstep(SL_CLIP_R, SL_CLIP_R + SL_CLIP_FADE, distance(wpos, sl_flash_hit.xyz))));
	return fc * (sl_gain.x * cone * clip * sl_att(d, sl_flash_a.w, SL_FLASH_DECAY) * max(dot(wnor, L), 0.0));
}

// The surface's albedo times everything the shader lights add. World position and normal come from the view-space ones.
vec3 sl_emission(vec3 wpos, vec3 wnor, vec3 alb) {
	vec3 lit = sl_beam(wpos, wnor);
	lit += sl_lamp(sl_lamp_pos0, sl_lamp_col0, wpos, wnor);
	lit += sl_lamp(sl_lamp_pos1, sl_lamp_col1, wpos, wnor);
	lit += sl_lamp(sl_lamp_pos2, sl_lamp_col2, wpos, wnor);
	lit += sl_lamp(sl_lamp_pos3, sl_lamp_col3, wpos, wnor);
	lit += sl_lamp(sl_lamp_pos4, sl_lamp_col4, wpos, wnor);
	lit += sl_lamp(sl_lamp_pos5, sl_lamp_col5, wpos, wnor);
	lit += sl_lamp(sl_lamp_pos6, sl_lamp_col6, wpos, wnor);
	lit += sl_lamp(sl_lamp_pos7, sl_lamp_col7, wpos, wnor);
	return alb * lit;
}
