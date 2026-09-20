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
	world.player.position = Vector3(0, 0.65, 4)
	world.add_custom_block({"position": [0.0, 0.6, 0.0], "size": [2.0, 2.0, 0.25], "rotation": 0, "material": 1})
	await frames(5)
	var tool = world.custom_tool
	tool.open_block(world.custom_blocks[0])
	var position: Vector3 = tool.ghost.position
	var dimensions: Vector3 = tool.ghost.dimensions
	tool.set_mode(0)
	tool.apply_drag(0, 1.25, position, dimensions, Vector3.RIGHT)
	check(is_equal_approx(tool.ghost.position.x, 1.25), "Move handle changes world position")
	tool.set_mode(1)
	position = tool.ghost.position
	tool.apply_drag(0, 0.25, position, dimensions, Vector3.RIGHT)
	check(is_equal_approx(tool.ghost.dimensions.x, 2.25), "Scale handle changes width")
	check(is_equal_approx(tool.ghost.position.x - tool.ghost.dimensions.x / 2, position.x - dimensions.x / 2), "Scale preserves opposite face")
	tool.apply_drag(1, -20, position, dimensions, Vector3.UP)
	check(is_equal_approx(tool.ghost.dimensions.y, 0.1), "Resize minimum clamp")
	tool.set_dimensions(Vector3(4, 0.25, 4))
	check(tool.ghost.dimensions.is_equal_approx(Vector3(4, 0.25, 4)), "Floor preset updates preview")
	tool.rotate_block()
	check(tool.ghost.quarter == 1, "Quick rotation")
	tool.choose_material(3)
	check(tool.ghost.material_id == 3 and world.selected_material == 3, "Swatch instantly updates material")
	tool.duplicate_block()
	check(tool.editing == null and world.custom_blocks[0].visual.visible, "Duplicate keeps original")
	check(tool.ghost.material_id == 3 and tool.ghost.quarter == 1, "Duplicate preserves material and rotation")
	tool.close()
	check(world.custom_blocks.size() == 1 and world.custom_blocks[0].material_id == 1, "Cancel duplicate preserves original state")
	# Exercise real palette button signals: one selection applies and closes.
	world.player.camera.look_at(Vector3(0, 1.5, 0))
	var history_size: int = world.undo_history.size()
	world.material_palette.open_palette()
	check(world.material_palette.paint_target == world.custom_blocks[0], "Palette captures aimed piece")
	world.material_palette.buttons[2].pressed.emit()
	check(world.custom_blocks[0].material_id == 2 and world.selected_material == 2, "One-click palette paints and selects")
	check(not world.material_palette.opened and not world.player.input_locked, "Palette restores movement")
	check(world.undo_history.size() == history_size + 1, "Painting creates one undo action")
	world.undo_build()
	check(world.custom_blocks[0].material_id == 1, "Material selection painting is undoable")
	await frames(2)
	world.material_palette.open_palette()
	world.material_palette.close()
	check(world.custom_blocks[0].material_id == 1, "Cancel palette does not paint")
	# Orbit preview does not permanently change the first-person camera.
	var camera_transform: Transform3D = world.player.camera.transform
	tool.open_block(world.custom_blocks[0])
	tool.orbiting = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(30, 10)
	tool._input(motion)
	check(not world.player.camera.transform.is_equal_approx(camera_transform), "Orbit changes preview viewpoint")
	tool.close()
	check(world.player.camera.transform.is_equal_approx(camera_transform), "Closing restores first-person viewpoint")
	print("Editor workflow integration tests: ", failures, " failures")
	quit(1 if failures else 0)
