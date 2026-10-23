## Spreadsheet model helpers: validation of a whole grid, importing parsed CSV, and export.
import std/[strutils, sequtils, tables]
import csv, schema, validation

type
  Grid* = seq[seq[string]]

proc newRow*(columns: seq[Column]): seq[string] = newSeq[string](columns.len)

proc isBlankRow*(row: seq[string]): bool =
  for v in row:
    if v.strip().len > 0: return false
  true

proc validateGrid*(grid: Grid; columns: seq[Column]): seq[seq[string]] =
  ## Returns an error message (or "") for every cell. Fully blank rows are not validated.
  result = newSeq[seq[string]](grid.len)
  for r in 0 ..< grid.len:
    result[r] = newSeq[string](columns.len)
  for c, col in columns:
    var ctx = ValidationContext()
    for row in grid:
      if not row.isBlankRow:
        ctx.counts.inc row[c].normalized
    for r, row in grid:
      if not row.isBlankRow:
        result[r][c] = validate(row[c], col.validators, ctx)

proc errorCount*(errors: seq[seq[string]]): int =
  for row in errors:
    for e in row:
      if e.len > 0: inc result

proc dataRows*(grid: Grid): Grid =
  for row in grid:
    if not row.isBlankRow: result.add row

proc headerKey(s: string): string =
  for c in s.toLowerAscii:
    if c in {'a' .. 'z', '0' .. '9'}: result.add c

proc mapHeaders*(header: seq[string]; columns: seq[Column]): seq[int] =
  ## For each schema column returns the index of the matching header cell, or -1.
  result = newSeq[int](columns.len)
  for c, col in columns:
    result[c] = -1
    var names = @[headerKey(col.title), headerKey(col.key)]
    for a in col.aliases: names.add headerKey(a)
    for i, h in header:
      if headerKey(h) in names:
        result[c] = i
        break

proc importRows*(parsed: seq[seq[string]]; columns: seq[Column]):
    tuple[grid: Grid, unmatched: seq[string], error: string] =
  ## Converts parsed CSV (first row is the header) into a grid using header names.
  if parsed.len < 2:
    result.error = "The file needs a header row and at least one data row."
    return
  let map = mapHeaders(parsed[0], columns)
  var used: seq[int]
  for i in map:
    if i >= 0: used.add i
  if used.len == 0:
    result.error = "No column headers matched. Expected: " &
      columns.mapIt(it.title).join(", ")
    return
  for i, h in parsed[0]:
    if i notin used and h.strip().len > 0: result.unmatched.add h
  for r in 1 ..< parsed.len:
    var row = newRow(columns)
    for c, i in map:
      if i >= 0 and i < parsed[r].len: row[c] = parsed[r][i].strip()
    if not row.isBlankRow: result.grid.add row
  if result.grid.len == 0:
    result.error = "The file contains no sample rows."

proc samplesCsv*(grid: Grid; columns: seq[Column]): string =
  ## Header uses column titles so the file can be re-imported.
  var rows: seq[seq[string]] = @[columns.mapIt(it.title)]
  for row in grid.dataRows:
    rows.add row.mapIt(it.strip())
  toCsv(rows)
