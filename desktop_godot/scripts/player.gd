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
	"rifle": {"label": "AK-47", "damage": 31.0, "headshot": 1.45, "fire_rate": 9.5, "magazine": 30, "reload": 1.82, "range": 82.0, "spread": 0.006, "move_spread": 0.016, "bloom": 0.017, "bloom_recover": 1.95, "recoil_pitch": 0.012, "recoil_yaw": 0.009, "auto": true, "sound": "rifle", "color": Color(1.0, 0.68, 0.34)},
}

const VIEWMODEL_SCENES := {
	"pistol": "res://assets/viewmodels/vx_pistol_viewmodel.tscn",
	"smg": "res://assets/viewmodels/ion_smg_viewmodel.tscn",
	"rifle": "res://assets/viewmodels/ak47_viewmodel.tscn",
}

const VIEWMODEL_FALLBACK_SCENES := {
	"pistol": "res://assets/viewmodels/vx_pistol_viewmodel.glb",
	"smg": "res://assets/viewmodels/ion_smg_viewmodel.glb",
	"rifle": "res://assets/viewmodels/ak47_viewmodel.glb",
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
var reload_total := 0.0
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
var active_viewmodel: Node3D
var active_viewmodel_id := ""
var viewmodel_animation_player: AnimationPlayer
var muzzle_socket: Node3D
var footstep_distance := 0.0
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
	if reload_timer == 0.0:
		reload_total = 0.0
	hit_marker = maxf(0.0, hit_marker - delta * 2.8)
	damage_flash = maxf(0.0, damage_flash - delta * 1.8)
	weapon_kick = maxf(0.0, weapon_kick - delta * 7.5)
	spread_bloom = maxf(0.0, spread_bloom - WEAPONS[current_weapon]["bloom_recover"] * delta)

	_read_actions()
	_update_movement(delta)
	_update_footsteps(delta)
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
	_configure_weapon_model()


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


func _update_footsteps(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or horizontal_speed < 1.0 or movement_input == Vector2.ZERO:
		footstep_distance = minf(footstep_distance, 0.35)
		return

	footstep_distance += horizontal_speed * delta
	var stride := 1.65 if Input.is_action_pressed("sprint") else 2.15
	if footstep_distance < stride:
		return

	footstep_distance = 0.0
	if game and game.has_method("play_footstep"):
		game.play_footstep(global_position + Vector3.UP * 0.08, _surface_underfoot(), clampf(horizontal_speed / SPRINT_SPEED, 0.35, 1.0))


func _surface_underfoot() -> String:
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.35, global_position + Vector3.DOWN * 1.25, 1)
	params.exclude = [get_rid()]
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit := space.intersect_ray(params)
	if hit.is_empty() or not hit.has("collider"):
		return "concrete"
	var collider = hit["collider"]
	if collider is Node and collider.has_meta("surface"):
		return String(collider.get_meta("surface"))
	return "concrete"


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
	_play_viewmodel_animation("fire")

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
	reload_total = reload_duration
	_play_viewmodel_animation("reload")
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
	reload_total = 0.0
	spread_bloom *= 0.35
	_reset_magazine()
	_configure_weapon_model()
	_play_viewmodel_animation("equip")


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
	_configure_weapon_model()


func _mount_viewmodel(id: String) -> void:
	if active_viewmodel_id == id and active_viewmodel:
		return
	for child in weapon_root.get_children():
		child.queue_free()
	weapon_parts.clear()
	ammo_display = null
	viewmodel_animation_player = null
	muzzle_socket = null
	active_viewmodel_id = id

	var scene := _load_viewmodel_scene(id)
	if scene:
		active_viewmodel = scene.instantiate() as Node3D
		if active_viewmodel:
			active_viewmodel.name = "%sImportedViewModel" % id.capitalize()
			weapon_root.add_child(active_viewmodel)
			_bind_imported_viewmodel()
	else:
		active_viewmodel = Node3D.new()
		active_viewmodel.name = "%sDevViewModelFallback" % id.capitalize()
		weapon_root.add_child(active_viewmodel)
		_build_dev_viewmodel()

	if not muzzle_socket:
		muzzle_socket = Node3D.new()
		muzzle_socket.name = "MuzzleSocket"
		muzzle_socket.position = Vector3(0.0, 0.01, -0.82)
		active_viewmodel.add_child(muzzle_socket)


func _load_viewmodel_scene(id: String) -> PackedScene:
	for path in [VIEWMODEL_SCENES[id], VIEWMODEL_FALLBACK_SCENES[id]]:
		if ResourceLoader.exists(path):
			var resource := load(path)
			if resource is PackedScene:
				return resource
	return null


func _bind_imported_viewmodel() -> void:
	viewmodel_animation_player = _find_animation_player(active_viewmodel)
	muzzle_socket = _find_node3d_by_names(active_viewmodel, ["muzzle", "muzzlesocket", "muzzle_socket", "barrel_end", "barrelend"])
	var display_node := _find_node_by_names(active_viewmodel, ["ammodisplay", "ammo_display", "counter", "ammo_counter"])
	if display_node is Label3D:
		ammo_display = display_node
	_play_viewmodel_animation("equip")


func _build_dev_viewmodel() -> void:
	var steel := _weapon_material(Color(0.10, 0.105, 0.095), Color(0.008, 0.008, 0.006), 0.02, 0.74, 0.33)
	var blued_steel := _weapon_material(Color(0.035, 0.039, 0.041), Color(0.002, 0.004, 0.006), 0.01, 0.82, 0.22)
	var worn_edge := _weapon_material(Color(0.48, 0.47, 0.42), Color(0.015, 0.014, 0.012), 0.02, 0.72, 0.26)
	var bakelite := _weapon_material(Color(0.48, 0.20, 0.075), Color(0.035, 0.012, 0.002), 0.02, 0.05, 0.45)
	var wood := _weapon_material(Color(0.46, 0.22, 0.095), Color(0.04, 0.018, 0.004), 0.025, 0.02, 0.50)
	var dark_wood := _weapon_material(Color(0.24, 0.11, 0.045), Color(0.018, 0.006, 0.002), 0.01, 0.02, 0.58)
	var glove := _weapon_material(Color(0.045, 0.052, 0.058), Color(0, 0, 0), 0.0, 0.12, 0.64)
	var sleeve := _weapon_material(Color(0.17, 0.22, 0.26), Color(0.01, 0.04, 0.06), 0.04, 0.18, 0.56)

	_weapon_box("StampedReceiver", Vector3(0.00, 0.00, 0.04), Vector3(0.31, 0.17, 0.58), steel)
	_weapon_box("DustCover", Vector3(0.0, 0.10, -0.01), Vector3(0.25, 0.065, 0.46), worn_edge, Vector3(-2, 0, 0))
	_weapon_box("RearTrunnion", Vector3(0.0, -0.01, 0.36), Vector3(0.30, 0.16, 0.11), blued_steel)
	_weapon_box("BoltCarrierSlot", Vector3(-0.165, 0.035, 0.05), Vector3(0.018, 0.060, 0.34), blued_steel)
	_weapon_box("ChargingHandle", Vector3(-0.21, 0.055, -0.02), Vector3(0.11, 0.035, 0.055), worn_edge, Vector3(0, 0, -8))
	_weapon_box("TriggerGuard", Vector3(0.02, -0.155, 0.12), Vector3(0.17, 0.030, 0.18), blued_steel, Vector3(-8, 0, 0))
	_weapon_box("Trigger", Vector3(0.02, -0.185, 0.08), Vector3(0.035, 0.09, 0.035), blued_steel, Vector3(-22, 0, 0))

	_weapon_box("WoodStockNeck", Vector3(0.0, -0.035, 0.45), Vector3(0.21, 0.13, 0.20), wood, Vector3(4, 0, 0))
	_weapon_box("WoodStock", Vector3(0.0, -0.060, 0.66), Vector3(0.28, 0.18, 0.30), wood, Vector3(8, 0, 0))
	_weapon_box("StockButtPlate", Vector3(0.0, -0.065, 0.83), Vector3(0.30, 0.20, 0.045), blued_steel, Vector3(8, 0, 0))
	_weapon_box("WoodPistolGrip", Vector3(0.045, -0.245, 0.22), Vector3(0.135, 0.31, 0.13), wood, Vector3(-13, 0, 6))
	_weapon_box("GripShadowGroove", Vector3(0.047, -0.245, 0.155), Vector3(0.142, 0.026, 0.022), dark_wood, Vector3(-13, 0, 6))
	_weapon_box("WoodLowerHandguard", Vector3(0.0, -0.040, -0.285), Vector3(0.31, 0.13, 0.38), wood, Vector3(-2, 0, 0))
	_weapon_box("WoodUpperHandguard", Vector3(0.0, 0.090, -0.305), Vector3(0.24, 0.075, 0.34), wood, Vector3(-2, 0, 0))

	for index in range(5):
		_weapon_box("HandguardGroove", Vector3(-0.158, -0.037, -0.42 + index * 0.065), Vector3(0.018, 0.100, 0.018), dark_wood)
		_weapon_box("HandguardGroove", Vector3(0.158, -0.037, -0.42 + index * 0.065), Vector3(0.018, 0.100, 0.018), dark_wood)

	_weapon_cylinder("Barrel", Vector3(0.0, 0.038, -0.61), 0.024, 0.74, blued_steel, Vector3(90, 0, 0))
	_weapon_cylinder("GasTube", Vector3(0.0, 0.118, -0.50), 0.030, 0.48, steel, Vector3(90, 0, 0))
	_weapon_box("FrontSightTower", Vector3(0.0, 0.105, -0.84), Vector3(0.13, 0.19, 0.045), blued_steel)
	_weapon_box("FrontSightPost", Vector3(0.0, 0.225, -0.84), Vector3(0.026, 0.080, 0.020), worn_edge)
	_weapon_box("RearSightLeaf", Vector3(0.0, 0.188, -0.095), Vector3(0.16, 0.026, 0.15), blued_steel, Vector3(-8, 0, 0))
	_weapon_box("MuzzleDevice", Vector3(0.0, 0.038, -0.99), Vector3(0.075, 0.075, 0.12), blued_steel)

	for index in range(7):
		var z := 0.02 - index * 0.043
		var y := -0.235 - index * 0.014
		var rot := Vector3(-8 - index * 2.2, 0, 0)
		var width := 0.205 - index * 0.004
		_weapon_box("CurvedMagazine", Vector3(0.0, y, z), Vector3(width, 0.105, 0.055), bakelite, rot)
	_weapon_box("MagazineFloorPlate", Vector3(0.0, -0.365, -0.255), Vector3(0.185, 0.035, 0.090), blued_steel, Vector3(-22, 0, 0))

	muzzle_socket = Node3D.new()
	muzzle_socket.name = "MuzzleSocket"
	muzzle_socket.position = Vector3(0.0, 0.038, -1.07)
	active_viewmodel.add_child(muzzle_socket)

	_weapon_box("RightGlove", Vector3(0.16, -0.245, 0.13), Vector3(0.16, 0.105, 0.19), glove, Vector3(-5, 0, 9))
	_weapon_box("LeftGlove", Vector3(-0.13, -0.175, -0.33), Vector3(0.15, 0.105, 0.20), glove, Vector3(0, 0, -9))
	_weapon_box("SupportSleeve", Vector3(-0.22, -0.32, -0.18), Vector3(0.16, 0.13, 0.58), sleeve, Vector3(0, 0, -13))
	_weapon_box("TriggerSleeve", Vector3(0.23, -0.37, 0.28), Vector3(0.16, 0.13, 0.42), sleeve, Vector3(0, 0, 16))

	ammo_display = Label3D.new()
	ammo_display.name = "AmmoDisplay"
	ammo_display.text = "%02d" % magazine
	ammo_display.font_size = 20
	ammo_display.pixel_size = 0.004
	ammo_display.modulate = Color(1.0, 0.72, 0.36)
	ammo_display.outline_size = 2
	ammo_display.outline_modulate = Color(0.0, 0.03, 0.05, 0.9)
	ammo_display.position = Vector3(0.142, 0.130, 0.155)
	ammo_display.rotation_degrees = Vector3(0, -23, 0)
	active_viewmodel.add_child(ammo_display)


func _configure_weapon_model() -> void:
	_mount_viewmodel(current_weapon)
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
	var reload_alpha := 0.0
	if reload_timer > 0.0 and reload_total > 0.0:
		reload_alpha = sin((1.0 - reload_timer / reload_total) * PI)
	var target_y := weapon_base_position.y + bob + weapon_kick * 0.1 - reload_alpha * 0.18
	weapon_root.position.y = lerpf(weapon_root.position.y, target_y, delta * 12.0)
	weapon_root.position.x = lerpf(weapon_root.position.x, weapon_base_position.x + sway, delta * 8.0)
	weapon_root.rotation_degrees = Vector3(-2.0 + weapon_kick * 13.0 + reload_alpha * 14.0, -5.0 + weapon_kick * 5.0 - reload_alpha * 10.0, -movement_input.x * 2.0 - weapon_kick * 7.0 + reload_alpha * 18.0)
	if ammo_display:
		ammo_display.text = "%02d" % magazine
		ammo_display.modulate = WEAPONS[current_weapon]["color"]


func muzzle_position() -> Vector3:
	if muzzle_socket and is_instance_valid(muzzle_socket):
		return muzzle_socket.global_position
	return camera.global_position - camera.global_transform.basis.z * 0.7 + camera.global_transform.basis.x * 0.25 - camera.global_transform.basis.y * 0.2


func _play_viewmodel_animation(action: String) -> void:
	if not viewmodel_animation_player:
		return
	var candidates := {
		"equip": ["equip", "draw", "ready", "idle"],
		"fire": ["fire", "shoot", "shot", "attack"],
		"reload": ["reload", "reload_full", "mag_reload"],
		"idle": ["idle", "weapon_idle"],
	}
	if not candidates.has(action):
		return
	for animation_name in candidates[action]:
		if viewmodel_animation_player.has_animation(animation_name):
			viewmodel_animation_player.play(animation_name)
			return


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _find_node3d_by_names(root: Node, names: Array[String]) -> Node3D:
	var found := _find_node_by_names(root, names)
	return found if found is Node3D else null


func _find_node_by_names(root: Node, names: Array[String]) -> Node:
	var normalized_name := String(root.name).to_lower().replace(" ", "").replace("-", "_")
	if names.has(normalized_name):
		return root
	for child in root.get_children():
		var found := _find_node_by_names(child, names)
		if found:
			return found
	return null


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
	active_viewmodel.add_child(mesh_instance)
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
	active_viewmodel.add_child(mesh_instance)
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
