extends CharacterBody3D

const MAX_HEALTH := 100.0
const SPEED := 5.6
const ACCEL := 18.0
const GRAVITY := 24.0
const WORLD_LAYER := 1
const HITBOX_LAYER := 4
const CHARACTER_SCENES := [
	"res://assets/characters/combatant.tscn",
	"res://assets/characters/combatant.glb",
]

const ANIMATION_ALIASES := {
	"idle":    ["idle", "combat_idle", "rifle_idle"],
	"run":     ["run",  "jog",  "locomotion", "rifle_run"],
	"shoot":   ["shoot", "fire", "rifle_fire", "attack"],
	"hit":     ["hit",  "damage", "flinch"],
	"death":   ["death", "die", "knockdown"],
	"respawn": ["respawn", "spawn", "stand_up", "idle"],
}

var game: Node
var callsign := "Synthetic"
var materials := {}
var nav_points: Array = []
var health := MAX_HEALTH
var alive := true
var respawn_timer := 0.0
var target_point := Vector3.ZERO
var shoot_timer := 0.0
var think_timer := 0.0
var strafe_dir := 1.0
var flash := 0.0
var visual_root: Node3D
var animation_player: AnimationPlayer
var animation_state := ""
var body_mesh: MeshInstance3D
var visor_mesh: MeshInstance3D   # tactical goggles — still flash on hit
var hit_areas: Array[Area3D] = []
var collision_shape: CollisionShape3D
var _bob_offset := 0.0            # per-instance idle breath offset


func _ready() -> void:
	_bob_offset = randf_range(0.0, TAU)
	_add_collision()
	_add_mesh()
	_add_hitbox("body", Vector3(0, 1.05, 0), Vector3(0.95, 1.25, 0.72), 1.0)
	_add_hitbox("head",  Vector3(0, 1.84, 0), Vector3(0.52, 0.44, 0.52), 1.55)
	if nav_points.size() > 0:
		target_point = nav_points.pick_random()


func tick_bot(delta: float, player) -> void:
	if not alive:
		respawn_timer = maxf(0.0, respawn_timer - delta)
		if respawn_timer == 0.0:
			respawn(game.bot_respawn_position(self))
		return

	flash        = maxf(0.0, flash       - delta * 5.0)
	shoot_timer  = maxf(0.0, shoot_timer - delta)
	think_timer  = maxf(0.0, think_timer - delta)

	# Goggle lens energy spikes on hit
	if visor_mesh and visor_mesh.material_override:
		visor_mesh.material_override.emission_energy_multiplier = 3.4 if flash > 0.0 else 1.1

	var to_player: Vector3 = player.global_position - global_position
	var distance: float    = to_player.length()
	var visible            := _has_line_of_sight(player)
	var move               := Vector3.ZERO
	var fired              := false

	if visible and distance < 34.0 and player.alive:
		var direction: Vector3 = to_player.normalized()
		var side := Vector3(-direction.z, 0, direction.x) * strafe_dir
		var desired_distance := 12.0
		if distance > desired_distance:
			move += direction
		elif distance < 7.0:
			move -= direction
		move += side * 0.7
		if shoot_timer == 0.0:
			_fire_at_player(player, distance)
			fired = true
	else:
		if think_timer == 0.0 or global_position.distance_to(target_point) < 1.6:
			target_point = nav_points.pick_random()
			think_timer  = randf_range(0.7, 1.5)
			strafe_dir  *= -1.0
		move = (target_point - global_position).normalized()

	_apply_movement(move, delta)
	if player.alive:
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
	_update_animation_state(move, fired)


func apply_damage(amount: float, zone: String) -> bool:
	if not alive:
		return false
	health = maxf(0.0, health - amount)
	flash  = 1.0
	if health > 0.0:
		_set_animation_state("hit", true)
		return false
	alive = false
	respawn_timer = randf_range(2.0, 3.2)
	collision_shape.disabled = true
	_set_animation_state("death", true)
	_hide_after_death(0.65)
	for area in hit_areas:
		area.monitoring      = false
		area.monitorable     = false
		area.collision_layer = 0
	return true


