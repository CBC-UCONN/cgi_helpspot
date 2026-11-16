import std/[unittest, sequtils, tables, strutils]
import ../src/[model, validation, validators, update, io]

proc hasError(errors: seq[ValidationError]; field, message: string): bool =
  errors.anyIt(it.field == field and it.message == message)

suite "schema-driven validation":
  test "project validators run for visible fields":
    var project = defaultProject()
    project["contact_email"] = "invalid"
    var errors = validateProject(project)
    check errors.hasError("contact_name", "Contact Name is required.")
    check errors.hasError("contact_email", "Enter a valid email address.")
    check not errors.anyIt(it.field == "novaseq_configuration")
    project["instrument"] = "Illumina NovaSeq 6000"
    errors = validateProject(project)
    check errors.hasError("novaseq_configuration", "NovaSeq Configuration is required.")
    project["novaseq_configuration"] = "PE 150"
    check not validateProject(project).anyIt(it.field == "novaseq_configuration")

  test "sample validators follow visible columns":
    var project = defaultProject()
    project["library_preparation"] = "Library preparation needed"
    var errors = validateSample(emptySample(), 0, project)
    check errors.hasError("sample[1].sample_id", "Sample ID is required.")
    check not errors.anyIt(it.field == "sample[1].library_id" or it.field == "sample[1].i7_index")
    project["library_preparation"] = "User prepared library"
    project["instrument"] = "Illumina NovaSeq 6000"
    errors = validateSample(emptySample(), 1, project)
    check errors.hasError("sample[2].library_id", "Library ID is required.")
    check errors.hasError("sample[2].i7_index", "i7 Index is required.")
    check not errors.anyIt(it.field == "sample[2].sample_id" or it.field == "sample[2].i5_index")

  test "duplicate sample IDs identify the correct cell":
    var first = emptySample()
    var second = emptySample()
    first["sample_id"] = "same"
    second["sample_id"] = " same "
    let rows = @[first, second]
    var project = defaultProject()
    project["library_preparation"] = "Library preparation needed"
    check validateSamples(rows, project).hasError("sample[2].sample_id", "Sample ID duplicates row 1.")

  test "schema validators are callable and reusable":
    let emailField = projectSchema.filterIt(it.key == "contact_email")[0]
    check emailField.validators.len == 1
    check emailField.validators[0]("a@b") == ""
    check required("Example")("  ") == "Example is required."

  test "project updates use schema defaults and kinds":
    var state = initialModel()
    check state.project.field("library_preparation") == ""
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "User prepared library"))
    check state.project.field("library_preparation") == "User prepared library"
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "invalid"))
    update(state, Msg(kind: setProjectField, column: "unknown", value: "ignored"))
    check state.project.field("library_preparation") == "User prepared library"
    check not state.project.hasKey("unknown")

  test "sample edits remain independent and hidden values persist":
    var state = initialModel()
    update(state, Msg(kind: setSampleCell, row: 0, column: "notes", value: "WGS"))
    update(state, Msg(kind: setSampleCell, row: 0, column: "i5_index", value: "ACGT"))
    check state.samples[0].field("notes") == "WGS"
    check state.samples[1].field("notes") == ""
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "Library preparation needed"))
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "User prepared library"))
    check state.samples[0].field("i5_index") == "ACGT"

  test "CSV import stores schema columns without predefined members":
    var project = defaultProject()
    project["library_preparation"] = "Library preparation needed"
    let columns = sampleColumns(project)
    let values = columns.mapIt(if it == "notes": "WGS" else: "sample")
    let parsed = parseCsv(columns.join(",") & "\n" & values.join(",") & "\n", project)
    check parsed.errors.len == 0
    check parsed.rows.len == 1
    check parsed.rows[0].field("notes") == "WGS"

  test "project blur validates and subsequent edits clear errors":
    var state = initialModel()
    update(state, Msg(kind: setProjectField, column: "contact_email", value: "bad"))
    update(state, Msg(kind: blurProjectField, column: "contact_email"))
    check state.errors.hasError("contact_email", "Enter a valid email address.")
    update(state, Msg(kind: setProjectField, column: "contact_email", value: "a@b"))
    check not state.errors.anyIt(it.field == "contact_email")

  test "sample edits and removal refresh duplicate errors":
    var state = initialModel()
    state.samples = @[emptySample(), emptySample()]
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "Library preparation needed"))
    update(state, Msg(kind: setSampleCell, row: 0, column: "sample_id", value: "one"))
    check not state.errors.anyIt(it.field == "sample[1].sample_id")
    update(state, Msg(kind: setSampleCell, row: 1, column: "sample_id", value: "one"))
    update(state, Msg(kind: blurSampleCell, row: 1, column: "sample_id"))
    check state.errors.hasError("sample[2].sample_id", "Sample ID duplicates row 1.")
    update(state, Msg(kind: setSampleCell, row: 1, column: "sample_id", value: "two"))
    check not state.errors.anyIt(it.field == "sample[2].sample_id")
    update(state, Msg(kind: setSampleCell, row: 1, column: "sample_id", value: "one"))
    update(state, Msg(kind: removeSample, row: 0))
    check not state.errors.anyIt(it.field == "sample[2].sample_id" or it.field == "sample[1].sample_id")

  test "successful CSV upload loads rows for submission validation":
    var state = initialModel()
    state.project["library_preparation"] = "Library preparation needed"
    let columns = sampleColumns(state.project)
    let values = columns.mapIt(if it == "sample_id": "one" else: "")
    update(state, Msg(kind: csvLoaded, value: columns.join(",") & "\n" & values.join(",") & "\n"))
    check state.csvMessage == "Loaded 1 sample(s) from CSV."
    update(state, Msg(kind: submitRequest))
    check state.errors.hasError("sample[1].tube_id", "Tube ID is required.")