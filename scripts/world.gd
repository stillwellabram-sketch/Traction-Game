extends Node3D

const Piece = preload("res://scripts/piece.gd")
const Player = preload("res://scripts/player.gd")
const NAMES = Piece.NAMES
const Materials = preload("res://scripts/material_library.gd")
const CustomBlock = preload("res://scripts/custom_block.gd")
const CustomTool = preload("res://scripts/custom_block_tool.gd")
const Palette = preload("res://scripts/material_palette.gd")
var load_player_profile := true
var profiles = preload("res://scripts/mechanics/blueprints.gd").new()
var cities: Array[Node3D] = []
var salvage: Node3D
var combat: Node3D
var mechanics_ui: CanvasLayer
var material_palette: CanvasLayer
var palette_requested := false
const Rules = preload("res://scripts/build_rules.gd")
const Grid = preload("res://scripts/placement_grid.gd")
var placement_grid: MeshInstance3D
var selected_span := 2.0
var selected_depth := 2.0
var structural_drag := false
var drag_start_requested := false
var drag_release_requested := false
var drag_anchor := Vector3.ZERO
var drag_pointer := Vector3.ZERO
var drag_size := Vector2.ZERO
var drag_quarter := 0
var grid_enabled := true
var detail_label: Label
const ChunkIndex = preload("res://scripts/mechanics/chunk_index.gd")
var chunks: Node3D
const City = preload("res://scripts/city_controller.gd")
var city: Node3D
const BuildState = preload("res://scripts/build_state.gd")
var selected_material := 0
var custom_blocks: Array[StaticBody3D] = []
var custom_tool: CanvasLayer
var material_label: Label
var help_label: Label
var walking_help := ""
var save_path := "user://construction.json"
var player: CharacterBody3D
var pieces: Array[StaticBody3D] = []
var preview: StaticBody3D
var selected := Piece.Kind.WHEEL
var view_quarter := 0
var undo_history: Array[Dictionary] = []
var pick_requested := false
var paint_requested := false
var painting := false
var brush_recorded := false
var brush_wait_release := false
var edit_requested := false
var create_custom_requested := false
var building := true
var valid := false
var candidate := Vector3.ZERO
var candidate_turns := 0
var target: StaticBody3D
var status: Label
var toolbar: Label
var notice: Label
var reason := ""
var place_requested := false
var remove_requested := false

func _ready() -> void:
	setup_input()
	setup_world()
	city = City.new()
	city.name = "City"
	city.world = self
	add_child(city)
	chunks = preload("res://scripts/mechanics/city_systems.gd").new()
	city.add_child(chunks)
	city.systems = chunks
	city.build_pieces = pieces
	city.decoration = custom_blocks
	placement_grid = Grid.new()
	city.add_child(placement_grid)
	player = Player.new()
	add_child(player)
	player.position = Vector3(0, 0.8, 7)
	setup_ui()
	notice.text = "Start with a wheel, tread or leg on the ground · M catalogue · then place a foundation on its top mount"
	refresh_preview()
	custom_tool = CustomTool.new()
	add_child(custom_tool)
	custom_tool.setup(self)
	material_palette = Palette.new()
	add_child(material_palette)
	material_palette.setup(self)
	mechanics_ui = preload("res://scripts/mechanics/mechanics_ui.gd").new()
	add_child(mechanics_ui)
	mechanics_ui.setup(self)
	cities.append(city)
	combat = preload("res://scripts/mechanics/combat.gd").new()
	add_child(combat)
	salvage = preload("res://scripts/mechanics/salvage.gd").new()
	add_child(salvage)
	salvage.processing_started.connect(profiles.protect)
	salvage.city_captured.connect(on_city_lost)
	register_city(city)
	if load_player_profile and profiles.load_profile(chunks.owner_id):
		var profile: Dictionary = profiles.profiles[chunks.owner_id]
		chunks.scrap = float(profile.scrap)
		chunks.fuel = float(profile.fuel)
		if profile.get("defeated", false):
			chunks.clear()
			for block in pieces:
				block.queue_free()
			pieces.clear()
			chunks.defeated = true
			profiles.losses[city.get_instance_id()] = true
			profiles.protected_cities[city.get_instance_id()] = true
			notice.text = "Blueprint and retained materials loaded · F10 rebuild"

func setup_input() -> void:
	var bindings := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "jump": KEY_SPACE, "sprint": KEY_CTRL, "edge_guard": KEY_SHIFT}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = bindings[action]
			InputMap.action_add_event(action, key)

func setup_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("496a91")
	sky_material.sky_horizon_color = Color("c2cbd0")
	sky_material.ground_bottom_color = Color("484940")
	sky_material.ground_horizon_color = Color("c2cbd0")
	sky_material.sun_angle_max = 3.0
	sky_material.sky_energy_multiplier = 0.6
	sky_material.ground_energy_multiplier = 0.4
	var sky := Sky.new()
	sky.sky_material = sky_material
	settings.background_mode = Environment.BG_SKY
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy = 0.35
	settings.fog_enabled = true
	settings.fog_light_color = Color("becbd2")
	settings.fog_density = 0.0007
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_color = Color("fff1dc")
	sun.light_energy = 0.75
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_enabled = true
	add_child(sun)
	add_child(preload("res://scripts/terrain.gd").new())

func setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var heading := Label.new()
	heading.text = "T R A C T I O N I S M   /   CONSTRUCTION YARD"
	heading.position = Vector2(28, 24)
	heading.add_theme_font_size_override("font_size", 23)
	root.add_child(heading)
	help_label = Label.new()
	help_label.text = "WASD  Move   ·   Shift  Edge-safe walk   ·   Ctrl  Sprint   ·   Space  Jump\nLook to rotate   ·   LMB  Place   ·   RMB  Remove   ·   MMB  Copy   ·   Z  Undo\nM Catalogue · 1–9 / 0 Helm / Wheel Select   ·   B  Build   ·   F5 / F9  Save / Load   ·   Esc  Mouse"
	help_label.position = Vector2(28, 62)
	help_label.add_theme_color_override("font_color", Color("e6ebde"))
	root.add_child(help_label)
	walking_help = help_label.text
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(6, 14)
	root.add_child(crosshair)
	status = Label.new()
	status.add_theme_color_override("font_outline_color", Color("15202b"))
	status.add_theme_constant_override("outline_size", 5)
	status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status.position = Vector2(-340, -105)
	status.size.x = 680
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status)
	toolbar = Label.new()
	toolbar.add_theme_color_override("font_outline_color", Color("15202b"))
	toolbar.add_theme_constant_override("outline_size", 5)
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toolbar.position = Vector2(-600, -68)
	toolbar.size = Vector2(1200, 60)
	toolbar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toolbar.add_theme_font_size_override("font_size", 16)
	root.add_child(toolbar)
	notice = Label.new()
	notice.position = Vector2(28, 150)
	root.add_child(notice)
	material_label = Label.new()
	material_label.position = Vector2(28, 180)
	root.add_child(material_label)
	detail_label = Label.new()
	detail_label.position = Vector2(28, 235)
	detail_label.add_theme_color_override("font_outline_color", Color("15202b"))
	detail_label.add_theme_constant_override("outline_size", 3)
	root.add_child(detail_label)

func _input(event: InputEvent) -> void:
	if structural_drag and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_structural_drag()
		get_viewport().set_input_as_handled()
		return
	if city.piloting() and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_E, KEY_ESCAPE]:
		city.stop_piloting()
		clear_build_requests()
		get_viewport().set_input_as_handled()

func clear_build_requests() -> void:
	cancel_structural_drag()
	place_requested = false
	remove_requested = false
	pick_requested = false
	palette_requested = false
	create_custom_requested = false
	edit_requested = false
	paint_requested = false

