extends Node3D

const PlayerScript := preload("res://scripts/player.gd")
const BotScript := preload("res://scripts/bot.gd")
const HudScript := preload("res://scripts/hud.gd")
const AudioDirectorScript := preload("res://scripts/audio_director.gd")

const WORLD_LAYER := 1
const ACTOR_LAYER := 2
const HITBOX_LAYER := 4
const MATCH_SECONDS := 8.0 * 60.0
const KILL_LIMIT := 30
const BOT_COUNT := 1

var rng := RandomNumberGenerator.new()
var materials := {}
var player
var hud: CanvasLayer
var audio
var arena_root: Node3D
var dynamic_root: Node3D
var fx_root: Node3D
var bots: Array = []
var match_time := MATCH_SECONDS
var game_active := true
var feed: Array[String] = []

var spawn_points := [
	Vector3(-21, 0.05, -18),
	Vector3(0, 0.05, -21),
	Vector3(21, 0.05, -18),
	Vector3(-21, 0.05, 18),
	Vector3(0, 0.05, 21),
	Vector3(21, 0.05, 18),
	Vector3(-23, 0.05, 0),
	Vector3(23, 0.05, 0),
]

var nav_points := [
	Vector3(-18, 0.05, -12),
	Vector3(-18, 0.05, 12),
	Vector3(18, 0.05, -12),
	Vector3(18, 0.05, 12),
	Vector3(-10, 0.05, -16),
	Vector3(-10, 0.05, 16),
	Vector3(10, 0.05, -16),
	Vector3(10, 0.05, 16),
	Vector3(-7, 0.05, 0),
	Vector3(7, 0.05, 0),
	Vector3(0, 0.05, -8),
	Vector3(0, 0.05, 8),
]

func _ready() -> void:
	rng.randomize()
	_install_input_map()
	arena_root = Node3D.new()
	arena_root.name = "Arena"
	add_child(arena_root)
	dynamic_root = Node3D.new()
	dynamic_root.name = "Actors"
	add_child(dynamic_root)
	fx_root = Node3D.new()
	fx_root.name = "Effects"
	add_child(fx_root)

	_build_materials()
	_build_environment()
	_build_arena()
	_spawn_player()
	_spawn_bots()
	_spawn_hud()
	_spawn_audio()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_add_feed("Astra Combat Wing online.")


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Input.is_action_just_pressed("fire") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.is_action_just_pressed("restart_match"):
		reset_match()

	if game_active:
		match_time = maxf(0.0, match_time - delta)
		if match_time == 0.0:
			_end_match("Time expired.")

	if hud:
		hud.update_match(player, bots, match_time, game_active, feed)


func _physics_process(delta: float) -> void:
	if not game_active:
		return

	for bot in bots:
		bot.tick_bot(delta, player)


func reset_match() -> void:
	match_time = MATCH_SECONDS
	game_active = true
	feed.clear()
	player.kills = 0
	player.deaths = 0
	player.reset_for_match(_choose_spawn(null))
	for index in range(bots.size()):
		bots[index].respawn(_choose_spawn(bots[index]))
	_add_feed("Match reset.")


func register_player_shot(origin: Vector3, direction: Vector3, weapon: Dictionary) -> void:
	if not game_active:
		return

	var visual_origin: Vector3 = player.muzzle_position() if player and player.has_method("muzzle_position") else origin
	if audio:
		audio.play_3d(weapon["sound"], visual_origin, -3.0)
	_spawn_muzzle_flash(visual_origin, direction, weapon["color"])

	var hit := _raycast(origin, origin + direction * weapon["range"], WORLD_LAYER | HITBOX_LAYER, [player.get_rid()])
	var has_hit := not hit.is_empty()
	var impact: Vector3 = origin + direction * weapon["range"]
	var impact_normal: Vector3 = -direction
	var impact_surface := "concrete"
	if has_hit:
		impact = hit["position"]
		impact_normal = hit.get("normal", -direction)
		impact_surface = _surface_from_hit(hit)

	_spawn_tracer(visual_origin, impact, weapon["color"], 0.052)
	_spawn_impact(impact, weapon["color"], 0.16, impact_normal, impact_surface)

	if has_hit and hit["collider"] is Area3D and hit["collider"].has_meta("bot"):
		var bot = hit["collider"].get_meta("bot")
		var zone := String(hit["collider"].get_meta("zone"))
		var multiplier := float(hit["collider"].get_meta("multiplier"))
		var died: bool = bot.apply_damage(weapon["damage"] * multiplier, zone)
		player.hit_marker = 0.15
		if audio:
			audio.play_3d("hit", impact, -8.0)
		if died:
			player.kills += 1
			player.health = minf(player.max_health, player.health + 18.0)
			_add_feed("DeTyrant eliminated %s%s." % [bot.callsign, " [critical]" if zone == "head" else ""])
			if audio:
				audio.play_2d("kill", -7.0)
			if player.kills >= KILL_LIMIT:
				_end_match("DeTyrant hit the kill limit.")


