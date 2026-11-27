extends Node

const EDITOR = preload("res://MainScene/level_editor.tscn")
const PARSER = preload("res://Levels/level_parser.gd")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")
const UI = preload("res://MainScene/workspace_theme.gd")

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
  await _check_touch_scrolling()
  for file in DirAccess.get_files_at("res://Levels"):
    if file.ends_with(".level"):
      assert(not PARSER.parse(FileAccess.get_file_as_string("res://Levels/" + file)).has("error"), file)
  _check_detector_objectives(editor)
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
  editor.rate_medal_input.text = "1/4"
  editor.cost_medal_input.text = "20"
  editor.star_rules.get_child(0).get_meta("rule").cost.text = "10"
  editor._add_star_rule()
  var fields: Dictionary = editor.star_rules.get_child(1).get_meta("rule")
  fields.hit_stars.button_pressed = true
  fields.excluded.text = "mirror, magnet"
  editor._add_star_output(fields.rates, "electron")
  var output_row: VBoxContainer = fields.rates.get_child(0)
  var particles: Control = output_row.get_meta("output").expression
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
  assert(editor.parsed.medals.star.size() == 2, "Star medal alternatives must be separate condition sets")
  assert(editor.parsed.title == "Test puzzle")
  assert(editor.parsed.medals.rate == 0.25 and editor.parsed.medals.cost == 20.0)
  assert(editor.source.text.contains("1/4/tick"), "Bare values in the settings controls should mean per tick.")
  assert(editor.parsed.medals.star[0].cost == 10.0)
  assert(editor.parsed.medals.star[1].rates.has("[up_r]"))
  assert(editor.parsed.medals.star[1].targets["[up_r]"] == "[(electron OR up) AND up_r]")
  assert(editor.parsed.medals.star[1].no_buildings == ["reflector", "magnet"])
  assert(editor.parsed.medals.star[1].hit_stars)
  assert(editor.source.text.contains("[(electron OR up) AND up_r]"))
  editor.star_tool_button.pressed.emit()
  editor._board_click(Vector2i(4, 1), MOUSE_BUTTON_LEFT)
  editor._board_click(Vector2i(4, 2), MOUSE_BUTTON_LEFT)
  editor._board_click(Vector2i(4, 1), MOUSE_BUTTON_LEFT)
  editor._select_move_tool()
  assert(editor.game.level.stars == [Vector2i(4, 2)])
  editor._start_playtest()
  assert(is_instance_valid(editor.test_game), "Playtest must create an isolated game")
  assert(editor.test_game.editor_playtest and editor.test_game.level.medals.star.size() == 2)
  assert(editor.test_game.level.stars == [Vector2i(4, 2)])
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
  await get_tree().process_frame
  await _check_stray_particle_editor(editor)
  editor.free()
  print("Level editor checks passed")
  get_tree().quit()

func _check_detector_objectives(editor) -> void:
  editor._set_source("5 x 5; rate_medal: {1/step}; cost_medal: {30}; star_medal: {any: 2/step}; detector: {x=0,y=0..1,[photon]};")
  editor._open_settings()
  assert(editor.detector_options.size() == 2)
  assert(editor.clear_detectors.get_child_count() == 2)
  editor.clear_mode_input.select(1)
  for choice in editor.clear_detectors.get_children(): choice.button_pressed = true
  editor.rate_medal_input.text = ""
  editor._add_star_output(editor.rate_outputs)
  editor._add_star_output(editor.rate_outputs)
  for index in range(2):
    var output: Dictionary = editor.rate_outputs.get_child(index).get_meta("output")
    output.destination.select(index + 1)
  var star_fields: Dictionary = editor.star_rules.get_child(0).get_meta("rule")
  star_fields.rates.get_child(0).get_meta("output").destination.select(2)
  editor._apply_settings()
  assert(not editor.parsed.has("error"), editor.settings_error.text)
  assert(editor.parsed.clear_ids == ["d1", "d2"])
  assert(editor.parsed.rate_rule.rates == {"any@d1": 0.25, "any@d2": 0.25})
  assert(editor.parsed.medals.star[0].rates.has("any@d2"))
  assert(editor.parsed.buildings[0].id == "d1" and editor.parsed.buildings[1].id == "d2")
  editor._open_settings()
  assert(editor.clear_detectors.get_child(0).button_pressed and editor.clear_detectors.get_child(1).button_pressed)
  assert(editor.rate_outputs.get_child(1).get_meta("output").destination.get_selected_metadata() == "d2")
  editor.settings_dialog.hide()
  editor._move_block(Vector2i(0, 0), Vector2i(2, 2))
  assert(editor.game._building_at(Vector2i(2, 2)).get_meta("detector_id") == "d1")
  editor._select_at(Vector2i(2, 2))
  editor._delete_selected()
  assert(editor.game._building_at(Vector2i(2, 2)) == null)
  assert(editor.parsed.clear_ids == ["d2"] and editor.parsed.rate_rule.rates == {"any@d2": 0.25})
  assert(editor.parsed.medals.star[0].rates.has("any@d2"))
  editor._select_at(Vector2i(0, 1))
  editor._delete_selected()
  assert(not editor.parsed.has("clear_ids") and not editor.parsed.has("rate_rule"))
  assert(editor.parsed.medals.star[0].rates == {"any": 0.5})
  editor._undo_editor()
  assert(editor.game._building_at(Vector2i(0, 1)) != null and editor.parsed.clear_ids == ["d2"])