func _unhandled_input(event: InputEvent) -> void:
	if custom_tool.opened or material_palette.opened or mechanics_ui.opened:
		return
	if structural_drag and ((event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)):
		cancel_structural_drag()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if structural_drag or drag_start_requested:
			drag_release_requested = true
		return
	if handle_mechanics_input(event):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M and not city.piloting():
		mechanics_ui.open_menu()
		return
	if city.piloting():
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_F5:
				save_build()
			elif event.keycode == KEY_F9:
				load_build()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C and player.controls_active():
			create_custom_requested = true
		elif event.keycode == KEY_E and player.controls_active():
			edit_requested = true
		elif event.keycode == KEY_T and player.controls_active():
			palette_requested = true
		elif event.keycode == KEY_V and player.controls_active():
			painting = not painting
			brush_recorded = false
		elif event.keycode == KEY_P and player.controls_active():
			paint_requested = true
		elif event.keycode == KEY_F5:
			save_build()
		elif event.keycode == KEY_F9:
			load_build()
		elif event.keycode == KEY_B:
			building = not building
		elif event.keycode == KEY_Z and player.controls_active():
			undo_build()
		elif event.keycode == KEY_Q and player.controls_active() and preload("res://scripts/mechanics/balance.gd").is_wheel(selected):
			var wheels := [13, 18, 19, 20, 21]
			select_piece(wheels[(wheels.find(selected) + 1) % wheels.size()])
		elif event.keycode == KEY_Q and player.controls_active() and Piece.has_span(selected) and not structural_drag:
			var sizes := [2.0, 1.0, 4.0]
			selected_span = sizes[(sizes.find(selected_span) + 1) % sizes.size()]
			selected_depth = selected_span
			refresh_preview()
		elif event.keycode == KEY_G and player.controls_active():
			grid_enabled = not grid_enabled
		elif event.keycode == KEY_0:
			select_piece(Piece.Kind.HELM)
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			select_piece(event.keycode - KEY_1)
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		if painting:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				var body := aimed_body()
				if body in pieces or body in custom_blocks:
					selected_material = body.material_id
			elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				selected_material = posmod(selected_material + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1), Materials.NAMES.size())
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Piece.has_span(selected):
				drag_start_requested = true
			else:
				place_requested = true
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			remove_requested = true
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			pick_requested = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_piece(selected - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_piece(selected + 1)

func select_piece(index: int) -> void:
	cancel_structural_drag()
	selected = posmod(index, NAMES.size())
	building = true
	refresh_preview()

# Eight degrees of hysteresis avoids oscillating at a diagonal heading.
func orientation_for_view(yaw: float) -> int:
	var difference := wrapf(yaw - view_quarter * PI / 2, -PI, PI)
	if absf(difference) > PI / 4 + deg_to_rad(8):
		view_quarter = posmod(roundi(yaw / (PI / 2)), 4)
	return view_quarter

func capture_build() -> Dictionary:
	var records: Array = []
	for p in pieces:
		records.append({"kind": p.kind, "x": p.cell.x, "y": p.cell.y, "z": p.cell.z, "rotation": p.quarter, "material": p.material_id, "span": p.span, "depth": p.depth, "hp": chunks.health.get(p.get_meta("block_id"), 0), "enabled": chunks.enabled.get(p.get_meta("block_id"), true), "core": p.get_meta("block_id") == chunks.graph.core_id})
	var custom: Array = []
	for block in custom_blocks:
		var record: Dictionary = block.to_record()
		record["hp"] = chunks.health.get(block.get_meta("block_id"), 220)
		custom.append(record)
	return {"version": 6, "pieces": records, "custom_blocks": custom, "city": city.to_record(), "mechanics": {"fuel": chunks.fuel, "scrap": chunks.scrap, "defeated": chunks.defeated}}

func remember_build() -> void:
	undo_history.append(capture_build())
	if undo_history.size() > 20:
		undo_history.pop_front()

func restore_build(data: Dictionary) -> void:
	data = preload("res://scripts/mechanics/traction_layout.gd").migrate(data)
	var carry_player: bool = city.piloting() or player_on_city()
	var rider: Transform3D = city.global_transform.affine_inverse() * player.global_transform
	city.stop_piloting()
	city.restore(data.get("city", {}))
	if carry_player:
		player.global_transform = city.global_transform * rider
	salvage.release(city)
	if is_instance_valid(city.towed_by):
		salvage.release(city.towed_by)
	profiles.protected_cities.erase(city.get_instance_id())
	profiles.losses.erase(city.get_instance_id())
	chunks.clear()
	for body in pieces + custom_blocks:
		body.queue_free()
	pieces.clear()
	custom_blocks.clear()
	for entry in data.pieces:
		add_piece(int(entry.kind), Vector3(entry.x, entry.y, entry.z), int(entry.rotation), int(entry.get("material", 2 if entry.kind == 0 else 0)), float(entry.get("span", 4.0)), float(entry.get("depth", entry.get("span", 4.0))))
	for record in data.get("custom_blocks", []):
		add_custom_block(record)
		chunks.health[custom_blocks.back().get_meta("block_id")] = float(record.get("hp", 220))
	if int(data.version) < 5:
		prune_unsupported()
	else:
		for i in data.pieces.size():
			var id: int = pieces[i].get_meta("block_id")
			var entry: Dictionary = data.pieces[i]
			if entry.core:
				chunks.graph.core_id = id
			chunks.health[id] = float(entry.hp)
			chunks.enabled[id] = entry.enabled
		for id in chunks.blocks:
			if chunks.health[id] <= 0:
				chunks.graph.remove_block(id)
		chunks.update_structure_visuals(chunks.graph.recalculate(chunks.graph.nodes.keys()))
		for id in chunks.blocks:
			chunks.show_health(id)
		chunks.fuel = float(data.mechanics.fuel)
		chunks.scrap = float(data.mechanics.scrap)
		chunks.defeated = data.mechanics.defeated
		if chunks.defeated:
			profiles.losses[city.get_instance_id()] = true
	# Move above intersecting restored geometry only, including tall custom blocks.
	var safe_y := player.position.y
	var player_bounds := AABB(player.position + Vector3(-0.32, 0.04, -0.32), Vector3(0.64, 1.72, 0.64))
	for body in pieces + custom_blocks:
		for geometry in body.get_children():
			if geometry is MeshInstance3D:
				var bounds: AABB = geometry.global_transform * geometry.get_aabb()
				if bounds.intersects(player_bounds):
					safe_y = maxf(safe_y, bounds.end.y + 0.1)
	player.position.y = safe_y
	player.velocity = Vector3.ZERO

func undo_build() -> void:
	brush_recorded = false
	brush_wait_release = painting and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if undo_history.is_empty():
		notice.text = "Nothing to undo"
		return
	restore_build(undo_history.pop_back())
	notice.text = "Last construction edit undone"

func add_custom_block(record: Dictionary) -> void:
	var block := CustomBlock.new()
	block.configure(Vector3(record.position[0], record.position[1], record.position[2]), Vector3(record.size[0], record.size[1], record.size[2]), int(record.rotation), int(record.material))
	city.add_child(block)
	custom_blocks.append(block)
	chunks.add_decoration(block)

func player_on_city() -> bool:
	var feet := player.global_position
	var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.12, feet - Vector3.UP * 0.4, 5)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var body := ChunkIndex.resolve(hit)
	return body in pieces or body in custom_blocks

