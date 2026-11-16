extends Node2D

func _process(_delta: float) -> void:
  queue_redraw()

## Outlines stay aligned to board cells even when the building rotates.
func _draw() -> void:
  var game = get_parent()
  if game.simulating: return
  for building in game.buildings:
    if not is_instance_valid(building): continue
    var fixed_position: bool = building.get_meta("fixed_position")
    var can_rotate: bool = building.get_meta("kind") in ["emitter", "mirror"] and not building.get_meta("fixed_rotation")
    var colour := Color("66d8b2") # movable
    if fixed_position:
      colour = Color("f4c55d") if can_rotate else Color("f17f81")
    var rectangle := Rect2(building.position - Vector2.ONE * game.CELL * 0.48, Vector2.ONE * game.CELL * 0.96)
    draw_rect(rectangle, colour, false, 3.0)
    if building == game.selected_building:
      draw_rect(rectangle.grow(-5.0), Color.WHITE, false, 2.0)
