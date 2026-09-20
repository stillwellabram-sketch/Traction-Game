extends RefCounted
const Balance = preload("res://scripts/mechanics/balance.gd")

static func build_proxy(piece: Node3D) -> void:
	var kind: int = piece.kind
	var size: Vector3 = Balance.MODULES[kind].size
	if Balance.is_traction(kind):
		build_running_gear_proxy(piece)
		return
	piece.box(Vector3(size.x, 0.12, size.z), Vector3(0, 0.06, 0))
	if kind in [10, 11, 12]:
		piece.box(size * Vector3(0.75, 0.7, 0.8), Vector3(0, size.y * 0.4, 0))
		for side in [-1, 1]:
			for i in 4:
				piece.box(Vector3(size.x * 0.12, size.y * 0.45, size.z * 0.12), Vector3(side * size.x * 0.42, size.y * 0.5, (i - 1.5) * size.z * 0.19))
		piece.box(Vector3(size.x * 0.35, size.y * 0.15, size.z * 0.6), Vector3(0, size.y * 0.86, 0))
	elif kind == Balance.GUN:
		piece.box(Vector3(0.55, 0.55, 0.6), Vector3(0, 0.4, 0))
		piece.box(Vector3(0.8, 0.4, 0.7), Vector3(0, 0.85, 0))
		piece.box(Vector3(0.16, 0.16, 1.6), Vector3(0, 0.95, -0.4))
	elif kind == Balance.GUT:
		for side in [-1, 1]:
			piece.box(Vector3(0.4, 1.8, 2), Vector3(side * 1.25, 0.95, 0))
		piece.box(Vector3(2.3, 0.4, 1.5), Vector3(0, 0.4, 0))
		for i in 7:
			piece.box(Vector3(0.18, 0.7, 0.35), Vector3((i - 3) * 0.32, 0.65, -0.8))

# Detail geometry is batched into one mesh per finish, independent of the
# existing collision/support proxies. Nothing here creates physics shapes.
const Finishes = preload("res://scripts/mechanics/mechanical_materials.gd")
static var primitives: Dictionary = {}
var owner_piece: Node3D
var batches: Dictionary = {}
var art_transform := Transform3D.IDENTITY

static func build(piece: Node3D) -> void:
	build_proxy(piece)
	for child in piece.get_children():
		if child is MeshInstance3D:
			child.visible = false
	var detail = new()
	detail.owner_piece = piece
	detail.assemble()
	detail.commit()

func emit(mesh: Mesh, at: Vector3, role: String, basis := Basis.IDENTITY) -> void:
	if not batches.has(role):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[role] = surface
	batches[role].append_from(mesh, 0, art_transform * Transform3D(basis, at))

func plate(at: Vector3, size: Vector3, role := "frame", basis := Basis.IDENTITY) -> void:
	var key := "box" + str(size)
	if not primitives.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		primitives[key] = mesh
	emit(primitives[key], at, role, basis)

func drum(at: Vector3, radius: float, length: float, axis := Vector3.RIGHT, role := "steel", segments := 20) -> void:
	var key := "cylinder%s/%s/%s" % [radius, length, segments]
	if not primitives.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		mesh.radial_segments = segments
		primitives[key] = mesh
	emit(primitives[key], at, role, Basis(Quaternion(Vector3.UP, axis.normalized())))

func rod(a: Vector3, b: Vector3, radius: float, role := "steel") -> void:
	drum((a + b) / 2, radius, a.distance_to(b), (b - a).normalized(), role, 12)

func beam(a: Vector3, b: Vector3, width: float, role := "frame") -> void:
	plate((a + b) / 2, Vector3(width, a.distance_to(b), width), role, Basis(Quaternion(Vector3.UP, (b - a).normalized())))

func flange(at: Vector3, radius: float, width: float, axis := Vector3.RIGHT, role := "steel") -> void:
	drum(at, radius, width, axis, role)
	var basis := Basis(Quaternion(Vector3.UP, axis.normalized()))
	for i in 8:
		var angle := i * TAU / 8
		var bolt := basis * Vector3(cos(angle) * radius * 0.78, width * 0.6, sin(angle) * radius * 0.78)
		drum(at + bolt, minf(radius * 0.08, 0.035), 0.035, axis, "brass", 6)

