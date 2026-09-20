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
	var shooter := Factory.starter(world, "shooter", Vector3(40, 0, 0))
	var target_city := Factory.starter(world, "target", Vector3(40, 0, -22))
	for i in 4:
		await physics_frame
	var wheel: StaticBody3D = target_city.build_pieces[12]
	var id: int = wheel.get_meta("block_id")
	var before: float = target_city.systems.health[id]
	var hit: Dictionary = world.combat.fire(shooter, wheel.to_global(Vector3(0, 0.7, 0)))
	check(hit.get("block") == wheel, "Gun ray resolves wheel on another chunked city")
	check(target_city.systems.health[id] == before - 90, "Damage routes to component hit")
	check(target_city.systems.health[target_city.build_pieces[9].get_meta("block_id")] == 650, "Engine health unaffected by wheel hit")
	check(world.combat.fire(shooter, wheel.global_position).is_empty(), "Gun cooldown enforced")
	shooter.systems.cooldown = 0
	shooter.systems.fuel = 0
	check(world.combat.fire(shooter, wheel.global_position).is_empty(), "Power/fuel failure locks gun")
	print("Combat integration tests: %d failures" % failures)
	quit(1 if failures else 0)
