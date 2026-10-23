## Declarative definitions of the project form fields and sample spreadsheet columns.
## To change validation, edit the validator lists below; see validation.nim for available validators.
## `help` is shown in the tooltip next to each label.
import validation

type
  FieldKind* = enum
    fkText, fkTextArea, fkSelect, fkDate

  ProjectField* = object
    key*, label*, placeholder*, help*: string
    kind*: FieldKind
    options*: seq[string]
    validators*: seq[Validator]

  Column* = object
    key*, title*, help*: string
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
    help: "First name of the person we should contact about this project. " &
          "They become the requester on the HelpSpot ticket.",
    validators: @[required(), maxLength(60)]),
  ProjectField(key: "contact_last_name", label: "Contact last name", kind: fkText,
    help: "Last name of the project contact.",
    validators: @[required(), maxLength(60)]),
  ProjectField(key: "contact_email", label: "Contact email", kind: fkText,
    placeholder: "name@example.org",
    help: "Address where status updates and questions about the project are sent.",
    validators: @[required(), email()]),
  ProjectField(key: "institution", label: "Institution / lab", kind: fkText,
    help: "Organisation or laboratory the samples come from.",
    validators: @[required(), maxLength(120)]),
  ProjectField(key: "principal_investigator", label: "Principal investigator", kind: fkText,
    help: "Name of the investigator responsible for the project, if different from the contact.",
    validators: @[required(), maxLength(120)]),
  ProjectField(key: "project_name", label: "Project name", kind: fkText,
    help: "A short, unique name for the project. It is also used to name the attached files.",
    validators: @[required(), maxLength(120)]),
  ProjectField(key: "organism", label: "Organism / species", kind: fkText,
    placeholder: "e.g. Homo sapiens",
    help: "Main organism being sequenced. Use the scientific name where possible.",
    validators: @[required(), maxLength(120)]),
  ProjectField(key: "sequencing_type", label: "Sequencing type", kind: fkSelect,
    options: seqTypes,
    help: "The kind of sequencing you want, for example whole genome or RNA-seq. " &
          "Choose Other and describe it in the notes if none fit.",
    validators: @[required(), oneOf(seqTypes)]),
  ProjectField(key: "platform", label: "Platform", kind: fkSelect,
    options: platforms,
    help: "The sequencing instrument you would like the samples run on.",
    validators: @[required(), oneOf(platforms)]),
  ProjectField(key: "read_length", label: "Read length (bp)", kind: fkText,
    placeholder: "e.g. 150",
    help: "Desired read length in base pairs as a whole number. Leave blank if unsure.",
    validators: @[numberRange(1, 1_000_000, integer = true)]),
  ProjectField(key: "target_coverage", label: "Target coverage / depth", kind: fkText,
    placeholder: "e.g. 30x or 20M reads",
    help: "How much data you need per sample, either as coverage (30x) or number of reads.",
    validators: @[maxLength(60)]),
  ProjectField(key: "due_date", label: "Requested completion date", kind: fkDate,
    help: "The date you would like results by. This is a request, not a guarantee.",
    validators: @[]),
  ProjectField(key: "po_number", label: "PO / billing reference", kind: fkText,
    help: "Purchase order or account number to bill, if applicable.",
    validators: @[maxLength(60)]),
  ProjectField(key: "description", label: "Project description / notes", kind: fkTextArea,
    help: "Anything else we should know: special handling, library prep details, " &
          "analysis requests or deadlines.",
    validators: @[maxLength(4000)]),
]

let sampleColumns* = @[
  Column(key: "sample_id", title: "Sample ID", aliases: @["id", "sample", "sampleid"],
    widthClass: "w-40",
    help: "Unique identifier for the sample, as written on the tube. " &
          "Letters, digits, '_', '-' and '.' only.",
    validators: @[required(), maxLength(50),
                  allowedChars(idChars, "letters, digits, '_', '-' and '.'"),
                  uniqueInColumn("Sample ID must be unique")]),
  Column(key: "sample_name", title: "Sample Name", aliases: @["name"],
    widthClass: "w-48",
    help: "Optional descriptive name for the sample.",
    validators: @[maxLength(100)]),
  Column(key: "sample_type", title: "Sample Type", aliases: @["type"],
    options: sampleTypes, widthClass: "w-32",
    help: "What you are submitting: genomic DNA, RNA, a prepared library and so on. " &
          "Pick a suggestion or type one.",
    validators: @[required(), oneOf(sampleTypes)]),
  Column(key: "organism", title: "Organism", aliases: @["species"],
    widthClass: "w-48",
    help: "Organism for this sample. Only needed when it differs from the project organism.",
    validators: @[maxLength(120)]),
  Column(key: "concentration_ng_ul", title: "Concentration (ng/uL)",
    aliases: @["concentration", "conc", "concentrationngul"],
    widthClass: "w-40",
    help: "Measured concentration in nanograms per microlitre, as a number.",
    validators: @[required(), numberRange(0, 100_000)]),
  Column(key: "volume_ul", title: "Volume (uL)", aliases: @["volume", "vol"],
    widthClass: "w-32",
    help: "Volume of sample provided in microlitres, as a number.",
    validators: @[required(), numberRange(0, 100_000)]),
  Column(key: "index_barcode", title: "Index / Barcode", aliases: @["index", "barcode"],
    widthClass: "w-40",
    help: "Index or barcode sequence for pooled libraries, using the bases A, C, G, T and N.",
    validators: @[allowedChars(baseChars, "bases A, C, G, T, N"), maxLength(40)]),
  Column(key: "notes", title: "Notes", aliases: @["comments", "comment"],
    widthClass: "w-64",
    help: "Optional comments about this sample, such as degradation or handling needs.",
    validators: @[maxLength(500)]),
]