func respawn(position: Vector3) -> void:
	global_position         = position
	health                  = MAX_HEALTH
	alive                   = true
	visible                 = true
	collision_shape.disabled = false
	velocity                = Vector3.ZERO
	shoot_timer = randf_range(0.2, 0.7)
	think_timer = randf_range(0.1, 0.4)
	_set_animation_state("respawn", true)
	for area in hit_areas:
		area.monitoring      = true
		area.monitorable     = true
		area.collision_layer = HITBOX_LAYER


func _apply_movement(move: Vector3, delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.1
	var desired := move.normalized() * SPEED
	velocity.x = move_toward(velocity.x, desired.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, desired.z, ACCEL * delta)
	move_and_slide()


func _fire_at_player(player, distance: float) -> void:
	shoot_timer = randf_range(0.18, 0.34)
	_set_animation_state("shoot", true)
	var accuracy := clampf(0.86 - distance * 0.012 - Vector2(player.velocity.x, player.velocity.z).length() * 0.018, 0.26, 0.88)
	var target: Vector3 = player.eye_position()
	target += Vector3(randf_range(-1.2, 1.2), randf_range(-0.7, 0.55), randf_range(-1.2, 1.2)) * (1.0 - accuracy)
	var direction: Vector3 = (target - (global_position + Vector3.UP * 1.45)).normalized()
	game.register_bot_shot(self, global_position + Vector3.UP * 1.45, direction, randf_range(9.0, 16.0))


func _has_line_of_sight(player) -> bool:
	var from := global_position + Vector3.UP * 1.45
	var to: Vector3 = player.eye_position()
	var params := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	params.exclude = [get_rid()]
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(params).is_empty()


func _add_collision() -> void:
	collision_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.56
	capsule.height = 1.8
	collision_shape.shape      = capsule
	collision_shape.position.y = 0.9
	add_child(collision_shape)


func _add_mesh() -> void:
	if _load_character_model():
		return
	_build_human_operator()


func _load_character_model() -> bool:
	for path in CHARACTER_SCENES:
		if ResourceLoader.exists(path):
			var resource := load(path)
			if resource is PackedScene:
				visual_root = resource.instantiate() as Node3D
				if visual_root:
					visual_root.name = "ImportedCombatant"
					add_child(visual_root)
					animation_player = _find_animation_player(visual_root)
					_set_animation_state("idle", true)
					return true
	return false


# ──────────────────────────────────────────────────────────────────────────────
#  HUMAN TACTICAL OPERATOR — procedural character
#  Inspired by Valorant agent / military operator aesthetic.
#  All dimensions in metres; character stands with feet at y=0.
# ──────────────────────────────────────────────────────────────────────────────
func _build_human_operator() -> void:
	visual_root      = Node3D.new()
	visual_root.name = "TacticalOperator"
	add_child(visual_root)

	# ── Pull shared materials; graceful fallback for any missing key ──────
	var skin_m    := _get_mat("skin",            Color(0.70, 0.46, 0.30))
	var pants_m   := _get_mat("combat_pants",    Color(0.41, 0.44, 0.36))
	var jacket_m  := _get_mat("tac_jacket",      Color(0.28, 0.32, 0.26))
	var coyote_m  := _get_mat("coyote_brown",    Color(0.62, 0.51, 0.31))
	var black_m   := _get_mat("tac_black",       Color(0.040, 0.045, 0.042))
	var helmet_m  := _get_mat("ballistic_helmet",Color(0.41, 0.43, 0.36))
	var metal_m   := _get_mat("dark_metal",      Color(0.10, 0.12, 0.13))
	var boot_m    := _get_mat("tac_boots",       Color(0.24, 0.19, 0.12))
	# Team accent (reuse bot_glow from main.gd — emissive, will flash on hit)
	var accent_dup : StandardMaterial3D = _get_mat("bot_glow", Color(0.12, 0.70, 1.0)).duplicate()
	accent_dup.emission_energy_multiplier = 1.1

	# ── HEAD ───────────────────────────────────────────────────────────────
	_s("HeadBase",   Vector3(0, 1.790, 0.012), 0.206, skin_m,   Vector3(1.00, 1.18, 0.97))
	_s("Forehead",   Vector3(0, 1.870,-0.148), 0.100, skin_m,   Vector3(1.60, 0.42, 0.88))
	_s("CheekL",     Vector3(-0.140, 1.760,-0.162), 0.070, skin_m, Vector3(1.30, 0.70, 0.80))
	_s("CheekR",     Vector3( 0.140, 1.760,-0.162), 0.070, skin_m, Vector3(1.30, 0.70, 0.80))
	_b("NoseBridge", Vector3(0, 1.800,-0.220), Vector3(0.052, 0.092, 0.082), skin_m)
	_s("NoseTip",    Vector3(0, 1.770,-0.256), 0.040, skin_m,   Vector3(0.80, 0.65, 1.00))
	_b("Jaw",        Vector3(0, 1.692,-0.138), Vector3(0.265, 0.072, 0.202), skin_m)
	_s("Chin",       Vector3(0, 1.670,-0.172), 0.054, skin_m,   Vector3(1.00, 0.62, 0.85))
	_s("EarL",       Vector3(-0.222, 1.785, 0.022), 0.048, skin_m, Vector3(0.50, 0.82, 0.48))
	_s("EarR",       Vector3( 0.222, 1.785, 0.022), 0.048, skin_m, Vector3(0.50, 0.82, 0.48))

	# ── TACTICAL GOGGLES (flash on damage) ────────────────────────────────
	visor_mesh = _b("TacGoggles",   Vector3(0, 1.793,-0.244), Vector3(0.362, 0.096, 0.052), accent_dup)
	_b("GogglesFrame",              Vector3(0, 1.793,-0.254), Vector3(0.402, 0.114, 0.030), black_m)
	_b("GoggleStrapL",              Vector3(-0.212, 1.793, 0.012), Vector3(0.040, 0.065, 0.342), black_m)
	_b("GoggleStrapR",              Vector3( 0.212, 1.793, 0.012), Vector3(0.040, 0.065, 0.342), black_m)

	# ── HELMET (ACH / MICH style) ──────────────────────────────────────────
	_s("HelmetShell",    Vector3(0, 1.952, 0.022), 0.254, helmet_m, Vector3(1.00, 0.73, 1.08))
	_b("HelmetBrimF",    Vector3(0, 1.840,-0.236), Vector3(0.465, 0.068, 0.126), helmet_m)
	_b("HelmetSideL",    Vector3(-0.254, 1.868, 0.018), Vector3(0.096, 0.080, 0.382), helmet_m)
	_b("HelmetSideR",    Vector3( 0.254, 1.868, 0.018), Vector3(0.096, 0.080, 0.382), helmet_m)
	_b("HelmetBrimR",    Vector3(0, 1.882, 0.278), Vector3(0.442, 0.065, 0.095), helmet_m)
	_b("ChinStrap",      Vector3(0, 1.782,-0.004), Vector3(0.078, 0.048, 0.422), black_m)
	_b("NVGMount",       Vector3(0, 1.998,-0.238), Vector3(0.140, 0.048, 0.038), metal_m)
	_b("SideRailL",      Vector3(-0.256, 1.935, 0.022), Vector3(0.020, 0.058, 0.320), metal_m)
	_b("SideRailR",      Vector3( 0.256, 1.935, 0.022), Vector3(0.020, 0.058, 0.320), metal_m)
	_b("HelmCoverF",     Vector3(0, 1.968,-0.200), Vector3(0.382, 0.042, 0.068), coyote_m)
	_b("HelmCoverTop",   Vector3(0, 2.014, 0.030), Vector3(0.238, 0.028, 0.282), coyote_m)
	_b("TeamStripe",     Vector3(0, 2.010, 0.148), Vector3(0.070, 0.038, 0.092), accent_dup)

	# ── NECK / BALACLAVA COLLAR ────────────────────────────────────────────
	_c("Neck",   Vector3(0, 1.632, 0.022), 0.072, 0.130, skin_m)
	_c("Collar", Vector3(0, 1.602, 0.015), 0.108, 0.075, black_m)

	# ── TORSO ──────────────────────────────────────────────────────────────
	body_mesh = _b("UpperTorso", Vector3(0, 1.302, 0.010), Vector3(0.562, 0.278, 0.268), jacket_m)
	_b("LowerTorso",             Vector3(0, 1.022, 0.005), Vector3(0.474, 0.232, 0.252), jacket_m)
	_b("Belt",                   Vector3(0, 0.910, 0.005), Vector3(0.476, 0.072, 0.254), black_m)

	# ── PLATE CARRIER ──────────────────────────────────────────────────────
	_b("PlateCarrierFront", Vector3(0, 1.298,-0.152), Vector3(0.446, 0.270, 0.048), coyote_m)
	_b("PlateCarrierBack",  Vector3(0, 1.298, 0.158), Vector3(0.446, 0.270, 0.042), coyote_m)
	_b("CummerBundL",       Vector3(-0.262, 1.242, 0.005), Vector3(0.062, 0.202, 0.254), coyote_m)
	_b("CummerBundR",       Vector3( 0.262, 1.242, 0.005), Vector3(0.062, 0.202, 0.254), coyote_m)
	_b("FrontPlateEdge",    Vector3(0, 1.300,-0.178), Vector3(0.360, 0.252, 0.018), black_m)
	# MOLLE pouches
	_b("MagPouchL",  Vector3(-0.152, 1.202,-0.178), Vector3(0.118, 0.175, 0.072), coyote_m)
	_b("MagPouchR",  Vector3( 0.152, 1.202,-0.178), Vector3(0.118, 0.175, 0.072), coyote_m)
	_b("MagPouchC",  Vector3( 0.000, 1.362,-0.185), Vector3(0.118, 0.120, 0.065), coyote_m)
	_b("UtilPouchL", Vector3(-0.150, 1.048,-0.178), Vector3(0.118, 0.132, 0.065), black_m)
	_b("UtilPouchR", Vector3( 0.150, 1.048,-0.178), Vector3(0.118, 0.132, 0.065), black_m)
	_b("AdminPouch", Vector3(0, 1.380,-0.192), Vector3(0.242, 0.072, 0.048), black_m)
	_b("RadioPouch", Vector3(-0.290, 1.288, 0.042), Vector3(0.065, 0.212, 0.108), black_m)

	# ── ARMS ───────────────────────────────────────────────────────────────
	for s in [-1.0, 1.0]:
		var L := "L" if s < 0 else "R"
		_s("ShoulderCap%s" % L, Vector3(s*0.314, 1.382, 0.008), 0.102, jacket_m, Vector3(0.82, 1.02, 0.82))
		_c("UpperArm%s"    % L, Vector3(s*0.334, 1.218, 0.012), 0.078, 0.275, jacket_m, Vector3(0,0,s*10))
		if s > 0:
			_b("IRFlag", Vector3(s*0.356, 1.228, 0.010), Vector3(0.025, 0.095, 0.120), coyote_m)
		_b("ElbowPad%s"    % L, Vector3(s*0.354, 1.068,-0.028), Vector3(0.095, 0.105, 0.135), black_m)
		_c("Forearm%s"     % L, Vector3(s*0.374, 0.902,-0.042), 0.062, 0.268, jacket_m, Vector3(s*7,0,s*4))
		_b("Hand%s"        % L, Vector3(s*0.384, 0.754,-0.072), Vector3(0.092, 0.168, 0.130), black_m)
		_b("Knuckles%s"    % L, Vector3(s*0.384, 0.744,-0.142), Vector3(0.090, 0.056, 0.048), black_m)
		if s > 0:
			_b("ThighHolster", Vector3(s*0.242, 0.672,-0.058), Vector3(0.092, 0.275, 0.120), black_m)
			_b("HolsterFlap",  Vector3(s*0.242, 0.782,-0.075), Vector3(0.100, 0.045, 0.132), black_m)
		else:
			_b("DumpPouch",    Vector3(s*0.240, 0.710, 0.042),  Vector3(0.108, 0.195, 0.148), coyote_m)

	# ── LEGS ───────────────────────────────────────────────────────────────
	for s in [-1.0, 1.0]:
		var L := "L" if s < 0 else "R"
		_c("Thigh%s"       % L, Vector3(s*0.148, 0.622, 0.010), 0.108, 0.322, pants_m)
		_b("CargoPocket%s" % L, Vector3(s*0.226, 0.607,-0.075), Vector3(0.092, 0.205, 0.092), pants_m)
		_b("CargoFlap%s"   % L, Vector3(s*0.226, 0.696,-0.082), Vector3(0.095, 0.038, 0.098), pants_m)
		_b("KneePad%s"     % L, Vector3(s*0.145, 0.443,-0.068), Vector3(0.165, 0.108, 0.108), black_m)
		_b("KneePadRib%s"  % L, Vector3(s*0.145, 0.449,-0.118), Vector3(0.145, 0.055, 0.028), black_m)
		_c("Shin%s"        % L, Vector3(s*0.142, 0.267, 0.005), 0.088, 0.296, pants_m)
		_b("BootAnkle%s"   % L, Vector3(s*0.142, 0.122,-0.010), Vector3(0.158, 0.112, 0.236), boot_m)
		_b("BootSole%s"    % L, Vector3(s*0.142, 0.058, 0.002), Vector3(0.178, 0.032, 0.312), black_m)
		_b("BootToe%s"     % L, Vector3(s*0.142, 0.072,-0.172), Vector3(0.168, 0.110, 0.085), boot_m)
		for li in range(4):
			_b("Lace%s_%d" % [L, li], Vector3(s*0.142, 0.094 + li*0.022,-0.048 + li*0.012), Vector3(0.164, 0.010, 0.008), black_m)

	# ── CARRIED WEAPON — AK-47 style at ready carry ────────────────────
	var dm := _get_mat("dark_metal", Color(0.09, 0.10, 0.11))
	var wm := _make_wood_mat()
	_b("WepReceiver",  Vector3(0.298, 1.108,-0.260), Vector3(0.082, 0.092, 0.455), dm,  Vector3(0,-8,0))
	_b("WepHandguard", Vector3(0.298, 1.105,-0.480), Vector3(0.094, 0.090, 0.205), wm,  Vector3(0,-8,0))
	_b("WepBarrel",    Vector3(0.298, 1.110,-0.642), Vector3(0.032, 0.032, 0.275), dm,  Vector3(0,-8,0))
	_b("WepMuzzleDev", Vector3(0.298, 1.110,-0.785), Vector3(0.052, 0.052, 0.070), dm,  Vector3(0,-8,0))
	_b("WepMagazine",  Vector3(0.298, 1.012,-0.295), Vector3(0.068, 0.228, 0.058), wm,  Vector3(-10,-8,0))
	_b("WepStock",     Vector3(0.298, 1.078, 0.132), Vector3(0.078, 0.082, 0.310), wm,  Vector3(5,-8,0))
	_b("WepGasTube",   Vector3(0.298, 1.150,-0.462), Vector3(0.028, 0.028, 0.210), dm,  Vector3(0,-8,0))
	_b("WepDustCover", Vector3(0.298, 1.142,-0.055), Vector3(0.245, 0.058, 0.430), dm,  Vector3(0,-8,0))
	_b("WepBoltHandle",Vector3(0.245, 1.148, 0.010), Vector3(0.068, 0.032, 0.050), dm,  Vector3(0,-8,0))
	_b("WepSightBase", Vector3(0.298, 1.155,-0.068), Vector3(0.112, 0.040, 0.032), dm,  Vector3(0,-8,0))
	_b("SuppHand",     Vector3(0.224, 1.075,-0.492), Vector3(0.155, 0.082, 0.185), black_m, Vector3(0,-8,0))


func _get_mat(key: String, fallback_color: Color) -> StandardMaterial3D:
	if materials.has(key):
		var m = materials[key]
		if m is StandardMaterial3D:
			return m
	var m := StandardMaterial3D.new()
	m.albedo_color = fallback_color
	m.roughness    = 0.65
	return m


func _make_wood_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.38, 0.18, 0.060)
	m.roughness    = 0.52
	m.metallic     = 0.02
	return m


