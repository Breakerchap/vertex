extends Node2D

var events: Array[Dictionary] = []

func add_event(kind: String, at: Vector2) -> void:
  events.append({"kind": kind, "position": to_local(at), "life": 2.0})
  if events.size() > 80: events.pop_front()

func clear_events() -> void:
  events.clear()
  queue_redraw()

func _process(delta: float) -> void:
  for i in range(events.size() - 1, -1, -1):
    events[i]["life"] = float(events[i].life) - delta
    if events[i].life <= 0.0: events.remove_at(i)
  queue_redraw()

## Always align outlines and placement previews with grid cells, not sprite rotation.
func _draw() -> void:
  var game = get_parent()
  if not game.simulating:
    for building in game.buildings:
      if not is_instance_valid(building): continue
      var fixed_position: bool = building.get_meta("fixed_position")
      var can_rotate: bool = building.get_meta("kind") in ["emitter", "mirror", "magnet"] and not building.get_meta("fixed_rotation")
      var colour := Color("66d8b2")
      if fixed_position:
        colour = Color("f4c55d") if can_rotate else Color("f17f81")
      var rectangle := Rect2(building.position - Vector2.ONE * game.CELL * 0.48, Vector2.ONE * game.CELL * 0.96)
      draw_rect(rectangle, colour, false, 3.0)
      if building == game.selected_building:
        draw_rect(rectangle.grow(-5.0), Color.WHITE, false, 2.0)

    var hover: Vector2i = game._mouse_cell()
    if hover.x >= 0 and hover.y >= 0 and hover.x < int(game.level.get("width", 0)) and hover.y < int(game.level.get("height", 0)):
      var kind: String = game.editor_brush if game.editor_preview else game.selected_kind
      if not game.editor_preview and is_instance_valid(game.palette) and not game.palette.drag_kind.is_empty():
        kind = game.palette.drag_kind
      var dragging_building: bool = game.drag_cell.x >= 0 and is_instance_valid(game.selected_building)
      var can_place: bool = not kind.is_empty() or dragging_building
      if can_place:
        var occupied = game._building_at(hover)
        var valid: bool = occupied == null
        if dragging_building:
          valid = valid and not game.selected_building.get_meta("fixed_position")
        var pos := game._cell_position(hover)
        var rect := Rect2(pos - Vector2.ONE * game.CELL * 0.47, Vector2.ONE * game.CELL * 0.94)
        var colour := Color("69d8ad", 0.22) if valid else Color("ec7377", 0.24)
        draw_rect(rect, colour, true)
        draw_rect(rect, Color("69d8ad") if valid else Color("ec7377"), false, 3.0)

  if not game.diagnostics_enabled: return
  var colours := {
    "reflection": Color("8fc7ff"),
    "field": Color("ceaeff"),
    "detection": Color("75dcb0"),
    "annihilation": Color("ffe08a"),
    "absorption": Color("ee8585"),
    "exit": Color("ee8585")
  }
  for event in events:
    var shade: Color = colours.get(event.kind, Color.WHITE)
    shade.a = clampf(float(event.life) / 2.0, 0.0, 1.0)
    var at: Vector2 = event.position
    draw_arc(at, 11.0 + (2.0 - float(event.life)) * 7.0, 0, TAU, 24, shade, 2.5)
    draw_circle(at, 3.0, shade)
