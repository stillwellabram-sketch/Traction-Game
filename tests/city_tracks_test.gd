extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var terrain = preload("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	for i in 3: await physics_frame
	check(terrain.height_at(0, 0) == 0, "Spawn clearing remains level")
	check(terrain.track_at(107, -300).z == 1 and terrain.track_at(107, 300).z == 1, "City scars remain ruler-straight across the map")
	check(terrain.raw_height(107, 0) > terrain.raw_height(107, 6) + 0.8, "Tread impressions are physical raised ridges")
	check(terrain.raw_height(107, 6) < terrain.raw_height(88, 6) - 2, "Track beds are recessed below surrounding ground")
	# Cross-slope must not force the two sides of an old city to different heights.
	for route in terrain.ROUTES:
		var normal := Vector2(route.x, route.y)
		var forward := Vector2(-route.y, route.x)
		for along in [-294.0, -150.0, -30.0, 6.0, 114.0, 246.0]:
			var left: Vector2 = normal * (route.z - route.w) + forward * along
			var right: Vector2 = normal * (route.z + route.w) + forward * along
			var level: float = terrain.raw_height(left.x, left.y)
			check(absf(level - terrain.raw_height(right.x, right.y)) < 0.01, "Paired trench beds share a common elevation")
			for offset in [-6.0, 6.0]:
				var edge: Vector2 = left + normal * offset
				check(absf(level - terrain.raw_height(edge.x, edge.y)) < 0.01, "Individual track bed is level across its width")
			if maxf(absf(left.x), absf(left.y)) < 355 and maxf(absf(right.x), absf(right.y)) < 355:
				check(absf(terrain.height_at(left.x, left.y) - terrain.height_at(right.x, right.y)) < 0.15, "Meshed left and right track beds retain their shared grade")
	for point in [Vector2(106.7, 8.3), Vector2(94.1, -8.7), Vector2(232.8, 178.2)]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 100, point.y), Vector3(point.x, -20, point.y), 1)
		var hit := root.world_3d.direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and absf(hit.position.y - terrain.height_at(point.x, point.y)) < 0.01, "Terrain sampler and physical surface agree")
	var world := Node3D.new()
	root.add_child(world)
	terrain.reparent(world)
	var city := preload("res://scripts/city_controller.gd").new()
	city.world = world
	city.local_bounds = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	world.add_child(city)
	check(city.terrain_height(Transform3D(Basis.IDENTITY, Vector3(107, 0, 6))) < 0, "City terrain following permits sunken track beds")
	check(terrain.vegetation.instance_count > 5000, "Scrubland contains instanced foliage")
	for visual in terrain.vegetation.get_children():
		if visual.name == "ErodedBankRocks":
			continue
		var batch: MultiMesh = visual.multimesh
		for i in batch.instance_count:
			var p := batch.get_instance_transform(i).origin
			check(terrain.track_at(p.x, p.z).z <= 0.12, "Vegetation keeps worn track beds clear")
	print("City tracks tests: %d failures" % failures)
	quit(1 if failures else 0)
