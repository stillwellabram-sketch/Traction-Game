extends Node3D
const B = preload("res://scripts/mechanics/balance.gd")
const Chunks = preload("res://scripts/mechanics/chunk_index.gd")
var last_result := ""

func fire(shooter: Node3D, aim_point: Vector3) -> Dictionary:
	var systems = shooter.systems
	if not aim_point.is_finite() or systems.defeated:
		return {}
	var gun: StaticBody3D = systems.find_module(B.GUN)
	if gun == null:
		last_result = "No operational gun connected to chassis"
		return {}
	if systems.cooldown > 0:
		return {}
	var stats: Dictionary = systems.performance()
	if stats.ratio < B.WEAPON_MIN_POWER or systems.fuel < B.SHOT_FUEL:
		last_result = "Gun locked out · insufficient power or fuel"
		return {}
	var muzzle := gun.to_global(Vector3(0, 0.95, -1.25))
	var direction := (aim_point - muzzle).normalized()
	if direction.length_squared() < 0.5:
		return {}
	systems.cooldown = B.SHOT_INTERVAL
	systems.fuel -= B.SHOT_FUEL
	var endpoint := muzzle + direction * B.SHOT_RANGE
	var query := PhysicsRayQueryParameters3D.create(muzzle, endpoint, 5)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		endpoint = hit.position
	tracer(muzzle, endpoint)
	var body := Chunks.resolve(hit)
	if not is_instance_valid(body) or not body.has_meta("city_systems"):
		last_result = "Shot hit terrain" if not hit.is_empty() else "Shot missed"
		return hit
	var target = body.get_meta("city_systems")
	if target == systems:
		last_result = "Shot blocked by your city"
		return hit
	var vulnerability := B.TOW_DAMAGE_MULTIPLIER if is_instance_valid(target.get_parent().tow_target) else 1.0
	var applied: float = target.damage(body.get_meta("block_id"), B.SHOT_DAMAGE * vulnerability)
	last_result = "%s hit · %.0f damage" % ["CUSTOM BLOCK" if body.kind < 0 else body.NAMES[body.kind], applied]
	hit["block"] = body
	hit["damage"] = applied
	return hit

func tracer(start: Vector3, finish: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(finish)
	mesh.surface_end()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ffdd92")
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	get_tree().create_timer(0.12).timeout.connect(visual.queue_free)