func assemble() -> void:
	var kind: int = owner_piece.kind
	var size: Vector3 = Balance.MODULES[kind].size
	if Balance.is_traction(kind):
		running_gear(kind)
		return
	# Twin load-bearing skids, crossmembers and mounting bolts.
	for side in [-1.0, 1.0]:
		plate(Vector3(side * size.x * 0.39, 0.07, 0), Vector3(size.x * 0.16, 0.14, size.z), "rust")
		for z in [-size.z * 0.4, size.z * 0.4]:
			drum(Vector3(side * size.x * 0.39, 0.16, z), 0.04, 0.035, Vector3.UP, "steel", 6)
	for z in [-size.z * 0.35, size.z * 0.35]:
		plate(Vector3(0, 0.08, z), Vector3(size.x * 0.85, 0.12, 0.12))
	match kind:
		10, 11, 12: engine(size)
		Balance.WHEEL: wheel()
		Balance.TREAD: tread()
		Balance.LEG: leg()
		Balance.GUN: gun()
		Balance.GUT: gut()

static func build_helm(piece: Node3D) -> void:
	for child in piece.get_children():
		if child is MeshInstance3D:
			child.visible = false
	var detail = new()
	detail.owner_piece = piece
	detail.helm()
	detail.commit()

func helm() -> void:
	plate(Vector3(0, 0.05, 0), Vector3(0.95, 0.1, 0.76), "rust")
	plate(Vector3(0, 0.49, 0), Vector3(0.27, 0.8, 0.3), "body")
	for side in [-1.0, 1.0]:
		beam(Vector3(side * 0.35, 0.13, 0), Vector3(side * 0.12, 0.65, 0), 0.06)
		for z in [-0.28, 0.28]:
			drum(Vector3(side * 0.37, 0.12, z), 0.035, 0.03, Vector3.UP, "steel", 6)
	plate(Vector3(0, 0.96, -0.02), Vector3(0.88, 0.13, 0.5), "body")
	for x in [-0.26, 0, 0.26]:
		flange(Vector3(x, 1.04, -0.1), 0.087, 0.015, Vector3.UP, "brass")
		drum(Vector3(x, 1.053, -0.1), 0.068, 0.008, Vector3.UP, "steel")
		beam(Vector3(x, 1.06, -0.1), Vector3(x + 0.035, 1.06, -0.13), 0.008, "frame")
	rod(Vector3(0, 1.1, -0.05), Vector3(0, 1.25, 0.14), 0.055)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.27
	ring.outer_radius = 0.34
	ring.rings = 24
	ring.ring_segments = 10
	emit(ring, Vector3(0, 1.25, 0.14), "brass", Basis(Vector3.RIGHT, PI / 2))
	for i in 5:
		var angle := i * TAU / 5
		beam(Vector3(0, 1.25, 0.14), Vector3(sin(angle) * 0.29, 1.25 + cos(angle) * 0.29, 0.14), 0.035, "steel")
	flange(Vector3(0, 1.25, 0.18), 0.09, 0.04, Vector3.BACK, "frame")

