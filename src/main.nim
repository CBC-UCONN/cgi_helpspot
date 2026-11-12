import std/[jsffi, strutils]
import karax/[karaxdsl, vdom, kbase]
import karax/karax
import model, update, csvio

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

proc syncFieldFeedback(id, message: cstring) {.importjs: """
  (function(id, message) {
    const input = document.getElementById(id);
    const error = document.getElementById(id + '-error');
    if (!input || !error) return;
    if (error.firstChild) error.firstChild.nodeValue = message;
    input.setAttribute('aria-invalid', message ? 'true' : 'false');
    if (id.startsWith('sample[')) {
      input.classList.toggle('text-red-700', !!message);
      input.classList.toggle('ring-1', !!message);
      input.classList.toggle('ring-inset', !!message);
      input.classList.toggle('ring-red-400', !!message);
      input.classList.toggle('focus:ring-1', !message);
      input.classList.toggle('focus:ring-inset', !message);
      input.classList.toggle('focus:ring-blue-500', !message);
    } else {
      input.classList.toggle('border-red-400', !!message);
      input.classList.toggle('border-slate-300', !message);
    }
  })(#, #)
""".}

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
  buildHtml(tdiv(id = field & "-error", class = "mt-1 text-xs text-red-600", `aria-live` = "polite")):
    text message

