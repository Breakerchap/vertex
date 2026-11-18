extends PanelContainer

signal kind_selected(kind: String)
signal mode_changed(enabled: bool)
signal kind_dropped(kind: String, screen_position: Vector2)

const CATALOG = preload("res://Buildings/building_catalog.gd")
const ICONS := {
  "emitter": preload("res://Buildings/Emitter/emitter.png"),
  "mirror": preload("res://Buildings/Mirror/mirror.png"),
  "wall": preload("res://Buildings/Wall/wall.png"),
  "detector": preload("res://Buildings/Detector/detector.png"),
  "magnet": preload("res://Buildings/MagneticField/plus_magnet.png"),
}
var click_mode := false
var counts: Dictionary = {}
var infinite := false
var locked := false
var selected := ""
var list: VBoxContainer
var drag_kind := ""
var drag_start := Vector2.ZERO
var ghost: TextureRect

func _ready() -> void:
  set_anchors_preset(Control.PRESET_RIGHT_WIDE)
  offset_left = -256
  offset_right = -16
  offset_top = 115
  offset_bottom = -16
  var margin := MarginContainer.new()
  for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
    margin.add_theme_constant_override(side, 10)
  add_child(margin)
  var column := VBoxContainer.new()
  column.add_theme_constant_override("separation", 8)
  margin.add_child(column)
  var title := Label.new()
  title.text = "INVENTORY"
  column.add_child(title)
  var mode := CheckButton.new()
  mode.text = "Click to place"
  mode.tooltip_text = "Choose a building, then click empty cells to place it"
  mode.toggled.connect(func(enabled: bool) -> void:
    click_mode = enabled
    if not enabled: selected = ""
    mode_changed.emit(enabled)
    refresh()
  )
  column.add_child(mode)
  var hint := Label.new()
  hint.text = "Drag onto the board"
  hint.add_theme_font_size_override("font_size", 12)
  column.add_child(hint)
  var scroll := ScrollContainer.new()
  scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  column.add_child(scroll)
  list = VBoxContainer.new()
  list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  scroll.add_child(list)
  ghost = TextureRect.new()
  ghost.custom_minimum_size = Vector2(72, 72)
  ghost.size = Vector2(72, 72)
  ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
  ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
  ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
  ghost.modulate.a = 0.75
  ghost.hide()
  get_parent().add_child.call_deferred(ghost)
  refresh()

func refresh() -> void:
  if not is_instance_valid(list): return
  for child in list.get_children():
    list.remove_child(child)
    child.queue_free()
  var kinds: Array = CATALOG.SCENES.keys() if infinite else counts.keys()
  kinds.sort()
  for kind in kinds:
    var amount := int(counts.get(kind, 0))
    if not infinite and amount <= 0: continue
    var button := Button.new()
    button.custom_minimum_size.y = 82
    button.icon = ICONS[kind]
    button.expand_icon = true
    button.text = " %s%s" % [str(kind).capitalize(), "  x%d" % amount if not infinite and amount > 1 else ""]
    button.tooltip_text = "%s ($%d)" % [str(kind).capitalize(), CATALOG.COSTS[kind]]
    button.toggle_mode = true
    button.button_pressed = click_mode and selected == kind
    button.disabled = locked
    button.pressed.connect(func() -> void:
      if click_mode: kind_selected.emit(kind)
      else: refresh()
    )
    button.gui_input.connect(_button_input.bind(kind))
    list.add_child(button)

func _button_input(event: InputEvent, kind: String) -> void:
  if not locked and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
    drag_kind = kind
    drag_start = get_global_mouse_position()

func _process(_delta: float) -> void:
  if drag_kind.is_empty() or not is_instance_valid(ghost): return
  var pos := get_global_mouse_position()
  if pos.distance_to(drag_start) > 8.0:
    ghost.texture = ICONS[drag_kind]
    ghost.position = pos - ghost.size * 0.5
    ghost.show()

func _input(event: InputEvent) -> void:
  if drag_kind.is_empty(): return
  if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
    var kind := drag_kind
    drag_kind = ""
    if is_instance_valid(ghost): ghost.hide()
    if event.position.distance_to(drag_start) > 8.0 and not locked:
      kind_dropped.emit(kind, event.position)
      get_viewport().set_input_as_handled()