func body_inside_yard(body: Node3D) -> bool:
	for visual in body.get_children():
		if visual is MeshInstance3D:
			var bounds: AABB = visual.global_transform * visual.get_aabb()
			if bounds.position.x < -350 or bounds.end.x > 350 or bounds.position.z < -350 or bounds.end.z > 350:
				return false
	return true

func paint_body(body: StaticBody3D, material_id: int, record_undo := true) -> void:
	if not is_instance_valid(body) or (body not in pieces and body not in custom_blocks):
		return
	if body.material_id == material_id:
		return
	if record_undo:
		remember_build()
	if body in pieces:
		body.set_surface(material_id)
	else:
		body.configure(body.position, body.dimensions, body.quarter, material_id)

func apply_brush(body: StaticBody3D) -> void:
	if not is_instance_valid(body) or (body not in pieces and body not in custom_blocks) or body.material_id == selected_material:
		return
	if not brush_recorded:
		remember_build()
		brush_recorded = true
	paint_body(body, selected_material, false)

func aimed_body() -> StaticBody3D:
	var camera: Camera3D = player.camera
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 10, 5)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return ChunkIndex.resolve(hit)

func refresh_preview() -> void:
	if is_instance_valid(preview):
		preview.queue_free()
	preview = Piece.new()
	preview.setup(selected, Vector3.ZERO, 0, true, selected_material, selected_span, selected_depth)
	city.add_child(preview)

func _physics_process(delta: float) -> void:
	for active_city in cities:
		active_city.systems.tick(delta)
	salvage.tick(delta, city if player.controls_active() and Input.is_physical_key_pressed(KEY_J) else null)
	placement_grid.hide()
	detail_label.hide()
	if player.piloting and not city.piloting():
		city.stop_piloting()
	if city.piloting():
		help_label.text = "W / S  Forward / Reverse   ·   A / D  Steer   ·   Space  Brake\nMouse  Look   ·   E / Esc  Stop and leave helm   ·   F5  Save"
		material_label.hide()
		var active: bool = player.controls_active() and get_window().has_focus()
		if not player.require_mouse_capture:
			active = player.controls_active()
		city.drive(delta, Input.get_axis("move_back", "move_forward") if active else 0, Input.get_axis("move_right", "move_left") if active else 0, Input.is_action_pressed("jump") or not active)
		preview.hide()
		toolbar.hide()
		status.text = "HELM · %.1f m/s · W/S drive · A/D steer · Space brake · E exit" % absf(city.speed)
		if city.boundary_blocked:
			status.text = "Terrain obstacle / map edge · reverse or steer away · E exit"
		status.modulate = Color("8cffce")
		clear_build_requests()
		return
	help_label.text = walking_help
	material_label.show()
	if mechanics_ui.opened:
		preview.hide()
		toolbar.hide()
		status.text = "Choose a piece to return to building"
		clear_build_requests()
		return
	if material_palette.opened:
		preview.hide()
		toolbar.hide()
		status.text = "MATERIALS · Click a swatch or press 1–4 · Esc to cancel"
		status.modulate = Color.WHITE
		return
	if custom_tool.opened:
		preview.hide()
		toolbar.hide()
		status.text = "CUSTOM BLOCK · Use the inspector · Esc to cancel"
		status.modulate = Color.WHITE
		return
	toolbar.show()
	if building:
		detail_label.show()
		detail_label.text = "GRID %.3f m · Alt fine · G grid%s" % [Rules.grid(selected, Input.is_physical_key_pressed(KEY_ALT)), (" · Q size: %.3f m" % selected_span) if Piece.has_span(selected) else ""]
	update_candidate()
	if drag_start_requested:
		drag_start_requested = false
		begin_structural_drag()
	if drag_release_requested:
		drag_release_requested = false
		place_requested = structural_drag
	if player.controls_active():
		if palette_requested:
			material_palette.open_palette()
		elif create_custom_requested:
			custom_tool.open_block()
		elif edit_requested:
			var body := aimed_body()
			if body in pieces and body.kind == Piece.Kind.HELM:
				city.start_piloting(body)
			elif body in pieces and body.kind == Piece.Kind.FOUNDATION:
				board_foundation(body)
			elif body in custom_blocks:
				custom_tool.open_block(body)
			else:
				notice.text = "Aim at a helm (3 m) or custom block, then press E"
		elif paint_requested:
			var body := aimed_body()
			paint_body(body, selected_material)
	palette_requested = false
	create_custom_requested = false
	edit_requested = false
	paint_requested = false
	if painting:
		preview.hide()
		placement_grid.hide()
		detail_label.hide()
		toolbar.hide()
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not player.controls_active():
			brush_recorded = false
			brush_wait_release = false
		elif not brush_wait_release and not material_palette.opened and not custom_tool.opened:
			apply_brush(aimed_body())
		help_label.text = "WASD Move · Shift Edge-safe walk · Space Jump\nV Return to building · T Choose finish · Z Undo stroke"
		material_label.text = "PAINT · %s · Wheel changes finish · T palette" % Materials.NAMES[selected_material]
		status.text = "Hold LMB · Paint pieces   |   RMB · Sample   |   Z · Undo stroke   |   V · Exit paint"
		status.modulate = Color("8cffce")
		clear_build_requests()
		return
	if building and player.controls_active() and not city.piloting():
		if pick_requested and is_instance_valid(target):
			selected_material = target.material_id
			if Piece.has_span(target.kind):
				selected_span = target.span
				selected_depth = target.depth
			select_piece(target.kind)
			update_candidate()
		if place_requested and valid:
			var cost: float = chunks.cost_of(preview)
			if not chunks.defeated and chunks.scrap >= cost:
				remember_build()
				chunks.scrap -= cost
				if pieces.is_empty() and custom_blocks.is_empty() and preload("res://scripts/mechanics/balance.gd").is_traction(selected):
					city.position.y += candidate.y
					candidate.y = 0
				add_piece(selected, candidate, candidate_turns, selected_material, selected_span, selected_depth)
			else:
				notice.text = "Need %.0f scrap / rebuild a defeated city first" % cost
		if remove_requested and is_instance_valid(target) and target.get_meta("block_id") != chunks.graph.core_id:
			remember_build()
			# Do not leave unsupported floating pieces after removing a support.
			pieces.erase(target)
			chunks.remove_block(target.get_meta("block_id"))
			target.queue_free()
	if place_requested and structural_drag:
		cancel_structural_drag()
	place_requested = false
	remove_requested = false
	pick_requested = false
	var slots: PackedStringArray = []
	for i in NAMES.size():
		slots.append(("[ %d %s ]" if i == selected else "%d %s") % [(i + 1) % 10, NAMES[i]])
	toolbar.text = NAMES[selected] + " · M Build catalogue · 1–9 Structure · 0 Helm"
	material_label.text = "Material: %s  ·  T Palette · V Brush · P Paint\nC  New custom block  ·  E  Use helm / edit custom block" % Materials.NAMES[selected_material]
	if selected >= 10:
		toolbar.text = NAMES[selected] + " · M Build catalogue · Wheel select"
	status.text = reason if building else "EXPLORATION MODE  ·  Press B to build"
	status.modulate = Color("8cffce") if valid else Color("ffd0a2")
	var aimed := aimed_body()
	if not structural_drag and aimed in pieces and aimed.kind == Piece.Kind.FOUNDATION:
		status.text = "E · Board this foundation · Build from the deck"
	if aimed in pieces and aimed.kind == Piece.Kind.HELM:
		status.text = "E · Take the helm (within 3 m) · Front follows the helm arrow"

