extends SceneTree

var failures := 0
func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await process_frame

func mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run this pointer/render test without --headless")
		quit(1)
		return
	var world = load("res://scenes/main.tscn").instantiate()
	world.load_player_profile = false
	root.add_child(world)
	preload("res://tests/legacy_fixture.gd").add(world)
	world.player.position = Vector3(0, 0.65, 4)
	world.add_custom_block({"position": [0.0, 0.6, 0.0], "size": [2.0, 2.0, 0.25], "rotation": 0, "material": 1})
	await frames(10)
	var tool = world.custom_tool
	tool.open_block(world.custom_blocks[0])
	await frames(5)
	check(tool.gizmo.handles.size() == 3, "Three projected handles rendered")
	var handle: Dictionary = tool.gizmo.handles[0].duplicate()
	var start: Vector3 = tool.ghost.position
	mouse_button(handle.point, true)
	check(tool.gizmo.dragging == 0, "Viewport click picks X handle")
	var motion := InputEventMouseMotion.new()
	motion.position = handle.point + handle.direction * handle.density
	motion.relative = handle.direction * handle.density
	root.push_input(motion)
	mouse_button(motion.position, false)
	check(is_equal_approx(tool.ghost.position.x, start.x + 1), "Viewport drag moves one metre")
	check(tool.gizmo.dragging == -1, "Release ends drag")
	await frames(3)
	var material_button: Button = tool.material_buttons[3]
	var button_centre := material_button.get_global_rect().get_center()
	mouse_button(button_centre, true)
	mouse_button(button_centre, false)
	check(tool.ghost.material_id == 3, "UI click selects brick instantly")
	tool.set_mode(1)
	await frames(3)
	handle = tool.gizmo.handles[1].duplicate()
	var height: float = tool.ghost.dimensions.y
	mouse_button(handle.point, true)
	motion.position = handle.point + handle.direction * handle.density * 0.5
	motion.relative = handle.direction * handle.density * 0.5
	root.push_input(motion)
	mouse_button(motion.position, false)
	check(is_equal_approx(tool.ghost.dimensions.y, height + 0.5), "Viewport resize grows height")
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/tractionism-fast-editor.png")
	tool.close()
	world.player.camera.look_at(Vector3(0, 1.5, 0))
	world.material_palette.open_palette()
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/tractionism-material-palette.png")
	check(root.get_visible_rect().encloses(world.material_palette.panel.get_global_rect()), "Palette is fully visible")
	var palette_button: Button = world.material_palette.buttons[0]
	button_centre = palette_button.get_global_rect().get_center()
	mouse_button(button_centre, true)
	mouse_button(button_centre, false)
	check(world.custom_blocks[0].material_id == 0 and not world.material_palette.opened, "Palette click paints and dismisses")
	print("Editor pointer/render tests: ", failures, " failures")
	quit(1 if failures else 0)
