import std/[strutils, math]
from std/unicode import runeLen

type Validator* = proc(value: string): string

proc required*(label: string): Validator =
  result = proc(value: string): string =
    if value.strip().len == 0: return label & " is required."

proc requiredMessage*(message: string): Validator =
  result = proc(value: string): string =
    if value.strip().len == 0: return message

proc validEmail*(): Validator =
  result = proc(value: string): string =
    let v = value.strip()
    if v.len > 0 and (v.count("@") != 1 or v.endsWith("@") or v.startsWith("@")):
      return "Enter a valid email address."

proc maxLength*(limit: int): Validator =
  result = proc(value: string): string =
    if value.runeLen > limit:
      return "Must be at most " & $limit & " characters."

proc oneOf*(options: seq[string]): Validator =
  result = proc(value: string): string =
    if value.strip().len > 0 and value notin options:
      return "Select a valid option."

proc allowedChars*(allowed: set[char]; description: string): Validator =
  result = proc(value: string): string =
    for character in value:
      if character notin allowed:
        return "Use only " & description & "."

proc numberRange*(minimum, maximum: float; integer = false): Validator =
  result = proc(value: string): string =
    let trimmed = value.strip()
    if trimmed.len == 0: return ""
    try:
      let number = parseFloat(trimmed)
      if classify(number) in {fcNan, fcInf, fcNegInf} or number < minimum or number > maximum or (integer and floor(number) != number):
        return "Enter " & (if integer: "a whole number" else: "a number") & " between " & $minimum & " and " & $maximum & "."
    except ValueError:
      return "Enter a valid number."

