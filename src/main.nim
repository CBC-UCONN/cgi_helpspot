import std/[jsffi, strutils]
import karax/[karaxdsl, vdom, kbase]
import karax/karax
import model, update, csvio, persistence

proc readSavedModel(): cstring {.importjs: """
  (function() {
    try { return localStorage.getItem('seqrequest.model.v1') || ''; }
    catch (_) { return null; }
  })()
""".}

proc saveModel(data: cstring): bool {.importjs: """
  (function(data) {
    try { localStorage.setItem('seqrequest.model.v1', data); return true; }
    catch (_) { return false; }
  })(#)
""".}

proc clearSavedModel(): bool {.importjs: """
  (function() {
    try { localStorage.removeItem('seqrequest.model.v1'); return true; }
    catch (_) { return false; }
  })()
""".}

proc confirmReset(): bool {.importjs: "window.confirm('Are you sure you want to reset? Any existing input will be lost.')".}

proc syncStorageMessage(message: cstring) {.importjs: """
  (function(message) {
    const notice = document.getElementById('storage-message');
    if (notice) notice.textContent = message;
  })(#)
""".}

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

proc navigateSampleCell(event: Event) {.importjs: """
  (function(event) {
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey || event.isComposing) return;
    const control = event.target;
    if (!control.matches('input, select')) return;
    const cell = control.closest('td');
    const row = cell && cell.parentElement;
    const body = row && row.parentElement;
    if (!body || body.tagName !== 'TBODY') return;
    let rowIndex = row.sectionRowIndex;
    let columnIndex = cell.cellIndex;
    switch (event.key) {
      case 'Enter':
      case 'ArrowDown': rowIndex++; break;
      case 'ArrowUp': rowIndex--; break;
      case 'ArrowRight': columnIndex++; break;
      case 'ArrowLeft': columnIndex--; break;
      default: return;
    }
    const targetRow = body.rows[rowIndex];
    const targetCell = targetRow && targetRow.cells[columnIndex];
    const target = targetCell && targetCell.querySelector('input, select');
    if (target) {
      event.preventDefault();
      target.focus();
    }
  })(#)
""".}

proc startFillDrag(event: Event; callback: proc(targetRow: int) {.closure.}; previewValue: proc(sourceValue: cstring; distance: int): cstring {.closure.}) {.importjs: """
  (function(event, callback, previewValue) {
    if (event.button !== 0) return;
    event.preventDefault();
    const cell = event.currentTarget.closest('td');
    const body = cell.closest('tbody');
    const sourceRow = cell.parentElement.sectionRowIndex;
    const column = cell.cellIndex;
    const sourceValue = cell.querySelector('input, select').value;
    let targetRow = sourceRow;
    const highlighted = [];
    function clearPreview() {
      for (const item of highlighted) {
        item.cell.style.boxShadow = item.shadow;
        if (item.preview) item.preview.remove();
      }
      highlighted.length = 0;
    }
    function move(moveEvent) {
      const element = document.elementFromPoint(moveEvent.clientX, moveEvent.clientY);
      const row = element && element.closest('tr');
      if (!row || row.parentElement !== body) return;
      targetRow = row.sectionRowIndex;
      clearPreview();
      for (let index = Math.min(sourceRow, targetRow); index <= Math.max(sourceRow, targetRow); index++) {
        const selectedCell = body.rows[index].cells[column];
        let preview = null;
        if (index !== sourceRow) {
          const control = selectedCell.querySelector('input, select');
          preview = document.createElement('div');
          preview.className = 'pointer-events-none absolute left-0 top-0 z-[5] w-full overflow-hidden whitespace-nowrap bg-white px-2 py-1.5 text-sm';
          preview.style.height = control.offsetHeight + 'px';
          preview.setAttribute('aria-hidden', 'true');
          preview.textContent = previewValue(sourceValue, index - sourceRow);
          selectedCell.appendChild(preview);
        }
        highlighted.push({cell: selectedCell, shadow: selectedCell.style.boxShadow, preview});
        selectedCell.style.boxShadow = 'inset 0 0 0 2px rgb(37, 99, 235)';
      }
    }
    function cleanup() {
      clearPreview();
      document.removeEventListener('mousemove', move);
      document.removeEventListener('mouseup', finish);
      document.removeEventListener('keydown', cancel);
      window.removeEventListener('blur', cleanup);
    }
    function finish() {
      cleanup();
      if (targetRow !== sourceRow) callback(targetRow);
    }
    function cancel(keyEvent) {
      if (keyEvent.key === 'Escape') cleanup();
    }
    document.addEventListener('mousemove', move);
    document.addEventListener('mouseup', finish);
    document.addEventListener('keydown', cancel);
    window.addEventListener('blur', cleanup);
  })(#, #, #)
""".}

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
var storageMessage = ""
let savedModel = readSavedModel()
if savedModel == nil:
  storageMessage = "Progress cannot be saved in this browser."
