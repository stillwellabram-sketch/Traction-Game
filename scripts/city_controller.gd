extends Node3D

# Each city keeps its construction in local coordinates.
# Only this root is moved; terrain and the walking player remain world-space.
const BRAKING := 5.0
var world: Node3D
var systems: Node3D
var build_pieces: Array[StaticBody3D] = []
var decoration: Array[StaticBody3D] = []
var tow_target: Node3D
var towed_by: Node3D
var last_obstacle := ""
var active_helm: StaticBody3D
var speed := 0.0
var pivot := Vector3.ZERO
var local_bounds := AABB()
var boundary_blocked := false
var motion_recorded := false

func piloting() -> bool:
	return is_instance_valid(active_helm)

func start_piloting(helm: StaticBody3D) -> bool:
	if not is_instance_valid(helm) or helm not in build_pieces or helm.kind != world.Piece.Kind.HELM or not systems.operational(helm.get_meta("block_id")):
		return false
	if world.player.global_position.distance_to(helm.global_position) > 3.0:
		world.notice.text = "Move within 3 m of the helm to take control"
		return false
	if not world.player_on_city():
		world.notice.text = "Stand on the city to use its helm"
		return false
	active_helm = helm
	motion_recorded = false
	speed = 0
	boundary_blocked = false
	world.player.piloting = true
	world.player.velocity = Vector3.ZERO
	refresh_bounds()
	pivot = local_bounds.get_center()
	pivot.y = 0
	world.preview.hide()
	world.notice.text = "Helm engaged · W/S drive · A/D steer · Space brake · E exit"
	return true

func stop_piloting() -> void:
	active_helm = null
	speed = 0
	boundary_blocked = false
	if is_instance_valid(world) and is_instance_valid(world.player) and world.city == self:
		world.player.piloting = false
		world.player.velocity = Vector3.ZERO
		world.notice.text = "City stopped · walk and build normally"

func refresh_bounds() -> void:
	var first := true
	for body in build_pieces + decoration:
		for visual in body.get_children():
			if visual is MeshInstance3D:
				var bounds: AABB = body.transform * visual.transform * visual.get_aabb()
				local_bounds = bounds if first else local_bounds.merge(bounds)
				first = false

func inside_yard(next_transform: Transform3D) -> bool:
	var bounds := next_transform * local_bounds
	return bounds.position.x >= -350 and bounds.end.x <= 350 and bounds.position.z >= -350 and bounds.end.z <= 350

func roughness_at(point: Vector3) -> float:
	var terrain := world.get_node("Landscape")
	var h: float = terrain.height_at(point.x, point.z)
	var slope := 0.0
	for offset in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		slope = maxf(slope, absf(terrain.height_at(point.x + offset.x, point.z + offset.y) - h) / 2)
	return slope * 3.0

func terrain_height(next_transform: Transform3D) -> float:
	var terrain := world.get_node("Landscape")
	var bounds := next_transform * local_bounds
	var result := -INF
	for x in [bounds.position.x, bounds.get_center().x, bounds.end.x]:
		for z in [bounds.position.z, bounds.get_center().z, bounds.end.z]:
			result = maxf(result, terrain.height_at(x, z))
	return result

func blocked_by_geometry(next_transform: Transform3D) -> bool:
	var excluded: Array[RID] = [world.get_node("Landscape").get_rid()]
	for own_city in [self, tow_target, towed_by]:
		if is_instance_valid(own_city):
			for chunk in own_city.systems.chunks.values() + own_city.systems.decoration_chunks.values():
				excluded.append(chunk.get_rid())
	var space := get_world_3d().direct_space_state
	for block in build_pieces + decoration:
		for shape in block.get_children():
			if not shape is CollisionShape3D or shape.shape == null:
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape.shape
			query.collision_mask = 5
			query.exclude = excluded
			query.margin = 0.005
			var local: Transform3D = block.transform * shape.transform
			query.transform = global_transform * local
			var destination: Transform3D = next_transform * local
			query.motion = destination.origin - query.transform.origin
			var sweep := space.cast_motion(query)
			if sweep[0] < 0.999:
				return true
			query.motion = Vector3.ZERO
			query.transform = destination
			if not space.intersect_shape(query, 1).is_empty():
				return true
	return false

func drive(delta: float, throttle: float, steering: float, brake: bool) -> void:
	if not piloting():
		return
	if active_helm not in build_pieces or active_helm.is_queued_for_deletion() or not systems.operational(active_helm.get_meta("block_id")):
		stop_piloting()
		return
	throttle = clampf(throttle, -1, 1)
	steering = clampf(steering, -1, 1)
	if is_instance_valid(towed_by):
		speed = 0
		return
	var tow_mass: float = tow_target.systems.performance().mass if is_instance_valid(tow_target) else 0.0
	var performance: Dictionary = systems.performance(roughness_at(global_position), tow_mass)
	var desired_speed: float = throttle * performance.speed * (1.0 if throttle >= 0 else 0.5)
	if brake:
		desired_speed = 0
	var slowing := brake or is_zero_approx(throttle) or speed * throttle < 0
	speed = move_toward(speed, desired_speed, (BRAKING if slowing else performance.acceleration) * delta)
	var old_transform := global_transform
	var next_basis := (Basis(Vector3.UP, steering * performance.turn_rate * delta) * old_transform.basis).orthonormalized()
	var forward := next_basis * active_helm.basis * Vector3.FORWARD
	var next_origin := old_transform * pivot - next_basis * pivot + forward * speed * delta
	next_origin.y = global_position.y
	var next_transform := Transform3D(next_basis, next_origin)
	var ground_y := terrain_height(next_transform)
	boundary_blocked = not inside_yard(next_transform) or absf(ground_y - global_position.y) > preload("res://scripts/mechanics/balance.gd").MAX_STEP_HEIGHT
	next_transform.origin.y = ground_y
	boundary_blocked = boundary_blocked or blocked_by_geometry(next_transform)
	last_obstacle = "Terrain obstacle / map edge" if boundary_blocked else ""
	if boundary_blocked:
		speed = 0
		return
	if not motion_recorded and not next_transform.is_equal_approx(old_transform):
		motion_recorded = true
		world.undo_history.clear()
	# Carry the pilot by exactly the same rigid motion, including rotation.
	var rider: Transform3D = old_transform.affine_inverse() * world.player.global_transform
	global_transform = next_transform
	world.player.global_transform = next_transform * rider

func to_record() -> Dictionary:
	return {"x": position.x, "y": position.y, "z": position.z, "yaw": rotation.y}

func restore(record: Dictionary) -> void:
	transform = Transform3D(Basis(Vector3.UP, float(record.get("yaw", 0))), Vector3(record.get("x", 0), record.get("y", 0), record.get("z", 0)))
