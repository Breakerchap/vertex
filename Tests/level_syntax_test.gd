extends Node

const GAME = preload("res://MainScene/level_game.tscn")
const PARSER = preload("res://Levels/level_parser.gd")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")

func _ready() -> void:
  _check_rate_migration()
  var scoped := PARSER.parse("3 x 3; clear: {a AND b}; rate_medal: {photon@a: 1/step; photon@b: 1/step}; cost_medal: {0}; star_medal: {[up OR down]@a: 1/step}; detector: {x=0,y=0,[photon OR up],id=a}; detector: {x=2,y=2,[photon],id=b};")
  assert(not scoped.has("error"), str(scoped))
  assert(scoped.clear_ids == ["a", "b"])
  assert(scoped.throughput_rule.periods.has("photon@a") and scoped.throughput_rule.periods.has("photon@b"))
  var scoped_counts := {}
  PARTICLES.record_detection(scoped_counts, "photon", "a")
  PARTICLES.record_detection(scoped_counts, "photon", "a")
  assert(scoped_counts.get("photon@b", 0) == 0 and scoped_counts["any"] == 2)
  PARTICLES.record_detection(scoped_counts, "photon", "b")
  assert(scoped_counts["photon@b"] == 1 and scoped_counts["any"] == 3)
  assert(PARSER.parse("2 x 2; clear: {missing}; rate_medal: {1}; cost_medal: {0}; star_medal: {any: 1};").has("error"))
  var scoped_game = GAME.instantiate()
  scoped_game.level = scoped
  scoped_game.total_counts = {"any": 2, "any@a": 2, "photon@a": 2}
  assert(not scoped_game._clear_requirement_met())
  assert(not scoped_game._meets_output(scoped.throughput_rule.periods, scoped_game.total_counts, 1.0))
  scoped_game.total_counts = scoped_counts
  assert(scoped_game._clear_requirement_met())
  assert(scoped_game._meets_output(scoped.throughput_rule.periods, scoped_counts, 1.0))
  assert(scoped_game._goal_count({"up@a": 3, "up_r@a": 2, "up_r@b": 4}, "[up,up_r]@a") == 3)
  scoped_game.level.clear_mode = "or"
  scoped_game.total_counts = {"any@b": 1}
  assert(scoped_game._clear_requirement_met())
  scoped_game.free()
  var level: Dictionary = PARSER.parse(FileAccess.get_file_as_string("res://Tests/magnet_fixture.level"))
  assert(not level.has("error"))
  assert(level.buildings[3].accepted == ["electron", "positron"])
  assert(level.medals.star[0].periods.has("[electron,positron]"))
  var goal_expression: Dictionary = PARSER.parse("2 x 2; goal: {[(electron OR up) AND up_r]: 1, 2, 3};")
  assert(goal_expression.medals.star[0].periods.has("[up_r]"))
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
  assert(migrated.medals.star[0].periods.has("[photon]") and migrated.medals.star[0].targets["[photon]"] == "[photon]")
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
  var slow_candidate := {"electron": 300.0}
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
  assert(game.output_rows[0].meter.target_period == 4.0 and game.output_rows[0].key == "any")
  assert(game.output_rows[1].meter.target_period == 2.0)
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
  assert(game.completed and "throughput" in game.earned_medals and "star" not in game.earned_medals)
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
  _check_pusher_stars()
  _check_mirrored_z_bosons()
  _check_bundled_launch()
  print("Level syntax checks passed")
  get_tree().quit()

func _check_mirrored_z_bosons() -> void:
  var source := """11 x 13;
rate_medal: {1/step};
cost_medal: {30};
star_medal: {any: 2/step};
emitter: {x=9, y=3, NW, [z_boson], rate=1/step, fixed=pr}
emitter: {x=1, y=3, NE, [z_boson], rate=1/step, fixed=pr}
emitter: {x=7, y=0, N, [electron], rate=1/step, fixed=pr}
emitter: {x=3, y=0, N, [electron], rate=1/step, fixed=pr}
wall: {x=4, y=6}
wall: {x=6, y=6}
"""
  var game = GAME.instantiate()
  game.editor_playtest = true
  game.level_override = PARSER.parse(source)
  assert(not game.level_override.has("error"), str(game.level_override))
  get_tree().root.add_child(game)
  game.begin_run()
  var reflections := [0]
  game.particle_event.connect(func(kind: String, _at: Vector2):
    if kind == "reflection": reflections[0] += 1)
  var mirror := Vector2(-1.0, 1.0)
  var offset := Vector2(10.0 * SimulationGrid.CELL, 0.0)
  for tick in range(900):
    game.step_simulation(SimulationGrid.TICK)
    var particles: Array[Particle] = game._particles()
    for particle in particles:
      var at := particle.motion_position() * mirror + offset
      var heading := particle.direction * mirror
      assert(particles.any(func(other: Particle) -> bool:
        return (other.flavour == particle.flavour and other.motion_position().distance_to(at) < 0.15
          and other.direction.distance_to(heading) < 0.004)), "The Z boson level lost symmetry at tick %d." % tick)
    for child in game.get_children():
      if child is Particle and child.is_queued_for_deletion(): child.free()
  assert(reflections[0] > 30, "The mirrored board should exercise repeated reflections.")
  game.free()

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
  assert(is_equal_approx(game.output_rows[0].meter.period, 1200.0), "The sparse stream should measure one detection every 1200 ticks.")
  assert(game.completed and game.earned_medals == ["cost", "throughput"], "A build at the cost limit should earn the Cost medal.")
  assert(game.cost_rows[0].label.text == "$5 / $5")
  assert(game.total_counts.get("electron", 0) == 1, "Forecast counts must never enter live totals.")
  game.stop_to_build()
  assert(is_inf(game.output_rows[0].meter.period) and game.output_rows[0].meter.sample_grid_ticks == 0.0)
  game.free()

