extends Control

const AXIS_COLORS := [Color("ff726c"), Color("82e49a"), Color("72b6ff")]
var tool: CanvasLayer
var handles: Array[Dictionary] = []
var dragging := -1
var start_mouse := Vector2.ZERO
var start_position := Vector3.ZERO
var start_size := Vector3.ONE
var drag_direction := Vector2.ZERO
var pixels_per_metre := 1.0
var drag_world_axis := Vector3.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	visible = tool.opened
	if visible:
		queue_redraw()

func _draw() -> void:
	handles.clear()
	if not tool.opened or not is_instance_valid(tool.ghost):
		return
	var block: StaticBody3D = tool.ghost
	var camera: Camera3D = tool.world.player.camera
	var centre: Vector3 = block.global_position + Vector3.UP * block.dimensions.y / 2
	if camera.is_position_behind(centre):
		return
	var corners: Array[Vector3] = []
	for x in [-0.5, 0.5]:
		for y in [0.0, 1.0]:
			for z in [-0.5, 0.5]:
				corners.append(block.global_transform * (Vector3(x, y, z) * block.dimensions))
	for edge in [[0,1], [0,2], [0,4], [1,3], [1,5], [2,3], [2,6], [3,7], [4,5], [4,6], [5,7], [6,7]]:
		if not camera.is_position_behind(corners[edge[0]]) and not camera.is_position_behind(corners[edge[1]]):
			draw_line(camera.unproject_position(corners[edge[0]]), camera.unproject_position(corners[edge[1]]), Color("d8f6ff"), 2, true)
	var origin := camera.unproject_position(centre)
	for axis in 3:
		var direction := Vector3.ZERO
		direction[axis] = 1
		if tool.transform_mode == 1:
			direction = block.global_basis * direction
		else:
			direction = tool.world.city.global_basis * direction
		var projected := camera.unproject_position(centre + direction) - origin
		var density := maxf(projected.length(), 12.0)
		var screen_axis := projected.normalized() if projected.length() > 8 else Vector2(0.7, 0.7)
		var endpoint := origin + screen_axis * (90 + axis * 12)
		handles.append({"point": endpoint, "direction": screen_axis, "density": density, "axis": direction})
		draw_line(origin, endpoint, AXIS_COLORS[axis], 4, true)
		if tool.transform_mode == 0:
			draw_circle(endpoint, 11, AXIS_COLORS[axis])
		else:
			draw_rect(Rect2(endpoint - Vector2.ONE * 10, Vector2.ONE * 20), AXIS_COLORS[axis])
		draw_string(ThemeDB.fallback_font, endpoint + Vector2(14, -9), ["X", "Y", "Z"][axis], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, AXIS_COLORS[axis])

func begin_drag(mouse: Vector2) -> bool:
	var nearest := 18.0
	var picked := -1
	for i in handles.size():
		var distance: float = mouse.distance_to(handles[i].point)
		if distance < nearest:
			nearest = distance
			picked = i
	if picked < 0:
		return false
	dragging = picked
	start_mouse = mouse
	start_position = tool.ghost.position
	start_size = tool.ghost.dimensions
	drag_direction = handles[picked].direction
	pixels_per_metre = handles[picked].density
	drag_world_axis = handles[picked].axis
	return true

func drag_to(mouse: Vector2, fine: bool) -> void:
	if dragging < 0:
		return
	var increment := 0.05 if fine else 0.25
	var amount := snappedf((mouse - start_mouse).dot(drag_direction) / pixels_per_metre, increment)
	tool.apply_drag(dragging, amount, start_position, start_size, drag_world_axis)

func end_drag() -> void:
	dragging = -1
