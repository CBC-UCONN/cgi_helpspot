import std/strutils
import model
import validators
import csvio

type
  MsgKind* = enum
    setProjectField,
    addSample, removeSample, setSampleCell,
    downloadTemplate, csvLoaded, submit

  Msg* = object
    kind*: MsgKind
    row*: int
    column*: string
    value*: string
    boolValue*: bool

proc setSampleValue(row: var SampleRow; column, value: string) =
  case column
  of "sample_id": row.sampleId = value
  of "sample_name": row.sampleName = value
  of "source": row.source = value
  of "strain": row.strain = value
  of "cell_type": row.cellType = value
  of "library_prep": row.libraryPrep = value
  of "i7_index": row.i7Index = value
  of "i5_index": row.i5Index = value
  of "reference": row.reference = value
  else: discard

proc setProjectValue(project: var ProjectForm; key, value: string; boolValue: bool) =
  case key
  of "projectName": project.projectName = value
  of "requester": project.requester = value
  of "email": project.email = value
  of "organism": project.organism = value
  of "assay": project.assay = parseEnum[AssayKind](value, project.assay)
  of "readType": project.readType = parseEnum[ReadKind](value, project.readType)
  of "indexType": project.indexType = parseEnum[IndexKind](value, project.indexType)
  of "libraryPrep": project.libraryPrep = value
  of "customReference": project.customReference = boolValue
  of "referenceName": project.referenceName = value
  of "notes": project.notes = value
  else: discard

proc update*(m: var AppModel; msg: Msg) =
  case msg.kind
  of setProjectField:
    setProjectValue(m.project, msg.column, msg.value, msg.boolValue)
  of addSample: m.samples.add emptySample()
  of removeSample:
    if m.samples.len > 1 and msg.row >= 0 and msg.row < m.samples.len:
      m.samples.delete msg.row
  of setSampleCell:
    if msg.row >= 0 and msg.row < m.samples.len:
      setSampleValue(m.samples[msg.row], msg.column, msg.value)
  of downloadTemplate: discard
  of csvLoaded:
    let parsed = parseCsv(msg.value, m.project)
    if parsed.errors.len > 0:
      m.csvMessage = parsed.errors.join(" ")
    else:
      m.samples = parsed.rows
      m.csvMessage = "Loaded " & $m.samples.len & " sample(s) from CSV."
      m.errors = @[]
  of submit:
    m.errors = validateAll(m)
    if m.errors.len == 0:
      m.submitted = true
      m.submissionMessage = "Request is valid and ready for submission. Connect the submit handler to your sequencing-core API to send it."
    else:
      m.submitted = false
      m.submissionMessage = "Please correct the highlighted fields."
