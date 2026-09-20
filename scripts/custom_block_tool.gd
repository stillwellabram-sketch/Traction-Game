extends CanvasLayer

const Block = preload("res://scripts/custom_block.gd")
const Materials = preload("res://scripts/material_library.gd")
const Gizmo = preload("res://scripts/block_gizmo.gd")
const MIN_SIZE := 0.1
const MAX_SIZE := 24.0
var world: Node3D
var panel: PanelContainer
var fields: Array[SpinBox] = []
var material_index := 0
var rotation_quarters := 0
var message: Label
var title: Label
var apply_button: Button
var delete_button: Button
var ghost: StaticBody3D
var editing: StaticBody3D
var opened := false
var syncing := false
var can_apply := false
var transform_mode := 0
var gizmo: Control
var mode_buttons: Array[Button] = []
var material_buttons: Array[Button] = []
var orbiting := false
var camera_before: Transform3D
var last_dimensions := Vector3(4, 3, 0.25)
var surface_move := false

func setup(owner_world: Node3D) -> void:
	world = owner_world
	gizmo = Gizmo.new()
	gizmo.tool = self
	add_child(gizmo)
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.085, 0.105, 0.97)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-355, 150)
	panel.custom_minimum_size = Vector2(330, 0)
	add_child(panel)
	panel.size = Vector2(340, maxf(320, get_viewport().get_visible_rect().size.y - 174))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 20)
	content.add_child(title)
	var description := Label.new()
	description.text = "Drag colored handles · Shift: fine snap\nRMB drag: orbit · R: rotate · Enter: apply"
	content.add_child(description)
	var modes := HBoxContainer.new()
	content.add_child(modes)
	for i in 2:
		var button := Button.new()
		button.text = ["Move [G]", "Resize [F]"][i]
		button.toggle_mode = true
		button.button_pressed = i == 0
		button.pressed.connect(set_mode.bind(i))
		modes.add_child(button)
		mode_buttons.append(button)
	var surface := Button.new()
	surface.text = "Click surface"
	surface.pressed.connect(func(): surface_move = true)
	modes.add_child(surface)
	var presets := HBoxContainer.new()
	content.add_child(presets)
	var sizes := [Vector3(4, 3, 0.25), Vector3(4, 0.25, 4), Vector3(0.25, 3, 0.25), Vector3.ONE]
	for i in 4:
		var button := Button.new()
		button.text = ["Wall", "Floor", "Beam", "Cube"][i]
		button.pressed.connect(set_dimensions.bind(sizes[i]))
		presets.add_child(button)
	var precision := CheckButton.new()
	precision.text = "Exact position / dimensions"
	content.add_child(precision)
	var numbers := VBoxContainer.new()
	content.add_child(numbers)
	numbers.hide()
	precision.toggled.connect(numbers.set_visible)
	for group in ["Move — city position", "Scale — local dimensions"]:
		var label := Label.new()
		label.text = group
		numbers.add_child(label)
		var row := HBoxContainer.new()
		numbers.add_child(row)
		for axis in ["X", "Y", "Z"]:
			var column := VBoxContainer.new()
			row.add_child(column)
			var axis_label := Label.new()
			axis_label.text = axis
			column.add_child(axis_label)
			var field := SpinBox.new()
			field.custom_minimum_size.x = 90
			field.min_value = MIN_SIZE if fields.size() >= 3 else -350
			field.max_value = MAX_SIZE if fields.size() >= 3 else 350
			field.allow_greater = fields.size() < 3
			field.allow_lesser = fields.size() < 3
			field.step = 0.05 if fields.size() >= 3 else 0.025
			field.value_changed.connect(_field_changed)
			column.add_child(field)
			fields.append(field)
	fields[1].min_value = 0
	var rotation_label := Label.new()
	rotation_label.text = "Material · click a swatch"
	content.add_child(rotation_label)
	var swatches := GridContainer.new()
	swatches.columns = 2
	content.add_child(swatches)
	for i in Materials.NAMES.size():
		var button := Button.new()
		button.text = Materials.NAMES[i]
		button.icon = Materials.get_material(i).albedo_texture
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 38)
		button.custom_minimum_size = Vector2(140, 46)
		button.pressed.connect(choose_material.bind(i))
		swatches.add_child(button)
		material_buttons.append(button)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var rotate := Button.new()
	rotate.text = "Rotate 90° [R]"
	rotate.pressed.connect(rotate_block)
	actions.add_child(rotate)
	var duplicate_button := Button.new()
	duplicate_button.text = "Duplicate"
	duplicate_button.pressed.connect(duplicate_block)
	actions.add_child(duplicate_button)
	message = Label.new()
	message.custom_minimum_size.x = 290
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message)
	var buttons := HBoxContainer.new()
	content.add_child(buttons)
	apply_button = Button.new()
	apply_button.pressed.connect(commit)
	buttons.add_child(apply_button)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.pressed.connect(delete_current)
	buttons.add_child(delete_button)
	panel.hide()