func update_candidate() -> void:
	valid = false
	target = null
	preview.visible = false
	if not building or not player.controls_active():
		cancel_structural_drag()
		reason = "Press Esc to capture the mouse"
		return
	if structural_drag:
		update_structural_drag()
		return
	var camera: Camera3D = player.camera
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 10, 5)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		reason = "Aim at terrain or a structure within 10 metres"
		return
	var hit_body := ChunkIndex.resolve(hit)
	if is_instance_valid(hit_body) and hit_body.has_meta("city_systems") and hit_body.get_meta("city_systems") != chunks:
		reason = "Cannot attach construction to another city"
		return
	if hit_body in custom_blocks:
		reason = "Custom blocks have no structural sockets · E to edit"
		return
	if hit_body in pieces:
		target = hit_body
	var point: Vector3 = city.to_local(hit.position)
	var normal: Vector3 = city.global_basis.inverse() * hit.normal
	var step := Rules.grid(selected, Input.is_physical_key_pressed(KEY_ALT))
	candidate_turns = orientation_for_view(player.global_rotation.y - city.global_rotation.y)
	var level := 0.6
	if target != null:
		level = target.cell.y
		if selected < 10 and selected not in [Piece.Kind.PILLAR, Piece.Kind.HELM] and (Piece.is_full_wall(target.kind) or target.kind in [4, 8]) and point.y > level + 1.5:
			level += 3.0
		elif selected < 10 and selected not in [Piece.Kind.PILLAR, Piece.Kind.HELM] and target.kind == Piece.Kind.HALF_WALL and point.y > level + 0.75:
			level += 1.5
	candidate = Vector3(snappedf(point.x, step), level, snappedf(point.z, step))
	var balance = preload("res://scripts/mechanics/balance.gd")
	if balance.is_traction(selected):
		var ground_point := city.to_global(candidate)
		ground_point.y = -INF
		var footprint := Rules.horizontal_rect(selected, candidate, candidate_turns, selected_span)
		for sample_x in [footprint.position.x, candidate.x, footprint.end.x]:
			for sample_z in [footprint.position.y, candidate.z, footprint.end.y]:
				var sample_point := city.to_global(Vector3(sample_x, 0, sample_z))
				ground_point.y = maxf(ground_point.y, get_node("Landscape").height_at(sample_point.x, sample_point.z))
		candidate.y = city.to_local(ground_point).y
	elif selected == Piece.Kind.FOUNDATION and target != null and balance.is_traction(target.kind):
		candidate = Vector3(target.cell.x, target.cell.y + balance.mount_height(target.kind) + 0.6, target.cell.z)
	elif selected == Piece.Kind.FOUNDATION and target == null:
		reason = "Place a wheel, tread or leg first, then aim at its top mount"
		return
	# Magnetize to the nearest deck perimeter when aiming near its edge.
	if target != null and target.kind in [0, 1]:
		var offset: Vector3 = point - target.cell
		var target_rect := Rules.horizontal_rect(target.kind, target.cell, target.quarter, target.span, target.depth)
		var half := Vector3(target_rect.size.x / 2, 0, target_rect.size.y / 2)
		var own_rect := Rules.horizontal_rect(selected, candidate, candidate_turns, selected_span, selected_depth)
		var own_half := Vector3(own_rect.size.x / 2, 0, own_rect.size.y / 2)
		var axis := 0 if absf(offset.x) / half.x > absf(offset.z) / half.z else 2
		var side := signf(offset[axis])
		var near_edge: bool = absf(offset[axis]) >= half[axis] - minf(0.35, half[axis] / 2)
		if Piece.is_edge(selected) and near_edge:
			candidate[axis] = target.cell[axis] + side * half[axis]
			var along := 2 if axis == 0 else 0
			if selected_span <= half[along] * 2:
				candidate[along] = clampf(candidate[along], target.cell[along] - half[along] + selected_span / 2, target.cell[along] + half[along] - selected_span / 2)
			candidate_turns = (1 if side > 0 else 3) if axis == 0 else (0 if side < 0 else 2)
		elif selected in [0, 1] and near_edge:
			candidate[axis] = target.cell[axis] + side * (half[axis] + own_half[axis])
	# Stack compact wall sections anywhere along a wider supporting wall.
	if target != null and (Piece.is_full_wall(target.kind) or target.kind == Piece.Kind.HALF_WALL) and Piece.is_edge(selected) and level > target.cell.y:
		candidate_turns = target.quarter
		var across := 2 if target.quarter % 2 == 0 else 0
		candidate[across] = target.cell[across]
		var along := 0 if across == 2 else 2
		if selected_span <= target.span:
			candidate[along] = clampf(candidate[along], target.cell[along] - (target.span - selected_span) / 2, target.cell[along] + (target.span - selected_span) / 2)
	# The top of stairs has a precise landing socket for each floor size.
	if target != null and target.kind == Piece.Kind.STAIRS and selected == Piece.Kind.FLOOR and level > target.cell.y:
		candidate = target.cell + target.basis * Vector3(0, 3, -(2 + selected_span / 2))
	validate_candidate(step)

