@tool
extends "res://Buildings/building.gd"

const HALF_CELL: float = 51.2
const EPSILON: float = 0.00001

@export_enum("Positive:1", "Negative:-1") var polarity: int = 1:
  set(value):
    polarity = 1 if value >= 0 else -1
    queue_redraw()

func _ready() -> void:
  super._ready()
  if not Engine.is_editor_hint():
    add_to_group("magnetic_fields")

func _draw() -> void:
  var colour := Color("ef8d88") if polarity > 0 else Color("81baf5")
  draw_rect(Rect2(-HALF_CELL, -HALF_CELL, HALF_CELL * 2, HALF_CELL * 2), Color("19263a"))
  draw_rect(Rect2(-46, -46, 92, 92), colour, false, 3.0)
  draw_arc(Vector2.ZERO, 29.0, -PI * 0.8, PI * 0.8, 48, colour, 3.0)
  draw_line(Vector2(-12, 0), Vector2(12, 0), colour, 5.0)
  if polarity > 0:
    draw_line(Vector2(0, -12), Vector2(0, 12), colour, 5.0)
  draw_line(Vector2(19, -25), Vector2(29, -19), colour, 3.0)
  draw_line(Vector2(29, -19), Vector2(30, -30), colour, 3.0)

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
