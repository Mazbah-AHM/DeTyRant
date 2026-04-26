extends CharacterBody3D

const GRAVITY := 24.0
const WALK_SPEED := 7.2
const SPRINT_SPEED := 10.4
const ACCELERATION := 42.0
const FRICTION := 34.0
const AIR_CONTROL := 8.0
const JUMP_SPEED := 7.4

const WEAPONS := {
	"pistol": {"label": "VX Pistol", "damage": 34.0, "headshot": 1.58, "fire_rate": 3.3, "magazine": 12, "reload": 1.15, "range": 60.0, "spread": 0.004, "move_spread": 0.012, "bloom": 0.022, "bloom_recover": 1.8, "recoil_pitch": 0.016, "recoil_yaw": 0.006, "auto": false, "sound": "pistol", "color": Color(1.0, 0.88, 0.55)},
	"smg": {"label": "Ion SMG", "damage": 16.0, "headshot": 1.35, "fire_rate": 12.0, "magazine": 26, "reload": 1.45, "range": 44.0, "spread": 0.010, "move_spread": 0.022, "bloom": 0.014, "bloom_recover": 2.25, "recoil_pitch": 0.006, "recoil_yaw": 0.012, "auto": true, "sound": "smg", "color": Color(0.58, 0.96, 1.0)},
	"rifle": {"label": "Pulse Rifle", "damage": 28.0, "headshot": 1.45, "fire_rate": 7.4, "magazine": 22, "reload": 1.62, "range": 76.0, "spread": 0.006, "move_spread": 0.016, "bloom": 0.017, "bloom_recover": 1.95, "recoil_pitch": 0.010, "recoil_yaw": 0.008, "auto": true, "sound": "rifle", "color": Color(0.46, 0.87, 1.0)},
}

var game: Node
var max_health := 100.0
var health := max_health
var alive := true
var kills := 0
var deaths := 0
var current_weapon := "rifle"
var magazine := 22
var reload_timer := 0.0
var shot_cooldown := 0.0
var spread_bloom := 0.0
var hit_marker := 0.0
var damage_flash := 0.0
var mouse_sensitivity := 0.00205
var pitch := 0.0
var recoil_offset := Vector2.ZERO
var weapon_kick := 0.0
var movement_input := Vector2.ZERO
var look_events := 0

var camera: Camera3D
var pitch_pivot: Node3D
var weapon_root: Node3D
var weapon_base_position := Vector3(0.34, -0.33, -0.84)
var weapon_parts: Array[MeshInstance3D] = []
var ammo_display: Label3D
var collision_shape: CollisionShape3D

func _ready() -> void:
	_add_collision()
	_add_camera()
	_add_weapon_model()
	_reset_magazine()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and alive:
		_apply_mouse_look(event.relative)


func _physics_process(delta: float) -> void:
	if not alive:
		velocity = velocity.move_toward(Vector3.ZERO, FRICTION * delta)
		move_and_slide()
		return

	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	reload_timer = maxf(0.0, reload_timer - delta)
	hit_marker = maxf(0.0, hit_marker - delta * 2.8)
	damage_flash = maxf(0.0, damage_flash - delta * 1.8)
	weapon_kick = maxf(0.0, weapon_kick - delta * 7.5)
	spread_bloom = maxf(0.0, spread_bloom - WEAPONS[current_weapon]["bloom_recover"] * delta)

	_read_actions()
	_update_movement(delta)
	_update_weapon_model(delta)
	_update_weapon_actions()


func reset_for_match(position: Vector3) -> void:
	kills = 0
	deaths = 0
	respawn(position)


func respawn(position: Vector3) -> void:
	health = max_health
	alive = true
	collision_shape.disabled = false
	if weapon_root:
		weapon_root.visible = true
	global_position = position
	velocity = Vector3.ZERO
	pitch = -0.02
	pitch_pivot.rotation.x = pitch
	current_weapon = "rifle"
	_reset_magazine()


