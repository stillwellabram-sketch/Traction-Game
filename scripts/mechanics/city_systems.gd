extends "res://scripts/mechanics/chunk_index.gd"
const Graph = preload("res://scripts/mechanics/structure_graph.gd")
var graph := Graph.new()
var blocks: Dictionary = {}
var unsupported_material: StandardMaterial3D

func add_block(block: StaticBody3D) -> int:
	var id := super.add_block(block)
	blocks[id] = block
	health[id] = Balance.max_health(block.kind)
	enabled[id] = true
	block.set_meta("city_systems", self)
	var volumes: Array = []
	for child in block.get_children():
		if child is MeshInstance3D and not child.get_meta("detail_only", false):
			volumes.append(block.transform * child.transform * child.get_aabb())
	var changed := graph.add_block(id, volumes, graph.core_id == -1 and block.kind == 0)
	changed.append(id)
	update_structure_visuals(changed)
	return id

func forget_block(id: int) -> void:
	blocks.erase(id)
	health.erase(id)
	enabled.erase(id)
	update_structure_visuals(graph.remove_block(id))

func update_structure_visuals(changed: Array) -> void:
	if unsupported_material == null:
		unsupported_material = StandardMaterial3D.new()
		unsupported_material.albedo_color = Color(1.0, 0.18, 0.05, 0.35)
		unsupported_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		unsupported_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for id in changed:
		if not blocks.has(id) or not is_instance_valid(blocks[id]):
			continue
		var active: bool = graph.supported.get(id, false)
		blocks[id].set_meta("supported", active)
		for child in blocks[id].get_children():
			if child is MeshInstance3D:
				child.material_overlay = null if active else unsupported_material

func clear() -> void:
	for chunk in decoration_chunks.values():
		chunk.collision_layer = 0
		chunk.queue_free()
	decoration_chunks.clear()
	decoration_membership.clear()
	super.clear()
	blocks.clear()
	health.clear()
	enabled.clear()
	defeated = false
	graph = Graph.new()

const Balance = preload("res://scripts/mechanics/balance.gd")
var fuel := Balance.INITIAL_FUEL
var scrap := Balance.INITIAL_SCRAP
var cargo_mass := 0.0
var health: Dictionary = {}
var enabled: Dictionary = {}
var stats: Dictionary = {}
var defeated := false
var owner_id := "local_player"
var cooldown := 0.0

func block_volume(block: StaticBody3D) -> float:
	var volume := 0.0
	for child in block.get_children():
		if child is MeshInstance3D and not child.get_meta("detail_only", false):
			volume += child.get_aabb().get_volume()
	return volume

func cost_of(block: StaticBody3D) -> float:
	return Balance.cost(block.kind, block_volume(block), block.material_id)

func records() -> Array:
	var result: Array = []
	for id in blocks:
		var block: StaticBody3D = blocks[id]
		result.append({"kind": block.kind, "mass": Balance.mass(block.kind, block_volume(block), block.material_id),
			"health": health.get(id, Balance.max_health(block.kind)) / Balance.max_health(block.kind),
			"connected": graph.supported.get(id, false), "enabled": enabled.get(id, true)})
	return result

func performance(roughness := 0.0, tow_mass := 0.0) -> Dictionary:
	stats = Balance.performance(records(), fuel, cargo_mass + scrap * Balance.SCRAP_MASS + fuel * Balance.FUEL_MASS, roughness, tow_mass)
	return stats

func tick(delta: float) -> void:
	cooldown = maxf(0, cooldown - delta)
	var current := performance()
	fuel = maxf(0, fuel - current.fuel_rate * delta)

func operational(id: int) -> bool:
	return not defeated and blocks.has(id) and graph.supported.get(id, false) and enabled.get(id, true) and health.get(id, 1.0) > 0

func find_module(kind: int) -> StaticBody3D:
	for id in blocks:
		if blocks[id].kind == kind and operational(id):
			return blocks[id]
	return null

