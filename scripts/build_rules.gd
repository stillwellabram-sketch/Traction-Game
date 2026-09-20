extends RefCounted

const Piece = preload("res://scripts/piece.gd")
const B = preload("res://scripts/mechanics/balance.gd")
const EPS := 0.025

static func grid(_kind: int, fine := false) -> float:
	return 0.125 if fine else 0.25

static func horizontal_rect(kind: int, pos: Vector3, quarter: int, span: float, depth := -1.0) -> Rect2:
	var dimensions := Vector2(span, depth if kind in [0, 1] and depth > 0 else span)
	if Piece.is_edge(kind):
		dimensions = Vector2(span, 0.01)
	elif kind == Piece.Kind.PILLAR:
		dimensions = Vector2(0.65, 0.65)
	elif kind == Piece.Kind.HELM:
		dimensions = Vector2(1.0, 0.8)
	elif kind == Piece.Kind.STAIRS:
		dimensions = Vector2(3.6, 4.0)
	if kind >= 10:
		var size: Vector3 = preload("res://scripts/mechanics/balance.gd").MODULES[kind].size
		dimensions = Vector2(size.x, size.z)
	if quarter % 2 == 1:
		dimensions = Vector2(dimensions.y, dimensions.x)
	return Rect2(Vector2(pos.x, pos.z) - dimensions / 2, dimensions)

# Sweep all rectangle boundaries to prove the whole footprint is supported.
# This handles seams between differently sized tiles without allowing gaps.
static func covered(area: Rect2, supports: Array[Rect2]) -> bool:
	var cuts: Array[float] = [area.position.x, area.end.x]
	for rect in supports:
		if rect.intersects(area, true):
			cuts.append(clampf(rect.position.x, area.position.x, area.end.x))
			cuts.append(clampf(rect.end.x, area.position.x, area.end.x))
	cuts.sort()
	for i in cuts.size() - 1:
		if cuts[i + 1] - cuts[i] < 0.00001:
			continue
		var x := (cuts[i] + cuts[i + 1]) / 2
		var intervals: Array[Vector2] = []
		for rect in supports:
			if x >= rect.position.x and x <= rect.end.x:
				intervals.append(Vector2(rect.position.y, rect.end.y))
		intervals.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
		var reach := area.position.y
		for interval in intervals:
			if interval.x > reach + 0.00001:
				break
			reach = maxf(reach, interval.y)
		if reach < area.end.y - 0.00001:
			return false
	return true

static func supported(kind: int, pos: Vector3, quarter: int, span: float, pool: Array[StaticBody3D], depth := -1.0) -> bool:
	if B.is_traction(kind):
		return true # Ground height and clearance are checked against terrain in world.
	if kind == Piece.Kind.FOUNDATION:
		# Ground foundations remain readable for old saves / construction fixtures.
		# New interactive construction requires a mount or an existing deck edge.
		if is_equal_approx(pos.y, 0.6):
			return true
		var deck := horizontal_rect(kind, pos, quarter, span, depth)
		for p in pool:
			if B.is_traction(p.kind) and absf(pos.y - 0.6 - p.cell.y - B.mount_height(p.kind)) < EPS:
				var mount := Rect2(Vector2(p.cell.x, p.cell.z) - Vector2.ONE * B.mount_width(p.kind) / 2, Vector2.ONE * B.mount_width(p.kind))
				if deck.grow(EPS).encloses(mount):
					return true
			if p.kind == Piece.Kind.FOUNDATION and absf(p.cell.y - pos.y) < EPS:
				var neighbor := horizontal_rect(p.kind, p.cell, p.quarter, p.span, p.depth)
				var overlap := deck.grow(EPS).intersection(neighbor)
				if overlap.has_area() and maxf(overlap.size.x, overlap.size.y) > 0.1:
					return true
		return false
	var footprint := horizontal_rect(kind, pos, quarter, span, depth)
	var decks: Array[Rect2] = []
	var wall_tops: Array[Rect2] = []
	for p in pool:
		if p.kind in [Piece.Kind.FOUNDATION, Piece.Kind.FLOOR] and absf(p.cell.y - pos.y) < EPS:
			decks.append(horizontal_rect(p.kind, p.cell, p.quarter, p.span, p.depth).grow(EPS))
		if Piece.is_edge(kind) and (Piece.is_full_wall(p.kind) or p.kind == Piece.Kind.HALF_WALL):
			var height := 1.5 if p.kind == Piece.Kind.HALF_WALL else 3.0
			if absf(pos.y - p.cell.y - height) < EPS and p.quarter % 2 == quarter % 2:
				wall_tops.append(horizontal_rect(p.kind, p.cell, p.quarter, p.span, p.depth).grow(EPS))
	# Permit decorative bases to straddle a wall perimeter, provided their centre
	# remains on a deck. Ordinary unsupported overhangs still fail coverage.
	if kind in [Piece.Kind.PILLAR, Piece.Kind.HELM]:
		for p in pool:
			if Piece.is_edge(p.kind) and absf(p.cell.y - pos.y) < EPS:
				if horizontal_rect(p.kind, p.cell, p.quarter, p.span, p.depth).grow(0.125).has_point(Vector2(pos.x, pos.z)):
					for deck in decks:
						if deck.has_point(Vector2(pos.x, pos.z)):
							return true
	if kind != Piece.Kind.FLOOR:
		return covered(footprint, decks) or (Piece.is_edge(kind) and covered(footprint, wall_tops))
	# Floors need a structural support beneath them; custom blocks never enter pool.
	for p in pool:
		if absf(pos.y - p.cell.y - 3.0) >= EPS:
			continue
		if Piece.is_full_wall(p.kind):
			var line := horizontal_rect(p.kind, p.cell, p.quarter, p.span, p.depth)
			var overlap := footprint.grow(EPS).intersection(line)
			if overlap.has_area() and maxf(overlap.size.x, overlap.size.y) >= minf(span, p.span) * 0.5:
				return true
		elif p.kind == Piece.Kind.PILLAR:
			if footprint.grow(EPS).has_point(Vector2(p.cell.x, p.cell.z)):
				return true
		elif p.kind == Piece.Kind.STAIRS:
			var landing: Vector3 = p.cell + Basis(Vector3.UP, p.quarter * PI / 2) * Vector3(0, 3, -(2 + span / 2))
			if pos.distance_to(landing) < EPS:
				return true
	return false

