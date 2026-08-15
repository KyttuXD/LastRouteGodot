class_name StaticOverlay
extends ColorRect

## Full-screen TV static, for a hunter gimmick to throw over the player's
## view for a beat -- a jump-scare tell, a "your signal just got worse" cue,
## whatever a future hunter wants a screen distortion for. Generic on
## purpose: nothing here knows which hunter asked for it, the same way
## PlayerController3D.interaction_veto doesn't know which hunter set it.
##
## Procedural, not a noise texture asset: a small fragment shader hashes
## screen position and TIME into pseudo-random per-pixel brightness, so a
## frame of static costs one draw and no imported art.

const SHADER_CODE := """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;

// A cheap hash, not a real noise function -- static does not need
// coherence between pixels, only that no two look alike frame to frame.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy * 0.5);
	float n = hash(cell + vec2(TIME * 113.0, TIME * 71.0));
	COLOR = vec4(vec3(n), intensity);
}
"""

var _remaining := 0.0
var _duration := 0.0
var _peak_intensity := 0.75
var _material: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0)
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	material = _material
	visible = false


## `intensity`: peak opacity, 0..1. Fades in over the first fifth of
## `duration` and out over the last fifth, rather than snapping, so it reads
## as an effect rather than a frame of flashing white noise.
func trigger(duration: float, intensity: float = 0.75) -> void:
	_duration = maxf(0.05, duration)
	_remaining = _duration
	_peak_intensity = intensity
	visible = true


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining = maxf(0.0, _remaining - delta)
	var t := 1.0 - _remaining / _duration
	var ramp := 0.2
	var envelope := 1.0
	if t < ramp:
		envelope = t / ramp
	elif t > 1.0 - ramp:
		envelope = (1.0 - t) / ramp
	# The shader owns the pixel colour outright (COLOR is set, not blended),
	# so the fade has to reach it through the uniform -- the node's own
	# `color` property is never read once a fragment() writes COLOR itself.
	_material.set_shader_parameter("intensity", _peak_intensity * envelope)
	if _remaining <= 0.0:
		visible = false
