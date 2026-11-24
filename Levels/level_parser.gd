class_name LevelParser
extends RefCounted

const CATALOG = preload("res://Buildings/building_catalog.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")
const PARTICLE_TOKEN := "[a-zA-Z_][a-zA-Z_0-9]*|[(),]"
const MEDAL_BLOCKS := ["rate_medal", "cost_medal", "star_medal"]

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
  names.append_array(MEDAL_BLOCKS + ["star", "goal", "inventory", "no_build", "magnetic_field", "mirror"])
  blocks.compile("(?is)\\b(" + "|".join(names) + ")\\s*:\\s*\\{([^}]*)\\}[ \\t]*;?")
  return blocks.search_all(_without_metadata(text))

static func parse(source: String) -> Dictionary:
  var text := mask_comments(source)
  var size_match := find_dimensions(text)
  if size_match == null:
    return {"error": "Missing grid size (for example 15 x 7)."}
  var data := {"width": int(size_match.get_string(1)), "height": int(size_match.get_string(2)), "medals": {}, "stars": [], "buildings": [], "inventory": {}, "no_build_areas": [], "title": "", "rotation_steps": 8, "legacy_rates": false}
  if data.width <= 0 or data.height <= 0:
    return {"error": "Grid dimensions must be positive."}
  for item in find_metadata(text):
    var key := item.get_string(1).to_lower()
    var value := item.get_string(2).strip_edges().trim_prefix('"').trim_suffix('"')
    if key == "rotation":
      if value not in ["4", "8"]: return {"error": "Rotation must be 4 or 8 directions."}
      data.rotation_steps = int(value)
    elif key == "title":
      data.title = value
  var blocks := find_blocks(text)
  var legacy_suffix := RegEx.new()
  legacy_suffix.compile("(?i)/s\\b")
  for block in blocks:
    if block.get_string(1).to_lower() in ["goal", "rate_medal", "star_medal"] and legacy_suffix.search(block.get_string(2)) != null:
      data.legacy_rates = true
  var old_goals: Array[Dictionary] = []
  for block in blocks:
    var kind := building_kind(block.get_string(1))
    var body := block.get_string(2)
    match kind:
      "goal":
        var result := _parse_goal(body)
        if result.has("error"):
          return result
        old_goals.append(result)
      "rate_medal", "cost_medal":
        var medal := kind.trim_suffix("_medal")
        if data.medals.has(medal): return {"error": "Duplicate " + kind + " declaration."}
        var amount := _parse_rate(body) if medal == "rate" else _parse_cost_limit(body)
        if medal == "rate" and amount <= 0.0: return {"error": "The Rate medal needs a positive rate."}
        if medal == "cost" and amount < 0.0: return {"error": "The Cost medal needs a nonnegative cost limit."}
        data.medals[medal] = amount
      "star_medal":
        var result := _parse_star_medal(body)
        if result.has("error"): return result
        if not data.medals.has("star"): data.medals.star = []
        data.medals.star.append(result)
      "star":
        var result := _parse_no_build(body, data.width, data.height)
        if result.has("error") or result.area.size != Vector2i.ONE:
          return {"error": "A star needs a single x and y coordinate inside the grid."}
        if result.area.position in data.stars: return {"error": "A cell can only contain one star."}
        data.stars.append(result.area.position)
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
  if data.medals.is_empty() and not old_goals.is_empty():
    data.medals = _medals_from_goals(old_goals)
  elif data.medals.size() != MEDAL_BLOCKS.size() or not old_goals.is_empty():
    return {"error": "Define a rate_medal, cost_medal and star_medal together."}
  var occupied := {}
  for building in data.buildings:
    var cell := Vector2i(building.x, building.y)
    var key := CATALOG.occupancy_key(building.kind, cell, building.facing)
    if occupied.has(key):
      return {"error": "Overlapping buildings at (%d, %d)." % [cell.x, cell.y]}
    occupied[key] = true
  return data

static func _parse_cost_limit(text: String) -> float:
  var value := text.strip_edges()
  if not value.is_valid_float() or not is_finite(float(value)): return -1.0
  return float(value)

