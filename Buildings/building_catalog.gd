extends RefCounted

# The game, level parser and editor share this catalog. Register new building
# scenes here; their level declarations remain editable without editor changes.
const SCENES := {
  "emitter": preload("res://Buildings/Emitter/emitter.tscn"),
  "mirror": preload("res://Buildings/Mirror/mirror.tscn"),
  "wall": preload("res://Buildings/Wall/wall.tscn"),
  "detector": preload("res://Buildings/Detector/detector.tscn"),
  "magnet": preload("res://Buildings/MagneticField/magnetic_field.tscn"),
}
const COSTS := {"mirror": 15, "wall": 5, "emitter": 40, "detector": 30, "magnet": 20}

const DIRECTIONS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const ROTATABLE_KINDS := ["emitter", "mirror", "magnet"]
const NEGATIVE_POLARITIES := ["negative", "-", "-1", "n"]
const VALID_POLARITIES := ["positive", "+", "+1", "1", "p"] + NEGATIVE_POLARITIES

static func rotation_lock_flag(kind: String) -> String:
  return "c" if kind == "magnet" else "r"
