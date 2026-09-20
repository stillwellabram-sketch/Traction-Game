extends Node3D
const Chunk = preload("res://scripts/mechanics/city_chunk.gd")
var chunks: Dictionary = {}
var membership: Dictionary = {}
var next_id := 1

func add_block(block: StaticBody3D) -> int:
	var id := next_id
	next_id += 1
	var key := Chunk.key_for(block.position)
	if not chunks.has(key):
		var chunk := Chunk.new()
		chunk.key = key
		add_child(chunk)
		chunks[key] = chunk
	chunks[key].add_block(id, block)
	membership[id] = key
	block.set_meta("block_id", id)
	block.tree_exiting.connect(remove_block.bind(id), CONNECT_ONE_SHOT)
	return id

func remove_block(id: int) -> void:
	if not membership.has(id):
		return
	var key: Vector3i = membership[id]
	var chunk: AnimatableBody3D = chunks[key]
	chunk.remove_block(id)
	membership.erase(id)
	if chunk.members.is_empty():
		chunks.erase(key)
		chunk.queue_free()

func clear() -> void:
	for chunk in chunks.values():
		chunk.collision_layer = 0
		chunk.queue_free()
	chunks.clear()
	membership.clear()

static func resolve(hit: Dictionary) -> StaticBody3D:
	var collider = hit.get("collider")
	if collider is Chunk:
		return collider.resolve_shape(int(hit.get("shape", -1)))
	return collider as StaticBody3D
