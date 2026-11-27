extends Control

const UI = preload("res://MainScene/workspace_theme.gd")
const TRACK_HEIGHT := 8.0

var target_period := 4.0
var period := INF
var measuring := false
var sample_grid_ticks := 0.0

func _ready() -> void:
  custom_minimum_size = Vector2(36.0, TRACK_HEIGHT)
  size_flags_vertical = Control.SIZE_SHRINK_CENTER

func set_period(value: float, pending: bool, ticks: float) -> void:
  sample_grid_ticks = ticks
  period = value
  measuring = pending
  queue_redraw()

static func format_period(value: float) -> String:
  if not is_finite(value): return "No output"
  if value == 0.0: return "0"
  if value < 0.0001: return String.num_scientific(value)
  return String.num(value, clampi(2 - floori(log(value) / log(10.0)), 0, 6))

func _draw() -> void:
  var track := Rect2(Vector2.ZERO, size)
  draw_rect(track, UI.BACKGROUND)
  var fill := track
  # Smaller periods are better; no output has an infinite period.
  fill.size.x *= clampf(target_period / period, 0.0, 1.0) if is_finite(period) and period > 0.0 else 0.0
  draw_rect(fill, UI.ACCENT)

func _get_tooltip(_at_position: Vector2) -> String:
  var requirement := "Target: %s ticks per particle or less" % format_period(target_period)
  if sample_grid_ticks > 0.0:
    var actual := "Average: %s ticks per particle" % format_period(period) if is_finite(period) else "No sustained output"
    return actual + "\n" + requirement
  if measuring: return "Measuring output…\n" + requirement
  return requirement
