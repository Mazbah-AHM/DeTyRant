extends CharacterBody3D

const GRAVITY        := 24.0
const WALK_SPEED     := 7.2
const SPRINT_SPEED   := 10.4
const CROUCH_SPEED   := 4.1
const ACCELERATION   := 42.0
const FRICTION       := 34.0
const AIR_CONTROL    := 8.0
const JUMP_SPEED     := 7.4
const STAND_CAPSULE_HEIGHT := 1.82
const CROUCH_CAPSULE_HEIGHT := 1.18
const STAND_EYE_HEIGHT := 1.58
const CROUCH_EYE_HEIGHT := 1.05

const WEAPONS := {
	"pistol": {
		"label": "Glock 17", "damage": 34.0, "headshot": 1.58,
		"fire_rate": 3.3, "magazine": 17, "reload": 1.15,
		"range": 60.0, "spread": 0.004, "move_spread": 0.012,
		"bloom": 0.022, "bloom_recover": 1.8, "recoil_pitch": 0.016, "recoil_yaw": 0.006,
		"auto": false, "sound": "pistol", "color": Color(1.0, 0.88, 0.55)
	},
	"smg": {
		"label": "H&K MP5", "damage": 18.0, "headshot": 1.35,
		"fire_rate": 13.0, "magazine": 30, "reload": 1.45,
		"range": 44.0, "spread": 0.009, "move_spread": 0.020,
		"bloom": 0.013, "bloom_recover": 2.25, "recoil_pitch": 0.006, "recoil_yaw": 0.010,
		"auto": true, "sound": "smg", "color": Color(0.58, 0.96, 1.0)
	},
	"rifle": {
		"label": "AK-47", "damage": 31.0, "headshot": 1.45,
		"fire_rate": 9.5, "magazine": 30, "reload": 1.82,
		"range": 82.0, "spread": 0.006, "move_spread": 0.016,
		"bloom": 0.017, "bloom_recover": 1.95, "recoil_pitch": 0.012, "recoil_yaw": 0.009,
		"auto": true, "sound": "rifle", "color": Color(1.0, 0.68, 0.34)
	},
}

const VIEWMODEL_SCENES := {
	"pistol": "res://assets/viewmodels/glock17_viewmodel.tscn",
	"smg":    "res://assets/viewmodels/mp5_viewmodel.tscn",
	"rifle":  "res://assets/viewmodels/ak47_viewmodel.tscn",
}
const VIEWMODEL_FALLBACK_SCENES := {
	"pistol": "res://assets/viewmodels/glock17_viewmodel.glb",
	"smg":    "res://assets/viewmodels/mp5_viewmodel.glb",
	"rifle":  "res://assets/viewmodels/ak47_viewmodel.glb",
}

var game: Node
var max_health     := 100.0
var health         := max_health
var alive          := true
var kills          := 0
var deaths         := 0
var current_weapon := "rifle"
var magazine       := 22
var reload_timer   := 0.0
var reload_total   := 0.0
var shot_cooldown  := 0.0
var spread_bloom   := 0.0
var hit_marker     := 0.0
var damage_flash   := 0.0
var mouse_sensitivity := 0.00205
var pitch          := 0.0
var recoil_offset  := Vector2.ZERO
var weapon_kick    := 0.0
var movement_input := Vector2.ZERO
var look_events    := 0
var crouching      := false

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
var footstep_distance   := 0.0
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
	reload_timer  = maxf(0.0, reload_timer  - delta)
	if reload_timer == 0.0:
		reload_total = 0.0
	hit_marker   = maxf(0.0, hit_marker   - delta * 2.8)
	damage_flash = maxf(0.0, damage_flash  - delta * 1.8)
	weapon_kick  = maxf(0.0, weapon_kick   - delta * 7.5)
	spread_bloom = maxf(0.0, spread_bloom  - WEAPONS[current_weapon]["bloom_recover"] * delta)

	_read_actions()
	_update_movement(delta)
	_update_footsteps(delta)
	_update_weapon_model(delta)
	_update_weapon_actions()


func reset_for_match(position: Vector3) -> void:
	kills  = 0
	deaths = 0
	respawn(position)


func respawn(position: Vector3) -> void:
	health = max_health
	alive  = true
	collision_shape.disabled = false
	if weapon_root:
		weapon_root.visible = true
	global_position = position
	velocity        = Vector3.ZERO
	pitch           = -0.02
	pitch_pivot.rotation.x = pitch
	crouching = false
	_set_crouch_height(STAND_CAPSULE_HEIGHT, STAND_EYE_HEIGHT)
	current_weapon  = "rifle"
	_reset_magazine()
	_configure_weapon_model()


func apply_damage(amount: float) -> void:
	if not alive:
		return
	health       = maxf(0.0, health - amount)
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
	if Input.is_action_pressed("move_left"):    movement_input.x -= 1.0
	if Input.is_action_pressed("move_right"):   movement_input.x += 1.0
	if Input.is_action_pressed("move_forward"): movement_input.y += 1.0
	if Input.is_action_pressed("move_back"):    movement_input.y -= 1.0
	movement_input = movement_input.normalized()


