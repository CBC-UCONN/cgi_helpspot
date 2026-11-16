import std/[unittest, tables, strutils]
import ../src/[model, io]

suite "serialization":
  test "project message and YAML preserve multiline and special characters":
    var project = defaultProject()
    project["contact_name"] = "Ada: Smith"
    project["additional_information"] = "First line\n\"quoted\""
    check projectMessage(project).contains("Contact Name: Ada: Smith\n")
    check projectMessage(project).contains("Additional Information: First line\n\"quoted\"\n")
    check projectYaml(project).contains("contact_name: \"Ada: Smith\"\n")
    check projectYaml(project).contains("additional_information: \"First line\\n\\\"quoted\\\"\"\n")
    check projectYaml(project).contains("novaseq_configuration: \"\"\n")

  test "sample CSV uses visible columns and escapes values":
    var state = initialModel()
    state.project["library_preparation"] = "Library preparation needed"
    state.samples = @[emptySample(), emptySample()]
    state.samples[0]["sample_id"] = "sample1"
    state.samples[0]["notes"] = "a, \"b\"\nnext"
    state.samples[1]["sample_id"] = "sample2"
    let csv = samplesCsv(state)
    check csv.startsWith(sampleColumns(state.project).join(",") & "\n")
    check not csv.splitLines()[0].contains("library_id")
    check csv.contains("\"a, \"\"b\"\"\nnext\"")
    check csv.contains("sample2,")

  test "sample CSV switches columns with project configuration":
    var state = initialModel()
    state.project["library_preparation"] = "User prepared library"
    state.project["instrument"] = "Illumina NovaSeq 6000"
    state.samples = @[]
    let header = samplesCsv(state).strip().split(',')
    check header == sampleColumns(state.project)
    check "library_id" in header
    check "i7_index" in header
    check "sample_id" notin header