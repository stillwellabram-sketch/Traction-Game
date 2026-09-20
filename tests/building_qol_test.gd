extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	world.load_player_profile = false
	root.add_child(world)
	preload("res://tests/legacy_fixture.gd").add(world)
	world.player.require_mouse_capture = false
	await frames(3)
	for quarter in range(4):
		check(world.orientation_for_view(quarter * PI / 2) == quarter, "Cardinal view orientation")
	world.view_quarter = 0
	check(world.orientation_for_view(deg_to_rad(48)) == 0, "Diagonal hysteresis")
	check(world.orientation_for_view(deg_to_rad(56)) == 1, "Crossed orientation threshold")
	check(world.orientation_for_view(-PI / 2) == 3, "Negative yaw wrap")
	for kind in [5, 6, 7]:
		check(world.supported(kind, Vector3(0, 0.6, 2), 0), "New edge piece supported")
		check(not world.supported(kind, Vector3(40, 0.6, 2), 0), "Floating edge piece rejected")
		var piece = world.Piece.new()
		piece.setup(kind, Vector3(0, 0.6, 2), 0)
		check(world.same_slot(2, Vector3(0, 0.6, 2), 2, piece), "Edge pieces share occupancy")
		piece.free()
	world.add_piece(8, Vector3(0, 0.6, 0), 0)
	check(world.supported(1, Vector3(0, 3.6, 0), 0), "Pillar supports upper floor")
	world.add_piece(1, Vector3(0, 3.6, 0), 0)
	world.add_piece(5, Vector3(0, 3.6, 2), 0)
	world.add_piece(6, Vector3(-4, 0.6, 2), 0)
	world.add_piece(7, Vector3(4, 0.6, 2), 0)
	world.save_path = "/private/tmp/tractionism-qol-save.json"
	world.save_build()
	var saved_count: int = world.pieces.size()
	world.load_build()
	check(world.pieces.size() == saved_count, "All new kinds survive save/load")
	world.remember_build()
	var pillar: StaticBody3D = world.pieces[12]
	world.pieces.erase(pillar)
	pillar.queue_free()
	world.prune_unsupported()
	check(world.pieces.size() == saved_count - 3, "Pillar removal cascades floor and railing")
	world.undo_build()
	check(world.pieces.size() == saved_count, "Undo restores cascade")
	world.select_piece(-1)
	check(world.selected == world.NAMES.size() - 1, "Selection wraps backwards")
	world.select_piece(world.NAMES.size())
	check(world.selected == 0, "Selection wraps forwards")
	# Isolated raised deck for real physics edge checks.
	world.add_piece(1, Vector3(40, 6, 0), 0)
	world.player.position = Vector3(40, 6.05, 0)
	world.player.velocity = Vector3.ZERO
	await frames(15)
	Input.action_press("edge_guard")
	Input.action_press("move_forward")
	await frames(140)
	check(world.player.position.y > 5.9 and world.player.position.z > -1.9, "Shift stops forward ledge falls")
	Input.action_press("move_right")
	await frames(140)
	check(world.player.position.y > 5.9 and world.player.position.x < 41.9, "Shift protects diagonal corners")
	Input.action_release("edge_guard")
	await frames(60)
	check(world.player.position.y < 5.0, "Releasing Shift permits walking off")
	Input.action_release("move_forward")
	Input.action_release("move_right")
	# Railings physically stop the capsule without the edge guard.
	world.add_piece(5, Vector3(40, 6, -2), 0)
	world.player.position = Vector3(40, 6.05, 0)
	world.player.velocity = Vector3.ZERO
	await frames(15)
	Input.action_press("move_forward")
	await frames(80)
	Input.action_release("move_forward")
	check(world.player.position.y > 5.9 and world.player.position.z > -1.8, "Railing collision stops player")
	DirAccess.remove_absolute(world.save_path)
	print("QoL integration tests: ", failures, " failures")
	quit(1 if failures else 0)