func register_bot_shot(bot, origin: Vector3, direction: Vector3, damage: float) -> void:
	if not game_active or not player.alive:
		return

	if audio:
		audio.play_3d("bot_fire", origin, -10.0)
	_spawn_muzzle_flash(origin, direction, Color(1.0, 0.42, 0.28))

	var end := origin + direction * 72.0
	var hit := _raycast(origin, end, WORLD_LAYER, [bot.get_rid()])
	var has_hit := not hit.is_empty()
	var blocked := has_hit and origin.distance_to(hit["position"]) < origin.distance_to(player.eye_position())
	var impact: Vector3 = hit["position"] if has_hit else end
	var impact_normal: Vector3 = hit.get("normal", -direction) if has_hit else -direction
	var impact_surface: String = _surface_from_hit(hit) if has_hit else "flesh"
	if not blocked:
		var player_distance := origin.distance_to(player.eye_position())
		impact = player.eye_position()
		impact_normal = -direction
		impact_surface = "flesh"
		if player_distance < 38.0:
			player.apply_damage(damage)
			if not player.alive:
				_add_feed("%s dropped DeTyrant." % bot.callsign)
				player.deaths += 1
				await get_tree().create_timer(1.4).timeout
				if game_active:
					player.respawn(_choose_spawn(player))

	_spawn_tracer(origin, impact, Color(1.0, 0.42, 0.28), 0.035)
	_spawn_impact(impact, Color(1.0, 0.42, 0.28), 0.10, impact_normal, impact_surface)


func bot_respawn_position(bot) -> Vector3:
	return _choose_spawn(bot)


func play_footstep(position: Vector3, surface: String, intensity: float) -> void:
	if audio:
		audio.play_footstep(surface, position, intensity)


func _spawn_player() -> void:
	player = PlayerScript.new()
	player.name = "DeTyrant"
	player.game = self
	player.collision_layer = ACTOR_LAYER
	player.collision_mask = WORLD_LAYER | ACTOR_LAYER
	dynamic_root.add_child(player)
	player.reset_for_match(_choose_spawn(null))


func _spawn_bots() -> void:
	for index in range(BOT_COUNT):
		var bot = BotScript.new()
		bot.name = "Bot%d" % index
		bot.game = self
		bot.callsign = ["Aegis-7", "Nova Trace", "Cipher Echo", "Helix-9", "Zero Drift", "Quartz Shade"][index]
		bot.nav_points = nav_points
		bot.materials = materials
		bot.collision_layer = ACTOR_LAYER
		bot.collision_mask = WORLD_LAYER | ACTOR_LAYER
		dynamic_root.add_child(bot)
		bot.respawn(spawn_points[(index + 1) % spawn_points.size()])
		bots.append(bot)


func _spawn_hud() -> void:
	hud = HudScript.new()
	add_child(hud)


func _spawn_audio() -> void:
	audio = AudioDirectorScript.new()
	add_child(audio)


func _build_materials() -> void:
	materials.terrain = _mat(Color(0.54, 0.60, 0.50), Color(0.05, 0.07, 0.055), 0.04, 0.0, 0.82)
	materials.concrete = _mat(Color(0.58, 0.61, 0.60), Color(0.05, 0.055, 0.06), 0.03, 0.0, 0.64)
	materials.sand = _mat(Color(0.73, 0.68, 0.56), Color(0.08, 0.065, 0.04), 0.02, 0.0, 0.88)
	materials.grass = _mat(Color(0.22, 0.42, 0.24), Color(0.02, 0.045, 0.02), 0.06, 0.0, 0.9)
	materials.floor = _mat(Color(0.32, 0.36, 0.39), Color(0.035, 0.045, 0.052), 0.05, 0.12, 0.58)
	materials.panel = _mat(Color(0.50, 0.55, 0.58), Color(0.025, 0.035, 0.045), 0.04, 0.36, 0.42)
	materials.wall = _mat(Color(0.25, 0.28, 0.30), Color(0.015, 0.022, 0.028), 0.04, 0.48, 0.45)
	materials.dark_metal = _mat(Color(0.10, 0.12, 0.13), Color(0.01, 0.016, 0.02), 0.05, 0.75, 0.34)
	materials.cover = _mat(Color(0.31, 0.34, 0.35), Color(0.03, 0.036, 0.04), 0.06, 0.48, 0.46)
	materials.cliff = _mat(Color(0.43, 0.40, 0.35), Color(0.055, 0.047, 0.035), 0.02, 0.0, 0.94)
	materials.water = _mat(Color(0.13, 0.42, 0.62, 0.62), Color(0.02, 0.18, 0.28), 0.24, 0.0, 0.08)
	materials.trim = _mat(Color(0.12, 0.63, 1.0), Color(0.12, 0.68, 1.0), 1.45, 0.05, 0.25)
	materials.warm = _mat(Color(1.0, 0.64, 0.28), Color(1.0, 0.46, 0.12), 1.15, 0.08, 0.35)
	materials.red = _mat(Color(1.0, 0.18, 0.22), Color(1.0, 0.08, 0.12), 1.25, 0.05, 0.32)
	materials.white_mark = _mat(Color(0.88, 0.90, 0.88), Color(0.1, 0.13, 0.14), 0.03, 0.0, 0.55)
	materials.bot = _mat(Color(0.66, 0.70, 0.72), Color(0.04, 0.08, 0.1), 0.18, 0.32, 0.38)
	materials.bot_glow = _mat(Color(0.12, 0.72, 1.0), Color(0.12, 0.72, 1.0), 1.5, 0.04, 0.24)
	materials.glass = _mat(Color(0.30, 0.64, 0.86, 0.28), Color(0.09, 0.40, 0.65), 0.55, 0.0, 0.05)
	materials.cloud = _mat(Color(0.92, 0.97, 1.0, 0.34), Color(0.22, 0.38, 0.58), 0.10, 0.0, 0.62)
	materials.banner = _mat(Color(0.95, 0.24, 0.18), Color(0.35, 0.04, 0.04), 0.05, 0.08, 0.48)
	materials.asphalt = _mat(Color(0.13, 0.13, 0.12), Color(0.01, 0.01, 0.008), 0.01, 0.0, 0.96)
	materials.brick = _mat(Color(0.47, 0.22, 0.14), Color(0.025, 0.008, 0.004), 0.02, 0.0, 0.82)
	materials.wood = _mat(Color(0.42, 0.24, 0.12), Color(0.035, 0.016, 0.006), 0.02, 0.02, 0.74)
	materials.bark = _mat(Color(0.20, 0.12, 0.07), Color(0.018, 0.009, 0.003), 0.01, 0.0, 0.88)
	materials.foliage = _mat(Color(0.11, 0.31, 0.11), Color(0.006, 0.030, 0.006), 0.025, 0.0, 0.92)
	materials.foliage_light = _mat(Color(0.26, 0.48, 0.18), Color(0.010, 0.045, 0.008), 0.03, 0.0, 0.9)
	materials.mud = _mat(Color(0.22, 0.17, 0.12), Color(0.012, 0.008, 0.004), 0.01, 0.0, 0.98)
	materials.rust = _mat(Color(0.63, 0.24, 0.09), Color(0.05, 0.012, 0.003), 0.02, 0.18, 0.78)
	materials.puddle = _mat(Color(0.09, 0.13, 0.12, 0.58), Color(0.01, 0.03, 0.025), 0.08, 0.0, 0.06)
	materials.glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materials.water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materials.cloud.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materials.puddle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_apply_material_noise(materials.terrain, 17, 0.045, Vector3(12, 12, 1))
	_apply_material_noise(materials.concrete, 23, 0.070, Vector3(9, 9, 1))
	_apply_material_noise(materials.sand, 31, 0.060, Vector3(10, 10, 1))
	_apply_material_noise(materials.cliff, 43, 0.090, Vector3(8, 8, 1))
	_apply_material_noise(materials.asphalt, 53, 0.115, Vector3(13, 13, 1))
	_apply_material_noise(materials.brick, 61, 0.080, Vector3(5, 5, 1))
	_apply_material_noise(materials.wood, 67, 0.135, Vector3(8, 8, 1))
	_apply_material_noise(materials.bark, 71, 0.180, Vector3(5, 12, 1))
	_apply_material_noise(materials.foliage, 73, 0.160, Vector3(6, 6, 1))
	_apply_material_noise(materials.mud, 79, 0.100, Vector3(8, 8, 1))
	_apply_material_noise(materials.rust, 83, 0.150, Vector3(4, 4, 1))


