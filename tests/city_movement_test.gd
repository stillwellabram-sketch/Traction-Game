extends SceneTree

var failures := 0
func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
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
	world.set_physics_process(false)
	check(world.supported(world.Piece.Kind.HELM, Vector3(0, 0.6, 0), 0), "Helm supported on deck")
	check(not world.supported(world.Piece.Kind.HELM, Vector3(40, 0.6, 0), 0), "Helm cannot float")
	# Propulsion is now required; a bare helm no longer moves a city.
	world.add_piece(11, Vector3(0, 0.6, -3), 0)
	for x in [-4.0, 4.0]:
		for z in [-3.0, 3.0]:
			world.add_piece(13, Vector3(x, 0.6, z), 0)
	world.add_piece(world.Piece.Kind.HELM, Vector3(0, 0.6, 0), 0)
	var helm: StaticBody3D = world.pieces.back()
	world.add_custom_block({"position": [3, 0.6, 2], "size": [1, 2, 0.3], "rotation": 1, "material": 3})
	var local_custom: Transform3D = world.custom_blocks[0].transform
	var initial: Dictionary = world.capture_build()
	for quarter in 4:
		world.city.stop_piloting()
		world.city.transform = Transform3D.IDENTITY
		helm.quarter = quarter
		helm.rotation.y = quarter * PI / 2
		world.player.position = Vector3(0, 0.65, 1.5)
		world.player.velocity = Vector3.ZERO
		await frames(10)
		check(world.city.start_piloting(helm), "Nearby grounded player takes helm")
		var rider: Transform3D = world.city.global_transform.affine_inverse() * world.player.global_transform
		var forward: Vector3 = helm.global_basis * Vector3.FORWARD
		world.city.drive(0.5, 1, 0, false)
		check(world.city.position.dot(forward) > 0.1, "W follows helm heading for quarter %d" % quarter)
		check(is_zero_approx(world.city.position.y), "City stays on ground")
		check(world.custom_blocks[0].transform.is_equal_approx(local_custom), "Custom block retains local attachment")
		check((world.city.global_transform.affine_inverse() * world.player.global_transform).is_equal_approx(rider), "Pilot carried without sliding")
		var old_basis: Basis = world.city.basis
		world.city.drive(0.5, 1, 1, false)
		check(not world.city.basis.is_equal_approx(old_basis), "A steers left")
		check((world.city.global_transform.affine_inverse() * world.player.global_transform).is_equal_approx(rider), "Pilot rotates with deck")
		world.city.drive(0.5, 0, 0, true)
		check(is_zero_approx(world.city.speed), "Space brakes to a stop")
		var before: Vector3 = helm.global_position
		forward = helm.global_basis * Vector3.FORWARD
		world.city.drive(0.5, -1, 0, false)
		check((helm.global_position - before).dot(forward) < -0.1, "S reverses along helm heading")
		world.city.stop_piloting()
		check(not world.player.piloting and is_zero_approx(world.city.speed), "Exiting stops city and restores walking")
	# Arbitrary rotation preserves snapping, custom tools, support and persistence.
	world.restore_build(initial)
	await frames(3)
	helm = world.pieces.back()
	world.city.position = Vector3(18, 0, -12)
	world.city.rotation.y = 0.63
	world.player.global_position = world.city.to_global(Vector3(0, 0.7, 1.5))
	world.player.velocity = Vector3.ZERO
	await frames(12)
	check(world.player_on_city(), "Collision follows translated and rotated deck")
	world.player.camera.look_at(world.city.to_global(Vector3(4, 0.6, 0)))
	world.select_piece(world.Piece.Kind.HELM)
	world.update_candidate()
	check(world.candidate.is_equal_approx(Vector3(4, 0.6, 0)), "Placement still uses city grid after arbitrary turn")
	check(world.valid, "Helm placement works after city motion")
	world.custom_tool.open_block(world.custom_blocks[0])
	check(world.custom_tool.ghost.global_transform.is_equal_approx(world.custom_blocks[0].global_transform), "Custom editor preview stays on moved city")
	world.custom_tool.set_mode(0)
	world.custom_tool.apply_drag(0, 0.5, world.custom_tool.ghost.position, world.custom_tool.ghost.dimensions, world.city.global_basis.x)
	check(is_equal_approx(world.custom_tool.ghost.position.x, 3.5), "Custom move handles follow city axes")
	world.custom_tool.close()
	world.save_path = "/private/tmp/tractionism-city-test.json"
	var saved: Dictionary = world.capture_build()
	check(world.BuildState.valid(JSON.parse_string(JSON.stringify(saved))), "Version 3 city save validates")
	world.save_build()
	world.city.position = Vector3.ZERO
	world.load_build()
	check(world.capture_build() == saved, "City pose and construction round-trip")
	await frames(5)
	# Unsupported helms are pruned just like other deck fixtures.
	helm = world.pieces.back()
	var base: StaticBody3D = world.pieces[4]
	world.pieces.erase(base)
	base.queue_free()
	world.prune_unsupported()
	check(helm not in world.pieces, "Removing helm foundation removes helm")
	world.restore_build(initial)
	await frames(3)
	helm = world.pieces.back()
	world.player.position = Vector3(0, 0.65, 1.5)
	world.player.velocity = Vector3.ZERO
	await frames(10)
	world.city.start_piloting(helm)
	world.city.position.z = -343.9
	world.city.position.y = world.city.terrain_height(world.city.transform)
	world.city.drive(0.5, 1, 0, false)
	check(world.city.boundary_blocked and is_equal_approx(world.city.position.z, -343.9), "Finite terrain edge stops the entire city")
	world.city.stop_piloting()
	world.player.position = Vector3(80, 0, 80)
	check(not world.city.start_piloting(helm), "Cannot remotely use helm")
	DirAccess.remove_absolute(world.save_path)
	print("City movement integration tests: ", failures, " failures")
	quit(1 if failures else 0)
