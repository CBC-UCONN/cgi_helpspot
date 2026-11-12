type
  AssayKind* = enum
    assayBulk = "Bulk DNA"
    assayAmplicon = "Amplicon"
    assaySingleCell = "Single-cell DNA"
    assayMetagenomic = "Metagenomic"

  ReadKind* = enum
    singleEnd = "Single-end"
    pairedEnd = "Paired-end"

  IndexKind* = enum
    noIndex = "No index"
    dualIndex = "Dual index (i7 + i5)"
    singleIndex = "Single index (i7)"

  ProjectForm* = object
    projectName*: string
    requester*: string
    email*: string
    organism*: string
    assay*: AssayKind
    readType*: ReadKind
    indexType*: IndexKind
    libraryPrep*: string
    customReference*: bool
    referenceName*: string
    notes*: string

  SampleRow* = object
    sampleId*: string
    sampleName*: string
    source*: string
    strain*: string
    cellType*: string
    libraryPrep*: string
    i7Index*: string
    i5Index*: string
    reference*: string

  ValidationError* = object
    field*: string
    message*: string

  # A schema predicate is deliberately kept independent of the view. This
  # lets field/column visibility be declared next to the schema definition.
  ProjectCondition* = proc(project: ProjectForm): bool

  ProjectFieldKind* = enum
    textField
    emailField
    selectField
    checkboxField
    textareaField

  ProjectFieldDef* = object
    key*: string
    label*: string
    kind*: ProjectFieldKind
    options*: seq[string]
    help*: string
    visibleIf*: ProjectCondition

  SampleColumnDef* = object
    key*: string
    label*: string
    visibleIf*: ProjectCondition

  AppSchema* = object
    projectFields*: seq[ProjectFieldDef]
    sampleColumns*: seq[SampleColumnDef]

  AppModel* = object
    project*: ProjectForm
    samples*: seq[SampleRow]
    errors*: seq[ValidationError]
    csvMessage*: string
    submitted*: bool
    submissionMessage*: string

proc alwaysVisible*(project: ProjectForm): bool = true

proc assayIs*(assay: AssayKind): ProjectCondition =
  result = proc(project: ProjectForm): bool = project.assay == assay

proc assayIsNot*(assay: AssayKind): ProjectCondition =
  result = proc(project: ProjectForm): bool = project.assay != assay

proc indexIs*(indexType: IndexKind): ProjectCondition =
  result = proc(project: ProjectForm): bool = project.indexType == indexType

proc indexIsNot*(indexType: IndexKind): ProjectCondition =
  result = proc(project: ProjectForm): bool = project.indexType != indexType

proc customReferenceEnabled*(project: ProjectForm): bool = project.customReference

proc projectSchema*(): seq[ProjectFieldDef] =
  ## The project form is defined here. To add a field, add its model member
  ## and one schema entry rather than changing the view layout.
  @[
    ProjectFieldDef(key: "projectName", label: "Project name", kind: textField, visibleIf: alwaysVisible),
    ProjectFieldDef(key: "requester", label: "Requester", kind: textField, visibleIf: alwaysVisible),
    ProjectFieldDef(key: "email", label: "Email", kind: emailField, visibleIf: alwaysVisible),
    ProjectFieldDef(key: "organism", label: "Organism", kind: textField, visibleIf: alwaysVisible),
    ProjectFieldDef(
      key: "assay", label: "Assay", kind: selectField,
      options: @[$assayBulk, $assayAmplicon, $assaySingleCell, $assayMetagenomic],
      visibleIf: alwaysVisible
    ),
    ProjectFieldDef(
      key: "readType", label: "Read type", kind: selectField,
      options: @[$singleEnd, $pairedEnd], visibleIf: alwaysVisible
    ),
    ProjectFieldDef(
      key: "indexType", label: "Indexing", kind: selectField,
      options: @[$noIndex, $singleIndex, $dualIndex], visibleIf: alwaysVisible
    ),
    ProjectFieldDef(key: "libraryPrep", label: "Library preparation", kind: textField, visibleIf: alwaysVisible),
    ProjectFieldDef(
      key: "customReference", label: "Use a custom reference", kind: checkboxField,
      help: "Adds reference fields to the sample table.", visibleIf: alwaysVisible
    ),
    ProjectFieldDef(
      key: "referenceName", label: "Reference name", kind: textField,
      visibleIf: customReferenceEnabled
    ),
    ProjectFieldDef(key: "notes", label: "Project notes", kind: textareaField, visibleIf: alwaysVisible)
  ]

proc sampleColumnSchema*(): seq[SampleColumnDef] =
  ## Sample-table columns and their display conditions live in one schema.
  ## The same schema is used by the view and CSV code.
  @[
    SampleColumnDef(key: "sample_id", label: "Sample ID", visibleIf: alwaysVisible),
    SampleColumnDef(key: "sample_name", label: "Sample name", visibleIf: alwaysVisible),
    SampleColumnDef(key: "source", label: "Source", visibleIf: alwaysVisible),
    SampleColumnDef(
      key: "strain", label: "Strain",
      visibleIf: proc(project: ProjectForm): bool = project.assay in {assayBulk, assayAmplicon, assayMetagenomic}
    ),
    SampleColumnDef(
      key: "cell_type", label: "Cell type",
      visibleIf: assayIs(assaySingleCell)
    ),
    SampleColumnDef(key: "library_prep", label: "Library prep", visibleIf: alwaysVisible),
    SampleColumnDef(
      key: "i7_index", label: "i7 index",
      visibleIf: proc(project: ProjectForm): bool = project.indexType in {singleIndex, dualIndex}
    ),
    SampleColumnDef(
      key: "i5_index", label: "i5 index",
      visibleIf: indexIs(dualIndex)
    ),
    SampleColumnDef(
      key: "reference", label: "Reference",
      visibleIf: customReferenceEnabled
    )
  ]

proc visibleProjectFields*(project: ProjectForm): seq[ProjectFieldDef] =
  for field in projectSchema():
    if field.visibleIf(project):
      result.add field

proc visibleSampleColumns*(project: ProjectForm): seq[SampleColumnDef] =
  for column in sampleColumnSchema():
    if column.visibleIf(project):
      result.add column

proc emptySample*(): SampleRow =
  SampleRow()

proc defaultProject*(): ProjectForm =
  ProjectForm(
    assay: assayBulk,
    readType: pairedEnd,
    indexType: dualIndex,
    customReference: false
  )

proc initialModel*(): AppModel =
  AppModel(project: defaultProject(), samples: @[emptySample()])
