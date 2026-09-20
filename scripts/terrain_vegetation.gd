extends Node3D
# Batched, deterministic foliage. Track beds are kept clear using the terrain's
# shared corridor mask; shrubs are cosmetic and never obstruct construction.
var instance_count := 0
func generate(terrain: Node3D) -> void:
	name = "Scrubland"
	var rng := RandomNumberGenerator.new()
	rng.seed = 27183
	var grass := plant_mesh(false)
	var bush := plant_mesh(true)
	for z in range(-320, 321, 64):
		for x in range(-320, 321, 64):
			for shrub in [false, true]:
				var transforms: Array[Transform3D] = []
				var colors: Array[Color] = []
				for i in (48 if shrub else 190):
					var px := x + rng.randf_range(-32, 32)
					var pz := z + rng.randf_range(-32, 32)
					if Vector2(px, pz).length() < 10 or terrain.track_at(px, pz).z > 0.12:
						continue
					var patch: float = terrain.noise.get_noise_2d(px * 4, pz * 4)
					if patch < (-0.12 if shrub else -0.35):
						continue
					var scale := rng.randf_range(0.65, 1.6) if shrub else rng.randf_range(0.65, 1.3)
					var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale)
					transforms.append(Transform3D(basis, Vector3(px, terrain.height_at(px, pz) - 0.04, pz)))
					colors.append(Color(rng.randf_range(0.6, 1.0), rng.randf_range(0.75, 1.05), rng.randf_range(0.65, 0.95)))
				if transforms.is_empty():
					continue
				var batch := MultiMesh.new()
				batch.transform_format = MultiMesh.TRANSFORM_3D
				batch.use_colors = true
				batch.mesh = bush if shrub else grass
				batch.instance_count = transforms.size()
				for i in transforms.size():
					batch.set_instance_transform(i, transforms[i])
					batch.set_instance_color(i, colors[i])
				var visual := MultiMeshInstance3D.new()
				visual.multimesh = batch
				visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				visual.visibility_range_end = 330 if shrub else 180
				add_child(visual)
				instance_count += transforms.size()

	add_bank_rocks(terrain, rng)

func add_bank_rocks(terrain: Node3D, rng: RandomNumberGenerator) -> void:
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.18, 0.11)
	material.roughness = 1.0
	rock.material = material
	var transforms: Array[Transform3D] = []
	for route in terrain.ROUTES:
		for along in range(-350, 351, 6):
			for lane in [-1, 1]:
				for edge in [-1, 1]:
					var across: float = route.z + lane * route.w + edge * rng.randf_range(12.5, 16.5)
					var point := Vector2(route.x, route.y) * across + Vector2(-route.y, route.x) * (along + rng.randf_range(-2, 2))
					if absf(point.x) > 350 or absf(point.y) > 350:
						continue
					var basis := Basis.from_euler(Vector3(rng.randf(), rng.randf() * TAU, rng.randf()))
					basis = basis.scaled(Vector3(rng.randf_range(1.1, 3.0), rng.randf_range(0.8, 1.6), rng.randf_range(1, 2.5)))
					transforms.append(Transform3D(basis, Vector3(point.x, terrain.height_at(point.x, point.y) - 0.3, point.y)))
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = rock
	batch.instance_count = transforms.size()
	for i in transforms.size(): batch.set_instance_transform(i, transforms[i])
	var visual := MultiMeshInstance3D.new()
	visual.name = "ErodedBankRocks"
	visual.multimesh = batch
	add_child(visual)

func plant_mesh(shrub: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 613 if shrub else 12
	for i in (36 if shrub else 16):
		var angle := rng.randf_range(0, TAU)
		var side := Vector3(cos(angle), 0, sin(angle))
		var origin := side * rng.randf_range(0, 0.8 if shrub else 0.6)
		var height := rng.randf_range(0.35, 1.05) if shrub else rng.randf_range(0.18, 0.48)
		var width := rng.randf_range(0.15, 0.3) if shrub else 0.045
		var tip := origin + Vector3.UP * height + side * 0.23
		var middle := origin + Vector3.UP * height * 0.6
		for point in [origin, middle - side * width, tip, origin, tip, middle + side * width]:
			surface.set_color(Color(0.25, 0.36, 0.11) if shrub else Color(0.32, 0.4, 0.14))
			surface.add_vertex(point)
	surface.generate_normals()
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/vegetation.gdshader")
	surface.set_material(material)
	return surface.commit()