func validate_candidate(step: float) -> void:
	if grid_enabled:
		placement_grid.show_at(candidate, step)
	detail_label.show()
	detail_label.text = "GRID %.3f m · Alt fine · G grid%s\nX %.3f   Y %.3f   Z %.3f" % [step, (" · Q size: %.3f m" % selected_span) if Piece.has_span(selected) else "", candidate.x, candidate.y, candidate.z]
	preview.position = candidate
	preview.rotation.y = candidate_turns * PI / 2
	preview.visible = true
	reason = "LMB to place  ·  Look to rotate  ·  RMB to dismantle"
	valid = supported(selected, candidate, candidate_turns, pieces, selected_span, selected_depth)
	if not valid:
		reason = "Running gear needs clear ground beneath the deck" if preload("res://scripts/mechanics/balance.gd").is_traction(selected) else "Needs support: foundations → walls / stairs → upper floors"
	for p in pieces:
		if same_slot(selected, candidate, candidate_turns, p, selected_span, selected_depth):
			valid = false
			reason = "This socket is already occupied"
	if city.to_global(candidate).distance_to(player.global_position) > 11:
		valid = false
		reason = "Outside construction range"
	if not body_inside_yard(preview):
		valid = false
		reason = "Keep the structure inside the yard"
	# Query the actual piece volumes so placement cannot trap the player.
	for geometry in preview.get_children():
		if geometry is MeshInstance3D:
			var shape := BoxShape3D.new()
			var bounds: AABB = geometry.get_aabb()
			shape.size = bounds.size * 0.98
			var overlap := PhysicsShapeQueryParameters3D.new()
			overlap.shape = shape
			overlap.transform = geometry.global_transform * Transform3D(Basis.IDENTITY, bounds.get_center())
			overlap.collision_mask = 6
			if not get_world_3d().direct_space_state.intersect_shape(overlap, 1).is_empty():
				valid = false
				reason = "Placement intersects you or a custom block"
	var cost: float = chunks.cost_of(preview)
	if chunks.scrap < cost:
		valid = false
		reason = "Need %.0f scrap" % cost
	if Piece.has_span(selected):
		detail_label.text += ("\n%.3f m long · %.0f scrap" % [selected_span, cost]) if Piece.is_edge(selected) else ("\n%.3f × %.3f m · %.0f scrap" % [selected_span, selected_depth, cost])
		if valid:
			reason = "Release LMB to build · RMB / Esc cancel" if structural_drag else "Hold LMB and look to stretch · Release to build"
	preview.tint(valid)

