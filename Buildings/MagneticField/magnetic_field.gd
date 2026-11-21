@tool
extends "res://Buildings/building.gd"

const HALF_CELL := GRID_SIZE * 0.5
const PLUS_TEXTURE = preload("res://Buildings/MagneticField/plus_magnet.png")
const MINUS_TEXTURE = preload("res://Buildings/MagneticField/minus_magnet.png")

@export_enum("Positive:1", "Negative:-1") var polarity: int = 1:
  set(value):
    polarity = 1 if value >= 0 else -1
    queue_redraw()

func _ready() -> void:
  super._ready()
  if not Engine.is_editor_hint():
    add_to_group("magnetic_fields")

func exit_heading(direction: Vector2, charge: int, exact := false) -> Vector2:
  var turn := PI * 0.5 if charge * polarity > 0 else -PI * 0.5
  var rotated := direction.rotated(turn)
  return rotated if exact else SimulationGrid.heading(rotated)

func _draw() -> void:
  var texture: Texture2D = PLUS_TEXTURE if polarity > 0 else MINUS_TEXTURE
  draw_texture_rect(texture, Rect2(-HALF_CELL, -HALF_CELL, HALF_CELL * 2, HALF_CELL * 2), false)
