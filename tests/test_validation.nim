import std/[unittest, sequtils, tables, strutils]
import ../src/[model, validation, validators, update, csvio]

proc hasError(errors: seq[ValidationError]; field, message: string): bool =
  errors.anyIt(it.field == field and it.message == message)

suite "schema-driven validation":
  test "project validators run for visible fields":
    var project = defaultProject()
    project["email"] = "invalid"
    var errors = validateProject(project)
    check errors.hasError("projectName", "Project name is required.")
    check errors.hasError("email", "Enter a valid email address.")
    check not errors.anyIt(it.field == "referenceName")
    project["customReference"] = "true"
    errors = validateProject(project)
    check errors.hasError("referenceName", "Reference name is required when using a custom reference.")
    project["referenceName"] = "hg38"
    check not validateProject(project).anyIt(it.field == "referenceName")

  test "sample validators follow visible columns":
    var project = defaultProject()
    project["indexType"] = $noIndex
    var errors = validateSample(emptySample(), 0, project)
    check errors.hasError("sample[1].sample_id", "Sample ID is required.")
    check not errors.anyIt(it.field == "sample[1].cell_type" or it.field == "sample[1].i7_index" or it.field == "sample[1].i5_index")
    project["assay"] = $assaySingleCell
    project["indexType"] = $singleIndex
    project["customReference"] = "true"
    errors = validateSample(emptySample(), 1, project)
    check errors.hasError("sample[2].cell_type", "Cell type is required for single-cell DNA requests.")
    check errors.hasError("sample[2].i7_index", "i7 index is required for indexed libraries.")
    check errors.hasError("sample[2].reference", "Reference is required for a custom-reference project.")
    check not errors.anyIt(it.field == "sample[2].i5_index")
    project["indexType"] = $dualIndex
    check validateSample(emptySample(), 1, project).hasError("sample[2].i5_index", "i5 index is required for dual-indexed libraries.")

  test "duplicate sample IDs identify the correct cell":
    var first = emptySample()
    var second = emptySample()
    first["sample_id"] = "same"
    second["sample_id"] = " same "
    let rows = @[first, second]
    check validateSamples(rows, defaultProject()).hasError("sample[2].sample_id", "Sample ID duplicates row 1.")

  test "schema validators are callable and reusable":
    let emailField = projectSchema.filterIt(it.key == "email")[0]
    check emailField.validators.len == 1
    check emailField.validators[0]("a@b") == ""
    check required("Example")("  ") == "Example is required."

  test "project updates use schema defaults and kinds":
    var state = initialModel()
    check state.project.field("assay") == $assayBulk
    check state.project.field("readType") == $pairedEnd
    check state.project.field("indexType") == $dualIndex
    update(state, Msg(kind: setProjectField, column: "assay", value: $assaySingleCell))
    update(state, Msg(kind: setProjectField, column: "customReference", boolValue: true))
    check state.project.field("assay") == $assaySingleCell
    check state.project.field("customReference") == "true"
    update(state, Msg(kind: setProjectField, column: "assay", value: "invalid"))
    update(state, Msg(kind: setProjectField, column: "unknown", value: "ignored"))
    check state.project.field("assay") == $assaySingleCell
    check not state.project.hasKey("unknown")

  test "sample edits remain independent and hidden values persist":
    var state = initialModel()
    update(state, Msg(kind: addSample))
    update(state, Msg(kind: setSampleCell, row: 0, column: "tests", value: "WGS"))
    update(state, Msg(kind: setSampleCell, row: 0, column: "i5_index", value: "index"))
    check state.samples[0].field("tests") == "WGS"
    check state.samples[1].field("tests") == ""
    update(state, Msg(kind: setProjectField, column: "indexType", value: $noIndex))
    update(state, Msg(kind: setProjectField, column: "indexType", value: $dualIndex))
    check state.samples[0].field("i5_index") == "index"

  test "CSV import stores schema columns without predefined members":
    var project = defaultProject()
    project["indexType"] = $noIndex
    let columns = sampleColumns(project)
    let values = columns.mapIt(if it == "tests": "WGS" else: "sample")
    let parsed = parseCsv(columns.join(",") & "\n" & values.join(",") & "\n", project)
    check parsed.errors.len == 0
    check parsed.rows.len == 1
    check parsed.rows[0].field("tests") == "WGS"

  test "project edits validate and clear errors immediately":
    var state = initialModel()
    update(state, Msg(kind: setProjectField, column: "email", value: "bad"))
    check state.errors.hasError("email", "Enter a valid email address.")
    update(state, Msg(kind: setProjectField, column: "email", value: "a@b"))
    check not state.errors.anyIt(it.field == "email")
    update(state, Msg(kind: setProjectField, column: "customReference", boolValue: true))
    check state.errors.anyIt(it.field == "referenceName")
    check state.errors.anyIt(it.field == "sample[1].reference")
    update(state, Msg(kind: setProjectField, column: "customReference", boolValue: false))
    check not state.errors.anyIt(it.field == "referenceName" or it.field == "sample[1].reference")

  test "sample edits and removal refresh duplicate errors":
    var state = initialModel()
    update(state, Msg(kind: setSampleCell, row: 0, column: "sample_id", value: "one"))
    check not state.errors.anyIt(it.field == "sample[1].sample_id")
    update(state, Msg(kind: addSample))
    update(state, Msg(kind: setSampleCell, row: 1, column: "sample_id", value: "one"))
    check state.errors.hasError("sample[2].sample_id", "Sample ID duplicates row 1.")
    update(state, Msg(kind: setSampleCell, row: 1, column: "sample_id", value: "two"))
    check not state.errors.anyIt(it.field == "sample[2].sample_id")
    update(state, Msg(kind: setSampleCell, row: 1, column: "sample_id", value: "one"))
    update(state, Msg(kind: removeSample, row: 0))
    check not state.errors.anyIt(it.field == "sample[2].sample_id" or it.field == "sample[1].sample_id")

  test "successful CSV upload validates imported rows":
    var state = initialModel()
    let columns = sampleColumns(state.project)
    let values = columns.mapIt(if it == "sample_id": "one" else: "")
    update(state, Msg(kind: csvLoaded, value: columns.join(",") & "\n" & values.join(",") & "\n"))
    check state.csvMessage == "Loaded 1 sample(s) from CSV."
    check state.errors.hasError("sample[1].source", "Source is required.")