func _check_one_off_output() -> void:
  var game := _run_sparse_level(false)
  _advance_forecast(game)
  assert(game.completed and game.earned_medals == ["cost"] and game.results_button.visible)
  assert(is_inf(game.output_rows[0].meter.period), "A single detection should not count as sustained output.")
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
  assert(game.output_rows[0].meter.period == 16.0 and game.output_rows[0].meter.sample_grid_ticks == 48.0,
    "Count three detections over the full 48-tick cycle, including silence.")
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
  assert(game.completed and "throughput" not in game.earned_medals)
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

func _check_pusher_stars() -> void:
  var game = GAME.instantiate()
  game.editor_playtest = true
  game.level_override = PARSER.parse("3 x 3; goal: {photon: 1, 2, 3}; star: {x=1,y=2}; emitter: {x=0,y=1,E,[photon]}; pusher: {x=1,y=1,N};")
  get_tree().root.add_child(game)
  game.begin_run()
  _run_steps(game, 0.25)
  assert(game.star_hits.has(Vector2i(1, 2)), "A push can take a particle through a star.")
  game.stop_to_build()
  game.begin_run()
  var blocker := PARTICLES.instantiate(Particle.Flavour.PROTON)
  blocker.size = 0.8
  blocker.free_flight = true
  blocker.direction = Vector2.ZERO
  blocker.position = Vector2(1.0, 0.55) * SimulationGrid.CELL
  game.add_child(blocker)
  _run_steps(game, 0.25)
  assert(game._particles() == [blocker] and game.star_hits.is_empty(), "A push interrupted by a collision should stop before the star.")
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
  assert(game.output_rows[0].meter.period == 4.0 and game.output_rows[0].meter.sample_grid_ticks == 4.0,
    "First Contact should measure exactly one photon per four ticks from a repeating cycle.")
  assert(game.completed and game.earned_medals.size() == 3, "First Contact should have a route to all three medals.")
  game.free()

