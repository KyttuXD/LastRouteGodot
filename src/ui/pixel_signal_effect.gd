class_name PixelSignalEffect
extends CanvasLayer

## Persistent route-only pixel post-process. It samples the completed 3D frame
## at a strength-scaled low resolution, softly gathers neighbouring blocks,
## then blends colour quantization back over the original. Detailed authored
## models receive the full treatment; broad structural walls receive one
## quarter of that blend (75% less) so they remain stable but visually related.
## It intentionally has
## no grain, scanlines or animated noise: the pixel blur is the whole effect.
## The HUD is a higher CanvasLayer, so text and controls remain crisp.

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	float block_size = mix(2.0, 4.0, strength);
	vec2 block = floor(pixel / block_size) * block_size + vec2(block_size * 0.5);
	vec2 sample_uv = clamp(block * SCREEN_PIXEL_SIZE,
		SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);
	vec3 original = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec2 blur_step = SCREEN_PIXEL_SIZE * block_size * mix(0.65, 1.35, strength);
	vec3 center = textureLod(screen_texture, sample_uv, 0.0).rgb;
	vec3 right = textureLod(screen_texture, sample_uv + vec2(blur_step.x, 0.0), 0.0).rgb;
	vec3 left = textureLod(screen_texture, sample_uv - vec2(blur_step.x, 0.0), 0.0).rgb;
	vec3 down = textureLod(screen_texture, sample_uv + vec2(0.0, blur_step.y), 0.0).rgb;
	vec3 up = textureLod(screen_texture, sample_uv - vec2(0.0, blur_step.y), 0.0).rgb;
	vec3 sampled = center * 0.44 + (right + left + down + up) * 0.14;

	float levels = mix(48.0, 22.0, strength);
	vec3 treated = floor(sampled * levels + 0.5) / levels;
	treated = clamp(treated, vec3(0.0), vec3(1.0));
	// Imported pixel props carry frequent neighbouring colour changes; broad
	// structural planes do not. Concentrate the blur/quantization where that
	// local detail exists, and suppress it on bright light sources.
	float detail = (length(center - right) + length(center - left)
		+ length(center - up) + length(center - down)) * 0.25;
	float prop_priority = smoothstep(0.025, 0.19, detail);
	float luminance = dot(center, vec3(0.2126, 0.7152, 0.0722));
	float light_suppression = 1.0 - smoothstep(0.76, 0.98, luminance);
	float full_blend = mix(strength, min(1.0, strength * 1.18), strength);
	float blend = mix(strength * 0.25, full_blend, prop_priority) * light_suppression;
	COLOR = vec4(mix(original, treated, blend), 1.0);
}
"""

var _surface: ColorRect
var _material: ShaderMaterial
var _admin_enabled := true


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
	_surface.visible = _admin_enabled and strength > 0.001


func strength() -> float:
	return float(_material.get_shader_parameter("strength")) if _material else 0.0


func set_admin_enabled(enabled: bool) -> void:
	_admin_enabled = enabled
	_refresh()


func admin_enabled() -> bool:
	return _admin_enabled
