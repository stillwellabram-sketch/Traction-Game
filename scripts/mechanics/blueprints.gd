extends RefCounted
const B = preload("res://scripts/mechanics/balance.gd")
const Piece = preload("res://scripts/piece.gd")
const Custom = preload("res://scripts/custom_block.gd")
const State = preload("res://scripts/build_state.gd")
var directory := "user://player_blueprints"
var profiles: Dictionary = {}
var protected_cities: Dictionary = {}
var losses: Dictionary = {}
var last_result := ""

func design(city: Node3D) -> Dictionary:
	var blocks: Array = []
	for block in city.build_pieces:
		var id: int = block.get_meta("block_id")
		blocks.append({"kind": block.kind, "x": block.cell.x, "y": block.cell.y, "z": block.cell.z,
			"rotation": block.quarter, "material": block.material_id, "span": block.span, "depth": block.depth,
			"core": id == city.systems.graph.core_id, "bus": "main", "enabled": city.systems.enabled.get(id, true)})
	var custom: Array = []
	for block in city.decoration:
		custom.append(block.to_record())
	return {"version": 4, "layout": "ground_traction", "pieces": blocks, "custom_blocks": custom, "city": {"x": 0, "z": 0, "yaw": 0}}

func valid_design(data: Variant) -> bool:
	if not State.valid(data) or data.pieces.is_empty():
		return false
	var cores := 0
	for block in data.pieces:
		if not block.get("core") is bool or not block.get("enabled") is bool or block.get("bus") != "main":
			return false
		if block.core:
			if block.kind != 0:
				return false
			cores += 1
	return cores == 1

func save_design(city: Node3D) -> bool:
	var blueprint := design(city)
	if not valid_design(blueprint):
		last_result = "Cannot save blueprint without a chassis"
		return false
	var owner: String = city.systems.owner_id
	profiles[owner] = {"version": 1, "owner": owner, "blueprint": blueprint,
		"scrap": city.systems.scrap, "fuel": city.systems.fuel, "defeated": city.systems.defeated}
	var saved := persist(owner)
	last_result = "Blueprint saved for " + owner if saved else "Blueprint kept in memory; disk save failed"
	return saved

func protect(city: Node3D) -> void:
	if not protected_cities.has(city.get_instance_id()):
		save_design(city)
		protected_cities[city.get_instance_id()] = true

func retain_after_loss(city: Node3D) -> void:
	var identity := city.get_instance_id()
	if losses.has(identity):
		return
	protect(city)
	losses[identity] = true
	city.systems.scrap = floorf(city.systems.scrap * B.LOSS_RETENTION)
	city.systems.fuel *= B.LOSS_RETENTION
	city.systems.defeated = true
	var owner: String = city.systems.owner_id
	if profiles.has(owner):
		profiles[owner].defeated = true
		profiles[owner].scrap = city.systems.scrap
		profiles[owner].fuel = city.systems.fuel
		persist(owner)
	last_result = "Defeated · blueprint retained · %.0f%% materials kept" % (B.LOSS_RETENTION * 100)

func path_for(owner: String) -> String:
	return directory.path_join(owner.sha256_text() + ".json")

func persist(owner: String) -> bool:
	var path := ProjectSettings.globalize_path(path_for(owner))
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(profiles[owner]))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func load_profile(owner: String) -> bool:
	var path := path_for(owner)
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("version") != 1 or data.get("owner") != owner or not valid_design(data.get("blueprint")):
		return false
	if not data.get("defeated", false) is bool:
		return false
	for key in ["scrap", "fuel"]:
		if not State.number(data.get(key)) or data[key] < 0:
			return false
	data.blueprint = preload("res://scripts/mechanics/traction_layout.gd").migrate(data.blueprint)
	profiles[owner] = data
	return true

func design_cost(blueprint: Dictionary) -> float:
	var total := 0.0
	for record in blueprint.pieces:
		var block := Piece.new()
		block.setup(int(record.kind), Vector3.ZERO, 0, false, int(record.material), float(record.span), float(record.get("depth", record.span)))
		var volume := 0.0
		for child in block.get_children():
			if child is MeshInstance3D and not child.get_meta("detail_only", false):
				volume += child.get_aabb().get_volume()
		total += B.cost(block.kind, volume, block.material_id)
		block.free()
	for record in blueprint.custom_blocks:
		total += B.cost(-1, record.size[0] * record.size[1] * record.size[2], int(record.material))
	return total

func rebuild(city: Node3D) -> bool:
	var owner: String = city.systems.owner_id
	if not profiles.has(owner) and not load_profile(owner):
		last_result = "No blueprint saved for this player"
		return false
	if not city.systems.defeated and not city.build_pieces.is_empty():
		last_result = "Rebuild is available after defeat or capture"
		return false
	var blueprint: Dictionary = profiles[owner].blueprint
	if not valid_design(blueprint):
		last_result = "Invalid blueprint · live city kept"
		return false
	var cost := design_cost(blueprint)
	if city.systems.scrap < cost:
		last_result = "Need %.0f scrap to rebuild · have %.0f" % [cost, city.systems.scrap]
		return false
	# Resolve a clear rebuild site before spending any materials.
	var location: Variant = city.world.rebuild_site(city, blueprint)
	if location == null:
		last_result = "No clear rebuild site available"
		return false
	city.world.salvage.release(city)
	if is_instance_valid(city.towed_by):
		city.world.salvage.release(city.towed_by)
	city.stop_piloting()
	city.systems.scrap -= cost
	city.systems.clear()
	for block in city.build_pieces + city.decoration:
		block.queue_free()
	city.build_pieces.clear()
	city.decoration.clear()
	city.transform = Transform3D(Basis.IDENTITY, location)
	var ordered: Array = blueprint.pieces.duplicate(true)
	ordered.sort_custom(func(a, b): return a.core and not b.core)
	for record in ordered:
		var block := preload("res://scripts/mechanics/city_factory.gd").add_piece(city, int(record.kind), Vector3(record.x, record.y, record.z), int(record.rotation), int(record.material), float(record.span), float(record.get("depth", record.span)))
		city.systems.enabled[block.get_meta("block_id")] = record.enabled
	for record in blueprint.custom_blocks:
		var block := Custom.new()
		block.configure(Vector3(record.position[0], record.position[1], record.position[2]), Vector3(record.size[0], record.size[1], record.size[2]), int(record.rotation), int(record.material))
		city.add_child(block)
		city.decoration.append(block)
		city.systems.add_decoration(block)
	city.refresh_bounds()
	protected_cities.erase(city.get_instance_id())
	losses.erase(city.get_instance_id())
	profiles[owner].defeated = false
	profiles[owner].scrap = city.systems.scrap
	profiles[owner].fuel = city.systems.fuel
	persist(owner)
	last_result = "Blueprint rebuilt · %.0f scrap used" % cost
	return true
