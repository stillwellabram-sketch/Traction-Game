extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	world.load_player_profile = false
	root.add_child(world)
	preload("res://tests/legacy_fixture.gd").add(world)
	await physics_frame
	assert(world.pieces.size() == 12, "Starter structure missing")
	assert(world.supported(2, Vector3(0, 0.6, 2), 0))
	assert(not world.supported(2, Vector3(40, 0.6, 2), 0))
	assert(world.supported(1, Vector3(0, 3.6, -4), 0))
	assert(not world.supported(1, Vector3(40, 3.6, -4), 0))
	assert(world.same_slot(1, Vector3(0, 0.6, 0), 0, world.pieces[4]))
	assert(world.same_slot(2, Vector3(0, 0.6, -6), 2, world.pieces[9]))
	world.add_piece(4, Vector3(0, 0.6, 0), 0)
	assert(world.supported(1, Vector3(0, 3.6, -4), 0))
	# Stair ramp is walkable without jumping.
	world.player.position = Vector3(0, 0.65, 2.6)
	world.player.require_mouse_capture = false
	Input.action_press("move_forward")
	for i in range(65):
		await physics_frame
	Input.action_release("move_forward")
	print("Stair position: ", world.player.position)
	assert(world.player.position.y > 2.0, "Player failed to climb stairs")
	# Save and reload preserve the building layout.
	world.save_path = "/private/tmp/tractionism-test-save.json"
	world.save_build()
	var count: int = world.pieces.size()
	world.add_piece(0, Vector3(40, 0.6, 0), 0)
	world.load_build()
	assert(world.pieces.size() == count, "Save/load round trip failed")
	# Unsupported cycles cannot survive removal of all foundations.
	for p in world.pieces.duplicate():
		if p.kind == 0:
			world.pieces.erase(p)
			p.queue_free()
	world.prune_unsupported()
	assert(world.pieces.is_empty(), "Floating structure survived support removal")
	DirAccess.remove_absolute(world.save_path)
	print("PASS: sockets, occupancy, support, stair traversal, save/load, cascading removal")
	quit()
