extends CanvasLayer

signal start_requested(settings: Dictionary)

var root: Control
var menu_layer: Control
var result_label: Label
var result_layer: Control
var result_details_label: Label
var bot_count_spin: SpinBox
var difficulty_option: OptionButton
var minutes_spin: SpinBox
var kill_limit_spin: SpinBox

var health_label: Label
var weapon_label: Label
var ammo_label: Label
var score_label: Label
var timer_label: Label
var state_label: Label
var feed_label: Label
var health_bar: ColorRect
var damage_flash: ColorRect
var crosshair: Control
var minimap: Control
var match_controls: Array[CanvasItem] = []

var crosshair_gap := 9.0
var hit_marker := 0.0
var minimap_player_position := Vector3.ZERO
var minimap_player_yaw := 0.0
var minimap_bot_positions: Array[Vector3] = []


func _ready() -> void:
	root = Control.new()
	root.name = "HUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_match_hud()
	_build_start_menu()
	_build_result_screen()
	show_start_menu()


func update_match(player, bots: Array, seconds: float, active: bool, feed: Array[String], started: bool, result_text := "") -> void:
	if not started:
		return
	if not player:
		return

	_set_match_hud_visible(true)
	health_label.text = "%d HP" % int(ceil(player.health))
	weapon_label.text = player.weapon_name().to_upper()
	ammo_label.text = "%02d  /  INF" % player.magazine
	score_label.text = "ELIMS %d    DEATHS %d    K/D %.2f" % [player.kills, player.deaths, _kd_ratio(player.kills, player.deaths)]
	var total_seconds := int(ceil(seconds))
	timer_label.text = "%02d:%02d" % [floori(total_seconds / 60.0), total_seconds % 60]
	state_label.text = "" if active else result_text
	feed_label.text = "\n".join(feed)
	health_bar.size.x = 230.0 * clampf(player.health / player.max_health, 0.0, 1.0)
	damage_flash.color.a = clampf(player.damage_flash * 0.10, 0.0, 0.10)
	crosshair_gap = 9.0 + player.spread_bloom * 180.0 + clampf(Vector2(player.velocity.x, player.velocity.z).length() * 0.42, 0.0, 5.5)
	hit_marker = player.hit_marker
	minimap_player_position = player.global_position
	minimap_player_yaw = player.rotation.y
	minimap_bot_positions.clear()
	for bot in bots:
		if bot and bot.alive:
			minimap_bot_positions.append(bot.global_position)
	crosshair.queue_redraw()
	minimap.queue_redraw()


func show_start_menu(result_text := "") -> void:
	if result_layer:
		result_layer.visible = false
	if menu_layer:
		menu_layer.visible = true
	if result_label:
		result_label.text = result_text
		result_label.visible = result_text != ""
	_set_match_hud_visible(false)


func hide_start_menu() -> void:
	if menu_layer:
		menu_layer.visible = false
	if result_layer:
		result_layer.visible = false
	_set_match_hud_visible(true)


func show_result_screen(result_text: String) -> void:
	if menu_layer:
		menu_layer.visible = false
	if result_layer:
		result_layer.visible = true
	if result_details_label:
		result_details_label.text = result_text
	_set_match_hud_visible(false)


func _build_match_hud() -> void:
	damage_flash = ColorRect.new()
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash.color = Color(0.65, 0.02, 0.03, 0.0)
	root.add_child(damage_flash)
	match_controls.append(damage_flash)

	minimap = Control.new()
	minimap.position = Vector2(26, 24)
	minimap.size = Vector2(190, 190)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	root.add_child(minimap)
	match_controls.append(minimap)

	var left_panel := _panel(Vector2(22, 740), Vector2(290, 128), Color(0.01, 0.025, 0.04, 0.58))
	root.add_child(left_panel)
	match_controls.append(left_panel)
	health_label = _label(Vector2(42, 754), 30, Color(0.92, 0.98, 1.0))
	weapon_label = _label(Vector2(42, 792), 16, Color(0.44, 0.9, 1.0))
	ammo_label = _label(Vector2(42, 818), 20, Color(0.88, 0.94, 1.0))
	root.add_child(health_label)
	root.add_child(weapon_label)
	root.add_child(ammo_label)
	match_controls.append(health_label)
	match_controls.append(weapon_label)
	match_controls.append(ammo_label)

	var health_back := ColorRect.new()
	health_back.position = Vector2(42, 850)
	health_back.size = Vector2(230, 5)
	health_back.color = Color(0.16, 0.19, 0.24, 0.9)
	root.add_child(health_back)
	match_controls.append(health_back)
	health_bar = ColorRect.new()
	health_bar.position = health_back.position
	health_bar.size = health_back.size
	health_bar.color = Color(0.22, 0.9, 1.0, 0.95)
	root.add_child(health_bar)
	match_controls.append(health_bar)

	var right_panel := _panel(Vector2(1280, 744), Vector2(298, 112), Color(0.01, 0.025, 0.04, 0.52))
	root.add_child(right_panel)
	match_controls.append(right_panel)
	timer_label = _label(Vector2(1304, 758), 26, Color(0.94, 0.98, 1.0))
	score_label = _label(Vector2(1304, 798), 18, Color(0.74, 0.86, 0.94))
	root.add_child(timer_label)
	root.add_child(score_label)
	match_controls.append(timer_label)
	match_controls.append(score_label)

	state_label = _label(Vector2(520, 820), 18, Color(1.0, 0.72, 0.36))
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.size = Vector2(560, 30)
	root.add_child(state_label)
	match_controls.append(state_label)

	feed_label = _label(Vector2(1160, 580), 16, Color(0.86, 0.94, 1.0))
	feed_label.size = Vector2(390, 160)
	feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(feed_label)
	match_controls.append(feed_label)

	crosshair = Control.new()
	crosshair.position = Vector2(800, 450)
	crosshair.size = Vector2.ZERO
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)
	match_controls.append(crosshair)


