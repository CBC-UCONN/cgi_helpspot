## Single page app: DNA sequencing project form + sample spreadsheet, submitted to HelpSpot.
{.push warning[CStringConv]: off.} # string and cstring are both JS strings on this backend
import std/[strutils, tables, times]
import karax/[karax, karaxdsl, vdom, kdom]
import lib/[csv, ini, schema, sheet, validation, yamlout]
import jsbridge

type
  Config = object
    helpspotUrl: string
    categoryId: int

  Status = enum
    stIdle, stSubmitting, stSuccess, stError

const
  initialRows = 10
  maxAddRows = 1000
  demo = defined(demo) # build with -d:demo (nimble webdemo) for the test data button

proc parseConfig(text: string): Config =
  let c = parseIni(text)
  result.helpspotUrl = c.getOrDefault("helpspot.url")
  if result.helpspotUrl.len == 0:
    raise newException(ValueError, "config.ini: [helpspot] url is required")
  result.categoryId = parseInt(c.getOrDefault("helpspot.category_id", "0"))

# Read at build time; edit config.ini and rebuild to change it.
const cfg = parseConfig(staticRead("../config.ini"))

var
  project = initTable[string, string]()
  grid: Grid
  cellErrors: seq[seq[string]]
  attempted = false               # show "required" errors only after a submit attempt
  addCount = "5"
  uploadMsg = ""
  uploadIsError = false
  status = stIdle
  statusMsg = ""

proc fieldError(f: ProjectField): string =
  validate(project.getOrDefault(f.key), f.validators)

proc isRequired(validators: seq[Validator]): bool =
  validate("", validators).len > 0

proc revalidate() =
  cellErrors = validateGrid(grid, sampleColumns)

proc projectErrorCount(): int =
  for f in projectFields:
    if f.fieldError.len > 0: inc result

proc resetGrid() =
  grid = @[]
  for _ in 1 .. initialRows: grid.add newRow(sampleColumns)
  revalidate()

proc fillTestData() =
  for (k, v) in {
      "contact_first_name": "Test", "contact_last_name": "User",
      "contact_email": "test.user@example.org", "institution": "Test Lab",
      "principal_investigator": "Dr. Test", "project_name": "TEST Project",
      "organism": "Homo sapiens", "sequencing_type": "Whole genome",
      "platform": "Illumina NovaSeq", "read_length": "150",
      "target_coverage": "30x", "description": "Test submission; please discard."}:
    project[k] = v
  resetGrid()
  for r in 0 ..< 3:
    grid[r] = @["TEST-" & $(r + 1), "Test sample " & $(r + 1), "gDNA", "Homo sapiens",
                "25.5", "30", "ACGTACGT", ""]
  revalidate()

proc slug(s: string): string =
  for c in s.toLowerAscii:
    if c in {'a' .. 'z', '0' .. '9'}: result.add c
    elif result.len > 0 and result[^1] != '_': result.add '_'
  result = result.strip(chars = {'_'})
  if result.len == 0: result = "project"

# ---------------------------------------------------------------- actions

proc onFileChosen(csvText, err: cstring) =
  if err.len > 0:
    uploadMsg = $err
    uploadIsError = true
  else:
    let res = importRows(parseCsv($csvText), sampleColumns)
    if res.error.len > 0:
      uploadMsg = res.error
      uploadIsError = true
    else:
      grid = res.grid
      revalidate()
      uploadIsError = false
      uploadMsg = "Imported " & $grid.len & " sample rows."
      if res.unmatched.len > 0:
        uploadMsg.add " Ignored unrecognised columns: " & res.unmatched.join(", ") & "."
  redraw()

proc addRows() =
  var n = 0
  try: n = parseInt(addCount.strip())
  except ValueError: discard
  if n < 1 or n > maxAddRows:
    uploadIsError = true
    uploadMsg = "Enter a number of rows between 1 and " & $maxAddRows & "."
    return
  uploadMsg = ""
  for _ in 1 .. n: grid.add newRow(sampleColumns)
  revalidate()

proc removeRow(r: int) =
  grid.delete r
  if grid.len == 0: grid.add newRow(sampleColumns)
  revalidate()

