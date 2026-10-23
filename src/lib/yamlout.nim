## Tiny YAML writer for flat key/value metadata (all scalars emitted as double quoted strings).
import std/strutils

proc yamlQuote*(s: string): string =
  result = "\""
  for c in s:
    case c
    of '\\': result.add "\\\\"
    of '"': result.add "\\\""
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    elif c < ' ': result.add "\\x" & toHex(ord(c), 2)
    else: result.add c
  result.add '"'

proc projectYaml*(fields: seq[(string, string)]; sampleCount: int;
                  submittedAt: string): string =
  ## Renders project metadata as a YAML document.
  result = "# DNA sequencing project metadata\n"
  result.add "submitted_at: " & yamlQuote(submittedAt) & "\n"
  result.add "sample_count: " & $sampleCount & "\n"
  result.add "project:\n"
  for (k, v) in fields:
    result.add "  " & k & ": " & yamlQuote(v) & "\n"
