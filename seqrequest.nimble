import std/os

# Sequencing Request SPA
# Build with: nimble build

version       = "0.1.0"
author        = "Sequencing Core"
description   = "Client-side DNA sequencing request form built with Nim and Karax"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.0"
requires "karax >= 1.3.0"

proc buildApp() =
  let outputDir = "public"
  mkDir outputDir
  # mkDir outputDir / "assets"

  # Compile the browser application. The generated JavaScript is copied into public.
  let cmd = "nim js -d:release --out:" & outputDir / "app.js" & " " & srcDir / "main.nim"
  exec cmd

  cpFile srcDir / "index.html", outputDir / "index.html"

task buildWeb, "Build the sequencing request application":
  buildApp()