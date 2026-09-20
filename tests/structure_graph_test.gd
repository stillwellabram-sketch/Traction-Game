extends SceneTree
const Graph = preload("res://scripts/mechanics/structure_graph.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1
func _initialize() -> void:
	var graph := Graph.new()
	for i in 5:
		graph.add_block(i, [AABB(Vector3(i, 0, 0), Vector3.ONE)], i == 0)
	graph.add_block(50, [AABB(Vector3(90, 0, 0), Vector3.ONE)])
	check(graph.supported[4] and not graph.supported[50], "Only chassis-connected blocks are supported")
	graph.remove_block(2)
	check(graph.supported[1] and not graph.supported[3] and not graph.supported[4], "Cut bridge flags severed region")
	check(graph.last_visited == 4, "Disconnected unrelated region is not traversed")
	graph.add_block(2, [AABB(Vector3(2, 0, 0), Vector3.ONE)])
	check(graph.supported[4], "Repair restores load path")
	graph.remove_block(0)
	check(not graph.supported[1] and not graph.supported[4], "No replacement root after chassis loss")
	check(not Graph.touching(AABB(Vector3.ZERO, Vector3.ONE), AABB(Vector3(1, 1, 0), Vector3.ONE)), "Corner/edge contact alone is not structural")
	print("Structure graph tests: %d failures" % failures)
	quit(1 if failures else 0)
