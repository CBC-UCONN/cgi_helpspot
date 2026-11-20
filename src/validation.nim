import std/[tables, unicode]
import model

proc validateProjectField*(project: ProjectForm; key: string): seq[ValidationError] =
  for fieldDef in visibleProjectFields(project):
    if fieldDef.key == key:
      let value = unicode.strip(project.field(key))
      if (fieldDef.required or fieldDef.spreadsheetDependency) and value.len == 0:
        result.add ValidationError(field: key, message: fieldDef.label & " is required.")
      for validator in fieldDef.validators:
        let message = validator(value)
        if message.len > 0:
          result.add ValidationError(field: key, message: message)
      break

proc validateSampleColumn*(rows: seq[SampleRow]; project: ProjectForm; key: string): seq[ValidationError] =
  for column in visibleSampleColumns(project):
    if column.key == key:
      var seen = initTable[string, int]()
      for index, row in rows:
        let value = unicode.strip(row.field(key))
        let errorKey = "sample[" & $(index + 1) & "]." & key
        if column.required and value.strip().len == 0:
          result.add ValidationError(field: errorKey, message: column.label & " is required.")
        for validator in column.validators:
          let message = validator(value)
          if message.len > 0:
            result.add ValidationError(field: errorKey, message: message)
        if key == "sample_id":
          let id = value.strip()
          if id.len > 0:
            if seen.hasKey(id):
              result.add ValidationError(field: errorKey, message: "Sample ID duplicates row " & $(seen[id] + 1) & ".")
            else:
              seen[id] = index
      break

proc validateProject*(project: ProjectForm): seq[ValidationError] =
  for fieldDef in visibleProjectFields(project):
    let value = unicode.strip(project.field(fieldDef.key))
    if (fieldDef.required or fieldDef.spreadsheetDependency) and value.strip().len == 0:
      result.add ValidationError(field: fieldDef.key, message: fieldDef.label & " is required.")
    for validator in fieldDef.validators:
      let message = validator(value)
      if message.len > 0:
        result.add ValidationError(field: fieldDef.key, message: message)

proc validateSample*(row: SampleRow; index: int; project: ProjectForm): seq[ValidationError] =
  let prefix = "sample[" & $(index + 1) & "]."
  for column in visibleSampleColumns(project):
    let value = unicode.strip(field(row, column.key))
    if column.required and value.strip().len == 0:
      result.add ValidationError(field: prefix & column.key, message: column.label & " is required.")
    for validator in column.validators:
      let message = validator(value)
      if message.len > 0:
        result.add ValidationError(field: prefix & column.key, message: message)

proc validateSamples*(rows: seq[SampleRow]; project: ProjectForm): seq[ValidationError] =
  var seen = initTable[string, int]()
  for index, row in rows:
    result.add validateSample(row, index, project)
    let id = unicode.strip(row.field("sample_id"))
    if id.len > 0:
      if seen.hasKey(id):
        result.add ValidationError(
          field: "sample[" & $(index + 1) & "].sample_id",
          message: "Sample ID duplicates row " & $(seen[id] + 1) & "."
        )
      else:
        seen[id] = index

proc validateAll*(model: AppModel): seq[ValidationError] =
  result.add validateProject(model.project)
  result.add validateSamples(model.samples, model.project)