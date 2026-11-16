extends CanvasLayer

const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]

@onready var simulation: ParticleSimulation = get_parent() as ParticleSimulation
@onready var play_pause: Button = $Panel/Margin/Controls/PlayPause
@onready var step_button: Button = $Panel/Margin/Controls/Step
@onready var slower: Button = $Panel/Margin/Controls/Slower
@onready var speed_label: Label = $Panel/Margin/Controls/Speed
@onready var faster: Button = $Panel/Margin/Controls/Faster
@onready var reset_speed: Button = $Panel/Margin/Controls/ResetSpeed

func _ready() -> void:
  play_pause.pressed.connect(_toggle_running)
  step_button.pressed.connect(_step_once)
  slower.pressed.connect(_change_speed.bind(-1))
  faster.pressed.connect(_change_speed.bind(1))
  reset_speed.pressed.connect(_reset_speed)
  _update_controls()

func _process(_delta: float) -> void:
  _update_controls()

func _toggle_running() -> void:
  if simulation.has_method("begin_run") and simulation.completed:
    return
  if simulation.has_method("begin_run") and not simulation.simulating:
    simulation.begin_run()
  simulation.running = not simulation.running
  _update_controls()

func _step_once() -> void:
  if simulation.has_method("begin_run") and simulation.completed:
    return
  if simulation.has_method("begin_run") and not simulation.simulating:
    simulation.begin_run()
  simulation.step_once()
  _update_controls()

func _change_speed(direction: int) -> void:
  var current := simulation.simulation_speed
  if direction < 0:
    for i in range(SPEEDS.size() - 1, -1, -1):
      if SPEEDS[i] < current - 0.0001:
        simulation.simulation_speed = SPEEDS[i]
        break
  else:
    for speed in SPEEDS:
      if speed > current + 0.0001:
        simulation.simulation_speed = speed
        break
  _update_controls()

func _reset_speed() -> void:
  simulation.simulation_speed = 1.0
  _update_controls()

func _update_controls() -> void:
  play_pause.text = "Pause" if simulation.running else "Play"
  speed_label.text = "%s×" % str(simulation.simulation_speed)
  slower.disabled = simulation.simulation_speed <= SPEEDS.front()
  faster.disabled = simulation.simulation_speed >= SPEEDS.back()
  reset_speed.disabled = is_equal_approx(simulation.simulation_speed, 1.0)
