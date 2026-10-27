class_name MaterialLook
extends RefCounted

## The one place that decides how glossy the world is. Everything the games build (the Last Route chunk surfaces, the City
## tile shader, shared prop materials, decor, every light) takes its roughness / metallic / specular from here, so the
## look is tuned in one file and checked by the `material_look` validator (docs/MATERIAL_LOOK.md).
##
## Default look: MATTE. Godot's StandardMaterial3D specular is 0.5 and lights add 0.5 specular by default, which on dark
## cobbles and tile under a flashlight gives bright glints and blue speckle. We keep surfaces rough, non-metallic and with a
## low specular, and lights with a low specular energy. Gloss is allowed only where it is meant (see ALLOWED_GLOSS).

## Roughness of ordinary surfaces (walls, floors, ground, props).
const ROUGHNESS_MATTE := 0.92
## Floors that read as polished (stone, parquet, check, metal grate): still soft, never a mirror.
const ROUGHNESS_SOFT_FLOOR := 0.82
const ROUGHNESS_METAL := 0.62
## City paving/roads: slightly damp, still diffuse.
const ROUGHNESS_CITY_GROUND := 0.86
const ROUGHNESS_CITY_SOLID := 0.95
## Specular reflectance (StandardMaterial3D.metallic_specular / shader SPECULAR) for dielectrics and for metal.
const SPECULAR_DEFAULT := 0.18
const SPECULAR_METAL := 0.32
## Metallic is 0 for everything except named metal kinds.
const METALLIC_DEFAULT := 0.0
const METALLIC_METAL := 0.18
## Light specular (OmniLight3D / SpotLight3D.light_specular). Godot's default is 0.5.
const LIGHT_SPECULAR := 0.22

## What the validator enforces over generated content (a margin above the values we apply).
const MIN_ROUGHNESS := 0.55
const MAX_METALLIC := 0.4
const MAX_SPECULAR := 0.35
const MAX_LIGHT_SPECULAR := 0.3

## Materials (by resource name) or mesh names that may be glossier. Glass and emissive materials are allowed by default
## (they glow rather than glint); add a name here to keep an intentional shine.
const ALLOWED_GLOSS: Array[String] = ["glass", "water", "wet", "mirror", "vault_glass"]


## Pulls a StandardMaterial3D into the matte look. `metal` keeps a soft metallic look (kind: metal props); `floor_soft` is for
## polished-looking floors. Emissive materials keep their own roughness (bulbs, windows) but not extra specular.
static func tame(material: BaseMaterial3D, metal: bool = false, floor_soft: bool = false) -> void:
	if material == null:
		return
	if material.emission_enabled and material.emission_energy_multiplier > 0.5:
		material.metallic_specular = minf(material.metallic_specular, SPECULAR_DEFAULT)
		return
	if metal:
		material.roughness = maxf(material.roughness, ROUGHNESS_METAL)
		material.metallic = minf(material.metallic, METALLIC_METAL)
		material.metallic_specular = minf(material.metallic_specular, SPECULAR_METAL)
	elif floor_soft:
		material.roughness = maxf(material.roughness, ROUGHNESS_SOFT_FLOOR)
		material.metallic = METALLIC_DEFAULT
		material.metallic_specular = minf(material.metallic_specular, SPECULAR_DEFAULT)
	else:
		material.roughness = maxf(material.roughness, ROUGHNESS_MATTE * .9)
		material.metallic = minf(material.metallic, METALLIC_DEFAULT + .05)
		material.metallic_specular = minf(material.metallic_specular, SPECULAR_DEFAULT)


## Painted floor kinds -> Vector3(roughness, metallic, specular). Used by the StandardMaterial3D floors and the vertex-colour
## response of the chunk texture arrays so both paths agree.
static func floor_response(kind: String) -> Vector3:
	if kind.begins_with("metal") or kind == "hazard" or kind == "grate" or kind.begins_with("safe"):
		return Vector3(ROUGHNESS_METAL, METALLIC_METAL, SPECULAR_METAL)
	if kind.begins_with("stone") or kind.begins_with("parquet") or kind.begins_with("check"):
		return Vector3(ROUGHNESS_SOFT_FLOOR, METALLIC_DEFAULT, SPECULAR_DEFAULT)
	return Vector3(ROUGHNESS_MATTE, METALLIC_DEFAULT, SPECULAR_DEFAULT)


static func tame_light(light: Light3D) -> void:
	if light != null and light.light_specular > LIGHT_SPECULAR:
		light.light_specular = LIGHT_SPECULAR


## Every light that enters the tree (flashlights in scenes, lamps, room lights, peers' flashlights) gets the low specular.
static func install(tree: SceneTree) -> void:
	var callback := Callable(MaterialLook, "_on_node_added")
	if not tree.node_added.is_connected(callback):
		tree.node_added.connect(callback)
	_tame_lights_under(tree.root)


static func _on_node_added(node: Node) -> void:
	if node is Light3D:
		tame_light(node as Light3D)


static func _tame_lights_under(node: Node) -> void:
	if node is Light3D:
		tame_light(node as Light3D)
	for child in node.get_children():
		_tame_lights_under(child)
