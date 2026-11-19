extends RefCounted

const BACKGROUND := Color("101722")
const SURFACE := Color("192536")
const LINE := Color("34465d")
const TEXT := Color("e8eff8")
const MUTED := Color("a5b8cf")
const ACCENT := Color("79e1c0")
const ERROR := Color("ffa5a9")
const GOLD := Color("f5ce7e")

static var shared: Theme

static func theme() -> Theme:
  if shared != null: return shared
  shared = Theme.new()
  shared.default_font_size = 15
  shared.set_color("font_color", "Label", TEXT)
  for type in ["Button", "OptionButton"]:
    shared.set_stylebox("normal", type, _box(Color("233248"), LINE, 8, 5))
    shared.set_stylebox("hover", type, _box(Color("30445d"), Color("657f9d"), 8, 5))
    shared.set_stylebox("pressed", type, _box(Color("22483f"), ACCENT, 8, 5))
    shared.set_stylebox("disabled", type, _box(Color("1e2939"), Color("29384a"), 8, 5))
    shared.set_stylebox("focus", type, _box(Color.TRANSPARENT, ACCENT))
    shared.set_color("font_color", type, TEXT)
    shared.set_color("font_hover_color", type, Color.WHITE)
    shared.set_color("font_pressed_color", type, ACCENT)
    shared.set_color("font_disabled_color", type, Color("8797aa"))
  shared.set_stylebox("panel", "PanelContainer", _box(SURFACE, LINE))
  shared.set_stylebox("panel", "PopupMenu", _box(SURFACE, LINE, 5, 5))
  shared.set_stylebox("hover", "PopupMenu", _box(Color("30445d"), Color.TRANSPARENT, 5, 1))
  shared.set_constant("v_separation", "PopupMenu", 7)
  shared.set_stylebox("normal", "LineEdit", _box(BACKGROUND, LINE, 8, 5))
  shared.set_stylebox("focus", "LineEdit", _box(Color.TRANSPARENT, ACCENT))
  shared.set_color("font_color", "LineEdit", TEXT)
  shared.set_color("font_placeholder_color", "LineEdit", MUTED)
  shared.set_stylebox("background", "ProgressBar", _box(BACKGROUND, Color.TRANSPARENT))
  shared.set_stylebox("fill", "ProgressBar", _box(ACCENT, Color.TRANSPARENT))
  shared.set_constant("separation", "VBoxContainer", 7)
  shared.set_constant("separation", "HBoxContainer", 7)
  shared.set_constant("h_separation", "HFlowContainer", 6)
  shared.set_constant("v_separation", "HFlowContainer", 5)
  shared.set_type_variation("PrimaryButton", "Button")
  shared.set_stylebox("normal", "PrimaryButton", _box(Color("22483f"), Color("579e88"), 8, 5))
  shared.set_stylebox("hover", "PrimaryButton", _box(Color("2f5d51"), ACCENT, 8, 5))
  shared.set_color("font_color", "PrimaryButton", ACCENT)
  return shared

static func heading(label: Label, size: int = 19) -> void:
  label.add_theme_font_size_override("font_size", size)
  label.add_theme_color_override("font_color", TEXT)

static func muted(label: Label, size: int = 13) -> void:
  label.add_theme_font_size_override("font_size", size)
  label.add_theme_color_override("font_color", MUTED)

static func margin(padding: int = 12) -> MarginContainer:
  var control := MarginContainer.new()
  for side in ["left", "right", "top", "bottom"]:
    control.add_theme_constant_override("margin_" + side, padding)
  return control

static func _box(background: Color, border: Color, padding_x: int = 0, padding_y: int = 0) -> StyleBoxFlat:
  var style := StyleBoxFlat.new()
  style.bg_color = background
  style.border_color = border
  style.set_border_width_all(1)
  style.set_corner_radius_all(8)
  style.content_margin_left = padding_x
  style.content_margin_right = padding_x
  style.content_margin_top = padding_y
  style.content_margin_bottom = padding_y
  return style
