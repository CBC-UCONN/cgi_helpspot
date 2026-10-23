import std/[unittest, strutils, tables]
import ../src/lib/[csv, ini, validation, schema, sheet, yamlout]

suite "ini":
  test "sections, comments, values containing '='":
    let c = parseIni("; c\n[helpspot]\nurl = http://x/a?b=c\n# n\ncategory_id=3\n")
    check c["helpspot.url"] == "http://x/a?b=c"
    check c["helpspot.category_id"] == "3"

suite "csv":
  test "quotes, escapes, CRLF, blank lines":
    let rows = parseCsv("a,b\r\n\"x,1\",\"he said \"\"hi\"\"\"\r\n\r\nlast,")
    check rows == @[@["a", "b"], @["x,1", "he said \"hi\""], @["last", ""]]
  test "round trip":
    let rows = @[@["a", "b,c"], @["\"q\"", "line\nbreak"]]
    check parseCsv(toCsv(rows)) == rows

suite "validators":
  let ctx = ValidationContext()
  test "required / maxLength":
    check required()("  ", ctx).len > 0
    check maxLength(3)("abcd", ctx).len > 0
    check maxLength(3)("", ctx) == ""
  test "numberRange":
    check numberRange(0, 10)("5", ctx) == ""
    check numberRange(0, 10)("11", ctx).len > 0
    check numberRange(0, 10)("nan", ctx).len > 0
    check numberRange(1, 10, integer = true)("2.5", ctx).len > 0
  test "email and oneOf":
    check email()("a@b.org", ctx) == ""
    check email()("a@b", ctx).len > 0
    check oneOf(@["DNA", "RNA"])("dna", ctx) == ""
    check oneOf(@["DNA", "RNA"])("xyz", ctx).len > 0

suite "sheet":
  test "duplicate ids flagged, blank rows ignored":
    let grid = @[@["S1", "", "DNA", "", "1", "1", "", ""],
                 @["S1", "", "DNA", "", "1", "1", "", ""],
                 newRow(sampleColumns)]
    let errs = validateGrid(grid, sampleColumns)
    check errs[0][0].len > 0 and errs[1][0].len > 0
    check errs[2].join("") == ""
  test "import maps headers":
    let parsed = parseCsv("Sample ID,volume,Extra\nA1,5,x\n,,\n")
    let res = importRows(parsed, sampleColumns)
    check res.error == ""
    check res.grid.len == 1 and res.grid[0][0] == "A1" and res.grid[0][5] == "5"
    check res.unmatched == @["Extra"]

suite "yaml":
  test "quotes values":
    let y = projectYaml(@[("name", "a \"b\"\nc")], 2, "2026-01-01")
    check "  name: \"a \\\"b\\\"\\nc\"" in y
    check "sample_count: 2" in y