func _build_start_menu() -> void:
	menu_layer = Control.new()
	menu_layer.name = "StartMenu"
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(menu_layer)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.54)
	menu_layer.add_child(shade)

	var panel := ColorRect.new()
	panel.position = Vector2(520, 150)
	panel.size = Vector2(560, 600)
	panel.color = Color(0.018, 0.026, 0.028, 0.92)
	menu_layer.add_child(panel)

	var title := _menu_label(Vector2(560, 190), "DETYRANT", 44, Color(0.92, 0.98, 1.0))
	menu_layer.add_child(title)
	var subtitle := _menu_label(Vector2(562, 244), "Configure your combat test, then deploy.", 18, Color(0.58, 0.75, 0.72))
	menu_layer.add_child(subtitle)

	result_label = _menu_label(Vector2(560, 282), "", 22, Color(1.0, 0.72, 0.32))
	result_label.size = Vector2(480, 58)
	result_label.visible = false
	menu_layer.add_child(result_label)

	_add_menu_field("Bots", Vector2(560, 352))
	bot_count_spin = SpinBox.new()
	bot_count_spin.position = Vector2(760, 342)
	bot_count_spin.size = Vector2(220, 44)
	bot_count_spin.min_value = 1
	bot_count_spin.max_value = 12
	bot_count_spin.step = 1
	bot_count_spin.value = 1
	menu_layer.add_child(bot_count_spin)

	_add_menu_field("Difficulty", Vector2(560, 422))
	difficulty_option = OptionButton.new()
	difficulty_option.position = Vector2(760, 412)
	difficulty_option.size = Vector2(220, 44)
	for label in ["Easy", "Normal", "Hard", "Nightmare"]:
		difficulty_option.add_item(label)
	difficulty_option.select(1)
	menu_layer.add_child(difficulty_option)

	_add_menu_field("Match Time", Vector2(560, 492))
	minutes_spin = SpinBox.new()
	minutes_spin.position = Vector2(760, 482)
	minutes_spin.size = Vector2(220, 44)
	minutes_spin.min_value = 1
	minutes_spin.max_value = 30
	minutes_spin.step = 1
	minutes_spin.value = 5
	minutes_spin.suffix = " min"
	menu_layer.add_child(minutes_spin)

	_add_menu_field("Kill Limit", Vector2(560, 562))
	kill_limit_spin = SpinBox.new()
	kill_limit_spin.position = Vector2(760, 552)
	kill_limit_spin.size = Vector2(220, 44)
	kill_limit_spin.min_value = 1
	kill_limit_spin.max_value = 100
	kill_limit_spin.step = 1
	kill_limit_spin.value = 30
	menu_layer.add_child(kill_limit_spin)

	var play_button := Button.new()
	play_button.text = "PLAY"
	play_button.position = Vector2(560, 646)
	play_button.size = Vector2(420, 58)
	play_button.add_theme_font_size_override("font_size", 24)
	play_button.pressed.connect(_on_play_pressed)
	menu_layer.add_child(play_button)

	var hint := _menu_label(Vector2(560, 716), "Win condition: finish with more eliminations than deaths.", 14, Color(0.58, 0.68, 0.66))
	hint.size = Vector2(460, 24)
	menu_layer.add_child(hint)