func _mat(albedo: Color, emission: Color, emission_energy: float, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.emission_enabled = emission_energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = emission_energy
	material.metallic = metallic
	material.roughness = roughness
	return material


func _apply_material_noise(material: StandardMaterial3D, seed: int, frequency: float, uv_scale: Vector3) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = frequency
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.45
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.noise = noise
	material.albedo_texture = texture
	material.uv1_scale = uv_scale


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.31, 0.58, 0.92)
	sky_material.sky_horizon_color = Color(0.78, 0.90, 1.0)
	sky_material.ground_bottom_color = Color(0.18, 0.22, 0.19)
	sky_material.ground_horizon_color = Color(0.62, 0.73, 0.70)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.50, 0.58)
	environment.ambient_light_energy = 1.2
	environment.glow_enabled = true
	environment.glow_intensity = 0.22
	environment.glow_bloom = 0.08
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.06
	environment.adjustment_contrast = 1.04
	environment.adjustment_saturation = 1.05
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.58, 0.75, 0.88)
	environment.fog_density = 0.004
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.light_color = Color(1.0, 0.95, 0.84)
	sun.light_energy = 3.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.rotation_degrees = Vector3(-42, -35, 0)
	add_child(sun)

	for data in [
		[Vector3(0, 4.2, 0), Color(0.26, 0.72, 1.0), 1.5, 24.0],
		[Vector3(-18, 3.8, -13), Color(0.22, 0.58, 1.0), 0.9, 14.0],
		[Vector3(18, 3.8, 13), Color(0.22, 0.58, 1.0), 0.9, 14.0],
		[Vector3(-18, 3.8, 13), Color(0.25, 0.95, 0.80), 0.75, 12.0],
		[Vector3(18, 3.8, -13), Color(1.0, 0.62, 0.32), 0.75, 12.0],
	]:
		var light := OmniLight3D.new()
		light.position = data[0]
		light.light_color = data[1]
		light.light_energy = data[2]
		light.omni_range = data[3]
		light.shadow_enabled = false
		add_child(light)


