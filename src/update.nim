import std/[strutils, tables, sets]
import model
import validation
import csvio

type
  MsgKind* = enum
    setProjectField, blurProjectField,
    addSample, removeSample, setSampleCell, blurSampleCell,
    downloadTemplate, csvLoaded, submitRequest

  Msg* = object
    kind*: MsgKind
    row*: int
    column*: string
    value*: string
    boolValue*: bool

proc setProjectValue(project: var ProjectForm; key, value: string; boolValue: bool) =
  for fieldDef in projectSchema:
    if fieldDef.key == key:
      if fieldDef.kind == checkboxField:
        project[key] = $boolValue
      elif fieldDef.options.len == 0 or value in fieldDef.options:
        project[key] = value
      return

proc replaceFieldErrors(m: var AppModel; key: string; errors: seq[ValidationError]) =
  var remaining: seq[ValidationError]
  for error in m.errors:
    if error.field != key: remaining.add error
  for error in errors:
    if error.field == key: remaining.add error
  m.errors = remaining

proc remapRowKey(key: string; removedRow: int): string =
  if not key.startsWith("sample["): return key
  let endIndex = key.find("].")
  if endIndex < 7: return key
  try:
    let row = parseInt(key[7 ..< endIndex]) - 1
    if row == removedRow: return ""
    if row > removedRow: return "sample[" & $row & key[endIndex .. ^1]
  except ValueError:
    discard
  key

proc hasFieldError(m: AppModel; key: string): bool =
  for error in m.errors:
    if error.field == key: return true

proc refreshSampleColumn(m: var AppModel; key: string; column: string) =
  let errors = validateSampleColumn(m.samples, m.project, column)
  var refresh = @[key]
  for error in m.errors:
    if error.field.startsWith("sample[") and error.field.endsWith("]." & column) and error.field != key:
      refresh.add error.field
  for fieldKey in refresh:
    m.replaceFieldErrors(fieldKey, errors)

proc sendRequest*(model: AppModel) =
  discard

proc update*(m: var AppModel; msg: Msg) =
  case msg.kind
  of setProjectField:
    setProjectValue(m.project, msg.column, msg.value, msg.boolValue)
    m.editedFields.incl(msg.column)
    if msg.column in m.liveFields:
      m.replaceFieldErrors(msg.column, validateProjectField(m.project, msg.column))
    m.submissionMessage = ""
  of blurProjectField:
    if msg.column in m.editedFields:
      m.replaceFieldErrors(msg.column, validateProjectField(m.project, msg.column))
      if m.hasFieldError(msg.column): m.liveFields.incl(msg.column)
      else: m.liveFields.excl(msg.column)
  of addSample:
    m.samples.add emptySample()
    m.submissionMessage = ""
  of removeSample:
    if msg.row >= 0 and msg.row < m.samples.len:
      m.samples.delete msg.row
      if m.samples.len == 0:
        m.samples.add emptySample()
      inc m.sampleRevision
      var remaining: seq[ValidationError]
      for error in m.errors:
        let key = remapRowKey(error.field, msg.row)
        if key.len > 0:
          remaining.add ValidationError(field: key, message: error.message)
      m.errors = remaining
      var retained = initHashSet[string]()
      for key in m.editedFields:
        let remapped = remapRowKey(key, msg.row)
        if remapped.len > 0: retained.incl(remapped)
      m.editedFields = retained
      var live = initHashSet[string]()
      for key in m.liveFields:
        let remapped = remapRowKey(key, msg.row)
        if remapped.len > 0: live.incl(remapped)
      m.liveFields = live
      let errors = validateSamples(m.samples, m.project)
      var keys: seq[string]
      for error in m.errors:
        if error.field.startsWith("sample[") and error.field notin keys:
          keys.add error.field
      for key in keys: m.replaceFieldErrors(key, errors)
      m.submissionMessage = ""
  of setSampleCell:
    if msg.row >= 0 and msg.row < m.samples.len:
      setSampleValue(m.samples[msg.row], msg.column, msg.value)
      let key = "sample[" & $(msg.row + 1) & "]." & msg.column
      m.editedFields.incl(key)
      if key in m.liveFields: m.refreshSampleColumn(key, msg.column)
      elif msg.column == "sample_id":
        var refresh: seq[string]
        for error in m.errors:
          if error.field.startsWith("sample[") and error.field.endsWith("].sample_id"):
            refresh.add error.field
        if refresh.len > 0:
          let errors = validateSampleColumn(m.samples, m.project, msg.column)
          for fieldKey in refresh: m.replaceFieldErrors(fieldKey, errors)
      m.submissionMessage = ""
  of blurSampleCell:
    if msg.row >= 0 and msg.row < m.samples.len:
      let key = "sample[" & $(msg.row + 1) & "]." & msg.column
      if key in m.editedFields:
        m.refreshSampleColumn(key, msg.column)
        if m.hasFieldError(key): m.liveFields.incl(key)
        else: m.liveFields.excl(key)
  of downloadTemplate: discard
  of csvLoaded:
    let parsed = parseCsv(msg.value, m.project)
    if parsed.errors.len > 0:
      m.csvMessage = parsed.errors.join(" ")
    else:
      m.samples = parsed.rows
      inc m.sampleRevision
      m.csvMessage = "Loaded " & $m.samples.len & " sample(s) from CSV."
      var remaining: seq[ValidationError]
      for error in m.errors:
        if not error.field.startsWith("sample["): remaining.add error
      m.errors = remaining
      var retained = initHashSet[string]()
      for key in m.editedFields:
        if not key.startsWith("sample["): retained.incl(key)
      m.editedFields = retained
      var live = initHashSet[string]()
      for key in m.liveFields:
        if not key.startsWith("sample["): live.incl(key)
      m.liveFields = live
      m.submissionMessage = ""
  of submitRequest:
    m.errors = validateAll(m)
    for error in m.errors: m.liveFields.incl(error.field)
    if m.errors.len == 0:
      sendRequest(m)
      m.submissionMessage = "Validation passed. Submission is not yet connected."
    else:
      m.submissionMessage = "Please correct the highlighted fields."
