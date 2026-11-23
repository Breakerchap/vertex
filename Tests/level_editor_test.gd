extends Node

const EDITOR = preload("res://MainScene/level_editor.tscn")
const PARSER = preload("res://Levels/level_parser.gd")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")

func _ready() -> void:
  get_window().size = Vector2i(1280, 720)
  var editor = EDITOR.instantiate()
  get_tree().root.add_child.call_deferred(editor)
  await get_tree().process_frame
  assert(editor.editor_panel.get_parent() is CanvasLayer, "Editor controls must stay in screen space")
  await get_tree().process_frame
  var viewport_size := get_viewport().get_visible_rect().size
  var panel_rect: Rect2 = editor.editor_panel.get_global_rect()
  assert(panel_rect.position.x >= 0 and panel_rect.position.y >= 0)
  assert(panel_rect.end.x <= viewport_size.x and panel_rect.end.y <= viewport_size.y)
  await _check_adaptive_layout(editor)
  for file in DirAccess.get_files_at("res://Levels"):
    if file.ends_with(".level"):
      assert(not PARSER.parse(FileAccess.get_file_as_string("res://Levels/" + file)).has("error"), file)
  var original := "# preserve this 99 x 99 comment\ntitle: A 15 x 15 dream;\n5 x 5;\ngoal: {[(electron OR up) AND up_r]: 1/s, 2/s, 3/s};\nwall: {x=+0..+1, y=0, fixed=p};\nmagnet: {x=2,y=2,-,fixed=rp};\ninventory: {mirror=2};\n"
  editor._set_source(original)
  editor._set_source("Not a valid level")
  assert(editor.parsed.has("error"))
  assert(editor.game.level.width == 5, "Last valid board must remain visible during an invalid source edit")
  var history_key := InputEventKey.new()
  history_key.pressed = true
  history_key.command_or_control_autoremap = true
  history_key.keycode = KEY_Z
  editor._unhandled_key_input(history_key)
  assert(not editor.parsed.has("error"))
  history_key.shift_pressed = true
  editor._unhandled_key_input(history_key)
  assert(editor.parsed.has("error"), "Shift with the platform shortcut modifier should redo.")
  history_key.shift_pressed = false
  editor._unhandled_key_input(history_key)
  assert(editor.game.editor_preview)
  assert(editor.game.level.width == 5)
  assert(editor.game.buildings.size() == 3)
  assert(editor.blocks.size() == 2)
  assert(editor.blocks[0].entries.size() == 2)
  assert(editor.palette.buttons.size() == CATALOG.SCENES.size())
  editor._board_click(Vector2i(0, 0), MOUSE_BUTTON_RIGHT)
  assert(editor.game._building_at(Vector2i(0, 0)) != null, "Right-click should select, not silently delete")
  editor._delete_selected()
  assert(editor.game._building_at(Vector2i(0, 0)) == null)
  assert(editor.game._building_at(Vector2i(1, 0)) != null, "Deleting one cell must preserve the rest of a range")
  editor._set_source(original)
  editor._board_click(Vector2i(2, 2), MOUSE_BUTTON_LEFT)
  editor._open_properties()
  assert(editor.inspector_heading.text.begins_with("Magnet"))
  assert(editor.property_fields.size() == 4)
  editor.inspector_dialog.hide()
  editor._move_block(Vector2i(2, 2), Vector2i(3, 2))
  assert(editor.source.text.contains("x=3"))
  assert(editor.game._building_at(Vector2i(3, 2)) != null)
  assert(editor.game._building_at(Vector2i(2, 2)) == null)
  editor._undo_editor()
  assert(editor.game._building_at(Vector2i(2, 2)) != null, "Editor undo must restore a moved building")
  editor._redo_editor()
  assert(editor.game._building_at(Vector2i(3, 2)) != null, "Editor redo must reapply a move")
  assert(editor.source.text.contains("# preserve this 99 x 99 comment"))
  assert(editor.source.text.contains("[(electron OR up) AND up_r]"))
  editor.palette.buttons.reflector.pressed.emit()
  editor._board_click(Vector2i(4, 4), MOUSE_BUTTON_LEFT)
  assert(not PARSER.parse(editor.source.text).has("error"))
  assert(editor.source.text.contains("reflector: {x=4, y=4}"))
  var key := InputEventKey.new()
  key.pressed = true
  key.keycode = KEY_Q
  editor._unhandled_key_input(key)
  assert(editor.game._building_at(Vector2i(4, 4)).get_meta("entry").facing == "NE")
  key.keycode = KEY_E
  editor._unhandled_key_input(key)
  assert(editor.game._building_at(Vector2i(4, 4)).get_meta("entry").facing == "E")
  key.keycode = KEY_BACKSPACE
  key.alt_pressed = true
  editor._unhandled_key_input(key)
  assert(editor.game._building_at(Vector2i(4, 4)) != null, "A modified Backspace must not remove a building.")
  key.alt_pressed = false
  editor._unhandled_key_input(key)
  assert(editor.game._building_at(Vector2i(4, 4)) == null, "Backspace must work as Delete.")
  editor._undo_editor()
  editor._select_at(Vector2i(1, 0))
  editor.visual_fields.y_end.value = 1
  editor._apply_visual_properties()
  assert(editor.game._building_at(Vector2i(1, 1)) != null)
  assert(editor.game._building_at(Vector2i(0, 0)) != null)
  editor._select_at(Vector2i(3, 2))
  editor._rotate_block(-1)
  assert("r" in editor.game._building_at(Vector2i(3, 2)).get_meta("entry").fixed)
  editor._open_settings()
  editor.title_input.text = "Test puzzle"
  editor.hint_input.text = "Redirect the beam"
  var first_solution: VBoxContainer = editor.goal_rows.get_child(0).get_meta("rows")
  editor._add_goal_row(first_solution, "cost", [INF, 20.0, 10.0])
  editor._add_goal_group()
  var output_row: VBoxContainer = editor.goal_rows.get_child(1).get_meta("rows").get_child(0)
  var particles: Control = output_row.get_meta("condition").expression
  assert(particles.picker.item_count == PARTICLES.TYPES.size() + PARTICLES.QUARK_FAMILIES.size() + 1)
  particles.clear_button.pressed.emit()
  particles.buttons["("].pressed.emit()
  _choose_particle(particles.picker, "electron")
  particles.buttons["OR"].pressed.emit()
  _choose_particle(particles.picker, "up")
  particles.buttons[")"].pressed.emit()
  particles.buttons["AND"].pressed.emit()
  _choose_particle(particles.picker, "up_r")
  editor._apply_settings()
  assert(editor.parsed.goals.size() == 2, "Goal alternatives must be separate groups")
  assert(editor.parsed.title == "Test puzzle" and editor.parsed.hint == "Redirect the beam")
  assert(editor.parsed.goals[0].cost == [INF, 20.0, 10.0])
  assert(editor.parsed.goals[1].has("[up_r]"))
  assert(editor.parsed.goal_targets[1]["[up_r]"] == "[(electron OR up) AND up_r]")
  assert(editor.source.text.contains("[(electron OR up) AND up_r]"))
  assert(editor.game.level.goals.size() == 2)
  editor._start_playtest()
  assert(is_instance_valid(editor.test_game), "Playtest must create an isolated game")
  assert(editor.test_game.editor_playtest and editor.test_game.level.goals.size() == 2)
  editor._end_playtest()
  assert(editor.test_game == null)
  var target := ProjectSettings.globalize_path("user://éditeur roundtrip %d.level" % OS.get_process_id())
  editor._write_file(target)
  assert(FileAccess.file_exists(target))
  var saved := FileAccess.get_file_as_string(target)
  assert(saved == editor.source.text)
  assert(editor.last_file_directory == target.get_base_dir())
  editor.file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
  editor._set_source("5 x 5; goal: {photon: 1, 2, 3};")
  editor._file_selected(target.trim_suffix(".level"))
  assert(FileAccess.get_file_as_string(target) == saved, "Appending an extension must not bypass overwrite confirmation.")
  editor.file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
  editor._file_selected(target)
  assert(editor.source.text == saved)
  assert(editor._is_bundled_level(ProjectSettings.globalize_path("res://Levels/01 - First Contact.level")))
  editor._open_source()
  editor._set_source("5 x 5; goal: {photon: 1, 2, 3};")
  history_key.keycode = KEY_S
  editor.source_dialog.push_input(history_key)
  assert(FileAccess.get_file_as_string(target) == editor.source.text, "The platform save shortcut must work from the source editor.")
  assert(editor.source_dialog.visible)
  if DisplayServer.get_name() == "headless":
    history_key.shift_pressed = true
    editor.source_dialog.push_input(history_key)
    assert(editor.file_dialog.visible and not editor.source_dialog.visible)
    assert(editor.file_dialog.current_dir == target.get_base_dir())
    editor.file_dialog.hide()
    editor.file_dialog.canceled.emit()
    await get_tree().process_frame
    assert(editor.source_dialog.visible, "Canceling Save As must return to the source editor.")
  editor.source_dialog.hide()
  DirAccess.remove_absolute(target)
  editor._set_source("5 x 5; goal: {photon: 1/step, 2/step, 3/step};")
  editor._place_editor_kind("holder", Vector2i(1, 1))
  editor._place_editor_kind("edge_wall", Vector2i(1, 1), "N")
  assert(editor.game._building_at(Vector2i(1, 2), "edge_wall", "S") == editor.selected_building)
  editor._copy_selected()
  assert(not editor._paste_building(Vector2i(1, 1)), "Paste should reject occupied edges.")
  assert(editor._paste_building(Vector2i(2, 1)))
  assert(editor.game._building_at(Vector2i(2, 1), "edge_wall", "N") != null)
  editor._undo_editor()
  assert(editor.game._building_at(Vector2i(2, 1), "edge_wall", "N") == null)
  assert(editor.game._building_at(Vector2i(1, 1), "holder") != null)
  assert(not editor.palette.buttons.has("rail"))
  editor._open_settings()
  editor.rotation_input.select(editor.rotation_input.get_item_index(4))
  editor._apply_settings()
  assert(editor.parsed.rotation_steps == 4, "Player rotation mode must persist in level source.")
  editor._place_editor_kind("emitter", Vector2i(3, 2))
  assert(editor.visual_fields.particles.tokens.is_empty(), "A new emitter should have no particles in its configured sequence.")
  assert(editor.selected_building.get_child(-1).particle_names.is_empty(), "A new emitter should have an empty preview.")
  editor._place_editor_kind("reflector", Vector2i(4, 2))
  editor.visual_fields.rotation.select(editor.visual_fields.rotation.get_item_index(8))
  editor.visual_fields.rotation.item_selected.emit(editor.visual_fields.rotation.selected)
  await get_tree().process_frame
  assert(editor.game._building_at(Vector2i(4, 2)).get_meta("entry").rotation == 8, "Changing a property should immediately apply it.")
  editor._start_playtest()
  var player_emitter: Node = editor.test_game._building_at(Vector2i(3, 2))
  editor.test_game.selected_building = player_emitter
  editor.test_game._rotate_selected()
  assert(player_emitter.orientation == 2, "Players should rotate 90 degrees in four-direction levels.")
  var mirror: Node = editor.test_game._building_at(Vector2i(4, 2))
  editor.test_game.selected_building = mirror
  editor.test_game._rotate_selected()
  assert(mirror.orientation == 3, "A building can override the level rotation mode.")
  editor.test_game._place_building({"kind": "wall", "x": 0, "y": 4}, true)
  var placed: Node = editor.test_game._building_at(Vector2i(0, 4))
  editor.test_game.begin_run()
  editor.test_game.step_simulation(SimulationGrid.TICK)
  var emitted: Array[Particle] = editor.test_game._particles()
  assert(emitted.size() == 1 and emitted[0].level_particle_name() == "electron", "An empty emitter should emit electrons by default.")
  var playtest_escape := InputEventKey.new()
  playtest_escape.pressed = true
  playtest_escape.keycode = KEY_ESCAPE
  editor._unhandled_key_input(playtest_escape)
  editor.test_game._unhandled_input(playtest_escape)
  assert(not editor.test_game.simulating and editor.test_game._building_at(Vector2i(0, 4)) == placed)
  assert(mirror.orientation == 3, "Escape should retain the playtest build and rotation.")
  editor._end_playtest()
  editor._select_at(Vector2i(3, 2))
  editor._move_block(Vector2i(3, 2), Vector2i(-1, 2))
  assert(editor.game._building_at(Vector2i(3, 2)) == null, "Dragging off the grid should delete the building.")
  editor._undo_editor()
  assert(editor.game._building_at(Vector2i(3, 2)) != null, "Undo should restore a building dragged off the grid.")
  var escape := InputEventKey.new()
  escape.keycode = KEY_ESCAPE
  escape.pressed = true
  editor._select_at(Vector2i(3, 2))
  var before_escape: Node = editor.game.selected_building
  editor._unhandled_key_input(escape)
  assert(editor.selected_block == -1 and editor.game.selected_building == null)
  assert(editor.game._building_at(Vector2i(3, 2)) == before_escape, "Escape should deselect without rebuilding the editor board.")
  editor.game.begin_run()
  editor._unhandled_key_input(escape)
  assert(not editor.game.simulating, "Escape should reset the running preview.")
  await _check_build_areas(editor, target)
  editor.free()
  print("Level editor checks passed")
  get_tree().quit()

