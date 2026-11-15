@abstract
class_name Particle
extends Node2D

var speed: int = 250
var charge: int
var colour: Global.ColourCharge
var spin: float
var isAnti: bool
var size: float = 1.0

@export var textures: Array[Texture2D] # [Particle Sprite, Anti-Particle Sprite]
@onready var sprite: Sprite2D = $Sprite2D

var direction: Vector2

func _ready() -> void:
  scale *= size

  sprite.texture = textures[0]

  if isAnti:
    match colour:
      Global.ColourCharge.RED: colour = Global.ColourCharge.ANTIRED
      Global.ColourCharge.GREEN: colour = Global.ColourCharge.ANTIGREEN
      Global.ColourCharge.BLUE: colour = Global.ColourCharge.ANTIBLUE
      _: colour = colour
    
    charge = -charge

    if textures.size() > 1:
      sprite.texture = textures[1]

func _process(delta: float) -> void:
  move(delta)

func move(delta: float) -> void:
  position += direction.normalized() * speed * delta
