import std/[tables, sets]
import validators

type
  ProjectForm* = Table[string, string]
  SampleRow* = Table[string, string]

  ValidationError* = object
    field*: string
    message*: string

  ProjectCondition* = proc(project: ProjectForm): bool

  ProjectFieldKind* = enum
    textField
    emailField
    selectField
    checkboxField
    textareaField
    choiceField

  ProjectFieldDef* = object
    key*: string
    label*: string
    kind*: ProjectFieldKind
    options*: seq[string]
    help*: string
    placeholder*: string
    fullWidth*: bool
    defaultValue*: string
    visibleIf*: ProjectCondition
    validators*: seq[Validator]

  SampleColumnDef* = object
    key*: string
    label*: string
    help*: string
    widthClass*: string
    options*: seq[string]
    uniqueMessage*: string
    visibleIf*: ProjectCondition
    validators*: seq[Validator]

  AppSchema* = object
    projectFields*: seq[ProjectFieldDef]
    sampleColumns*: seq[SampleColumnDef]

  AppModel* = object
    project*: ProjectForm
    samples*: seq[SampleRow]
    sampleRevision*: int
    errors*: seq[ValidationError]
    editedFields*: HashSet[string]
    liveFields*: HashSet[string]
    csvMessage*: string
    submissionMessage*: string

proc alwaysVisible*(project: ProjectForm): bool = true

proc field*(values: Table[string, string]; key: string): string =
  values.getOrDefault(key)

