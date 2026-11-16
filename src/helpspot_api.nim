import std/[json, strutils, xmlparser, xmltree, asyncjs, jsfetch, httpcore, base64, parsecfg, streams]
import model, csvio

const helpSpotUrl* = static:
  let config = loadConfig(newStringStream(staticRead("../config.ini")))
  config.getSectionValue("helpspot", "url")

const helpSpotCategory* = static:
  let config = loadConfig(newStringStream(staticRead("../config.ini")))
  config.getSectionValue("helpspot", "category")

const helpSpotReportingTags* = static:
  let config = loadConfig(newStringStream(staticRead("../config.ini")))
  config.getSectionValue("helpspot", "reportingTags")

proc projectMessage*(project: ProjectForm): string =
  for fieldDef in projectSchema:
    result.add fieldDef.label & ": " & project.field(fieldDef.key) & "\n"

proc projectYaml*(project: ProjectForm): string =
  for fieldDef in projectSchema:
    result.add fieldDef.key & ": " & $(%project.field(fieldDef.key)) & "\n"

proc samplesCsv*(state: AppModel): string =
  let columns = sampleColumns(state.project)
  result = columns.join(",") & "\n"
  for row in state.samples:
    var values: seq[string]
    for column in columns:
      values.add csvEscape(row.field(column))
    result.add values.join(",") & "\n"


proc responseMessage*(body: string; ok: bool; status: int): string =
  var root: XmlNode
  try:
    root = parseXml(body)
  except CatchableError:
    discard
  if not ok:
    if root != nil and root.kind == xnElement and root.tag == "errors":
      let errors = root.findAll("description")
      if errors.len > 0 and errors[0].innerText.strip().len > 0:
        return "HelpSpot rejected the request: " & errors[0].innerText.strip()
    return "HelpSpot rejected the request (HTTP " & $status & ")."
  if root != nil and root.kind == xnElement and root.tag == "request":
    for child in root:
      if child.kind == xnElement and child.tag == "xRequest":
        let requestNumber = child.innerText.strip()
        if requestNumber.len > 0:
          return "Request submitted successfully. Request number: " & requestNumber
  "HelpSpot returned an unexpected response. Check whether the request was created before retrying."

proc postHelpSpot*(url, category, reportingTags: string; state: AppModel;
                   callback: proc(message: string) {.closure.}) {.async.} =
  if url.len == 0:
    callback("HelpSpot URL is not configured.")
    return
  let form = newFormData()
  form.add("tNote", cstring(projectMessage(state.project)))
  form.add("sFirstName", cstring(state.project.field("contact_name")))
  form.add("sEmail", cstring(state.project.field("contact_email")))
  if category.len > 0:
    form.add("xCategory", cstring(category))
  if reportingTags.len > 0:
    form.add("reportingTags", cstring(reportingTags))
  form.add("File1_sFilename", cstring("project.yaml"))
  form.add("File1_sFileMimeType", cstring("application/yaml"))
  form.add("File1_bFileBody", cstring(encode(projectYaml(state.project))))
  form.add("File2_sFilename", cstring("samples.csv"))
  form.add("File2_sFileMimeType", cstring("text/csv"))
  form.add("File2_bFileBody", cstring(encode(samplesCsv(state))))
  var response: Response
  var body: cstring
  try:
    let options = newFetchOptions(metod = HttpPost, body = cast[cstring](form), credentials = fcOmit, referrer = cstring(""))
    let endpoint = url.strip(leading = false, chars = {'/'}) & "/api/index.php?method=request.create"
    response = await fetch(cstring(endpoint), options)
    body = await response.text()
  except:
    callback("Network error: could not confirm submission. Check whether the request was created before retrying.")
    return
  callback(responseMessage($body, response.ok, int(response.status)))