import std/[unittest, sequtils, tables]
import ../src/[model, update]

proc hasField(state: AppModel; key: string): bool =
  state.errors.anyIt(it.field == key)

suite "blur validation and submission":
  test "only edited fields validate on blur":
    var state = initialModel()
    update(state, Msg(kind: blurProjectField, column: "contact_name"))
    check state.errors.len == 0
    update(state, Msg(kind: setProjectField, column: "contact_email", value: "bad"))
    check state.errors.len == 0
    update(state, Msg(kind: blurProjectField, column: "contact_email"))
    check state.hasField("contact_email")
    check not state.hasField("contact_name")
    update(state, Msg(kind: setProjectField, column: "contact_email", value: "name@example.com"))
    check not state.hasField("contact_email")
    update(state, Msg(kind: blurProjectField, column: "contact_email"))
    check not state.hasField("contact_email")

  test "sample cells validate on blur":
    var state = initialModel()
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "Library preparation needed"))
    update(state, Msg(kind: setSampleCell, row: 0, column: "tube_id", value: "too-long-value"))
    check state.errors.len == 0
    update(state, Msg(kind: blurSampleCell, row: 0, column: "tube_id"))
    check state.hasField("sample[1].tube_id")
    check not state.hasField("sample[1].sample_id")
    update(state, Msg(kind: setSampleCell, row: 0, column: "tube_id", value: "tube1"))
    check not state.hasField("sample[1].tube_id")
    update(state, Msg(kind: blurSampleCell, row: 0, column: "tube_id"))
    check not state.hasField("sample[1].tube_id")

  test "removing a row deletes its data and remaps remaining errors":
    var state = initialModel()
    state.samples = @[emptySample()]
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "Library preparation needed"))
    update(state, Msg(kind: addSample))
    update(state, Msg(kind: addSample))
    update(state, Msg(kind: setSampleCell, row: 0, column: "sample_id", value: "first"))
    update(state, Msg(kind: setSampleCell, row: 1, column: "sample_id", value: "second"))
    update(state, Msg(kind: setSampleCell, row: 2, column: "sample_id", value: "third"))
    update(state, Msg(kind: setSampleCell, row: 2, column: "tube_id", value: "too-long-value"))
    update(state, Msg(kind: blurSampleCell, row: 2, column: "tube_id"))
    update(state, Msg(kind: removeSample, row: 1))
    check state.samples.len == 2
    check state.samples[0].field("sample_id") == "first"
    check state.samples[1].field("sample_id") == "third"
    check state.hasField("sample[2].tube_id")
    check not state.hasField("sample[3].tube_id")

  test "removing the only row clears its data and validation state":
    var state = initialModel()
    state.samples = @[emptySample()]
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "Library preparation needed"))
    update(state, Msg(kind: setProjectField, column: "contact_email", value: "bad"))
    update(state, Msg(kind: blurProjectField, column: "contact_email"))
    update(state, Msg(kind: setSampleCell, row: 0, column: "sample_id", value: "sample1"))
    update(state, Msg(kind: setSampleCell, row: 0, column: "tube_id", value: "too-long-value"))
    update(state, Msg(kind: blurSampleCell, row: 0, column: "tube_id"))
    check state.hasField("sample[1].tube_id")
    update(state, Msg(kind: removeSample, row: 0))
    check state.samples.len == 1
    for column in sampleColumnSchema:
      check state.samples[0].field(column.key) == ""
    check not state.hasField("sample[1].tube_id")
    check state.hasField("contact_email")
    update(state, Msg(kind: blurSampleCell, row: 0, column: "tube_id"))
    check not state.hasField("sample[1].tube_id")

  test "editing another row clears a visible duplicate error":
    var state = initialModel()
    state.samples = @[emptySample()]
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "Library preparation needed"))
    update(state, Msg(kind: addSample))
    update(state, Msg(kind: setSampleCell, row: 0, column: "sample_id", value: "same"))
    update(state, Msg(kind: setSampleCell, row: 1, column: "sample_id", value: "same"))
    update(state, Msg(kind: blurSampleCell, row: 1, column: "sample_id"))
    check state.hasField("sample[2].sample_id")
    update(state, Msg(kind: setSampleCell, row: 0, column: "sample_id", value: "different"))
    check not state.hasField("sample[2].sample_id")

  test "invalid submit validates all fields":
    var state = initialModel()
    update(state, Msg(kind: submitRequest))
    check state.hasField("contact_name")
    check state.hasField("sample[1].sample_id")
    check state.submissionMessage == "Please correct the highlighted fields."

  test "valid submit reaches the unconnected stub":
    var state = initialModel()
    state.samples = @[emptySample()]
    state.project["contact_name"] = "Name"
    state.project["contact_email"] = "name@example.com"
    state.project["principal_investigator"] = "PI"
    state.project["contact_pi"] = "Contact"
    for fieldDef in projectSchema:
      if fieldDef.key == "irb_certification": state.project[fieldDef.key] = fieldDef.options[0]
    state.samples[0]["sample_id"] = "sample1"
    state.samples[0]["tube_id"] = "tube1"
    state.samples[0]["organism"] = "human"
    state.samples[0]["sample_type"] = "DNA"
    state.samples[0]["concentration_ng_ul"] = "1"
    state.samples[0]["volume_ul"] = "1"
    state.samples[0]["read_depth"] = "1"
    state.samples[0]["library_id"] = "library1"
    update(state, Msg(kind: submitRequest))
    check state.errors.len == 0
    check state.submissionMessage == "Validation passed. Submission is not yet connected."