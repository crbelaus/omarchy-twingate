function splitTabLine(line) {
  var parts = String(line || "").split("\t")
  for (var i = 0; i < parts.length; i++) parts[i] = parts[i].trim()
  return parts
}

// `twingate resources [--all]` prints a tab-separated table (RESOURCE NAME,
// ADDRESS, ALIAS, AUTH STATUS) and, when disconnected, a single sentence
// instead. A trailing "N background resource(s) has/have been hidden…" line
// shows up when resources were omitted (i.e. `--all` was not passed).
function parseResources(raw) {
  var text = String(raw || "").trim()
  if (text === "" || /must be connected/i.test(text)) {
    return { connected: false, resources: [], hiddenCount: 0 }
  }

  var lines = text.split(/\r?\n/)
  var headerIndex = -1
  for (var i = 0; i < lines.length; i++) {
    if (splitTabLine(lines[i])[0] === "RESOURCE NAME") {
      headerIndex = i
      break
    }
  }
  if (headerIndex === -1) return { connected: true, resources: [], hiddenCount: 0 }

  var resources = []
  var hiddenCount = 0
  for (var j = headerIndex + 1; j < lines.length; j++) {
    var line = lines[j]
    if (line.trim() === "") continue
    var hiddenMatch = line.match(/^(\d+)\s+background resources?\s+(?:has|have)\s+been\s+hidden/i)
    if (hiddenMatch) {
      hiddenCount = parseInt(hiddenMatch[1], 10) || 0
      continue
    }
    if (line.indexOf("\t") === -1) continue

    var cols = splitTabLine(line)
    resources.push({
      name: cols[0] || "",
      address: cols[1] || "",
      alias: cols[2] || "",
      authStatus: cols[3] || "",
      locked: cols[3] !== "" && cols[3] !== "-"
    })
  }

  return { connected: true, resources: resources, hiddenCount: hiddenCount }
}

// `twingate account list` prints a tab-separated table (EMAIL, NETWORK,
// NETWORK URL), or nothing at all when no account has been added yet.
function parseAccounts(raw) {
  var text = String(raw || "").trim()
  if (text === "") return []

  var lines = text.split(/\r?\n/)
  var headerIndex = -1
  for (var i = 0; i < lines.length; i++) {
    if (splitTabLine(lines[i])[0] === "EMAIL") {
      headerIndex = i
      break
    }
  }
  if (headerIndex === -1) return []

  var accounts = []
  for (var j = headerIndex + 1; j < lines.length; j++) {
    var line = lines[j]
    if (line.trim() === "" || line.indexOf("\t") === -1) continue
    var cols = splitTabLine(line)
    if (cols[0] === "") continue
    accounts.push({ email: cols[0] || "", network: cols[1] || "", networkUrl: cols[2] || "" })
  }
  return accounts
}

if (typeof module !== "undefined") {
  module.exports = {
    splitTabLine: splitTabLine,
    parseResources: parseResources,
    parseAccounts: parseAccounts
  }
}
