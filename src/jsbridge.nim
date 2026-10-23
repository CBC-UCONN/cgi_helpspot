## Browser glue: spreadsheet file reading (SheetJS), HelpSpot attachments and the no-cors POST.
{.push warning[CStringConv]: off.} # string and cstring are both JS strings on this backend
import std/[base64, jsffi, strutils]
import karax/kdom

type Form* = JsObject

var XLSX {.importc.}: JsObject # SheetJS, loaded by index.html

proc newForm*(): Form {.importjs: "new FormData()".}

proc append*(f: Form; key, value: cstring) {.importjs: "#.append(#, #)".}

proc utf8Bytes(s: cstring): JsObject {.importjs: "new TextEncoder().encode(#)".}

proc base64Utf8(s: cstring): string =
  let bytes = utf8Bytes(s)
  let n = bytes.length.to(int)
  var bin = newString(n)
  for i in 0 ..< n: bin[i] = char(bytes[i].to(int))
  encode(bin)

proc attach*(f: Form; n: int; filename, mime, content: string) =
  ## HelpSpot expects File<n>_bFileBody as base64 text, not a multipart file part.
  let prefix = "File" & $n
  f.append(prefix & "_sFilename", filename)
  f.append(prefix & "_sFileMimeType", mime)
  f.append(prefix & "_bFileBody", base64Utf8(content))

proc fetchPost(url: cstring; body: Form): JsObject
  {.importjs: "fetch(#, {method: 'POST', body: #, mode: 'no-cors'})".}

proc then(p: JsObject; ok: proc (); fail: proc (e: JsObject)) {.importjs: "#.then(#, #)".}

proc errorText(e: JsObject): cstring {.importjs: "String(#)".}

proc post*(url: cstring; form: Form; cb: proc (err: cstring)) =
  ## HelpSpot does not allow CORS, so the response is opaque: only a network/request
  ## failure can be detected. cb gets "" on success.
  fetchPost(url, form).then(
    proc () = cb(""),
    proc (e: JsObject) = cb(errorText(e)))

proc viewportWidth(): int = int(window.toJs.innerWidth.to(float))

proc tooltipPosition*(anchor: Node; width: int): (int, int) =
  ## Fixed-position left/top for a tooltip placed under `anchor`, kept inside the viewport.
  let r = anchor.toJs.getBoundingClientRect()
  let left = int(r.left.to(float))
  (max(8, min(left, viewportWidth() - width - 8)), int(r.bottom.to(float)))

proc addKeydownListener(cb: proc (e: JsObject)) {.importjs: "window.addEventListener('keydown', #)".}

proc onEscape*(cb: proc ()) =
  addKeydownListener(proc (e: JsObject) =
    if e.key.to(cstring) == "Escape": cb())

proc newFileReader(): JsObject {.importjs: "new FileReader()".}

proc readSpreadsheet*(input: Node; cb: proc (csv, err: cstring)) =
  ## Reads the chosen .csv/.xlsx/.xls file and calls cb with CSV text (err is "" on success).
  let files = input.toJs.files
  if files.length.to(int) == 0: return
  let file = files[0]
  let name = ($file.name.to(cstring)).toLowerAscii
  let reader = newFileReader()
  reader.onerror = proc () = cb("", "Could not read the file.")
  if name.endsWith(".xlsx") or name.endsWith(".xls"):
    reader.onload = proc () =
      try:
        let readOpts = newJsObject()
        readOpts["type"] = "array"
        let wb = XLSX.read(reader.result, readOpts)
        let sheet = wb.Sheets[wb.SheetNames[0].to(cstring)]
        let csvOpts = newJsObject()
        csvOpts["blankrows"] = false
        cb(XLSX.utils.sheet_to_csv(sheet, csvOpts).to(cstring), "")
      except:
        cb("", "Could not parse the Excel file: " & getCurrentExceptionMsg())
    reader.readAsArrayBuffer(file)
  else:
    reader.onload = proc () = cb(reader.result.to(cstring), "")
    reader.readAsText(file)
  input.toJs.value = "" # allow choosing the same file again
