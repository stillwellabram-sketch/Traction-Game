extends RefCounted

# PROTOTYPE GUESSES: all values below need playtesting. Units: tonnes, kW,
# metres/second, fuel units/second, HP, scrap units. No city-size cap.
const ENGINE_SMALL := 10
const ENGINE_MEDIUM := 11
const ENGINE_LARGE := 12
const WHEEL := 13
const WHEEL_3 := 18
const WHEEL_4 := 19
const WHEEL_5 := 20
const WHEEL_6 := 21
const TREAD := 14
const LEG := 15
const GUN := 16
const GUT := 17
const INITIAL_FUEL := 400.0
const INITIAL_SCRAP := 3000.0
const SCRAP_MASS := 0.001
const FUEL_MASS := 0.01
const REPAIR_COST_FRACTION := 0.5
const REEL_SPEED := 2.0
const SALVAGE_FUEL_PER_COST := 0.02
const LOSS_RETENTION := 0.5
const SHOT_DAMAGE := 90.0
const SHOT_INTERVAL := 0.6
const SHOT_RANGE := 180.0
const SHOT_FUEL := 0.1
const WEAPON_MIN_POWER := 0.65
const TOW_MOBILITY_THRESHOLD := 0.3
const TOW_RANGE := 22.0
const TOW_DAMAGE_MULTIPLIER := 1.35
const TOW_MASS_MULTIPLIER := 1.4
const TERRAIN_MASS_DRAG := 0.002
const MAX_STEP_HEIGHT := 2.0
const SALVAGE_FRACTION := 0.6
const MATERIAL_DENSITY := [0.8, 0.25, 1.2, 1.0]
const MODULES := {
	10: {"name": "Small engine", "size": Vector3(1, 1.2, 1.5), "mass": 3.0, "power": 300.0, "fuel": 0.12, "draw": 0.0, "hp": 360.0, "cost": 100.0},
	11: {"name": "Medium engine", "size": Vector3(2, 1.8, 2), "mass": 8.0, "power": 900.0, "fuel": 0.32, "draw": 0.0, "hp": 650.0, "cost": 260.0},
	12: {"name": "Large engine", "size": Vector3(3, 2.4, 3), "mass": 20.0, "power": 2400.0, "fuel": 0.8, "draw": 0.0, "hp": 1000.0, "cost": 650.0},
	13: {"name": "Wheel 2 × 2", "size": Vector3(2, 2.4, 2), "mass": 2.0, "draw": 120.0, "speed": 13.0, "torque": 1.0, "terrain": 0.65, "hp": 280.0, "cost": 60.0},
	14: {"name": "Tread assembly", "size": Vector3(1.2, 1.4, 2.8), "mass": 6.0, "draw": 280.0, "speed": 9.0, "torque": 1.8, "terrain": 1.4, "hp": 520.0, "cost": 150.0},
	15: {"name": "Walking leg", "size": Vector3(1.3, 2.2, 1.3), "mass": 4.0, "draw": 200.0, "speed": 7.0, "torque": 1.5, "terrain": 2.2, "hp": 400.0, "cost": 130.0},
	16: {"name": "Deck gun", "size": Vector3(1, 1.2, 2), "mass": 3.0, "draw": 100.0, "hp": 350.0, "cost": 150.0},
	17: {"name": "Gut processor", "size": Vector3(3, 2, 2), "mass": 12.0, "draw": 250.0, "rate": 28.0, "hp": 700.0, "cost": 350.0},
	18: {"name": "Wheel 3 × 3", "size": Vector3(3, 3.6, 3), "mass": 6.75, "draw": 270.0, "speed": 13.0, "torque": 1.2, "terrain": 0.80, "hp": 630.0, "cost": 135.0},
	19: {"name": "Wheel 4 × 4", "size": Vector3(4, 4.8, 4), "mass": 16.00, "draw": 480.0, "speed": 13.0, "torque": 1.4, "terrain": 0.95, "hp": 1120.0, "cost": 240.0},
	20: {"name": "Wheel 5 × 5", "size": Vector3(5, 6.0, 5), "mass": 31.25, "draw": 750.0, "speed": 13.0, "torque": 1.6, "terrain": 1.10, "hp": 1750.0, "cost": 375.0},
	21: {"name": "Wheel 6 × 6", "size": Vector3(6, 7.2, 6), "mass": 54.00, "draw": 1080.0, "speed": 13.0, "torque": 1.8, "terrain": 1.25, "hp": 2520.0, "cost": 540.0}
}