func engine(size: Vector3) -> void:
	var radius := size.x * 0.3
	var center := Vector3(0, size.y * 0.46, 0)
	drum(center, radius, size.z * 0.67, Vector3.BACK, "body", 28)
	for z in [-0.34, -0.23, 0.23, 0.34]:
		flange(center + Vector3(0, 0, size.z * z), radius * 1.08, size.z * 0.045, Vector3.BACK, "rust")
	flange(center + Vector3(0, 0, size.z * 0.385), radius * 0.66, size.z * 0.04, Vector3.BACK, "body")
	drum(center + Vector3(0, 0, size.z * 0.425), radius * 0.22, size.z * 0.07, Vector3.BACK, "steel")
	for side in [-1.0, 1.0]:
		# Panelled crankcase and vertically finned auxiliary cylinders.
		plate(Vector3(side * size.x * 0.39, size.y * 0.29, 0), Vector3(size.x * 0.19, size.y * 0.3, size.z * 0.58), "body")
		for i in 5:
			plate(Vector3(side * size.x * 0.493, size.y * 0.29, (i - 2) * size.z * 0.1), Vector3(0.012, size.y * 0.2, size.z * 0.025), "frame")
		var tank := Vector3(side * size.x * 0.36, size.y * 0.66, size.z * 0.28)
		drum(tank, size.x * 0.105, size.y * 0.43, Vector3.UP, "body")
		for level in [-0.18, 0.05, 0.22]:
			flange(tank + Vector3(0, size.y * level, 0), size.x * 0.118, 0.035, Vector3.UP, "frame")
		# Exposed copper manifold and bright pushrod, both within the footprint.
		var a := Vector3(side * size.x * 0.35, size.y * 0.55, -size.z * 0.3)
		var b := a + Vector3(0, size.y * 0.23, 0)
		rod(a, b, size.x * 0.025, "brass")
		rod(b, Vector3(b.x, b.y, size.z * 0.22), size.x * 0.025, "brass")
		rod(Vector3(side * size.x * 0.22, size.y * 0.75, -size.z * 0.22), Vector3(side * size.x * 0.22, size.y * 0.75, size.z * 0.22), size.x * 0.02)
	# End shaft, bearing and valve housing distinguish a machine from a crate.
	flange(center + Vector3(0, 0, -size.z * 0.4), radius * 0.65, size.z * 0.1, Vector3.FORWARD)
	drum(center + Vector3(0, 0, -size.z * 0.46), radius * 0.26, size.z * 0.075, Vector3.FORWARD, "frame")
	plate(Vector3(0, size.y * 0.83, 0), Vector3(size.x * 0.35, size.y * 0.15, size.z * 0.4), "body")
	for i in 6:
		plate(Vector3(0, size.y * 0.915, (i - 2.5) * size.z * 0.06), Vector3(size.x * 0.28, 0.025, size.z * 0.023), "frame")

func wheel() -> void:
	var center := Vector3(0, 0.02, 0)
	drum(center, 0.54, 0.7, Vector3.RIGHT, "frame", 32)
	for i in 28:
		var angle := i * TAU / 28
		var radial := Vector3(0, cos(angle), sin(angle))
		plate(center + radial * 0.574, Vector3(0.78, 0.085, 0.12), "rust", Basis(Vector3.RIGHT, angle))
	for side in [-1.0, 1.0]:
		var hub := center + Vector3(side * 0.37, 0, 0)
		flange(hub, 0.44, 0.055, Vector3.RIGHT * side, "rust")
		for i in 10:
			var angle := i * TAU / 10
			var radial := Vector3(0, cos(angle), sin(angle))
			beam(hub + radial * 0.12, hub + radial * 0.4, 0.065, "body")
		flange(hub + Vector3(side * 0.045, 0, 0), 0.2, 0.09, Vector3.RIGHT * side)
	beam(Vector3(-0.43, 0.15, 0.42), Vector3(-0.43, 0.75, 0), 0.14)
	beam(Vector3(0.43, 0.15, 0.42), Vector3(0.43, 0.75, 0), 0.14)
	rod(Vector3(-0.42, 0.68, 0.35), Vector3(0.42, 0.68, 0.35), 0.085, "body")

func tread() -> void:
	plate(Vector3(0, -0.03, 0), Vector3(0.66, 0.5, 2.2), "body")
	for z in [-0.85, -0.42, 0.0, 0.42, 0.85]:
		drum(Vector3(0, -0.06, z), 0.34 if absf(z) < 0.8 else 0.42, 0.86, Vector3.RIGHT, "frame")
		for side in [-1.0, 1.0]:
			flange(Vector3(side * 0.46, -0.06, z), 0.26, 0.065, Vector3.RIGHT * side, "rust")
	for i in 9:
		for side in [-1.0, 1.0]:
			shoe(Vector3(0, -0.06 + side * 0.48, (i - 4) * 0.19), 0 if side > 0 else PI)
	for end in [-1.0, 1.0]:
		for i in 10:
			var angle := -PI / 2 + (i + 0.5) * PI / 10
			shoe(Vector3(0, -0.06 + sin(angle) * 0.48, end * (0.85 + cos(angle) * 0.48)), atan2(end * cos(angle), sin(angle)))
	for side in [-1.0, 1.0]:
		beam(Vector3(side * 0.42, 0.18, -0.85), Vector3(side * 0.42, 0.18, 0.85), 0.12, "body")

