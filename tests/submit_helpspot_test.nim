import std/[parsecfg, streams, strutils]
import ../src/[model, update, helpspot_api]

const helpSpotUrl = static:
  let config = loadConfig(newStringStream(staticRead("../config.ini")))
  config.getSectionValue("helpspot", "url")

const helpSpotCategory = static:
  let config = loadConfig(newStringStream(staticRead("../config.ini")))
  config.getSectionValue("helpspot", "category")

var state = initialModel()
for (key, value) in [
  ("contact_name", "HelpSpot Integration Test"),
  ("contact_email", "helpspot-test@example.com"),
  ("principal_investigator", "Test PI"),
  ("pi_email", "helpspot-test@example.com"),
  ("library_preparation", "Library preparation needed"),
  ("instrument", "PacBio Revio"),
  ("description", "TEST ONLY: automated HelpSpot API integration test. No sequencing is requested."),
  ("irb_certification", "An active/approved IRB protocol is not needed for these samples")
]:
  update(state, Msg(kind: setProjectField, column: key, value: value))
while state.samples.len > 1:
  update(state, Msg(kind: removeSample, row: state.samples.len - 1))
for (key, value) in [
  ("sample_id", "TEST_SAMPLE_001"),
  ("tube_id", "TEST_001"),
  ("organism", "Test organism"),
  ("sample_type", "DNA"),
  ("concentration_ng_ul", "1"),
  ("volume_ul", "1"),
  ("read_depth", "1"),
  ("notes", "TEST ONLY: not a real sample")
]:
  update(state, Msg(kind: setSampleCell, row: 0, column: key, value: value))

update(state, Msg(kind: submitRequest))
if not state.submitting:
  echo state.submissionMessage
  for error in state.errors:
    echo error.field, ": ", error.message
  quit(1)

discard postHelpSpot(helpSpotUrl, helpSpotCategory, state,
  proc(message: string) =
    update(state, Msg(kind: submissionFinished, value: message))
    echo state.submissionMessage
    if not state.submissionMessage.startsWith("Request submitted successfully."):
      quit(1))