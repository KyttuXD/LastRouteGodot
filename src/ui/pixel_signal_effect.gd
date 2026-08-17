class_name PixelSignalEffect
extends CanvasLayer

## Restrained route-only post-process. It samples the completed 3D frame at a
## two-pixel cadence, then blends quantization, ordered dither, faint scanlines
## and animated signal grain back over the original. The HUD is a higher
## CanvasLayer, so text and controls remain crisp.

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.28;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bayer4(vec2 pixel) {
	vec2 p = mod(floor(pixel), 4.0);
	float x = p.x;
	float y = p.y;
	float value = 0.0;
	if (y < 1.0) value = (x < 1.0) ? 0.0 : ((x < 2.0) ? 8.0 : ((x < 3.0) ? 2.0 : 10.0));
	else if (y < 2.0) value = (x < 1.0) ? 12.0 : ((x < 2.0) ? 4.0 : ((x < 3.0) ? 14.0 : 6.0));
	else if (y < 3.0) value = (x < 1.0) ? 3.0 : ((x < 2.0) ? 11.0 : ((x < 3.0) ? 1.0 : 9.0));
	else value = (x < 1.0) ? 15.0 : ((x < 2.0) ? 7.0 : ((x < 3.0) ? 13.0 : 5.0));
	return (value + 0.5) / 16.0 - 0.5;
}

void fragment() {
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 block = floor(pixel * 0.5) * 2.0 + vec2(1.0);
	vec2 sample_uv = clamp(block * SCREEN_PIXEL_SIZE,
		SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);
	vec3 original = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 sampled = textureLod(screen_texture, sample_uv, 0.0).rgb;

	float levels = mix(52.0, 28.0, strength);
	float dither = bayer4(pixel) * mix(0.35, 0.85, strength);
	vec3 treated = floor(sampled * levels + dither) / levels;
	float grain = hash(floor(pixel * 0.5) + floor(TIME * vec2(19.0, 13.0))) - 0.5;
	float scanline = mod(floor(pixel.y), 2.0) - 0.5;
	treated += grain * 0.035 * strength + scanline * 0.018 * strength;
	treated = clamp(treated, vec3(0.0), vec3(1.0));
	COLOR = vec4(mix(original, treated, strength), 1.0);
}
"""

var _surface: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	layer = 0
	_surface = ColorRect.new()
	_surface.name = "PixelSignalSurface"
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_surface.material = _material
	add_child(_surface)
	Settings.visual_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var strength := clampf(Settings.pixel_effect_percent / 100.0, 0.0, 1.0)
	_material.set_shader_parameter("strength", strength)
	_surface.visible = strength > 0.001


func strength() -> float:
	return float(_material.get_shader_parameter("strength")) if _material else 0.0
