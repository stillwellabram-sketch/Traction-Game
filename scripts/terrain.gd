extends StaticBody3D

# The same sampled surface drives rendering, collision, placement and city motion.
const EXTENT := 360.0
const STEP := 2.0
const COUNT := 360
const STRIDE := COUNT + 1
# Straight migration corridors: normal X/Z, centre, half separation between tracks.
const ROUTES := [Vector4(1, 0, 130, 23), Vector4(0.9393727, 0.3428978, -230, 28)]
var noise := FastNoiseLite.new()
var heights := PackedFloat32Array()
var bed_profile_samples: Dictionary = {}
const PROFILE_STEP := 32.0
var vegetation: Node3D

func _init() -> void:
	noise.seed = 6721
	noise.frequency = 0.009
	noise.fractal_octaves = 4

# X = lane distance, Y = longitudinal distance, Z = worn ground coverage.
func track_at(x: float, z: float) -> Vector3:
	var nearest := Vector3(INF, 0, 0)
	for route in ROUTES:
		var across: float = x * route.x + z * route.y - route.z
		var lane := absf(absf(across) - route.w)
		if lane < nearest.x:
			nearest = Vector3(lane, -x * route.y + z * route.x, 1.0 - smoothstep(10, 16, lane))
	return nearest

func natural_height(x: float, z: float) -> float:
	var distance := maxf(absf(x), absf(z))
	var blend := smoothstep(65, 205, distance)
	var hills := 8 + 30 * (noise.get_noise_2d(x, z) * 0.5 + 0.5)
	return blend * hills

func nearest_route(x: float, z: float) -> int:
	var index := 0
	var distance := INF
	for i in ROUTES.size():
		var route: Vector4 = ROUTES[i]
		var lane := absf(absf(x * route.x + z * route.y - route.z) - route.w)
		if lane < distance:
			distance = lane
			index = i
	return index

func bed_profile_sample(route_index: int, sample_index: int) -> float:
	var key := Vector2i(route_index, sample_index)
	if bed_profile_samples.has(key):
		return bed_profile_samples[key]
	var route: Vector4 = ROUTES[route_index]
	var normal := Vector2(route.x, route.y)
	var forward := Vector2(-route.y, route.x)
	var lowest := INF
	# Both track footprints share a cutting height. Sample a short length of the
	# route too, so the old city's bed bridges small bumps with a gradual grade.
	for longitudinal in [-16.0, 0.0, 16.0]:
		for side in [-1.0, 1.0]:
			for lateral in [-10.0, 0.0, 10.0]:
				var p: Vector2 = normal * (route.z + side * route.w + lateral) + forward * (sample_index * PROFILE_STEP + longitudinal)
				lowest = minf(lowest, natural_height(p.x, p.y))
	var height := lowest - 7.5
	bed_profile_samples[key] = height
	return height

func bed_height(route_index: int, along: float) -> float:
	var sample_index := floori(along / PROFILE_STEP)
	var weight := smoothstep(0, 1, along / PROFILE_STEP - sample_index)
	return lerpf(bed_profile_sample(route_index, sample_index), bed_profile_sample(route_index, sample_index + 1), weight)

func raw_height(x: float, z: float) -> float:
	var ground := natural_height(x, z)
	var track := track_at(x, z)
	var bed := 1.0 - smoothstep(10, 14, track.x)
	# Broad, crosswise grousers every 12 m, with eroded rather than sheer edges.
	var rib := 1.0 - smoothstep(0.7, 2.8, absf(wrapf(track.y, -6, 6)))
	var ridge := rib * (1.0 - smoothstep(8, 12, track.x)) * 2.2
	var bank := exp(-pow((track.x - 16) / 3.0, 2)) * 0.9
	if bed > 0:
		ground = lerpf(ground, bed_height(nearest_route(x, z), track.y), bed)
	return ground + ridge + bank

func height_at(x: float, z: float) -> float:
	if heights.is_empty() or absf(x) >= EXTENT or absf(z) >= EXTENT:
		return raw_height(x, z)
	var grid := Vector2(x + EXTENT, z + EXTENT) / STEP
	var ix := floori(grid.x)
	var iz := floori(grid.y)
	var u := grid.x - ix
	var v := grid.y - iz
	var a := heights[iz * STRIDE + ix]
	var b := heights[iz * STRIDE + ix + 1]
	var c := heights[(iz + 1) * STRIDE + ix]
	var d := heights[(iz + 1) * STRIDE + ix + 1]
	return a + (b - a) * u + (c - a) * v if u + v <= 1 else d + (c - d) * (1 - u) + (b - d) * (1 - v)

