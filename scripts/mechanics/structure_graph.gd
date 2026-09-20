extends RefCounted

# Event-driven spatial hash + undirected load paths. Only components touching an
# edit are traversed. A severed bridge may require visiting a large component;
# unrelated disconnected regions are never scanned, and ticks do no graph work.
const CELL := 8.0
const CONTACT := 0.045
var nodes: Dictionary = {}
var buckets: Dictionary = {}
var links: Dictionary = {}
var supported: Dictionary = {}
var core_id := -1
var last_visited := 0

func keys_for(bounds: AABB) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var a := Vector3i(floori(bounds.position.x / CELL), floori(bounds.position.y / CELL), floori(bounds.position.z / CELL))
	var b := Vector3i(floori(bounds.end.x / CELL), floori(bounds.end.y / CELL), floori(bounds.end.z / CELL))
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				result.append(Vector3i(x, y, z))
	return result

static func touching(a: AABB, b: AABB) -> bool:
	if not a.grow(CONTACT).intersects(b):
		return false
	var substantial := 0
	for axis in 3:
		if minf(a.end[axis], b.end[axis]) - maxf(a.position[axis], b.position[axis]) > CONTACT:
			substantial += 1
	return substantial >= 2 # Edge/corner-only contact cannot carry a city.

func connected(a: Array, b: Array) -> bool:
	for box_a in a:
		for box_b in b:
			if touching(box_a, box_b):
				return true
	return false

func add_block(id: int, volumes: Array, is_core := false) -> Array:
	if nodes.has(id):
		remove_block(id)
	var keys: Dictionary = {}
	var candidates: Dictionary = {}
	for box in volumes:
		for key in keys_for(box.grow(CONTACT)):
			keys[key] = true
			for neighbor in buckets.get(key, {}):
				candidates[neighbor] = true
	nodes[id] = {"boxes": volumes, "keys": keys.keys()}
	links[id] = {}
	for neighbor in candidates:
		if connected(volumes, nodes[neighbor].boxes):
			links[id][neighbor] = true
			links[neighbor][id] = true
	for key in keys:
		if not buckets.has(key):
			buckets[key] = {}
		buckets[key][id] = true
	if is_core:
		core_id = id
	# New blocks cannot disconnect an existing supported region. Propagate only
	# through newly attached islands, stopping at already supported vertices.
	last_visited = 0
	var reaches := id == core_id
	for neighbor in links[id]:
		reaches = reaches or supported.get(neighbor, false)
	if not reaches:
		supported[id] = false
		return []
	var changed: Array = [id]
	supported[id] = true
	var cursor := 0
	while cursor < changed.size():
		var current: int = changed[cursor]
		cursor += 1
		for neighbor in links[current]:
			if not supported.get(neighbor, false):
				supported[neighbor] = true
				changed.append(neighbor)
	last_visited = changed.size()
	return changed

func remove_block(id: int) -> Array:
	if not nodes.has(id):
		return []
	var seeds: Array = links[id].keys()
	for neighbor in seeds:
		links[neighbor].erase(id)
	for key in nodes[id].keys:
		buckets[key].erase(id)
		if buckets[key].is_empty():
			buckets.erase(key)
	nodes.erase(id)
	links.erase(id)
	supported.erase(id)
	# Do not silently appoint a new chassis after the core is destroyed.
	return recalculate(seeds)

func recalculate(seeds: Array) -> Array:
	last_visited = 0
	var visited: Dictionary = {}
	var changed: Array = []
	for seed_id in seeds:
		if visited.has(seed_id) or not nodes.has(seed_id):
			continue
		var queue: Array = [seed_id]
		visited[seed_id] = true
		var cursor := 0
		var reaches_core := false
		while cursor < queue.size():
			var id: int = queue[cursor]
			cursor += 1
			reaches_core = reaches_core or id == core_id
			for neighbor in links[id]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		last_visited += queue.size()
		for id in queue:
			if supported.get(id, false) != reaches_core:
				changed.append(id)
			supported[id] = reaches_core
	return changed