proc submit() =
  if status == stSubmitting: return
  attempted = true
  revalidate()
  let samples = grid.dataRows
  if projectErrorCount() > 0 or cellErrors.errorCount > 0:
    status = stError
    statusMsg = "Please fix the highlighted fields before submitting."
    return
  if samples.len == 0:
    status = stError
    statusMsg = "Add at least one sample."
    return

  var meta: seq[(string, string)]
  for f in projectFields: meta.add (f.key, project.getOrDefault(f.key).strip())
  let name = slug(project.getOrDefault("project_name"))
  let yaml = projectYaml(meta, samples.len, now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"))
  let csvText = samplesCsv(samples, sampleColumns)

  let form = newForm()
  form.append("tNote", (if demo: "[TEST SUBMISSION - please discard]\n\n" else: "") &
    "New DNA sequencing project submission\n\n" &
    "Project: " & project.getOrDefault("project_name") & "\n" &
    "Principal investigator: " & project.getOrDefault("principal_investigator") & "\n" &
    "Institution: " & project.getOrDefault("institution") & "\n" &
    "Samples: " & $samples.len & "\n\n" &
    "Attached: " & name & "_project.yaml, " & name & "_samples.csv")
  form.append("sFirstName", project.getOrDefault("contact_first_name").strip())
  form.append("sLastName", project.getOrDefault("contact_last_name").strip())
  form.append("sEmail", project.getOrDefault("contact_email").strip())
  if cfg.categoryId > 0: form.append("xCategory", $cfg.categoryId)
  form.attach(1, name & "_project.yaml", "application/x-yaml", yaml)
  form.attach(2, name & "_samples.csv", "text/csv", csvText)

  status = stSubmitting
  statusMsg = "Submitting..."
  post(cfg.helpspotUrl, form, proc (err: cstring) =
    # The response is opaque (no CORS), so success only means the request did not fail.
    if err.len > 0:
      status = stError
      statusMsg = "Submission failed: " & $err
    else:
      status = stSuccess
      statusMsg = "Ticket submitted."
    redraw())

# ---------------------------------------------------------------- views

const
  inputBase = "w-full rounded border px-2 py-1 text-sm focus:outline-none focus:ring-2 "
  okCls = inputBase & "border-slate-300 focus:ring-sky-400"
  badCls = inputBase & "border-red-500 bg-red-50 focus:ring-red-400"

proc renderField(f: ProjectField): VNode =
  let key = f.key
  let val = project.getOrDefault(key)
  let err = f.fieldError
  let cls = if err.len > 0 and (val.len > 0 or attempted): badCls else: okCls
  let setVal = proc (ev: Event; n: VNode) =
    project[key] = $getInputText(n)
  result = buildHtml(tdiv(class = if f.kind == fkTextArea: "md:col-span-2" else: "")):
    label(class = "block text-sm font-medium mb-1", `for` = "f-" & key):
      text f.label
      if isRequired(f.validators):
        span(class = "text-red-600"): text " *"
    if f.kind == fkSelect:
      select(id = "f-" & key, class = cls, onchange = setVal):
        option(value = "", selected = (val == "")): text ""
        for o in f.options:
          option(value = o, selected = (val == o)): text o
    elif f.kind == fkTextArea:
      textarea(id = "f-" & key, class = cls, rows = "4", oninput = setVal):
        text val
    elif f.kind == fkDate:
      input(id = "f-" & key, class = cls, `type` = "date", value = val, oninput = setVal)
    else:
      input(id = "f-" & key, class = cls, `type` = "text", value = val,
            placeholder = f.placeholder, oninput = setVal)
    if err.len > 0 and (val.len > 0 or attempted):
      p(class = "mt-1 text-xs text-red-600"): text err

proc renderCell(r, c: int): VNode =
  let val = grid[r][c]
  let err = cellErrors[r][c]
  let bad = err.len > 0 and (val.strip().len > 0 or attempted)
  let col = sampleColumns[c]
  result = buildHtml(td(class = "p-0 border border-slate-200 " & col.widthClass)):
    input(id = "c-" & $r & "-" & $c,
          class = "w-full px-2 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-inset " &
                  (if bad: "bg-red-100 focus:ring-red-400" else: "bg-white focus:ring-sky-400"),
          `type` = "text", value = val, title = (if bad: err else: ""),
          list = (if col.options.len > 0: "dl-" & col.key else: ""),
          oninput = proc (ev: Event; n: VNode) =
            grid[r][c] = $getInputText(n)
            revalidate())

proc renderSheet(): VNode =
  let badCells = block:
    var n = 0
    for r in 0 ..< grid.len:
      for c in 0 ..< sampleColumns.len:
        let v = grid[r][c].strip()
        if cellErrors[r][c].len > 0 and (v.len > 0 or attempted): inc n
    n
  result = buildHtml(tdiv):
    for col in sampleColumns:
      if col.options.len > 0:
        datalist(id = "dl-" & col.key):
          for o in col.options: option(value = o)
    tdiv(class = "overflow-x-auto max-h-[32rem] overflow-y-auto border border-slate-300 rounded"):
      table(class = "border-collapse"):
        thead(class = "sticky top-0 z-10"):
          tr:
            th(class = "bg-slate-200 border border-slate-300 px-2 py-1 text-xs"): text "#"
            for col in sampleColumns:
              th(class = "bg-slate-200 border border-slate-300 px-2 py-1 text-xs text-left " &
                         col.widthClass):
                text col.title
                if isRequired(col.validators):
                  span(class = "text-red-600"): text " *"
            th(class = "bg-slate-200 border border-slate-300 px-2 py-1")
        tbody:
          for r in 0 ..< grid.len:
            tr:
              td(class = "bg-slate-100 border border-slate-200 px-2 text-xs text-slate-500 text-right"):
                text $(r + 1)
              for c in 0 ..< sampleColumns.len:
                renderCell(r, c)
              td(class = "border border-slate-200 px-1 bg-white"):
                button(class = "text-slate-400 hover:text-red-600 text-sm", title = "Remove row",
                       onclick = proc (ev: Event; n: VNode) = removeRow(r)):
                  text "\u00D7"
    if badCells > 0:
      p(class = "mt-2 text-sm text-red-600"):
        text $badCells & " cell(s) need attention. Hover a highlighted cell for details."

proc createDom(): VNode =
  let statusCls = case status
    of stSuccess: "bg-green-100 text-green-800 border-green-300"
    of stError: "bg-red-100 text-red-800 border-red-300"
    else: "bg-sky-100 text-sky-800 border-sky-300"
  result = buildHtml(tdiv):
    header(class = "sticky top-0 z-20 bg-white border-b border-slate-300 shadow-sm"):
      tdiv(class = "max-w-7xl mx-auto px-4 py-3 flex items-center justify-between gap-4"):
        h1(class = "text-xl font-semibold"): text "DNA Sequencing Project Submission"
        tdiv(class = "flex items-center gap-3"):
          if demo:
            button(class = "rounded border border-amber-500 bg-amber-100 px-4 py-2 text-amber-900 " &
                           "hover:bg-amber-200",
                   onclick = proc (ev: Event; n: VNode) = fillTestData()):
              text "Fill test data"
          button(class = "rounded bg-sky-600 px-5 py-2 text-white font-medium hover:bg-sky-700 " &
                         "disabled:opacity-50",
                 onclick = proc (ev: Event; n: VNode) = submit()):
            text(if status == stSubmitting: "Submitting..." else: "Submit ticket")
    main(class = "max-w-7xl mx-auto px-4 py-6 space-y-6"):
      if statusMsg.len > 0:
        tdiv(class = "rounded border p-3 text-sm " & statusCls): text statusMsg
      section(class = "bg-white rounded shadow p-5"):
        h2(class = "text-lg font-semibold mb-4"): text "Project information"
        tdiv(class = "grid grid-cols-1 md:grid-cols-2 gap-4"):
          for f in projectFields:
            renderField(f)
      section(class = "bg-white rounded shadow p-5"):
        h2(class = "text-lg font-semibold mb-1"): text "Samples"
        p(class = "text-sm text-slate-600 mb-3"):
          text "Enter samples below or upload a CSV / Excel file whose first row contains column headers."
        tdiv(class = "mb-4"):
          input(`type` = "file", accept = ".csv,.xlsx,.xls,text/csv",
                class = "text-sm file:mr-3 file:rounded file:border-0 file:bg-slate-200 " &
                        "file:px-3 file:py-1.5 file:hover:bg-slate-300",
                onchange = proc (ev: Event; n: VNode) = readSpreadsheet(n.dom, onFileChosen))
          if uploadMsg.len > 0:
            p(class = "mt-2 text-sm " & (if uploadIsError: "text-red-600" else: "text-green-700")):
              text uploadMsg
        renderSheet()
        tdiv(class = "mt-4 flex items-center gap-2"):
          button(class = "rounded bg-slate-700 px-4 py-1.5 text-sm text-white hover:bg-slate-800",
                 onclick = proc (ev: Event; n: VNode) = addRows()):
            text "Add rows"
          input(`type` = "number", min = "1", max = $maxAddRows, value = addCount,
                class = "w-24 rounded border border-slate-300 px-2 py-1 text-sm",
                oninput = proc (ev: Event; n: VNode) = addCount = $getInputText(n))

resetGrid()
setRenderer createDom, "ROOT"
