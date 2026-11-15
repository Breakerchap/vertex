extends CheckButton

@onready var simulation := get_node("/root/main") as ParticleSimulation
simulation.step_simulation(1.0 / 60.0)