func _build_result_screen() -> void:
	result_layer = Control.new()
	result_layer.name = "ResultScreen"
	result_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(result_layer)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.64)
	result_layer.add_child(shade)

	var panel := ColorRect.new()
	panel.position = Vector2(500, 186)
	panel.size = Vector2(600, 528)
	panel.color = Color(0.014, 0.024, 0.026, 0.94)
	result_layer.add_child(panel)

	var title := _menu_label(Vector2(560, 232), "MATCH RESULT", 38, Color(0.92, 0.98, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_layer.add_child(title)

	result_details_label = _menu_label(Vector2(560, 308), "", 24, Color(0.82, 0.94, 0.92))
	result_details_label.size = Vector2(480, 210)
	result_details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_details_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_layer.add_child(result_details_label)

	var play_again_button := Button.new()
	play_again_button.text = "PLAY AGAIN"
	play_again_button.position = Vector2(590, 576)
	play_again_button.size = Vector2(420, 58)
	play_again_button.add_theme_font_size_override("font_size", 24)
	play_again_button.pressed.connect(_on_play_again_pressed)
	result_layer.add_child(play_again_button)

	var hint := _menu_label(Vector2(560, 650), "Return to setup, adjust match settings, then deploy again.", 14, Color(0.58, 0.68, 0.66))
	hint.size = Vector2(480, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_layer.add_child(hint)

	result_layer.visible = false


func _on_play_pressed() -> void:
	var selected := difficulty_option.get_selected_id()
	var difficulty := difficulty_option.get_item_text(selected)
	start_requested.emit({
		"bot_count": int(bot_count_spin.value),
		"difficulty": difficulty,
		"minutes": int(minutes_spin.value),
		"kill_limit": int(kill_limit_spin.value),
	})


func _on_play_again_pressed() -> void:
	show_start_menu()


func _draw_crosshair() -> void:
	var color := Color(0.90, 0.98, 1.0, 0.88)
	var accent := Color(0.24, 0.88, 1.0, 0.92)
	var hit := Color(1.0, 0.78, 0.22, 0.94)
	var gap := crosshair_gap
	var length := 11.0
	crosshair.draw_line(Vector2(-gap - length, 0), Vector2(-gap, 0), color, 1.6)
	crosshair.draw_line(Vector2(gap, 0), Vector2(gap + length, 0), color, 1.6)
	crosshair.draw_line(Vector2(0, -gap - length), Vector2(0, -gap), color, 1.6)
	crosshair.draw_line(Vector2(0, gap), Vector2(0, gap + length), color, 1.6)
	crosshair.draw_circle(Vector2.ZERO, 1.45, accent)
	if hit_marker > 0.0:
		crosshair.draw_line(Vector2(-13, -13), Vector2(-6, -6), hit, 2.2)
		crosshair.draw_line(Vector2(13, -13), Vector2(6, -6), hit, 2.2)
		crosshair.draw_line(Vector2(-13, 13), Vector2(-6, 6), hit, 2.2)
		crosshair.draw_line(Vector2(13, 13), Vector2(6, 6), hit, 2.2)


func _draw_minimap() -> void:
	var center := minimap.size * 0.5
	var radius := 86.0
	minimap.draw_circle(center, radius + 7.0, Color(0.0, 0.0, 0.0, 0.35))
	minimap.draw_circle(center, radius, Color(0.018, 0.032, 0.034, 0.72))
	minimap.draw_arc(center, radius, 0.0, TAU, 96, Color(0.38, 0.70, 0.66, 0.78), 2.0)
	minimap.draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), Color(0.30, 0.46, 0.44, 0.22), 1.0)
	minimap.draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), Color(0.30, 0.46, 0.44, 0.22), 1.0)
	for angle_index in range(8):
		var angle := float(angle_index) / 8.0 * TAU
		var start := center + Vector2(cos(angle), sin(angle)) * (radius - 12.0)
		var end := center + Vector2(cos(angle), sin(angle)) * radius
		minimap.draw_line(start, end, Color(0.62, 0.82, 0.76, 0.28), 1.0)

	for bot_position in minimap_bot_positions:
		var delta := bot_position - minimap_player_position
		var blip := Vector2(delta.x, delta.z) * 2.25
		if blip.length() > radius - 10.0:
			blip = blip.normalized() * (radius - 10.0)
		minimap.draw_circle(center + blip, 5.0, Color(0.98, 0.15, 0.10, 0.96))

	var forward := Vector2(-sin(minimap_player_yaw), -cos(minimap_player_yaw))
	var right := Vector2(forward.y, -forward.x)
	var p0 := center + forward * 12.0
	var p1 := center - forward * 8.0 + right * 7.0
	var p2 := center - forward * 8.0 - right * 7.0
	minimap.draw_colored_polygon(PackedVector2Array([p0, p1, p2]), Color(0.18, 0.90, 1.0, 0.96))


func _set_match_hud_visible(visible: bool) -> void:
	for item in match_controls:
		item.visible = visible


func _kd_ratio(kills: int, deaths: int) -> float:
	if deaths <= 0:
		return float(kills)
	return float(kills) / float(deaths)


func _add_menu_field(text: String, position: Vector2) -> void:
	var label := _menu_label(position, text, 18, Color(0.78, 0.88, 0.84))
	label.size = Vector2(180, 32)
	menu_layer.add_child(label)


func _panel(position: Vector2, size: Vector2, color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.position = position
	panel.size = size
	panel.color = color
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _label(position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _menu_label(position: Vector2, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = Vector2(480, 40)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label
