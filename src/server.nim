## Development server: serves the static files in public/ with mummy.
import std/[os, strutils, mimetypes]
import mummy

const
  publicDir = "public"
  host = "127.0.0.1"

let port = parseInt(getEnv("PORT", "8765"))

proc handler(request: Request) =
  if request.httpMethod notin ["GET", "HEAD"]:
    request.respond(405, @[("Allow", "GET, HEAD")], "Method not allowed")
    return

  var rel = request.path.split('?')[0]
  if rel.endsWith("/"): rel.add "index.html"
  # Reject traversal attempts and anything that is not a plain relative path.
  if ".." in rel or '\\' in rel or '\0' in rel:
    request.respond(400, @[], "Bad request")
    return

  let file = publicDir / rel.strip(chars = {'/'}, trailing = false)
  if not fileExists(file):
    request.respond(404, @[("Content-Type", "text/plain")], "Not found")
    return

  let mimes = newMimetypes()
  let ext = file.splitFile.ext.strip(chars = {'.'})
  request.respond(200, @[("Content-Type", mimes.getMimetype(ext, "application/octet-stream")),
                         ("Cache-Control", "no-store")], readFile(file))

if not dirExists(publicDir):
  quit "public/ not found; run `nimble web` first.", 1

let server = newServer(handler)
echo "Serving ", publicDir, " at http://", host, ":", port
server.serve(Port(port), host)