func _check_touch_scrolling() -> void:
  var layer := CanvasLayer.new()
  layer.layer = 110
  add_child(layer)
  var scroll := UI.vertical_scroll()
  scroll.size = Vector2(200, 120)
  layer.add_child(scroll)
  var rows := VBoxContainer.new()
  rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  scroll.add_child(rows)
  var presses := [0]
  for i in range(10):
    var button := UI.button(rows, "Row %d" % i, func() -> void: presses[0] += 1)
    button.custom_minimum_size.y = 42
  await get_tree().process_frame
  await get_tree().process_frame
  var touch_emulation := Input.emulate_touch_from_mouse
  Input.emulate_touch_from_mouse = true
  var at := Vector2(70, 70)
  var down := InputEventMouseMotion.new()
  down.position = at
  down.device = InputEvent.DEVICE_ID_EMULATION
  get_viewport().push_input(down, true)
  _mouse_button(MOUSE_BUTTON_LEFT, at, true, InputEvent.DEVICE_ID_EMULATION)
  _touch(0, at, true)
  var swipe := InputEventMouseMotion.new()
  swipe.position = at - Vector2(0, 33)
  swipe.relative = swipe.position - at
  swipe.button_mask = MOUSE_BUTTON_MASK_LEFT
  swipe.device = InputEvent.DEVICE_ID_EMULATION
  get_viewport().push_input(swipe, true)
  _touch_drag(0, swipe.position)
  _mouse_button(MOUSE_BUTTON_LEFT, swipe.position, false, InputEvent.DEVICE_ID_EMULATION)
  _touch(0, swipe.position, false)
  assert(scroll.scroll_vertical >= 30 and presses[0] == 0,
    "Swiping from a button should scroll without activating it. Scroll: %d, presses: %d." % [scroll.scroll_vertical, presses[0]])
  Input.emulate_touch_from_mouse = touch_emulation
  await get_tree().process_frame
  await get_tree().process_frame
  var tap: Vector2 = rows.get_child(2).get_global_rect().get_center()
  _mouse_button(MOUSE_BUTTON_LEFT, tap, true, InputEvent.DEVICE_ID_EMULATION)
  _touch(0, tap, true)
  _mouse_button(MOUSE_BUTTON_LEFT, tap, false, InputEvent.DEVICE_ID_EMULATION)
  _touch(0, tap, false)
  assert(presses[0] == 1, "An ordinary tap should still activate a button in the scroller.")
  layer.free()

func _check_stray_particle_editor(editor) -> void:
  editor._set_source(editor.NEW_LEVEL)
  assert(editor.palette.buttons.has("stray_particle"))
  var cell := Vector2i(3, 3)
  editor._select_palette_kind("stray_particle")
  editor._board_click(cell, MOUSE_BUTTON_LEFT)
  assert(editor.selected_building.facing == "E")
  await get_tree().process_frame
  _tap_cell(editor.game, cell)
  assert(editor.selected_building.facing == "REST" and editor.source.text.contains("REST"))
  var particle: OptionButton = editor.visual_fields.particle
  for index in range(particle.item_count):
    if particle.get_item_metadata(index) == "proton": particle.select(index)
  editor._apply_visual_properties()
  assert(editor.selected_building.particle_name == "proton")
  editor.game.begin_run()
  assert(editor.game._particles().size() == 1 and editor.game._particles()[0].speed == 0.0)
  editor._reset_preview()
  assert(editor.game._particles().is_empty() and editor.game._building_at(cell).visible)