elif ($savedModel).len > 0 and not decodeModel($savedModel, state):
  storageMessage = "Saved progress could not be restored."

proc dispatch(msg: Msg) =
  if msg.kind == resetRequest:
    if not clearSavedModel():
      storageMessage = "Progress could not be cleared. Reset was cancelled."
      syncStorageMessage(cstring(storageMessage))
      return
    update(state, msg)
    storageMessage = ""
    syncStorageMessage(cstring(storageMessage))
    return
  update(state, msg)
  if not saveModel(cstring(encodeModel(state))):
    storageMessage = "Progress could not be saved in this browser."
  else:
    storageMessage = ""
  syncStorageMessage(cstring(storageMessage))

proc fieldError(field: string): string =
  for e in state.errors:
    if e.field == field: return e.message
  ""

proc hasError(field: string): bool = fieldError(field).len > 0

proc inputClass(field: string): string =
  "w-full rounded-lg border bg-white px-3 py-2 text-sm shadow-sm outline-none transition focus:ring-2 " &
  (if hasError(field): "border-red-400 focus:border-red-500 focus:ring-red-100" else: "border-slate-300 focus:border-blue-500 focus:ring-blue-100")

proc helpInfo(id, help: string): VNode =
  let tooltipId = id & "-help"
  buildHtml(span(class = "group relative inline-flex shrink-0 align-middle")):
    button(`type` = "button", class = "inline-flex h-4 w-4 items-center justify-center rounded-full border border-slate-400 text-[10px] font-semibold leading-none text-slate-600 hover:bg-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600", `aria-label` = "Information", `aria-describedby` = tooltipId):
      text "i"
    span(id = tooltipId, role = "tooltip", class = "absolute left-0 top-full z-30 mt-2 hidden w-64 max-w-[calc(100vw-2rem)] rounded-md bg-slate-900 px-3 py-2 text-xs font-normal leading-relaxed text-white shadow-lg group-hover:block group-focus-within:block"):
      text help

