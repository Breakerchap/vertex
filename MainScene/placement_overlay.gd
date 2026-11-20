extends Node2D

const CATALOG = preload("res://Buildings/building_catalog.gd")

const EVENT_COLOURS := {
  "reflection": Color("8fc7ff"),
  "field": Color("ceaeff"),
  "detection": Color("75dcb0"),
  "annihilation": Color("ffe08a"),
  "fusion": Color("ffc681"),
  "absorption": Color("ee8585"),
  "exit": Color("ee8585"),
}

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
  if game.level.is_empty() or game.level.has("error"): return
  if not game.simulating:
    for building in game.buildings:
      if not is_instance_valid(building): continue
      var fixed_position: bool = building.get_meta("fixed_position")
      var can_rotate: bool = building.get_meta("kind") in CATALOG.ROTATABLE_KINDS and not building.get_meta("fixed_rotation")
      var colour := Color("66d8b2")
      if fixed_position:
        colour = Color("f4c55d") if can_rotate else Color("f17f81")
      var kind: String = building.get_meta("kind")
      var facing := str(CATALOG.DIRECTIONS[building.orientation]) if kind == "edge_wall" else "E"
      var rectangle := _outline(kind, building.position, facing)
      draw_rect(rectangle, colour, false, 3.0)
      if building == game.selected_building:
        draw_rect(rectangle.grow(2.0), Color.WHITE, false, 2.0)

    var hover: Vector2i = game._mouse_cell()
    if game.is_cell_on_board(hover):
      var palette = game.external_palette if game.editor_preview else game.palette
      var kind: String = game.selected_kind
      if is_instance_valid(palette):
        if game.editor_preview:
          kind = palette.selected
        if not palette.drag_kind.is_empty():
          kind = palette.drag_kind
      var dragging_building: bool = game.drag_cell.x >= 0 and is_instance_valid(game.selected_building)
      if kind.is_empty() and is_instance_valid(game.selected_building) and not game.selected_building.get_meta("fixed_position"):
        dragging_building = true
      var can_place: bool = not kind.is_empty() or dragging_building
      if can_place:
        var facing := "E"
        if kind.is_empty():
          kind = game.selected_building.get_meta("kind")
          if kind == "edge_wall":
            facing = CATALOG.DIRECTIONS[game.selected_building.orientation]
        elif kind == "edge_wall":
          facing = game._edge_facing(hover, game.get_global_mouse_position())
        var valid: bool = game._building_at(hover, kind, facing) == null
        if dragging_building:
          valid = valid and (game.editor_preview or not game.selected_building.get_meta("fixed_position"))
        var rect := _outline(kind, game._cell_position(hover), facing)
        var colour := Color("69d8ad", 0.22) if valid else Color("ec7377", 0.24)
        draw_rect(rect, colour, true)
        draw_rect(rect, Color("69d8ad") if valid else Color("ec7377"), false, 3.0)

  for event in events:
    var shade: Color = EVENT_COLOURS.get(event.kind, Color.WHITE)
    shade.a = clampf(float(event.life) / 2.0, 0.0, 1.0)
    var at: Vector2 = event.position
    draw_arc(at, 11.0 + (2.0 - float(event.life)) * 7.0, 0, TAU, 24, shade, 2.5)
    draw_circle(at, 3.0, shade)


func _outline(kind: String, at: Vector2, facing: String) -> Rect2:
  var cell := SimulationGrid.CELL
  var size := Vector2.ONE * cell * 0.94
  if kind == "edge_wall":
    var normal: Vector2 = SimulationGrid.VECTORS[CATALOG.DIRECTIONS.find(facing)]
    at += normal * cell * 0.5
    size = normal.abs() * cell * 0.1 + normal.orthogonal().abs() * cell * 0.98
  return Rect2(at - size * 0.5, size)