func apply_damage(amount: float) -> void:
	if not alive:
		return
	health = maxf(0.0, health - amount)
	damage_flash = minf(0.8, damage_flash + 0.34)
	if health == 0.0:
		alive = false
		collision_shape.disabled = true
		if weapon_root:
			weapon_root.visible = false


func eye_position() -> Vector3:
	return camera.global_position


func weapon_name() -> String:
	return WEAPONS[current_weapon]["label"]


func _apply_mouse_look(relative: Vector2) -> void:
	if relative == Vector2.ZERO:
		return
	look_events += 1
	rotate_y(-relative.x * mouse_sensitivity)
	pitch = clampf(pitch - relative.y * mouse_sensitivity, -1.22, 1.1)
	pitch_pivot.rotation.x = pitch


func _read_actions() -> void:
	movement_input = Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		movement_input.x -= 1.0
	if Input.is_action_pressed("move_right"):
		movement_input.x += 1.0
	if Input.is_action_pressed("move_forward"):
		movement_input.y += 1.0
	if Input.is_action_pressed("move_back"):
		movement_input.y -= 1.0
	movement_input = movement_input.normalized()


func _update_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.1
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_SPEED

	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") and movement_input.y > 0.0 else WALK_SPEED
	camera.fov = lerpf(camera.fov, 82.0 if speed == SPRINT_SPEED else 78.0, delta * 5.5)
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var desired := (forward * movement_input.y + right * movement_input.x) * speed
	var acceleration := ACCELERATION if is_on_floor() else AIR_CONTROL

	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	if movement_input == Vector2.ZERO and is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)

	move_and_slide()


func _update_weapon_actions() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		_switch_weapon("pistol")
	if Input.is_action_just_pressed("weapon_2"):
		_switch_weapon("smg")
	if Input.is_action_just_pressed("weapon_3"):
		_switch_weapon("rifle")
	if Input.is_action_just_pressed("reload"):
		_start_reload()
	if reload_timer == 0.0 and magazine == 0:
		_start_reload()
	if reload_timer > 0.0:
		return

	var weapon: Dictionary = WEAPONS[current_weapon]
	var trigger := Input.is_action_pressed("fire") if weapon["auto"] else Input.is_action_just_pressed("fire")
	if trigger:
		_try_fire(weapon)


func _try_fire(weapon: Dictionary) -> void:
	if shot_cooldown > 0.0:
		return
	if magazine <= 0:
		_start_reload()
		return

	magazine -= 1
	shot_cooldown = 1.0 / weapon["fire_rate"]
	spread_bloom = minf(0.12, spread_bloom + weapon["bloom"])
	weapon_kick = minf(0.17, weapon_kick + 0.11)

	pitch = clampf(pitch - weapon["recoil_pitch"], -1.22, 1.1)
	pitch_pivot.rotation.x = pitch
	rotate_y(randf_range(-weapon["recoil_yaw"], weapon["recoil_yaw"]))

	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED, 0.0, 1.0)
	var spread: float = weapon["spread"] + weapon["move_spread"] * speed_ratio + spread_bloom
	direction += camera.global_transform.basis.x * randf_range(-spread, spread)
	direction += camera.global_transform.basis.y * randf_range(-spread, spread)
	game.register_player_shot(origin, direction.normalized(), weapon)


func _start_reload() -> void:
	var weapon: Dictionary = WEAPONS[current_weapon]
	if reload_timer > 0.0 or magazine >= weapon["magazine"]:
		return
	var weapon_id := current_weapon
	var reload_duration: float = weapon["reload"]
	reload_timer = reload_duration
	if game.audio:
		game.audio.play_2d("reload", -10.0)
	await get_tree().create_timer(reload_duration).timeout
	if alive and current_weapon == weapon_id:
		_reset_magazine()


func _switch_weapon(id: String) -> void:
	if not WEAPONS.has(id) or current_weapon == id:
		return
	current_weapon = id
	reload_timer = 0.0
	spread_bloom *= 0.35
	_reset_magazine()
	_configure_weapon_model()


