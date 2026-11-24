extends Control

const UI = preload("res://MainScene/workspace_theme.gd")
const TRACK_HEIGHT := 8.0

var target := 1.0
var rate := 0.0
var measuring := false
var sample_steps := 0.0

func _ready() -> void:
  custom_minimum_size = Vector2(36.0, TRACK_HEIGHT)
  size_flags_vertical = Control.SIZE_SHRINK_CENTER

func set_rate(value: float, pending: bool, steps: float) -> void:
  sample_steps = steps
  rate = value
  measuring = pending
  queue_redraw()

static func format_rate(value: float) -> String:
  if value > 0.0 and value < 0.0001: return String.num_scientific(value)
  if value == 0.0: return "0"
  return String.num(value, clampi(2 - floori(log(value) / log(10.0)), 0, 6)).trim_suffix(".0")

func _draw() -> void:
  var track := Rect2(Vector2.ZERO, size)
  draw_rect(track, UI.BACKGROUND)
  var fill := track
  fill.size.x *= clampf(rate / target, 0.0, 1.0)
  draw_rect(fill, UI.ACCENT)

func _get_tooltip(_at_position: Vector2) -> String:
  if sample_steps > 0.0: return "%s/s output" % format_rate(rate)
  if measuring: return "Measuring output…"
  return "%s/s required" % format_rate(target)
