## Minimal INI parser: `[section]`, `key = value`, and `;` / `#` comment lines.
import std/[strutils, tables]

proc parseIni*(text: string): Table[string, string] =
  ## Keys are returned as "section.key" ("key" when outside any section).
  var section = ""
  for raw in text.splitLines:
    let line = raw.strip()
    if line.len == 0 or line[0] in {';', '#'}: continue
    if line[0] == '[' and line[^1] == ']':
      section = line[1 .. ^2].strip()
      continue
    let eq = line.find('=')
    if eq < 1: continue
    let key = line[0 ..< eq].strip()
    result[(if section.len > 0: section & "." & key else: key)] = line[eq + 1 .. ^1].strip()