func _check_adaptive_layout(editor: Control) -> void:
  var original_size := get_window().size
  assert(editor.file_dialog.use_native_dialog and editor.file_dialog.access == FileDialog.ACCESS_FILESYSTEM)
  var phone_landscape := Vector2i(1160, 540)
  for resolution in [Vector2i(800, 500), Vector2i(1920, 650), Vector2i(390, 844), phone_landscape, Vector2i(2304, 1440)]:
    var original_source: String = editor.source.text
    get_window().size = resolution
    if resolution == phone_landscape:
      get_window().size_changed.disconnect(Global._update_window_scale)
      get_window().content_scale_size = phone_landscape
    await get_tree().process_frame
    await get_tree().process_frame
    var workspace := get_viewport().get_visible_rect()
    assert(absf(workspace.size.aspect() - Vector2(resolution).aspect()) < 0.01, "The viewport must expand to the window's aspect ratio.")
    assert(workspace.encloses(editor.editor_panel.get_global_rect()))
    assert(workspace.encloses(editor.palette.get_global_rect()))
    if resolution == phone_landscape:
      _check_landscape_editor_docks(editor, workspace)
      editor._set_source(original_source + "\nemitter: {x=4,y=4,E};\nmagnet: {x=5,y=4,+};\n")
      _tap_cell(editor.game, Vector2i(4, 4))
      _tap_cell(editor.game, Vector2i(5, 4))
      assert(editor.game._building_at(Vector2i(4, 4)).get_meta("entry").facing == "NE")
      assert(editor.game._building_at(Vector2i(5, 4)).polarity == -1)
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
    if resolution.x < resolution.y:
      assert(editor.compact_layout and not editor.palette.visible)
      editor.tools_button.pressed.emit()
      assert(editor.palette.visible and workspace.encloses(editor.palette.get_global_rect()))
      editor.tools_button.pressed.emit()
      editor._open_settings()
      await get_tree().process_frame
      assert(workspace.encloses(Rect2(editor.settings_dialog.position, editor.settings_dialog.size)))
      editor.settings_dialog.hide()
      editor.file_dialog.use_native_dialog = false
      editor.file_dialog.access = FileDialog.ACCESS_USERDATA
      for mode in [FileDialog.FILE_MODE_OPEN_FILE, FileDialog.FILE_MODE_SAVE_FILE]:
        editor._show_file_dialog(mode)
        await get_tree().process_frame
        var dialog_rect := Rect2(editor.file_dialog.position, editor.file_dialog.size)
        editor.file_dialog.hide()
        assert(dialog_rect.size.y >= 280 and workspace.encloses(dialog_rect),
          "File dialog %s must fit inside %s with room for the file list." % [dialog_rect, workspace])
      editor.file_dialog.access = FileDialog.ACCESS_FILESYSTEM
      editor.file_dialog.use_native_dialog = true
      var original: String = editor.source.text
      _check_camera(editor.game)
      editor._set_source(original)
    editor._start_playtest()
    await get_tree().process_frame
    await get_tree().process_frame
    var game: Node2D = editor.test_game
    assert(workspace.encloses(game.hud_panel.get_global_rect()))
    assert(workspace.encloses(game.palette.get_global_rect()))
    if resolution == phone_landscape:
      assert(not game.compact_layout and game.game_sidebar.visible and game.hud_options.visible)
      var emitter: Node = game._building_at(Vector2i(4, 4))
      var magnet: Node = game._building_at(Vector2i(5, 4))
      _tap_cell(game, Vector2i(4, 4))
      assert(CATALOG.DIRECTIONS[emitter.orientation] == "N")
      _tap_cell(game, Vector2i(5, 4))
      assert(magnet.polarity == 1)
      magnet.set_meta("fixed_rotation", true)
      _tap_cell(game, Vector2i(5, 4))
      assert(magnet.polarity == 1, "A touch tap must respect the same lock as Q.")
    if resolution.x < resolution.y:
      game.sidebar_toggle.pressed.emit()
      assert(game.palette.is_visible_in_tree() and workspace.encloses(game.game_sidebar.get_global_rect()))
      game.sidebar_toggle.pressed.emit()
      _check_camera(game)
    game._show_results()
    assert(game.results.visible and workspace.encloses(Rect2(game.results.position, game.results.size)))
    editor._end_playtest()
    await get_tree().process_frame
    if resolution == phone_landscape:
      get_window().size_changed.connect(Global._update_window_scale)
      editor._set_source(original_source)
  get_window().size = original_size

