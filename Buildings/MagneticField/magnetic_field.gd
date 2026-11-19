@tool
extends "res://Buildings/building.gd"

const HALF_CELL := GRID_SIZE * 0.5
const EPSILON: float = 0.00001
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

func _draw() -> void:
  var texture: Texture2D = PLUS_TEXTURE if polarity > 0 else MINUS_TEXTURE
  draw_texture_rect(texture, Rect2(-HALF_CELL, -HALF_CELL, HALF_CELL * 2, HALF_CELL * 2), false)

func turn_radius() -> float:
  return HALF_CELL * global_transform.x.length()

func contains_point(point: Vector2) -> bool:
  var local := to_local(point)
  return absf(local.x) <= HALF_CELL + EPSILON and absf(local.y) <= HALF_CELL + EPSILON

## Return when the centre of a moving particle first enters this cell.
func entry_fraction(from: Vector2, motion: Vector2) -> float:
  var start := to_local(from)
  var move := global_transform.basis_xform_inv(motion)
  if contains_point(from):
    # Do not start a second turn when leaving or sliding along a boundary.
    if (absf(start.x) >= HALF_CELL - EPSILON and start.x * move.x >= 0.0) or (absf(start.y) >= HALF_CELL - EPSILON and start.y * move.y >= 0.0):
      return INF
    return 0.0
  var near := 0.0
  var far := 1.0
  for axis in range(2):
    var position := start[axis]
    var velocity := move[axis]
    if absf(velocity) < EPSILON:
      if absf(position) > HALF_CELL: return INF
      continue
    var first := (-HALF_CELL - position) / velocity
    var second := (HALF_CELL - position) / velocity
    near = maxf(near, minf(first, second))
    far = minf(far, maxf(first, second))
    if near > far: return INF
  return near if near >= 0.0 and near <= 1.0 else INF
