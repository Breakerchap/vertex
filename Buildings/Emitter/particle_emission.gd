class_name ParticleEmission
extends Resource

## One entry in an emitter's ordered sequence. Direction is relative to the emitter.
@export var flavour: Particle.Flavour = Particle.Flavour.ELECTRON
@export var is_anti: bool = false
@export var direction: Vector2 = Vector2.RIGHT

@export var colour: Particle.ColourCharge = Particle.ColourCharge.NONE
