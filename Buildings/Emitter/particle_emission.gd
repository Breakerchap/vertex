class_name ParticleEmission
extends Resource

## One entry in an emitter's ordered sequence. Direction is relative to the emitter.
@export var flavour: Global.Flavour = Global.Flavour.ELECTRON
@export var is_anti: bool = false
@export var direction: Vector2 = Vector2.RIGHT

@export var colour: Particle.ColourCharge = Particle.ColourCharge.NONE
