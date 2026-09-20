extends RefCounted
const B = preload("res://scripts/mechanics/balance.gd")

# Old saves mounted traction inside a ground-level deck. Keep the design, raising
# the superstructure above its running gear instead of deleting the player's work.
static func migrate(data: Dictionary) -> Dictionary:
	if data.get("version", 1) >= 6 or data.get("layout", "") == "ground_traction":
		return data
	var result := data.duplicate(true)
	var lift := 0.0
	for record in result.get("pieces", []):
		if B.is_traction(int(record.kind)):
			lift = maxf(lift, B.mount_height(int(record.kind)))
	if lift > 0:
		for record in result.pieces:
			if B.is_traction(int(record.kind)):
				record.y = lift - B.mount_height(int(record.kind))
			else:
				record.y += lift
		for record in result.get("custom_blocks", []):
			record.position[1] += lift
	result["layout"] = "ground_traction"
	return result
