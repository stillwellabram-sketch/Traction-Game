extends SceneTree
const Factory = preload("res://scripts/mechanics/city_factory.gd")
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
	world.player.require_mouse_capture = false
	var actor := Factory.starter(world, "driver", Vector3(40, 0, 0))
	var obstacle := Factory.starter(world, "obstacle", Vector3(40, 0, -20))
	world.cities.append(actor)
	world.cities.append(obstacle)
	world.switch_city(actor)
	for i in 10:
		await physics_frame
	check(actor.start_piloting(actor.build_pieces[14]), "Pilot boards physics test city")
	for i in 250:
		actor.drive(1.0 / 60, 1, 0, false)
		await physics_frame
	check(actor.boundary_blocked and actor.position.z > -8.1, "Chunk geometry stops at another city instead of phasing through")
	var stopped: Vector3 = actor.position
	for i in 40:
		actor.drive(1.0 / 60, -1, 0, false)
		await physics_frame
	check(actor.position.z > stopped.z, "Can reverse away from collision")
	actor.position = Vector3(155, 0, 50)
	actor.position.y = actor.terrain_height(actor.transform)
	world.player.position = actor.to_global(Vector3(0, 0.7, 4.5))
	var before: Vector3 = actor.position
	for i in 40:
		actor.drive(1.0 / 60, 1, 0, false)
		await physics_frame
	check(actor.position.distance_to(before) > 0.01 and not actor.boundary_blocked, "Ordinary hills permit movement")
	print("Mechanics obstacle tests: %d failures" % failures)
	quit(1 if failures else 0)
