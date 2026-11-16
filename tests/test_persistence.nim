import std/[unittest, tables, sets]
import ../src/[model, persistence, update]

suite "model persistence":
  test "round trips project, hidden sample values, and validation state":
    var original = initialModel()
    original.project["contact_name"] = "Test user"
    original.samples[0]["library_id"] = "lib001"
    original.samples.add emptySample()
    original.samples[10]["notes"] = "Last row"
    original.errors = @[ValidationError(field: "contact_name", message: "error")]
    original.editedFields.incl "contact_name"
    original.liveFields.incl "contact_name"
    original.csvMessage = "Loaded"
    original.submissionMessage = "Incomplete"
    var restored = initialModel()
    check decodeModel(encodeModel(original), restored)
    check restored.project["contact_name"] == "Test user"
    check restored.samples.len == 11
    check restored.samples[0]["library_id"] == "lib001"
    check restored.samples[10]["notes"] == "Last row"
    check restored.errors[0].message == "error"
    check "contact_name" in restored.editedFields
    check "contact_name" in restored.liveFields
    check restored.csvMessage == "Loaded"
    check restored.submissionMessage == "Incomplete"

  test "rejects malformed or unsupported data without modifying state":
    var state = initialModel()
    state.project["contact_name"] = "Keep"
    check not decodeModel("not json", state)
    check not decodeModel("{\"version\":2}", state)
    check state.project["contact_name"] == "Keep"

  test "reset restores defaults and replaces the sample table":
    var state = initialModel()
    state.project["contact_name"] = "Test user"
    state.samples[0]["notes"] = "Keep until reset"
    state.errors.add ValidationError(field: "contact_name", message: "error")
    state.editedFields.incl "contact_name"
    update(state, Msg(kind: resetRequest))
    check state.project["contact_name"] == ""
    check state.samples.len == 10
    check state.samples[0]["notes"] == ""
    check state.errors.len == 0
    check state.editedFields.len == 0
    check state.sampleRevision == 1