func set_mode(value: int) -> void:
	transform_mode = value
	gizmo.end_drag()
	for i in mode_buttons.size():
		mode_buttons[i].button_pressed = i == value

func set_dimensions(value: Vector3) -> void:
	gizmo.end_drag()
	syncing = true
	for i in 3:
		fields[i + 3].value = value[i]
	syncing = false
	update_preview()

func choose_material(index: int) -> void:
	material_index = index
	world.selected_material = index
	update_preview()

func rotate_block() -> void:
	gizmo.end_drag()
	rotation_quarters = posmod(rotation_quarters + 1, 4)
	update_preview()

func duplicate_block() -> void:
	gizmo.end_drag()
	if is_instance_valid(editing):
		editing.visual.show()
	editing = null
	title.text = "DUPLICATE CUSTOM BLOCK"
	apply_button.text = "Place"
	delete_button.hide()
	var offset: Vector3 = ghost.basis.x * (ghost.dimensions.x + 0.25)
	syncing = true
	for i in 3:
		fields[i].value += offset[i]
	syncing = false
	update_preview()

func apply_drag(axis: int, amount: float, initial_position: Vector3, initial_size: Vector3, world_axis: Vector3) -> void:
	var position := initial_position
	var size := initial_size
	var local_axis: Vector3 = world.city.global_basis.inverse() * world_axis
	if transform_mode == 0:
		position += local_axis * amount
	else:
		size[axis] = clampf(initial_size[axis] + amount, MIN_SIZE, MAX_SIZE)
		# Resize away from the negative face; the opposite face stays anchored.
		if axis != 1:
			position += local_axis * (size[axis] - initial_size[axis]) / 2
	syncing = true
	for i in 3:
		fields[i].value = position[i]
		fields[i + 3].value = size[i]
	syncing = false
	update_preview()