func _reset_magazine() -> void:
	magazine = WEAPONS[current_weapon]["magazine"]


func _add_collision() -> void:
	collision_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.54
	capsule.height = 1.82
	collision_shape.shape = capsule
	collision_shape.position.y = 0.92
	add_child(collision_shape)


func _add_camera() -> void:
	pitch_pivot = Node3D.new()
	pitch_pivot.name = "PitchPivot"
	pitch_pivot.position.y = 1.58
	add_child(pitch_pivot)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 78.0
	camera.near = 0.035
	camera.far = 240.0
	camera.current = true
	pitch_pivot.add_child(camera)


func _add_weapon_model() -> void:
	weapon_root = Node3D.new()
	weapon_root.name = "ViewWeapon"
	camera.add_child(weapon_root)

	var gunmetal := _weapon_material(Color(0.54, 0.58, 0.60), Color(0.03, 0.06, 0.08), 0.16, 0.48, 0.24)
	var dark := _weapon_material(Color(0.055, 0.065, 0.075), Color(0.00, 0.02, 0.03), 0.05, 0.68, 0.30)
	var rubber := _weapon_material(Color(0.035, 0.04, 0.045), Color(0, 0, 0), 0.0, 0.10, 0.72)
	var cyan := _weapon_material(Color(0.18, 0.78, 1.0), Color(0.18, 0.82, 1.0), 1.8, 0.08, 0.18)
	var glass := _weapon_material(Color(0.28, 0.72, 1.0, 0.46), Color(0.10, 0.50, 0.88), 0.65, 0.0, 0.04)
	var glove := _weapon_material(Color(0.045, 0.052, 0.058), Color(0, 0, 0), 0.0, 0.12, 0.64)
	var sleeve := _weapon_material(Color(0.17, 0.22, 0.26), Color(0.01, 0.04, 0.06), 0.04, 0.18, 0.56)

	_weapon_box("UpperReceiver", Vector3(0.00, 0.02, 0.04), Vector3(0.28, 0.15, 0.66), gunmetal)
	_weapon_box("LowerReceiver", Vector3(0.02, -0.075, 0.09), Vector3(0.20, 0.13, 0.42), dark)
	_weapon_box("TopRail", Vector3(0.0, 0.125, -0.02), Vector3(0.30, 0.035, 0.58), dark)
	_weapon_box("EnergyCore", Vector3(0.0, 0.075, -0.06), Vector3(0.135, 0.032, 0.39), cyan)
	_weapon_box("SidePanelL", Vector3(-0.155, 0.01, 0.02), Vector3(0.026, 0.105, 0.48), dark)
	_weapon_box("SidePanelR", Vector3(0.155, 0.01, 0.02), Vector3(0.026, 0.105, 0.48), dark)

	for z in [0.22, 0.11, 0.0, -0.11, -0.22]:
		_weapon_box("RailRib", Vector3(0, 0.156, z), Vector3(0.32, 0.018, 0.034), gunmetal)

	_weapon_cylinder("Barrel", Vector3(0.0, 0.01, -0.48), 0.028, 0.44, dark, Vector3(90, 0, 0))
	_weapon_cylinder("MuzzleBrake", Vector3(0.0, 0.01, -0.72), 0.050, 0.12, dark, Vector3(90, 0, 0))
	_weapon_box("MuzzleGlow", Vector3(0.0, 0.01, -0.79), Vector3(0.05, 0.05, 0.018), cyan)

	_weapon_box("Grip", Vector3(0.045, -0.235, 0.18), Vector3(0.12, 0.28, 0.13), rubber, Vector3(-11, 0, 4))
	_weapon_box("ForeGrip", Vector3(-0.02, -0.205, -0.28), Vector3(0.105, 0.25, 0.10), rubber, Vector3(-8, 0, -3))
	_weapon_box("StockBridge", Vector3(0.015, -0.005, 0.48), Vector3(0.16, 0.10, 0.28), dark)
	_weapon_box("StockPad", Vector3(0.015, -0.035, 0.66), Vector3(0.23, 0.17, 0.09), rubber)

	_weapon_box("OpticMount", Vector3(0.0, 0.205, 0.08), Vector3(0.12, 0.055, 0.16), dark)
	_weapon_box("OpticGlass", Vector3(0.0, 0.235, -0.02), Vector3(0.17, 0.105, 0.10), glass)
	_weapon_box("AmmoDisplayPlate", Vector3(0.12, 0.108, 0.20), Vector3(0.09, 0.055, 0.12), glass, Vector3(0, -18, 0))

	_weapon_box("RightGlove", Vector3(0.16, -0.245, 0.13), Vector3(0.16, 0.105, 0.19), glove, Vector3(-5, 0, 9))
	_weapon_box("LeftGlove", Vector3(-0.13, -0.215, -0.31), Vector3(0.15, 0.105, 0.20), glove, Vector3(0, 0, -9))
	_weapon_box("SupportSleeve", Vector3(-0.22, -0.34, -0.17), Vector3(0.16, 0.13, 0.58), sleeve, Vector3(0, 0, -13))
	_weapon_box("TriggerSleeve", Vector3(0.23, -0.37, 0.28), Vector3(0.16, 0.13, 0.42), sleeve, Vector3(0, 0, 16))

	ammo_display = Label3D.new()
	ammo_display.name = "AmmoDisplay"
	ammo_display.text = "%02d" % magazine
	ammo_display.font_size = 26
	ammo_display.pixel_size = 0.004
	ammo_display.modulate = Color(0.42, 0.92, 1.0)
	ammo_display.outline_size = 2
	ammo_display.outline_modulate = Color(0.0, 0.03, 0.05, 0.9)
	ammo_display.position = Vector3(0.113, 0.125, 0.18)
	ammo_display.rotation_degrees = Vector3(0, -18, 0)
	weapon_root.add_child(ammo_display)

	_configure_weapon_model()