func _ready() -> void:
	name = "Landscape"
	heights.resize(STRIDE * STRIDE)
	for z in STRIDE:
		for x in STRIDE:
			heights[z * STRIDE + x] = raw_height(x * STEP - EXTENT, z * STEP - EXTENT)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/terrain.gdshader")
	material.set_shader_parameter("routes", PackedVector4Array(ROUTES))
	material.set_shader_parameter("soil_normal", load("res://assets/materials/Concrete034/NormalGL.jpg"))
	material.set_shader_parameter("soil_texture", load("res://assets/materials/Concrete034/Color.jpg"))
	var mesh := make_surface(-EXTENT, EXTENT, STEP, false)
	var visual := MeshInstance3D.new()
	visual.name = "Ground"
	visual.mesh = mesh
	visual.material_override = material
	add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	add_child(collision)
	# A coarse, non-playable continuation takes the corridors to the skyline.
	var horizon := MeshInstance3D.new()
	horizon.name = "DistantLandscape"
	horizon.mesh = make_surface(-1800, 1800, 24, true)
	horizon.material_override = material
	horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(horizon)
	vegetation = preload("res://scripts/terrain_vegetation.gd").new()
	add_child(vegetation)
	vegetation.generate(self)

func make_surface(low: float, high: float, spacing: float, distant: bool) -> ArrayMesh:
	var count := roundi((high - low) / spacing)
	var stride := count + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(stride * stride)
	normals.resize(vertices.size())
	colors.resize(vertices.size())
	for z in stride:
		for x in stride:
			var px := low + x * spacing
			var pz := low + z * spacing
			var i := z * stride + x
			vertices[i] = Vector3(px, height_at(px, pz), pz)
			normals[i] = Vector3(height_at(px - 1, pz) - height_at(px + 1, pz), 2, height_at(px, pz - 1) - height_at(px, pz + 1)).normalized()
			var track := track_at(px, pz)
			colors[i] = Color(track.z, noise.get_noise_2d(px * 3, pz * 3) * 0.5 + 0.5, 0, 1)
	for z in count:
		for x in count:
			var px := low + (x + 0.5) * spacing
			var pz := low + (z + 0.5) * spacing
			if distant and absf(px) < EXTENT and absf(pz) < EXTENT:
				continue
			var a := z * stride + x
			var inner_edge := -1
			if distant:
				if absf(px) < EXTENT and is_equal_approx(pz, EXTENT + spacing / 2): inner_edge = 0
				elif absf(pz) < EXTENT and is_equal_approx(px, -EXTENT - spacing / 2): inner_edge = 1
				elif absf(px) < EXTENT and is_equal_approx(pz, -EXTENT - spacing / 2): inner_edge = 2
				elif absf(pz) < EXTENT and is_equal_approx(px, EXTENT + spacing / 2): inner_edge = 3
			if inner_edge >= 0:
				# Match every playable boundary vertex; coarse horizon triangles
				# otherwise leave cracks where a deep trench crosses the map edge.
				var corners := [a, a + 1, a + stride + 1, a + stride]
				var perimeter: Array[int] = []
				for side in 4:
					perimeter.append(corners[side])
					if side != inner_edge: continue
					for sub in range(1, roundi(spacing / STEP)):
						var point: Vector3 = vertices[corners[side]].lerp(vertices[corners[(side + 1) % 4]], sub * STEP / spacing)
						perimeter.append(append_surface_vertex(point.x, point.z, vertices, normals, colors))
				var centre := append_surface_vertex(px, pz, vertices, normals, colors)
				for side in perimeter.size():
					indices.append_array(PackedInt32Array([centre, perimeter[side], perimeter[(side + 1) % perimeter.size()]]))
			else:
				indices.append_array(PackedInt32Array([a, a + 1, a + stride, a + 1, a + stride + 1, a + stride]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func append_surface_vertex(x: float, z: float, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> int:
	var index := vertices.size()
	vertices.append(Vector3(x, height_at(x, z), z))
	normals.append(Vector3(height_at(x - 1, z) - height_at(x + 1, z), 2, height_at(x, z - 1) - height_at(x, z + 1)).normalized())
	colors.append(Color(track_at(x, z).z, noise.get_noise_2d(x * 3, z * 3) * 0.5 + 0.5, 0, 1))
	return index