static func is_module(kind: int) -> bool:
	return MODULES.has(kind)

static func is_traction(kind: int) -> bool:
	return is_wheel(kind) or kind in [TREAD, LEG]

static func max_health(kind: int) -> float:
	return MODULES[kind].hp if is_module(kind) else (650.0 if kind == 0 else 220.0)

static func mass(kind: int, volume: float, material: int) -> float:
	return MODULES[kind].mass if is_module(kind) else maxf(0.03, volume * MATERIAL_DENSITY[clampi(material, 0, 3)])

static func cost(kind: int, volume: float, material: int) -> float:
	return MODULES[kind].cost if is_module(kind) else ceilf(maxf(2, mass(kind, volume, material) * 3))

static func terrain_drag(roughness: float, total_mass: float, handling: float) -> float:
	return 1.0 + maxf(roughness, 0) * (1.0 + total_mass * TERRAIN_MASS_DRAG) / maxf(handling, 0.2)

# Records contain mass, kind, health ratio, connected and enabled. Shared by
# live cities, previews and tests; no rendering or physics dependencies.
static func performance(records: Array, fuel: float, cargo_mass := 0.0, roughness := 0.0, tow_mass := 0.0) -> Dictionary:
	var weight := cargo_mass + tow_mass * TOW_MASS_MULTIPLIER
	var supply := 0.0
	var demand := 0.0
	var consumption := 0.0
	var traction := 0.0
	var installed := 0.0
	var speed_weight := 0.0
	var terrain_weight := 0.0
	var torque_weight := 0.0
	for record in records:
		weight += record.mass
		var kind: int = record.kind
		if not is_module(kind):
			continue
		var spec: Dictionary = MODULES[kind]
		if is_traction(kind):
			installed += spec.draw
		var health: float = clampf(record.get("health", 1.0), 0, 1)
		if not record.get("connected", true) or not record.get("enabled", true) or health <= 0:
			continue
		if spec.has("power") and fuel > 0:
			supply += spec.power * health
			consumption += spec.fuel * health
		demand += spec.draw * health
		if is_traction(kind):
			var draw: float = spec.draw * health
			traction += draw
			speed_weight += spec.speed * draw
			terrain_weight += spec.terrain * draw
			torque_weight += spec.torque * draw
	var ratio := minf(1, supply / maxf(demand, 0.001))
	var mobility := traction / maxf(installed, 0.001)
	var handling := terrain_weight / maxf(traction, 0.001)
	var drag := terrain_drag(roughness, weight, handling)
	var power := traction * ratio
	var load_factor := sqrt(power / maxf(weight * 4, 1))
	var speed := speed_weight / maxf(traction, 0.001) * minf(load_factor, 1.5) * sqrt(mobility) / drag
	var torque := torque_weight / maxf(traction, 0.001)
	return {"mass": weight, "supply": supply, "demand": demand, "ratio": ratio, "fuel_rate": consumption,
		"mobility": mobility * ratio, "speed": speed, "acceleration": minf(4, power * torque / maxf(weight * 2, 1)) / drag,
		"turn_rate": 0.5 * minf(load_factor, 1.0) * mobility / drag, "drag": drag}

static func is_wheel(kind: int) -> bool:
	return kind in [WHEEL, WHEEL_3, WHEEL_4, WHEEL_5, WHEEL_6]

static func mount_height(kind: int) -> float:
	return MODULES[kind].size.y if is_traction(kind) else 0.0

static func mount_width(kind: int) -> float:
	return minf(2.0, MODULES[kind].size.x * 0.85)