func _build_arena() -> void:
	_add_box(Vector3(0, -0.42, 0), Vector3(86, 0.82, 86), materials.terrain, true, "TerrainBase")
	_add_box(Vector3(0, 0.02, 0), Vector3(52, 0.08, 16), materials.concrete, true, "CentralCombatLane")
	_add_box(Vector3(0, 0.035, -16), Vector3(45, 0.09, 8), materials.sand, true, "NorthSandyLane")
	_add_box(Vector3(0, 0.035, 16), Vector3(45, 0.09, 8), materials.sand, true, "SouthSandyLane")
	_add_box(Vector3(-26, 0.04, 0), Vector3(5.5, 0.1, 48), materials.grass, true, "WestGreenShoulder")
	_add_box(Vector3(26, 0.04, 0), Vector3(5.5, 0.1, 48), materials.grass, true, "EastGreenShoulder")

	for z in [-20, 20]:
		_add_box(Vector3(0, 0.18, z), Vector3(54, 0.35, 0.55), materials.white_mark, false, "RunwayStripe")
	for x in [-18, -9, 0, 9, 18]:
		_add_box(Vector3(x, 0.13, -7.7), Vector3(5.4, 0.13, 0.16), materials.trim, false, "LaneLight")
		_add_box(Vector3(x, 0.13, 7.7), Vector3(5.4, 0.13, 0.16), materials.trim, false, "LaneLight")

	_add_box(Vector3(-34.5, 1.55, 0), Vector3(1.2, 3.1, 64), materials.cliff, true, "WestCliffWall")
	_add_box(Vector3(34.5, 1.55, 0), Vector3(1.2, 3.1, 64), materials.cliff, true, "EastCliffWall")
	_add_box(Vector3(0, 1.55, -34.5), Vector3(66, 3.1, 1.2), materials.cliff, true, "NorthCliffWall")
	_add_box(Vector3(0, 0.35, 34.8), Vector3(86, 0.18, 18), materials.water, false, "DistantWater")

	_add_box(Vector3(-12.0, 1.0, -9.5), Vector3(5.5, 2.0, 3.0), materials.cover, true, "LeftAStack")
	_add_box(Vector3(12.0, 1.0, -9.5), Vector3(5.5, 2.0, 3.0), materials.cover, true, "RightAStack")
	_add_box(Vector3(-12.0, 1.0, 9.5), Vector3(5.5, 2.0, 3.0), materials.cover, true, "LeftBStack")
	_add_box(Vector3(12.0, 1.0, 9.5), Vector3(5.5, 2.0, 3.0), materials.cover, true, "RightBStack")

	for position in [Vector3(-8, 0.75, 0), Vector3(8, 0.75, 0), Vector3(0, 0.75, -12), Vector3(0, 0.75, 12)]:
		_add_box(position, Vector3(3.2, 1.5, 1.5), materials.wall, true, "HalfCover")
		_add_box(position + Vector3.UP * 0.84, Vector3(2.7, 0.11, 0.18), materials.trim, false, "HalfCoverGlow")

	for position in [Vector3(-23, 1.25, -18), Vector3(23, 1.25, -18), Vector3(-23, 1.25, 18), Vector3(23, 1.25, 18)]:
		_add_cylinder(position, 0.72, 2.5, materials.dark_metal, true, "SupportPillar")
		_add_cylinder(position + Vector3.UP * 1.38, 0.9, 0.18, materials.warm, false, "PillarBeacon")

	_build_combat_detail()
	_build_bridge_landmark()
	_build_dropship_landmark()
	_build_terrain_dressing()
	_build_realism_dressing()
	_build_skyline_dressing()


func _build_combat_detail() -> void:
	for z in [-12, -4, 4, 12]:
		_add_box(Vector3(-27.3, 0.34, z), Vector3(0.12, 0.52, 3.8), materials.trim, false, "ShoulderGuideLight")
		_add_box(Vector3(27.3, 0.34, z), Vector3(0.12, 0.52, 3.8), materials.trim, false, "ShoulderGuideLight")

	for x in [-21, -14, -7, 0, 7, 14, 21]:
		_add_box(Vector3(x, 0.095, 0), Vector3(0.09, 0.055, 15.4), materials.dark_metal, false, "ConcreteExpansionJoint")

	for data in [
		[Vector3(-17, 0.72, -2.6), Vector3(2.3, 1.42, 0.72), Vector3(0, 18, 0)],
		[Vector3(17, 0.72, 2.6), Vector3(2.3, 1.42, 0.72), Vector3(0, 18, 0)],
		[Vector3(-2.8, 0.54, -17.1), Vector3(3.1, 1.05, 0.56), Vector3(0, -8, 0)],
		[Vector3(2.8, 0.54, 17.1), Vector3(3.1, 1.05, 0.56), Vector3(0, -8, 0)],
	]:
		_add_box(data[0], data[1], materials.dark_metal, true, "AngledCoverCore", data[2])
		_add_box(data[0] + Vector3.UP * 0.75, Vector3(data[1].x * 0.72, 0.07, 0.08), materials.trim, false, "AngledCoverLight", data[2])

	for position in [Vector3(-6, 0.35, -5.2), Vector3(6, 0.35, 5.2)]:
		_add_cylinder(position, 1.15, 0.08, materials.trim, false, "ObjectiveGlowDisc", Vector3(90, 0, 0))
		_add_cylinder(position + Vector3.UP * 0.08, 0.36, 0.18, materials.glass, false, "ObjectiveHoloCore")

	for position in [Vector3(-29, 2.8, -21), Vector3(29, 2.8, -21), Vector3(-29, 2.8, 21), Vector3(29, 2.8, 21)]:
		_add_cylinder(position, 0.11, 5.6, materials.dark_metal, false, "LightMast")
		_add_box(position + Vector3(0, 2.5, -0.32), Vector3(0.18, 0.18, 0.82), materials.trim, false, "LightMastHead")
		_add_box(position + Vector3(0, 1.1, 0.02), Vector3(0.05, 1.6, 0.12), materials.banner, false, "RedRangeBanner")


