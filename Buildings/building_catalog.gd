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
const COSTS := {"mirror": 10, "wall": 5, "emitter": 40, "detector": 30, "magnet": 20}