func move_to_surface(screen_position: Vector2) -> void:
	var camera: Camera3D = world.player.camera
	var start := camera.project_ray_origin(screen_position)
	var ray := PhysicsRayQueryParameters3D.create(start, start + camera.project_ray_normal(screen_position) * 24, 5)
	if is_instance_valid(editing):
		ray.exclude = [editing.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return
	var position: Vector3 = world.city.to_local(hit.position)
	var normal: Vector3 = world.city.global_basis.inverse() * hit.normal
	# Place outside vertical surfaces instead of halfway through them.
	var extent: Vector3 = ghost.basis * (ghost.dimensions / 2)
	if absf(normal.y) < 0.5:
		position += normal * extent.abs().dot(normal.abs())
	for axis in 3:
		if absf(normal[axis]) < 0.5:
			position[axis] = snappedf(position[axis], 0.25)
		else:
			position[axis] = (ceilf(position[axis] / 0.025) if normal[axis] > 0 else floorf(position[axis] / 0.025)) * 0.025
	syncing = true
	for i in 3:
		fields[i].value = position[i]
	syncing = false
	surface_move = false
	update_preview()

func _input(event: InputEvent) -> void:
	if not opened:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		gizmo.end_drag()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		orbiting = false
	if event is InputEventMouseMotion and gizmo.dragging >= 0:
		gizmo.drag_to(event.position, event.shift_pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and orbiting:
		var camera: Camera3D = world.player.camera
		var centre: Vector3 = ghost.global_position + Vector3.UP * ghost.dimensions.y / 2
		var offset := camera.global_position - centre
		var radius := maxf(offset.length(), 1)
		var yaw: float = atan2(offset.x, offset.z) - event.relative.x * 0.006
		var pitch: float = clampf(asin(offset.y / radius) + event.relative.y * 0.006, -1.3, 1.3)
		camera.global_position = centre + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * radius
		camera.look_at(centre)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif not get_viewport().gui_get_focus_owner() is LineEdit:
			match event.keycode:
				KEY_G: set_mode(0)
				KEY_F: set_mode(1)
				KEY_R: rotate_block()
				KEY_ENTER: commit()
				_: return
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not opened:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if surface_move:
				move_to_surface(event.position)
			else:
				gizmo.begin_drag(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = true
		get_viewport().set_input_as_handled()

func open_block(block: StaticBody3D = null) -> void:
	if opened:
		return
	editing = block
	camera_before = world.player.camera.transform
	opened = true
	set_mode(0)
	surface_move = false
	world.player.input_locked = true
	world.player.velocity.x = 0
	world.player.velocity.z = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.preview.hide()
	var location: Vector3 = world.city.to_local(world.player.global_position - world.player.global_basis.z * 4)
	location.y = maxf(0, location.y)
	var size := last_dimensions
	var turns: int = world.orientation_for_view(world.player.global_rotation.y - world.city.global_rotation.y)
	var finish: int = world.selected_material
	if is_instance_valid(editing):
		location = editing.position
		size = editing.dimensions
		turns = editing.quarter
		finish = editing.material_id
	else:
		var camera: Camera3D = world.player.camera
		var ray := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 10, 5)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			location = world.city.to_local(hit.position).snapped(Vector3.ONE * 0.1)
			location.y = maxf(location.y, 0)
	syncing = true
	for i in 3:
		fields[i].value = location[i]
		fields[i + 3].value = size[i]
	rotation_quarters = turns
	material_index = finish
	syncing = false
	ghost = Block.new()
	world.city.add_child(ghost)
	if is_instance_valid(editing):
		editing.visual.hide()
	title.text = "EDIT CUSTOM BLOCK" if is_instance_valid(editing) else "NEW CUSTOM BLOCK"
	apply_button.text = "Apply" if is_instance_valid(editing) else "Place"
	delete_button.visible = is_instance_valid(editing)
	panel.show()
	update_preview()

func _field_changed(_value: float) -> void:
	if not syncing:
		update_preview()

func update_preview() -> void:
	if not is_instance_valid(ghost):
		return
	ghost.configure(Vector3(fields[0].value, fields[1].value, fields[2].value), Vector3(fields[3].value, fields[4].value, fields[5].value), rotation_quarters, material_index, true)
	for i in material_buttons.size():
		material_buttons[i].add_theme_color_override("font_color", Color("91e6bf") if i == material_index else Color.WHITE)

func validate_preview() -> bool:
	var half: Vector3 = ghost.dimensions / 2
	if ghost.quarter % 2 == 1:
		half = Vector3(half.z, half.y, half.x)
	if not world.body_inside_yard(ghost):
		message.text = "Keep the block inside the yard after the city's movement."
		return false
	if ghost.global_position.distance_to(world.player.global_position) > 24:
		message.text = "Move closer: custom editing range is 24 m."
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ghost.collider.shape
	query.transform = ghost.collider.global_transform
	query.collision_mask = 2
	if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		message.text = "This block would intersect you. Move or resize it."
		return false
	message.text = "Click a surface in the world." if surface_move else "Ready · 0.25 m snap / Shift 0.05 m · No structural support"
	return true

func _physics_process(_delta: float) -> void:
	if opened and is_instance_valid(ghost):
		can_apply = validate_preview()
		apply_button.disabled = not can_apply
		ghost.tint(can_apply)

func commit() -> void:
	if not opened:
		return
	# Signals can fire between physics frames; validate the current values again.
	if not validate_preview():
		return
	var cost: float = world.chunks.Balance.cost(-1, ghost.dimensions.x * ghost.dimensions.y * ghost.dimensions.z, ghost.material_id)
	if is_instance_valid(editing):
		cost = maxf(0, cost - world.chunks.Balance.cost(-1, editing.dimensions.x * editing.dimensions.y * editing.dimensions.z, editing.material_id))
	if world.chunks.defeated or world.chunks.scrap < cost:
		message.text = "Need %.0f scrap / rebuild your chassis first" % cost
		return
	world.remember_build()
	world.chunks.scrap -= cost
	last_dimensions = ghost.dimensions
	if is_instance_valid(editing):
		editing.configure(ghost.position, ghost.dimensions, ghost.quarter, ghost.material_id)
	else:
		world.add_custom_block(ghost.to_record())
	world.notice.text = "Custom block saved · E to edit · Z to undo"
	close()

func delete_current() -> void:
	if not is_instance_valid(editing):
		return
	world.remember_build()
	world.custom_blocks.erase(editing)
	editing.queue_free()
	close()

func close() -> void:
	gizmo.end_drag()
	orbiting = false
	world.player.camera.transform = camera_before
	if is_instance_valid(editing):
		editing.visual.show()
	if is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	editing = null
	opened = false
	panel.hide()
	world.player.input_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
