class_name CitySky
extends Node3D

## The open night sky: an inverted sphere that follows the camera and is drawn by one unshaded
## spatial shader (navy to purple gradient, pixel stars, quantised cloud blobs, a moon). No post effects and no real
## lights; the shader is the whole sky.

const RADIUS := 380.0
const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

uniform vec3 top_color = vec3(0.02, 0.03, 0.10);
uniform vec3 horizon_color = vec3(0.30, 0.13, 0.33);
uniform vec3 moon_dir = vec3(0.35, 0.55, -0.75);
varying vec3 dir;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() { dir = VERTEX; }

void fragment() {
	vec3 d = normalize(dir);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(up, 0.5));
	// A planar mapping (no pole pinch at the zenith): d.xz stretched toward the horizon.
	vec2 plane = d.xz / (abs(d.y) + 0.28);
	vec2 star_cell = floor(plane * 38.0);
	float star = step(0.986, hash(star_cell)) * step(0.06, d.y);
	col += vec3(star) * (0.55 + 0.45 * sin(TIME * 1.6 + hash(star_cell + 3.1) * 6.2831));
	vec2 cloud_uv = floor(plane * 7.0) / 3.0;
	float cloud = noise(cloud_uv * 1.1 + vec2(TIME * 0.012, 0.0)) * 0.6 + noise(cloud_uv * 2.7) * 0.4;
	float mask = smoothstep(0.50, 0.60, cloud) * smoothstep(0.03, 0.28, d.y);
	vec3 cloud_col = mix(vec3(0.15, 0.09, 0.24), vec3(0.50, 0.26, 0.44), clamp(1.0 - d.y * 2.2, 0.0, 1.0));
	col = mix(col, cloud_col, mask * 0.78);
	float m = dot(d, normalize(moon_dir));
	col += vec3(0.04, 0.09, 0.14) * smoothstep(0.980, 0.9975, m);
	col = mix(col, vec3(0.86, 0.95, 1.0), step(0.9975, m));
	ALBEDO = col;
}
"""

var _mesh_instance: MeshInstance3D


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	sphere.material = material
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = sphere
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.extra_cull_margin = 16384.0
	add_child(_mesh_instance)
	top_level = true


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position