static func occupied(kind: int, pos: Vector3, quarter: int, span: float, other: StaticBody3D, depth := -1.0) -> bool:
	if B.is_traction(kind) or B.is_traction(other.kind):
		var height := B.mount_height(kind) if B.is_traction(kind) else (0.0 if kind in [0, 1] else 3.0)
		var other_height := B.mount_height(other.kind) if B.is_traction(other.kind) else (0.0 if other.kind in [0, 1] else 3.0)
		var bottom := pos.y - (0.6 if kind == 0 else (0.2 if kind == 1 else 0.0))
		var other_bottom: float = other.cell.y - (0.6 if other.kind == 0 else (0.2 if other.kind == 1 else 0.0))
		return bottom < other.cell.y + other_height - EPS and pos.y + height > other_bottom + EPS and horizontal_rect(kind, pos, quarter, span, depth).grow(-EPS).intersects(horizontal_rect(other.kind, other.cell, other.quarter, other.span, other.depth))
	if kind in [0, 1] and other.kind in [0, 1]:
		return absf(pos.y - other.cell.y) < EPS and horizontal_rect(kind, pos, quarter, span, depth).grow(-EPS).intersects(horizontal_rect(other.kind, other.cell, other.quarter, other.span, other.depth))
	if Piece.is_edge(kind) and Piece.is_edge(other.kind):
		if quarter % 2 != other.quarter % 2:
			return false # Perpendicular wall joints are intentional.
		var normal := 2 if quarter % 2 == 0 else 0
		if absf(pos[normal] - other.cell[normal]) > EPS:
			return false
		var along := 0 if normal == 2 else 2
		var height := 1.5 if kind == Piece.Kind.HALF_WALL else (1.1 if kind == Piece.Kind.RAILING else 3.0)
		var other_height := 1.5 if other.kind == Piece.Kind.HALF_WALL else (1.1 if other.kind == Piece.Kind.RAILING else 3.0)
		return absf(pos[along] - other.cell[along]) < (span + other.span) / 2 - EPS and pos.y < other.cell.y + other_height - EPS and pos.y + height > other.cell.y + EPS
	if (kind >= 10 or kind in [4, 8, 9]) and (other.kind >= 10 or other.kind in [4, 8, 9]):
		return absf(pos.y - other.cell.y) < EPS and horizontal_rect(kind, pos, quarter, span, depth).grow(-EPS).intersects(horizontal_rect(other.kind, other.cell, other.quarter, other.span, other.depth))
	return false
