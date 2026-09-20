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
	await frames(4)
	check(world.Rules.grid(2) == 0.25 and world.Rules.grid(8) == 0.25, "Uniform fine grids")
	check(world.Rules.grid(8, true) == 0.125, "Pillar precision mode")
	check(world.supported(8, Vector3(0.75, 0.6, 0.25), 0), "Off-centre pillar supported")
	check(world.supported(9, Vector3(0.5, 0.6, 0.75), 1), "Off-centre helm supported")
	check(not world.supported(8, Vector3(5.9, 0.6, 0), 0), "Pillar base may not overhang deck")
	check(world.supported(2, Vector3(0, 0.6, 0.5), 0, world.pieces, 2), "Interior partition supported")
	world.add_piece(0, Vector3(20, 0.6, 0), 0, 2, 2)
	world.add_piece(0, Vector3(22, 0.6, 0), 0, 2, 2)
	check(world.supported(8, Vector3(21, 0.6, 0.25), 0), "Pillar can cross a supported tile seam")
	world.add_piece(0, Vector3(25, 0.6, 0), 0, 2, 2)
	check(not world.supported(2, Vector3(23.5, 0.6, 0), 0, world.pieces, 4), "Coverage rejects gap between tiles")
	check(world.same_slot(0, Vector3(20.5, 0.6, 0), 0, world.pieces[12], 2), "Overlapping deck rejected")
	check(not world.same_slot(0, Vector3(22, 0.6, 0), 0, world.pieces[12], 2), "Flush deck seam allowed")
	world.add_piece(2, Vector3(20, 0.6, -1), 0, 3, 2)
	var wall: StaticBody3D = world.pieces.back()
	check(world.same_slot(6, Vector3(20.5, 0.6, -1), 0, wall, 1), "Wall segment overlap rejected")
	check(not world.same_slot(6, Vector3(21.5, 0.6, -1), 0, wall, 1), "Flush wall segments allowed")
	check(world.supported(6, Vector3(20.5, 3.6, -1), 0, world.pieces, 1), "Small wall stacks on wider wall")
	check(not world.supported(6, Vector3(21, 3.6, -1), 0, world.pieces, 2), "Overhanging stacked wall rejected")
	world.add_piece(8, Vector3(20.75, 0.6, 0.25), 0)
	check(world.supported(1, Vector3(21, 3.6, 0), 0, world.pieces, 1), "Offset pillar supports compact upper floor")
	world.add_piece(1, Vector3(21, 3.6, 0), 0, 1, 1)
	world.add_piece(7, Vector3(20, 0.6, 0), 0, 1, 1)
	check(world.supported(2, Vector3(20, 2.1, 0), 0, world.pieces, 1), "Half walls support stacked wall sections")
	world.remember_build()
	var before_removal: int = world.pieces.size()
	var removed: StaticBody3D = world.pieces[13]
	world.pieces.erase(removed)
	removed.queue_free()
	world.prune_unsupported()
	check(world.pieces.size() == before_removal - 3, "Removing seam support removes pillar and dependent floor")
	world.undo_build()
	check(world.pieces.size() == before_removal and world.pieces[12].span == 2, "Undo restores fine-grid structure and sizes")
	await frames(3)
	# A one-metre doorway remains wide enough for the actual player capsule.
	world.add_piece(0, Vector3(40, 0.6, 0), 0, 2, 2)
	world.add_piece(3, Vector3(40, 0.6, 0), 0, 1, 1)
	world.player.position = Vector3(40, 0.65, 0.8)
	world.player.velocity = Vector3.ZERO
	world.player.rotation = Vector3.ZERO
	await frames(12)
	Input.action_press("move_forward")
	await frames(24)
	Input.action_release("move_forward")
	check(world.player.position.z < -0.2, "Player walks through compact doorway")
	# Raycast placement selects finer locations rather than old tile centres.
	world.player.position = Vector3(0, 0.65, 4)
	world.player.velocity = Vector3.ZERO
	await frames(10)
	world.player.camera.look_at(Vector3(0.8, 0.6, 0.3))
	world.select_piece(8)
	world.update_candidate()
	check(world.candidate.is_equal_approx(Vector3(0.75, 0.6, 0.25)), "Pillar preview follows quarter-metre grid")
	check(world.valid, "Fine pillar preview is buildable")
	world.player.camera.look_at(Vector3(5.9, 0.6, 0))
	world.select_piece(2)
	world.selected_span = 1
	world.refresh_preview()
	world.update_candidate()
	check(is_equal_approx(world.candidate.x, 6) and world.candidate_turns % 2 == 1, "Wall magnet aligns deck perimeter")
	world.select_piece(0)
	world.update_candidate()
	check(is_equal_approx(world.candidate.x, 6.5), "Compact foundation magnet extends flush")
	world.city.position = Vector3(10, 0, -8)
	world.city.rotation.y = 0.37
	world.player.global_position = world.city.to_global(Vector3(-2, 0.65, 4))
	world.player.velocity = Vector3.ZERO
	await frames(5)
	world.player.camera.look_at(world.city.to_global(Vector3(0.8, 0.6, 0.3)))
	world.select_piece(8)
	world.update_candidate()
	check(world.candidate.is_equal_approx(Vector3(0.75, 0.6, 0.25)) and world.valid, "Fine grid follows translated and rotated city")
	# Geometry and save records retain independent module sizes.
	var saved: Dictionary = world.capture_build()
	check(world.BuildState.valid(JSON.parse_string(JSON.stringify(saved))), "Version 4 mixed spans validate")
	world.save_path = "/private/tmp/tractionism-fine-test.json"
	world.save_build()
	world.load_build()
	check(world.capture_build() == saved, "Mixed-span save/load round-trip")
	check(world.pieces[12].span == 2 and world.pieces[12].get_child(0).mesh.size.x == 2, "Saved compact geometry restored")
	var legacy := {"version": 1, "pieces": [{"kind": 0, "x": 0, "y": 0.6, "z": 0, "rotation": 0}]}
	world.restore_build(legacy)
	check(world.pieces[0].span == 4 and world.pieces[0].get_child(0).mesh.size.x == 4, "Legacy geometry stays four metres")
	DirAccess.remove_absolute(world.save_path)
	print("Fine building integration tests: ", failures, " failures")
	quit(1 if failures else 0)
