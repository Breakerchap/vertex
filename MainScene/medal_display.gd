extends RefCounted

const ICONS := {
  "throughput": preload("res://rate_medal.png"),
  "cost": preload("res://cost_medal.png"),
  "star": preload("res://star_medal.png"),
}

static func icon(kind: String, size: float, earned := true) -> TextureRect:
  var badge := TextureRect.new()
  badge.texture = ICONS[kind]
  badge.custom_minimum_size = Vector2.ONE * size
  badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
  badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
  badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  set_earned(badge, kind, earned)
  return badge

static func set_earned(badge: TextureRect, kind: String, earned: bool) -> void:
  badge.modulate.a = 1.0 if earned else 0.32
  badge.tooltip_text = "%s medal (%s)" % [kind.capitalize(), "earned" if earned else "unearned"]
  badge.mouse_filter = Control.MOUSE_FILTER_STOP

static func strip(earned: Array, size: float) -> HBoxContainer:
  var row := HBoxContainer.new()
  for kind in ICONS:
    row.add_child(icon(kind, size, kind in earned))
  return row
