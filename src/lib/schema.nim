## Declarative definitions of the project form fields and sample spreadsheet columns.
## To change validation, edit the validator lists below; see validation.nim for available validators.
import validation

type
  FieldKind* = enum
    fkText, fkTextArea, fkSelect, fkDate

  ProjectField* = object
    key*, label*, placeholder*: string
    kind*: FieldKind
    options*: seq[string]
    validators*: seq[Validator]

  Column* = object
    key*, title*: string
    aliases*: seq[string]     ## extra header names recognised when importing files
    options*: seq[string]     ## suggestions offered while typing (not enforced unless a validator does)
    widthClass*: string       ## tailwind width class
    validators*: seq[Validator]

const
  sampleTypes = @["gDNA", "DNA", "RNA", "cDNA", "Library", "Amplicon", "Other"]
  seqTypes = @["Whole genome", "Exome", "Targeted panel", "Amplicon", "RNA-seq",
               "Metagenomic", "Other"]
  platforms = @["Illumina NovaSeq", "Illumina NextSeq", "Illumina MiSeq",
                "PacBio", "Oxford Nanopore", "Other"]
  idChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '-', '.'}
  baseChars = {'A', 'C', 'G', 'T', 'N', 'a', 'c', 'g', 't', 'n', '-', '+'}

let projectFields* = @[
  ProjectField(key: "contact_first_name", label: "Contact first name", kind: fkText,
    validators: @[required(), maxLength(60)]),
  ProjectField(key: "contact_last_name", label: "Contact last name", kind: fkText,
    validators: @[required(), maxLength(60)]),
  ProjectField(key: "contact_email", label: "Contact email", kind: fkText,
    placeholder: "name@example.org", validators: @[required(), email()]),
  ProjectField(key: "institution", label: "Institution / lab", kind: fkText,
    validators: @[required(), maxLength(120)]),
  ProjectField(key: "principal_investigator", label: "Principal investigator", kind: fkText,
    validators: @[required(), maxLength(120)]),
  ProjectField(key: "project_name", label: "Project name", kind: fkText,
    validators: @[required(), maxLength(120)]),
  ProjectField(key: "organism", label: "Organism / species", kind: fkText,
    placeholder: "e.g. Homo sapiens", validators: @[required(), maxLength(120)]),
  ProjectField(key: "sequencing_type", label: "Sequencing type", kind: fkSelect,
    options: seqTypes, validators: @[required(), oneOf(seqTypes)]),
  ProjectField(key: "platform", label: "Platform", kind: fkSelect,
    options: platforms, validators: @[required(), oneOf(platforms)]),
  ProjectField(key: "read_length", label: "Read length (bp)", kind: fkText,
    placeholder: "e.g. 150", validators: @[numberRange(1, 1_000_000, integer = true)]),
  ProjectField(key: "target_coverage", label: "Target coverage / depth", kind: fkText,
    placeholder: "e.g. 30x or 20M reads", validators: @[maxLength(60)]),
  ProjectField(key: "due_date", label: "Requested completion date", kind: fkDate,
    validators: @[]),
  ProjectField(key: "po_number", label: "PO / billing reference", kind: fkText,
    validators: @[maxLength(60)]),
  ProjectField(key: "description", label: "Project description / notes", kind: fkTextArea,
    validators: @[maxLength(4000)]),
]

let sampleColumns* = @[
  Column(key: "sample_id", title: "Sample ID", aliases: @["id", "sample", "sampleid"],
    widthClass: "w-40",
    validators: @[required(), maxLength(50),
                  allowedChars(idChars, "letters, digits, '_', '-' and '.'"),
                  uniqueInColumn("Sample ID must be unique")]),
  Column(key: "sample_name", title: "Sample Name", aliases: @["name"],
    widthClass: "w-48", validators: @[maxLength(100)]),
  Column(key: "sample_type", title: "Sample Type", aliases: @["type"],
    options: sampleTypes, widthClass: "w-32",
    validators: @[required(), oneOf(sampleTypes)]),
  Column(key: "organism", title: "Organism", aliases: @["species"],
    widthClass: "w-48", validators: @[maxLength(120)]),
  Column(key: "concentration_ng_ul", title: "Concentration (ng/uL)",
    aliases: @["concentration", "conc", "concentrationngul"],
    widthClass: "w-40", validators: @[required(), numberRange(0, 100_000)]),
  Column(key: "volume_ul", title: "Volume (uL)", aliases: @["volume", "vol"],
    widthClass: "w-32", validators: @[required(), numberRange(0, 100_000)]),
  Column(key: "index_barcode", title: "Index / Barcode", aliases: @["index", "barcode"],
    widthClass: "w-40",
    validators: @[allowedChars(baseChars, "bases A, C, G, T, N"), maxLength(40)]),
  Column(key: "notes", title: "Notes", aliases: @["comments", "comment"],
    widthClass: "w-64", validators: @[maxLength(500)]),
]
