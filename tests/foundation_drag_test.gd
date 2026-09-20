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
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	world.player.require_mouse_capture = false
	world.player.position = Vector3(0, 4, 5)
	world.add_piece(13, Vector3.ZERO, 0)
	for i in 3: await physics_frame
	world.select_piece(0)
	world.player.camera.look_at(Vector3(0, 2.32, 0))
	world.update_candidate()
	check(world.valid and world.begin_structural_drag(), "Drag starts from a supported wheel mount")
	world.player.camera.look_at(world.city.to_global(world.drag_pointer + Vector3(4, 0, -2)))
	world.update_candidate()
	check(world.valid and is_equal_approx(world.selected_span, 6) and is_equal_approx(world.selected_depth, 4), "Dragging forms one rectangular foundation")
	var cost: float = world.chunks.cost_of(world.preview)
	check(cost > 0, "Expanded slab has a material cost")
	var before: int = world.pieces.size()
	world.place_requested = true
	world._physics_process(0.016)
	check(world.pieces.size() == before + 1, "Drag commits one block")
	check(not world.structural_drag, "Release ends drag")
	var deck: StaticBody3D = world.pieces.back()
	check(deck.span == 6 and deck.depth == 4, "Built collision geometry retains rectangular dimensions")
	check(world.supported(8, deck.cell + Vector3(2, 0, 0), 0), "Pillars attach near long edge of expanded slab")
	check(not world.supported(8, deck.cell + Vector3(0, 0, 2.5), 0), "Short edge does not gain phantom support")
	# Escape cancels before either the player mouse toggle or placement can run.
	world.select_piece(0)
	world.candidate = deck.cell + Vector3(4, 0, 0)
	world.valid = true
	world.player.camera.look_at(world.candidate)
	check(world.begin_structural_drag(), "Second drag starts")
	var wallet: float = world.chunks.scrap
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	world._input(escape)
	check(not world.structural_drag and world.chunks.scrap == wallet, "Escape cancels without spending scrap")
	var saved: Dictionary = world.capture_build()
	check(world.BuildState.valid(saved), "Rectangle save validates")
	world.restore_build(saved)
	check(world.pieces.back().depth == 4 and world.pieces.back().span == 6, "Save restores both rectangle axes")
	var design: Dictionary = world.profiles.design(world.city)
	check(world.profiles.valid_design(design), "Rectangle blueprint validates")
	check(world.profiles.design_cost(design) > cost, "Blueprint cost includes rectangle and running gear")
	world.mechanics_ui.open_menu()
	check(world.mechanics_ui.tabs.size() == 3 and world.player.input_locked, "Three side tabs lock building input")
	world.mechanics_ui.show_category(1)
	check(world.mechanics_ui.catalogue.get_child_count() == 2, "Decoration includes helm and custom block")
	world.mechanics_ui.show_category(2)
	check(world.mechanics_ui.catalogue.get_child_count() == 12, "Engineering includes all wheel sizes")
	world.mechanics_ui.choose_piece(21)
	check(world.selected == 21 and not world.mechanics_ui.opened and not world.player.input_locked, "Catalogue selection resumes building")
	for kind in world.NAMES.size():
		check(world.Rules.grid(kind) == 0.25 and world.Rules.grid(kind, true) == 0.125, "All pieces share fixture grid")
	print("Foundation drag tests: %d failures" % failures)
	quit(1 if failures else 0)
