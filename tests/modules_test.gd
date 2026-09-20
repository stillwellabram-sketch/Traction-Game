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
	preload("res://tests/legacy_fixture.gd").add(world)
	world.set_physics_process(false)
	world.player.require_mouse_capture = false
	world.add_piece(11, Vector3(0, 0.6, 0), 0)
	for x in [-3.0, 3.0]:
		for z in [-3.0, 3.0]:
			world.add_piece(13, Vector3(x, 0.6, z), 0)
	world.add_piece(9, Vector3(0, 0.6, 3), 0)
	world.player.position = Vector3(0, 0.7, 4.5)
	for i in 8:
		await physics_frame
	check(world.same_slot(13, Vector3.ZERO, 0, world.pieces[4]), "Running gear cannot intersect a low foundation")
	var stats: Dictionary = world.chunks.performance()
	check(stats.supply == 900 and stats.demand == 480 and stats.speed > 0, "Installed engine and four wheels join structural power bus")
	check(world.city.start_piloting(world.pieces.back()), "Helm is usable with chunk collision")
	world.city.drive(0.5, 1, 1, false)
	check(world.city.position.length() > 0.1 and world.city.rotation.y != 0, "Power-derived movement and steering work")
	var fuel: float = world.chunks.fuel
	world.chunks.tick(1)
	check(world.chunks.fuel < fuel, "Engines consume fuel")
	world.chunks.fuel = 0
	check(world.chunks.performance().speed == 0, "Fuel exhaustion removes propulsion")
	print("Module integration tests: %d failures" % failures)
	quit(1 if failures else 0)
