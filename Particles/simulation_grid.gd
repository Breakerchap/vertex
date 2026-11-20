class_name SimulationGrid
extends RefCounted

const CELL := 102.4
const TICKS_PER_STEP := 15
const GRID_TICKS_PER_STEP := 4
const TICK := 1.0 / TICKS_PER_STEP
const DIRECTIONS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const VECTORS := [Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1),
  Vector2.LEFT, Vector2(-1, -1), Vector2.UP, Vector2(1, -1)]

static func center(point: Vector2) -> Vector2:
  return point.snapped(Vector2.ONE * CELL)

static func heading(travel: Vector2) -> Vector2:
  if travel.is_zero_approx():
    return Vector2.ZERO
  return VECTORS[posmod(roundi(travel.angle() / (PI / 4.0)), VECTORS.size())]
