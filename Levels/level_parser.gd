class_name LevelParser
extends RefCounted

const CATALOG = preload("res://Buildings/building_catalog.gd")

static func parse(source: String) -> Dictionary:
  var lines := PackedStringArray()
  for line in source.split("\n"):
    lines.append(line.split("#", true, 1)[0])
  var text := "\n".join(lines)
  var dimensions := RegEx.new()
  dimensions.compile("(?i)(\\d+)\\s*x\\s*(\\d+)")
  var size_match := dimensions.search(text)
  if size_match == null:
    return {"error": "Missing grid size (for example 15 x 7)."}
  var data := {"width": int(size_match.get_string(1)), "height": int(size_match.get_string(2)), "goals": [], "buildings": [], "inventory": {}}
  if data.width <= 0 or data.height <= 0:
    return {"error": "Grid dimensions must be positive."}
  var blocks := RegEx.new()
  var names: Array = CATALOG.SCENES.keys()
  names.append_array(["goal", "inventory", "magnetic_field"])
  blocks.compile("(?is)\\b(" + "|".join(names) + ")\\s*:\\s*\\{([^}]*)\\}")
  for block in blocks.search_all(text):
    var kind := block.get_string(1).to_lower()
    if kind == "magnetic_field": kind = "magnet"
    var body := block.get_string(2)
    if kind == "goal":
      var goal := {}
      for clause in body.split(";", false):
        var parts := clause.split(":", true, 1)
        if parts.size() != 2:
          return {"error": "Invalid goal: " + clause}
        var values := []
        for value in parts[1].split(",", false):
          var token := value.strip_edges().to_lower().replace("/s", "")
          if token == "inf":
            values.append(INF)
          elif token.is_valid_float() and float(token) >= 0.0:
            values.append(float(token))
          else:
            return {"error": "Invalid goal value: " + token}
        if values.size() != 3:
          return {"error": "Each goal needs three values (one per star)."}
        var target := parts[0].strip_edges().to_lower()
        if target.begins_with("[") and target.ends_with("]"):
          var expression := _detector_expression(target.substr(1, target.length() - 2))
          if expression.has("error"):
            return expression
          goal["[" + ",".join(expression.accepted) + "]"] = values
        else:
          goal[target] = values
      if goal.is_empty():
        return {"error": "Empty goal."}
      data.goals.append(goal)
    elif kind == "inventory":
      for item in body.split(",", false):
        var pair := item.split("=", true, 1)
        if pair.size() != 2 or not pair[1].strip_edges().is_valid_int() or int(pair[1]) < 0:
          return {"error": "Invalid inventory entry: " + item}
        var name := pair[0].strip_edges().to_lower()
        if name == "magnetic_field": name = "magnet"
        if not CATALOG.SCENES.has(name):
          return {"error": "Unknown inventory item: " + name}
        data.inventory[name] = int(pair[1])
    else:
      var entry := {"kind": kind, "facing": "E", "fixed": "", "rate": 1.0, "particles": []}
      var list_regex := RegEx.new()
      list_regex.compile("\\[([^]]*)\\]")
      var list_match := list_regex.search(body)
      if list_match:
        if kind == "detector":
          var expression := _detector_expression(list_match.get_string(1))
          if expression.has("error"):
            return expression
          entry.particles = expression.particles
          entry.accepted = expression.accepted
        else:
          for value in list_match.get_string(1).split(",", false):
            entry.particles.append(value.strip_edges().to_lower())
        body = body.substr(0, list_match.get_start()) + body.substr(list_match.get_end())
      for part in body.split(",", false):
        var token := part.strip_edges()
        if token.is_empty():
          continue
        var pair := token.split("=", true, 1)
        if pair.size() == 2:
          entry[pair[0].strip_edges().to_lower()] = pair[1].strip_edges().to_lower()
        elif kind == "magnet" and token in ["+", "-", "+1", "-1"]:
          entry.polarity = token
        else:
          entry.facing = token.to_upper()
      if kind == "magnet" and str(entry.get("polarity", "positive")) not in ["positive", "negative", "+", "-", "+1", "-1", "1", "p", "n"]:
        return {"error": "Invalid magnetic polarity: " + str(entry.polarity)}
      if not entry.has("x") or not entry.has("y"):
        return {"error": kind + " needs x and y coordinates."}
      if entry.facing not in ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]:
        return {"error": "Invalid direction: " + entry.facing}
      if not str(entry.rate).is_valid_float() or float(entry.rate) <= 0.0:
        return {"error": "Emitter rate must be positive."}
      for name in entry.particles:
        if not _valid_particle(name):
          return {"error": "Unknown particle: " + name}
      var xs := _range_values(str(entry.x))
      var ys := _range_values(str(entry.y))
      if xs.is_empty() or ys.is_empty():
        return {"error": "Invalid coordinate or range for " + kind}
      for x in xs:
        for y in ys:
          if x < 0 or y < 0 or x >= data.width or y >= data.height:
            return {"error": "%s coordinate (%d, %d) is outside the grid." % [kind, x, y]}
          var placed: Dictionary = entry.duplicate(true)
          placed.x = x
          placed.y = y
          data.buildings.append(placed)
  if data.goals.is_empty():
    return {"error": "The level needs at least one goal."}
  return data

