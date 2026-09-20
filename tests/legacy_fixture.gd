extends RefCounted
# Explicit legacy geometry fixture; production startup is intentionally empty.
static func add(world: Node3D) -> void:
	for x in range(-1, 2):
		for z in range(-1, 2):
			world.add_piece(0, Vector3(x * 4, 0.6, z * 4), 0)
	world.add_piece(3, Vector3(0, 0.6, -6), 0)
	world.add_piece(2, Vector3(-4, 0.6, -6), 0)
	world.add_piece(2, Vector3(4, 0.6, -6), 0)
	world.select_piece(0)
