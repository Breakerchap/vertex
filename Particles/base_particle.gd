class_name Particle
extends Node2D

enum ColourCharge {
  NONE,
  RED,
  GREEN,
  BLUE,
  ANTIRED,
  ANTIGREEN,
  ANTIBLUE
}

enum Flavour {
  UP,
  DOWN,
  ELECTRON,
  PHOTON
}

var flavour: Flavour
var speed: int = 250
var charge: int
var colour: ColourCharge
var spin: float
@export var isAnti: bool = false
var size: float = 1.0

@export var textures: Array[Texture2D] # [Particle Sprite, Anti-Particle Sprite]
@onready var sprite: Sprite2D = $Sprite2D

@export var direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
  scale *= size

  sprite.texture = textures[0]

  if isAnti:
    match colour:
      ColourCharge.RED: colour = ColourCharge.ANTIRED
      ColourCharge.GREEN: colour = ColourCharge.ANTIGREEN
      ColourCharge.BLUE: colour = ColourCharge.ANTIBLUE
      _: colour = colour
    
    charge = -charge

    if textures.size() > 1:
      sprite.texture = textures[1]

func _physics_process(delta: float) -> void:
  move(delta)

func snap_to_8(directionA: Vector2) -> Vector2:
  if directionA.is_zero_approx():
    return Vector2.ZERO

  var angle: float = snappedf(directionA.angle(), PI / 4.0)
  return Vector2.RIGHT.rotated(angle)

# Anti-particle annihilation
func _on_area_2d_area_entered(area: Area2D) -> void:
  print("Hitbox entered by area: ", area)
  print("Self: ", self)
  print("Self direction: ", direction)
  var otherParticle: Particle = area.get_parent() as Particle
  if otherParticle == null or otherParticle.is_queued_for_deletion():
    return

  if isAnti == otherParticle.isAnti or flavour != otherParticle.flavour:
    return

  # Spawn photons semi-realistically
  var collision_pos: Vector2 = (
    global_position + otherParticle.global_position
  ) / 2.0

  var incoming: Vector2 = direction - otherParticle.direction

  if incoming.is_zero_approx():
    incoming = Vector2.RIGHT

  # Snap to one of 8 compass directions
  var angle: float = snappedf(incoming.angle(), PI / 4.0)
  var snapped_direction: Vector2 = Vector2.RIGHT.rotated(angle)

  # Two opposite, perpendicular photon directions
  var photon_direction: Vector2 = snapped_direction.orthogonal()

  spawn_photon(collision_pos, photon_direction)
  spawn_photon(collision_pos, -photon_direction)

  otherParticle.queue_free()
  queue_free()


func spawn_photon(pos: Vector2, dir: Vector2) -> void:
  var photon: Particle = load("res://Particles/Photon/photon.tscn").instantiate()

  photon.direction = dir
  get_tree().current_scene.add_child(photon)
  photon.global_position = pos


func move(delta: float) -> void:
  position += direction.normalized() * speed * delta