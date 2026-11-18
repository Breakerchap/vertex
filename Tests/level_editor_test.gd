extends Node

const EDITOR = preload("res://MainScene/level_editor.tscn")
const PARSER = preload("res://Levels/level_parser.gd")
const CATALOG = preload("res://Buildings/building_catalog.gd")

func _ready() -> void:
  var editor = EDITOR.instantiate()
  get_tree().root.add_child.call_deferred(editor)
  await get_tree().process_frame
  for file in DirAccess.get_files_at("res://Levels"):
    if file.ends_with(".level"):
      assert(not PARSER.parse(FileAccess.get_file_as_string("res://Levels/" + file)).has("error"), file)
  var original := "5 x 5;\n# preserve this comment\ngoal: {[electron OR positron]: 1/s, 2/s, 3/s};\nwall: {x=0..1, y=0, fixed=p};\nmagnet: {x=2,y=2,-,fixed=rp};\ninventory: {mirror=2};\n"
  editor._set_source(original)
  assert(editor.blocks.size() == 2)
  assert(editor.blocks[0].entries.size() == 2)
  assert(editor.tool_select.item_count == CATALOG.SCENES.size() + 1)
  editor._board_click(Vector2i(0, 0), MOUSE_BUTTON_RIGHT)
  assert(editor.source.text == original, "Deleting one cell of a range must not delete the whole range")
  editor._board_click(Vector2i(2, 2), MOUSE_BUTTON_LEFT)
  assert(editor.properties.text.contains("magnet"))
  assert(editor.property_fields.size() == 4)
  editor._board_click(Vector2i(3, 2), MOUSE_BUTTON_LEFT)
  assert(editor.source.text.contains("x=3"))
  assert(editor.source.text.contains("# preserve this comment"))
  assert(editor.source.text.contains("[electron OR positron]"))
  var kinds: Array = CATALOG.SCENES.keys()
  kinds.sort()
  editor.tool_select.select(kinds.find("mirror") + 1)
  editor._board_click(Vector2i(4, 4), MOUSE_BUTTON_LEFT)
  assert(not PARSER.parse(editor.source.text).has("error"))
  assert(editor.source.text.contains("mirror: {x=4, y=4}"))
  var target := ProjectSettings.globalize_path("res://Tests/editor_roundtrip_tmp.level")
  editor._write_file(target)
  assert(FileAccess.file_exists(target))
  var saved := FileAccess.get_file_as_string(target)
  assert(saved == editor.source.text)
  editor.file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
  editor._set_source("5 x 5; goal: {photon: 1, 2, 3};")
  editor._file_selected(target)
  assert(editor.source.text == saved)
  DirAccess.remove_absolute(target)
  editor.free()
  print("Level editor checks passed")
  get_tree().quit()
