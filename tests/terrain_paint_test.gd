extends SceneTree
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
	world.player.require_mouse_capture = false
	for i in 5:
		await physics_frame
	# Both perimeter overlap and aiming high on the wall must work.
	check(world.supported(8, Vector3(-4, 0.6, -6), 0), "Pillar can straddle wall/deck boundary")
	check(world.supported(9, Vector3(-4, 0.6, -6), 0), "Helm can straddle wall/deck boundary")
	check(not world.supported(8, Vector3(-4, 0.6, -6.3), 0), "Centre off the deck remains unsupported")
	world.player.position = Vector3(-4, 0.65, -3)
	world.player.camera.look_at(Vector3(-4, 2.4, -6))
	world.select_piece(8)
	world.update_candidate()
	check(is_equal_approx(world.candidate.y, 0.6) and world.valid, "High wall aim places pillar at deck level")
	world.select_piece(9)
	world.update_candidate()
	check(is_equal_approx(world.candidate.y, 0.6) and world.valid, "High wall aim places helm at deck level")
	var history: int = world.undo_history.size()
	var first_material: int = world.pieces[0].material_id
	world.selected_material = 1
	world.apply_brush(world.pieces[0])
	world.apply_brush(world.pieces[1])
	world.apply_brush(world.pieces[1])
	check(world.undo_history.size() == history + 1, "One undo record per stroke")
	check(world.pieces[0].material_id == 1 and world.pieces[1].material_id == 1, "Brush paints multiple pieces")
	world.undo_build()
	check(world.pieces[0].material_id == first_material and world.pieces[1].material_id == first_material, "Undo restores entire stroke")
	world.painting = true
	world.material_palette.open_palette()
	world.material_palette.choose(3)
	check(world.selected_material == 3 and world.pieces[0].material_id == first_material, "Brush palette selects without painting")
	var terrain = world.get_node("Landscape")
	check(terrain.height_at(40, 40) == 0, "Starting clearing stays level")
	check(terrain.height_at(230, 170) > 5, "Surrounding terrain has elevation")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(230, 100, 170), Vector3(230, -10, 170), 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.position.y > 5, "Hills have matching walkable collision")
	print("Terrain and painting integration tests: %d failures" % failures)
	quit(1 if failures else 0)
