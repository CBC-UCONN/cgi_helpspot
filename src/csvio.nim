import std/[strutils, sequtils]
import model

proc sampleColumns*(p: ProjectForm): seq[string] =
  for column in visibleSampleColumns(p):
    result.add column.key

proc csvEscape*(value: string): string =
  if value.contains({',', '"', '\n', '\r'}):
    '"' & value.replace("\"", "\"\"") & '"'
  else:
    value

proc templateCsv*(p: ProjectForm): string =
  let columns = visibleSampleColumns(p)
  result = columns.mapIt(it.key).join(",") & "\n"
  result.add columns.mapIt(csvEscape(field(emptySample(), it.key))).join(",") & "\n"

proc parseCsvLine(line: string): seq[string] =
  var current = ""
  var quoted = false
  var i = 0
  while i < line.len:
    let c = line[i]
    if c == '"':
      if quoted and i + 1 < line.len and line[i + 1] == '"':
        current.add '"'
        inc i
      else:
        quoted = not quoted
    elif c == ',' and not quoted:
      result.add current
      current = ""
    else:
      current.add c
    inc i
  result.add current

proc parseCsv*(contents: string; p: ProjectForm): tuple[rows: seq[SampleRow], errors: seq[string]] =
  let lines = contents.replace("\r\n", "\n").replace('\r', '\n').splitLines()
  if lines.len == 0 or lines[0].strip().len == 0:
    result.errors.add "The CSV file is empty."
    return

  let expected = sampleColumns(p)
  let headers = parseCsvLine(lines[0]).mapIt(it.strip().toLowerAscii())
  if headers != expected:
    result.errors.add "CSV columns do not match the current project form. Expected: " & expected.join(", ")
    return

  for lineNumber in 1 ..< lines.len:
    if lines[lineNumber].strip().len == 0: continue
    let values = parseCsvLine(lines[lineNumber])
    if values.len != expected.len:
      result.errors.add "Row " & $lineNumber & " has " & $values.len & " columns; expected " & $expected.len & "."
      continue
    var row = emptySample()
    for i, name in expected:
      let value = values[i].strip()
      setSampleValue(row, name, value)
    result.rows.add row

  if result.rows.len == 0 and result.errors.len == 0:
    result.errors.add "The CSV contains no sample rows."
