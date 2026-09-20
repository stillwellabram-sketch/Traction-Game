extends MeshInstance3D

var previous_key := Vector4(INF, INF, INF, INF)
func _init() -> void:
	mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.4, 0.85, 1.0, 0.3)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

func show_at(point: Vector3, step: float) -> void:
	visible = true
	var centre := Vector3(snappedf(point.x, step), point.y + 0.025, snappedf(point.z, step))
	var key := Vector4(centre.x, centre.y, centre.z, step)
	if key == previous_key:
		return
	previous_key = key
	position = centre
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var count := 8
	var radius := count * step
	for i in range(-count, count + 1):
		var offset := i * step
		mesh.surface_add_vertex(Vector3(offset, 0, -radius))
		mesh.surface_add_vertex(Vector3(offset, 0, radius))
		mesh.surface_add_vertex(Vector3(-radius, 0, offset))
		mesh.surface_add_vertex(Vector3(radius, 0, offset))
	mesh.surface_end()
