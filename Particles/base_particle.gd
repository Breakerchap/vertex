class_name Particle
extends Node2D

enum ColourCharge { NONE, RED, GREEN, BLUE, ANTIRED, ANTIGREEN, ANTIBLUE }
enum Flavour { UP, DOWN, ELECTRON, PHOTON, PION_PLUS, PION_MINUS, PION_ZERO, PROTON, NEUTRON, DELTA_MINUS, DELTA_PLUS, MUON, NEUTRINO, NUCLEUS }

const COLOUR_TINTS := {
  ColourCharge.RED: Color(1.0, 0.35, 0.35),
  ColourCharge.GREEN: Color(0.35, 1.0, 0.45),
  ColourCharge.BLUE: Color(0.4, 0.55, 1.0),
}

var flavour: Flavour
var charge: int
var colour: ColourCharge
@export var isAnti := false
## Grid cells travelled per grid tick.
@export var speed: float = 1.0
@export var textures: Array[Texture2D]
## Bounces and perpendicular reaction products can travel between grid headings.
var free_flight := false
var flight_cell := Vector2.ZERO
@export var direction := Vector2.RIGHT:
  set(value):
    direction = value.normalized() if free_flight else SimulationGrid.heading(value)
var size := 1.0
## Original quarks, stored as (flavour, colour).
var constituents: Array[Vector2i] = []
var separating_from: Array[Particle] = []

var mass: float:
  get:
    if flavour in [Flavour.PHOTON, Flavour.NEUTRINO]: return 0.0
    if flavour == Flavour.ELECTRON: return 1.0
    if is_quark() or flavour == Flavour.MUON: return 2.0
    if is_pion(): return 3.0
    if flavour in [Flavour.PROTON, Flavour.NEUTRON, Flavour.DELTA_MINUS, Flavour.DELTA_PLUS]: return 4.0
    return 5.0

# The node stays at a cell centre. The sprite and hitbox travel together.
var progress := 0.0
# During a magnetic turn, progress runs from the entry edge to the exit edge.
var magnetic_exit := Vector2.ZERO
var glass_wait := 0.0
var held_by: Node2D
var source_building: Node2D
var passed_gates: Array[Node] = []
var placeholder_label := ""
static var _blank_textures := {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D

func _ready() -> void:
  scale *= size
  if isAnti:
    match colour:
      ColourCharge.RED: colour = ColourCharge.ANTIRED
      ColourCharge.GREEN: colour = ColourCharge.ANTIGREEN
      ColourCharge.BLUE: colour = ColourCharge.ANTIBLUE
    charge = -charge
  if not textures.is_empty():
    sprite.texture = textures[1] if isAnti and textures.size() > 1 else textures[0]
  var shape := CircleShape2D.new()
  if sprite.texture != null:
    var diameter := sprite.texture.get_size() * sprite.scale.abs()
    shape.radius = minf(diameter.x, diameter.y) * 0.5
    if texture_is_blank(sprite.texture):
      placeholder_label = {
        Flavour.PHOTON: "γ", Flavour.UP: "u", Flavour.DOWN: "d", Flavour.PION_PLUS: "π⁺",
        Flavour.PION_MINUS: "π⁻", Flavour.PION_ZERO: "π⁰", Flavour.PROTON: "p",
        Flavour.NEUTRON: "n", Flavour.DELTA_MINUS: "Δ⁻", Flavour.DELTA_PLUS: "Δ⁺",
      }.get(flavour, "")
  $Area2D/CollisionShape2D.shape = shape
  if free_flight:
    flight_cell = SimulationGrid.center(global_position)
  else:
    global_position = SimulationGrid.center(global_position)
  update_motion_offset()

static func texture_is_blank(texture: Texture2D) -> bool:
  var path := texture.resource_path
  if path.is_empty(): return texture.get_image().is_invisible()
  if not _blank_textures.has(path):
    _blank_textures[path] = texture.get_image().is_invisible()
  return _blank_textures[path]

func travel_vector() -> Vector2:
  if magnetic_exit.is_zero_approx():
    return direction * SimulationGrid.CELL
  return (direction + magnetic_exit) * (SimulationGrid.CELL * 0.5)

func motion_position() -> Vector2:
  var origin := global_position
  if not magnetic_exit.is_zero_approx():
    origin -= direction * (SimulationGrid.CELL * 0.5)
  return origin + travel_vector() * progress

func update_motion_offset() -> void:
  sprite.position = to_local(motion_position())
  area.position = sprite.position
  if not placeholder_label.is_empty(): queue_redraw()

func _draw() -> void:
  if placeholder_label.is_empty(): return
  var at := sprite.position
  var tint: Color = COLOUR_TINTS.get(colour, Color("b9dbef"))
  var radius := world_collision_radius() / absf(global_scale.x)
  draw_circle(at, radius, Color(tint, 0.28))
  draw_arc(at, radius, 0.0, TAU, 32, tint, 2.0, true)
  var font := ThemeDB.fallback_font
  var width := font.get_string_size(placeholder_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
  draw_string(font, at + Vector2(-width * 0.5, 11.0), placeholder_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, tint)

func world_collision_radius() -> float:
  var shape := $Area2D/CollisionShape2D.shape as CircleShape2D
  return shape.radius * absf(global_scale.x)

func mass_speed() -> float:
  if mass == 0.0: return 1.5
  if mass >= 4.0: return 0.5
  return 1.0

func is_quark() -> bool:
  return flavour == Flavour.UP or flavour == Flavour.DOWN

func is_pion() -> bool:
  return flavour in [Flavour.PION_PLUS, Flavour.PION_MINUS, Flavour.PION_ZERO]

func passes_glass() -> bool:
  return flavour in [Flavour.ELECTRON, Flavour.MUON, Flavour.NEUTRINO, Flavour.PHOTON]

## Name used by level goals and detectors.
func level_particle_name() -> String:
  match flavour:
    Flavour.ELECTRON: return "positron" if isAnti else "electron"
    Flavour.MUON: return "anti_muon" if isAnti else "muon"
    Flavour.NEUTRINO: return "anti_neutrino" if isAnti else "neutrino"
    Flavour.PHOTON: return "photon"
    Flavour.UP, Flavour.DOWN:
      var name := "up" if flavour == Flavour.UP else "down"
      match colour:
        ColourCharge.RED: name += "_r"
        ColourCharge.GREEN: name += "_g"
        ColourCharge.BLUE: name += "_b"
      return name
    Flavour.PION_PLUS: return "pion_plus"
    Flavour.PION_MINUS: return "pion_minus"
    Flavour.PION_ZERO: return "pion_zero"
    Flavour.PROTON: return "proton"
    Flavour.NEUTRON: return "neutron"
    Flavour.DELTA_MINUS: return "delta_minus"
    Flavour.DELTA_PLUS: return "delta_plus"
    Flavour.NUCLEUS: return "nucleus"
  return "unknown"