static func _parse_output_target(target: String) -> Dictionary:
  if target.begins_with("[") and target.ends_with("]"):
    var expression := particle_expression(target.substr(1, target.length() - 2))
    if expression.has("error"): return expression
    if expression.accepted.is_empty(): return {"error": "Output expression matches no particle: " + target}
    return {"key": "[" + ",".join(expression.accepted) + "]", "target": PARTICLES.current_expression(target)}
  var name := PARTICLES.current_name(target.to_lower())
  if not _valid_particle(name): return {"error": "Unknown output target: " + target}
  return {"key": name, "target": name}

static func _parse_star_medal(body: String) -> Dictionary:
  var rule := {"rates": {}, "targets": {}, "no_buildings": [], "hit_stars": false}
  var seen := {}
  for clause in body.strip_edges().split(";", false):
    if clause.strip_edges().is_empty(): continue
    var parts := clause.split(":", true, 1)
    if parts.size() != 2: return {"error": "Invalid Star medal condition: " + clause}
    var target := parts[0].strip_edges()
    var value := parts[1].strip_edges()
    var key := target.to_lower()
    if key not in ["cost", "no_buildings", "hit_stars", "any"]:
      var output := _parse_output_target(target)
      if output.has("error"): return output
      key = output.key
      rule.targets[key] = output.target
    if seen.has(key): return {"error": "Duplicate Star medal condition: " + target}
    seen[key] = true
    match key:
      "cost":
        var cost_limit := _parse_cost_limit(value)
        if cost_limit < 0.0: return {"error": "The Star medal cost limit must be nonnegative."}
        rule.cost = cost_limit
      "no_buildings":
        for name in value.split(","):
          var kind := building_kind(name.strip_edges())
          if not CATALOG.SCENES.has(kind): return {"error": "Unknown excluded building: " + name.strip_edges()}
          if kind not in rule.no_buildings: rule.no_buildings.append(kind)
      "hit_stars":
        if value.to_lower() != "true": return {"error": "Use hit_stars: true to require every placed star."}
        rule.hit_stars = true
      _:
        var rate := _parse_rate(value)
        if rate <= 0.0: return {"error": "Output rates must be positive: " + value}
        rule.rates[key] = rate
  if seen.is_empty(): return {"error": "The Star medal needs at least one condition."}
  return rule

static func _medals_from_goals(goals: Array[Dictionary]) -> Dictionary:
  var rate := INF
  var cost_limit := INF
  var alternatives: Array[Dictionary] = []
  for old in goals:
    var lowest := 0.0
    for key in old.goal:
      if key != "cost" and is_finite(old.goal[key][0]): lowest += float(old.goal[key][0])
    if lowest > 0.0: rate = minf(rate, lowest)
    for tier in [2, 1, 0]:
      var rates := {}
      var possible := true
      for key in old.goal:
        if key == "cost": continue
        var amount: float = old.goal[key][tier]
        if is_inf(amount): possible = false
        elif amount > 0.0: rates[key] = amount
      if not possible: continue
      var rule := {"rates": rates, "targets": old.targets, "no_buildings": [], "hit_stars": false}
      if old.goal.has("cost") and is_finite(old.goal.cost[tier]):
        rule.cost = floorf(old.goal.cost[tier])
        cost_limit = minf(cost_limit, rule.cost)
      if rates.is_empty() and not rule.has("cost"): rule.rates["any"] = 1.0
      alternatives.append(rule)
      break
  if alternatives.is_empty():
    alternatives.append({"rates": {"any": 1.0}, "targets": {}, "no_buildings": [], "hit_stars": false})
  return {"rate": rate if is_finite(rate) else 1.0, "cost": cost_limit if is_finite(cost_limit) else 0.0, "star": alternatives}

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
    if target.to_lower() == "cost":
      goal["cost"] = values
      continue
    var output := _parse_output_target(target)
    if output.has("error"): return output
    goal[output.key] = values
    targets[output.key] = output.target
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