const
  identifierChars = {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.'}
  barcodeChars = {'A', 'C', 'G', 'T', 'N', 'a', 'c', 'g', 't', 'n', '-', '+'}

let
  institutionOptions = @[
    "UConn (Storrs, Avery Point, or other)", "UConn Health", "JAX-GM", "Other"
  ]
  membershipOptions = @["Yes", "No"]
  serviceOptions = @[
    "Complete NGS workflow (sample QC through NGS sequencing)",
    "Next Generation Sequencing (NGS) Library Preparation only",
    "Customer prepared library QC and CGI sequencing",
    "Digital Droplet PCR (Designed Probe Assays)",
    "Digital Droplet PCR (Evagreen assays)",
    "PacBio Sequel IIe/Revio library prep and sequencing",
    "PacBio Sequel IIe/Revio - RUN ONLY",
    "ONT MinION/PromethION library prep and sequencing",
    "ONT MinION/Promethion - RUN ONLY"
  ]
  irbOptions = @[
    "I certify that the samples I am submitting fall under an active/approved IRB protocol and all sample names have been de-identified",
    "An active/approved IRB protocol is not needed for these samples"
  ]
  sampleTypeOptions = @["gDNA", "DNA", "RNA", "cDNA", "Library", "Amplicon", "Other"]

let projectSchema* = @[
  # Contact name
  ProjectFieldDef(
    key: "contact_name", label: "Contact name", kind: textField,
    placeholder: "Full name", validators: @[required("Contact name"), maxLength(120)]
  ),
  # Contact email
  ProjectFieldDef(
    key: "contact_email", label: "Contact email", kind: emailField,
    placeholder: "name@example.com", validators: @[required("Contact email"), validEmail()]
  ),
  # Principal investigator
  ProjectFieldDef(
    key: "principal_investigator", label: "Principal investigator", kind: textField,
    placeholder: "Principal investigator name",
    validators: @[required("Principal investigator"), maxLength(120)]
  ),
  # Contact PI
  ProjectFieldDef(
    key: "contact_pi", label: "Contact PI", kind: textField,
    placeholder: "Contact PI name", validators: @[required("Contact PI"), maxLength(120)]
  ),
  # Institution
  ProjectFieldDef(
    key: "institution", label: "Institution", kind: selectField,
    options: institutionOptions, validators: @[oneOf(institutionOptions)]
  ),
  # ISG member
  ProjectFieldDef(
    key: "is_isg_member", label: "ISG member", kind: choiceField,
    options: membershipOptions, validators: @[oneOf(membershipOptions)]
  ),
  # Service requested
  ProjectFieldDef(
    key: "service_requested", label: "Service requested", kind: selectField,
    options: serviceOptions, fullWidth: true, validators: @[oneOf(serviceOptions)]
  ),
  # Read length
  ProjectFieldDef(
    key: "read_length", label: "Read length", kind: textField,
    help: "Optional read length in bases.", placeholder: "Bases",
    validators: @[numberRange(1, 1000000, integer = true)]
  ),
  # PO number
  ProjectFieldDef(
    key: "po_number", label: "PO number", kind: textField,
    placeholder: "Purchase order number", validators: @[maxLength(60)]
  ),
  # Description
  ProjectFieldDef(
    key: "description", label: "Description", kind: textareaField,
    help: "Describe the project and any relevant requirements.", fullWidth: true,
    validators: @[maxLength(4000)]
  ),
  # IRB certification
  ProjectFieldDef(
    key: "irb_certification", label: "IRB certification", kind: choiceField,
    options: irbOptions, fullWidth: true,
    validators: @[required("IRB certification"), oneOf(irbOptions)]
  )
]

let sampleColumnSchema* = @[
  # Sample ID
  SampleColumnDef(
    key: "sample_id", label: "Sample ID", widthClass: "min-w-40",
    help: "Unique ID using letters, numbers, underscores, hyphens, or periods.",
    uniqueMessage: "Sample ID must be unique.",
    validators: @[required("Sample ID"), maxLength(50), allowedChars(identifierChars, "letters, numbers, underscores, hyphens, and periods")]
  ),
  # Tube ID
  SampleColumnDef(
    key: "tube_id", label: "Tube ID", widthClass: "min-w-28",
    help: "Up to 6 letters, numbers, underscores, hyphens, or periods.",
    validators: @[required("Tube ID"), maxLength(6), allowedChars(identifierChars, "letters, numbers, underscores, hyphens, and periods")]
  ),
  # Organism
  SampleColumnDef(
    key: "organism", label: "Organism", widthClass: "min-w-40",
    validators: @[required("Organism"), maxLength(120)]
  ),
  # Sample type
  SampleColumnDef(
    key: "sample_type", label: "Sample type", widthClass: "min-w-36",
    options: sampleTypeOptions, validators: @[required("Sample type"), oneOf(sampleTypeOptions)]
  ),
  # Concentration (ng/uL)
  SampleColumnDef(
    key: "concentration_ng_ul", label: "Concentration (ng/uL)", widthClass: "min-w-40",
    validators: @[required("Concentration"), numberRange(0, 100000)]
  ),
  # Volume (uL)
  SampleColumnDef(
    key: "volume_ul", label: "Volume (uL)", widthClass: "min-w-32",
    validators: @[required("Volume"), numberRange(0, 100000)]
  ),
  # Read depth
  SampleColumnDef(
    key: "read_depth", label: "Read depth", widthClass: "min-w-32",
    validators: @[required("Read depth"), numberRange(0, 1000000)]
  ),
  # Notes
  SampleColumnDef(
    key: "notes", label: "Notes", widthClass: "min-w-48", validators: @[maxLength(500)]
  ),
  # Library ID
  SampleColumnDef(
    key: "library_id", label: "Library ID", widthClass: "min-w-40",
    help: "Unique ID using letters, numbers, underscores, hyphens, or periods.",
    uniqueMessage: "Library ID must be unique.",
    validators: @[required("Library ID"), maxLength(50), allowedChars(identifierChars, "letters, numbers, underscores, hyphens, and periods")]
  ),
  # Library name
  SampleColumnDef(
    key: "library_name", label: "Library name", widthClass: "min-w-40",
    validators: @[maxLength(100)]
  ),
  # Library type
  SampleColumnDef(
    key: "library_type", label: "Library type", widthClass: "min-w-40",
    validators: @[maxLength(100)]
  ),
  # Index barcode
  SampleColumnDef(
    key: "index_barcode", label: "Index barcode", widthClass: "min-w-40",
    help: "Use A, C, G, T, N, hyphens, or plus signs.",
    validators: @[maxLength(40), allowedChars(barcodeChars, "A, C, G, T, N, hyphens, and plus signs")]
  )
]

proc setSampleValue*(row: var SampleRow; key, value: string) =
  for column in sampleColumnSchema:
    if column.key == key:
      row[key] = value
      return

proc visibleProjectFields*(project: ProjectForm): seq[ProjectFieldDef] =
  for fieldDef in projectSchema:
    if fieldDef.visibleIf == nil or fieldDef.visibleIf(project):
      result.add fieldDef

proc visibleSampleColumns*(project: ProjectForm): seq[SampleColumnDef] =
  for column in sampleColumnSchema:
    if column.visibleIf == nil or column.visibleIf(project):
      result.add column

proc emptySample*(): SampleRow =
  result = initTable[string, string]()
  for column in sampleColumnSchema:
    result[column.key] = ""

proc defaultProject*(): ProjectForm =
  result = initTable[string, string]()
  for fieldDef in projectSchema:
    result[fieldDef.key] = fieldDef.defaultValue

proc initialModel*(): AppModel =
  AppModel(project: defaultProject(), samples: @[emptySample()])
