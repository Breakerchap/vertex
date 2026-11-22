class_name LevelParser
extends RefCounted

const CATALOG = preload("res://Buildings/building_catalog.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")
const PARTICLE_TOKEN := "[a-zA-Z_][a-zA-Z_0-9]*|[(),]"

static func mask_comments(source: String) -> String:
  var lines := PackedStringArray()
  for line in source.split("\n"):
    var comment := line.find("#")
    lines.append(line if comment < 0 else line.left(comment) + " ".repeat(line.length() - comment))
  return "\n".join(lines)

static func find_metadata(text: String) -> Array[RegExMatch]:
  var metadata := RegEx.new()
  metadata.compile("(?im)^\\h*(title|hint|rotation)\\h*:\\h*([^;\\n]+)\\h*;")
  return metadata.search_all(text)

static func _without_metadata(text: String) -> String:
  for item in find_metadata(text):
    text = text.left(item.get_start()) + " ".repeat(item.get_end() - item.get_start()) + text.substr(item.get_end())
  return text

static func find_dimensions(text: String) -> RegExMatch:
  var dimensions := RegEx.new()
  dimensions.compile("(?i)(\\d+)\\s*x\\s*(\\d+)")
  return dimensions.search(_without_metadata(text))

static func find_blocks(text: String) -> Array[RegExMatch]:
  var blocks := RegEx.new()
  var names: Array = CATALOG.SCENES.keys()
  names.append_array(["goal", "inventory", "no_build", "magnetic_field", "mirror"])
  blocks.compile("(?is)\\b(" + "|".join(names) + ")\\s*:\\s*\\{([^}]*)\\}[ \\t]*;?")
  return blocks.search_all(_without_metadata(text))

static func parse(source: String) -> Dictionary:
  var text := mask_comments(source)
  var size_match := find_dimensions(text)
  if size_match == null:
    return {"error": "Missing grid size (for example 15 x 7)."}
  var data := {"width": int(size_match.get_string(1)), "height": int(size_match.get_string(2)), "goals": [], "goal_targets": [], "buildings": [], "inventory": {}, "no_build_areas": [], "title": "", "hint": "", "rotation_steps": 8, "legacy_rates": false}
  if data.width <= 0 or data.height <= 0:
    return {"error": "Grid dimensions must be positive."}
  for item in find_metadata(text):
    var key := item.get_string(1).to_lower()
    var value := item.get_string(2).strip_edges().trim_prefix('"').trim_suffix('"')
    if key == "rotation":
      if value not in ["4", "8"]: return {"error": "Rotation must be 4 or 8 directions."}
      data.rotation_steps = int(value)
    else:
      data[key] = value
  var blocks := find_blocks(text)
  var legacy_suffix := RegEx.new()
  legacy_suffix.compile("(?i)/s\\b")
  for block in blocks:
    if block.get_string(1).to_lower() == "goal" and legacy_suffix.search(block.get_string(2)) != null:
      data.legacy_rates = true
  for block in blocks:
    var kind := building_kind(block.get_string(1))
    var body := block.get_string(2)
    match kind:
      "goal":
        var result := _parse_goal(body)
        if result.has("error"):
          return result
        data.goals.append(result.goal)
        data.goal_targets.append(result.targets)
      "inventory":
        var result := _parse_inventory(body, data.inventory)
        if result.has("error"):
          return result
      "no_build":
        var result := _parse_no_build(body, data.width, data.height)
        if result.has("error"):
          return result
        data.no_build_areas.append(result.area)
      _:
        var result := parse_building(kind, body, data.width, data.height, data.legacy_rates)
        if result.has("error"):
          return result
        data.buildings.append_array(result.entries)
  if data.goals.is_empty():
    return {"error": "The level needs at least one goal."}
  var occupied := {}
  for building in data.buildings:
    var cell := Vector2i(building.x, building.y)
    var key := CATALOG.occupancy_key(building.kind, cell, building.facing)
    if occupied.has(key):
      return {"error": "Overlapping buildings at (%d, %d)." % [cell.x, cell.y]}
    occupied[key] = true
  return data

static func building_kind(name: String) -> String:
  var kind := name.to_lower()
  match kind:
    "magnetic_field": return "magnet"
    "mirror": return "reflector"
  return kind

