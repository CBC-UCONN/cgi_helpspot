import std/[strutils, tables, sets]
import model
import validation
import csvio

type
  MsgKind* = enum
    setProjectField, blurProjectField,
    addSample, removeSample, setSampleCell, blurSampleCell, fillSampleCells,
    downloadTemplate, csvLoaded, submitRequest, submissionFinished, resetRequest

  Msg* = object
    kind*: MsgKind
    row*: int
    targetRow*: int
    column*: string
    value*: string
    boolValue*: bool

proc setProjectValue(project: var ProjectForm; key, value: string; boolValue: bool) =
  for fieldDef in projectSchema:
    if fieldDef.key == key:
      if fieldDef.kind == checkboxField:
        project[key] = $boolValue
      elif fieldDef.options.len == 0 or value in fieldDef.options or (fieldDef.kind == selectField and value.len == 0):
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

proc sampleFillValue*(value: string; distance: int; hasOptions: bool): string =
  if hasOptions or distance == 0 or value.len == 0:
    return value
  var numberStart = value.len
  while numberStart > 0 and value[numberStart - 1] in {'0'..'9'}:
    dec numberStart
  if numberStart == 0 or numberStart == value.len:
    return value
  var digits = value[numberStart .. ^1]
  if distance < 0:
    let width = digits.len
    var amount = $(-(distance + 1))
    var carry = 1
    var index = amount.high
    while index >= 0 and carry > 0:
      let sum = ord(amount[index]) - ord('0') + carry
      amount[index] = chr(ord('0') + sum mod 10)
      carry = sum div 10
      dec index
    if carry > 0:
      amount = "1" & amount
    let length = max(digits.len, amount.len)
    digits = repeat('0', length - digits.len) & digits
    amount = repeat('0', length - amount.len) & amount
    let negative = digits < amount
    if negative:
      swap(digits, amount)
    var borrow = 0
    for digitIndex in countdown(length - 1, 0):
      var difference = ord(digits[digitIndex]) - ord(amount[digitIndex]) - borrow
      borrow = 0
      if difference < 0:
        difference += 10
        borrow = 1
      digits[digitIndex] = chr(ord('0') + difference)
    while digits.len > width and digits[0] == '0':
      digits = digits[1 .. ^1]
    return value[0 ..< numberStart] & (if negative: "-" else: "") & digits
  var carry = distance
  var index = digits.high
  while index >= 0 and carry > 0:
    let sum = ord(digits[index]) - ord('0') + carry mod 10
    digits[index] = chr(ord('0') + sum mod 10)
    carry = carry div 10 + sum div 10
    dec index
  if carry > 0:
    digits = $carry & digits
  value[0 ..< numberStart] & digits

proc refreshSampleColumn(m: var AppModel; key: string; column: string) =
  let errors = validateSampleColumn(m.samples, m.project, column)
  var refresh = @[key]
  for error in m.errors:
    if error.field.startsWith("sample[") and error.field.endsWith("]." & column) and error.field != key:
      refresh.add error.field
  for fieldKey in refresh:
    m.replaceFieldErrors(fieldKey, errors)

proc update*(m: var AppModel; msg: Msg) =
  case msg.kind
  of resetRequest:
    let revision = m.sampleRevision + 1
    m = initialModel()
    m.sampleRevision = revision
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
  of fillSampleCells:
    if msg.row >= 0 and msg.row < m.samples.len and msg.targetRow >= 0 and msg.targetRow < m.samples.len:
      var columnVisible = false
      var hasOptions = false
      for column in visibleSampleColumns(m.project):
        if column.key == msg.column:
          columnVisible = true
          hasOptions = column.options.len > 0
          break
      if columnVisible:
        let value = m.samples[msg.row].field(msg.column)
        for row in min(msg.row, msg.targetRow) .. max(msg.row, msg.targetRow):
          if row != msg.row:
            let filledValue = sampleFillValue(value, row - msg.row, hasOptions)
            update(m, Msg(kind: setSampleCell, row: row, column: msg.column, value: filledValue))
            update(m, Msg(kind: blurSampleCell, row: row, column: msg.column))
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
    if m.submitting: return
    m.errors = validateAll(m)
    for error in m.errors: m.liveFields.incl(error.field)
    if m.errors.len == 0:
      m.submitting = true
      m.submissionMessage = "Submitting request..."
    else:
      m.submissionMessage = "Please correct the highlighted fields."
  of submissionFinished:
    if m.submitting:
      m.submitting = false
      m.submissionMessage = msg.value