proc labelText(label, field, help: string): VNode =
  buildHtml(tdiv(class = "mb-1 flex items-center gap-1")):
    label(`for` = field, class = "block text-sm font-medium text-slate-700"):
      text label
    if help.len > 0:
      helpInfo("project-" & field, help)

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
      labelText(fieldDef.label, key, fieldDef.help)
      input(id = key, class = inputClass(key), value = value, `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error", `type` = (if fieldDef.kind == emailField: "email" else: "text")):
        proc oninput(ev: Event; n: VNode) {.noredraw.} =
          dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
          syncFieldFeedback(cstring(key), cstring(fieldError(key)))
        proc onblur(ev: Event; n: VNode) =
          dispatch(Msg(kind: blurProjectField, column: key))
      errorText(key)
  of selectField:
    buildHtml(tdiv(class = "space-y-1")):
      labelText(fieldDef.label, key, fieldDef.help)
      select(id = key, class = inputClass(key), value = value, `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
        proc onchange(ev: Event; n: VNode) =
          dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
        proc onblur(ev: Event; n: VNode) =
          dispatch(Msg(kind: blurProjectField, column: key))
        for optionValue in fieldDef.options:
          option(value = optionValue, selected = optionValue == value):
            text optionValue
      errorText(key)
  of choiceField:
    buildHtml(fieldset(class = "space-y-2", `aria-describedby` = key & "-error")):
      legend(class = "flex items-center gap-1 text-sm font-medium text-slate-700"):
        text fieldDef.label
        if fieldDef.help.len > 0:
          helpInfo("project-" & key, fieldDef.help)
      for optionValue in fieldDef.options:
        label(class = "flex items-start gap-2 text-sm text-slate-700"):
          input(`type` = "radio", name = key, value = optionValue, checked = optionValue == value, class = "mt-1", `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
            proc onchange(ev: Event; n: VNode) =
              dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
            proc onblur(ev: Event; n: VNode) =
              dispatch(Msg(kind: blurProjectField, column: key))
          span: text optionValue
      errorText(key)
  of checkboxField:
    buildHtml(tdiv(class = "rounded-xl border border-slate-200 bg-slate-50 p-4")):
      tdiv(class = "flex items-start gap-2"):
        label(class = "flex cursor-pointer items-start gap-3"):
          input(id = key, `type` = "checkbox", class = "mt-1 h-4 w-4 rounded border-slate-300", checked = value == "true", `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
            proc onchange(ev: Event; n: VNode) =
              dispatch(Msg(kind: setProjectField, column: key, boolValue: checkboxChecked(key)))
            proc onblur(ev: Event; n: VNode) =
              dispatch(Msg(kind: blurProjectField, column: key))
          span(class = "block text-sm font-medium text-slate-800"): text fieldDef.label
        if fieldDef.help.len > 0:
          helpInfo("project-" & key, fieldDef.help)
      errorText(key)
  of textareaField:
    buildHtml(tdiv(class = "space-y-1")):
      labelText(fieldDef.label, key, fieldDef.help)
      textarea(id = key, class = inputClass(key), rows = "4", value = value, `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
        proc oninput(ev: Event; n: VNode) {.noredraw.} =
          dispatch(Msg(kind: setProjectField, column: key, value: $n.value))
          syncFieldFeedback(cstring(key), cstring(fieldError(key)))
        proc onblur(ev: Event; n: VNode) =
          dispatch(Msg(kind: blurProjectField, column: key))
      errorText(key)

proc projectSection(): VNode =
  let fields = visibleProjectFields(state.project)
  buildHtml(section(class = "rounded-2xl border border-slate-200 bg-white p-6 shadow-sm")):
    tdiv:
      h2(class = "text-xl font-semibold text-slate-900"): text "Project information"
      p(class = "mt-1 text-sm text-slate-500"): text "Fields and sample columns adapt to these answers."
    tdiv(class = "mt-6 grid gap-5 md:grid-cols-2"):
      for fieldDef in fields:
        if fieldDef.fullWidth:
          tdiv(class = "md:col-span-2"):
            projectFieldView(fieldDef)
        else:
          projectFieldView(fieldDef)

proc sampleCell(rowIndex: int; column: SampleColumnDef; value: string): VNode =
  let key = "sample[" & $(rowIndex + 1) & "]." & column.key
  let cellClass = if hasError(key): "block w-full min-w-0 border-0 bg-white px-2 py-1.5 text-sm text-red-700 outline-none ring-1 ring-inset ring-red-400" else: "block w-full min-w-0 border-0 bg-white px-2 py-1.5 text-sm outline-none focus:ring-1 focus:ring-inset focus:ring-blue-500"
  buildHtml(td(class = column.widthClass & " group relative border border-slate-300 p-0 align-top")):
    if column.options.len > 0:
      select(id = key, class = cellClass, value = value, `aria-label` = column.label & ", row " & $(rowIndex + 1), `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
        proc onchange(ev: Event; n: VNode) =
          dispatch(Msg(kind: setSampleCell, row: rowIndex, column: column.key, value: $n.value))
        proc onblur(ev: Event; n: VNode) = dispatch(Msg(kind: blurSampleCell, row: rowIndex, column: column.key))
        option(value = "", selected = value.len == 0): text ""
        if value.len > 0 and value notin column.options:
          option(value = value, selected = true): text value
        for optionValue in column.options:
          option(value = optionValue, selected = optionValue == value): text optionValue
    else:
      input(id = key, size = "1", class = cellClass, value = value, `aria-label` = column.label & ", row " & $(rowIndex + 1), `aria-invalid` = (if hasError(key): "true" else: "false"), `aria-describedby` = key & "-error"):
        proc oninput(ev: Event; n: VNode) {.noredraw.} =
          dispatch(Msg(kind: setSampleCell, row: rowIndex, column: column.key, value: $n.value))
          for index in 0 ..< state.samples.len:
            let cellKey = "sample[" & $(index + 1) & "]." & column.key
            syncFieldFeedback(cstring(cellKey), cstring(fieldError(cellKey)))
        proc onblur(ev: Event; n: VNode) = dispatch(Msg(kind: blurSampleCell, row: rowIndex, column: column.key))
    errorText(key)
    button(`type` = "button", tabindex = "-1", class = "pointer-events-none absolute bottom-0 right-0 z-10 h-3 w-3 cursor-crosshair border border-white bg-blue-600 opacity-0 group-focus-within:pointer-events-auto group-focus-within:opacity-100", title = "Drag to copy up or down", `aria-label` = "Drag to copy " & column.label & " from row " & $(rowIndex + 1)):
      proc onmousedown(ev: Event; n: VNode) {.noredraw.} =
        startFillDrag(ev,
          proc(targetRow: int) =
            dispatch(Msg(kind: fillSampleCells, row: rowIndex, targetRow: targetRow, column: column.key))
            redraw(),
          proc(sourceValue: cstring; distance: int): cstring =
            cstring(sampleFillValue($sourceValue, distance, column.options.len > 0)))

proc removeSampleButton(rowIndex: int): VNode =
  buildHtml(button(class = "h-8 w-8 text-sm font-bold text-red-600 hover:bg-red-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-red-600", `type` = "button", `aria-label` = "Remove row " & $(rowIndex + 1), title = "Remove row")):
    text "X"
    proc onclick = dispatch(Msg(kind: removeSample, row: rowIndex))

proc sampleTable(): VNode =
  let columns = visibleSampleColumns(state.project)
  let dependenciesSelected = spreadsheetDependenciesSelected(state.project)
  var dependencyLabels: seq[string]
  for fieldDef in projectSchema:
    if fieldDef.spreadsheetDependency:
      dependencyLabels.add fieldDef.label
  let dependencyMessage = "Choose options for " & dependencyLabels.join(" and ") & " before entering sample data."
  buildHtml(section(class = "rounded-2xl border border-slate-200 bg-white shadow-sm")):
    tdiv(class = "flex flex-col gap-4 border-b border-slate-200 p-6 sm:flex-row sm:items-center sm:justify-between"):
      tdiv:
        h2(class = "text-xl font-semibold text-slate-900"): text "Samples"
      tdiv(class = "flex flex-wrap gap-2"):
        button(class = (if dependenciesSelected: "rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50" else: "cursor-not-allowed rounded-lg border border-slate-300 bg-slate-100 px-3 py-2 text-sm font-medium text-slate-400"), `type` = "button", disabled = not dependenciesSelected):
          text "Download CSV template"
          proc onclick = downloadText("sequencing-samples.csv", templateCsv(state.project))
        label(class = (if dependenciesSelected: "cursor-pointer rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50" else: "cursor-not-allowed rounded-lg border border-slate-300 bg-slate-100 px-3 py-2 text-sm font-medium text-slate-400")):
          text "Upload CSV"
          input(id = "csv-file", class = "hidden", `type` = "file", accept = ".csv,text/csv", disabled = not dependenciesSelected):
            proc onchange = readFileInput("csv-file", proc(content: cstring) = dispatch(Msg(kind: csvLoaded, value: $content)))
    if state.csvMessage.len > 0:
      tdiv(class = "mx-6 mt-4 rounded-lg bg-blue-50 px-4 py-3 text-sm text-blue-800"): text state.csvMessage
    tdiv(class = "relative overflow-x-auto"):
      tdiv(class = (if dependenciesSelected: "" else: "pointer-events-none select-none blur-sm"), `aria-hidden` = (if dependenciesSelected: "false" else: "true")):
        table(class = "w-max table-auto border-collapse"):
          if dependenciesSelected:
            thead(class = "bg-slate-50"):
              tr:
                th(class = "w-9 border border-slate-300 px-1 py-2 text-center text-xs font-medium text-slate-500"): text "#"
                for column in columns:
                  th(class = column.widthClass & " border border-slate-300 px-2 py-2 text-left text-xs font-semibold text-slate-600"):
                    tdiv(class = "inline-flex items-center gap-1"):
                      text column.label
                      if column.help.len > 0:
                        helpInfo("sample-" & column.key, column.help)
                th(class = "w-8 border border-slate-300 p-0"): text ""
          tbody(index = state.sampleRevision):
            proc onkeydown(ev: Event; n: VNode) {.noredraw.} =
              navigateSampleCell(ev)
            for i, row in state.samples:
              tr:
                td(class = "w-9 border border-slate-300 px-1 py-1 text-center align-top text-xs text-slate-500"):
                  text $(i + 1)
                for column in columns:
                  if dependenciesSelected:
                    sampleCell(i, column, field(row, column.key))
                  else:
                    td(class = column.widthClass & " border border-slate-300 p-0 align-top"):
                      tdiv(class = "h-8")
                td(class = "w-8 border border-slate-300 p-0 align-top"):
                  if dependenciesSelected:
                    removeSampleButton(i)
                  else:
                    tdiv(class = "h-8")
      if not dependenciesSelected:
        tdiv(class = "pointer-events-none absolute inset-0 z-10 flex min-h-64 items-center justify-center px-6 text-center", role = "status"):
          p(class = "max-w-md text-sm font-semibold text-slate-900 drop-shadow-[0_1px_2px_rgba(255,255,255,0.95)]"):
            text dependencyMessage
    tdiv(class = "flex flex-col gap-3 border-t border-slate-200 p-6 sm:flex-row sm:items-center sm:justify-between"):
      button(class = (if dependenciesSelected: "rounded-lg bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800" else: "cursor-not-allowed rounded-lg bg-slate-400 px-4 py-2 text-sm font-semibold text-white"), `type` = "button", disabled = not dependenciesSelected):
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
        p(id = "storage-message", class = "text-sm font-medium text-red-700", role = "status"): text storageMessage
        if state.submissionMessage.len > 0:
          p(class = "text-sm font-medium text-slate-800", role = "status"): text state.submissionMessage
        projectSection()
      sampleTable()
      tdiv(class = "flex justify-end"):
        button(class = "rounded-md border border-red-300 bg-white px-4 py-2 text-sm font-semibold text-red-700 hover:bg-red-50", `type` = "button"):
          text "Reset"
          proc onclick =
            if confirmReset(): dispatch(Msg(kind: resetRequest))

setRenderer app, "app"