func _check_adaptive_layout(editor: Control) -> void:
  var original_size := get_window().size
  assert(editor.file_dialog.use_native_dialog and editor.file_dialog.access == FileDialog.ACCESS_FILESYSTEM)
  for resolution in [Vector2i(800, 500), Vector2i(1920, 650), Vector2i(800, 1000), Vector2i(2304, 1440)]:
    get_window().size = resolution
    await get_tree().process_frame
    await get_tree().process_frame
    var workspace := get_viewport().get_visible_rect()
    assert(absf(workspace.size.aspect() - Vector2(resolution).aspect()) < 0.01, "The viewport must expand to the window's aspect ratio.")
    assert(workspace.encloses(editor.editor_panel.get_global_rect()))
    assert(workspace.encloses(editor.palette.get_global_rect()))
    var board_center: Vector2i = editor.game.screen_to_cell(editor.game.get_canvas_transform() * editor.game._cell_position(Vector2i(4, 4)))
    assert(board_center == Vector2i(4, 4), "The scaled board must still map pointer positions to cells.")
    editor._open_source()
    editor.source_error.text = "Source diagnostic for layout"
    await get_tree().process_frame
    await get_tree().process_frame
    assert(editor.source_dialog.visible and editor.source.has_focus())
    assert(workspace.encloses(Rect2(editor.source_dialog.position, editor.source_dialog.size)))
    assert(not editor.source.get_rect().intersects(editor.source_error.get_rect()), "Source and diagnostics must not overlap.")
    editor.source_dialog.hide()
    editor._start_playtest()
    await get_tree().process_frame
    await get_tree().process_frame
    var game: Node2D = editor.test_game
    assert(workspace.encloses(game.hud_panel.get_global_rect()))
    assert(workspace.encloses(game.palette.get_global_rect()))
    game._finish_run(1)
    assert(game.results.visible and workspace.encloses(Rect2(game.results.position, game.results.size)))
    editor._end_playtest()
    await get_tree().process_frame
  get_window().size = original_size

