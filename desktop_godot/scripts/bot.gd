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
	"idle": ["idle", "combat_idle", "rifle_idle"],
	"run": ["run", "jog", "locomotion", "rifle_run"],
	"shoot": ["shoot", "fire", "rifle_fire", "attack"],
	"hit": ["hit", "damage", "flinch"],
	"death": ["death", "die", "knockdown"],
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
var visor_mesh: MeshInstance3D
var hit_areas: Array[Area3D] = []
var collision_shape: CollisionShape3D

func _ready() -> void:
	_add_collision()
	_add_mesh()
	_add_hitbox("body", Vector3(0, 1.05, 0), Vector3(0.95, 1.25, 0.72), 1.0)
	_add_hitbox("head", Vector3(0, 1.84, 0), Vector3(0.52, 0.44, 0.52), 1.55)
	if nav_points.size() > 0:
		target_point = nav_points.pick_random()


func tick_bot(delta: float, player) -> void:
	if not alive:
		respawn_timer = maxf(0.0, respawn_timer - delta)
		if respawn_timer == 0.0:
			respawn(game.bot_respawn_position(self))
		return

	flash = maxf(0.0, flash - delta * 5.0)
	shoot_timer = maxf(0.0, shoot_timer - delta)
	think_timer = maxf(0.0, think_timer - delta)
	if visor_mesh:
		visor_mesh.material_override.emission_energy_multiplier = 2.4 if flash > 0.0 else 1.5

	var to_player: Vector3 = player.global_position - global_position
	var distance: float = to_player.length()
	var visible := _has_line_of_sight(player)
	var move := Vector3.ZERO
	var fired := false

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
			think_timer = randf_range(0.7, 1.5)
			strafe_dir *= -1.0
		move = (target_point - global_position).normalized()

	_apply_movement(move, delta)
	if player.alive:
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
	_update_animation_state(move, fired)


func apply_damage(amount: float, zone: String) -> bool:
	if not alive:
		return false
	health = maxf(0.0, health - amount)
	flash = 1.0
	if health > 0.0:
		_set_animation_state("hit", true)
		return false

	alive = false
	respawn_timer = randf_range(2.0, 3.2)
	collision_shape.disabled = true
	_set_animation_state("death", true)
	_hide_after_death(0.65)
	for area in hit_areas:
		area.monitoring = false
		area.monitorable = false
		area.collision_layer = 0
	return true


func respawn(position: Vector3) -> void:
	global_position = position
	health = MAX_HEALTH
	alive = true
	visible = true
	collision_shape.disabled = false
	velocity = Vector3.ZERO
	shoot_timer = randf_range(0.2, 0.7)
	think_timer = randf_range(0.1, 0.4)
	_set_animation_state("respawn", true)
	for area in hit_areas:
		area.monitoring = true
		area.monitorable = true
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
	collision_shape.shape = capsule
	collision_shape.position.y = 0.9
	add_child(collision_shape)


func _add_mesh() -> void:
	if _load_character_model():
		return
	_build_dev_character()


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


func _build_dev_character() -> void:
	visual_root = Node3D.new()
	visual_root.name = "DevCombatantFallback"
	add_child(visual_root)
	var armor_material: Material = materials.get("bot", StandardMaterial3D.new())
	var glow_material: Material = materials.get("bot_glow", StandardMaterial3D.new())
	var dark_material: Material = materials.get("dark_metal", armor_material)

	body_mesh = MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.42
	body.height = 1.55
	body_mesh.mesh = body
	body_mesh.position.y = 0.9
	body_mesh.material_override = armor_material
	visual_root.add_child(body_mesh)

	_add_bot_box("ChestPlate", Vector3(0, 1.17, -0.23), Vector3(0.72, 0.48, 0.12), dark_material)
	_add_bot_box("CoreLight", Vector3(0, 1.25, -0.31), Vector3(0.20, 0.08, 0.045), glow_material)
	_add_bot_box("Belt", Vector3(0, 0.77, -0.11), Vector3(0.74, 0.12, 0.18), dark_material)

	for side in [-1.0, 1.0]:
		_add_bot_box("ThighArmor", Vector3(side * 0.20, 0.42, 0), Vector3(0.22, 0.62, 0.22), armor_material)
		_add_bot_box("Boot", Vector3(side * 0.20, 0.10, -0.04), Vector3(0.25, 0.18, 0.34), dark_material)
		_add_bot_box("ShoulderArmor", Vector3(side * 0.50, 1.24, 0), Vector3(0.20, 0.38, 0.26), glow_material)
		_add_bot_box("ForearmArmor", Vector3(side * 0.58, 0.92, -0.20), Vector3(0.16, 0.38, 0.18), armor_material, Vector3(-12, 0, side * 7.0))

	visor_mesh = MeshInstance3D.new()
	var visor := BoxMesh.new()
	visor.size = Vector3(0.58, 0.16, 0.08)
	visor_mesh.mesh = visor
	visor_mesh.position = Vector3(0, 1.84, -0.36)
	visor_mesh.material_override = glow_material.duplicate()
	visual_root.add_child(visor_mesh)

	_add_bot_box("HelmetBrow", Vector3(0, 1.92, -0.24), Vector3(0.70, 0.14, 0.26), dark_material)
	_add_bot_box("Backpack", Vector3(0, 1.12, 0.36), Vector3(0.52, 0.62, 0.20), dark_material)
	_add_bot_box("Rifle", Vector3(0.46, 1.10, -0.44), Vector3(0.12, 0.10, 0.78), dark_material, Vector3(0, -4, 0))
	_add_bot_box("RifleAccent", Vector3(0.46, 1.14, -0.54), Vector3(0.13, 0.035, 0.24), glow_material, Vector3(0, -4, 0))


func _add_bot_box(node_name: String, position: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = material
	visual_root.add_child(mesh_instance)
	return mesh_instance


func _update_animation_state(move: Vector3, fired: bool) -> void:
	if fired:
		return
	if move.length() > 0.1:
		_set_animation_state("run")
	else:
		_set_animation_state("idle")
	if not animation_player and visual_root:
		var bob := sin(Time.get_ticks_msec() * 0.012 + float(get_instance_id() % 100)) * 0.035 if move.length() > 0.1 else 0.0
		visual_root.position.y = lerpf(visual_root.position.y, bob, 0.18)
		visual_root.rotation_degrees.z = lerpf(visual_root.rotation_degrees.z, clampf(move.x, -1.0, 1.0) * -3.5, 0.12)


func _set_animation_state(state: String, restart := false) -> void:
	if animation_state == state and not restart:
		return
	animation_state = state
	if not animation_player:
		return
	var candidates: Array = ANIMATION_ALIASES.get(state, [state])
	for animation_name in animation_player.get_animation_list():
		if candidates.has(String(animation_name).to_lower()):
			animation_player.play(animation_name)
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
	area.name = "%sHitbox" % zone.capitalize()
	area.collision_layer = HITBOX_LAYER
	area.collision_mask = 0
	area.set_meta("bot", self)
	area.set_meta("zone", zone)
	area.set_meta("multiplier", multiplier)
	add_child(area)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	area.add_child(shape)
	hit_areas.append(area)
