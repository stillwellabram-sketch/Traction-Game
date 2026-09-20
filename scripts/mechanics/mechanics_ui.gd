extends CanvasLayer
const B = preload("res://scripts/mechanics/balance.gd")
var world: Node3D
var panel: PanelContainer
var hud: Label
var opened := false
var timer := 0.0
var catalogue: VBoxContainer
var tabs: Array[Button] = []
var category := 0
const CATEGORIES = ["Structural", "Decoration", "Engineering"]
const ITEMS = [[0, 1, 2, 3, 4, 5, 6, 7, 8], [9, -1], [10, 11, 12, 13, 18, 19, 20, 21, 14, 15, 16, 17]]

func setup(owner_world: Node3D) -> void:
	world = owner_world
	layer = 7
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14212a")
	style.set_content_margin_all(18)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var content := VBoxContainer.new()
	panel.add_child(content)
	var title := Label.new()
	title.text = "BUILD CATALOGUE · Select a piece · M / Esc closes"
	content.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	content.add_child(row)
	var sidebar := VBoxContainer.new()
	row.add_child(sidebar)
	for index in CATEGORIES.size():
		var tab := Button.new()
		tab.text = CATEGORIES[index]
		tab.custom_minimum_size = Vector2(150, 48)
		tab.toggle_mode = true
		tab.pressed.connect(func(): show_category(index))
		sidebar.add_child(tab)
		tabs.append(tab)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	catalogue = VBoxContainer.new()
	catalogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalogue.add_theme_constant_override("separation", 8)
	scroll.add_child(catalogue)
	show_category(0)
	panel.hide()
	hud = Label.new()
	hud.position = Vector2(855, 18)
	hud.add_theme_font_size_override("font_size", 14)
	hud.add_theme_color_override("font_outline_color", Color("101820"))
	hud.add_theme_constant_override("outline_size", 5)
	add_child(hud)

func show_category(index: int) -> void:
	category = index
	for i in tabs.size():
		tabs[i].set_pressed_no_signal(i == category)
	for child in catalogue.get_children():
		catalogue.remove_child(child)
		child.queue_free()
	for kind in ITEMS[index]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(475, 66)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if B.MODULES.has(kind):
			var spec: Dictionary = B.MODULES[kind]
			var energy: String = "%d kW supply" % spec.power if spec.has("power") else "%d kW draw" % spec.draw
			button.text = "%s · %d scrap\n%s · %.1f t · %.1f × %.1f m" % [spec.name, spec.cost, energy, spec.mass, spec.size.x, spec.size.z]
		elif kind == -1:
			button.text = "CUSTOM BLOCK\nDecorative shapes · Move, scale and paint · No structural support"
		elif kind == 0:
			button.text = "FOUNDATION\nHold LMB and look to stretch · Release to build"
		elif kind == 9:
			button.text = "HELM\nSteer the city · Place on a deck · E to use"
		else:
			button.text = "%s\n%s" % [world.NAMES[kind], "Hold LMB to stretch · Alt for precision" if world.Piece.has_span(kind) else "0.25 m grid · Alt for 0.125 m precision"]
		button.pressed.connect(func(): choose_piece(kind))
		catalogue.add_child(button)

func choose_piece(kind: int) -> void:
	close()
	world.painting = false
	if kind == -1:
		world.create_custom_requested = true
	else:
		world.select_piece(kind)

func open_menu() -> void:
	opened = true
	world.player.input_locked = true
	world.clear_build_requests()
	world.preview.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.hide()
	panel.show()
	panel.reset_size()
	panel.position = (get_viewport().get_visible_rect().size - panel.size) / 2

func close() -> void:
	opened = false
	panel.hide()
	hud.show()
	world.player.input_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if opened and event is InputEventKey and event.pressed:
		if event.keycode in [KEY_M, KEY_ESCAPE]:
			close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_instance_valid(world):
		return
	timer -= delta
	if timer > 0:
		return
	timer = 0.2
	var stats: Dictionary = world.chunks.performance()
	hud.position.x = maxf(800, get_viewport().get_visible_rect().size.x - 405)
	hud.text = "%s · %d chunks\nMass %.1f t · Power %.0f / %.0f kW\nFuel %.1f · Scrap %.0f · Mobility %.0f%%\nM Build catalogue · X Switch aimed module\nF Fire gun · R Tow · J Reel · H Repair\nF6 Test rival · F7 Switch city\nF8 Save blueprint · F10 Rebuild blueprint" % [world.chunks.owner_id, world.chunks.chunks.size(), stats.mass, stats.supply, stats.demand, world.chunks.fuel, world.chunks.scrap, stats.mobility * 100]

	var body: StaticBody3D = world.aimed_body()
	if is_instance_valid(body) and body.has_meta("city_systems"):
		var systems = body.get_meta("city_systems")
		var id: int = body.get_meta("block_id")
		var label: String = "CUSTOM BLOCK" if body.kind < 0 else body.NAMES[body.kind]
		if id == systems.graph.core_id:
			label = "CHASSIS CORE"
		hud.text += "\n%s · %.0f / %.0f HP\n%s" % [label, systems.health.get(id, 0), B.max_health(body.kind), "Connected" if systems.graph.supported.get(id, false) else "Disconnected / decoration"]
	if world.chunks.defeated:
		hud.text += "\nDEFEATED · F10 rebuild saved blueprint"
	elif is_instance_valid(world.city.towed_by):
		hud.text += "\nBEING TOWED · your powered gun still works"
	elif is_instance_valid(world.city.tow_target):
		hud.text += "\nTOWING · extra mass / +35% incoming damage"
