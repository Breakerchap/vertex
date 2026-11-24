extends PanelContainer

signal kind_selected(kind: String)
signal kind_dropped(kind: String, screen_position: Vector2)

const CATALOG = preload("res://Buildings/building_catalog.gd")
const UI = preload("res://MainScene/workspace_theme.gd")
const ICONS := {
  "emitter": preload("res://Buildings/Emitter/emitter.png"),
  "reflector": preload("res://Buildings/Reflector/reflector.png"),
  "wall": preload("res://Buildings/Wall/wall.png"),
  "detector": preload("res://Buildings/Detector/detector.png"),
  "magnet": preload("res://Buildings/MagneticField/plus_magnet.png"),
  "stray_particle": preload("res://Particles/Electron/electron.png"),
}
var counts: Dictionary = {}
var infinite := false
var locked := false
var selected := ""
var height_limit := INF:
  set(value):
    height_limit = value
    _fit_list()
var scroll: ScrollContainer
var contents: VBoxContainer
var list: GridContainer
var buttons := {}
var empty: Label
var drag_kind := ""
var drag_start := Vector2.ZERO
var ghost: TextureRect

func _ready() -> void:
  if infinite:
    set_anchors_preset(Control.PRESET_RIGHT_WIDE)
    offset_left = -256
    offset_right = -16
    offset_top = 72
    offset_bottom = -16
  theme = UI.theme()
  var margin := UI.margin()
  add_child(margin)
  var column := VBoxContainer.new()
  column.add_theme_constant_override("separation", 8)
  margin.add_child(column)
  var title := Label.new()
  title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  title.text = "Building tools" if infinite else "Inventory"
  title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  UI.heading(title)
  column.add_child(title)
  scroll = ScrollContainer.new()
  scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  column.add_child(scroll)
  contents = VBoxContainer.new()
  contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  scroll.add_child(contents)
  list = GridContainer.new()
  list.columns = 1 if infinite else 2
  contents.add_child(list)
  empty = Label.new()
  empty.text = "Empty"
  UI.muted(empty)
  contents.add_child(empty)
  if not infinite:
    contents.minimum_size_changed.connect(_fit_list)
  ghost = TextureRect.new()
  ghost.custom_minimum_size = Vector2(72, 72)
  ghost.size = Vector2(72, 72)
  ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
  ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
  ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
  ghost.top_level = true
  ghost.z_index = 2
  ghost.modulate.a = 0.75
  ghost.hide()
  add_child(ghost)
  refresh()

func _fit_list() -> void:
  if not is_instance_valid(contents) or infinite: return
  var frame_height := get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
  scroll.custom_minimum_size.y = minf(contents.get_combined_minimum_size().y, maxf(44.0, height_limit - frame_height))

func set_compact(compact: bool) -> void:
  if not infinite: return
  list.columns = 2 if compact else 1
  for button in buttons.values():
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.custom_minimum_size.y = 44 if compact else 56

func refresh() -> void:
  if not is_instance_valid(list): return
  var kinds: Array = CATALOG.SCENES.keys() if infinite else counts.keys()
  kinds.sort()
  for kind in buttons.keys():
    if kind not in kinds:
      var old: Button = buttons[kind]
      list.remove_child(old)
      old.queue_free()
      buttons.erase(kind)
  empty.visible = kinds.is_empty()
  for kind in kinds:
    var amount := int(counts.get(kind, 0))
    var button: Button = buttons.get(kind)
    if button == null:
      button = Button.new()
      button.custom_minimum_size.y = 56 if infinite else 76
      button.icon = _icon(kind)
      button.expand_icon = true
      button.alignment = HORIZONTAL_ALIGNMENT_LEFT if infinite else HORIZONTAL_ALIGNMENT_CENTER
      if not infinite:
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
        button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
      button.add_theme_constant_override("icon_max_width", 36 if infinite else 46)
      button.toggle_mode = true
      button.pressed.connect(func() -> void: kind_selected.emit("" if selected == kind else kind))
      button.gui_input.connect(_button_input.bind(kind))
      list.add_child(button)
      buttons[kind] = button
    var kind_name := str(kind).capitalize()
    button.text = kind_name if infinite else "%s ×%d" % [kind_name, amount]
    button.tooltip_text = kind_name if infinite else "%s · $%d each" % [kind_name, CATALOG.COSTS[kind]]
    button.set_pressed_no_signal(selected == kind)
    button.disabled = locked or (not infinite and amount <= 0)

func _button_input(event: InputEvent, kind: String) -> void:
  if not locked and not buttons[kind].disabled and event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
    drag_kind = kind
    drag_start = get_global_mouse_position()

func _process(_delta: float) -> void:
  if drag_kind.is_empty() or not is_instance_valid(ghost): return
  var pos := get_global_mouse_position()
  if pos.distance_to(drag_start) > 8.0:
    ghost.texture = _icon(drag_kind)
    ghost.position = pos - ghost.size * 0.5
    ghost.show()

func _input(event: InputEvent) -> void:
  if drag_kind.is_empty(): return
  if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
    var kind := drag_kind
    drag_kind = ""
    if is_instance_valid(ghost): ghost.hide()
    if event.position.distance_to(drag_start) > 8.0:
      if not locked: kind_dropped.emit(kind, event.position)
      var button: Button = buttons.get(kind)
      if is_instance_valid(button): button.set_pressed_no_signal(selected == kind)
      get_viewport().set_input_as_handled()

func _icon(kind: String) -> Texture2D:
  if ICONS.has(kind): return ICONS[kind]
  return CATALOG.DEVICE.SPRITES[kind][0]
