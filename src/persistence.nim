import std/[json, tables, sets]
import model

proc encodeModel*(state: AppModel): string =
  var project = newJObject()
  for key, value in state.project:
    project[key] = %value
  var samples = newJArray()
  for row in state.samples:
    var sample = newJObject()
    for key, value in row:
      sample[key] = %value
    samples.add sample
  var errors = newJArray()
  for error in state.errors:
    errors.add %*{"field": error.field, "message": error.message}
  var editedFields = newJArray()
  for key in state.editedFields:
    editedFields.add %key
  var liveFields = newJArray()
  for key in state.liveFields:
    liveFields.add %key
  $(%*{"version": 1, "project": project, "samples": samples,
      "errors": errors, "editedFields": editedFields, "liveFields": liveFields,
      "csvMessage": state.csvMessage, "submissionMessage": state.submissionMessage})

proc decodeModel*(encoded: string; state: var AppModel): bool =
  try:
    let data = parseJson(encoded)
    if data.kind != JObject or data["version"].getInt() != 1 or
        data["project"].kind != JObject or data["samples"].kind != JArray or
        data["errors"].kind != JArray or data["editedFields"].kind != JArray or
        data["liveFields"].kind != JArray or data["samples"].len == 0:
      return false
    var restored = initialModel()
    for fieldDef in projectSchema:
      if data["project"].hasKey(fieldDef.key):
        let value = data["project"][fieldDef.key].getStr()
        if fieldDef.options.len == 0 or value.len == 0 or value in fieldDef.options:
          restored.project[fieldDef.key] = value
    restored.samples = @[]
    for sample in data["samples"]:
      if sample.kind != JObject:
        return false
      var row = emptySample()
      for column in sampleColumnSchema:
        if sample.hasKey(column.key):
          row[column.key] = sample[column.key].getStr()
      restored.samples.add row
    for error in data["errors"]:
      restored.errors.add ValidationError(field: error["field"].getStr(), message: error["message"].getStr())
    for key in data["editedFields"]:
      restored.editedFields.incl key.getStr()
    for key in data["liveFields"]:
      restored.liveFields.incl key.getStr()
    restored.csvMessage = data["csvMessage"].getStr()
    restored.submissionMessage = data["submissionMessage"].getStr()
    state = restored
    true
  except CatchableError:
    false