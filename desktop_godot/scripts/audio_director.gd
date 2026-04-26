extends Node

var streams := {}
var footstep_streams := {}

func _ready() -> void:
	streams["rifle"] = _make_burst(0.12, 135.0, 0.55, 0.35)
	streams["smg"] = _make_burst(0.075, 210.0, 0.48, 0.28)
	streams["pistol"] = _make_burst(0.10, 165.0, 0.52, 0.18)
	streams["bot_fire"] = _make_burst(0.08, 120.0, 0.38, 0.24)
	streams["hit"] = _make_tone(0.055, 920.0, 0.30)
	streams["kill"] = _make_tone(0.18, 540.0, 0.24)
	streams["reload"] = _make_tone(0.16, 240.0, 0.18)
	streams["match_end"] = _make_tone(0.34, 110.0, 0.22)
	_build_footstep_bank()


func play_2d(id: String, volume_db := -8.0) -> void:
	if not streams.has(id):
		return
	var player := AudioStreamPlayer.new()
	player.stream = streams[id]
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	_free_after(player, player.stream.get_length() + 0.05)


func play_3d(id: String, position: Vector3, volume_db := -8.0) -> void:
	if not streams.has(id):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = streams[id]
	player.volume_db = volume_db
	player.max_distance = 48.0
	add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()
	_free_after(player, player.stream.get_length() + 0.05)


func play_footstep(surface: String, position: Vector3, intensity: float) -> void:
	var bank: Array = footstep_streams.get(surface, footstep_streams.get("concrete", []))
	if bank.is_empty():
		return
	var stream = bank.pick_random()
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = lerpf(-18.0, -9.0, clampf(intensity, 0.0, 1.0))
	player.pitch_scale = randf_range(0.92, 1.08)
	player.max_distance = 18.0
	add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()
	_free_after(player, player.stream.get_length() + 0.05)


func _free_after(node: Node, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(node):
		node.queue_free()


func _build_footstep_bank() -> void:
	for surface in ["concrete", "sand", "grass", "stone", "metal", "water", "wood"]:
		var loaded := _load_surface_steps(surface)
		if loaded.is_empty():
			loaded = _make_surface_steps(surface)
		footstep_streams[surface] = loaded


func _load_surface_steps(surface: String) -> Array:
	var loaded := []
	for index in range(1, 5):
		for extension in ["wav", "ogg", "mp3"]:
			var path := "res://assets/audio/footsteps/%s_%d.%s" % [surface, index, extension]
			if ResourceLoader.exists(path):
				var stream = load(path)
				if stream is AudioStream:
					loaded.append(stream)
	return loaded


func _make_surface_steps(surface: String) -> Array:
	var specs := {
		"concrete": [0.095, 150.0, 0.26, 0.45],
		"sand": [0.125, 95.0, 0.18, 0.68],
		"grass": [0.115, 125.0, 0.15, 0.78],
		"stone": [0.090, 180.0, 0.24, 0.55],
		"metal": [0.080, 260.0, 0.22, 0.36],
		"water": [0.130, 80.0, 0.18, 0.85],
		"wood": [0.100, 210.0, 0.20, 0.48],
	}
	var spec: Array = specs.get(surface, specs["concrete"])
	var result := []
	for index in range(4):
		result.append(_make_footstep(spec[0], spec[1] + index * 17.0, spec[2], spec[3], surface))
	return result


func _make_footstep(duration: float, frequency: float, volume: float, noise: float, surface: String) -> AudioStreamWAV:
	var sample_rate := 44100
	var sample_count := int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in range(sample_count):
		var t := float(index) / sample_rate
		var envelope := exp(-t * 26.0)
		var thump := sin(t * TAU * frequency) * 0.65
		var scrape := randf_range(-1.0, 1.0) * noise
		var grit := sin(t * TAU * frequency * 2.7) * 0.18
		if surface == "sand" or surface == "grass":
			thump *= 0.35
			grit *= 0.55
		elif surface == "metal":
			grit += sin(t * TAU * frequency * 4.2) * 0.28
		elif surface == "water":
			thump *= 0.2
			grit += sin(t * TAU * 22.0) * 0.25
		elif surface == "wood":
			thump *= 0.85
			grit += sin(t * TAU * frequency * 3.4) * 0.18
		var value := (thump + scrape + grit) * volume * envelope
		bytes.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	return _wav(bytes, sample_rate)


func _make_tone(duration: float, frequency: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 44100
	var sample_count := int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in range(sample_count):
		var t := float(index) / sample_rate
		var envelope := pow(1.0 - t / duration, 2.0)
		var value := sin(t * TAU * frequency) * volume * envelope
		bytes.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	return _wav(bytes, sample_rate)


func _make_burst(duration: float, frequency: float, volume: float, noise: float) -> AudioStreamWAV:
	var sample_rate := 44100
	var sample_count := int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in range(sample_count):
		var t := float(index) / sample_rate
		var envelope := pow(1.0 - t / duration, 3.2)
		var tone := sin(t * TAU * frequency) + sin(t * TAU * frequency * 0.51) * 0.45
		var grit := randf_range(-1.0, 1.0) * noise
		var value := (tone + grit) * volume * envelope
		bytes.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	return _wav(bytes, sample_rate)


func _wav(bytes: PackedByteArray, sample_rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream
