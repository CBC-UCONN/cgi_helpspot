import std/[strutils, tables]
import model

type Validator* = proc(value: string): string

proc required*(label: string): Validator =
  result = proc(value: string): string =
    if value.strip().len == 0: return label & " is required."

proc validEmail*(): Validator =
  result = proc(value: string): string =
    let v = value.strip()
    if v.len > 0 and (v.count("@") != 1 or v.endsWith("@") or v.startsWith("@")):
      return "Enter a valid email address."

proc validateProject*(p: ProjectForm): seq[ValidationError] =
  let checks = [
    ("projectName", p.projectName, required("Project name")),
    ("requester", p.requester, required("Requester")),
    ("email", p.email, validEmail()),
    ("organism", p.organism, required("Organism")),
    ("libraryPrep", p.libraryPrep, required("Library preparation"))
  ]
  for (field, value, validator) in checks:
    let message = validator(value)
    if message.len > 0:
      result.add ValidationError(field: field, message: message)
  if p.customReference and p.referenceName.strip().len == 0:
    result.add ValidationError(field: "referenceName", message: "Reference name is required when using a custom reference.")

proc validateSample*(row: SampleRow; index: int; p: ProjectForm): seq[ValidationError] =
  let prefix = "sample[" & $(index + 1) & "]"
  if row.sampleId.strip().len == 0:
    result.add ValidationError(field: prefix & ".sample_id", message: "Sample ID is required.")
  if row.sampleName.strip().len == 0:
    result.add ValidationError(field: prefix & ".sample_name", message: "Sample name is required.")
  if row.source.strip().len == 0:
    result.add ValidationError(field: prefix & ".source", message: "Source is required.")

  if p.assay == assaySingleCell and row.cellType.strip().len == 0:
    result.add ValidationError(field: prefix & ".cell_type", message: "Cell type is required for single-cell DNA requests.")

  if p.indexType in {dualIndex, singleIndex} and row.i7Index.strip().len == 0:
    result.add ValidationError(field: prefix & ".i7_index", message: "i7 index is required for indexed libraries.")

  if p.indexType == dualIndex and row.i5Index.strip().len == 0:
    result.add ValidationError(field: prefix & ".i5_index", message: "i5 index is required for dual-indexed libraries.")

  if p.customReference and row.reference.strip().len == 0:
    result.add ValidationError(field: prefix & ".reference", message: "Reference is required for a custom-reference project.")

proc validateSamples*(rows: seq[SampleRow]; p: ProjectForm): seq[ValidationError] =
  var seen = initTable[string, int]()
  for i, row in rows:
    result.add validateSample(row, i, p)
    let id = row.sampleId.strip()
    if id.len > 0:
      if seen.hasKey(id):
        result.add ValidationError(
          field: "sample[" & $(i + 1) & ".sampleId",
          message: "Sample ID duplicates row " & $(seen[id] + 1) & "."
        )
      else:
        seen[id] = i

proc validateAll*(model: AppModel): seq[ValidationError] =
  result.add validateProject(model.project)
  result.add validateSamples(model.samples, model.project)
