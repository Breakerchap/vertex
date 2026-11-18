extends Control

signal cell_clicked(cell: Vector2i, button: int)

const CELL := 48.0
var level: Dictionary = {}
var selected := Vector2i(-1, -1)
var icons: Dictionary = {}

func _draw() -> void:
  if level.is_empty(): return
  for x in range(level.width):
    for y in range(level.height):
      var rect := Rect2(x * CELL, (level.height - 1 - y) * CELL, CELL, CELL)
      draw_rect(rect, Color("253247"))
      draw_rect(rect, Color("40516a"), false, 1.0)
      if selected == Vector2i(x, y): draw_rect(rect.grow(-2), Color("f4c55d"), false, 3.0)
  for entry in level.buildings:
    var rect := Rect2(entry.x * CELL, (level.height - 1 - entry.y) * CELL, CELL, CELL)
    if icons.has(entry.kind):
      draw_texture_rect(icons[entry.kind], rect.grow(-5), false)
    else:
      draw_circle(rect.get_center(), CELL * 0.35, Color("6ba9c4"))
    var letter: String = str(entry.kind).substr(0, 1).to_upper()
    draw_string(ThemeDB.fallback_font, rect.position + Vector2(3, 14), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
    if entry.kind in ["emitter", "mirror"]:
      var directions := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
      var angle := directions.find(entry.facing) * PI / 4.0
      var direction := Vector2.RIGHT.rotated(angle)
      var tip := rect.get_center() + direction * 16.0
      draw_line(rect.get_center(), tip, Color.WHITE, 2.5)
      draw_line(tip, tip - direction.rotated(0.6) * 7.0, Color.WHITE, 2.0)
      draw_line(tip, tip - direction.rotated(-0.6) * 7.0, Color.WHITE, 2.0)
    elif entry.kind == "magnet":
      var polarity := str(entry.get("polarity", "positive"))
      var sign_text := "−" if polarity in ["negative", "-", "-1", "n"] else "+"
      draw_string(ThemeDB.fallback_font, rect.position + Vector2(18, 32), sign_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

func set_level(data: Dictionary) -> void:
  level = data
  custom_minimum_size = Vector2(data.width, data.height) * CELL if not data.is_empty() else Vector2(240, 240)
  queue_redraw()

func _gui_input(event: InputEvent) -> void:
  if level.is_empty() or not event is InputEventMouseButton or not event.pressed: return
  var x := floori(event.position.x / CELL)
  var y := int(level.height) - 1 - floori(event.position.y / CELL)
  if x >= 0 and y >= 0 and x < level.width and y < level.height:
    cell_clicked.emit(Vector2i(x, y), event.button_index)
