import std/[unittest, sequtils, tables]
import ../src/[model, update]

suite "spreadsheet dependencies":
  test "initial model displays ten blank sample rows":
    let state = initialModel()
    check state.samples.len == 10
    for row in state.samples:
      for column in sampleColumnSchema:
        check row.field(column.key) == ""

  test "spreadsheet unlocks only after every dependency has a valid option":
    var state = initialModel()
    let dependencies = projectSchema.filterIt(it.spreadsheetDependency)
    check dependencies.len > 0
    check not spreadsheetDependenciesSelected(state.project)

    for index, fieldDef in dependencies:
      update(state, Msg(kind: setProjectField, column: fieldDef.key, value: fieldDef.options[0]))
      check spreadsheetDependenciesSelected(state.project) == (index == dependencies.high)

    check spreadsheetDependenciesSelected(state.project)
    state.project[dependencies[0].key] = "not an option"
    check not spreadsheetDependenciesSelected(state.project)
