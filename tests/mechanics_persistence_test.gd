extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	world.load_player_profile = false
	root.add_child(world)
	preload("res://tests/legacy_fixture.gd").add(world)
	world.set_physics_process(false)
	world.profiles.directory = "/private/tmp/tractionism-persistence-profiles"
	world.add_piece(11, Vector3(0, 0.6, 0), 0)
	var engine: int = world.pieces.back().get_meta("block_id")
	world.chunks.damage(engine, 200)
	world.chunks.enabled[engine] = false
	world.add_custom_block({"position": [1, 0.6, 1], "size": [1, 2, 0.2], "rotation": 0, "material": 1})
	world.chunks.damage(world.custom_blocks.back().get_meta("block_id"), 50)
	var saved: Dictionary = world.capture_build()
	check(world.BuildState.valid(JSON.parse_string(JSON.stringify(saved))), "Mechanics save validates after JSON round trip")
	world.restore_build(saved)
	check(world.capture_build() == saved, "Health, switches, materials, wallet and city pose round trip")
	var blueprint: Dictionary = world.profiles.design(world.city)
	check(world.profiles.valid_design(blueprint), "Blueprint serializes bus routing and chassis identity")
	check(not blueprint.pieces.back().enabled and blueprint.pieces.back().bus == "main", "Disabled route retained")
	var bad := saved.duplicate(true)
	bad.pieces.back().hp = -1
	check(not world.BuildState.valid(bad), "Reject negative health")
	bad = saved.duplicate(true)
	bad.mechanics.fuel = -2
	check(not world.BuildState.valid(bad), "Reject negative resource balances")
	var id: int = world.custom_blocks.back().get_meta("block_id")
	var weight: float = world.chunks.performance().mass
	world.custom_blocks.back().configure(Vector3(2, 0.6, 1), Vector3(2, 2, 0.2), 0, 1)
	check(world.chunks.health[id] == 170 and world.chunks.performance().mass > weight, "Custom edit preserves health and updates cargo mass")
	for i in 3:
		await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(2, 1, 4), Vector3(2, 1, 0), 4)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(world.ChunkIndex.resolve(hit) == world.custom_blocks.back(), "Moved custom block chunk collider follows edit")
	print("Mechanics persistence tests: %d failures" % failures)
	quit(1 if failures else 0)
