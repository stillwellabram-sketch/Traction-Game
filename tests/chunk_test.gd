extends SceneTree
const Chunk = preload("res://scripts/mechanics/city_chunk.gd")
const Piece = preload("res://scripts/piece.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var city := Node3D.new()
	root.add_child(city)
	var chunk := Chunk.new()
	city.add_child(chunk)
	var wall := Piece.new()
	wall.setup(3, Vector3(0, 0.6, 0), 0)
	city.add_child(wall)
	chunk.add_block(1, wall)
	var floor_piece := Piece.new()
	floor_piece.setup(0, Vector3(0, 0.6, 0), 0)
	city.add_child(floor_piece)
	chunk.add_block(2, floor_piece)
	check(chunk.members.size() == 2 and wall.collision_layer == 0, "One compound physics unit owns two blocks")
	check(Chunk.key_for(Vector3(-0.01, 0, 8)) == Vector3i(-1, 0, 1), "Negative coordinates chunk consistently")
	for i in 3:
		await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(1.5, 2, 3), Vector3(1.5, 2, -3), 1)
	var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and chunk.resolve_shape(hit.shape) == wall, "Ray shape resolves the specific wall block")
	chunk.remove_block(1)
	for i in 3:
		await physics_frame
	check(root.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Removal updates just the chunk collision")
	check(chunk.members.size() == 1, "Unrelated chunk member retained")
	print("Chunk integration tests: %d failures" % failures)
	quit(1 if failures else 0)
