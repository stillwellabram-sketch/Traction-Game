extends AnimatableBody3D

const Materials = preload("res://scripts/material_library.gd")
var material_id := 0

# IDs are append-only: existing version-1 saves retain their piece types.
enum Kind { FOUNDATION, FLOOR, WALL, DOORWAY, STAIRS, RAILING, WINDOW, HALF_WALL, PILLAR, HELM, ENGINE_SMALL, ENGINE_MEDIUM, ENGINE_LARGE, WHEEL, TREAD, LEG, GUN, GUT, WHEEL_3, WHEEL_4, WHEEL_5, WHEEL_6 }
const NAMES := ["FOUNDATION", "FLOOR", "WALL", "DOORWAY", "STAIRS", "RAILING", "WINDOW", "HALF WALL", "PILLAR", "HELM", "SMALL ENGINE", "MEDIUM ENGINE", "LARGE ENGINE", "WHEEL 2×2", "TREAD", "LEG", "GUN", "GUT", "WHEEL 3×3", "WHEEL 4×4", "WHEEL 5×5", "WHEEL 6×6"]

static func is_edge(value: int) -> bool:
	return value in [Kind.WALL, Kind.DOORWAY, Kind.RAILING, Kind.WINDOW, Kind.HALF_WALL]

static func is_full_wall(value: int) -> bool:
	return value in [Kind.WALL, Kind.DOORWAY, Kind.WINDOW]

static func has_span(value: int) -> bool:
	return value in [Kind.FOUNDATION, Kind.FLOOR] or is_edge(value)

# Span is stored per piece; old saves keep their original four-metre modules.
var span := 4.0
var depth := 4.0
var kind := 0
var ghost := false
var cell := Vector3.ZERO
var quarter := 0
var finish: StandardMaterial3D

