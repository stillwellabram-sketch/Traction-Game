extends SceneTree
const Piece = preload("res://scripts/piece.gd")
const Systems = preload("res://scripts/mechanics/city_systems.gd")
const B = preload("res://scripts/mechanics/balance.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var systems := Systems.new()
	root.add_child(systems)
	for kind in range(9, 22):
		var piece := Piece.new()
		piece.setup(kind, Vector3.ZERO, 0)
		root.add_child(piece)
		var count := 0
		var body: MeshInstance3D
		var hardware: MeshInstance3D
		for child in piece.get_children():
			if child is MeshInstance3D and child.visible:
				count += 1
				check(child.get_meta("detail_only", false), "Visible machinery is separate from support proxies")
				if child.get_meta("mechanical_role", "") == "body":
					body = child
				else:
					hardware = child
		check(count >= 3 and count <= 5, "Detailed art uses at most five finish batches")
		var hardware_material: Material = hardware.material_override
		piece.set_surface(1)
		check(body.material_override == piece.finish, "Paint changes body panels")
		check(hardware.material_override == hardware_material, "Paint retains working metal parts")
		if kind >= 10:
			check(systems.cost_of(piece) == B.MODULES[kind].cost, "Art does not affect module balance")
		piece.free()
		var ghost := Piece.new()
		ghost.setup(kind, Vector3.ZERO, 0, true)
		ghost.tint(false)
		for child in ghost.get_children():
			if child is MeshInstance3D and child.visible:
				check(child.material_override == ghost.finish, "All ghost details share placement validity tint")
		ghost.free()
	print("Mechanical art tests: %d failures" % failures)
	quit(1 if failures else 0)
