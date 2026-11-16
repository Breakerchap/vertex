@tool
extends Node2D

## A cell is the 128-pixel emitter sprite at its current 0.8 scale.
const GRID_SIZE: float = 102.4
var _snapping_to_grid := false

func _ready() -> void:
  set_notify_local_transform(true)
  set_notify_transform(true)
  _snap_to_grid()

func _notification(what: int) -> void:
  if (what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED or what == NOTIFICATION_TRANSFORM_CHANGED) and is_inside_tree():
    _snap_to_grid()

## Positions use the same world-space grid even under different parent nodes.
func _snap_to_grid() -> void:
  if _snapping_to_grid:
    return
  _snapping_to_grid = true
  var snapped := global_position.snapped(Vector2.ONE * GRID_SIZE)
  if not global_position.is_equal_approx(snapped):
    global_position = snapped
  _snapping_to_grid = false
