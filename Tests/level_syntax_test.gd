extends Node

const GAME = preload("res://MainScene/level_game.tscn")
const PARSER = preload("res://Levels/level_parser.gd")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")

func _ready() -> void:
  var level: Dictionary = PARSER.parse(FileAccess.get_file_as_string("res://Tests/magnet_fixture.level"))
  assert(not level.has("error"))
  assert(level.buildings[3].accepted == ["electron", "positron"])
  assert(level.medals.star[0].rates.has("[electron,positron]"))
  var goal_expression: Dictionary = PARSER.parse("2 x 2; goal: {[(electron OR up) AND up_r]: 1, 2, 3};")
  assert(goal_expression.medals.star[0].rates.has("[up_r]"))
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
  var reflectors := PARSER.parse("3 x 3; goal: {anti_neutrino: 1, 1, 1}; mirror: {x=0,y=0}; reflector: {x=1,y=1}; inventory: {mirror=2}; emitter: {x=2,y=2,[anti_neutrino,proton]};")
  assert(not reflectors.has("error") and reflectors.buildings[0].kind == "reflector" and reflectors.buildings[1].kind == "reflector" and reflectors.inventory.reflector == 2)
  assert(reflectors.buildings[2].particles == ["anti_neutrino", "proton"])
  var removed := PARSER.parse("3 x 3; goal: {electron: 1, 1, 1}; emitter: {x=0,y=0,[nucleus]};")
  assert(removed.has("error"), "Removed particles must be rejected.")
  var bosons := PARSER.parse("3 x 3; goal: {photon: 1, 2, 3}; emitter: {x=1,y=1,[gluon,z_boson,w_plus,w_minus]};")
  assert(not bosons.has("error") and bosons.buildings[0].particles == ["gluon", "z_boson", "w_plus", "w_minus"])
  assert(overlap.has("error"), "Overlapping buildings must be rejected")
  var metadata := PARSER.parse("3 x 3;\ntitle: A small test;\nhint: Try the mirror;\ngoal: {photon: 1, 1, 1};")
  assert(metadata.title == "A small test" and not metadata.has("hint"), "Existing hints should be ignored.")
  var migrated := PARSER.parse("4 x 4; goal: {[photon_b]: 1, 2, 3}; emitter: {x=0,y=0,[photon_r,up]}; rail: {x=1,y=0}; inventory: {rail=2,gate=1};")
  assert(migrated.medals.star[0].rates.has("[photon]") and migrated.medals.star[0].targets["[photon]"] == "[photon]")
  assert(migrated.buildings.size() == 1 and migrated.buildings[0].particles == ["photon", "up_r"])
  assert(migrated.inventory == {"gate": 1}, "Saved rails should stay unavailable.")
  var game = GAME.instantiate()
  game.level = level
  game._place_building(level.buildings[3], false)
  assert(game.buildings[0].accepted == ["electron", "positron"])
  game.buildings[0].free()
  game.buildings.clear()
  var candidate := {"[electron,positron]": 1.0}
  assert(game._meets_output(candidate, {"electron": 10, "positron": 0}, 10.0))
  assert(game._meets_output(candidate, {"electron": 6, "positron": 4}, 10.0))
  assert(not game._meets_output(candidate, {"electron": 9, "positron": 0}, 10.0))
  var slow_candidate := {"electron": 1.0 / 300.0}
  assert(game._meets_output(slow_candidate, {"electron": 6}, 1800.0))
  assert(not game._meets_output(slow_candidate, {"electron": 6}, 1920.0), "The forecast should use the measured rate.")
  assert(game._goal_count({"up": 4, "up_r": 2}, "[up,up_r]") == 4)
  var counts := {}
  PARTICLES.record_detection(counts, "up_r")
  assert(counts == {"any": 1, "up_r": 1, "up": 1})
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
  game._place_building({"kind": "reflector", "x": 0, "y": 0}, true)
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
  assert(game.output_rows[0].meter.target == 1.0 and game.output_rows[0].key == "any")
  assert(game.output_rows[1].meter.target == 2.0)
  # Turn the positron beam towards the detector.
  game.selected_building = game.buildings[2]
  game._rotate_selected()
  game.begin_run()
  assert(game.get_playback_speed() == 1.0)
  game.editor_playtest = false
  key.keycode = KEY_ESCAPE
  var placed_mirror: Node = game._building_at(Vector2i(0, 0))
  game._unhandled_input(key)
  assert(not game.simulating and game._building_at(Vector2i(0, 0)) == placed_mirror, "Escape should retain the player's build.")
  game.editor_playtest = true
  game.begin_run()
  assert(game.forecast == null, "The forecast should wait for the first live detection.")
  _run_steps(game, 16)
  assert(game.forecast != null)
  assert(game.get_playback_speed() > 1.0 and game.get_playback_speed() < 2.0)
  _run_steps(game, 12)
  assert(game.get_playback_speed() == 2.0)
  var live_counts: Dictionary = game.total_counts.duplicate()
  _advance_forecast(game)
  assert(game.completed and "rate" in game.earned_medals and "star" not in game.earned_medals)
  game._show_results()
  assert(game.results_text.text.begins_with("2 of 3 medals earned"))
  game._result_action(&"continue")
  assert(game.running and not game.results.visible)
  assert(game.total_counts == live_counts, "The forecast must leave the live simulation alone")
  game.stop_to_build()
  game.begin_run()
  assert(game.get_playback_speed() == 1.0)
  game.set_playback_speed(0.5)
  game.elapsed = 28.0
  assert(game.get_playback_speed() == 0.5, "A manual speed should override the automatic ramp")
  game.free()
  _check_sparse_output()
  _check_one_off_output()
  _check_burst_output()
  _check_stray_particles()
  _check_map_stars()
  _check_bundled_launch()
  print("Level syntax checks passed")
  get_tree().quit()

