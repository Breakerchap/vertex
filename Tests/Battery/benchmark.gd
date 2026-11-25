extends Node
## Opt-in harness. The normal main scene and normal game defaults are unchanged.

const GAME := preload("res://MainScene/level_game.tscn")
const PARSER := preload("res://Levels/level_parser.gd")
const MODES := ["baseline", "fps30", "forecast64", "combined"]

var game
var menu: PanelContainer
var active := true
var variant := "baseline"
var seconds := 180.0
var warmup := 15.0
var cli := false
var lost_focus := false
var battery
var history: Array[String] = []

func _ready() -> void:
  for arg in OS.get_cmdline_user_args():
    var fields := arg.split("=", true, 1)
    if fields.size() != 2: continue
    match fields[0]:
      "variant":
        variant = fields[1]
        cli = true
      "scenario": active = fields[1] == "active"
      "seconds": seconds = maxf(1.0, float(fields[1]))
      "warmup": warmup = maxf(0.0, float(fields[1]))
  if cli:
    if variant not in MODES:
      push_error("Unknown battery benchmark variant: " + variant)
      get_tree().quit(2)
      return
    _run.call_deferred()
    return
  DisplayServer.screen_set_keep_on(true)
  var android_runtime = Engine.get_singleton("AndroidRuntime")
  if android_runtime:
    battery = android_runtime.getApplicationContext().getSystemService("batterymanager")
  var layer := CanvasLayer.new()
  layer.layer = 20
  add_child(layer)
  menu = PanelContainer.new()
  menu.position = Vector2(24, 24)
  layer.add_child(menu)
  _show_choices("Unplug first. Each run takes 3m 15s.\nKeep the app open without touching the board.")

func _show_choices(message: String) -> void:
  for child in menu.get_children():
    menu.remove_child(child)
    child.queue_free()
  var controls := VBoxContainer.new()
  menu.add_child(controls)
  var info := Label.new()
  info.text = message
  controls.add_child(info)
  if not history.is_empty():
    var previous := Label.new()
    previous.text = "\n".join(history.slice(-6))
    controls.add_child(previous)
  var load_toggle := CheckButton.new()
  load_toggle.text = "Run particle simulation"
  load_toggle.button_pressed = active
  load_toggle.toggled.connect(func(value: bool): active = value)
  controls.add_child(load_toggle)
  for mode in MODES:
    var button := Button.new()
    button.text = mode
    button.custom_minimum_size.y = 38
    button.pressed.connect(func():
      variant = mode
      _run.call_deferred()
    )
    controls.add_child(button)

func _fixture() -> Dictionary:
  var source := "title: Battery test;\n18 x 14;\nrate_medal: {1/step};\ncost_medal: {0};\nstar_medal: {any: 7/step};\n"
  for y in range(1, 14, 2):
    source += "emitter: {x=1,y=%d,E,[photon],rate=1/step,fixed=rp}\n" % y
    source += "detector: {x=16,y=%d,[photon],fixed=rp}\n" % y
  return PARSER.parse(source)

func _run() -> void:
  if is_instance_valid(game): return
  if is_instance_valid(menu): menu.hide()
  lost_focus = false
  Engine.max_fps = 30 if variant in ["fps30", "combined"] else (60 if cli else 0)
  game = GAME.instantiate()
  game.editor_playtest = true
  game.level_override = _fixture()
  if game.level_override.has("error"):
    push_error(str(game.level_override.error))
    get_tree().quit(3)
    return
  game.forecast_refresh_steps = 64.0 if variant in ["forecast64", "combined"] else 16.0
  add_child(game)
  if active:
    game.begin_run()
    game.set_playback_speed(1.0)
    game.running = true
  await get_tree().create_timer(warmup, true, false, true).timeout
  if active and not game.completed:
    push_error("Workload did not reach a detector during warm-up")
    get_tree().quit(4)
    return
  var charge_at_start := _battery_counter(1)
  var energy_at_start := _battery_counter(5)
  var charging: bool = battery != null and battery.isCharging()
  var frames_at_start := Engine.get_process_frames()
  var start := Time.get_ticks_msec()
  var elapsed_at_start: float = game.elapsed
  var detected_at_start: int = game.total_counts.get("any", 0)
  var next_forecast: float = game.next_forecast_at
  var refreshes := 0
  print("VERTEX_BENCH_START ", variant, " ", "active" if active else "idle")
  while Time.get_ticks_msec() - start < seconds * 1000.0:
    await get_tree().process_frame
    if game.next_forecast_at != next_forecast:
      next_forecast = game.next_forecast_at
      refreshes += 1
  var duration := float(Time.get_ticks_msec() - start) / 1000.0
  var charge_at_end := _battery_counter(1)
  var energy_at_end := _battery_counter(5)
  charging = charging or (battery != null and battery.isCharging())
  var measurement := {
    "variant": variant, "scenario": "active" if active else "idle",
    "seconds": duration, "fps": (Engine.get_process_frames() - frames_at_start) / duration,
    "game_steps": game.elapsed - elapsed_at_start,
    "detections": int(game.total_counts.get("any", 0)) - detected_at_start,
    "forecast_refreshes": refreshes, "lost_focus": lost_focus,
  }
  var status := "battery reading unavailable or too coarse"
  if lost_focus or charging:
    status = "invalid run: backgrounded or charging"
  else:
    if charge_at_end > 0 and charge_at_start > charge_at_end:
      measurement["battery_ua_h"] = charge_at_start - charge_at_end
      measurement["mean_drain_ma"] = (charge_at_start - charge_at_end) * 3.6 / duration
      status = "%.0f mA whole-phone draw" % measurement.mean_drain_ma
    if energy_at_end > 0 and energy_at_start > energy_at_end:
      measurement["mean_drain_mw"] = (energy_at_start - energy_at_end) * 0.0036 / duration
      status += "; %.0f mW" % measurement.mean_drain_mw
  measurement["charging"] = charging
  print("VERTEX_BENCH_END ", JSON.stringify(measurement))
  if cli:
    get_tree().quit(5 if lost_focus else 0)
    return
  remove_child(game)
  game.queue_free()
  game = null
  Engine.max_fps = 30
  history.append("%s %s: %s | %.0f FPS, %d forecasts" % [
    variant, measurement.scenario, status, measurement.fps, refreshes])
  _show_choices("Unplug first. Each run takes 3m 15s.\nKeep the app open without touching the board.")
  menu.show()

# Android BatteryManager charge (1, µAh) and energy (5, nWh). Unsupported values are negative.
func _battery_counter(property: int) -> int:
  return int(battery.getLongProperty(property)) if battery != null else -1

func _notification(what: int) -> void:
  if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
    if is_instance_valid(game) and not cli:
      lost_focus = true