func _build_bridge_landmark() -> void:
	_add_box(Vector3(0, 5.7, -38), Vector3(58, 1.2, 3.4), materials.dark_metal, false, "DistantSkyBridge")
	_add_box(Vector3(-24, 3.0, -38), Vector3(2.2, 5.8, 3.2), materials.wall, false, "BridgeSupport")
	_add_box(Vector3(24, 3.0, -38), Vector3(2.2, 5.8, 3.2), materials.wall, false, "BridgeSupport")
	for x in [-18, -9, 0, 9, 18]:
		_add_box(Vector3(x, 6.45, -36.1), Vector3(4.6, 0.12, 0.25), materials.trim, false, "BridgeLight")
		_add_box(Vector3(x, 4.95, -36.1), Vector3(3.4, 0.12, 0.20), materials.warm, false, "BridgeWarmLight")


func _build_dropship_landmark() -> void:
	var origin := Vector3(15, 8.0, -17)
	_add_box(origin, Vector3(8.8, 1.15, 4.2), materials.dark_metal, false, "DropShipHull", Vector3(0, -13, 0))
	_add_box(origin + Vector3(-4.4, -0.1, 0.2), Vector3(4.2, 0.35, 7.4), materials.wall, false, "DropShipWingL", Vector3(0, -18, 8))
	_add_box(origin + Vector3(4.4, -0.1, 0.2), Vector3(4.2, 0.35, 7.4), materials.wall, false, "DropShipWingR", Vector3(0, -8, -8))
	_add_box(origin + Vector3(0, -0.28, -2.55), Vector3(2.0, 0.3, 0.75), materials.trim, false, "DropShipEngineGlow", Vector3(0, -13, 0))
	_add_box(origin + Vector3(0, 0.48, 2.45), Vector3(4.2, 0.25, 0.45), materials.glass, false, "DropShipCanopy", Vector3(0, -13, 0))


func _build_terrain_dressing() -> void:
	for position in [Vector3(-29, 0.5, -23), Vector3(-31, 0.45, 13), Vector3(31, 0.6, -10), Vector3(29, 0.55, 24), Vector3(-4, 0.35, 27), Vector3(18, 0.35, 27)]:
		_add_sphere(position, Vector3(2.2, 0.85, 1.5), materials.cliff, false, "RockCluster")
	for position in [Vector3(-28, 1.05, -4), Vector3(29, 1.05, 6), Vector3(-20, 1.05, 25), Vector3(23, 1.05, 25)]:
		_add_cylinder(position, 0.16, 2.1, materials.dark_metal, false, "SlimTreeTrunk")
		_add_sphere(position + Vector3.UP * 1.55, Vector3(1.1, 0.8, 1.1), materials.grass, false, "WindCutCanopy")
	for x in [-20, -10, 10, 20]:
		_add_box(Vector3(x, 0.12, 25.5), Vector3(4.4, 0.08, 0.22), materials.white_mark, false, "WaterEdgeStripe")


func _build_realism_dressing() -> void:
	_add_box(Vector3(0, 0.075, 0), Vector3(54, 0.045, 13.5), materials.asphalt, false, "CrackedAsphaltOverlay")
	_add_box(Vector3(-5.0, 0.092, -3.2), Vector3(6.5, 0.03, 3.2), materials.mud, false, "MuddyPatch")
	_add_box(Vector3(8.5, 0.096, 5.4), Vector3(5.8, 0.025, 2.6), materials.mud, false, "MuddyPatch")
	_add_puddle(Vector3(-5.4, 0.126, -3.0), Vector3(2.5, 0.018, 0.95), Vector3(0, 12, 0))
	_add_puddle(Vector3(8.9, 0.126, 5.2), Vector3(2.0, 0.018, 0.78), Vector3(0, -10, 0))

	_add_ruined_facade(Vector3(-31.5, 2.8, -12.0), Vector3(0, 0, 0), 0)
	_add_ruined_facade(Vector3(31.5, 2.8, 10.5), Vector3(0, 180, 0), 1)
	_add_wood_shack(Vector3(-21.0, 1.25, 20.5), Vector3(0, 14, 0))
	_add_rusted_car(Vector3(19.5, 0.55, -17.5), Vector3(0, -16, 0))
	_add_rusted_car(Vector3(-18.5, 0.55, -18.8), Vector3(0, 18, 0))

	for position in [Vector3(-29, 0.0, -2), Vector3(29, 0.0, -8), Vector3(-26, 0.0, 15), Vector3(27, 0.0, 20), Vector3(-6, 0.0, 25), Vector3(13, 0.0, 24)]:
		_add_tree(position)

	for index in range(130):
		var side := -1.0 if index % 2 == 0 else 1.0
		var x := side * rng.randf_range(20.0, 30.5)
		var z := rng.randf_range(-26.0, 27.0)
		_add_grass_clump(Vector3(x, 0.18, z), rng.randf_range(0.65, 1.35))

	for index in range(32):
		var x := rng.randf_range(-24.0, 24.0)
		var z := rng.randf_range(-22.0, 22.0)
		if absf(x) < 9.0 and absf(z) < 8.0:
			continue
		var size := Vector3(rng.randf_range(0.25, 0.85), 0.05, rng.randf_range(0.20, 0.65))
		_add_box(Vector3(x, 0.135, z), size, materials.cliff, false, "LooseDebris", Vector3(0, rng.randf_range(0.0, 180.0), 0))