func _advance_forecast(game: Node2D) -> void:
  var deadline := Time.get_ticks_msec() + 30000
  while game.forecast != null and Time.get_ticks_msec() < deadline:
    game._process(0.0)
  assert(game.forecast == null, "The forecast did not finish within the test budget.")

func _run_sparse_level(repeating: bool) -> Node2D:
  var game: Node2D = GAME.instantiate()
  game.editor_playtest = true
  game.level_override = PARSER.parse("3 x 2; rate_medal: {1/300}; cost_medal: {5}; star_medal: {photon: 1/300}; emitter: {x=0,y=0,E,[electron],rate=1/300}; detector: {x=2,y=0,[electron]}; inventory: {wall=1};")
  get_tree().root.add_child(game)
  assert(game._place_inventory_building("wall", Vector2i(0, 1)))
  game.begin_run()
  game.buildings[0].repeat_sequence = repeating
  _run_steps(game, 3)
  assert(game.total_counts.get("electron", 0) == 1 and game.forecast != null)
  return game

func _check_sparse_output() -> void:
  var game := _run_sparse_level(true)
  _advance_forecast(game)
  assert(is_equal_approx(game.output_rows[0].meter.rate, 1.0 / 300.0), "The sparse stream should measure one detection every 300 steps.")
  assert(game.completed and game.earned_medals == ["cost", "rate"], "A build at the cost limit should earn the Cost medal.")
  assert(game.cost_rows[0].label.text == "$5 / $5")
  assert(game.total_counts.get("electron", 0) == 1, "Forecast counts must never enter live totals.")
  game.stop_to_build()
  assert(game.output_rows[0].meter.rate == 0.0 and game.output_rows[0].meter.sample_steps == 0.0)
  game.free()

func _check_one_off_output() -> void:
  var game := _run_sparse_level(false)
  _advance_forecast(game)
  assert(game.completed and game.earned_medals == ["cost"] and game.results_button.visible)
  assert(game.output_rows[0].meter.rate == 0.0, "A single detection should not count as sustained output.")
  game.free()

func _check_burst_output() -> void:
  var source := "3 x 2; rate_medal: {0.5}; cost_medal: {0}; star_medal: {photon: 0.25; cost: 0}; emitter: {x=0,y=0,E,[photon,photon,photon,electron,electron,electron,electron,electron,electron,electron,electron,electron],rate=1/step}; detector: {x=2,y=0,[photon]};"
  var game: Node2D = GAME.instantiate()
  game.editor_playtest = true
  game.level_override = PARSER.parse(source)
  get_tree().root.add_child(game)
  game.begin_run()
  _run_steps(game, 2)
  assert(game.forecast != null, "The first burst should start a forecast.")
  _advance_forecast(game)
  assert(game.output_rows[0].meter.rate == 0.25 and game.output_rows[0].meter.sample_steps == 12.0,
    "Count three detections over the full twelve-step cycle, including silence.")
  assert(game.earned_medals == ["cost", "star"], "The burst should earn only the medals whose limits it meets.")
  game.free()