func shoe(at: Vector3, angle: float) -> void:
	var basis := Basis(Vector3.RIGHT, angle)
	plate(at, Vector3(1.08, 0.07, 0.17), "rust", basis)
	plate(at + basis * Vector3(0, 0.055, 0), Vector3(1.04, 0.045, 0.045), "steel", basis)
	for side in [-1.0, 1.0]:
		drum(at + basis * Vector3(side * 0.41, 0.055, 0.04), 0.022, 0.025, basis.y, "frame", 6)

func leg() -> void:
	plate(Vector3(0, 0.125, 0), Vector3(1.12, 0.25, 1.05), "body")
	for side in [-1.0, 1.0]:
		for z in [-0.36, 0.36]:
			plate(Vector3(side * 0.42, 0.4, z), Vector3(0.16, 0.09, 0.18), "rust")
		beam(Vector3(side * 0.3, 0.38, 0.15), Vector3(side * 0.3, 1.05, -0.22), 0.16, "body")
		beam(Vector3(side * 0.3, 1.05, -0.22), Vector3(side * 0.3, 1.82, 0.18), 0.19, "body")
		rod(Vector3(side * 0.44, 0.48, 0.29), Vector3(side * 0.44, 1.16, 0.05), 0.065, "rust")
		rod(Vector3(side * 0.44, 1.1, 0.07), Vector3(side * 0.44, 1.7, 0.25), 0.032, "steel")
	for level in [Vector3(0, 0.48, 0.15), Vector3(0, 1.07, -0.22), Vector3(0, 1.82, 0.18)]:
		rod(level - Vector3(0.35, 0, 0), level + Vector3(0.35, 0, 0), 0.13, "frame")
		for side in [-1.0, 1.0]:
			flange(level + Vector3(side * 0.4, 0, 0), 0.16, 0.08, Vector3.RIGHT * side)

func gun() -> void:
	flange(Vector3(0, 0.19, 0), 0.46, 0.18, Vector3.UP, "rust")
	plate(Vector3(0, 0.5, 0.12), Vector3(0.48, 0.48, 0.55), "body")
	for side in [-1.0, 1.0]:
		plate(Vector3(side * 0.34, 0.73, 0), Vector3(0.13, 0.48, 0.64), "body")
		flange(Vector3(side * 0.43, 0.85, -0.05), 0.15, 0.06, Vector3.RIGHT * side)
		rod(Vector3(side * 0.19, 1.07, 0.23), Vector3(side * 0.19, 1.07, -0.72), 0.045, "steel")
	drum(Vector3(0, 0.95, -0.38), 0.095, 1.6, Vector3.FORWARD, "frame", 24)
	for z in [-0.35, -0.65, -0.98]:
		flange(Vector3(0, 0.95, z), 0.14, 0.07, Vector3.FORWARD, "rust")
	# Muzzle stays aligned with Combat's (0, .95, -1.25) ray origin.
	drum(Vector3(0, 0.95, -1.19), 0.12, 0.07, Vector3.FORWARD, "steel")
	drum(Vector3(0, 0.95, -1.229), 0.075, 0.006, Vector3.FORWARD, "frame")