static func _parse_goal(body: String) -> Dictionary:
  var goal := {}
  var targets := {}
  for clause in body.split(";", false):
    var parts := clause.split(":", true, 1)
    if parts.size() != 2:
      return {"error": "Invalid goal: " + clause}
    var values := []
    for value in parts[1].split(",", false):
      var token := value.strip_edges().to_lower()
      if token == "inf":
        values.append(INF)
      elif _parse_rate(token) >= 0.0 and (parts[0].strip_edges().to_lower() != "cost" or token.is_valid_float()):
        values.append(_parse_rate(token))
      else:
        return {"error": "Invalid goal value: " + token}
    if values.size() != 3:
      return {"error": "Each goal needs three values (one per star)."}
    var target := parts[0].strip_edges()
    if target.begins_with("[") and target.ends_with("]"):
      var expression := particle_expression(target.substr(1, target.length() - 2))
      if expression.has("error"):
        return expression
      if expression.accepted.is_empty():
        return {"error": "Goal expression matches no particle: " + target}
      var key := "[" + ",".join(expression.accepted) + "]"
      goal[key] = values
      targets[key] = PARTICLES.current_expression(target)
    else:
      target = PARTICLES.current_name(target.to_lower())
      if target != "cost" and not _valid_particle(target):
        return {"error": "Unknown goal target: " + target}
      goal[target] = values
  if goal.is_empty():
    return {"error": "Empty goal."}
  return {"goal": goal, "targets": targets}

static func _parse_inventory(body: String, inventory: Dictionary) -> Dictionary:
  for item in body.split(",", false):
    var pair := item.split("=", true, 1)
    if pair.size() != 2 or not pair[1].strip_edges().is_valid_int() or int(pair[1]) < 0:
      return {"error": "Invalid inventory entry: " + item}
    var name := building_kind(pair[0].strip_edges())
    if name == "rail": continue
    if not CATALOG.SCENES.has(name):
      return {"error": "Unknown inventory item: " + name}
    inventory[name] = int(pair[1])
  return {}

static func _parse_no_build(body: String, width: int, height: int) -> Dictionary:
  var axes := {}
  for item in body.split(",", false):
    var pair := item.split("=", true, 1)
    var axis := pair[0].strip_edges().to_lower()
    if pair.size() != 2 or axis not in ["x", "y"] or axes.has(axis):
      return {"error": "A no-build area needs one x and one y coordinate or range."}
    var endpoints := _range_endpoints(pair[1].strip_edges())
    if endpoints.is_empty():
      return {"error": "Invalid %s coordinate or range for a no-build area." % axis}
    endpoints.sort()
    axes[axis] = endpoints
  if axes.size() != 2:
    return {"error": "A no-build area needs one x and one y coordinate or range."}
  if axes.x[0] < 0 or axes.x[1] >= width or axes.y[0] < 0 or axes.y[1] >= height:
    return {"error": "A no-build area extends outside the grid."}
  var first := Vector2i(axes.x[0], axes.y[0])
  var last := Vector2i(axes.x[1], axes.y[1])
  return {"area": Rect2i(first, last - first + Vector2i.ONE)}

## Bare values and /step are per step. /s is supported for existing levels.
static func _parse_rate(value: String, legacy_bare := false) -> float:
  var token := value.strip_edges().to_lower()
  var legacy := token.ends_with("/s") or (legacy_bare and not token.ends_with("/step"))
  token = token.trim_suffix("/step").trim_suffix("/s")
  var parts := token.split("/")
  if parts.is_empty() or parts.size() > 2 or not parts[0].is_valid_float(): return -1.0
  var rate := float(parts[0])
  if parts.size() == 2:
    if not parts[1].is_valid_float() or float(parts[1]) <= 0.0: return -1.0
    rate /= float(parts[1])
  if not is_finite(rate): return -1.0
  # Legacy authored rates used a 60 Hz simulation.
  return rate * SimulationGrid.TICKS_PER_STEP * SimulationGrid.GRID_TICKS_PER_STEP / 60.0 if legacy else rate

