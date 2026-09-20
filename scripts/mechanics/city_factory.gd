extends RefCounted
const City = preload("res://scripts/city_controller.gd")
const Systems = preload("res://scripts/mechanics/city_systems.gd")
const Piece = preload("res://scripts/piece.gd")

static func add_piece(city: Node3D, kind: int, position: Vector3, quarter := 0, material := 0, span := 4.0, depth := -1.0) -> StaticBody3D:
	var piece := Piece.new()
	piece.setup(kind, position, quarter, false, material, span, depth)
	city.add_child(piece)
	city.build_pieces.append(piece)
	city.systems.add_block(piece)
	return piece

static func create(world: Node3D, owner_id: String, location: Vector3) -> Node3D:
	var city := City.new()
	city.world = world
	city.name = owner_id
	world.add_child(city)
	city.position = location
	city.systems = Systems.new()
	city.systems.owner_id = owner_id
	city.add_child(city.systems)
	return city

static func starter(world: Node3D, owner_id: String, location: Vector3) -> Node3D:
	var city := create(world, owner_id, location)
	# Centre foundation is the chassis for new designs.
	add_piece(city, 0, Vector3(0, 3.0, 0), 0, 2)
	for x in [-4, 0, 4]:
		for z in [-4, 0, 4]:
			if x != 0 or z != 0:
				add_piece(city, 0, Vector3(x, 3.0, z), 0, 2)
	add_piece(city, 11, Vector3(0, 3.0, 0))
	for x in [-4, 4]:
		for z in [-3, 3]:
			add_piece(city, 13, Vector3(x, 0, z))
	add_piece(city, 9, Vector3(0, 3.0, 3))
	add_piece(city, 16, Vector3(0, 3.0, -4))
	city.refresh_bounds()
	return city