func _configure_weapon_model() -> void:
	if current_weapon == "pistol":
		weapon_base_position = Vector3(0.28, -0.35, -0.64)
		weapon_root.position = weapon_base_position
		weapon_root.scale = Vector3(0.82, 0.86, 0.72)
	elif current_weapon == "smg":
		weapon_base_position = Vector3(0.32, -0.34, -0.76)
		weapon_root.position = weapon_base_position
		weapon_root.scale = Vector3(0.9, 0.95, 0.86)
	else:
		weapon_base_position = Vector3(0.34, -0.33, -0.84)
		weapon_root.position = weapon_base_position
		weapon_root.scale = Vector3.ONE


func _update_weapon_model(delta: float) -> void:
	var move_amount := clampf(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED, 0.0, 1.0)
	var bob := sin(Time.get_ticks_msec() * 0.012) * move_amount * 0.022
	var sway := movement_input.x * 0.025
	var target_y := weapon_base_position.y + bob + weapon_kick * 0.1
	weapon_root.position.y = lerpf(weapon_root.position.y, target_y, delta * 12.0)
	weapon_root.position.x = lerpf(weapon_root.position.x, weapon_base_position.x + sway, delta * 8.0)
	weapon_root.rotation_degrees = Vector3(-2.0 + weapon_kick * 13.0, -5.0 + weapon_kick * 5.0, -movement_input.x * 2.0 - weapon_kick * 7.0)
	if ammo_display:
		ammo_display.text = "%02d" % magazine
		ammo_display.modulate = WEAPONS[current_weapon]["color"]


func _weapon_box(node_name: String, position: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weapon_root.add_child(mesh_instance)
	weapon_parts.append(mesh_instance)
	return mesh_instance


func _weapon_cylinder(node_name: String, position: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 28
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weapon_root.add_child(mesh_instance)
	weapon_parts.append(mesh_instance)
	return mesh_instance


func _weapon_material(albedo: Color, emission: Color, energy: float, metallic := 0.28, roughness := 0.28) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.emission_enabled = energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = energy
	material.metallic = metallic
	material.roughness = roughness
	if albedo.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