func _update_animation_state(move: Vector3, fired: bool) -> void:
	if fired:
		return
	if move.length() > 0.1:
		_set_animation_state("run")
	else:
		_set_animation_state("idle")
	if not animation_player and visual_root:
		var t   := Time.get_ticks_msec() * 0.001
		var spd := move.length()
		var bob := sin(t * 9.2 + _bob_offset) * 0.030 if spd > 0.1 else sin(t * 1.35 + _bob_offset) * 0.006
		visual_root.position.y = lerpf(visual_root.position.y, bob, 0.18)
		visual_root.rotation_degrees.z = lerpf(
			visual_root.rotation_degrees.z,
			clampf(move.x, -1.0, 1.0) * -4.0 + sin(t * 1.35 + _bob_offset) * 0.28,
			0.12)


func _set_animation_state(state: String, restart := false) -> void:
	if animation_state == state and not restart:
		return
	animation_state = state
	if not animation_player:
		return
	var candidates: Array = ANIMATION_ALIASES.get(state, [state])
	for anim_name in animation_player.get_animation_list():
		if candidates.has(String(anim_name).to_lower()):
			animation_player.play(anim_name)
			return


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _hide_after_death(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if not alive:
		visible = false


func _add_hitbox(zone: String, offset: Vector3, size: Vector3, multiplier: float) -> void:
	var area := Area3D.new()
	area.name            = "%sHitbox" % zone.capitalize()
	area.collision_layer = HITBOX_LAYER
	area.collision_mask  = 0
	area.set_meta("bot",        self)
	area.set_meta("zone",       zone)
	area.set_meta("multiplier", multiplier)
	add_child(area)
	var shape := CollisionShape3D.new()
	var box   := BoxShape3D.new()
	box.size      = size
	shape.shape   = box
	shape.position = offset
	area.add_child(shape)
	hit_areas.append(area)


# ── Geometry helpers (shorthand) ─────────────────────────────────────────────

func _b(node_name: String, position: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mi   := MeshInstance3D.new()
	mi.name   = node_name
	var mesh  := BoxMesh.new()
	mesh.size  = size
	mi.mesh    = mesh
	mi.position         = position
	mi.rotation_degrees  = rotation
	mi.material_override = material
	visual_root.add_child(mi)
	return mi


func _c(node_name: String, position: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mi  := MeshInstance3D.new()
	mi.name  = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius    = radius
	mesh.bottom_radius = radius
	mesh.height        = height
	mesh.radial_segments = 20
	mi.mesh   = mesh
	mi.position         = position
	mi.rotation_degrees  = rotation
	mi.material_override = material
	visual_root.add_child(mi)
	return mi


func _s(node_name: String, position: Vector3, radius: float, material: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var mi  := MeshInstance3D.new()
	mi.name  = node_name
	var mesh := SphereMesh.new()
	mesh.radius          = radius
	mesh.height          = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings           = 12
	mi.mesh   = mesh
	mi.position         = position
	mi.scale            = scale
	mi.material_override = material
	visual_root.add_child(mi)
	return mi