extends CharacterBody3D

var camera: Camera3D
var pitch := 0.0
var require_mouse_capture := true
var input_locked := false
var piloting := false
const EDGE_PROBE_MARGIN := 0.22
const EDGE_MAX_DROP := 0.45

func controls_active() -> bool:
	return not input_locked and (not require_mouse_capture or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)

# Probe ahead of the capsule centre, not underneath its trailing edge.
# Split axes allow sliding along a ledge while the outward motion is blocked.
func has_support_at(offset: Vector3) -> bool:
	var feet := global_position + offset
	var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.25, feet - Vector3.UP * EDGE_MAX_DROP, 5)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.y >= cos(floor_max_angle)

func guard_edges(delta: float) -> void:
	var step := Vector3(velocity.x, 0, velocity.z) * delta
	if absf(step.x) > 0.00001 and not has_support_at(Vector3(step.x + signf(step.x) * EDGE_PROBE_MARGIN, 0, 0)):
		velocity.x = 0
	if absf(step.z) > 0.00001 and not has_support_at(Vector3(0, 0, step.z + signf(step.z) * EDGE_PROBE_MARGIN)):
		velocity.z = 0
	step = Vector3(velocity.x, 0, velocity.z) * delta
	if step.length_squared() > 0 and not has_support_at(step + step.normalized() * EDGE_PROBE_MARGIN):
		velocity.x = 0
		velocity.z = 0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 5
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	camera = Camera3D.new()
	camera.far = 2500
	camera.position.y = 1.65
	camera.fov = 80
	add_child(camera)
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.0022)
		pitch = clampf(pitch - event.relative.y * 0.0022, -1.48, 1.48)
		camera.rotation.x = pitch
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if piloting:
		velocity = Vector3.ZERO
		return
	var moving := Vector2.ZERO
	if controls_active():
		moving = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := global_basis * Vector3(moving.x, 0, moving.y)
	var guarding := controls_active() and Input.is_action_pressed("edge_guard")
	var speed := 2.0 if guarding else (8.0 if Input.is_action_pressed("sprint") else 4.5)
	velocity.x = move_toward(velocity.x, direction.x * speed, 30 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 30 * delta)
	if not is_on_floor():
		velocity.y -= 22 * delta
	elif Input.is_action_just_pressed("jump") and controls_active():
		velocity.y = 7
	if guarding and is_on_floor() and velocity.y <= 0:
		guard_edges(delta)
	move_and_slide()
	if position.y < -20:
		position = Vector3(0, 4, 8)
		velocity = Vector3.ZERO
