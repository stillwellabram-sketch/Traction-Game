extends RefCounted
static var cache: Dictionary = {}

static func finish(role: String, body: Material, material_id: int) -> Material:
	# User-painted wood/brick/concrete applies to housing panels, leaving working
	# hardware metallic. Ghosts bypass these finishes entirely.
	if role == "body" and material_id != 0:
		return body
	if cache.has(role):
		return cache[role]
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/mechanics/mechanical_metal.gdshader")
	material.set_shader_parameter("grain_map", preload("res://assets/materials/Metal032/Color.jpg"))
	material.set_shader_parameter("normal_map", preload("res://assets/materials/Metal032/NormalGL.jpg"))
	var colors := {"body": Color("65716d"), "frame": Color("454d50"), "steel": Color("a3adaa"), "rust": Color("785942"), "brass": Color("b89960")}
	material.set_shader_parameter("coat", colors.get(role, Color("65716d")))
	material.set_shader_parameter("corrosion", {"body": 0.18, "frame": 0.12, "steel": 0.04, "rust": 0.38, "brass": 0.08}.get(role, 0.4))
	material.set_shader_parameter("metalness", 0.7 if role in ["steel", "brass"] else 0.45)
	cache[role] = material
	return material
