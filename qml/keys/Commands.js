.pragma library

// Pure chord/scope resolution, kept free of QML types so it can be tested with node.
//
//   command: { id, title, scope, keys: ["j", "g g", "C-d"], run(), when?(), hidden? }
//   scopes:  innermost first, e.g. ["list", "mail/list", "mail", "global"]
//   seq:     tokens typed so far, e.g. ["g"]
//
// Returns { exact, prefixes }. `exact` is the innermost command bound to the whole
// sequence; `prefixes` are { cmd, next } for commands that continue it.
function resolve(commands, scopes, seq) {
  var key = seq.join(" ")
  var exact = null
  var prefixes = []
  for (var s = 0; s < scopes.length; s++) {
    for (var i = 0; i < commands.length; i++) {
      var c = commands[i]
      if (c.scope !== scopes[s]) continue
      if (c.when && !c.when()) continue
      for (var k = 0; k < c.keys.length; k++) {
        var bound = c.keys[k]
        if (bound === key) { if (!exact) exact = c }
        else if (bound.indexOf(key + " ") === 0) prefixes.push({ cmd: c, next: bound.slice(key.length + 1) })
      }
    }
  }
  return { exact: exact, prefixes: prefixes }
}

// Commands that apply in `scopes`, one entry per id (innermost wins), for help/palette.
function applicable(commands, scopes) {
  var seen = {}
  var out = []
  for (var s = 0; s < scopes.length; s++) {
    for (var i = 0; i < commands.length; i++) {
      var c = commands[i]
      if (c.scope !== scopes[s] || c.hidden || seen[c.id]) continue
      if (c.when && !c.when()) continue
      seen[c.id] = true
      out.push(c)
    }
  }
  return out
}

// Subsequence match: every character of `query` appears in `text` in order.
function fuzzy(query, text) {
  var q = query.toLowerCase().replace(/\s+/g, "")
  var t = text.toLowerCase()
  var j = 0
  for (var i = 0; i < t.length && j < q.length; i++) if (t[i] === q[j]) j++
  return j === q.length
}

function keyLabel(keys) {
  return keys.map(function(k) { return k.replace(/^C-/, "Ctrl-").replace(/^S-/, "Shift-") }).join("  ")
}

// ":goto calendar" / "goto calendar" -> { name: "goto", arg: "calendar" }; null when empty.
function parseEx(text) {
  var m = /^\s*:?\s*(\S+)(\s+(.*))?$/.exec(text)
  if (!m) return null
  return { name: m[1].toLowerCase(), arg: (m[3] || "").trim(), hasSpace: m[2] !== undefined }
}

// The command (any scope) whose `ex` names include `name`, honouring `when`.
function findEx(commands, name) {
  for (var i = 0; i < commands.length; i++) {
    var c = commands[i]
    if (!c.ex || (c.when && !c.when())) continue
    if (c.ex.indexOf(name) >= 0) return c
  }
  return null
}

var sectionNames = {
  "global": "Everywhere", "nav": "Menu pane", "folder": "Folders pane", "list": "List pane",
  "reader": "Reading pane", "mail": "Mail", "calendar/list": "Calendar", "contacts/list": "People",
  "tasks/list": "Tasks", "settings": "Settings", "sms": "SMS"
}
function sectionName(scope) { return sectionNames[scope] || scope }

// Every non-hidden command grouped by scope, scopes in `first` (the active ones) leading.
// Returns [{ scope, name, active, commands }].
function grouped(commands, first) {
  var order = first.slice()
  for (var i = 0; i < commands.length; i++) if (order.indexOf(commands[i].scope) < 0) order.push(commands[i].scope)
  var out = []
  for (var s = 0; s < order.length; s++) {
    var cs = commands.filter(function(c) { return c.scope === order[s] && !c.hidden && c.keys.length > 0 })
    if (cs.length) out.push({ scope: order[s], name: sectionName(order[s]), active: first.indexOf(order[s]) >= 0, commands: cs })
  }
  return out
}