func same_slot(k: int, pos: Vector3, rotation_quarters: int, other: StaticBody3D, span := 4.0, depth := -1.0) -> bool:
	return Rules.occupied(k, pos, rotation_quarters, span, other, depth)

func supported(k: int, pos: Vector3, rotation_quarters: int, pool: Array[StaticBody3D] = pieces, span := 4.0, depth := -1.0) -> bool:
	return Rules.supported(k, pos, rotation_quarters, span, pool, depth)

func prune_unsupported() -> void:
	var stable: Array[StaticBody3D] = []
	var changed := true
	while changed:
		changed = false
		for p in pieces:
			if p not in stable and supported(p.kind, p.cell, p.quarter, stable, p.span, p.depth):
				stable.append(p)
				changed = true
	for p in pieces.duplicate():
		if p not in stable:
			pieces.erase(p)
			p.queue_free()

func add_piece(k: int, pos: Vector3, rotation_quarters: int, material_id := -1, span := 4.0, depth := -1.0) -> void:
	var piece := Piece.new()
	piece.setup(k, pos, rotation_quarters, false, (2 if k == 0 else 0) if material_id < 0 else material_id, span, depth)
	city.add_child(piece)
	pieces.append(piece)
	chunks.add_block(piece)

func save_build() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		notice.text = "Could not save construction."
		return
	file.store_string(JSON.stringify(capture_build()))
	notice.text = "Construction saved · structural pieces, materials and custom blocks"

func load_build() -> void:
	if not FileAccess.file_exists(save_path):
		notice.text = "No saved construction yet. Press F5 to save."
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not BuildState.valid(data):
		notice.text = "Save file is invalid. Current construction was kept."
		return
	remember_build()
	restore_build(data)
	notice.text = "Construction restored · Z to undo load"

func handle_mechanics_input(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo or not player.controls_active():
		return false
	match event.keycode:
		KEY_F:
			if not player_on_city() and not city.piloting():
				notice.text = "Board your city to use its gun"
				return true
			undo_history.clear()
			var camera: Camera3D = player.camera
			var ray := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 180, 5)
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			combat.fire(city, hit.get("position", ray.to))
			notice.text = combat.last_result
		KEY_R:
			undo_history.clear()
			if is_instance_valid(city.tow_target):
				salvage.release(city)
			else:
				var camera: Camera3D = player.camera
				var ray := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 30, 5)
				var hit := get_world_3d().direct_space_state.intersect_ray(ray)
				var body := ChunkIndex.resolve(hit)
				if is_instance_valid(body) and body.has_meta("city_systems"):
					salvage.attach(city, body.get_meta("city_systems").get_parent(), hit.position)
			notice.text = salvage.last_result
		KEY_X:
			var body := aimed_body()
			if body in pieces and body.kind >= 10:
				var id: int = body.get_meta("block_id")
				chunks.enabled[id] = not chunks.enabled[id]
				notice.text = "%s · bus %s" % [NAMES[body.kind], "ON" if chunks.enabled[id] else "OFF"]
		KEY_H:
			undo_history.clear()
			var body := aimed_body()
			if body in pieces:
				notice.text = "Repaired" if chunks.repair(body.get_meta("block_id")) else "Cannot repair · check scrap / chassis"
		KEY_F6:
			if cities.size() == 1:
				var other := preload("res://scripts/mechanics/city_factory.gd").starter(self, "test_player", Vector3(22, 0, -22))
				cities.append(other)
				register_city(other)
				notice.text = "Test rival spawned northeast · F7 switches crew"
		KEY_F8:
			profiles.save_design(city)
			notice.text = profiles.last_result
		KEY_F10:
			if profiles.rebuild(city):
				undo_history.clear()
				player.position = boarding_spawn()
				player.velocity = Vector3.ZERO
			notice.text = profiles.last_result
		KEY_F7:
			if cities.size() > 1:
				switch_city(cities[(cities.find(city) + 1) % cities.size()])
		_:
			return false
	return true

func switch_city(next_city: Node3D) -> void:
	city.stop_piloting()
	city = next_city
	pieces = city.build_pieces
	custom_blocks = city.decoration
	chunks = city.systems
	placement_grid.reparent(city, false)
	refresh_preview()
	undo_history.clear()
	player.position = boarding_spawn()
	player.velocity = Vector3.ZERO
	player.rotation = city.rotation
	notice.text = "Controlling " + chunks.owner_id

func register_city(registered: Node3D) -> void:
	registered.systems.before_damage.connect(func():
		profiles.protect(registered)
		undo_history.clear())
	registered.systems.core_lost.connect(on_city_lost.bind(registered))

func on_city_lost(lost: Node3D) -> void:
	profiles.retain_after_loss(lost)
	lost.stop_piloting()
	undo_history.clear()
	notice.text = profiles.last_result

