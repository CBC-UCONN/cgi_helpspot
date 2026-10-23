## Minimal RFC 4180 CSV reader/writer (works on the native and JS backends).
import std/strutils

proc parseCsv*(text: string): seq[seq[string]] =
  ## Parses CSV text into rows. Blank lines are skipped.
  let s = if text.startsWith("\xEF\xBB\xBF"): text[3 .. ^1] else: text
  var
    row: seq[string]
    field = ""
    inQuotes = false
    i = 0

  proc endRow(row: var seq[string]; field: var string; rows: var seq[seq[string]]) =
    row.add field
    field = ""
    if not (row.len == 1 and row[0].len == 0):
      rows.add row
    row = @[]

  while i < s.len:
    let c = s[i]
    if inQuotes:
      if c == '"':
        if i + 1 < s.len and s[i + 1] == '"':
          field.add '"'
          inc i
        else:
          inQuotes = false
      else:
        field.add c
    elif c == '"':
      inQuotes = true
    elif c == ',':
      row.add field
      field = ""
    elif c == '\r' or c == '\n':
      if c == '\r' and i + 1 < s.len and s[i + 1] == '\n':
        inc i
      endRow(row, field, result)
    else:
      field.add c
    inc i

  if field.len > 0 or row.len > 0:
    endRow(row, field, result)

proc csvEscape*(value: string): string =
  if value.len > 0 and (value.find({',', '"', '\n', '\r'}) >= 0 or
      value[0] == ' ' or value[^1] == ' '):
    "\"" & value.replace("\"", "\"\"") & "\""
  else:
    value

proc toCsv*(rows: seq[seq[string]]): string =
  for row in rows:
    for i, v in row:
      if i > 0: result.add ','
      result.add csvEscape(v)
    result.add '\n'
