## Composable validators. A validator returns "" when the value is valid, otherwise an error message.
## Except for `required`, validators accept empty values so they can be combined freely.
import std/[strutils, tables]

type
  ValidationContext* = object
    ## Per column data that validators needing sibling values (e.g. uniqueness) can use.
    counts*: CountTable[string]

  Validator* = proc (value: string; ctx: ValidationContext): string {.closure.}

proc normalized*(value: string): string = value.strip()

proc required*(msg = "Required"): Validator =
  result = proc (v: string; ctx: ValidationContext): string =
    if v.normalized.len == 0: msg else: ""

proc minLength*(n: int): Validator =
  result = proc (v: string; ctx: ValidationContext): string =
    if v.normalized.len > 0 and v.normalized.len < n: "At least " & $n & " characters" else: ""

proc maxLength*(n: int): Validator =
  result = proc (v: string; ctx: ValidationContext): string =
    if v.normalized.len > n: "At most " & $n & " characters" else: ""

proc allowedChars*(chars: set[char]; description: string): Validator =
  result = proc (v: string; ctx: ValidationContext): string =
    for c in v.normalized:
      if c notin chars: return "Only " & description & " allowed"
    ""

proc oneOf*(options: seq[string]; ignoreCase = true): Validator =
  result = proc (v: string; ctx: ValidationContext): string =
    let val = v.normalized
    if val.len == 0: return ""
    for o in options:
      if (if ignoreCase: cmpIgnoreCase(o, val) == 0 else: o == val): return ""
    "Must be one of: " & options.join(", ")

proc numberRange*(minVal, maxVal: float; integer = false): Validator =
  result = proc (v: string; ctx: ValidationContext): string =
    let val = v.normalized
    if val.len == 0: return ""
    for c in val:
      if c notin {'0' .. '9', '.', '-', '+', 'e', 'E'}: return "Must be a number"
    if integer and val.find({'.', 'e', 'E'}) >= 0: return "Must be a whole number"
    var n: float
    try:
      n = parseFloat(val)
    except ValueError:
      return "Must be a number"
    if n < minVal or n > maxVal: "Must be between " & $minVal & " and " & $maxVal else: ""

proc email*(): Validator =
  result = proc (v: string; ctx: ValidationContext): string =
    let val = v.normalized
    if val.len == 0: return ""
    let at = val.find('@')
    if at < 1 or val.find('@', at + 1) >= 0 or ' ' in val: return "Invalid email address"
    let domain = val[at + 1 .. ^1]
    if domain.len < 3 or '.' notin domain or domain[0] == '.' or domain[^1] == '.':
      return "Invalid email address"
    ""

proc uniqueInColumn*(msg = "Duplicate value"): Validator =
  result = proc (v: string; ctx: ValidationContext): string =
    let val = v.normalized
    if val.len > 0 and ctx.counts.getOrDefault(val) > 1: msg else: ""

proc validate*(value: string; validators: openArray[Validator];
               ctx = ValidationContext()): string =
  ## Returns the first error message, or "" if every validator passes.
  for check in validators:
    let err = check(value, ctx)
    if err.len > 0: return err
  ""