func _add_puddle(position: Vector3, size: Vector3, rotation := Vector3.ZERO) -> void:
	_add_box(position, size, materials.puddle, false, "WaterPuddle", rotation)
	_add_box(position + Vector3.UP * 0.006, Vector3(size.x * 0.82, size.y, size.z * 0.65), materials.glass, false, "PuddleHighlight", rotation)


func _add_ruined_facade(position: Vector3, rotation := Vector3.ZERO, variant := 0) -> void:
	_add_box(position, Vector3(0.7, 5.6, 14.0), materials.brick, false, "BrickBuildingFacade", rotation)
	_add_box(position + Vector3(0, 2.95, 0), Vector3(0.9, 0.28, 14.4), materials.concrete, false, "FacadeCornice", rotation)
	for z in [-4.6, 0.0, 4.6]:
		for y in [1.9, 3.4]:
			_add_box(position + Vector3(-0.42, y - 2.8, z), Vector3(0.08, 1.0, 1.15), materials.dark_metal, false, "BrokenWindowVoid", rotation)
			_add_box(position + Vector3(-0.47, y - 2.8, z), Vector3(0.04, 0.82, 0.92), materials.glass, false, "DirtyWindowGlass", rotation)
	if variant == 1:
		_add_box(position + Vector3(-0.55, -1.1, -4.4), Vector3(0.08, 1.8, 1.2), materials.dark_metal, false, "DoorVoid", rotation)
	for index in range(6):
		var z_offset := -6.2 + float(index) * 2.45
		_add_box(position + Vector3(-0.52, -2.15, z_offset), Vector3(0.08, 0.18, 1.6), materials.foliage, false, "FacadeIvy", rotation)


func _add_wood_shack(position: Vector3, rotation := Vector3.ZERO) -> void:
	_add_box(position, Vector3(6.8, 2.4, 5.2), materials.wood, false, "WoodShackBody", rotation)
	_add_box(position + Vector3(0, 1.45, 0), Vector3(7.4, 0.30, 5.9), materials.rust, false, "RustRoof", rotation + Vector3(0, 0, 4))
	_add_box(position + Vector3(0, 1.55, 0), Vector3(7.4, 0.30, 5.9), materials.rust, false, "RustRoof", rotation + Vector3(0, 0, -4))
	_add_box(position + Vector3(0, -0.35, -2.68), Vector3(1.2, 1.6, 0.08), materials.dark_metal, false, "ShackDoor", rotation)
	for x in [-2.1, 2.1]:
		_add_box(position + Vector3(x, 0.25, -2.72), Vector3(1.05, 0.8, 0.06), materials.glass, false, "ShackWindow", rotation)


func _add_rusted_car(position: Vector3, rotation := Vector3.ZERO) -> void:
	_add_box(position + Vector3(0, 0.35, 0), Vector3(3.8, 0.75, 1.8), materials.rust, false, "RustedCarBody", rotation)
	_add_box(position + Vector3(-0.35, 0.95, 0), Vector3(1.8, 0.65, 1.5), materials.dark_metal, false, "RustedCarCabin", rotation)
	_add_box(position + Vector3(-0.35, 1.02, -0.78), Vector3(1.3, 0.35, 0.08), materials.glass, false, "BrokenWindshield", rotation)
	for x in [-1.25, 1.25]:
		for z in [-0.92, 0.92]:
			_add_cylinder(position + Vector3(x, 0.18, z), 0.34, 0.18, materials.dark_metal, false, "CarWheel", rotation + Vector3(90, 0, 0))


func _add_tree(position: Vector3) -> void:
	var height := rng.randf_range(3.0, 5.4)
	_add_cylinder(position + Vector3.UP * (height * 0.5), rng.randf_range(0.16, 0.28), height, materials.bark, false, "TreeTrunk")
	for index in range(4):
		var canopy_offset := Vector3(rng.randf_range(-0.65, 0.65), height + rng.randf_range(-0.1, 0.9), rng.randf_range(-0.65, 0.65))
		var scale := Vector3(rng.randf_range(1.0, 1.75), rng.randf_range(0.70, 1.15), rng.randf_range(1.0, 1.75))
		_add_sphere(position + canopy_offset, scale, materials.foliage if index % 2 == 0 else materials.foliage_light, false, "LeafCanopy")


func _add_grass_clump(position: Vector3, scale: float) -> void:
	for blade in range(4):
		var offset := Vector3(rng.randf_range(-0.20, 0.20), 0, rng.randf_range(-0.20, 0.20))
		var height := rng.randf_range(0.45, 1.05) * scale
		var rotation := Vector3(rng.randf_range(-10.0, 10.0), rng.randf_range(0.0, 180.0), rng.randf_range(-12.0, 12.0))
		_add_box(position + offset + Vector3.UP * (height * 0.5), Vector3(0.035, height, 0.055), materials.foliage_light, false, "GrassBlade", rotation)


func _build_skyline_dressing() -> void:
	for data in [
		[Vector3(-23, 11.5, -50), Vector3(7.0, 0.95, 2.0)],
		[Vector3(-14, 12.4, -52), Vector3(5.8, 0.85, 1.7)],
		[Vector3(18, 10.8, -48), Vector3(6.2, 0.9, 1.8)],
		[Vector3(31, 12.1, -46), Vector3(4.2, 0.7, 1.3)],
		[Vector3(-36, 9.0, 28), Vector3(5.0, 0.72, 1.4)],
		[Vector3(38, 9.5, 30), Vector3(5.4, 0.78, 1.5)],
	]:
		_add_sphere(data[0], data[1], materials.cloud, false, "SoftCloudBank")

	for data in [
		[Vector3(-42, 1.2, 41), Vector3(8.0, 2.1, 4.0)],
		[Vector3(-18, 0.9, 45), Vector3(5.5, 1.4, 2.8)],
		[Vector3(32, 1.1, 42), Vector3(7.2, 1.8, 3.4)],
	]:
		_add_sphere(data[0], data[1], materials.cliff, false, "DistantIsland")