static func parse_building(kind: String, body: String, width: int, height: int, legacy_rates := false) -> Dictionary:
  var entry := {"kind": kind, "facing": CATALOG.default_facing(kind), "fixed": "", "rate": 1.0, "particles": []}
  var list_regex := RegEx.new()
  list_regex.compile("\\[([^]]*)\\]")
  var list_match := list_regex.search(body)
  if list_match:
    if kind == "detector":
      var expression := particle_expression(list_match.get_string(1))
      if expression.has("error"):
        return expression
      entry.particles = expression.particles
      entry.accepted = expression.accepted
      entry.particle_expression = PARTICLES.current_expression(list_match.get_string(1).strip_edges())
    else:
      for value in list_match.get_string(1).split(",", false):
        entry.particles.append(PARTICLES.emission_name(value.strip_edges().to_lower()))
    body = body.substr(0, list_match.get_start()) + body.substr(list_match.get_end())
  for part in body.split(",", false):
    var token := part.strip_edges()
    if token.is_empty():
      continue
    var pair := token.split("=", true, 1)
    if pair.size() == 2:
      var key := pair[0].strip_edges().to_lower()
      var value := pair[1].strip_edges().to_lower()
      entry[key] = value.to_upper() if key == "facing" else value
    elif kind == "magnet" and token in ["+", "-", "+1", "-1"]:
      entry.polarity = token
    else:
      entry.facing = token.to_upper()
  if kind == "magnet" and str(entry.get("polarity", "positive")) not in CATALOG.VALID_POLARITIES:
    return {"error": "Invalid magnetic polarity: " + str(entry.polarity)}
  if not entry.has("x") or not entry.has("y"):
    return {"error": kind + " needs x and y coordinates."}
  if entry.facing not in CATALOG.DIRECTIONS:
    return {"error": "Invalid direction: " + entry.facing}
  if entry.has("rotation"):
    if entry.rotation not in ["4", "8"]:
      return {"error": "Building rotation must be 4 or 8 directions."}
    entry.rotation = int(entry.rotation)
  if kind == "edge_wall" and entry.facing not in CATALOG.CARDINALS:
    return {"error": "An edge wall must face E, S, W or N."}
  if kind == "filter" and entry.get("colour", "red") not in CATALOG.FILTER_COLOURS:
    return {"error": "A filter colour must be red, green or blue."}
  if kind == "gate" and entry.get("open", "false") not in ["true", "false"]:
    return {"error": "Gate open must be true or false."}
  entry.rate = _parse_rate(str(entry.rate), legacy_rates and kind == "emitter")
  if entry.rate <= 0.0:
    return {"error": "Emitter rate must be positive."}
  for name in entry.particles:
    if not _valid_particle(name):
      return {"error": "Unknown particle: " + name}
  var xs := _range_values(str(entry.x))
  var ys := _range_values(str(entry.y))
  if xs.is_empty() or ys.is_empty():
    return {"error": "Invalid coordinate or range for " + kind}
  var entries: Array[Dictionary] = []
  for x in xs:
    for y in ys:
      if x < 0 or y < 0 or x >= width or y >= height:
        return {"error": "%s coordinate (%d, %d) is outside the grid." % [kind, x, y]}
      var placed: Dictionary = entry.duplicate(true)
      placed.x = x
      placed.y = y
      entries.append(placed)
  return {"entries": entries}

static func _range_endpoints(value: String) -> Array[int]:
  var parts := value.split("..")
  if parts.size() > 2 or not parts[0].strip_edges().is_valid_int() or (parts.size() == 2 and not parts[1].strip_edges().is_valid_int()):
    return []
  var first := int(parts[0])
  return [first, int(parts[1]) if parts.size() == 2 else first]

static func _range_values(value: String) -> Array[int]:
  var result: Array[int] = []
  var endpoints := _range_endpoints(value)
  if endpoints.is_empty(): return result
  var first := endpoints[0]
  var last := endpoints[1]
  var direction := 1 if last >= first else -1
  for number in range(first, last + direction, direction):
    result.append(number)
  return result

static func _valid_particle(name: String) -> bool:
  return PARTICLES.is_selector(name)

# Compile a particle expression into its matching particle names. AND binds
# more tightly than OR; commas retain the original list's OR behavior.
static func particle_expression(source: String) -> Dictionary:
  var lexer := RegEx.new()
  lexer.compile("\\s*(" + PARTICLE_TOKEN + ")")
  var output: Array[String] = []
  var operators: Array[String] = []
  var particles: Array[String] = []
  var pos := 0
  var expect_value := true
  while pos < source.length():
    if source.substr(pos).strip_edges().is_empty(): break
    var match_token := lexer.search(source, pos)
    if match_token == null or match_token.get_start() != pos:
      return {"error": "Invalid particle expression: " + source}
    pos = match_token.get_end()
    var token := PARTICLES.current_name(match_token.get_string(1).to_lower())
    if token == "(":
      if not expect_value: return {"error": "Add AND or OR before the opening bracket."}
      operators.append(token)
    elif token == ")":
      if expect_value: return {"error": "Add a particle before the closing bracket."}
      while not operators.is_empty() and operators.back() != "(":
        output.append(operators.pop_back())
      if operators.is_empty(): return {"error": "Unmatched closing bracket in particle expression."}
      operators.pop_back()
      expect_value = false
    elif token in ["and", "or", ","]:
      if expect_value: return {"error": "Add a particle before AND or OR."}
      if token == ",": token = "or"
      while not operators.is_empty() and operators.back() != "(" and (token == "or" or operators.back() == "and"):
        output.append(operators.pop_back())
      operators.append(token)
      expect_value = true
    else:
      if not expect_value or not _valid_particle(token):
        return {"error": "Invalid particle or missing operator: " + token}
      output.append(token)
      if token not in particles: particles.append(token)
      expect_value = false
  if expect_value: return {"error": "The expression needs a particle."}
  while not operators.is_empty():
    var operator: String = operators.pop_back()
    if operator == "(": return {"error": "Close the open bracket in the particle expression."}
    output.append(operator)
  var accepted: Array[String] = []
  for name in PARTICLES.TYPES:
    var stack: Array[bool] = []
    for token in output:
      if token in ["and", "or"]:
        var right: bool = stack.pop_back()
        var left: bool = stack.pop_back()
        stack.append(left and right if token == "and" else left or right)
      else:
        stack.append(name == token or PARTICLES.family(name) == token)
    if stack[0]: accepted.append(name)
  return {"particles": particles, "accepted": accepted}
