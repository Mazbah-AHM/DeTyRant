extends CanvasLayer

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
var crosshair_gap := 9.0
var hit_marker := 0.0

func _ready() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	damage_flash = ColorRect.new()
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash.color = Color(0.65, 0.02, 0.03, 0.0)
	root.add_child(damage_flash)

	var left_panel := _panel(Vector2(22, 22), Vector2(290, 128), Color(0.01, 0.025, 0.04, 0.58))
	root.add_child(left_panel)
	health_label = _label(Vector2(42, 36), 30, Color(0.92, 0.98, 1.0))
	weapon_label = _label(Vector2(42, 74), 16, Color(0.44, 0.9, 1.0))
	ammo_label = _label(Vector2(42, 100), 20, Color(0.88, 0.94, 1.0))
	root.add_child(health_label)
	root.add_child(weapon_label)
	root.add_child(ammo_label)

	var health_back := ColorRect.new()
	health_back.position = Vector2(42, 132)
	health_back.size = Vector2(230, 5)
	health_back.color = Color(0.16, 0.19, 0.24, 0.9)
	root.add_child(health_back)
	health_bar = ColorRect.new()
	health_bar.position = health_back.position
	health_bar.size = health_back.size
	health_bar.color = Color(0.22, 0.9, 1.0, 0.95)
	root.add_child(health_bar)

	var right_panel := _panel(Vector2(1280, 22), Vector2(298, 112), Color(0.01, 0.025, 0.04, 0.52))
	root.add_child(right_panel)
	timer_label = _label(Vector2(1304, 36), 26, Color(0.94, 0.98, 1.0))
	score_label = _label(Vector2(1304, 76), 18, Color(0.74, 0.86, 0.94))
	root.add_child(timer_label)
	root.add_child(score_label)

	state_label = _label(Vector2(620, 32), 18, Color(1.0, 0.72, 0.36))
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.size = Vector2(360, 30)
	root.add_child(state_label)

	feed_label = _label(Vector2(1160, 690), 16, Color(0.86, 0.94, 1.0))
	feed_label.size = Vector2(390, 160)
	feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(feed_label)

	crosshair = Control.new()
	crosshair.position = Vector2(800, 450)
	crosshair.size = Vector2.ZERO
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)


func update_match(player, bots: Array, seconds: float, active: bool, feed: Array[String]) -> void:
	if not player:
		return

	health_label.text = "%d HP" % int(ceil(player.health))
	weapon_label.text = player.weapon_name().to_upper()
	ammo_label.text = "%02d  /  INF" % player.magazine
	score_label.text = "ELIMS %d    DEATHS %d" % [player.kills, player.deaths]
	var total_seconds := int(ceil(seconds))
	timer_label.text = "%02d:%02d" % [floori(total_seconds / 60.0), total_seconds % 60]
	state_label.text = "" if active else "MATCH COMPLETE - ENTER TO RESET"
	feed_label.text = "\n".join(feed)
	health_bar.size.x = 230.0 * clampf(player.health / player.max_health, 0.0, 1.0)
	damage_flash.color.a = clampf(player.damage_flash * 0.10, 0.0, 0.10)
	crosshair_gap = 9.0 + player.spread_bloom * 180.0 + clampf(Vector2(player.velocity.x, player.velocity.z).length() * 0.42, 0.0, 5.5)
	hit_marker = player.hit_marker
	crosshair.queue_redraw()


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
