import std/[unittest, tables, strutils]
import ../src/[model, helpspot_api]

suite "HelpSpot submission payload":
  test "project details retain multiline and special characters":
    var project = defaultProject()
    project["contact_name"] = "Ada: Smith"
    project["description"] = "First line\n\"quoted\""
    check projectMessage(project).contains("Contact name: Ada: Smith\n")
    check projectMessage(project).contains("Description: First line\n\"quoted\"\n")
    check projectYaml(project).contains("contact_name: \"Ada: Smith\"\n")
    check projectYaml(project).contains("description: \"First line\\n\\\"quoted\\\"\"\n")
    check projectYaml(project).contains("novaseq_configuration: \"\"\n")

  test "samples use visible columns and escape CSV values":
    var state = initialModel()
    state.project["library_preparation"] = "Library preparation needed"
    state.samples = @[emptySample()]
    state.samples[0]["sample_id"] = "sample1"
    state.samples[0]["notes"] = "a, \"b\"\nnext"
    let csv = samplesCsv(state)
    check csv.startsWith("sample_id,tube_id,")
    check not csv.contains("library_id")
    check csv.contains("\"a, \"\"b\"\"\nnext\"")

  test "HelpSpot responses distinguish success, rejection and malformed XML":
    check responseMessage("<request><xRequest>12345</xRequest></request>", true, 200) ==
      "Request submitted successfully. Request number: 12345"
    check responseMessage("<errors><error><description>Invalid &amp; missing</description></error></errors>", false, 400) ==
      "HelpSpot rejected the request: Invalid & missing"
    check responseMessage("<errors>", false, 400) == "HelpSpot rejected the request (HTTP 400)."
    check responseMessage("<request><xRequest>12345", true, 200) ==
      "HelpSpot returned an unexpected response. Check whether the request was created before retrying."