func remove_block(id: int) -> void:
	if decoration_membership.has(id):
		var key: Vector3i = decoration_membership[id]
		decoration_chunks[key].remove_block(id)
		decoration_membership.erase(id)
		if decoration_chunks[key].members.is_empty():
			decoration_chunks[key].queue_free()
			decoration_chunks.erase(key)
	super.remove_block(id)
	forget_block(id)

signal before_damage
signal component_damaged(block: StaticBody3D, amount: float)
signal core_lost
var wreck_material: StandardMaterial3D

func damage(id: int, amount: float) -> float:
	if not blocks.has(id) or not is_finite(amount) or amount <= 0:
		return 0.0
	before_damage.emit()
	var before: float = health[id]
	health[id] = maxf(0, before - amount)
	var applied: float = before - health[id]
	if applied <= 0:
		return 0.0
	component_damaged.emit(blocks[id], applied)
	if health[id] == 0:
		var changed := graph.remove_block(id)
		changed.append(id)
		update_structure_visuals(changed)
		if id == graph.core_id:
			defeated = true
			core_lost.emit()
	show_health(id)
	return applied

func show_health(id: int) -> void:
	if not blocks.has(id):
		return
	var block: StaticBody3D = blocks[id]
	var ratio: float = health[id] / Balance.max_health(block.kind)
	for child in block.get_children():
		if child is MeshInstance3D:
			if ratio <= 0:
				if wreck_material == null:
					wreck_material = StandardMaterial3D.new()
					wreck_material.albedo_color = Color("252329")
					wreck_material.roughness = 1
				child.material_overlay = wreck_material
			elif ratio < 1:
				var scar := StandardMaterial3D.new()
				scar.albedo_color = Color(0.2, 0.06, 0.025, (1 - ratio) * 0.6)
				scar.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				child.material_overlay = scar
			elif graph.supported.get(id, false):
				child.material_overlay = null

func repair(id: int) -> bool:
	if defeated or not blocks.has(id):
		return false
	var block: StaticBody3D = blocks[id]
	var maximum := Balance.max_health(block.kind)
	var missing: float = maximum - health[id]
	var cost := ceilf(cost_of(block) * Balance.REPAIR_COST_FRACTION * missing / maximum)
	if cost <= 0 or scrap < cost:
		return false
	scrap -= cost
	health[id] = maximum
	if block.kind >= 0 and not graph.nodes.has(id):
		var volumes: Array = []
		for child in block.get_children():
			if child is MeshInstance3D and not child.get_meta("detail_only", false):
				volumes.append(block.transform * child.transform * child.get_aabb())
		update_structure_visuals(graph.add_block(id, volumes))
	show_health(id)
	return true

var decoration_chunks: Dictionary = {}
var decoration_membership: Dictionary = {}

func add_decoration(block: StaticBody3D) -> int:
	var id := next_id
	next_id += 1
	blocks[id] = block
	health[id] = Balance.max_health(-1)
	enabled[id] = true
	block.set_meta("block_id", id)
	block.set_meta("city_systems", self)
	update_decoration(block)
	block.tree_exiting.connect(remove_block.bind(id), CONNECT_ONE_SHOT)
	return id

func update_decoration(block: StaticBody3D) -> void:
	var id: int = block.get_meta("block_id")
	if decoration_membership.has(id):
		var old: Vector3i = decoration_membership[id]
		decoration_chunks[old].remove_block(id)
		if decoration_chunks[old].members.is_empty():
			decoration_chunks[old].queue_free()
			decoration_chunks.erase(old)
	var key := Chunk.key_for(block.position)
	if not decoration_chunks.has(key):
		var chunk := Chunk.new()
		chunk.collision_layer = 4 # Decorations remain excluded from load paths.
		add_child(chunk)
		decoration_chunks[key] = chunk
	decoration_membership[id] = key
	decoration_chunks[key].add_block(id, block)
