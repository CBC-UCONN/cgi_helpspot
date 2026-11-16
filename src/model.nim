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
    required*: bool
    fullWidth*: bool
    defaultValue*: string
    displayIf*: ProjectCondition
    spreadsheetDependency*: bool
    validators*: seq[Validator]

  SampleColumnDef* = object
    key*: string
    label*: string
    help*: string
    required*: bool
    widthClass*: string
    options*: seq[string]
    uniqueMessage*: string
    displayIf*: ProjectCondition
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
  indexChars = {'A', 'C', 'G', 'T', 'N', 'a', 'c', 'g', 't', 'n', '-', '+'}

let
  institutionOptions = @[
    "UConn (Storrs, Avery Point, or other)", "UConn Health", "JAX-GM", "Other"
  ]
  membershipOptions = @["Yes", "No"]


  irbOptions = @[
    "An active/approved IRB protocol is not needed for these samples",
    "I certify that the samples I am submitting fall under an active/approved IRB protocol and all sample names have been de-identified",
  ]

  libraryOptions = @[
    "Library preparation needed",
    "User prepared library",
  ]

  sampleTypeOptions = @["DNA", "RNA"]

  instrumentOptions = @[
    "Illumina NovaSeq 6000", 
    "PacBio Sequel IIe", 
    "PacBio Revio", 
    "ONT MinION", 
    "ONT PromethION"
  ]

  novaseqOptions = @[
    "SE 35",
    "PE 50",
    "PE 100",
    "PE 150",
    "PE 250",
  ]

  sampleDispositionOptions = @[
    "Return to submitter",
    "Destroy",
  ]

  libraryPrepOptions = @[
    "NEBNext Ultra II DNA Library Prep Kit",
    "NEBNext Ultra II RNA Library Prep Kit",
    "Illumina DNA Prep Kit",
    "Illumina RNA Prep Kit",

  ]



let projectSchema* = @[

  # Contact name
  ProjectFieldDef(
    key: "contact_name", label: "Contact name", kind: textField, required: true,
    validators: @[maxLength(120)],
    help: "Name of primary contact person."
  ),

 # Contact email
  ProjectFieldDef(
    key: "contact_email", label: "Contact email", kind: emailField, required: true,
    validators: @[validEmail()],
    help: "Email address of primary contact person."
  ),

  # Principal investigator
  ProjectFieldDef(
    key: "principal_investigator", label: "Principal investigator", kind: textField, required: true,
    validators: @[maxLength(120)],
    help: "Name of the principal investigator."
  ),

  # Contact PI
  ProjectFieldDef(
    key: "pi_email", label: "PI email", kind: textField, required: true,
    validators: @[maxLength(120)],
    help: "Email address of the PI contact."
  ),

  # Institution
  ProjectFieldDef(
    key: "institution", label: "Institution", kind: selectField,
    options: institutionOptions, 
    help: "Select the institution associated with this project.",
  ),

  # ISG member
  ProjectFieldDef(
    key: "is_isg_member", label: "ISG member", kind: choiceField,
    options: membershipOptions, 
    help: "Indicate if the submitter is an ISG member.",
  ),

  # PO number
  ProjectFieldDef(
    key: "po_number", label: "PO number", kind: textField,
    validators: @[maxLength(60)],
    help: "Purchase order number.",
  ),

  # Library Preparation
  ProjectFieldDef(
    key: "library_preparation", label: "Library Preparation", kind: choiceField,
    options: libraryOptions,
    help: "Select the library preparation status for the project.",
    spreadsheetDependency: true,
  ),

  # Instrument
  ProjectFieldDef(
    key: "instrument", label: "Instrument", kind: selectField,
    options: instrumentOptions, 
    help: "Select the instrument used for the project.",
    spreadsheetDependency: true,
  ),

  # NovaSeq configuration
  ProjectFieldDef(
    key: "novaseq_configuration", label: "NovaSeq Configuration", kind: selectField,
    options: novaseqOptions, 
    displayIf: proc(project: ProjectForm): bool =
    project.field("instrument") == "Illumina NovaSeq 6000",
    help: "Select the NovaSeq configuration used for the project.",
  ),


  # Description
  ProjectFieldDef(
    key: "description", label: "Description", kind: textareaField,
    fullWidth: true,
    validators: @[maxLength(4000)],
    help: "Describe the project and any relevant requirements.", 
  ),

  # IRB certification
  ProjectFieldDef(
    key: "irb_certification", label: "IRB certification", kind: choiceField, required: true,
    options: irbOptions, 
    fullWidth: true,
    help: "In accordance with the University of Connecticut - Storrs Institutional Review Board (IRB), any DNA/RNA samples derived from human subjects being submitted to the Center for Genome Innovation for processing (includes all listed services provided by the CGI or Chromosome Core) must be covered by an approved and active IRB protocol. The principal investigator listed on this sample submission form must be the same PI listed on the approved IRB protocol. All human subject sample names must be de-identified. Check the appropriate box."
  )
]

