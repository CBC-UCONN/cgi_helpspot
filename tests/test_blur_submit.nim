import std/[unittest, sequtils, tables]
import ../src/[model, update]

proc hasField(state: AppModel; key: string): bool =
  state.errors.anyIt(it.field == key)

suite "blur validation and submission":
  test "trim fields before blur validation and on submit":
    var state = initialModel()
    state.samples = @[emptySample()]
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "Library preparation needed"))
    update(state, Msg(kind: setProjectField, column: "contact_email", value: "  name@example.com  "))
    update(state, Msg(kind: blurProjectField, column: "contact_email"))
    check state.project.field("contact_email") == "name@example.com"
    check not state.hasField("contact_email")
    update(state, Msg(kind: setSampleCell, row: 0, column: "sample_id", value: "  sample1  "))
    update(state, Msg(kind: blurSampleCell, row: 0, column: "sample_id"))
    check state.samples[0].field("sample_id") == "sample1"
    check not state.hasField("sample[1].sample_id")
    update(state, Msg(kind: setProjectField, column: "contact_name", value: "\xC2\xA0Jane Doe\xC2\xA0"))
    update(state, Msg(kind: blurProjectField, column: "contact_name"))
    check state.project.field("contact_name") == "Jane Doe"
    update(state, Msg(kind: setProjectField, column: "additional_information", value: "  first line\nsecond line  "))
    update(state, Msg(kind: setSampleCell, row: 0, column: "notes", value: "  sample notes  "))
    update(state, Msg(kind: submitRequest))
    check state.project.field("additional_information") == "first line\nsecond line"
    check state.samples[0].field("notes") == "sample notes"

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
    state.project["library_preparation"] = "Library preparation needed"
    update(state, Msg(kind: submitRequest))
    check state.hasField("contact_name")
    check state.hasField("sample[1].sample_id")
    check state.submissionMessage == "Please correct the highlighted fields."

  test "valid submit starts and completes submission":
    var state = initialModel()
    state.samples = @[emptySample()]
    state.project["contact_name"] = "Name"
    state.project["contact_email"] = "name@example.com"
    state.project["principal_investigator"] = "PI"
    state.project["pi_email"] = "pi@example.com"
    state.project["institution"] = "UConn Health"
    state.project["is_isg_member"] = "Yes"
    state.project["po_number"] = "PO-123"
    state.project["library_preparation"] = "Library preparation needed"
    state.project["instrument"] = "PacBio Revio"
    for fieldDef in projectSchema:
      if fieldDef.key == "irb_certification": state.project[fieldDef.key] = fieldDef.options[0]
    state.samples[0]["sample_id"] = "sample1"
    state.samples[0]["tube_id"] = "tube1"
    state.samples[0]["organism"] = "human"
    state.samples[0]["sample_type"] = "DNA"
    state.samples[0]["concentration_ng_ul"] = "1"
    state.samples[0]["volume_ul"] = "1"
    state.samples[0]["read_depth"] = "1"
    state.samples[0]["sample_disposition"] = "Return to submitter"
    state.samples[0]["library_id"] = "library1"
    update(state, Msg(kind: submitRequest))
    check state.errors.len == 0
    check state.submitting
    check state.submissionMessage == "Submitting request..."
    update(state, Msg(kind: submissionFinished, value: "Request submitted."))
    check not state.submitting
    check state.submissionMessage == "Request submitted."