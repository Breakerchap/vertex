class_name Particle
extends Node2D

enum ColourCharge { NONE, RED, GREEN, BLUE, ANTIRED, ANTIGREEN, ANTIBLUE }
enum Flavour { UP, DOWN, ELECTRON, PHOTON }

var flavour: Flavour
var speed: int = 250
var charge: int
var colour: ColourCharge
var spin: float
@export var isAnti: bool = false
var size: float = 1.0
@export var textures: Array[Texture2D]
@export var direction: Vector2 = Vector2.RIGHT
@export var collision_radius: float = 33.0

# Magnetic turns retain their progress across fixed simulation steps.
var magnetic_field: Node2D = null
var magnetic_last_field: Node2D = null
var magnetic_remaining: float = 0.0
var magnetic_turn_sign: float = 0.0
@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
  scale *= size
  sprite.texture = textures[0]
  if isAnti:
    match colour:
      ColourCharge.RED: colour = ColourCharge.ANTIRED
      ColourCharge.GREEN: colour = ColourCharge.ANTIGREEN
      ColourCharge.BLUE: colour = ColourCharge.ANTIBLUE
      _: pass
    charge = -charge
    if textures.size() > 1:
      sprite.texture = textures[1]

func advance(delta: float) -> void:
  global_position += direction.normalized() * speed * delta

## Name used by level goals and detectors.
func level_particle_name() -> String:
  match flavour:
    Flavour.PHOTON: return "photon"
    Flavour.ELECTRON: return "positron" if isAnti else "electron"
    Flavour.UP, Flavour.DOWN:
      var name := "up" if flavour == Flavour.UP else "down"
      match colour:
        ColourCharge.RED: name += "_r"
        ColourCharge.GREEN: name += "_g"
        ColourCharge.BLUE: name += "_b"
      return name
  return "unknown"