extends Control

const UI = preload("res://MainScene/workspace_theme.gd")
const FILLED_STAR = preload("res://filled_star.png")
const EMPTY_STAR = preload("res://empty_star.png")
const STAR_SIZE := 15.0
const MARKER_HEIGHT := 18.0
const TRACK_HEIGHT := 8.0

var markers: Array[Dictionary] = []
var max_rate := 0.0
var track_inset := 0.0
var rate := 0.0
var active := false
var sample_steps := 0.0

func _ready() -> void:
  resized.connect(_layout_markers)
  _layout_markers()

func set_thresholds(thresholds: Array) -> void:
  var tiers_by_rate := {}
  for tier in range(thresholds.size()):
    var threshold: float = thresholds[tier]
    if not tiers_by_rate.has(threshold):
      tiers_by_rate[threshold] = PackedStringArray()
    tiers_by_rate[threshold].append(str(tier + 1))
    if is_finite(threshold):
      max_rate = maxf(max_rate, threshold)
  var rates := tiers_by_rate.keys()
  rates.sort()
  for threshold in rates:
    markers.append({"rate": threshold, "tiers": tiers_by_rate[threshold]})

func set_rate(value: float, measuring: bool, steps: float) -> void:
  sample_steps = steps
  if rate == value and active == measuring: return
  rate = value
  active = measuring
  queue_redraw()

static func format_rate(value: float) -> String:
  if value > 0.0 and value < 0.0001: return String.num_scientific(value)
  if value == 0.0: return "0"
  return String.num(value, clampi(2 - floori(log(value) / log(10.0)), 0, 6))

func _layout_markers() -> void:
  track_inset = 0.0
  for marker in markers:
    marker.width = STAR_SIZE * marker.tiers.size()
    track_inset = maxf(track_inset, marker.width * 0.5)
  var track_width := maxf(1.0, size.x - track_inset * 2.0)
  var lane_ends: Array[float] = []
  for marker in markers:
    marker.x = track_inset + track_width * _fraction(marker.rate)
    var left: float = marker.x - marker.width * 0.5
    var lane := 0
    while lane < lane_ends.size() and lane_ends[lane] + 6.0 > left:
      lane += 1
    var right: float = left + marker.width
    if lane == lane_ends.size():
      lane_ends.append(right)
    else:
      lane_ends[lane] = right
    marker.lane = lane
  custom_minimum_size.y = lane_ends.size() * MARKER_HEIGHT + TRACK_HEIGHT + 5.0
  queue_redraw()

func _fraction(value: float) -> float:
  var has_unreachable: bool = not markers.is_empty() and is_inf(markers.back().rate)
  if is_inf(value): return 1.0
  return clampf(value / (max_rate if max_rate > 0.0 else 1.0), 0.0, 1.0) * (0.85 if has_unreachable else 1.0)

func _draw() -> void:
  var track_y := size.y - TRACK_HEIGHT - 1.0
  var track := Rect2(track_inset, track_y, maxf(1.0, size.x - track_inset * 2.0), TRACK_HEIGHT)
  draw_rect(track, UI.BACKGROUND)
  if rate > 0.0:
    track.size.x *= _fraction(rate)
    draw_rect(track, UI.ACCENT)
  for marker in markers:
    var target: float = marker.rate
    var enough_time := sample_steps * target >= 1.0 - 0.000001 or target == 0.0
    var reached: bool = active and enough_time and (rate >= target or (rate > 0.0 and is_equal_approx(rate / target, 1.0)))
    var shade := UI.GOLD if reached else UI.MUTED
    var y: float = track_y - 4.0 - (marker.lane + 1) * MARKER_HEIGHT
    var x: float = marker.x - STAR_SIZE * marker.tiers.size() * 0.5
    draw_line(Vector2(marker.x, track_y - 3.0), Vector2(marker.x, track_y + TRACK_HEIGHT), shade, 2.0)
    for _tier in marker.tiers:
      draw_texture_rect(FILLED_STAR if reached else EMPTY_STAR, Rect2(x, y, STAR_SIZE, STAR_SIZE), false)
      x += STAR_SIZE

func _get_tooltip(at_position: Vector2) -> String:
  var track_y := size.y - TRACK_HEIGHT - 1.0
  for marker in markers:
    var y: float = track_y - 4.0 - (marker.lane + 1) * MARKER_HEIGHT
    if Rect2(marker.x - marker.width * 0.5, y, marker.width, MARKER_HEIGHT).has_point(at_position):
      var target := "∞" if is_inf(marker.rate) else "%s/step" % str(marker.rate).trim_suffix(".0")
      return "%s for star tier %s" % [target, ", ".join(marker.tiers)]
  return "%s/step over %s steps" % [format_rate(rate), String.num(sample_steps, 1)] if active else "No active run"
