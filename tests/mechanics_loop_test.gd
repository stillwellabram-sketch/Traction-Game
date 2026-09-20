extends SceneTree
const Factory = preload("res://scripts/mechanics/city_factory.gd")
const Blueprints = preload("res://scripts/mechanics/blueprints.gd")
const B = preload("res://scripts/mechanics/balance.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
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
	world.set_physics_process(false)
	world.profiles.directory = "/private/tmp/tractionism-loop-profiles"
	var attacker := Factory.starter(world, "loop_attacker", Vector3(40, 0, 0))
	var target := Factory.starter(world, "loop_defender", Vector3(40, 0, -30))
	world.cities.append(attacker)
	world.cities.append(target)
	world.register_city(attacker)
	world.register_city(target)
	world.switch_city(attacker)
	world.player.require_mouse_capture = false
	await frames(6)
	check(attacker.start_piloting(attacker.build_pieces[14]), "Built city helm engages")
	var start_position: Vector3 = attacker.position
	attacker.drive(0.5, 1, 0.4, false)
	check(attacker.position.distance_to(start_position) > 0.1, "Built city moves on engine and traction power")
	attacker.stop_piloting()
	var disabled: Array = []
	for block in target.build_pieces:
		if block.kind == B.WHEEL:
			disabled.append(block)
	var expected_count: int = target.build_pieces.size()
	# Keep this combat fixture in the level clearing; dedicated terrain tests cover the tracks.
	# Real physics rays disable three separate wheels; no direct damage shortcut.
	for wheel in disabled.slice(0, 3):
		var side := -1.0 if wheel.cell.z < 0 else 1.0
		attacker.position = wheel.global_position + Vector3(0, -0.6, 20 * side)
		attacker.rotation.y = PI if side < 0 else 0
		await frames(3)
		for shot in 4:
			attacker.systems.tick(B.SHOT_INTERVAL)
			var hit: Dictionary = world.combat.fire(attacker, wheel.to_global(Vector3(0, 0.7, 0)))
			check(hit.get("block") == wheel, "Gun targets the chosen wheel")
	check(target.systems.performance().mobility <= B.TOW_MOBILITY_THRESHOLD, "Gun damage enables towing")
	check(world.profiles.profiles.has("loop_defender"), "Pre-damage blueprint automatically protected")
	check(world.profiles.profiles.loop_defender.blueprint.pieces.size() == expected_count, "Blueprint contains original modules")
	# Put attacker at towing range and install its processor at the front edge.
	attacker.rotation = Vector3.ZERO
	attacker.position = Vector3(40, 0, -10)
	Factory.add_piece(attacker, B.GUT, Vector3(0, 0.6, -5))
	attacker.refresh_bounds()
	check(world.salvage.attach(attacker, target, target.to_global(Vector3(0, 0.6, 5))), "Disabled rival attaches")
	await frames(3)
	# A towed defender can still fire, with a live powered gun and normal cooldown.
	target.systems.cooldown = 0
	var fuel_before: float = target.systems.fuel
	world.combat.fire(target, target.position + Vector3(0, 2, -100))
	check(target.systems.fuel < fuel_before and target.systems.cooldown > 0, "Defending crew fires while towed")
	var balance_before: float = target.systems.scrap
	var target_fuel: float = target.systems.fuel
	var attacker_scrap: float = attacker.systems.scrap
	for i in 1800:
		world.salvage.tick(0.1, attacker)
	check(target.systems.defeated and target.build_pieces.is_empty(), "Contact gut fully processes city")
	check(attacker.systems.scrap > attacker_scrap, "Attacker receives salvage")
	check(target.systems.scrap == floorf(balance_before * B.LOSS_RETENTION), "Defender retains configured material fraction")
	check(is_equal_approx(target.systems.fuel, target_fuel * B.LOSS_RETENTION), "Fuel retention applies too")
	world.profiles.retain_after_loss(target)
	check(target.systems.scrap == floorf(balance_before * B.LOSS_RETENTION), "Loss penalty applies only once")
	var from_disk := Blueprints.new()
	from_disk.directory = world.profiles.directory
	check(from_disk.load_profile("loop_defender"), "Independent player blueprint reloads from disk")
	var blueprint: Dictionary = from_disk.profiles.loop_defender.blueprint
	var cost: float = from_disk.design_cost(blueprint)
	var retained: float = target.systems.scrap
	target.systems.scrap = cost - 1
	check(not world.profiles.rebuild(target) and target.build_pieces.is_empty(), "Insufficient resources leave live state unchanged")
	target.systems.scrap = retained
	check(world.profiles.rebuild(target), "Retained materials can reconstruct saved design")
	check(target.build_pieces.size() == expected_count and not target.systems.defeated, "Rebuilt blocks and modules match blueprint")
	check(is_equal_approx(target.systems.scrap, retained - cost), "Rebuild pays exact design cost")
	check(target.systems.performance().mobility == 1 and target.systems.performance().speed > 0, "Rebuilt city is powered and mobile")
	check(not world.profiles.rebuild(target), "Cannot duplicate a live city via repeated rebuild")
	for owner in ["loop_attacker", "loop_defender"]:
		DirAccess.remove_absolute(world.profiles.path_for(owner))
	print("Full mechanics loop: %d failures" % failures)
	quit(1 if failures else 0)
