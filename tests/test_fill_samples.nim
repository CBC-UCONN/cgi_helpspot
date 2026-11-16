import std/[unittest, sequtils]
import ../src/[model, update]

suite "sample cell fill":
  test "increments trailing numbers while preserving padding and copying other values":
    check sampleFillValue("Sample009", 1, false) == "Sample010"
    check sampleFillValue("Sample099", 1, false) == "Sample100"
    check sampleFillValue("Sample999", 1, false) == "Sample1000"
    check sampleFillValue("Sample99999999999999999999", 1, false) == "Sample100000000000000000000"
    check sampleFillValue("Sample009", 12, false) == "Sample021"
    check sampleFillValue("Sample010", -1, false) == "Sample009"
    check sampleFillValue("Sample100", -12, false) == "Sample088"
    check sampleFillValue("Sample001", -1, false) == "Sample000"
    check sampleFillValue("Sample001", -2, false) == "Sample-001"
    check sampleFillValue("Sample100000000000000000000", -1, false) == "Sample099999999999999999999"
    check sampleFillValue("123", 1, false) == "123"
    check sampleFillValue("Sample", 1, false) == "Sample"
    check sampleFillValue("Sample009", 1, true) == "Sample009"

  test "decrements upwards and increments downwards":
    var state = initialModel()
    update(state, Msg(kind: setSampleCell, row: 3, column: "tube_id", value: "Tube009"))
    update(state, Msg(kind: fillSampleCells, row: 3, targetRow: 5, column: "tube_id"))
    update(state, Msg(kind: fillSampleCells, row: 3, targetRow: 1, column: "tube_id"))
    check state.samples[2].field("tube_id") == "Tube008"
    check state.samples[1].field("tube_id") == "Tube007"
    check state.samples[4].field("tube_id") == "Tube010"
    check state.samples[5].field("tube_id") == "Tube011"

  test "copies values down and up without changing other columns":
    var state = initialModel()
    update(state, Msg(kind: setSampleCell, row: 2, column: "organism", value: "Human"))
    update(state, Msg(kind: setSampleCell, row: 1, column: "notes", value: "keep"))
    update(state, Msg(kind: fillSampleCells, row: 2, targetRow: 4, column: "organism"))
    update(state, Msg(kind: fillSampleCells, row: 2, targetRow: 0, column: "organism"))
    for row in 0 .. 4:
      check state.samples[row].field("organism") == "Human"
    check state.samples[5].field("organism") == ""
    check state.samples[1].field("notes") == "keep"

  test "fills dropdown values and clears with a blank source":
    var state = initialModel()
    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "Library preparation needed"))
    update(state, Msg(kind: setSampleCell, row: 0, column: "sample_type", value: "DNA"))
    update(state, Msg(kind: fillSampleCells, row: 0, targetRow: 2, column: "sample_type"))
    check state.samples[2].field("sample_type") == "DNA"
    update(state, Msg(kind: fillSampleCells, row: 3, targetRow: 1, column: "sample_type"))
    check state.samples[1].field("sample_type") == ""
    check state.samples[2].field("sample_type") == ""

  test "validates filled cells and rejects invalid destinations":
    var state = initialModel()
    update(state, Msg(kind: setSampleCell, row: 0, column: "tube_id", value: "too-long-value"))
    update(state, Msg(kind: fillSampleCells, row: 0, targetRow: 2, column: "tube_id"))
    check state.errors.anyIt(it.field == "sample[2].tube_id")
    check state.errors.anyIt(it.field == "sample[3].tube_id")
    update(state, Msg(kind: fillSampleCells, row: 0, targetRow: 100, column: "tube_id"))
    check state.samples[3].field("tube_id") == ""