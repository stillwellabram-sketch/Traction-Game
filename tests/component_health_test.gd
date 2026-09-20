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
	world.profiles.directory = "/private/tmp/tractionism-health-profiles"
	world.add_piece(11, Vector3(0, 0.6, 0), 0)
	var engine: int = world.pieces.back().get_meta("block_id")
	var wheels: Array[int] = []
	for x in [-3.0, 3.0]:
		for z in [-3.0, 3.0]:
			world.add_piece(13, Vector3(x, 0.6, z), 0)
			wheels.append(world.pieces.back().get_meta("block_id"))
	var original: Dictionary = world.chunks.performance()
	var previous: float = original.speed
	for i in 3:
		world.chunks.damage(wheels[i], 10000)
		var stats: Dictionary = world.chunks.performance()
		check(stats.speed > 0 and stats.speed < previous, "Every lost wheel progressively reduces speed")
		check(stats.turn_rate < original.turn_rate, "Wheel loss degrades steering")
		previous = stats.speed
	check(world.chunks.health[engine] == 650 and world.chunks.health[wheels[3]] == 280, "Other components retain independent health")
	check(world.chunks.repair(wheels[0]), "Scrap repairs disabled component")
	check(world.chunks.performance().speed > previous, "Repair restores performance")
	world.chunks.damage(engine, 10000)
	check(world.chunks.performance().supply == 0, "Destroyed engine supplies no power")
	check(world.chunks.damage(engine, -5) == 0, "Invalid negative damage cannot heal")
	print("Component health tests: %d failures" % failures)
	quit(1 if failures else 0)