func _check_landscape_editor_docks(editor, workspace: Rect2) -> void:
  var toolbar: PanelContainer = editor.game.get_node("SimulationControls/Panel")
  var more: Button = toolbar.get_node("Margin/Controls/More")
  assert(not editor.compact_layout and editor.palette.visible and editor.edit_bar.visible and editor.file_bar.visible)
  assert(not more.visible and toolbar.get_node("Margin/Controls/Speed").visible)
  assert(toolbar.size.y <= 55.0, "The simulation toolbar should only occupy one row in landscape.")
  assert(editor.playtest_button.get_parent() == editor.file_bar)
  assert(editor.editor_panel.size.y <= 100.0, "Playtest and status should fit alongside the file actions.")
  assert(editor.game._board_view().size.y >= workspace.size.y * 0.70)
  editor.game.fit_board()
  var board_rect: Rect2 = editor.game.get_canvas_transform() * editor.game.level_bounds
  assert(editor.game._board_view().encloses(board_rect), "The fitted board should sit between the toolbars.")

func _tap_cell(game, cell: Vector2i) -> void:
  var at := _screen_cell(game, cell)
  _touch(0, at, true)
  _touch(0, at, false)

func _check_camera(game) -> void:
  var camera: Camera2D = game.get_node("Camera2D")
  var cell := Vector2i(5, 4)
  var anchor := _screen_cell(game, cell)
  var fitted := camera.zoom.x
  var count: int = game.buildings.size()
  if game.editor_preview:
    game.external_palette.kind_selected.emit("wall")
  else:
    game.inventory["wall"] = 1
    game._select_inventory("wall")
  _mouse_button(MOUSE_BUTTON_WHEEL_UP, anchor, true)
  assert(camera.zoom.x > fitted, "The wheel should zoom in.")
  assert(_screen_cell(game, cell).distance_to(anchor) < 1.0, "Zoom should preserve the cell under the pointer.")
  _mouse_button(MOUSE_BUTTON_RIGHT, anchor, true)
  var drag := InputEventMouseMotion.new()
  drag.position = anchor + Vector2(30, -12)
  drag.relative = drag.position - anchor
  get_viewport().push_input(drag, true)
  _mouse_button(MOUSE_BUTTON_RIGHT, drag.position, false)
  assert(_screen_cell(game, cell).distance_to(drag.position) < 1.0,
    "Dragging should pan at the current zoom. Expected %s, got %s." % [drag.position, _screen_cell(game, cell)])
  game.fit_board()
  assert(is_equal_approx(camera.zoom.x, fitted) and _screen_cell(game, cell).distance_to(anchor) < 1.0)

  var center := _screen_cell(game, Vector2i(4, 4))
  var finger := center - Vector2(22, 0)
  var other := center + Vector2(22, 0)
  _touch(0, finger, true)
  _mouse_button(MOUSE_BUTTON_LEFT, finger, true, InputEvent.DEVICE_ID_EMULATION)
  _touch(1, other, true)
  _touch_drag(1, other + Vector2(30, 0))
  assert(camera.zoom.x > fitted, "A two-finger spread should zoom in.")
  assert(_screen_cell(game, Vector2i(4, 4)).distance_to(center + Vector2(15, 0)) < 1.0)
  _touch(1, other + Vector2(30, 0), false)
  _touch(0, finger, false)
  _mouse_button(MOUSE_BUTTON_LEFT, finger, false, InputEvent.DEVICE_ID_EMULATION)
  game.fit_board()
  _touch(0, center, true)
  _touch_drag(0, center + Vector2(0, 24))
  _touch(0, center + Vector2(0, 24), false)
  assert(_screen_cell(game, Vector2i(4, 4)).distance_to(center + Vector2(0, 24)) < 1.0, "A one-finger drag should pan.")
  assert(game.buildings.size() == count, "Camera gestures must preserve the board even when a placement tool is active.")
  var destination := _screen_cell(game, cell)
  _touch(0, destination, true)
  _mouse_button(MOUSE_BUTTON_LEFT, destination, true, InputEvent.DEVICE_ID_EMULATION)
  _touch(0, destination, false)
  _mouse_button(MOUSE_BUTTON_LEFT, destination, false, InputEvent.DEVICE_ID_EMULATION)
  assert(game.buildings.size() == count + 1 and game._building_at(cell) != null, "A touch tap should place once at the transformed cell.")
  game.fit_board()

func _mouse_button(button: int, at: Vector2, pressed: bool, device := 0) -> void:
  var event := InputEventMouseButton.new()
  event.button_index = button
  event.position = at
  event.pressed = pressed
  event.device = device
  get_viewport().push_input(event, true)

func _touch(index: int, at: Vector2, pressed: bool) -> void:
  var event := InputEventScreenTouch.new()
  event.index = index
  event.position = at
  event.pressed = pressed
  get_viewport().push_input(event, true)

func _touch_drag(index: int, at: Vector2) -> void:
  var event := InputEventScreenDrag.new()
  event.index = index
  event.position = at
  get_viewport().push_input(event, true)

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
