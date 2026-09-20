extends SceneTree
const B = preload("res://scripts/mechanics/balance.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1
func record(kind: int, mass: float, health := 1.0) -> Dictionary:
	return {"kind": kind, "mass": mass, "health": health}
func _initialize() -> void:
	var records := [record(0, 80), record(11, 8)]
	for i in 4:
		records.append(record(13, 2))
	var base := B.performance(records, 100)
	check(base.speed > 0 and base.ratio == 1, "Fueled engine powers traction")
	check(B.performance(records, 0).speed == 0, "No fuel means no powered movement")
	check(B.performance([record(0, 80)], 100).speed == 0, "Helm cannot propel a bare city")
	check(B.performance(records, 100, 300).speed < base.speed, "Cargo mass reduces speed")
	check(B.performance(records, 100, 0, 2).speed > 0 and B.performance(records, 100, 0, 2).speed < base.speed, "Rough terrain adds drag without hard stop")
	var overloaded := records.duplicate(true)
	for i in 12:
		overloaded.append(record(16, 3))
	check(B.performance(overloaded, 100).ratio < 1, "Shared consumer overload degrades power")
	check(B.performance(records, 100, 0, 0, 100).speed < base.speed, "Tow mass reduces speed")
	print("Power and movement math tests: %d failures" % failures)
	quit(1 if failures else 0)