func _update_movement(delta: float) -> void:
	_update_crouch(delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.1
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_SPEED

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint") and movement_input.y > 0.0:
		speed = SPRINT_SPEED
	camera.fov = lerpf(camera.fov, 82.0 if speed == SPRINT_SPEED else 78.0, delta * 5.5)
	var forward := -global_transform.basis.z
	var right   :=  global_transform.basis.x
	var desired := (forward * movement_input.y + right * movement_input.x) * speed
	var accel   := ACCELERATION if is_on_floor() else AIR_CONTROL
	velocity.x = move_toward(velocity.x, desired.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired.z, accel * delta)
	if movement_input == Vector2.ZERO and is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
	move_and_slide()


func _update_crouch(delta: float) -> void:
	var wants_crouch := Input.is_action_pressed("crouch")
	crouching = wants_crouch or (crouching and not _can_stand())
	var target_height := CROUCH_CAPSULE_HEIGHT if crouching else STAND_CAPSULE_HEIGHT
	var target_eye := CROUCH_EYE_HEIGHT if crouching else STAND_EYE_HEIGHT
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = lerpf(capsule.height, target_height, delta * 14.0)
	collision_shape.position.y = capsule.height * 0.5
	pitch_pivot.position.y = lerpf(pitch_pivot.position.y, target_eye, delta * 14.0)


func _set_crouch_height(capsule_height: float, eye_height: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = capsule_height
	collision_shape.position.y = capsule.height * 0.5
	pitch_pivot.position.y = eye_height


func _can_stand() -> bool:
	var params := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.72, global_position + Vector3.UP * STAND_CAPSULE_HEIGHT, 1)
	params.exclude = [get_rid()]
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(params).is_empty()


func _update_footsteps(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or hspeed < 1.0 or movement_input == Vector2.ZERO:
		footstep_distance = minf(footstep_distance, 0.35)
		return
	footstep_distance += hspeed * delta
	var stride := 1.65 if Input.is_action_pressed("sprint") else 2.15
	if footstep_distance < stride:
		return
	footstep_distance = 0.0
	if game and game.has_method("play_footstep"):
		game.play_footstep(global_position + Vector3.UP * 0.08, _surface_underfoot(), clampf(hspeed / SPRINT_SPEED, 0.35, 1.0))


func _surface_underfoot() -> String:
	var space  := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.35, global_position + Vector3.DOWN * 1.25, 1)
	params.exclude = [get_rid()]
	params.collide_with_areas  = false
	params.collide_with_bodies = true
	var hit := space.intersect_ray(params)
	if hit.is_empty() or not hit.has("collider"):
		return "concrete"
	var collider = hit["collider"]
	if collider is Node and collider.has_meta("surface"):
		return String(collider.get_meta("surface"))
	return "concrete"


func _update_weapon_actions() -> void:
	if Input.is_action_just_pressed("weapon_1"): _switch_weapon("pistol")
	if Input.is_action_just_pressed("weapon_2"): _switch_weapon("smg")
	if Input.is_action_just_pressed("weapon_3"): _switch_weapon("rifle")
	if Input.is_action_just_pressed("reload"):   _start_reload()
	if reload_timer == 0.0 and magazine == 0:    _start_reload()
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
	magazine     -= 1
	shot_cooldown = 1.0 / weapon["fire_rate"]
	spread_bloom  = minf(0.12, spread_bloom + weapon["bloom"])
	weapon_kick   = minf(0.17, weapon_kick + 0.11)
	_play_viewmodel_animation("fire")
	pitch = clampf(pitch - weapon["recoil_pitch"], -1.22, 1.1)
	pitch_pivot.rotation.x = pitch
	rotate_y(randf_range(-weapon["recoil_yaw"], weapon["recoil_yaw"]))
	var origin    := camera.global_position
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
	var weapon_id      := current_weapon
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
	reload_timer   = 0.0
	reload_total   = 0.0
	spread_bloom  *= 0.35
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
	collision_shape.shape      = capsule
	collision_shape.position.y = 0.92
	add_child(collision_shape)


func _add_camera() -> void:
	pitch_pivot          = Node3D.new()
	pitch_pivot.name     = "PitchPivot"
	pitch_pivot.position.y = 1.58
	add_child(pitch_pivot)
	camera          = Camera3D.new()
	camera.name     = "Camera"
	camera.fov      = 78.0
	camera.near     = 0.035
	camera.far      = 240.0
	camera.current  = true
	pitch_pivot.add_child(camera)


func _add_weapon_model() -> void:
	weapon_root      = Node3D.new()
	weapon_root.name = "ViewWeapon"
	camera.add_child(weapon_root)
	_configure_weapon_model()


func _mount_viewmodel(id: String) -> void:
	if active_viewmodel_id == id and active_viewmodel:
		return
	for child in weapon_root.get_children():
		child.queue_free()
	weapon_parts.clear()
	ammo_display           = null
	viewmodel_animation_player = null
	muzzle_socket          = null
	active_viewmodel_id    = id

	var scene := _load_viewmodel_scene(id)
	if scene:
		active_viewmodel = scene.instantiate() as Node3D
		if active_viewmodel:
			active_viewmodel.name = "%sImportedViewModel" % id.capitalize()
			weapon_root.add_child(active_viewmodel)
			_bind_imported_viewmodel()
	else:
		active_viewmodel      = Node3D.new()
		active_viewmodel.name = "%sDevViewModelFallback" % id.capitalize()
		weapon_root.add_child(active_viewmodel)
		_build_dev_viewmodel(id)

	if not muzzle_socket:
		muzzle_socket          = Node3D.new()
		muzzle_socket.name     = "MuzzleSocket"
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


# ──────────────────────────────────────────────────────────────────────────────
#  DISPATCH — builds the right fallback viewmodel for each weapon
# ──────────────────────────────────────────────────────────────────────────────
func _build_dev_viewmodel(id: String) -> void:
	match id:
		"pistol": _build_glock17()
		"smg":    _build_mp5()
		"rifle":  _build_ak47()
		_:        _build_ak47()


func _configure_weapon_model() -> void:
	_mount_viewmodel(current_weapon)
	match current_weapon:
		"pistol":
			weapon_base_position = Vector3(0.26, -0.36, -0.58)
			weapon_root.position = weapon_base_position
			weapon_root.scale    = Vector3(0.84, 0.88, 0.78)
		"smg":
			weapon_base_position = Vector3(0.30, -0.34, -0.74)
			weapon_root.position = weapon_base_position
			weapon_root.scale    = Vector3(0.92, 0.96, 0.88)
		_:
			weapon_base_position = Vector3(0.34, -0.33, -0.84)
			weapon_root.position = weapon_base_position
			weapon_root.scale    = Vector3.ONE


func _update_weapon_model(delta: float) -> void:
	var move_amount  := clampf(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED, 0.0, 1.0)
	var bob          := sin(Time.get_ticks_msec() * 0.012) * move_amount * 0.022
	var sway         := movement_input.x * 0.025
	var reload_alpha := 0.0
	if reload_timer > 0.0 and reload_total > 0.0:
		reload_alpha = sin((1.0 - reload_timer / reload_total) * PI)
	var target_y := weapon_base_position.y + bob + weapon_kick * 0.1 - reload_alpha * 0.18
	weapon_root.position.y = lerpf(weapon_root.position.y, target_y, delta * 12.0)
	weapon_root.position.x = lerpf(weapon_root.position.x, weapon_base_position.x + sway, delta * 8.0)
	weapon_root.rotation_degrees = Vector3(
		-2.0 + weapon_kick * 13.0 + reload_alpha * 14.0,
		-5.0 + weapon_kick *  5.0 - reload_alpha * 10.0,
		-movement_input.x * 2.0 - weapon_kick * 7.0 + reload_alpha * 18.0)
	if ammo_display:
		ammo_display.text     = "%02d" % magazine
		ammo_display.modulate = WEAPONS[current_weapon]["color"]


func muzzle_position() -> Vector3:
	if muzzle_socket and is_instance_valid(muzzle_socket):
		return muzzle_socket.global_position
	return camera.global_position \
		- camera.global_transform.basis.z * 0.7 \
		+ camera.global_transform.basis.x * 0.25 \
		- camera.global_transform.basis.y * 0.2


func _play_viewmodel_animation(action: String) -> void:
	if not viewmodel_animation_player:
		return
	var candidates := {
		"equip":  ["equip",  "draw",   "ready",       "idle"],
		"fire":   ["fire",   "shoot",  "shot",        "attack"],
		"reload": ["reload", "reload_full", "mag_reload"],
		"idle":   ["idle",   "weapon_idle"],
	}
	if not candidates.has(action):
		return
	for anim_name in candidates[action]:
		if viewmodel_animation_player.has_animation(anim_name):
			viewmodel_animation_player.play(anim_name)
			return


# ──────────────────────────────────────────────────────────────────────────────
#  GLOCK 17  (9mm polymer-frame pistol)
# ──────────────────────────────────────────────────────────────────────────────
func _build_glock17() -> void:
	# Materials
	var poly   := _wm(Color(0.058, 0.062, 0.060), Color(0,0,0), 0.0,  0.06, 0.70)  # matte polymer frame
	var slide  := _wm(Color(0.115, 0.118, 0.112), Color(0.008,0.009,0.007), 0.02, 0.88, 0.18)  # nitride slide
	var barrel := _wm(Color(0.155, 0.158, 0.148), Color(0.010,0.012,0.008), 0.02, 0.84, 0.15)  # match barrel
	var blk    := _wm(Color(0.022, 0.022, 0.020), Color(0,0,0), 0.0, 0.12, 0.58)
	var tritium:= _wm(Color(0.38, 0.98, 0.50),    Color(0.38, 0.98, 0.50), 2.0, 0.0, 0.12)
	var glove  := _wm(Color(0.040, 0.045, 0.052), Color(0,0,0), 0.0, 0.12, 0.68)
	var sleeve := _wm(Color(0.145, 0.192, 0.225), Color(0.01,0.03,0.05), 0.03, 0.18, 0.58)
	var poly_d := _wm(Color(0.038, 0.040, 0.038), Color(0,0,0), 0.0, 0.05, 0.72)  # slightly darker poly detail

	# ── FRAME (lower receiver + grip) ────────────────────────────────────
	_wb("Frame",        Vector3(0.00, -0.065,-0.178), Vector3(0.318, 0.305, 0.490), poly)
	_wb("GripBody",     Vector3(0.00, -0.278, 0.042), Vector3(0.288, 0.302, 0.350), poly)
	_wb("Backstrap",    Vector3(0.00, -0.272, 0.215), Vector3(0.248, 0.286, 0.052), slide)
	_wb("Beavertail",   Vector3(0.00,  0.018, 0.190), Vector3(0.265, 0.058, 0.062), poly, Vector3(14,0,0))

	# Grip texture — vertical stippling columns
	for i in range(6):
		var z := -0.065 + i * 0.066
		_wb("StipL%d" % i, Vector3(-0.162,-0.278, z), Vector3(0.008, 0.268, 0.042), poly_d)
		_wb("StipR%d" % i, Vector3( 0.162,-0.278, z), Vector3(0.008, 0.268, 0.042), poly_d)
	# Finger grooves
	for i in range(3):
		_wb("FingerGroove%d" % i, Vector3(0.0,-0.185 - i*0.082,-0.168), Vector3(0.308, 0.040, 0.044), poly_d)
	# Palm swell sides
	_wb("SwellL", Vector3(-0.158,-0.258, 0.052), Vector3(0.016, 0.220, 0.280), poly_d)
	_wb("SwellR", Vector3( 0.158,-0.258, 0.052), Vector3(0.016, 0.220, 0.280), poly_d)

	# ── SLIDE ─────────────────────────────────────────────────────────────
	_wb("Slide",        Vector3(0.00,  0.068,-0.218), Vector3(0.298, 0.162, 0.665), slide)
	_wb("SlideTop",     Vector3(0.00,  0.150,-0.218), Vector3(0.224, 0.025, 0.620), slide)
	# Ejection port (left side, creates visual depth)
	_wb("EjPort",       Vector3(-0.158, 0.078,-0.058), Vector3(0.016, 0.092, 0.205), poly)
	# Rear serrations (6 cuts, right-slanted for purchase)
	for i in range(7):
		_wb("RSerr%d" % i, Vector3(0.0, 0.068, 0.118 + i*0.028), Vector3(0.310, 0.166, 0.010), blk)
	# Front serrations (suppressor-cut, Gen 5-style)
	for i in range(5):
		_wb("FSerr%d" % i, Vector3(0.0, 0.068,-0.355 - i*0.026), Vector3(0.310, 0.166, 0.010), blk)
	# Loaded chamber indicator nub
	_wb("ChambInd",     Vector3( 0.148, 0.148,-0.052), Vector3(0.012, 0.022, 0.028), blk)

	# ── BARREL ────────────────────────────────────────────────────────────
	_wc("Barrel",       Vector3(0.0,  0.042,-0.355), 0.032, 0.600, barrel, Vector3(90,0,0))
	_wc("MuzzleCrown",  Vector3(0.0,  0.042,-0.645), 0.038, 0.042, barrel, Vector3(90,0,0))
	_wb("BarrelHood",   Vector3(0.0,  0.042,-0.642), Vector3(0.076, 0.070, 0.038), barrel)

	# ── TRIGGER GUARD ─────────────────────────────────────────────────────
	_wb("TGBot",        Vector3(0.00,-0.128,-0.195), Vector3(0.258, 0.032, 0.465), poly)
	_wb("TGL",          Vector3(-0.128,-0.095,-0.195), Vector3(0.032, 0.076, 0.422), poly)
	_wb("TGR",          Vector3( 0.128,-0.095,-0.195), Vector3(0.032, 0.076, 0.422), poly)
	_wb("TGFront",      Vector3(0.00,-0.088,-0.395), Vector3(0.265, 0.082, 0.038), poly)
	# Front underrail (Picatinny)
	_wb("PicRail",      Vector3(0.00,-0.090,-0.298), Vector3(0.265, 0.042, 0.305), poly)
	for i in range(5):
		_wb("RailCross%d" % i, Vector3(0.0,-0.078,-0.195 - i*0.058), Vector3(0.270, 0.015, 0.012), blk)

	# ── TRIGGER ───────────────────────────────────────────────────────────
	_wb("TrigBlade",    Vector3(0.00,-0.095,-0.222), Vector3(0.038, 0.132, 0.040), slide, Vector3(-22,0,0))
	_wb("TrigSafety",   Vector3(0.00,-0.085,-0.212), Vector3(0.018, 0.048, 0.022), poly_d)

	# ── SIGHTS ────────────────────────────────────────────────────────────
	# Rear — u-notch with two tritium dots
	_wb("RearBase",     Vector3(0.00, 0.162, 0.118), Vector3(0.265, 0.056, 0.065), blk)
	_wb("RearWingL",    Vector3(-0.065, 0.168, 0.142), Vector3(0.072, 0.078, 0.040), blk)
	_wb("RearWingR",    Vector3( 0.065, 0.168, 0.142), Vector3(0.072, 0.078, 0.040), blk)
	_wb("RearDotL",     Vector3(-0.042, 0.180, 0.146), Vector3(0.014, 0.018, 0.008), tritium)
	_wb("RearDotR",     Vector3( 0.042, 0.180, 0.146), Vector3(0.014, 0.018, 0.008), tritium)
	# Front — blade post with tritium
	_wb("FrontBase",    Vector3(0.00, 0.160,-0.602), Vector3(0.212, 0.040, 0.058), blk)
	_wb("FrontPost",    Vector3(0.00, 0.180,-0.605), Vector3(0.055, 0.072, 0.040), blk)
	_wb("FrontDot",     Vector3(0.00, 0.194,-0.606), Vector3(0.018, 0.020, 0.010), tritium)

	# ── MUZZLE SOCKET ─────────────────────────────────────────────────────
	muzzle_socket          = Node3D.new()
	muzzle_socket.name     = "MuzzleSocket"
	muzzle_socket.position = Vector3(0.0, 0.042, -0.672)
	active_viewmodel.add_child(muzzle_socket)

	# ── HANDS / ARMS ──────────────────────────────────────────────────────
	# Right strong hand gripping the frame
	_wb("RPalm",        Vector3( 0.158,-0.285, 0.082), Vector3(0.185, 0.105, 0.255), glove)
	_wb("RThumb",       Vector3(-0.145,-0.260, 0.022), Vector3(0.062, 0.088, 0.222), glove)
	_wb("RThumbKnuckle",Vector3(-0.145,-0.242, 0.120), Vector3(0.058, 0.042, 0.058), glove)
	_wb("RIndexFinger", Vector3(-0.130,-0.108,-0.198), Vector3(0.045, 0.068, 0.048), glove)
	_wb("RSleeve",      Vector3( 0.228,-0.405, 0.312), Vector3(0.185, 0.152, 0.402), sleeve)
	_wb("RSleeveElbow", Vector3( 0.242,-0.462, 0.545), Vector3(0.185, 0.145, 0.245), sleeve, Vector3(-10,0,0))
	# Left support hand beneath grip
	_wb("LSuppPalm",    Vector3(-0.138,-0.328, 0.012), Vector3(0.165, 0.098, 0.298), glove)
	_wb("LThumb",       Vector3( 0.132,-0.310, 0.012), Vector3(0.055, 0.075, 0.195), glove)
	_wb("LSleeve",      Vector3(-0.218,-0.425,-0.172), Vector3(0.168, 0.142, 0.385), sleeve, Vector3(0,0,-8))

	# ── AMMO DISPLAY ──────────────────────────────────────────────────────
	_build_ammo_display(Vector3(0.152, 0.115, 0.145), Vector3(0,-22,0))


# ──────────────────────────────────────────────────────────────────────────────
#  H&K MP5  (9mm roller-delayed SMG)
# ──────────────────────────────────────────────────────────────────────────────
func _build_mp5() -> void:
	var steel  := _wm(Color(0.095, 0.098, 0.092), Color(0.005,0.006,0.004), 0.01, 0.86, 0.18)  # blued steel
	var poly   := _wm(Color(0.068, 0.072, 0.068), Color(0,0,0), 0.0,  0.08, 0.64)  # polymer furniture
	var worn   := _wm(Color(0.440, 0.435, 0.415), Color(0.012,0.012,0.010), 0.02, 0.72, 0.28)  # edge wear
	var blk    := _wm(Color(0.022, 0.022, 0.020), Color(0,0,0), 0.0, 0.10, 0.62)
	var glove  := _wm(Color(0.040, 0.045, 0.052), Color(0,0,0), 0.0, 0.12, 0.68)
	var sleeve := _wm(Color(0.145, 0.192, 0.225), Color(0.01,0.03,0.05), 0.03, 0.18, 0.58)
	var tritium:= _wm(Color(0.38, 0.98, 0.50), Color(0.38, 0.98, 0.50), 2.0, 0.0, 0.12)

	# ── RECEIVER (stamped steel, compact) ─────────────────────────────────
	_wb("Receiver",     Vector3(0.00, 0.00, 0.02),  Vector3(0.308, 0.172, 0.575), steel)
	_wb("DustCover",    Vector3(0.00, 0.105,-0.015), Vector3(0.258, 0.065, 0.495), worn, Vector3(-1.5,0,0))
	_wb("CockingSlot",  Vector3(-0.162, 0.035, 0.05), Vector3(0.018, 0.058, 0.350), blk)
	# H&K slap-style cocking handle (left side)
	_wb("CockHandle",   Vector3(-0.218, 0.055,-0.020), Vector3(0.108, 0.034, 0.058), worn, Vector3(0,0,-8))
	_wb("CockKnob",     Vector3(-0.248, 0.052,-0.016), Vector3(0.055, 0.030, 0.040), steel)

	# ── BARREL (shorter than rifle — ~230mm from receiver face) ───────────
	_wc("Barrel",       Vector3(0.00, 0.038,-0.450), 0.022, 0.480, steel, Vector3(90,0,0))
	_wb("BarrelJacket", Vector3(0.00, 0.038,-0.380), Vector3(0.068, 0.068, 0.320), steel) # sight block / jacket
	_wb("FrontSightHood",Vector3(0.00, 0.114,-0.618), Vector3(0.065, 0.042, 0.028), steel)
	_wb("FrontPost",    Vector3(0.00, 0.132,-0.618), Vector3(0.018, 0.068, 0.018), worn)
	_wb("FrontDot",     Vector3(0.00, 0.148,-0.619), Vector3(0.010, 0.012, 0.010), tritium)

	# ── HANDGUARD (slim polymer tri-rail style) ────────────────────────────
	_wb("Handguard",    Vector3(0.00,-0.042,-0.375), Vector3(0.292, 0.118, 0.340), poly, Vector3(-1,0,0))
	_wb("HandguardTop", Vector3(0.00, 0.088,-0.375), Vector3(0.238, 0.060, 0.328), poly, Vector3(-1,0,0))
	# Ventilation slats
	for i in range(5):
		_wb("VentL%d" % i, Vector3(-0.150,-0.042,-0.245 - i*0.055), Vector3(0.022, 0.088, 0.028), blk)
		_wb("VentR%d" % i, Vector3( 0.150,-0.042,-0.245 - i*0.055), Vector3(0.022, 0.088, 0.028), blk)

	# ── TRIGGER GROUP ──────────────────────────────────────────────────────
	_wb("TriggerHousing",Vector3(0.00,-0.158, 0.082), Vector3(0.258, 0.185, 0.372), poly)
	_wb("TrigGuardBot", Vector3(0.00,-0.248, 0.062), Vector3(0.220, 0.030, 0.355), poly)
	_wb("TrigGuardL",   Vector3(-0.112,-0.212, 0.062), Vector3(0.030, 0.075, 0.310), poly)
	_wb("TrigGuardR",   Vector3( 0.112,-0.212, 0.062), Vector3(0.030, 0.075, 0.310), poly)
	_wb("TrigBlade",    Vector3(0.00,-0.195, 0.045), Vector3(0.035, 0.115, 0.038), steel, Vector3(-18,0,0))
	# Selector lever (left side)
	_wb("Selector",     Vector3(-0.162,-0.022, 0.202), Vector3(0.018, 0.055, 0.085), steel)
	_wb("SelectorKnob", Vector3(-0.172,-0.010, 0.242), Vector3(0.024, 0.038, 0.032), worn)

	# ── PISTOL GRIP (H&K style, slightly back-angled) ─────────────────────
	_wb("PistolGrip",   Vector3(0.00,-0.265, 0.235), Vector3(0.265, 0.308, 0.148), poly, Vector3(-14,0,0))
	_wb("GripCap",      Vector3(0.00,-0.388, 0.290), Vector3(0.240, 0.038, 0.145), steel, Vector3(-14,0,0))
	# Grip stippling
	for i in range(4):
		_wb("GripSL%d" % i, Vector3(-0.135,-0.270 + i*0.062, 0.222), Vector3(0.010, 0.048, 0.135), blk, Vector3(-14,0,0))
		_wb("GripSR%d" % i, Vector3( 0.135,-0.270 + i*0.062, 0.222), Vector3(0.010, 0.048, 0.135), blk, Vector3(-14,0,0))

	# ── MAGAZINE (30-round curved, steel body) ─────────────────────────────
	for i in range(8):
		var rz := 0.065 - i * 0.034
		var ry := -0.225 - i * 0.015
		var rr := Vector3(-5 - i * 1.8, 0, 0)
		var rw := 0.198 - i * 0.003
		_wb("Mag%d" % i, Vector3(0.0, ry, rz), Vector3(rw, 0.098, 0.052), steel, rr)
	_wb("MagFloor",     Vector3(0.0,-0.368,-0.228), Vector3(0.178, 0.032, 0.082), worn, Vector3(-20,0,0))
	_wb("MagCatch",     Vector3(0.0,-0.152, 0.162), Vector3(0.058, 0.055, 0.032), steel)

	# ── REAR SIGHT (H&K drum / diopter style) ─────────────────────────────
	_wc("SightDrum",    Vector3(0.0, 0.148, 0.155), 0.055, 0.038, steel, Vector3(0,0,90))
	_wb("SightBase",    Vector3(0.0, 0.120, 0.155), Vector3(0.155, 0.022, 0.062), steel)
	_wb("SightProtL",   Vector3(-0.082, 0.148, 0.155), Vector3(0.018, 0.082, 0.065), steel)
	_wb("SightProtR",   Vector3( 0.082, 0.148, 0.155), Vector3(0.018, 0.082, 0.065), steel)

	# ── STOCK (MP5A3 retractable, extended) ────────────────────────────────
	_wb("StockTubeL",   Vector3(-0.072, 0.008, 0.408), Vector3(0.022, 0.022, 0.445), steel)
	_wb("StockTubeR",   Vector3( 0.072, 0.008, 0.408), Vector3(0.022, 0.022, 0.445), steel)
	_wb("StockBarL",    Vector3(-0.072, 0.008, 0.580), Vector3(0.022, 0.092, 0.080), steel) # rear bar connects tubes
	_wb("StockBarR",    Vector3( 0.072, 0.008, 0.580), Vector3(0.022, 0.092, 0.080), steel)
	_wb("StockCrossbar",Vector3(0.000, 0.008, 0.595), Vector3(0.172, 0.022, 0.022), steel)
	_wb("ButtPlate",    Vector3(0.000, 0.008, 0.620), Vector3(0.172, 0.145, 0.048), poly)
	# Stock release latch
	_wb("StockLatch",   Vector3(0.082, 0.048, 0.295), Vector3(0.025, 0.038, 0.042), worn)

	# ── MUZZLE SOCKET ─────────────────────────────────────────────────────
	muzzle_socket          = Node3D.new()
	muzzle_socket.name     = "MuzzleSocket"
	muzzle_socket.position = Vector3(0.0, 0.038, -0.698)
	active_viewmodel.add_child(muzzle_socket)

	# ── HANDS ─────────────────────────────────────────────────────────────
	_wb("RightPalm",    Vector3( 0.148,-0.268, 0.255), Vector3(0.175, 0.105, 0.195), glove)
	_wb("RThumb",       Vector3(-0.138,-0.245, 0.218), Vector3(0.058, 0.082, 0.185), glove)
	_wb("RSleeve",      Vector3( 0.225,-0.395, 0.435), Vector3(0.178, 0.148, 0.405), sleeve)
	_wb("LeftPalm",     Vector3(-0.125,-0.042,-0.332), Vector3(0.148, 0.098, 0.195), glove)
	_wb("LThumb",       Vector3( 0.128,-0.042,-0.315), Vector3(0.052, 0.072, 0.178), glove)
	_wb("LSleeve",      Vector3(-0.215,-0.322,-0.188), Vector3(0.165, 0.138, 0.565), sleeve, Vector3(0,0,-11))

	_build_ammo_display(Vector3(0.145, 0.125, 0.145), Vector3(0,-20,0))


# ──────────────────────────────────────────────────────────────────────────────
#  AK-47  (7.62×39mm assault rifle — enhanced from original)
# ──────────────────────────────────────────────────────────────────────────────
func _build_ak47() -> void:
	var steel  := _wm(Color(0.100, 0.105, 0.095), Color(0.008,0.008,0.006), 0.02, 0.74, 0.33)
	var blued  := _wm(Color(0.035, 0.039, 0.041), Color(0.002,0.004,0.006), 0.01, 0.82, 0.22)
	var worn   := _wm(Color(0.480, 0.470, 0.420), Color(0.015,0.014,0.012), 0.02, 0.72, 0.26)
	var bake   := _wm(Color(0.480, 0.200, 0.075), Color(0.035,0.012,0.002), 0.02, 0.05, 0.45)  # bakelite mag
	var wood   := _wm(Color(0.460, 0.220, 0.095), Color(0.040,0.018,0.004), 0.025, 0.02, 0.50)
	var dwood  := _wm(Color(0.240, 0.110, 0.045), Color(0.018,0.006,0.002), 0.01,  0.02, 0.58)
	var glove  := _wm(Color(0.045, 0.052, 0.058), Color(0,0,0), 0.0, 0.12, 0.64)
	var sleeve := _wm(Color(0.172, 0.222, 0.262), Color(0.01,0.04,0.06), 0.04, 0.18, 0.56)

	# ── RECEIVER ──────────────────────────────────────────────────────────
	_wb("StampedReceiver",   Vector3(0.00, 0.00, 0.04),  Vector3(0.310, 0.170, 0.580), steel)
	_wb("DustCover",         Vector3(0.00, 0.100,-0.010), Vector3(0.252, 0.065, 0.462), worn, Vector3(-2,0,0))
	_wb("RearTrunnion",      Vector3(0.00,-0.010, 0.360), Vector3(0.302, 0.162, 0.112), blued)
	_wb("BoltCarrierSlot",   Vector3(-0.164, 0.035, 0.050), Vector3(0.018, 0.060, 0.345), blued)
	_wb("ChargingHandle",    Vector3(-0.210, 0.055,-0.018), Vector3(0.112, 0.035, 0.055), worn, Vector3(0,0,-8))
	_wb("TriggerGuard",      Vector3( 0.020,-0.155, 0.125), Vector3(0.172, 0.030, 0.182), blued, Vector3(-8,0,0))
	_wb("Trigger",           Vector3( 0.020,-0.185, 0.080), Vector3(0.035, 0.090, 0.035), blued, Vector3(-22,0,0))
	_wb("SelectorLever",     Vector3(-0.162,-0.025, 0.148), Vector3(0.018, 0.052, 0.178), worn)
	_wb("SelectorKnob",      Vector3(-0.172,-0.010, 0.228), Vector3(0.025, 0.038, 0.032), worn)

	# ── STOCK (wood, full-stock) ───────────────────────────────────────────
	_wb("WoodStockNeck",     Vector3(0.00,-0.035, 0.448), Vector3(0.210, 0.130, 0.202), wood, Vector3(4,0,0))
	_wb("WoodStock",         Vector3(0.00,-0.060, 0.660), Vector3(0.280, 0.182, 0.302), wood, Vector3(8,0,0))
	_wb("StockButtPlate",    Vector3(0.00,-0.065, 0.835), Vector3(0.302, 0.202, 0.045), blued, Vector3(8,0,0))
	_wb("StockScrew",        Vector3(0.00,-0.062, 0.798), Vector3(0.035, 0.038, 0.015), worn, Vector3(8,0,0))

	# ── GRIP ──────────────────────────────────────────────────────────────
	_wb("WoodPistolGrip",    Vector3(0.045,-0.245, 0.222), Vector3(0.135, 0.312, 0.132), wood, Vector3(-13,0,6))
	_wb("GripShadow",        Vector3(0.047,-0.245, 0.155), Vector3(0.142, 0.026, 0.022), dwood,Vector3(-13,0,6))
	_wb("GripScrew",         Vector3(0.045,-0.248, 0.188), Vector3(0.008, 0.012, 0.012), worn, Vector3(-13,0,6))

	# ── HANDGUARDS (wood) ─────────────────────────────────────────────────
	_wb("WoodLowerHandguard",Vector3(0.00,-0.040,-0.285), Vector3(0.312, 0.132, 0.382), wood, Vector3(-2,0,0))
	_wb("WoodUpperHandguard",Vector3(0.00, 0.090,-0.305), Vector3(0.242, 0.075, 0.342), wood, Vector3(-2,0,0))
	# Handguard grooves
	for i in range(6):
		_wb("HGrvL%d" % i, Vector3(-0.158,-0.037,-0.425 + i*0.062), Vector3(0.018, 0.100, 0.018), dwood)
		_wb("HGrvR%d" % i, Vector3( 0.158,-0.037,-0.425 + i*0.062), Vector3(0.018, 0.100, 0.018), dwood)

	# ── BARREL ASSEMBLY ───────────────────────────────────────────────────
	_wc("Barrel",            Vector3(0.00, 0.038,-0.610), 0.024, 0.740, blued, Vector3(90,0,0))
	_wc("GasTube",           Vector3(0.00, 0.118,-0.500), 0.030, 0.480, steel, Vector3(90,0,0))
	_wb("GasBlock",          Vector3(0.00, 0.078,-0.498), Vector3(0.058, 0.072, 0.055), blued)
	_wb("GasKey",            Vector3(0.00, 0.108,-0.498), Vector3(0.032, 0.040, 0.032), blued)
	_wb("FrontSightTower",   Vector3(0.00, 0.105,-0.840), Vector3(0.132, 0.192, 0.045), blued)
	_wb("FrontSightPost",    Vector3(0.00, 0.226,-0.840), Vector3(0.026, 0.080, 0.020), worn)
	_wb("FrontSightGuardL",  Vector3(-0.065, 0.148,-0.838), Vector3(0.018, 0.115, 0.045), blued)
	_wb("FrontSightGuardR",  Vector3( 0.065, 0.148,-0.838), Vector3(0.018, 0.115, 0.045), blued)
	_wb("RearSightLeaf",     Vector3(0.00, 0.188,-0.095), Vector3(0.162, 0.026, 0.152), blued, Vector3(-8,0,0))
	_wb("RearSightFlipper",  Vector3(0.00, 0.202,-0.068), Vector3(0.055, 0.045, 0.022), worn, Vector3(-8,0,0))
	_wb("MuzzleDevice",      Vector3(0.00, 0.038,-0.990), Vector3(0.075, 0.075, 0.120), blued)
	# Cleaning rod under barrel
	_wc("CleaningRod",       Vector3(0.00,-0.025,-0.522), 0.010, 0.665, steel, Vector3(90,0,0))

	# ── MAGAZINE (bakelite, curved 30-round) ───────────────────────────────
	for i in range(8):
		var mz := 0.018 - i * 0.042
		var my := -0.235 - i * 0.014
		var mr := Vector3(-7 - i * 2.2, 0, 0)
		var mw := 0.205 - i * 0.004
		_wb("Mag%d" % i, Vector3(0.0, my, mz), Vector3(mw, 0.105, 0.055), bake, mr)
	_wb("MagFloorPlate",     Vector3(0.00,-0.368,-0.258), Vector3(0.188, 0.035, 0.092), blued, Vector3(-22,0,0))
	# Witness holes
	for i in range(3):
		_wb("MagWin%d" % i, Vector3(-0.106,-0.278 + i*0.055,-0.105 - i*0.032), Vector3(0.012, 0.028, 0.035), dwood)

	# ── MUZZLE SOCKET ─────────────────────────────────────────────────────
	muzzle_socket          = Node3D.new()
	muzzle_socket.name     = "MuzzleSocket"
	muzzle_socket.position = Vector3(0.0, 0.038, -1.065)
	active_viewmodel.add_child(muzzle_socket)

	# ── HANDS ─────────────────────────────────────────────────────────────
	_wb("RightGlove",  Vector3( 0.162,-0.248, 0.132), Vector3(0.162, 0.108, 0.192), glove, Vector3(-5,0,9))
	_wb("LeftGlove",   Vector3(-0.128,-0.178,-0.332), Vector3(0.152, 0.108, 0.202), glove)
	_wb("SuppSleeve",  Vector3(-0.222,-0.322,-0.182), Vector3(0.162, 0.132, 0.582), sleeve, Vector3(0,0,-13))
	_wb("TrigSleeve",  Vector3( 0.232,-0.372, 0.282), Vector3(0.162, 0.132, 0.422), sleeve, Vector3(0,0,16))

	_build_ammo_display(Vector3(0.145, 0.132, 0.155), Vector3(0,-23,0))


func _build_ammo_display(pos: Vector3, rot: Vector3) -> void:
	ammo_display                  = Label3D.new()
	ammo_display.name             = "AmmoDisplay"
	ammo_display.text             = "%02d" % magazine
	ammo_display.font_size        = 20
	ammo_display.pixel_size       = 0.004
	ammo_display.modulate         = Color(1.0, 0.72, 0.36)
	ammo_display.outline_size     = 2
	ammo_display.outline_modulate = Color(0.0, 0.03, 0.05, 0.9)
	ammo_display.position         = pos
	ammo_display.rotation_degrees = rot
	active_viewmodel.add_child(ammo_display)


# ── Viewmodel geometry helpers ────────────────────────────────────────────────

func _wb(node_name: String, position: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mi   := MeshInstance3D.new()
	mi.name   = node_name
	var mesh  := BoxMesh.new()
	mesh.size  = size
	mi.mesh    = mesh
	mi.position         = position
	mi.rotation_degrees  = rotation
	mi.material_override = material
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	active_viewmodel.add_child(mi)
	weapon_parts.append(mi)
	return mi


func _wc(node_name: String, position: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mi   := MeshInstance3D.new()
	mi.name   = node_name
	var mesh  := CylinderMesh.new()
	mesh.top_radius    = radius
	mesh.bottom_radius = radius
	mesh.height        = height
	mesh.radial_segments = 24
	mi.mesh    = mesh
	mi.position         = position
	mi.rotation_degrees  = rotation
	mi.material_override = material
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	active_viewmodel.add_child(mi)
	weapon_parts.append(mi)
	return mi


func _wm(albedo: Color, emission: Color, energy: float, metallic := 0.28, roughness := 0.28) -> StandardMaterial3D:
	var material                    := StandardMaterial3D.new()
	material.albedo_color            = albedo
	material.emission_enabled        = energy > 0.0
	material.emission                = emission
	material.emission_energy_multiplier = energy
	material.metallic                = metallic
	material.roughness               = roughness
	if albedo.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


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
