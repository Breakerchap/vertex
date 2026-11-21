extends RefCounted

const DEVICE = preload("res://Buildings/GridDevices/grid_device.gd")
const SCENES := {
  "emitter": preload("res://Buildings/Emitter/emitter.tscn"),
  "reflector": preload("res://Buildings/Reflector/reflector.tscn"),
  "wall": preload("res://Buildings/Wall/wall.tscn"),
  "detector": preload("res://Buildings/Detector/detector.tscn"),
  "magnet": preload("res://Buildings/MagneticField/magnetic_field.tscn"),
  "gate": preload("res://Buildings/GridDevices/gate.tscn"),
  "glass": preload("res://Buildings/GridDevices/glass.tscn"),
  "filter": preload("res://Buildings/GridDevices/filter.tscn"),
  "edge_wall": preload("res://Buildings/GridDevices/edge_wall.tscn"),
  "holder": preload("res://Buildings/GridDevices/holder.tscn"),
  "pusher": preload("res://Buildings/GridDevices/pusher.tscn"),
}
const COSTS := {"reflector": 15, "wall": 5, "emitter": 40, "detector": 30, "magnet": 20,
  "gate": 15, "glass": 10, "filter": 10, "edge_wall": 5, "holder": 15, "pusher": 15}

const DIRECTIONS := SimulationGrid.DIRECTIONS
const CARDINALS := ["E", "S", "W", "N"]
const FACING_KINDS := ["emitter", "reflector", "gate", "pusher"]
const ROTATABLE_KINDS := FACING_KINDS + ["magnet", "edge_wall", "filter"]
const NEGATIVE_POLARITIES := ["negative", "-", "-1", "n"]
const VALID_POLARITIES := ["positive", "+", "+1", "1", "p"] + NEGATIVE_POLARITIES
const FILTER_COLOURS := ["red", "green", "blue"]

static func default_facing(kind: String) -> String:
  return "N" if kind == "pusher" else "E"

static func rotation_lock_flag(kind: String) -> String:
  return "c" if kind == "magnet" else "r"

static func next_orientation(orientation: int, turn: int, rotation_steps: int) -> int:
  if rotation_steps == 4:
    return posmod(orientation + turn * (1 if orientation % 2 else 2), DIRECTIONS.size())
  return posmod(orientation + turn, DIRECTIONS.size())

static func occupancy_key(kind: String, cell: Vector2i, facing := "E") -> Vector3i:
  match kind:
    "rail": return Vector3i(cell.x, cell.y, 1)
    "edge_wall":
      match facing:
        "W": return Vector3i(cell.x - 1, cell.y, 2)
        "N": return Vector3i(cell.x, cell.y + 1, 3)
        "S": return Vector3i(cell.x, cell.y, 3)
        _: return Vector3i(cell.x, cell.y, 2)
    _: return Vector3i(cell.x, cell.y, 0)
