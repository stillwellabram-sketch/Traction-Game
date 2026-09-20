extends SceneTree

var failures := 0
func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	world.load_player_profile = false
	root.add_child(world)
	preload("res://tests/legacy_fixture.gd").add(world)
	world.player.require_mouse_capture = false
	# Propulsion is now required; a bare helm no longer moves a city.
	world.add_piece(11, Vector3(0, 0.6, -3), 0)
	for x in [-4.0, 4.0]:
		for z in [-3.0, 3.0]:
			world.add_piece(13, Vector3(x, 0.6, z), 0)
	world.add_piece(world.Piece.Kind.HELM, Vector3(0, 0.6, 0), 0)
	world.player.position = Vector3(0, 0.65, 1.5)
	await frames(12)
	world.player.camera.look_at(Vector3(0, 1.55, 0))
	key(KEY_E)
	await frames(3)
	check(world.city.piloting(), "E enters the aimed helm")
	var rider: Vector3 = world.city.to_local(world.player.global_position)
	var history: int = world.undo_history.size()
	Input.action_press("move_forward")
	await frames(90)
	check(world.city.position.z < -1, "W drives through the normal input loop")
	check(world.city.to_local(world.player.global_position).distance_to(rider) < 0.02, "Driver stays on the deck over many ticks")
	Input.action_press("move_left")
	await frames(30)
	check(world.city.rotation.y > 0.1, "A steers left through normal input")
	Input.action_release("move_forward")
	Input.action_release("move_left")
	Input.action_press("jump")
	await frames(60)
	Input.action_release("jump")
	check(is_zero_approx(world.city.speed), "Space brakes without making driver jump")
	check(world.undo_history.is_empty(), "Driving clears construction undo so fuel/motion cannot be rolled back")
	key(KEY_E)
	await frames(5)
	check(not world.city.piloting() and not world.player.piloting, "E releases helm")
	check(world.player_on_city(), "Player can stand on moved city after release")
	var stopped: Transform3D = world.city.transform
	Input.action_press("move_right")
	await frames(20)
	Input.action_release("move_right")
	check(world.city.transform.is_equal_approx(stopped), "Walking after release does not drive city")
	check(world.city.to_local(world.player.global_position).distance_to(rider) > 0.3, "Walking resumes on deck")
	key(KEY_Z)
	await frames(3)
	check(world.city.transform.is_equal_approx(stopped), "Construction undo does not rewind movement")
	check(world.player_on_city(), "Undo carries onboard player with restored city")
	world.player.position = world.city.to_global(Vector3(0, 0.65, 1.5))
	world.player.velocity = Vector3.ZERO
	await frames(10)
	world.player.camera.look_at(world.city.to_global(Vector3(0, 1.55, 0)))
	key(KEY_E)
	await frames(3)
	key(KEY_ESCAPE)
	await frames(3)
	check(not world.city.piloting(), "Esc safely releases helm")
	print("City input integration tests: ", failures, " failures")
	quit(1 if failures else 0)