func _add_box(position: Vector3, size: Vector3, material: Material, solid := true, node_name := "Block", rotation := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.rotation_degrees = rotation
	body.collision_layer = WORLD_LAYER
	body.collision_mask = ACTOR_LAYER
	body.set_meta("surface", _surface_from_name(node_name))
	arena_root.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mesh_instance)

	if solid:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)

	return body


func _add_cylinder(position: Vector3, radius: float, height: float, material: Material, solid := true, node_name := "Cylinder", rotation := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.rotation_degrees = rotation
	body.collision_layer = WORLD_LAYER
	body.collision_mask = ACTOR_LAYER
	body.set_meta("surface", _surface_from_name(node_name))
	arena_root.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 48
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	if solid:
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = height
		shape.shape = cylinder
		body.add_child(shape)

	return body


func _add_sphere(position: Vector3, scale: Vector3, material: Material, solid := false, node_name := "Sphere") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.collision_layer = WORLD_LAYER
	body.collision_mask = ACTOR_LAYER
	body.set_meta("surface", _surface_from_name(node_name))
	arena_root.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh_instance.mesh = mesh
	mesh_instance.scale = scale
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mesh_instance)

	if solid:
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = maxf(scale.x, maxf(scale.y, scale.z))
		shape.shape = sphere
		body.add_child(shape)

	return body


func _surface_from_name(node_name: String) -> String:
	var lower := node_name.to_lower()
	if lower.contains("sand"):
		return "sand"
	if lower.contains("grass") or lower.contains("canopy") or lower.contains("leaf") or lower.contains("ivy"):
		return "grass"
	if lower.contains("cliff") or lower.contains("rock") or lower.contains("island"):
		return "stone"
	if lower.contains("water") or lower.contains("puddle"):
		return "water"
	if lower.contains("wood") or lower.contains("shack"):
		return "wood"
	if lower.contains("metal") or lower.contains("pillar") or lower.contains("ship") or lower.contains("bridge") or lower.contains("mast") or lower.contains("rail") or lower.contains("light") or lower.contains("rust") or lower.contains("car"):
		return "metal"
	return "concrete"


func _surface_from_hit(hit: Dictionary) -> String:
	if hit.is_empty() or not hit.has("collider"):
		return "concrete"
	var collider = hit["collider"]
	if collider is Node and collider.has_meta("surface"):
		return String(collider.get_meta("surface"))
	return "flesh" if collider is Area3D else "concrete"


func _spawn_tracer(start: Vector3, end: Vector3, color: Color, thickness: float) -> void:
	var length := start.distance_to(end)
	if length <= 0.05:
		return

	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, length)
	tracer.mesh = mesh
	tracer.material_override = _mat(color, color, 2.3, 0.0, 0.18)
	fx_root.add_child(tracer)
	tracer.global_position = start.lerp(end, 0.5)
	tracer.look_at(end)

	var tween := create_tween()
	tween.tween_property(tracer, "scale", Vector3(0.2, 0.2, 0.2), 0.075)
	tween.parallel().tween_property(tracer, "transparency", 1.0, 0.075)
	tween.tween_callback(tracer.queue_free)


func _spawn_muzzle_flash(position: Vector3, direction: Vector3, color: Color) -> void:
	var flash := Node3D.new()
	flash.name = "MuzzleFlash"
	fx_root.add_child(flash)
	flash.global_position = position
	if direction.length() > 0.01:
		flash.look_at(position + direction.normalized())

	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.08
	core_mesh.height = 0.16
	core.mesh = core_mesh
	core.material_override = _mat(Color(1.0, 0.86, 0.48), color, 4.5, 0.0, 0.1)
	flash.add_child(core)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 5.0
	flash.add_child(light)

	var particles := GPUParticles3D.new()
	particles.name = "MuzzleFlashParticles"
	particles.amount = 18
	particles.lifetime = 0.08
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = direction.normalized()
	process.spread = 19.0
	process.initial_velocity_min = 1.8
	process.initial_velocity_max = 4.5
	process.gravity = Vector3.ZERO
	process.scale_min = 0.025
	process.scale_max = 0.085
	process.color = Color(color.r, color.g, color.b, 0.9)
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	particles.set_draw_pass_mesh(0, quad)
	flash.add_child(particles)
	particles.emitting = true

	var tween := create_tween()
	tween.tween_property(core, "scale", Vector3.ONE * 1.8, 0.035)
	tween.parallel().tween_property(core, "transparency", 1.0, 0.045)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.055)
	tween.tween_interval(0.12)
	tween.tween_callback(flash.queue_free)


func _spawn_impact(position: Vector3, color: Color, size: float, normal := Vector3.UP, surface := "concrete") -> void:
	var pulse := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	pulse.mesh = mesh
	pulse.material_override = _mat(color, color, 2.6, 0.0, 0.18)
	fx_root.add_child(pulse)
	pulse.global_position = position

	var tween := create_tween()
	tween.tween_property(pulse, "scale", Vector3.ONE * 2.6, 0.11)
	tween.parallel().tween_property(pulse, "transparency", 1.0, 0.11)
	tween.tween_callback(pulse.queue_free)

	if surface != "flesh":
		_spawn_impact_decal(position, normal, color, surface)
	else:
		_spawn_blood_effect(position, normal)


