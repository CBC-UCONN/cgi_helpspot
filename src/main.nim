import std/[jsffi, strutils]
import karax/[karaxdsl, vdom, kbase]
import karax/karax
import model, update, validators, csvio

proc readFileInput(id: cstring; callback: proc(content: cstring) {.closure.}) {.importjs: """
  (function(id, callback) {
    const input = document.getElementById(id);
    if (!input || !input.files || input.files.length === 0) return;
    const reader = new FileReader();
    reader.onload = function() { callback(String(reader.result)); };
    reader.readAsText(input.files[0]);
  })(#, #)
""".}

proc downloadText(filename, content: cstring) {.importjs: """
  (function(filename, content) {
    const blob = new Blob([content], {type: 'text/csv;charset=utf-8'});
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  })(#, #)
""".}

proc checkboxChecked(id: cstring): bool {.importjs: "document.getElementById(#).checked".}

var state = initialModel()

proc dispatch(msg: Msg) =
  update(state, msg)

proc fieldError(field: string): string =
  for e in state.errors:
    if e.field == field: return e.message
  ""

proc hasError(field: string): bool = fieldError(field).len > 0

proc inputClass(field: string): string =
  "w-full rounded-lg border bg-white px-3 py-2 text-sm shadow-sm outline-none transition focus:ring-2 " &
  (if hasError(field): "border-red-400 focus:border-red-500 focus:ring-red-100" else: "border-slate-300 focus:border-blue-500 focus:ring-blue-100")

proc labelText(label, field: string): VNode =
  buildHtml(label(`for` = field, class = "mb-1 block text-sm font-medium text-slate-700")):
    text label

proc errorText(field: string): VNode =
  let message = fieldError(field)
  buildHtml(tdiv(class = "mt-1 text-xs text-red-600")):
    if message.len > 0: text message

proc projectValue(project: ProjectForm; key: string): string =
  case key
  of "projectName": project.projectName
  of "requester": project.requester
  of "email": project.email
  of "organism": project.organism
  of "assay": $project.assay
  of "readType": $project.readType
  of "indexType": $project.indexType
  of "libraryPrep": project.libraryPrep
  of "customReference": $project.customReference
  of "referenceName": project.referenceName
  of "notes": project.notes
  else: ""

proc projectBoolValue(project: ProjectForm; key: string): bool =
  key == "customReference" and project.customReference

proc projectFieldView(fieldDef: ProjectFieldDef): VNode =
  let key = fieldDef.key
  let value = projectValue(state.project, key)
  case fieldDef.kind
  of textField, emailField:
    buildHtml(tdiv(class = "space-y-1")):
      labelText(fieldDef.label, key)
      input(id = key, class = inputClass(key), value = value, `type` = (if fieldDef.kind == emailField: "email" else: "text")):
        proc oninput(ev: Event; n: VNode) =
          dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
      if fieldDef.help.len > 0:
        p(class = "text-xs text-slate-500"): text fieldDef.help
      errorText(key)
  of selectField:
    buildHtml(tdiv(class = "space-y-1")):
      labelText(fieldDef.label, key)
      select(id = key, class = inputClass(key), value = value):
        proc onchange(ev: Event; n: VNode) =
          dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
        for optionValue in fieldDef.options:
          option(value = optionValue, selected = optionValue == value):
            text optionValue
      if fieldDef.help.len > 0:
        p(class = "text-xs text-slate-500"): text fieldDef.help
      errorText(key)
  of checkboxField:
    buildHtml(tdiv(class = "rounded-xl border border-slate-200 bg-slate-50 p-4")):
      label(class = "flex cursor-pointer items-start gap-3"):
        input(id = key, `type` = "checkbox", class = "mt-1 h-4 w-4 rounded border-slate-300", checked = projectBoolValue(state.project, key)):
          proc onchange(ev: Event; n: VNode) =
            dispatch(Msg(kind: setProjectField, column: key, boolValue: checkboxChecked(key)))
        span:
          span(class = "block text-sm font-medium text-slate-800"): text fieldDef.label
          if fieldDef.help.len > 0:
            span(class = "mt-1 block text-xs text-slate-500"): text fieldDef.help
      errorText(key)
  of textareaField:
    buildHtml(tdiv(class = "space-y-1")):
      labelText(fieldDef.label, key)
      textarea(id = key, class = inputClass(key), rows = "4", value = value):
        proc oninput(ev: Event; n: VNode) =
          dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
      if fieldDef.help.len > 0:
        p(class = "text-xs text-slate-500"): text fieldDef.help
      errorText(key)

proc projectSection(): VNode =
  buildHtml(section(class = "rounded-2xl border border-slate-200 bg-white p-6 shadow-sm")):
    tdiv:
      h2(class = "text-lg font-semibold text-slate-900"): text "Project information"
      p(class = "mt-1 text-sm text-slate-500"): text "Fields and sample columns adapt to these answers."
    tdiv(class = "mt-6 grid gap-5 md:grid-cols-2"):
      for fieldDef in visibleProjectFields(state.project):
        projectFieldView(fieldDef)

