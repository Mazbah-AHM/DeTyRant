extends Node

var streams := {}

func _ready() -> void:
	streams["rifle"] = _make_burst(0.12, 135.0, 0.55, 0.35)
	streams["smg"] = _make_burst(0.075, 210.0, 0.48, 0.28)
	streams["pistol"] = _make_burst(0.10, 165.0, 0.52, 0.18)
	streams["bot_fire"] = _make_burst(0.08, 120.0, 0.38, 0.24)
	streams["hit"] = _make_tone(0.055, 920.0, 0.30)
	streams["kill"] = _make_tone(0.18, 540.0, 0.24)
	streams["reload"] = _make_tone(0.16, 240.0, 0.18)
	streams["match_end"] = _make_tone(0.34, 110.0, 0.22)


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


func _free_after(node: Node, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(node):
		node.queue_free()


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