func _spawn_impact_decal(position: Vector3, normal: Vector3, color: Color, surface: String) -> void:
	var decal := MeshInstance3D.new()
	decal.name = "%sImpactDecal" % surface.capitalize()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.34, 0.34)
	decal.mesh = mesh
	var material := StandardMaterial3D.new()
	var scorch := Color(0.035, 0.030, 0.026, 0.62)
	if surface == "sand":
		scorch = Color(0.20, 0.15, 0.09, 0.45)
	elif surface == "grass":
		scorch = Color(0.02, 0.09, 0.035, 0.40)
	elif surface == "metal":
		scorch = Color(color.r * 0.35, color.g * 0.45, color.b * 0.60, 0.55)
	elif surface == "stone":
		scorch = Color(0.05, 0.045, 0.04, 0.55)
	material.albedo_color = scorch
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	decal.material_override = material
	fx_root.add_child(decal)

	var n := normal.normalized()
	if n.length() < 0.01:
		n = Vector3.UP
	var tangent := n.cross(Vector3.UP)
	if tangent.length() < 0.01:
		tangent = n.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var binormal := tangent.cross(n).normalized()
	decal.global_transform = Transform3D(Basis(tangent, n, binormal), position + n * 0.018)

	var tween := create_tween()
	tween.tween_interval(8.0)
	tween.tween_property(decal, "transparency", 1.0, 0.7)
	tween.tween_callback(decal.queue_free)


func _spawn_blood_effect(position: Vector3, normal: Vector3) -> void:
	var n := normal.normalized()
	if n.length() < 0.01:
		n = Vector3.UP
	var blood_material := _mat(Color(0.52, 0.015, 0.018, 0.86), Color(0.08, 0.0, 0.0), 0.02, 0.0, 0.42)
	blood_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for index in range(12):
		var drop := MeshInstance3D.new()
		drop.name = "BloodDrop"
		var mesh := SphereMesh.new()
		mesh.radius = randf_range(0.018, 0.046)
		mesh.height = mesh.radius * 2.0
		drop.mesh = mesh
		drop.material_override = blood_material
		fx_root.add_child(drop)
		drop.global_position = position + n * 0.04
		var spray := (n + Vector3(randf_range(-0.85, 0.85), randf_range(0.0, 0.75), randf_range(-0.85, 0.85))).normalized()
		var target := drop.global_position + spray * randf_range(0.18, 0.72) + Vector3.DOWN * randf_range(0.03, 0.20)
		var tween := create_tween()
		tween.tween_property(drop, "global_position", target, randf_range(0.10, 0.22))
		tween.parallel().tween_property(drop, "scale", Vector3.ONE * randf_range(0.45, 0.75), 0.20)
		tween.tween_interval(0.28)
		tween.tween_property(drop, "transparency", 1.0, 0.25)
		tween.tween_callback(drop.queue_free)

	var mist := GPUParticles3D.new()
	mist.name = "BloodMist"
	mist.amount = 26
	mist.lifetime = 0.22
	mist.one_shot = true
	mist.explosiveness = 1.0
	mist.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = n
	process.spread = 42.0
	process.initial_velocity_min = 0.9
	process.initial_velocity_max = 3.2
	process.gravity = Vector3(0, -5.2, 0)
	process.scale_min = 0.025
	process.scale_max = 0.075
	process.color = Color(0.62, 0.02, 0.025, 0.72)
	mist.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	mist.set_draw_pass_mesh(0, quad)
	fx_root.add_child(mist)
	mist.global_position = position + n * 0.05
	mist.emitting = true
	var mist_tween := create_tween()
	mist_tween.tween_interval(0.55)
	mist_tween.tween_callback(mist.queue_free)


func _raycast(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	var params := PhysicsRayQueryParameters3D.create(from, to, mask)
	params.exclude = exclude
	params.collide_with_areas = true
	params.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(params)


func _choose_spawn(actor) -> Vector3:
	var best: Vector3 = spawn_points[0]
	var best_score := -INF
	for spawn in spawn_points:
		var score := 999.0
		if player and player != actor and player.alive:
			score = minf(score, spawn.distance_to(player.global_position))
		for bot in bots:
			if bot != actor and bot.alive:
				score = minf(score, spawn.distance_to(bot.global_position))
		if score > best_score:
			best_score = score
			best = spawn
	return best


func _add_feed(text: String) -> void:
	feed.push_front(text)
	if feed.size() > 5:
		feed.resize(5)


func _end_match(reason: String) -> void:
	if not game_active:
		return
	game_active = false
	_add_feed(reason)
	if audio:
		audio.play_2d("match_end", -6.0)


func _install_input_map() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("sprint", KEY_SHIFT)
	_bind_key("crouch", KEY_CTRL)
	_bind_key("jump", KEY_SPACE)
	_bind_key("reload", KEY_R)
	_bind_key("weapon_1", KEY_1)
	_bind_key("weapon_2", KEY_2)
	_bind_key("weapon_3", KEY_3)
	_bind_key("restart_match", KEY_ENTER)
	_bind_mouse("fire", MOUSE_BUTTON_LEFT)


func _bind_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _bind_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
