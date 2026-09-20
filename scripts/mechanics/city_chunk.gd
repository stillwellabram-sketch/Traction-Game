extends AnimatableBody3D

# Compound collision unit. Visual/build records keep their city-local transforms;
# the chunk body itself stays at identity under the city root.
const SIZE := 8.0
var key := Vector3i.ZERO
var members: Dictionary = {}
var owners: Dictionary = {}

static func key_for(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / SIZE), floori(point.y / SIZE), floori(point.z / SIZE))

func _init() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0

func add_block(id: int, block: StaticBody3D) -> void:
	remove_block(id)
	members[id] = block
	var shape_owners: Array[int] = []
	for child in block.get_children():
		if child is CollisionShape3D and child.shape != null and not child.disabled:
			var owner_id := create_shape_owner(block)
			shape_owner_set_transform(owner_id, block.transform * child.transform)
			shape_owner_add_shape(owner_id, child.shape)
			shape_owners.append(owner_id)
	owners[id] = shape_owners
	block.collision_layer = 0

func remove_block(id: int) -> void:
	for owner_id in owners.get(id, []):
		remove_shape_owner(owner_id)
	owners.erase(id)
	members.erase(id)

func resolve_shape(shape_index: int) -> StaticBody3D:
	if shape_index < 0:
		return null
	return shape_owner_get_owner(shape_find_owner(shape_index)) as StaticBody3D

func block_bounds(id: int) -> AABB:
	var bounds := AABB()
	var first := true
	var block: StaticBody3D = members[id]
	for child in block.get_children():
		if child is MeshInstance3D:
			var box: AABB = block.transform * child.transform * child.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	return bounds