func _check_stray_particles() -> void:
  var source := "5 x 2; rate_medal: {1}; cost_medal: {10}; star_medal: {any: 1}; inventory: {stray_particle=1}; detector: {x=4,y=1,[electron]}; stray_particle: {x=1,y=0,REST,[proton]};"
  var parsed := PARSER.parse(source)
  assert(not parsed.has("error"))
  assert(PARSER.parse_building("stray_particle", "x=2,y=0,[electron,proton]", 5, 2).has("error"))
  assert(PARSER.parse_building("wall", "x=2,y=0,REST", 5, 2).has("error"))
  assert(CATALOG.next_stray_heading("N", 1, 4) == "REST" and CATALOG.next_stray_heading("REST", 1, 4) == "E")
  var game: Node2D = GAME.instantiate()
  game.editor_playtest = true
  game.level_override = parsed
  get_tree().root.add_child(game)
  var start := Vector2i(0, 1)
  assert(game._place_inventory_building("stray_particle", start))
  game.selected_building = game._building_at(start)
  game._rotate_selected(-1)
  assert(game.selected_building.facing == "REST")
  game.undo_build()
  assert(game._building_at(start).facing == "E")
  game.redo_build()
  game.selected_building = game._building_at(start)
  assert(game.selected_building.facing == "REST")
  game._rotate_selected(1)
  var proton_preview: Particle = game._building_at(Vector2i(1, 0)).get_node("ParticlePreview")
  var electron_preview: Particle = game._building_at(start).get_node("ParticlePreview")
  assert(game._particles().is_empty(), "The previews must stay out of the simulation.")
  game.begin_run()
  assert(game._particles().size() == 2 and not game._building_at(start).visible)
  var proton: Particle = game._particles().filter(func(p: Particle) -> bool: return p.flavour == Particle.Flavour.PROTON).front()
  var electron: Particle = game._particles().filter(func(p: Particle) -> bool: return p.flavour == Particle.Flavour.ELECTRON).front()
  assert(proton_preview.sprite.global_scale.is_equal_approx(proton.sprite.global_scale))
  assert(electron_preview.sprite.global_scale.is_equal_approx(electron.sprite.global_scale))
  assert(is_equal_approx(proton_preview.world_collision_radius(), proton.world_collision_radius()))
  assert(proton.speed == 0.0 and proton.direction == Vector2.ZERO)
  var rest_position := proton.motion_position()
  _run_steps(game, 3)
  assert(game.total_counts.get("electron", 0) == 1 and proton.motion_position() == rest_position)
  _advance_forecast(game)
  assert(game.completed and "rate" not in game.earned_medals)
  game.stop_to_build()
  assert(game._particles().is_empty() and game._building_at(start).visible)
  game.begin_run()
  assert(game._particles().size() == 2, "Each new run should spawn one fresh particle per piece.")
  game.free()

func _run_steps(game: Node2D, amount: float) -> void:
  for tick in range(roundi(SimulationGrid.TICKS_PER_STEP * SimulationGrid.GRID_TICKS_PER_STEP * amount)):
    game.step_simulation(SimulationGrid.TICK)
    for child in game.get_children():
      if child is Particle and child.is_queued_for_deletion(): child.free()

func _check_map_stars() -> void:
  var source := "5 x 2; rate_medal: {2}; cost_medal: {20}; star_medal: {hit_stars: true; no_buildings: mirror, magnet; cost: 20}; star: {x=1,y=0}; star: {x=3,y=0}; emitter: {x=0,y=0,E,[photon]}; detector: {x=2,y=0,[photon]}; inventory: {mirror=1};"
  var parsed := PARSER.parse(source)
  assert(parsed.medals.star[0].no_buildings == ["reflector", "magnet"])
  assert(PARSER.parse(source + " star: {x=1,y=0};").has("error"))
  assert(PARSER.parse(source + " star: {x=5,y=0};").has("error"))
  var game: Node2D = GAME.instantiate()
  game.editor_playtest = true
  game.level_override = parsed
  get_tree().root.add_child(game)
  game.begin_run()
  _run_steps(game, 3)
  assert(game.completed and game.earned_medals == ["cost"] and game.star_hits.size() == 1,
    "A detector stops the particle before the star behind it.")
  game.stop_to_build()
  assert(game.star_hits.is_empty())
  game.selected_building = game.buildings[1]
  game._move_selected_to(Vector2i(4, 0))
  assert(game._place_inventory_building("reflector", Vector2i(0, 1)))
  game.begin_run()
  _run_steps(game, 3)
  assert(game.star_hits.size() == 2 and game.earned_medals == ["cost"], "An excluded building blocks only the Star medal.")
  game.stop_to_build()
  game.selected_building = game._building_at(Vector2i(0, 1))
  game._remove_selected()
  game.begin_run()
  _run_steps(game, 3)
  assert(game.star_hits.size() == 2 and game.earned_medals == ["cost", "star"])
  game.free()

func _check_bundled_launch() -> void:
  Global.selected_level = "res://Levels/01 - First Contact.level"
  var game: Node2D = GAME.instantiate()
  game.editor_playtest = true
  get_tree().root.add_child(game)
  assert(game.buildings.size() == 4 and game.level.stars.size() == 2)
  game.selected_building = game._building_at(Vector2i(5, 2))
  game._move_selected_to(Vector2i(5, 3))
  game.begin_run()
  _run_steps(game, 8)
  _advance_forecast(game)
  assert(game.output_rows[0].meter.rate == 1.0 and game.output_rows[0].meter.sample_steps == 1.0,
    "First Contact should measure exactly one photon per second from a repeating cycle.")
  assert(game.completed and game.earned_medals.size() == 3, "First Contact should have a route to all three medals.")
  game.free()
