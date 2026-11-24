extends Control

const UI = preload("res://MainScene/workspace_theme.gd")
const MEDALS = preload("res://MainScene/medal_display.gd")
const MARKER_SIZE := 17.0
const TRACK_HEIGHT := 8.0

var target := 1.0
var medal := "rate"
var rate := 0.0
var active := false
var sample_steps := 0.0

func _ready() -> void:
  custom_minimum_size.y = MARKER_SIZE + TRACK_HEIGHT + 6.0
  texture_filter = TEXTURE_FILTER_NEAREST

func set_rate(value: float, measuring: bool, steps: float) -> void:
  sample_steps = steps
  rate = value
  active = measuring
  queue_redraw()

static func format_rate(value: float) -> String:
  if value > 0.0 and value < 0.0001: return String.num_scientific(value)
  if value == 0.0: return "0"
  return String.num(value, clampi(2 - floori(log(value) / log(10.0)), 0, 6))

func _draw() -> void:
  var track_y := size.y - TRACK_HEIGHT - 1.0
  var track := Rect2(0.0, track_y, size.x - MARKER_SIZE * 0.5, TRACK_HEIGHT)
  draw_rect(track, UI.BACKGROUND)
  var fill := track
  fill.size.x *= clampf(rate / target, 0.0, 1.0)
  draw_rect(fill, UI.ACCENT)
  var reached := active and sample_steps * target >= 1.0 - 0.000001 and (rate >= target or is_equal_approx(rate / target, 1.0))
  var shade := UI.GOLD if reached else UI.MUTED
  draw_line(Vector2(track.end.x, track_y - 3.0), track.end, shade, 2.0)
  var marker := Rect2(track.end.x - MARKER_SIZE * 0.5, track_y - MARKER_SIZE - 3.0, MARKER_SIZE, MARKER_SIZE)
  draw_texture_rect(MEDALS.ICONS[medal], marker, false, Color(1.0, 1.0, 1.0, 1.0 if reached else 0.32))

func _get_tooltip(_at_position: Vector2) -> String:
  var goal := "%s/step for the %s medal" % [format_rate(target), medal.capitalize()]
  if not active: return goal
  return "%s\n%s/step over %s steps" % [goal, format_rate(rate), String.num(sample_steps, 1)]