proc projectFieldView(fieldDef: ProjectFieldDef): VNode =
  let key = fieldDef.key
  let value = state.project.field(key)
  case fieldDef.kind
  of textField, emailField:
    buildHtml(tdiv(class = "space-y-1")):
      labelText(fieldDef.label, key)
      input(id = key, class = inputClass(key), value = value, `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error", `type` = (if fieldDef.kind == emailField: "email" else: "text")):
        proc oninput(ev: Event; n: VNode) {.noredraw.} =
          dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
          syncFieldFeedback(cstring(key), cstring(fieldError(key)))
        proc onblur(ev: Event; n: VNode) =
          dispatch(Msg(kind: blurProjectField, column: key))
      if fieldDef.help.len > 0:
        p(class = "text-xs text-slate-500"): text fieldDef.help
      errorText(key)
  of selectField:
    buildHtml(tdiv(class = "space-y-1")):
      labelText(fieldDef.label, key)
      select(id = key, class = inputClass(key), value = value, `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
        proc onchange(ev: Event; n: VNode) =
          dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
        proc onblur(ev: Event; n: VNode) =
          dispatch(Msg(kind: blurProjectField, column: key))
        for optionValue in fieldDef.options:
          option(value = optionValue, selected = optionValue == value):
            text optionValue
      if fieldDef.help.len > 0:
        p(class = "text-xs text-slate-500"): text fieldDef.help
      errorText(key)
  of choiceField:
    buildHtml(fieldset(class = "space-y-2", `aria-describedby` = key & "-error")):
      legend(class = "block text-sm font-medium text-slate-700"): text fieldDef.label
      for optionValue in fieldDef.options:
        label(class = "flex items-start gap-2 text-sm text-slate-700"):
          input(`type` = "radio", name = key, value = optionValue, checked = optionValue == value, class = "mt-1", `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
            proc onchange(ev: Event; n: VNode) =
              dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
            proc onblur(ev: Event; n: VNode) =
              dispatch(Msg(kind: blurProjectField, column: key))
          span: text optionValue
      if fieldDef.help.len > 0:
        p(class = "text-xs text-slate-500"): text fieldDef.help
      errorText(key)
  of checkboxField:
    buildHtml(tdiv(class = "rounded-xl border border-slate-200 bg-slate-50 p-4")):
      label(class = "flex cursor-pointer items-start gap-3"):
        input(id = key, `type` = "checkbox", class = "mt-1 h-4 w-4 rounded border-slate-300", checked = value == "true", `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
          proc onchange(ev: Event; n: VNode) =
            dispatch(Msg(kind: setProjectField, column: key, boolValue: checkboxChecked(key)))
          proc onblur(ev: Event; n: VNode) =
            dispatch(Msg(kind: blurProjectField, column: key))
        span:
          span(class = "block text-sm font-medium text-slate-800"): text fieldDef.label
          if fieldDef.help.len > 0:
            span(class = "mt-1 block text-xs text-slate-500"): text fieldDef.help
      errorText(key)
  of textareaField:
    buildHtml(tdiv(class = "space-y-1")):
      labelText(fieldDef.label, key)
      textarea(id = key, class = inputClass(key), rows = "4", value = value, `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
        proc oninput(ev: Event; n: VNode) {.noredraw.} =
          dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
          syncFieldFeedback(cstring(key), cstring(fieldError(key)))
        proc onblur(ev: Event; n: VNode) =
          dispatch(Msg(kind: blurProjectField, column: key))
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
  let key = "sample[" & $(rowIndex + 1) & "]." & column.key
  buildHtml(td(class = column.widthClass & " border border-slate-300 p-0 align-top")):
    input(id = key, size = "1", class = (if hasError(key): "block w-full min-w-0 border-0 bg-white px-2 py-1.5 text-sm text-red-700 outline-none ring-1 ring-inset ring-red-400" else: "block w-full min-w-0 border-0 bg-white px-2 py-1.5 text-sm outline-none focus:ring-1 focus:ring-inset focus:ring-blue-500"), value = value, `aria-label` = column.label & ", row " & $(rowIndex + 1), `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
      proc oninput(ev: Event; n: VNode) {.noredraw.} =
        dispatch(Msg(kind: setSampleCell, row: rowIndex, column: column.key, value: $n.value))
        for index in 0 ..< state.samples.len:
          let cellKey = "sample[" & $(index + 1) & "]." & column.key
          syncFieldFeedback(cstring(cellKey), cstring(fieldError(cellKey)))
      proc onblur(ev: Event; n: VNode) = dispatch(Msg(kind: blurSampleCell, row: rowIndex, column: column.key))
    errorText(key)

proc removeSampleButton(rowIndex: int): VNode =
  buildHtml(button(class = "h-8 w-8 text-sm font-bold text-red-600 hover:bg-red-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-red-600", `type` = "button", `aria-label` = "Remove row " & $(rowIndex + 1), title = "Remove row")):
    text "X"
    proc onclick = dispatch(Msg(kind: removeSample, row: rowIndex))

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
      table(class = "w-max table-auto border-collapse"):
        thead(class = "bg-slate-50"):
          tr:
            th(class = "w-9 border border-slate-300 px-1 py-2 text-center text-xs font-medium text-slate-500"): text "#"
            for column in columns:
              th(class = column.widthClass & " border border-slate-300 px-2 py-2 text-left text-xs font-semibold text-slate-600"): text column.label
            th(class = "w-8 border border-slate-300 p-0"): text ""
        tbody(index = state.sampleRevision):
          for i, row in state.samples:
            tr:
              td(class = "w-9 border border-slate-300 px-1 py-1 text-center align-top text-xs text-slate-500"): text $(i + 1)
              for column in columns:
                sampleCell(i, column, field(row, column.key))
              td(class = "w-8 border border-slate-300 p-0 align-top"):
                removeSampleButton(i)
    tdiv(class = "flex flex-col gap-3 border-t border-slate-200 p-6 sm:flex-row sm:items-center sm:justify-between"):
      button(class = "rounded-lg bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800", `type` = "button"):
        text "+ Add sample"
        proc onclick = dispatch(Msg(kind: addSample))
      p(class = "text-xs text-slate-500"): text "Tip: download a template after changing the project settings so its columns stay synchronized."

proc app(): VNode =
  buildHtml(tdiv(class = "min-h-screen")):
    header(class = "border-b border-slate-200 bg-white"):
      tdiv(class = "mx-auto flex max-w-7xl flex-wrap items-start justify-between gap-4 px-6 py-5"):
        tdiv:
          p(class = "text-sm font-semibold uppercase tracking-wider text-blue-600"): text "UConn Center for Genome Innovation"
          h1(class = "mt-1 text-2xl font-bold tracking-tight text-slate-900"): text "Sequencing Request Form"
          p(class = "mt-1 max-w-2xl text-sm text-slate-500"): text "Enter project and sample details below."
        button(class = "rounded-md bg-blue-700 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-800", `type` = "button"):
          text "Submit request"
          proc onclick = dispatch(Msg(kind: submitRequest))
    main(class = "space-y-6 px-6 py-8"):
      tdiv(class = "mx-auto max-w-7xl space-y-6"):
        if state.submissionMessage.len > 0:
          p(class = "text-sm font-medium text-slate-800", role = "status"): text state.submissionMessage
        projectSection()
      sampleTable()

setRenderer app, "app"