func _choose_particle(picker: OptionButton, name: String) -> void:
  for i in range(1, picker.item_count):
    if picker.get_item_metadata(i) == name:
      picker.item_selected.emit(i)
      return
  assert(false, "Particle is missing from the dropdown: " + name)

func _check_build_areas(editor, target: String) -> void:
  var level_source := "6 x 6;\ngoal: {photon: 1, 2, 3};\ninventory: {wall=3, edge_wall=1};\n# Preserve this comment.\n"
  editor._set_source(level_source)
  await get_tree().process_frame
  editor.block_area_button.pressed.emit()
  _area_drag(editor.game, Vector2i(5, 5), Vector2i(5, 5))
  assert(editor.parsed.no_build_areas == [Rect2i(5, 5, 1, 1)], "A single click should block one cell.")
  editor._undo_editor()
  _area_drag(editor.game, Vector2i(4, 4), Vector2i(1, 1))
  assert(editor.parsed.no_build_areas == [Rect2i(1, 1, 4, 4)], "A reverse drag should block the entire rectangle.")
  assert(PARSER.parse(level_source + "no_build: {x=4..6, y=1};").has("error"))
  editor.unblock_area_button.pressed.emit()
  _area_drag(editor.game, Vector2i(2, 2), Vector2i(3, 3))
  for x in range(6):
    for y in range(6):
      var cell := Vector2i(x, y)
      var blocked := Rect2i(1, 1, 4, 4).has_point(cell) and not Rect2i(2, 2, 2, 2).has_point(cell)
      assert(editor.game._is_build_blocked(cell) == blocked, "Unblocking should clear only the selected cells.")
  editor._undo_editor()
  assert(editor.game._is_build_blocked(Vector2i(2, 2)))
  editor._redo_editor()
  assert(not editor.game._is_build_blocked(Vector2i(2, 2)))
  editor.palette.buttons.holder.pressed.emit()
  assert(not editor.game.area_selection_enabled)
  editor._board_click(Vector2i(1, 2), MOUSE_BUTTON_LEFT)
  assert(editor.game._building_at(Vector2i(1, 2)) != null, "The level author can still place starting buildings in restricted cells.")
  var saved: String = editor.source.text
  editor._write_file(target)
  editor._set_source(level_source)
  editor.file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
  editor._file_selected(target)
  DirAccess.remove_absolute(target)
  assert(editor.source.text == saved and saved.contains("# Preserve this comment."))
  editor._start_playtest()
  var player = editor.test_game
  assert(player._building_at(Vector2i(1, 2)) != null, "Authored buildings in restricted cells should load in playtest.")
  player._select_inventory("wall")
  player._click_cell(Vector2i(1, 1), MOUSE_BUTTON_LEFT)
  player._drop_inventory("wall", _screen_cell(player, Vector2i(4, 4)))
  assert(player.inventory.wall == 3 and player.cost == 0 and player.undo_history.is_empty(), "Rejected clicks and drops should leave the build unchanged.")
  assert(player._building_at(Vector2i(1, 1)) == null and player._building_at(Vector2i(4, 4)) == null)
  player._click_cell(Vector2i(2, 2), MOUSE_BUTTON_LEFT)
  var wall: Node = player._building_at(Vector2i(2, 2))
  assert(wall != null and player.inventory.wall == 2)
  player._click_cell(Vector2i(2, 2), MOUSE_BUTTON_RIGHT)
  player._move_selected_to(Vector2i(1, 1))
  assert(wall.get_meta("cell") == Vector2i(2, 2), "Players cannot move buildings into a restricted area.")
  player._move_selected_to(Vector2i(3, 3))
  assert(wall.get_meta("cell") == Vector2i(3, 3))
  player._select_inventory("edge_wall")
  player._click_cell(Vector2i(0, 2), MOUSE_BUTTON_LEFT, null, "E")
  assert(player.inventory.edge_wall == 1, "A restricted edge should also be blocked from the adjoining unrestricted cell.")
  player._click_cell(Vector2i(0, 2), MOUSE_BUTTON_LEFT, null, "N")
  var edge: Node = player._building_at(Vector2i(0, 2), "edge_wall", "N")
  assert(edge != null)
  player._click_cell(Vector2i(0, 2), MOUSE_BUTTON_RIGHT, edge, "N")
  player._rotate_selected()
  assert(player._building_at(Vector2i(0, 2), "edge_wall", "N") == edge, "Rotating an edge wall into a restricted area should be blocked.")
  editor._end_playtest()

func _area_drag(game, first: Vector2i, last: Vector2i) -> void:
  for pressed in [true, false]:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = _screen_cell(game, first if pressed else last)
    get_viewport().push_input(event, true)

func _screen_cell(game, cell: Vector2i) -> Vector2:
  return game.get_global_transform_with_canvas() * game._cell_position(cell)