static func _range_values(value: String) -> Array[int]:
  var result: Array[int] = []
  var parts := value.split("..")
  if parts.size() > 2 or not parts[0].is_valid_int() or (parts.size() == 2 and not parts[1].is_valid_int()):
    return result
  var first := int(parts[0])
  var last := int(parts[1]) if parts.size() == 2 else first
  var direction := 1 if last >= first else -1
  for number in range(first, last + direction, direction):
    result.append(number)
  return result

static func _valid_particle(name: String) -> bool:
  if name in ["photon", "electron", "positron"]:
    return true
  return name in ["up", "down", "up_r", "up_g", "up_b", "down_r", "down_g", "down_b"]

# Compile a particle expression into its matching particle names. AND binds
# more tightly than OR; commas retain the original list's OR behavior.
static func _detector_expression(source: String) -> Dictionary:
  var lexer := RegEx.new()
  lexer.compile("\\s*([a-zA-Z_][a-zA-Z_0-9]*|[(),])")
  var output: Array[String] = []
  var operators: Array[String] = []
  var particles: Array[String] = []
  var pos := 0
  var expect_value := true
  while pos < source.length():
    if source.substr(pos).strip_edges().is_empty(): break
    var match_token := lexer.search(source, pos)
    if match_token == null or match_token.get_start() != pos:
      return {"error": "Invalid detector expression: " + source}
    pos = match_token.get_end()
    var token := match_token.get_string(1).to_lower()
    if token == "(":
      if not expect_value: return {"error": "Invalid detector expression: " + source}
      operators.append(token)
    elif token == ")":
      if expect_value: return {"error": "Invalid detector expression: " + source}
      while not operators.is_empty() and operators.back() != "(":
        output.append(operators.pop_back())
      if operators.is_empty(): return {"error": "Unmatched detector parenthesis: " + source}
      operators.pop_back()
      expect_value = false
    elif token in ["and", "or", ","]:
      if expect_value: return {"error": "Invalid detector expression: " + source}
      if token == ",": token = "or"
      while not operators.is_empty() and operators.back() != "(" and (token == "or" or operators.back() == "and"):
        output.append(operators.pop_back())
      operators.append(token)
      expect_value = true
    else:
      if not expect_value or not _valid_particle(token):
        return {"error": "Invalid detector particle: " + token}
      output.append(token)
      if token not in particles: particles.append(token)
      expect_value = false
  if expect_value: return {"error": "Invalid detector expression: " + source}
  while not operators.is_empty():
    var operator: String = operators.pop_back()
    if operator == "(": return {"error": "Unmatched detector parenthesis: " + source}
    output.append(operator)
  var accepted: Array[String] = []
  for name in ["photon", "electron", "positron", "up", "down", "up_r", "up_g", "up_b", "down_r", "down_g", "down_b"]:
    var stack: Array[bool] = []
    for token in output:
      if token in ["and", "or"]:
        var right: bool = stack.pop_back()
        var left: bool = stack.pop_back()
        stack.append(left and right if token == "and" else left or right)
      else:
        stack.append(name == token or name.begins_with(token + "_"))
    if stack[0]: accepted.append(name)
  return {"particles": particles, "accepted": accepted}