func _check_rate_migration() -> void:
  var legacy := "5 x 5;\n# keep 8/step and cost: 20 unchanged\nrate_medal: {photon@a: 2/step; any: 1/2};\ncost_medal: {30};\nstar_medal: {photon: 1/300; cost: 20; hit_stars: true};\nemitter: {x=0,y=0,E,[photon], rate=1/s};\nemitter: {x=0,y=1,E,[electron]};\nemitter: {x=0,y=2,E,[electron], rate=0.75/tick};\ndetector: {x=4,y=0,[photon],id=a};\n"
  var upgraded := PARSER.migrate_rates(legacy)
  assert(upgraded != legacy and PARSER.migrate_rates(upgraded) == upgraded, "Migration must be idempotent.")
  assert(upgraded.contains("# keep 8/step and cost: 20 unchanged"))
  assert(upgraded.contains("throughput_medal: {photon@a: period=2; any: period=8}"))
  assert(upgraded.contains("cost: 20") and upgraded.contains("photon: period=1200"))
  assert(not upgraded.contains("rate=") and upgraded.contains("period=4"))
  var old_data := PARSER.parse(legacy)
  var new_data := PARSER.parse(upgraded)
  assert(not old_data.has("error") and not new_data.has("error"))
  assert(old_data.medals == new_data.medals and old_data.throughput_rule == new_data.throughput_rule)
  assert(old_data.buildings.size() == new_data.buildings.size())
  for i in range(3):
    assert(is_equal_approx(old_data.buildings[i].period, new_data.buildings[i].period))
  assert(new_data.buildings[0].period == 4.0 and new_data.buildings[1].period == 4.0 and is_equal_approx(new_data.buildings[2].period, 4.0 / 3.0))
  assert(new_data.medals.cost == 30.0)
  var goal := "3 x 3; goal: {photon: 1/s, 2/step, inf; cost: 30, 20, 10}; emitter: {x=0,y=0,rate=1/2};"
  var migrated_goal := PARSER.migrate_rates(goal)
  assert(migrated_goal.contains("photon: period=4, period=2, inf") and migrated_goal.contains("cost: 30, 20, 10"))
  assert(PARSER.parse(goal).medals == PARSER.parse(migrated_goal).medals)
  assert(PARSER.parse(goal).buildings == PARSER.parse(migrated_goal).buildings)
  assert(PARSER.parse(migrated_goal).buildings[0].period == 8.0)
  var per_tick := "3 x 3; rate_medal: {0.5/tick}; cost_medal: {0}; star_medal: {any: 1/tick}; emitter: {x=0,y=0,E,[electron],rate=0.5/tick};"
  var migrated_tick := PARSER.migrate_rates(per_tick)
  assert(migrated_tick.contains("period=2") and not migrated_tick.contains("rate="))
  assert(PARSER.parse(per_tick).buildings == PARSER.parse(migrated_tick).buildings)
  assert(PARSER.parse(per_tick).medals == PARSER.parse(migrated_tick).medals)
  for period in ["0.5", "1", "2", "3", "4", "1/2"]:
    var authored := migrated_tick.replace("E,[electron],period=2", "E,[electron],period=" + period)
    var data := PARSER.parse(authored)
    assert(not data.has("error"), str(data))
    assert(is_equal_approx(data.buildings[0].period, PARSER._parse_period(period)))
    assert(PARSER.migrate_rates(authored) == authored)
  for invalid_period in ["0", "-1", "inf", "nan", "1/0", "3/tick"]:
    assert(PARSER.parse(per_tick.replace("rate=0.5/tick", "period=" + invalid_period)).has("error"))
  assert(PARSER.parse(per_tick.replace("rate=0.5/tick", "period=2, rate=0.5/tick")).has("error"))
  assert(PARSER.parse(migrated_tick).medals.throughput == 2.0)
  assert(PARSER.parse(migrated_tick).medals.star[0].periods.any == 1.0)
  assert(PARSER.parse(migrated_tick.replace("throughput_medal: {period=2}", "throughput_medal: {2}")).medals.throughput == 2.0)
  for invalid_period in ["0", "-1", "inf", "nan", "1/0"]:
    assert(PARSER.parse(migrated_tick.replace("throughput_medal: {period=2}", "throughput_medal: {period=" + invalid_period + "}")).has("error"))
  assert(PARSER.parse(migrated_tick.replace("star_medal: {any: period=1}", "star_medal: {any: period=0}")).has("error"))
  var game = GAME.instantiate()
  var required := {"any": 2.0}
  assert(game._meets_output(required, {"any": 2}, 4.0))
  assert(game._meets_output(required, {"any": 4}, 4.0))
  assert(not game._meets_output(required, {"any": 1}, 4.0))
  assert(not game._meets_output(required, {}, 4.0))
  assert(not game._meets_output(required, {"any": 2}, 0.0))
  game.free()
  var saved_progress := ConfigFile.new()
  saved_progress.set_value("levels", "test", {"completed": true, "medals": ["rate", "cost", "throughput"]})
  assert(Global._stored_progress(saved_progress, "test").medals == ["throughput", "cost"])
  var invalid := "3 x 3; rate_medal: {1/step};"
  assert(PARSER.migrate_rates(invalid) == invalid)
  assert(PARSER._parse_rate("1/tick") == 1.0 and PARSER._parse_rate("1/4/tick") == 0.25)
  assert(PARSER._parse_rate("1/step") == 0.25 and PARSER._parse_rate("1/s") == 0.25)
  # Exercise the on-disk migration without touching a player's levels.
  var path := "user://rate-migration-test-%d.level" % Time.get_ticks_usec()
  var file := FileAccess.open(path, FileAccess.WRITE)
  assert(file != null)
  file.store_string(legacy)
  file.close()
  var old_backup := FileAccess.open(path + ".pre-tick.bak", FileAccess.WRITE)
  assert(old_backup != null)
  old_backup.store_string("Earlier backup")
  old_backup.close()
  var period_backup := FileAccess.open(path + ".pre-period.bak", FileAccess.WRITE)
  assert(period_backup != null)
  period_backup.store_string("Previous period backup")
  period_backup.close()
  assert(Global.migrate_level_file(path))
  assert(FileAccess.get_file_as_string(path + ".pre-period.bak") == "Previous period backup")
  assert(FileAccess.get_file_as_string(path + ".pre-tick.bak") == "Earlier backup")
  assert(FileAccess.get_file_as_string(path) == upgraded)
  assert(FileAccess.get_file_as_string(path + ".pre-throughput.bak") == legacy)
  assert(not Global.migrate_level_file(path))
  DirAccess.remove_absolute(path)
  DirAccess.remove_absolute(path + ".pre-throughput.bak")
  DirAccess.remove_absolute(path + ".pre-tick.bak")
  DirAccess.remove_absolute(path + ".pre-period.bak")
