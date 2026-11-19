extends VBoxContainer

const CATALOG = preload("res://Particles/particle_catalog.gd")
const PARSER = preload("res://Levels/level_parser.gd")
const UI = preload("res://MainScene/workspace_theme.gd")

var sequence := false
var tokens: Array[String] = []
var original := ""
var edited := false
var picker: OptionButton
var preview: Label
var buttons := {}
var undo_button: Button
var clear_button: Button

func _ready() -> void:
  preview = Label.new()
  preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  add_child(preview)
  picker = OptionButton.new()
  picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  picker.fit_to_longest_item = false
  picker.tooltip_text = "Append a particle to the repeating sequence" if sequence else "Insert a particle into the expression"
  picker.get_popup().about_to_popup.connect(_fill_particles)
  picker.item_selected.connect(func(index: int) -> void:
    if index > 0: _append(picker.get_item_metadata(index))
  )
  add_child(picker)
  var toolbar := HFlowContainer.new()
  add_child(toolbar)
  if not sequence:
    for token in ["AND", "OR", "(", ")"]:
      buttons[token] = _button(toolbar, token, _append.bind(token))
    buttons["("].tooltip_text = "Open bracket"
    buttons[")"].tooltip_text = "Close bracket"
  undo_button = _button(toolbar, "Remove last", _remove_last)
  clear_button = _button(toolbar, "Clear", func() -> void:
    tokens.clear()
    _changed()
  )
  _fill_particles()
  _refresh()

func load_text(value: String) -> void:
  original = value
  edited = false
  tokens.clear()
  if sequence:
    for name in value.split(",", false):
      if not name.strip_edges().is_empty(): tokens.append(name.strip_edges().to_lower())
  else:
    var regex := RegEx.new()
    regex.compile(PARSER.PARTICLE_TOKEN)
    for item in regex.search_all(value):
      var token := item.get_string().to_lower()
      tokens.append("OR" if token == "," else token.to_upper() if token in ["and", "or"] else token)
  if is_node_ready(): _refresh()

func source_text() -> String:
  if not edited: return original
  if sequence: return ", ".join(tokens)
  return " ".join(tokens).replace("( ", "(").replace(" )", ")")

func _fill_particles() -> void:
  if picker.item_count == CATALOG.TYPES.size() + 1: return
  picker.clear()
  picker.add_item("Choose a particle…")
  picker.set_item_disabled(0, true)
  for name in CATALOG.TYPES:
    picker.add_item(CATALOG.label(name))
    picker.set_item_metadata(picker.item_count - 1, name)
  picker.select(0)

func _append(token: String) -> void:
  tokens.append(token)
  _changed()

func _remove_last() -> void:
  tokens.pop_back()
  _changed()

func _changed() -> void:
  edited = true
  picker.select(0)
  _refresh()

func _refresh() -> void:
  var names := PackedStringArray()
  for token in tokens:
    names.append(CATALOG.label(token) if CATALOG.TYPES.has(token) else token)
  var text := "  →  ".join(names) if sequence else " ".join(names).replace("( ", "(").replace(" )", ")")
  preview.text = text if not text.is_empty() else ("Default: Electron" if sequence else "No particles selected")
  preview.add_theme_color_override("font_color", UI.MUTED if tokens.is_empty() else UI.ACCENT)
  clear_button.disabled = tokens.is_empty()
  undo_button.disabled = tokens.is_empty()
  if sequence: return
  var needs_particle: bool = tokens.is_empty() or tokens.back() in ["AND", "OR", "("]
  picker.disabled = not needs_particle
  buttons["AND"].disabled = needs_particle
  buttons["OR"].disabled = needs_particle
  buttons["("].disabled = not needs_particle
  buttons[")"].disabled = needs_particle or tokens.count("(") <= tokens.count(")")

func _button(parent: Control, title: String, action: Callable) -> Button:
  var button := Button.new()
  button.text = title
  button.pressed.connect(action)
  parent.add_child(button)
  return button