func rebuild_site(rebuilding: Node3D, blueprint: Dictionary) -> Variant:
	var extent := Vector2(4, 4)
	for record in blueprint.pieces:
		extent.x = maxf(extent.x, absf(record.x) + maxf(record.span, 4) / 2)
		extent.y = maxf(extent.y, absf(record.z) + maxf(record.get("depth", record.span), record.span) / 2)
	for record in blueprint.custom_blocks:
		extent.x = maxf(extent.x, absf(record.position[0]) + maxf(record.size[0], record.size[2]) / 2)
		extent.y = maxf(extent.y, absf(record.position[2]) + maxf(record.size[0], record.size[2]) / 2)
	for x in [0, 40, -40, 80, -80, 160, -160, 240, -240]:
		for z in [0, 40, -40, 80, -80, 160, -160, 240, -240]:
			var area := Rect2(Vector2(x, z) - extent - Vector2.ONE * 3, extent * 2 + Vector2.ONE * 6)
			var clear := true
			for other in cities:
				if other == rebuilding or other.build_pieces.is_empty():
					continue
				other.refresh_bounds()
				var bounds: AABB = other.global_transform * other.local_bounds
				if area.intersects(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))):
					clear = false
			if clear and area.position.x >= -350 and area.end.x <= 350 and area.position.y >= -350 and area.end.y <= 350:
				var height := -INF
				for sample_x in [area.position.x, float(x), area.end.x]:
					for sample_z in [area.position.y, float(z), area.end.y]:
						height = maxf(height, get_node("Landscape").height_at(sample_x, sample_z))
				return Vector3(x, height, z)
	return null

func board_foundation(deck: StaticBody3D) -> bool:
	if deck not in pieces or deck.kind != Piece.Kind.FOUNDATION or player.global_position.distance_to(deck.global_position) > 10:
		return false
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.8
	for offset in [Vector3.ZERO, Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5)]:
		var inset: float = maxf(0, minf(deck.span, deck.depth) / 2 - 0.34)
		var safe_offset: Vector3 = offset.limit_length(inset)
		var point := city.to_global(deck.cell + safe_offset + Vector3.UP * 0.04)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = point + Vector3.UP * 0.9
		query.collision_mask = 5
		if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			player.global_position = point
			player.velocity = Vector3.ZERO
			notice.text = "Boarded foundation"
			return true
	notice.text = "Clear some standing room on the deck first"
	return false

func boarding_spawn() -> Vector3:
	for block in city.build_pieces:
		if block.kind == Piece.Kind.HELM:
			return city.to_global(block.cell + Basis(Vector3.UP, block.quarter * PI / 2) * Vector3(0, 0.1, 1.5))
	for block in city.build_pieces:
		if block.kind == Piece.Kind.FOUNDATION:
			return city.to_global(block.cell + Vector3.UP * 0.1)
	return city.to_global(Vector3(0, 1, 4.7))

func drag_plane_point() -> Variant:
	var origin := city.to_local(player.camera.global_position)
	var direction: Vector3 = city.global_basis.inverse() * -player.camera.global_basis.z
	var normal := Basis(Vector3.UP, drag_quarter * PI / 2) * Vector3.BACK if Piece.is_edge(selected) else Vector3.UP
	var denominator := direction.dot(normal)
	if absf(denominator) < 0.02:
		return null
	var distance: float = (drag_anchor - origin).dot(normal) / denominator
	if distance < 0 or distance > 40:
		return null
	return origin + direction * distance

func begin_structural_drag() -> bool:
	if not valid or not Piece.has_span(selected):
		return false
	drag_anchor = candidate
	drag_quarter = candidate_turns
	var point: Variant = drag_plane_point()
	if point == null:
		return false
	drag_pointer = point
	drag_size = Vector2(selected_span, selected_depth)
	drag_quarter = candidate_turns
	structural_drag = true
	return true

func update_structural_drag() -> void:
	var point: Variant = drag_plane_point()
	if point == null:
		valid = false
		reason = "Look toward the build plane to resize · RMB cancels"
		return
	var basis := Basis(Vector3.UP, drag_quarter * PI / 2)
	var delta: Vector3 = basis.inverse() * (point - drag_pointer)
	var step := Rules.grid(0, Input.is_physical_key_pressed(KEY_ALT))
	delta = Vector3(snappedf(delta.x, step), 0, 0 if Piece.is_edge(selected) else snappedf(delta.z, step))
	var width := drag_size.x + absf(delta.x)
	var length := width if Piece.is_edge(selected) else drag_size.y + absf(delta.z)
	if not is_equal_approx(width, selected_span) or not is_equal_approx(length, selected_depth):
		selected_span = width
		selected_depth = length
		refresh_preview()
	candidate = drag_anchor + basis * delta / 2
	candidate_turns = drag_quarter
	validate_candidate(step)

func cancel_structural_drag() -> void:
	drag_start_requested = false
	drag_release_requested = false
	if not structural_drag:
		return
	structural_drag = false
	selected_span = drag_size.x
	selected_depth = drag_size.y
	refresh_preview()
