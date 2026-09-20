extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	world.load_player_profile = false
	root.add_child(world)
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	world.player.require_mouse_capture = false
	world.add_piece(13, Vector3.ZERO, 0)
	world.add_piece(0, Vector3(0, 3, 0), 0, 2, 16, 16)
	world.player.position = Vector3(0, 3.1, 5)
	for i in 3: await physics_frame
	for kind in [2, 3, 5, 6, 7]:
		world.select_piece(kind)
		world.candidate = Vector3(0, 3, 0)
		world.candidate_turns = 0
		world.valid = true
		world.player.camera.look_at(Vector3(0, 4, 0))
		check(world.begin_structural_drag(), "All wall types start a drag")
		world.player.camera.look_at(Vector3(4, 4, 0))
		world.update_candidate()
		check(world.valid and is_equal_approx(world.selected_span, 6), "Wall drag grows length along its own axis")
		check(world.candidate.is_equal_approx(Vector3(2, 3, 0)), "Wall keeps its baseline and plane")
		world.cancel_structural_drag()
		check(world.selected_span == 2, "Cancellation restores starting size")
	world.player.position = Vector3(5, 3.1, 0)
	world.select_piece(2)
	world.candidate = Vector3(0, 3, 0)
	world.candidate_turns = 1
	world.valid = true
	world.player.camera.look_at(Vector3(0, 4, 0))
	check(world.begin_structural_drag(), "Rotated wall drag starts")
	world.player.camera.look_at(Vector3(0, 4, -4))
	world.update_candidate()
	check(world.valid and world.candidate.is_equal_approx(Vector3(0, 3, -2)), "Rotated wall follows local length axis")
	world.place_requested = true
	world._physics_process(0.016)
	check(world.pieces.back().kind == 2 and world.pieces.back().span == 6, "Release commits stretched wall")
	var saved: Dictionary = world.capture_build()
	check(world.BuildState.valid(saved), "Stretched wall save validates")
	world.restore_build(saved)
	check(world.pieces.back().span == 6, "Save retains stretched wall length")
	var floor_piece = world.Piece.new()
	floor_piece.setup(1, Vector3.ZERO, 0, false, 0, 6, 3)
	check(floor_piece.depth == 3 and floor_piece.get_child(0).mesh.size == Vector3(6, 0.2, 3), "Floors retain independent rectangular axes")
	floor_piece.free()
	print("Structural drag tests: %d failures" % failures)
	quit(1 if failures else 0)
