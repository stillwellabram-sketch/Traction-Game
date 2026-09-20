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
	world.profiles.directory = "/private/tmp/tractionism-salvage-profiles"
	var attacker := Factory.starter(world, "attacker", Vector3(45, 0, 0))
	Factory.add_piece(attacker, 17, Vector3(0, 0.6, -5))
	attacker.refresh_bounds()
	var target := Factory.starter(world, "defender", Vector3(45, 0, -20))
	check(not world.salvage.attach(attacker, target, target.to_global(Vector3(0, 0.6, 5))), "Healthy mobile city cannot be towed")
	for piece in target.build_pieces:
		if piece.kind == 13:
			target.systems.damage(piece.get_meta("block_id"), 10000)
	check(world.salvage.attach(attacker, target, target.to_global(Vector3(0, 0.6, 5))), "Disabled city can be attached")
	check(target.systems.find_module(16) != null and target.systems.performance().ratio >= 0.65, "Towed crew retains powered weapons")
	check(not world.salvage.attach(target, attacker, attacker.position), "Tow cycles rejected")
	var before: float = attacker.systems.scrap
	var start: Vector3 = target.position
	for i in 250:
		world.salvage.tick(0.1, attacker)
	check(target.position.distance_to(start) > 1, "Reeling physically moves target")
	check(attacker.systems.scrap > before, "Contact processor yields scrap over time")
	for i in 1500:
		world.salvage.tick(0.1, attacker)
	if not target.build_pieces.is_empty():
		print("Remaining: ", target.build_pieces.map(func(p): return p.kind), " position ", target.position, " links ", world.salvage.links)
	check(target.build_pieces.is_empty() and not is_instance_valid(attacker.tow_target), "Gut completes capture and releases tow")
	var final_scrap: float = attacker.systems.scrap
	world.salvage.tick(10, attacker)
	check(attacker.systems.scrap == final_scrap, "Finished target cannot award duplicate salvage")
	print("Tow and gut tests: %d failures" % failures)
	quit(1 if failures else 0)
