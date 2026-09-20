extends RefCounted

const Piece = preload("res://scripts/piece.gd")
const Materials = preload("res://scripts/material_library.gd")

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return number(value) and value == int(value) and value >= minimum and value <= maximum

static func vector_data(value: Variant, minimum: float, maximum: float) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component in value:
		if not number(component) or component < minimum or component > maximum:
			return false
	return true

# Validate the complete document before changing the live world.
static func valid(data: Variant) -> bool:
	if not data is Dictionary or not integer_in(data.get("version"), 1, 6):
		return false
	if data.get("version") >= 3:
		var city: Variant = data.get("city")
		if not city is Dictionary:
			return false
		for key in ["x", "z", "yaw"]:
			if not number(city.get(key)):
				return false
		if not number(city.get("y", 0)):
			return false
	if not data.get("pieces") is Array:
		return false
	if data.version >= 5:
		var mechanics = data.get("mechanics")
		if not mechanics is Dictionary or not mechanics.get("defeated") is bool:
			return false
		for key in ["fuel", "scrap"]:
			if not number(mechanics.get(key)) or mechanics[key] < 0:
				return false
	var cores := 0
	for record in data.pieces:
		if not record is Dictionary:
			return false
		if not integer_in(record.get("kind"), 0, Piece.NAMES.size() - 1) or not integer_in(record.get("rotation"), 0, 3):
			return false
		var span: Variant = record.get("span", 4.0)
		if not number(span) or span < 1 or span > 720 or not is_equal_approx(span * 8, roundf(span * 8)):
			return false
		var depth: Variant = record.get("depth", span)
		if not number(depth) or depth < 1 or depth > 720 or not is_equal_approx(depth * 8, roundf(depth * 8)):
			return false
		if int(record.kind) not in [Piece.Kind.FOUNDATION, Piece.Kind.FLOOR] and depth != span:
			return false
		if not Piece.has_span(int(record.kind)) and span != 4:
			return false
		for field in ["x", "y", "z"]:
			if not number(record.get(field)):
				return false
		if not integer_in(record.get("material", 2 if record.kind == 0 else 0), 0, Materials.NAMES.size() - 1):
			return false
		if data.version >= 5:
			if not number(record.get("hp")) or record.hp < 0 or record.hp > preload("res://scripts/mechanics/balance.gd").max_health(int(record.kind)):
				return false
			if not record.get("core") is bool or not record.get("enabled") is bool:
				return false
			if record.core:
				if record.kind != 0:
					return false
				cores += 1
	if data.version >= 5 and cores != (1 if data.pieces.any(func(p): return p.kind == 0) else 0):
		return false
	var custom: Variant = data.get("custom_blocks", [])
	if not custom is Array:
		return false
	for record in custom:
		if not record is Dictionary:
			return false
		if not vector_data(record.get("position"), -INF, INF) or not vector_data(record.get("size"), 0.1, 24):
			return false
		if not number(record.get("hp", 220)) or record.get("hp", 220) < 0 or record.get("hp", 220) > 220:
			return false
		if record.position[1] < 0:
			return false
		if not integer_in(record.get("rotation"), 0, 3) or not integer_in(record.get("material"), 0, Materials.NAMES.size() - 1):
			return false

	return true