let sampleColumnSchema* = @[
  # Sample ID
  SampleColumnDef(
    key: "sample_id", label: "Sample ID", required: true, widthClass: "min-w-40",
    help: "Unique ID using letters, numbers, underscores, hyphens, or periods.",
    uniqueMessage: "Sample ID must be unique.",
    displayIf: proc(project: ProjectForm): bool =
      project.field("library_preparation") == "Library preparation needed",
    validators: @[maxLength(50), allowedChars(identifierChars, "letters, numbers, underscores, hyphens, and periods")],
  ),

  # Library ID
  SampleColumnDef(
    key: "library_id", label: "Library ID", required: true, widthClass: "min-w-40",
    help: "Unique ID using letters, numbers, underscores, hyphens, or periods.",
    uniqueMessage: "Library ID must be unique.",
    displayIf: proc(project: ProjectForm): bool =
      project.field("library_preparation") == "User prepared library",
    validators: @[maxLength(50), allowedChars(identifierChars, "letters, numbers, underscores, hyphens, and periods")],
  ),
  
  # Tube ID
  SampleColumnDef(
    key: "tube_id", label: "Tube ID", required: true, widthClass: "min-w-28",
    help: "Up to 10 letters, numbers, underscores, hyphens, or periods.",
    validators: @[maxLength(10), allowedChars(identifierChars, "letters, numbers, underscores, hyphens, and periods")],
  ),

  # Organism
  SampleColumnDef(
    key: "organism", label: "Organism", required: true, widthClass: "min-w-40",
    validators: @[maxLength(120)],
    help: "Name of the organism or group of organisms."
  ),

  # Sample type
  SampleColumnDef(
    key: "sample_type", label: "Sample type", required: true, widthClass: "min-w-36",
    options: sampleTypeOptions, 
    validators: @[oneOf(sampleTypeOptions)],
    displayIf: proc(project: ProjectForm): bool =
      project.field("library_preparation") == "Library preparation needed"
  ),

  # Library type
  SampleColumnDef(
    key: "library_type", label: "Library type", widthClass: "min-w-40",
    options: libraryPrepOptions,
    validators: @[maxLength(100)],
    displayIf: proc(project: ProjectForm): bool =
      project.field("library_preparation") == "User prepared library",
  ),

  # Concentration (ng/uL)
  SampleColumnDef(
    key: "concentration_ng_ul", label: "Concentration (ng/uL)", required: true, widthClass: "min-w-40",
    validators: @[numberRange(0, 10000)],
  ),

  # Volume (uL)
  SampleColumnDef(
    key: "volume_ul", label: "Volume (uL)", required: true, widthClass: "min-w-32",
    validators: @[numberRange(0, 10000)],
  ),

  # Desired Read depth
  SampleColumnDef(
    key: "read_depth", label: "Desired Read Depth", required: true, widthClass: "min-w-32",
    validators: @[numberRange(0, 10000)],
  ),

  # i7 Index
  SampleColumnDef(
    key: "i7_index", label: "i7 Index", widthClass: "min-w-40",
    validators: @[maxLength(40), allowedChars(indexChars, "A, C, G, T, or N allowed")],
    displayIf: proc(project: ProjectForm): bool =
      project.field("library_preparation") == "User prepared library",
    help: "i7 Index sequence. Valid values are A, C, G, T, or N",
  ),

  # i5 Index
  SampleColumnDef(
    key: "i5_index", label: "i5 Index", widthClass: "min-w-40",
    validators: @[maxLength(40), allowedChars(indexChars, "A, C, G, T, or N allowed")],
    displayIf: proc(project: ProjectForm): bool =
      project.field("library_preparation") == "User prepared library",
    help: "i5 Index sequence. Valid values are A, C, G, T, or N",
  ),

  # Sample Disposition
  SampleColumnDef(
    key: "sample_disposition", label: "Sample Disposition", widthClass: "min-w-40",
    options: sampleDispositionOptions, validators: @[oneOf(sampleDispositionOptions)],
    help: "What should be done with the any remaining sample upon completion. Sample ."
  ),

  # Notes
  SampleColumnDef(
    key: "notes", label: "Notes", widthClass: "min-w-48", 
    validators: @[maxLength(500)],
  ),
]

proc setSampleValue*(row: var SampleRow; key, value: string) =
  for column in sampleColumnSchema:
    if column.key == key:
      row[key] = value
      return

proc visibleProjectFields*(project: ProjectForm): seq[ProjectFieldDef] =
  for fieldDef in projectSchema:
    if fieldDef.displayIf == nil or fieldDef.displayIf(project):
      result.add fieldDef

proc visibleSampleColumns*(project: ProjectForm): seq[SampleColumnDef] =
  for column in sampleColumnSchema:
    if column.displayIf == nil or column.displayIf(project):
      result.add column

proc spreadsheetDependenciesSelected*(project: ProjectForm): bool =
  for fieldDef in projectSchema:
    if fieldDef.spreadsheetDependency:
      let value = project.field(fieldDef.key)
      if value.len == 0 or value notin fieldDef.options:
        return false
  true

proc emptySample*(): SampleRow =
  result = initTable[string, string]()
  for column in sampleColumnSchema:
    result[column.key] = ""

proc defaultProject*(): ProjectForm =
  result = initTable[string, string]()
  for fieldDef in projectSchema:
    result[fieldDef.key] = fieldDef.defaultValue

proc initialModel*(): AppModel =
  result = AppModel(project: defaultProject())
  for _ in 0 ..< 10:
    result.samples.add emptySample()
