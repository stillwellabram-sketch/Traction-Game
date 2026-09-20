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
	await frames(3)
	# Stacking inherits the underlying wall's edge and rotation.
	check(world.supported(2, Vector3(-4, 3.6, -6), 0), "Full wall stacks on full wall")
	check(not world.supported(2, Vector3(-4, 3.6, -6), 1), "Perpendicular stack rejected")
	world.add_piece(2, Vector3(-4, 3.6, -6), 0, 3)
	check(world.supported(6, Vector3(-4, 6.6, -6), 0), "Window stacks on second wall")
	world.add_piece(6, Vector3(-4, 6.6, -6), 0, 1)
	check(world.supported(1, Vector3(-4, 9.6, -4), 0), "Stacked wall supports upper floor")
	world.player.position = Vector3(-4, 0.6, -2)
	world.player.camera.look_at(Vector3(-4, 2.9, -6))
	world.select_piece(2)
	world.update_candidate()
	check(world.candidate.is_equal_approx(Vector3(-4, 3.6, -6)), "Aim picks exact upper wall socket")
	world.remember_build()
	var stack_count: int = world.pieces.size()
	var base: StaticBody3D = world.pieces[10]
	world.pieces.erase(base)
	base.queue_free()
	world.prune_unsupported()
	check(world.pieces.size() == stack_count - 3, "Removing base collapses stacked walls")
	world.undo_build()
	check(world.pieces.size() == stack_count, "Undo restores complete wall stack")
	await frames(2)
	# Custom shapes live outside the structural support graph.
	var record := {"position": [12.0, 0.0, 0.0], "size": [4.0, 3.0, 0.3], "rotation": 0, "material": 1}
	world.add_custom_block(record)
	world.prune_unsupported()
	check(world.custom_blocks.size() == 1, "Custom block survives structural pruning")
	check(not world.supported(2, Vector3(12, 3, 0), 0), "Custom wall cannot support stacked wall")
	check(not world.supported(1, Vector3(12, 3, 2), 0), "Custom wall cannot support floor")
	world.player.position = Vector3(12, 0.05, 4)
	world.player.velocity = Vector3.ZERO
	world.player.camera.rotation = Vector3.ZERO
	await frames(20)
	world.update_candidate()
	check(not world.valid and world.reason.contains("no structural sockets"), "Custom hit cannot become structural placement")
	Input.action_press("move_forward")
	await frames(65)
	Input.action_release("move_forward")
	check(world.player.position.z > 0.45, "Custom block has player collision")
	world.player.position = Vector3(12, 0.05, 5)
	world.player.velocity = Vector3.ZERO
	await frames(5)
	var tool = world.custom_tool
	tool.open_block(world.custom_blocks[0])
	check(world.player.input_locked and tool.opened, "Inspector locks player input")
	tool.fields[0].value = 13.0
	tool.fields[3].value = 6.0
	tool.choose_material(3)
	tool.update_preview()
	await frames(2)
	check(tool.can_apply, "Valid transformed block can be committed")
	tool.commit()
	check(not tool.opened and not world.player.input_locked, "Applying closes inspector")
	check(world.custom_blocks[0].dimensions.x == 6 and world.custom_blocks[0].position.x == 13, "Move and resize applied")
	check(world.custom_blocks[0].collider.shape.size.x == 6 and world.custom_blocks[0].material_id == 3, "Collision and material updated")
	world.undo_build()
	check(world.custom_blocks[0].dimensions.x == 4 and world.custom_blocks[0].material_id == 1, "Undo restores transform and material")
	await frames(3)
	tool.open_block(world.custom_blocks[0])
	tool.fields[3].value = 8
	tool.close()
	check(world.custom_blocks[0].dimensions.x == 4, "Cancel leaves original untouched")
	tool.open_block()
	tool.fields[0].value = world.player.position.x
	tool.fields[1].value = world.player.position.y
	tool.fields[2].value = world.player.position.z
	await frames(2)
	check(not tool.can_apply, "Inspector blocks player overlap")
	tool.commit()
	check(world.custom_blocks.size() == 1 and tool.opened, "Invalid commit is rejected")
	tool.fields[2].value = 1
	tool.fields[0].value = 17
	await frames(2)
	tool.commit()
	check(world.custom_blocks.size() == 2, "New custom block placement")
	tool.open_block(world.custom_blocks[1])
	tool.delete_current()
	check(world.custom_blocks.size() == 1, "Inspector deletes custom block")
	world.undo_build()
	check(world.custom_blocks.size() == 2, "Undo restores deleted custom block")
	var serialized: Dictionary = world.capture_build()
	check(world.BuildState.valid(serialized), "Current serialization validates")
	world.save_path = "/private/tmp/tractionism-custom-test.json"
	world.save_build()
	world.custom_blocks[0].configure(Vector3(50, 0, 0), Vector3.ONE, 1, 0)
	world.load_build()
	check(world.capture_build() == serialized, "Materials and custom transforms round-trip")
	var invalid := serialized.duplicate(true)
	invalid.custom_blocks[0].size[0] = -1
	check(not world.BuildState.valid(invalid), "Malformed dimensions rejected")
	var malformed_file := FileAccess.open(world.save_path, FileAccess.WRITE)
	malformed_file.store_string(JSON.stringify(invalid))
	malformed_file.close()
	world.load_build()
	check(world.capture_build() == serialized, "Invalid save leaves current world intact")
	invalid = serialized.duplicate(true)
	invalid.custom_blocks[0].position[0] = INF
	check(not world.BuildState.valid(invalid), "Non-finite coordinates rejected")
	var legacy: Dictionary = {"version": 1, "pieces": [{"kind": 0, "x": 0, "y": 0.6, "z": 0, "rotation": 0}]}
	check(world.BuildState.valid(JSON.parse_string(JSON.stringify(legacy))), "JSON legacy save accepted")
	world.restore_build(legacy)
	check(world.pieces.size() == 1 and world.custom_blocks.is_empty(), "Legacy save restores")
	for i in world.Materials.NAMES.size():
		var material: StandardMaterial3D = world.Materials.get_material(i)
		check(material.albedo_texture != null and material.normal_texture != null and material.roughness_texture != null, "PBR maps loaded")
		check(material.uv1_triplanar and not material.uv1_world_triplanar, "Texture tiling follows the moving geometry")
	DirAccess.remove_absolute(world.save_path)
	print("Custom building integration tests: ", failures, " failures")
	quit(1 if failures else 0)
