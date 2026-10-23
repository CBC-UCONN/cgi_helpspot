version       = "0.1.0"
author        = "CGI"
description   = "Single page app for submitting DNA sequencing projects to HelpSpot"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.0"
requires "karax >= 1.3.0"
requires "mummy >= 0.4.0"

const publicDir = "public"

proc buildWeb(extraFlags = "") =
  mkDir publicDir
  exec "nim js -d:release " & extraFlags & " --out:" & publicDir & "/app.js src/app.nim"
  cpFile "index.html", publicDir & "/index.html"

task web, "Compile the Karax app and copy index.html into public/":
  buildWeb()

task webdemo, "Like web, plus a 'Fill test data' button; tickets are marked [TEST SUBMISSION]":
  buildWeb("-d:demo")

task serve, "Build the static site, then serve public/ with mummy on http://127.0.0.1:8765":
  exec "nimble web"
  exec "nim c -r --threads:on --out:bin/server src/server.nim"

task servedemo, "Build with test data support, then serve public/":
  exec "nimble webdemo"
  exec "nim c -r --threads:on --out:bin/server src/server.nim"

task test, "Run unit tests for the platform independent modules":
  exec "nim c -r --hints:off tests/test_lib.nim"
