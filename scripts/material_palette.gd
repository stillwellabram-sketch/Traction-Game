extends CanvasLayer

const Materials = preload("res://scripts/material_library.gd")
var world: Node3D
var panel: PanelContainer
var buttons: Array[Button] = []
var caption: Label
var opened := false
var paint_target: StaticBody3D

func setup(owner_world: Node3D) -> void:
	world = owner_world
	layer = 5
	panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17212b")
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	panel.add_child(content)
	caption = Label.new()
	content.add_child(caption)
	var row := GridContainer.new()
	row.columns = 2
	content.add_child(row)
	for i in Materials.NAMES.size():
		var button := Button.new()
		button.text = "%d  %s" % [i + 1, Materials.NAMES[i]]
		button.icon = Materials.get_material(i).albedo_texture
		button.add_theme_color_override("icon_normal_color", Materials.get_material(i).albedo_color)
		button.expand_icon = true
		button.tooltip_text = ["Brushed steel · reflective cool metal", "Timber · warm grain, matte finish", "Concrete · cool mineral surface", "Brick · small masonry courses"][i]
		button.add_theme_constant_override("icon_max_width", 80)
		button.custom_minimum_size = Vector2(240, 100)
		button.pressed.connect(choose.bind(i))
		row.add_child(button)
		buttons.append(button)
	panel.hide()

func open_palette() -> void:
	if opened:
		return
	paint_target = world.aimed_body()
	caption.text = "MATERIALS · Click or press 1–4 · Esc to cancel\n" + ("Paints the targeted piece and sets your active material" if paint_target in world.pieces or paint_target in world.custom_blocks else "Sets the material for your next pieces")
	if world.painting:
		caption.text = "PAINT BRUSH · Choose a finish · 1–4\nHold LMB to paint · RMB sample · Wheel change finish"
	opened = true
	world.brush_recorded = false
	world.player.input_locked = true
	world.player.velocity.x = 0
	world.player.velocity.z = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in buttons.size():
		buttons[i].add_theme_color_override("font_color", Color("91e6bf") if i == world.selected_material else Color.WHITE)
	panel.show()
	call_deferred("center_panel")

func center_panel() -> void:
	panel.reset_size()
	panel.position = (get_viewport().get_visible_rect().size - panel.size) / 2

func choose(index: int) -> void:
	if not opened:
		return
	world.selected_material = index
	# Selecting a swatch paints the piece aimed at when the palette opened.
	if not world.painting and is_instance_valid(paint_target) and (paint_target in world.pieces or paint_target in world.custom_blocks):
		world.paint_body(paint_target, index)
	close()

func _input(event: InputEvent) -> void:
	if opened and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_T:
			close()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			choose(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()

func close() -> void:
	world.brush_wait_release = world.painting
	opened = false
	paint_target = null
	panel.hide()
	world.player.input_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
