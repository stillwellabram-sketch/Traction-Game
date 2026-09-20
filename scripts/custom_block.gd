extends AnimatableBody3D

const Materials = preload("res://scripts/material_library.gd")
var kind := -1
var dimensions := Vector3(4, 3, 0.25)
var material_id := 0
var quarter := 0
var visual: MeshInstance3D
var collider: CollisionShape3D
var preview_material: StandardMaterial3D

func _init() -> void:
	sync_to_physics = false
	# Layer 4 is walkable decoration, never part of the structural graph.
	collision_layer = 4
	collision_mask = 0
	visual = MeshInstance3D.new()
	visual.mesh = BoxMesh.new()
	add_child(visual)
	collider = CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	add_child(collider)

func configure(location: Vector3, size: Vector3, turns: int, finish: int, ghost := false) -> void:
	position = location
	dimensions = size
	quarter = posmod(turns, 4)
	rotation.y = quarter * PI / 2
	material_id = finish
	visual.mesh.size = dimensions
	visual.position.y = dimensions.y / 2
	collider.shape.size = dimensions
	collider.position = visual.position
	collision_layer = 0 if ghost else 4
	if ghost:
		preview_material = Materials.get_material(material_id).duplicate()
		preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		visual.material_override = preview_material
	else:
		visual.material_override = Materials.get_material(material_id)
	if not ghost and has_meta("city_systems"):
		get_meta("city_systems").update_decoration(self)

func tint(valid: bool) -> void:
	preview_material.albedo_color = Color(1, 1, 1, 0.9) if valid else Color(1, 0.25, 0.2, 0.6)

func to_record() -> Dictionary:
	return {"position": [position.x, position.y, position.z], "size": [dimensions.x, dimensions.y, dimensions.z], "rotation": quarter, "material": material_id}
