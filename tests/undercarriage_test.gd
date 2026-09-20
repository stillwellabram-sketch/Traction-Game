extends SceneTree
const B = preload("res://scripts/mechanics/balance.gd")
const R = preload("res://scripts/build_rules.gd")
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
	world.player.require_mouse_capture = false
	world.player.set_physics_process(false)
	world.player.position = Vector3(0, 0.1, 5)
	for i in 4: await physics_frame
	check(world.pieces.is_empty(), "Fresh spawn has no starting base")
	check(world.BuildState.valid(world.capture_build()), "Empty construction can be saved")
	world.player.camera.look_at(Vector3.ZERO)
	world.select_piece(0)
	world.update_candidate()
	check(not world.valid, "Bare ground rejects foundations")
	world.select_piece(13)
	world.update_candidate()
	check(world.valid and absf(world.candidate.y) < 0.01, "Running gear previews on terrain")
	world.add_piece(13, Vector3.ZERO, 0)
	check(world.BuildState.valid(world.capture_build()), "Running gear before chassis can be saved")
	for i in 3: await physics_frame
	world.player.camera.look_at(Vector3(0, 2.3, 0))
	world.select_piece(0)
	world.update_candidate()
	check(world.valid and is_equal_approx(world.candidate.y, 3.0), "Foundation snaps above wheel top mount")
	world.add_piece(0, Vector3(0, 3, 0), 0, 0, 2)
	check(world.pieces[0].get_meta("supported", false), "Adding chassis connects its starting wheel")
	check(R.supported(0, Vector3(2, 3, 0), 0, 2, world.pieces), "Deck can extend from raised foundation")
	for i in 3: await physics_frame
	check(world.board_foundation(world.pieces[1]) and world.player.position.y > 3, "Player can board raised deck")
	for kind in [13, 14, 15, 18, 19, 20, 21]:
		var piece = world.Piece.new()
		piece.setup(kind, Vector3.ZERO, 0)
		var pool: Array[StaticBody3D] = [piece]
		var deck := Vector3(0, B.mount_height(kind) + 0.6, 0)
		check(R.supported(0, deck, 0, 2, pool), "Every running gear size supports a top foundation")
		check(not R.occupied(0, deck, 0, 2, piece), "Top foundation clears running gear")
		check(R.occupied(0, deck - Vector3.UP * 0.3, 0, 2, piece), "Sinking foundation into running gear rejected")
		piece.free()
	var saved: Dictionary = world.capture_build()
	check(saved.version == 6 and world.BuildState.valid(saved), "Current layout round trips through validation")
	world.restore_build(saved)
	check(is_equal_approx(world.pieces[1].cell.y, 3), "New layouts are not lifted twice")
	var old := {"version":5, "pieces":[{"kind":13,"y":0.6},{"kind":0,"y":0.6}], "custom":[]}
	var migrated: Dictionary = preload("res://scripts/mechanics/traction_layout.gd").migrate(old)
	check(is_equal_approx(migrated.pieces[0].y, 0) and is_equal_approx(migrated.pieces[1].y, 3), "Legacy layout lifts deck and grounds wheel")
	print("Undercarriage tests: %d failures" % failures)
	quit(1 if failures else 0)
