extends RefCounted

const NAMES := ["Steel", "Wood", "Concrete", "Brick"]
const ASSETS := ["Metal032", "Wood050", "Concrete034", "Bricks059"]
static var cache: Dictionary = {}

static func get_material(index: int) -> StandardMaterial3D:
	index = clampi(index, 0, NAMES.size() - 1)
	if cache.has(index):
		return cache[index]
	var material := StandardMaterial3D.new()
	var path := "res://assets/materials/%s/" % ASSETS[index]
	material.albedo_texture = load(path + "Color.jpg")
	material.normal_enabled = true
	material.normal_texture = load(path + "NormalGL.jpg")
	# Individually tuned physical finishes; material IDs stay save-compatible.
	material.normal_scale = [0.45, 0.85, 0.55, 0.9][index]
	material.albedo_color = [Color("a4adb5"), Color("d6ae81"), Color("c4c8c9"), Color("d3a48f")][index]
	material.roughness = [0.72, 0.95, 1.0, 1.0][index]
	material.roughness_texture = load(path + "Roughness.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if index == 0:
		material.metallic = 0.9
		material.metallic_texture = load(path + "Metalness.jpg")
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	# Mesh dimensions provide metre-based tiling; local mapping travels with the city.
	material.uv1_triplanar = true
	material.uv1_world_triplanar = false
	material.uv1_scale = Vector3.ONE * [0.5, 0.65, 0.4, 1.0][index]
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	cache[index] = material
	return material
