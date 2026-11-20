extends Node

const GAME = preload("res://MainScene/level_game.tscn")
const PARSER = preload("res://Levels/level_parser.gd")

func _ready() -> void:
  var level: Dictionary = PARSER.parse(FileAccess.get_file_as_string("res://Tests/magnet_fixture.level"))
  assert(not level.has("error"))
  assert(level.buildings[3].accepted == ["electron", "positron"])
  assert(level.goals[0].has("[electron,positron]"))
  var goal_expression: Dictionary = PARSER.parse("2 x 2; goal: {[(electron OR up) AND up_r]: 1, 2, 3};")
  assert(goal_expression.goals[0].has("[up_r]"))
  goal_expression = PARSER.parse("2 x 2; goal: {[electron OR (positron]: 1, 2, 3};")
  assert(goal_expression.has("error"))
  var expression: Dictionary = PARSER.parse("2 x 2; goal: {electron: 1, 2, 3}; detector: {x=0,y=0,[electron OR up AND up_r]};")
  assert(expression.buildings[0].accepted == ["electron", "up_r"])
  expression = PARSER.parse("2 x 2; goal: {electron: 1, 2, 3}; detector: {x=0,y=0,[(electron OR up) AND up_r]};")
  assert(expression.buildings[0].accepted == ["up_r"])
  expression = PARSER.parse("2 x 2; goal: {electron: 1, 2, 3}; detector: {x=0,y=0,[electron OR (positron]};")
  assert(expression.has("error"))
  var impossible := PARSER.parse("3 x 3; goal: {[electron AND photon]: 1, 1, 1};")
  assert(impossible.has("error"), "Mutually exclusive goal expression must be rejected")
  var overlap := PARSER.parse("3 x 3; goal: {photon: 1, 1, 1}; wall: {x=1,y=1}; mirror: {x=1,y=1};")
  assert(overlap.has("error"), "Overlapping buildings must be rejected")
  var metadata := PARSER.parse("3 x 3;\ntitle: A small test;\nhint: Try the mirror;\ngoal: {photon: 1, 1, 1};")
  assert(metadata.title == "A small test" and metadata.hint == "Try the mirror")
  var migrated := PARSER.parse("4 x 4; goal: {[photon_b]: 1, 2, 3}; emitter: {x=0,y=0,[photon_r,up]}; rail: {x=1,y=0}; inventory: {rail=2,gate=1};")
  assert(migrated.goals[0].has("[photon]") and migrated.goal_targets[0]["[photon]"] == "[photon]")
  assert(migrated.buildings.size() == 1 and migrated.buildings[0].particles == ["photon", "up_r"])
  assert(migrated.inventory == {"gate": 1}, "Saved rails should stay unavailable.")
  var game = GAME.instantiate()
  game.level = level
  game._place_building(level.buildings[3], false)
  assert(game.buildings[0].accepted == ["electron", "positron"])
  game.buildings[0].free()
  game.buildings.clear()
  var candidate := {"goal": level.goals[0], "tier": 0}
  assert(game._meets_output(candidate, {"electron": 10, "positron": 0}, 10.0, false))
  assert(game._meets_output(candidate, {"electron": 6, "positron": 4}, 10.0, false))
  assert(not game._meets_output(candidate, {"electron": 9, "positron": 0}, 10.0, false))
  assert(game._goal_count({"up": 4, "up_r": 2}, "[up,up_r]") == 4)
  game._place_building(level.buildings[2], false)
  game.selected_building = game.buildings[0]
  assert(game.selected_building.polarity == -1)
  game._rotate_selected()
  assert(game.selected_building.polarity == 1)
  game.undo_build()
  assert(game.buildings[0].polarity == -1, "Build undo should restore polarity")
  game.redo_build()
  assert(game.buildings[0].polarity == 1, "Build redo should reapply polarity")
  game._place_building({"kind": "magnet", "x": 0, "y": 0, "fixed": "pc", "polarity": "-"}, false)
  game.selected_building = game.buildings[1]
  game._rotate_selected()
  assert(game.selected_building.polarity == -1)
  game.free()
  Global.selected_level = "res://Tests/magnet_fixture.level"
  game = GAME.instantiate()
  game.editor_playtest = true
  get_tree().root.add_child.call_deferred(game)
  await get_tree().process_frame
  game._place_building({"kind": "mirror", "x": 0, "y": 0}, true)
  game.selected_building = game._building_at(Vector2i(0, 0))
  var mirror_orientation: int = game.selected_building.orientation
  var key := InputEventKey.new()
  key.pressed = true
  key.keycode = KEY_Q
  game._unhandled_input(key)
  assert(game.selected_building.orientation == posmod(mirror_orientation - 1, 8))
  key.keycode = KEY_E
  game._unhandled_input(key)
  assert(game.selected_building.orientation == mirror_orientation)
  assert(not game.has_method("_open_config"))
  assert(game.buildings[3].accepted == ["electron", "positron"])
  assert(game.output_rows[0].meter.markers.size() == 2)
  assert(game.output_rows[0].meter.markers[1].tiers == PackedStringArray(["2", "3"]))
  # Turn the positron beam towards the detector.
  game.selected_building = game.buildings[2]
  game._rotate_selected()
  game.begin_run()
  assert(game.get_playback_speed() == 1.0)
  for tick in range(roundi(SimulationGrid.TICKS_PER_STEP * SimulationGrid.GRID_TICKS_PER_STEP * game.WATCH_STEPS)):
    assert(game.forecast == null, "The player should see the machine run before a forecast starts")
    game.step_simulation(SimulationGrid.TICK)
    if tick == SimulationGrid.TICKS_PER_STEP * SimulationGrid.GRID_TICKS_PER_STEP * 16:
      assert(game.get_playback_speed() > 1.0 and game.get_playback_speed() < 2.0)
    for child in game.get_children():
      if child is Particle and child.is_queued_for_deletion(): child.free()
  assert(game.forecast != null)
  assert(game.get_playback_speed() == 2.0)
  assert(game.recent_counts.positron > 0)
  var live_counts: Dictionary = game.total_counts.duplicate()
  var forecast_deadline := Time.get_ticks_msec() + 20000
  while game.forecast != null and not game.completed and Time.get_ticks_msec() < forecast_deadline:
    await get_tree().process_frame
  assert(game.completed, "A positron beam meeting the grouped goal should complete the level")
  assert(game.results.dialog_text.begins_with("1 star(s) earned"))
  assert(game.total_counts == live_counts, "The forecast must leave the live simulation alone")
  game.stop_to_build()
  game.begin_run()
  assert(game.get_playback_speed() == 1.0)
  game.set_playback_speed(0.5)
  game.elapsed = game.WATCH_STEPS
  assert(game.get_playback_speed() == 0.5, "A manual speed should override the automatic ramp")
  game.free()
  print("Level syntax checks passed")
  get_tree().quit()