proc sampleCell(rowIndex: int; column: SampleColumnDef; value: string): VNode =
  buildHtml(td(class = "border-b border-slate-200 p-2 align-top")):
    input(class = "min-w-32 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-100", value = value):
      proc oninput(ev: Event; n: VNode) = dispatch(Msg(kind: setSampleCell, row: rowIndex, column: column.key, value: $n.value))
    let key = "sample[" & $(rowIndex + 1) & "]." & column.key
    if hasError(key):
      p(class = "mt-1 text-xs text-red-600"): text fieldError(key)

proc sampleTable(): VNode =
  let columns = visibleSampleColumns(state.project)
  buildHtml(section(class = "rounded-2xl border border-slate-200 bg-white shadow-sm")):
    tdiv(class = "flex flex-col gap-4 border-b border-slate-200 p-6 sm:flex-row sm:items-center sm:justify-between"):
      tdiv:
        h2(class = "text-lg font-semibold text-slate-900"): text "Samples"
        p(class = "mt-1 text-sm text-slate-500"): text $(state.samples.len) & " sample row(s). Columns reflect the project settings."
      tdiv(class = "flex flex-wrap gap-2"):
        button(class = "rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50", `type` = "button"):
          text "Download CSV template"
          proc onclick = downloadText("sequencing-samples.csv", templateCsv(state.project))
        label(class = "cursor-pointer rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"):
          text "Upload CSV"
          input(id = "csv-file", class = "hidden", `type` = "file", accept = ".csv,text/csv"):
            proc onchange = readFileInput("csv-file", proc(content: cstring) = dispatch(Msg(kind: csvLoaded, value: $content)))
    if state.csvMessage.len > 0:
      tdiv(class = "mx-6 mt-4 rounded-lg bg-blue-50 px-4 py-3 text-sm text-blue-800"): text state.csvMessage
    tdiv(class = "overflow-x-auto"):
      table(class = "min-w-full border-collapse"):
        thead(class = "bg-slate-50"):
          tr:
            th(class = "sticky left-0 border-b border-slate-200 px-3 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500"): text "#"
            for column in columns:
              th(class = "border-b border-slate-200 px-3 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500"): text column.label
            th(class = "border-b border-slate-200 px-3 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500"): text ""
        tbody:
          for i, row in state.samples:
            tr:
              td(class = "border-b border-slate-200 px-3 py-2 text-sm font-medium text-slate-500"): text $(i + 1)
              for column in columns:
                sampleCell(i, column, field(row, column.key))
              td(class = "border-b border-slate-200 px-3 py-2"):
                button(class = "rounded-md px-2 py-1 text-xs font-medium text-red-600 hover:bg-red-50", `type` = "button", disabled = state.samples.len <= 1):
                  text "Remove"
                  proc onclick = dispatch(Msg(kind: removeSample, row: i))
    tdiv(class = "flex flex-col gap-3 border-t border-slate-200 p-6 sm:flex-row sm:items-center sm:justify-between"):
      button(class = "rounded-lg bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800", `type` = "button"):
        text "+ Add sample"
        proc onclick = dispatch(Msg(kind: addSample))
      p(class = "text-xs text-slate-500"): text "Tip: download a template after changing the project settings so its columns stay synchronized."

proc summaryView(): VNode =
  let errorCount = state.errors.len
  buildHtml(tdiv(class = "rounded-2xl border border-slate-200 bg-white p-6 shadow-sm")):
    h2(class = "text-lg font-semibold text-slate-900"): text "Review & submit"
    tdiv(class = "mt-4 grid gap-3 text-sm sm:grid-cols-3"):
      tdiv(class = "rounded-lg bg-slate-50 p-3"): text "Samples: " & $state.samples.len
      tdiv(class = "rounded-lg bg-slate-50 p-3"): text "Validation errors: " & $errorCount
      tdiv(class = "rounded-lg bg-slate-50 p-3"): text "Read: " & $state.project.readType
    if state.submissionMessage.len > 0:
      tdiv(class = (if state.errors.len > 0: "mt-4 rounded-lg bg-red-50 p-4 text-sm text-red-800" else: "mt-4 rounded-lg bg-emerald-50 p-4 text-sm text-emerald-800")):
        text state.submissionMessage
    tdiv(class = "mt-5 flex justify-end"):
      button(class = "rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50", `type` = "button"):
        text "Validate & submit request"
        proc onclick = dispatch(Msg(kind: submit))

proc app(): VNode =
  buildHtml(tdiv(class = "min-h-screen")):
    header(class = "border-b border-slate-200 bg-white"):
      tdiv(class = "mx-auto max-w-7xl px-6 py-5"):
        p(class = "text-sm font-semibold uppercase tracking-wider text-blue-600"): text "Sequencing Core"
        h1(class = "mt-1 text-2xl font-bold tracking-tight text-slate-900"): text "DNA sequencing request"
        p(class = "mt-1 max-w-2xl text-sm text-slate-500"): text "Describe the project, enter samples, validate everything in your browser, and submit the request."
    main(class = "mx-auto max-w-7xl space-y-6 px-6 py-8"):
      projectSection()
      sampleTable()
      summaryView()

setRenderer app, "app"
