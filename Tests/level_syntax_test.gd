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
  var game = GAME.instantiate()
  game.level = level
  game._place_building(level.buildings[3], false)
  assert(game.buildings[0].accepted == ["electron", "positron"])
  game.buildings[0].free()
  game.buildings.clear()
  var samples: Array[Dictionary] = [{"electron": 5, "positron": 0}]
  assert(game._stable_stars(samples) == 1)
  samples = [{"electron": 3, "positron": 2}]
  assert(game._stable_stars(samples) == 1)
  samples = [{"electron": 4, "positron": 0}]
  assert(game._stable_stars(samples) == 0)
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
  var detector = game.buildings[3]
  game.selected_building = detector
  game._open_config()
  assert(game.config_particles.source_text() == "electron OR positron")
  game._apply_config()
  assert(game.selected_building.accepted == ["electron", "positron"])
  # Turn the positron beam towards the detector.
  game.selected_building = game.buildings[2]
  game._rotate_selected()
  game.begin_run()
  for tick in range(60 * 30):
    if game.completed: break
    game.step_simulation(1.0 / 60.0)
    for child in game.get_children():
      if child is Particle and child.is_queued_for_deletion(): child.free()
  assert(game.completed, "A positron beam meeting the grouped goal should complete the level")
  game.free()
  print("Level syntax checks passed")
  get_tree().quit()
