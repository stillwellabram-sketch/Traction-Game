extends Node3D
const B = preload("res://scripts/mechanics/balance.gd")
var links: Dictionary = {}
var last_result := ""
signal city_captured(city: Node3D)
signal processing_started(city: Node3D)

func attach(attacker: Node3D, target: Node3D, hit_point: Vector3) -> bool:
	if attacker == target or not hit_point.is_finite() or is_instance_valid(attacker.towed_by) or is_instance_valid(target.towed_by) or is_instance_valid(target.tow_target):
		last_result = "Invalid tow · city already linked"
		return false
	if target.systems.performance().mobility > B.TOW_MOBILITY_THRESHOLD:
		last_result = "Disable target mobility below %.0f%% first" % (B.TOW_MOBILITY_THRESHOLD * 100)
		return false
	var anchor := source_anchor(attacker)
	if anchor.distance_to(hit_point) > B.TOW_RANGE:
		last_result = "Move within %.0f m to tow" % B.TOW_RANGE
		return false
	if is_instance_valid(attacker.tow_target):
		release(attacker)
	attacker.tow_target = target
	target.towed_by = attacker
	target.speed = 0
	links[attacker] = {"target": target, "target_anchor": target.to_local(hit_point), "length": anchor.distance_to(hit_point), "progress": 0.0}
	last_result = "Tow attached · J reel in · R release · towing increases incoming damage"
	return true

func source_anchor(city: Node3D) -> Vector3:
	var gut: StaticBody3D = city.systems.find_module(B.GUT)
	return gut.to_global(Vector3(0, 0.8, -0.9)) if gut != null else city.to_global(Vector3(0, 0.6, 0))

func release(attacker: Node3D) -> void:
	if not links.has(attacker):
		return
	var target: Node3D = links[attacker].target
	if is_instance_valid(target):
		target.towed_by = null
	attacker.tow_target = null
	links.erase(attacker)
	last_result = "Tow released"

func tick(delta: float, reeling_city: Node3D = null) -> void:
	for attacker in links.keys():
		var link: Dictionary = links[attacker]
		var target: Node3D = link.target
		if not is_instance_valid(attacker) or not is_instance_valid(target):
			links.erase(attacker)
			continue
		if attacker.systems.defeated:
			release(attacker)
			continue
		var stats: Dictionary = attacker.systems.performance()
		if attacker == reeling_city and stats.ratio > 0:
			link.length = maxf(0.15, link.length - B.REEL_SPEED * stats.ratio * delta)
		var anchor := source_anchor(attacker)
		var target_anchor: Vector3 = target.to_global(link.target_anchor)
		var separation := target_anchor - anchor
		var carry: bool = target.world.city == target and (target.piloting() or target.world.player_on_city())
		var old_transform := target.global_transform
		if separation.length() > link.length:
			var next_transform := old_transform
			next_transform.origin += separation.normalized() * (link.length - separation.length())
			next_transform.origin.y = target.terrain_height(next_transform)
			if target.inside_yard(next_transform) and absf(next_transform.origin.y - old_transform.origin.y) <= B.MAX_STEP_HEIGHT and not target.blocked_by_geometry(next_transform):
				target.global_transform = next_transform
				# A defending pilot remains attached and can still shoot while towed.
				if carry:
					var rider: Transform3D = old_transform.affine_inverse() * target.world.player.global_transform
					target.world.player.global_transform = next_transform * rider
		var gut: StaticBody3D = attacker.systems.find_module(B.GUT)
		if gut == null or stats.ratio <= 0:
			continue
		var gut_bounds := gut.global_transform * AABB(Vector3(-1.5, 0, -1), Vector3(3, 2, 2))
		var contact := false
		for block in target.build_pieces:
			for mesh in block.get_children():
				if mesh is MeshInstance3D and gut_bounds.grow(0.2).intersects(mesh.global_transform * mesh.get_aabb()):
					contact = true
		if not contact:
			continue
		var rate: float = B.MODULES[B.GUT].rate * stats.ratio
		link.progress += rate * delta
		process_target(attacker, target, link)
		if links.has(attacker):
			links[attacker] = link

func process_target(attacker: Node3D, target: Node3D, link: Dictionary) -> void:
	# Consume one actual block at a time; no duplicated material payout on repeat.
	# The chassis is last so the defending crew remains active while processing.
	var candidate: StaticBody3D
	for block in target.build_pieces:
		if block.get_meta("block_id") != target.systems.graph.core_id:
			candidate = block
			break
	if candidate == null and not target.build_pieces.is_empty():
		candidate = target.build_pieces[0]
	if candidate == null:
		finish_capture(attacker, target)
		return
	processing_started.emit(target)
	var cost: float = target.systems.cost_of(candidate)
	if link.progress < cost:
		return
	link.progress -= cost
	attacker.systems.scrap += cost * B.SALVAGE_FRACTION
	attacker.systems.fuel += cost * B.SALVAGE_FUEL_PER_COST
	var id: int = candidate.get_meta("block_id")
	target.systems.remove_block(id)
	target.build_pieces.erase(candidate)
	candidate.queue_free()
	# The original contact may have been consumed. Reattach the rope to the
	# nearest surviving surface so reeling can continue feeding the processor.
	var source: Vector3 = target.to_local(source_anchor(attacker))
	var nearest := INF
	for block in target.build_pieces:
		for mesh in block.get_children():
			if mesh is MeshInstance3D:
				var bounds: AABB = block.transform * mesh.transform * mesh.get_aabb()
				var point := source.clamp(bounds.position, bounds.end)
				var distance := point.distance_squared_to(source)
				if distance < nearest:
					nearest = distance
					link.target_anchor = point
	if target.build_pieces.is_empty():
		finish_capture(attacker, target)

func finish_capture(attacker: Node3D, target: Node3D) -> void:
	target.systems.defeated = true
	for block in target.decoration:
		attacker.systems.scrap += B.cost(-1, block.dimensions.x * block.dimensions.y * block.dimensions.z, block.material_id) * B.SALVAGE_FRACTION
		block.queue_free()
	target.decoration.clear()
	target.stop_piloting()
	release(attacker)
	city_captured.emit(target)
	last_result = "City processed · owner retains blueprint and partial materials"