func setup(piece_kind: int, location: Vector3, turns: int, preview := false, surface := 0, width := 4.0, length := -1.0) -> void:
	sync_to_physics = false
	kind = piece_kind
	span = width if has_span(kind) else 4.0
	depth = length if kind in [Kind.FOUNDATION, Kind.FLOOR] and length > 0 else span
	cell = location
	quarter = posmod(turns, 4)
	ghost = preview
	position = cell
	rotation.y = quarter * PI / 2
	collision_layer = 0 if ghost else 1
	collision_mask = 0
	material_id = surface
	finish = Materials.get_material(material_id)
	if ghost:
		finish = StandardMaterial3D.new()
	if ghost:
		finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match kind:
		0: box(Vector3(span, 0.6, depth), Vector3(0, -0.3, 0))
		1: box(Vector3(span, 0.2, depth), Vector3(0, -0.1, 0))
		2: box(Vector3(span, 3, 0.18), Vector3(0, 1.5, 0))
		3:
			var opening := minf(1.4, span - 0.2)
			var post := (span - opening) / 2
			for side in [-1.0, 1.0]:
				box(Vector3(post, 3, 0.18), Vector3(side * (span + opening) / 4, 1.5, 0))
			box(Vector3(opening, 0.65, 0.18), Vector3(0, 2.675, 0))
		4:
			for i in range(12):
				var h := (i + 1) * 0.25
				box(Vector3(3.6, h, 4.0 / 12), Vector3(0, h / 2, 2.0 - (i + 0.5) * 4.0 / 12), false)
			# A hidden ramp gives smooth walking over the visible stair treads.
			if not ghost:
				var ramp := ConvexPolygonShape3D.new()
				ramp.points = PackedVector3Array([Vector3(-1.8,0,2), Vector3(1.8,0,2), Vector3(-1.8,0,-2), Vector3(1.8,0,-2), Vector3(-1.8,3,-2), Vector3(1.8,3,-2)])
				var collider := CollisionShape3D.new()
				collider.shape = ramp
				add_child(collider)
		Kind.RAILING:
			var bays := maxi(1, ceili(span / 2.0))
			for i in bays + 1:
				var x := lerpf(-span / 2 + 0.06, span / 2 - 0.06, float(i) / bays)
				box(Vector3(0.12, 1.1, 0.12), Vector3(x, 0.55, 0))
			for y in [0.4, 1.05]:
				box(Vector3(span, 0.12, 0.12), Vector3(0, y, 0))
		Kind.WINDOW:
			box(Vector3(span, 1, 0.18), Vector3(0, 0.5, 0))
			box(Vector3(span, 0.5, 0.18), Vector3(0, 2.75, 0))
			var bays := maxi(1, ceili(span / 2.0))
			var post := minf(0.2, span * 0.1)
			for i in bays + 1:
				var x := lerpf(-(span - post) / 2, (span - post) / 2, float(i) / bays)
				box(Vector3(post, 1.5, 0.18), Vector3(x, 1.75, 0))
		Kind.HALF_WALL:
			box(Vector3(span, 1.5, 0.18), Vector3(0, 0.75, 0))
		Kind.PILLAR:
			box(Vector3(0.35, 3, 0.35), Vector3(0, 1.5, 0))
			for y in [0.1, 2.9]:
				box(Vector3(0.65, 0.2, 0.65), Vector3(0, y, 0))
		Kind.HELM:
			box(Vector3(1.0, 0.08, 0.8), Vector3(0, 0.04, 0))
			box(Vector3(0.25, 0.85, 0.3), Vector3(0, 0.47, 0))
			box(Vector3(0.9, 0.15, 0.55), Vector3(0, 0.95, 0))
			box(Vector3(0.09, 0.65, 0.12), Vector3(0, 1.25, 0.14))
			box(Vector3(0.65, 0.09, 0.12), Vector3(0, 1.25, 0.14))
			var ring := MeshInstance3D.new()
			var wheel := TorusMesh.new()
			wheel.inner_radius = 0.27
			wheel.outer_radius = 0.34
			ring.mesh = wheel
			ring.rotation.x = PI / 2
			ring.position = Vector3(0, 1.25, 0.14)
			ring.material_override = finish
			add_child(ring)
			# A small deck arrow indicates local -Z without obscuring the view.
			var arrow_material := StandardMaterial3D.new()
			arrow_material.albedo_color = Color("f6c76e")
			for segment in 3:
				var arrow := MeshInstance3D.new()
				var shape := BoxMesh.new()
				shape.size = Vector3(0.035, 0.012, 0.24 if segment == 0 else 0.13)
				arrow.mesh = shape
				arrow.position = Vector3(0, 1.035, -0.06)
				if segment > 0:
					var side := -1.0 if segment == 1 else 1.0
					arrow.position = Vector3(side * 0.04, 1.035, -0.14)
					arrow.rotation.y = side * -PI / 4
				arrow.material_override = finish if ghost else arrow_material
				add_child(arrow)

	if kind == Kind.HELM:
		preload("res://scripts/mechanics/module_visual.gd").build_helm(self)
	if kind >= 10:
		preload("res://scripts/mechanics/module_visual.gd").build(self)

func box(size: Vector3, offset: Vector3, solid := true) -> void:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = finish
	mesh.position = offset
	add_child(mesh)
	if not ghost and solid:
		var collider := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		collider.shape = bounds
		collider.position = offset
		add_child(collider)

func tint(valid: bool) -> void:
	finish.albedo_color = Color(0.25, 0.95, 0.72, 0.45) if valid else Color(1, 0.25, 0.18, 0.45)

func set_surface(index: int) -> void:
	material_id = index
	finish = Materials.get_material(index)
	for child in get_children():
		if child is MeshInstance3D:
			child.material_override = preload("res://scripts/mechanics/mechanical_materials.gd").finish(child.get_meta("mechanical_role"), finish, index) if child.has_meta("mechanical_role") else finish
