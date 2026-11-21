@tool
extends "res://Buildings/solid_building.gd"

const SPRITES := {
  "gate": [preload("res://Buildings/GridDevices/gate_closed.png"), preload("res://Buildings/GridDevices/gate_open.png")],
  "glass": [preload("res://Buildings/GridDevices/glass.png")],
  "filter": [preload("res://Buildings/GridDevices/filter_red.png"), preload("res://Buildings/GridDevices/filter_green.png"), preload("res://Buildings/GridDevices/filter_blue.png")],
  "rail": [preload("res://Buildings/GridDevices/rail_clockwise.png"), preload("res://Buildings/GridDevices/rail_counterclockwise.png")],
  "edge_wall": [preload("res://Buildings/GridDevices/edge_wall.png")],
  "holder": [preload("res://Buildings/GridDevices/holder.png")],
  "pusher": [preload("res://Buildings/GridDevices/pusher_down.png"), preload("res://Buildings/GridDevices/pusher_up.png")],
}
const FILTER_COLOURS := [Particle.ColourCharge.RED, Particle.ColourCharge.GREEN, Particle.ColourCharge.BLUE]

@export var kind := "gate"
@export var orientation := 0:
  set(value):
    orientation = posmod(value, 8)
    if is_node_ready(): _configure_shape()
@export var filter_colour := 0:
  set(value):
    filter_colour = clampi(value, 0, FILTER_COLOURS.size() - 1)
    queue_redraw()
@export var track := ""
@export var counterclockwise := false:
  set(value):
    counterclockwise = value
    queue_redraw()
@export var starts_open := false

var gate_open := false
var push_up := true
var held_particle: Particle
static var _blank_textures := {}

func _ready() -> void:
  super._ready()
  set_meta("device", kind)
  if kind in ["rail", "edge_wall"]: set_meta("grid_layer", kind)
  _configure_shape()
  if collision_shape.disabled: remove_from_group("particle_blockers")
  reset_device()

func _configure_shape() -> void:
  var shape := RectangleShape2D.new()
  collision_shape.position = Vector2.ZERO
  collision_shape.rotation = 0.0
  shape.size = Vector2.ONE * GRID_SIZE * 0.78
  if kind == "gate":
    collision_shape.rotation = orientation * PI / 4.0
  if kind == "edge_wall":
    var edge_orientation := orientation - orientation % 2
    collision_shape.position = SimulationGrid.VECTORS[edge_orientation] * GRID_SIZE * 0.5
    collision_shape.rotation = edge_orientation * PI / 4.0
    shape.size = Vector2(GRID_SIZE * 0.08, GRID_SIZE)
  collision_shape.shape = shape
  collision_shape.disabled = kind in ["rail", "holder", "pusher"]
  queue_redraw()

func reset_device() -> void:
  gate_open = starts_open
  push_up = true
  held_particle = null
  queue_redraw()

func sweep_for(particle: Particle, from: Vector2, motion: Vector2) -> Dictionary:
  match kind:
    "gate":
      if particle.global_position.is_equal_approx(global_position) or self in particle.passed_gates:
        return {}
    "glass":
      if particle.passes_glass():
        return {}
    "filter":
      if particle.flavour == Particle.Flavour.PHOTON or (particle.is_quark() and particle.colour == FILTER_COLOURS[filter_colour]):
        return {}
  return sweep(from, motion, particle.world_collision_radius())

## Return whether the impact lets the particle carry on.
func hit_gate(particle: Particle, from: Vector2, motion: Vector2) -> bool:
  var axis: Vector2 = SimulationGrid.VECTORS[orientation].normalized()
  if absf(motion.normalized().cross(axis)) > 0.00001 or absf((from - global_position).cross(axis)) > 0.01:
    return false
  var passable := gate_open
  gate_open = not gate_open
  if passable:
    particle.passed_gates.append(self)
  queue_redraw()
  return passable

func next_push() -> Vector2:
  var shift: Vector2 = SimulationGrid.VECTORS[posmod(orientation + (-2 if push_up else 2), 8)]
  push_up = not push_up
  queue_redraw()
  return shift * GRID_SIZE

func _draw() -> void:
  var variants: Array = SPRITES[kind]
  var variant := 0
  var label := ""
  var tint := Color("8cb9d6")
  match kind:
    "gate":
      variant = int(gate_open)
      label = "Open" if gate_open else "Closed"
    "filter":
      variant = filter_colour
      tint = Particle.COLOUR_TINTS[FILTER_COLOURS[variant]]
      label = "Filter"
    "glass": label = "Glass"
    "rail":
      variant = int(counterclockwise)
      label = "CCW" if counterclockwise else "CW"
    "holder": label = "Holder"
    "pusher":
      variant = int(not push_up)
      label = "Push ↑" if push_up else "Push ↓"
  var texture: Texture2D = variants[variant]
  var rect := Rect2(-Vector2.ONE * GRID_SIZE * 0.5, Vector2.ONE * GRID_SIZE)
  if kind == "edge_wall":
    draw_set_transform(collision_shape.position, collision_shape.rotation)
    # The square texture already contains the narrow wall and its transparent padding.
    draw_texture_rect(texture, rect, false)
    return
  var path := texture.resource_path
  if not _blank_textures.has(path):
    _blank_textures[path] = texture.get_image().is_invisible()
  if kind in ["gate", "pusher"]:
    draw_set_transform(Vector2.ZERO, orientation * PI / 4.0)
  draw_texture_rect(texture, rect, false)
  if not _blank_textures[path]: return
  if kind == "rail":
    draw_rect(rect.grow(-6.0), tint, false, 3.0)
    draw_string(ThemeDB.fallback_font, Vector2(-44.0, -28.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tint)
  else:
    draw_rect(rect.grow(-8.0), Color(tint, 0.18))
    draw_rect(rect.grow(-8.0), tint, false, 2.0)
    var font := ThemeDB.fallback_font
    var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
    draw_string(font, Vector2(-width * 0.5, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, tint)