func gut() -> void:
	for side in [-1.0, 1.0]:
		plate(Vector3(side * 1.27, 0.95, 0), Vector3(0.36, 1.7, 1.85), "body")
		for z in [-0.7, 0.7]:
			beam(Vector3(side * 1.47, 0.18, z), Vector3(side * 1.47, 1.68, -z), 0.09, "rust")
		for y in [0.35, 1.35]:
			flange(Vector3(side * 1.48, y, -0.12), 0.22, 0.035, Vector3.RIGHT * side, "steel")
	plate(Vector3(0, 0.25, 0.1), Vector3(2.3, 0.22, 1.65), "frame")
	for z in [-0.58, 0.36]:
		drum(Vector3(0, 0.68, z), 0.27, 2.25, Vector3.RIGHT, "frame")
		for i in 13:
			var x := (i - 6) * 0.17
			flange(Vector3(x, 0.68, z), 0.32, 0.08, Vector3.RIGHT, "rust")
			for tooth in 4:
				var angle := tooth * PI / 2 + i * 0.3
				plate(Vector3(x, 0.68 + cos(angle) * 0.32, z + sin(angle) * 0.32), Vector3(0.11, 0.13, 0.12), "steel", Basis(Vector3.RIGHT, angle))
	plate(Vector3(0, 1.76, 0.3), Vector3(2.5, 0.13, 0.5), "body")

func commit() -> void:
	for role in batches:
		var visual := MeshInstance3D.new()
		visual.mesh = batches[role].commit()
		visual.set_meta("mechanical_role", role)
		visual.set_meta("detail_only", true)
		visual.material_override = owner_piece.finish if owner_piece.ghost else Finishes.finish(role, owner_piece.finish, owner_piece.material_id)
		owner_piece.add_child(visual)

static func build_running_gear_proxy(piece: Node3D) -> void:
	var kind: int = piece.kind
	var height := Balance.mount_height(kind)
	var width := Balance.mount_width(kind)
	piece.box(Vector3(width, 0.16, width), Vector3(0, height - 0.08, 0))
	if Balance.is_wheel(kind):
		var diameter: float = Balance.MODULES[kind].size.x
		var visual := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = diameter / 2
		mesh.bottom_radius = diameter / 2
		mesh.height = diameter * 0.6
		visual.mesh = mesh
		visual.position.y = diameter / 2
		visual.rotation.z = PI / 2
		visual.material_override = piece.finish
		piece.add_child(visual)
		if not piece.ghost:
			var collider := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = diameter / 2
			shape.height = diameter * 0.6
			collider.shape = shape
			collider.transform = visual.transform
			piece.add_child(collider)
		for side in [-1.0, 1.0]:
			piece.box(Vector3(0.13, height - diameter / 2, 0.22), Vector3(side * diameter * 0.32, (height + diameter / 2) / 2, 0))
	elif kind == Balance.TREAD:
		piece.box(Vector3(1.1, 1.12, 2.65), Vector3(0, 0.56, 0))
		piece.box(Vector3(0.65, 0.25, 0.8), Vector3(0, 1.2, 0))
	else:
		piece.box(Vector3(1.1, 0.25, 1.1), Vector3(0, 0.125, 0))
		piece.box(Vector3(0.7, 1.8, 0.6), Vector3(0, 1.15, 0))

func running_gear(kind: int) -> void:
	var height := Balance.mount_height(kind)
	var width := Balance.mount_width(kind)
	if Balance.is_wheel(kind):
		var diameter: float = Balance.MODULES[kind].size.x
		var scale_factor := diameter / 1.24
		art_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_factor), Vector3(0, diameter / 2 - 0.02 * scale_factor, 0))
		wheel()
	elif kind == Balance.TREAD:
		art_transform.origin.y = 0.6
		tread()
	else:
		leg()
	art_transform = Transform3D.IDENTITY
	plate(Vector3(0, height - 0.08, 0), Vector3(width, 0.16, width), "body")
	for side in [-1.0, 1.0]:
		beam(Vector3(side * width * 0.4, height * 0.53, 0), Vector3(side * width * 0.4, height - 0.1, 0), 0.12, "frame")
		for z in [-width * 0.36, width * 0.36]:
			drum(Vector3(side * width * 0.36, height - 0.01, z), 0.035, 0.015, Vector3.UP, "steel", 6)
