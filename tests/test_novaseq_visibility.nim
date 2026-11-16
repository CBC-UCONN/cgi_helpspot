import std/[unittest, sequtils]
import ../src/[model, update]

proc hasNovaSeqConfiguration(project: ProjectForm): bool =
  visibleProjectFields(project).anyIt(it.key == "novaseq_configuration")

proc hasSampleColumn(project: ProjectForm; key: string): bool =
  visibleSampleColumns(project).anyIt(it.key == key)

suite "NovaSeq configuration visibility":
  test "only the NovaSeq instrument displays its configuration":
    var state = initialModel()
    check not state.project.hasNovaSeqConfiguration()

    let instrumentField = projectSchema.filterIt(it.key == "instrument")[0]
    for instrument in instrumentField.options:
      update(state, Msg(kind: setProjectField, column: "instrument", value: instrument))
      check state.project.hasNovaSeqConfiguration() == (instrument == "Illumina NovaSeq 6000")

    update(state, Msg(kind: setProjectField, column: "instrument", value: "Illumina NovaSeq 6000"))
    update(state, Msg(kind: setProjectField, column: "novaseq_configuration", value: "PE 150"))
    update(state, Msg(kind: setProjectField, column: "instrument", value: "PacBio Revio"))
    check not state.project.hasNovaSeqConfiguration()
    update(state, Msg(kind: setProjectField, column: "instrument", value: "Illumina NovaSeq 6000"))
    check state.project.hasNovaSeqConfiguration()
    check state.project.field("novaseq_configuration") == "PE 150"

  test "library columns follow the selected library preparation option":
    var state = initialModel()

    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "User prepared library"))
    check state.project.hasSampleColumn("library_id")
    check not state.project.hasSampleColumn("sample_id")
    check state.project.hasSampleColumn("tube_id")

    update(state, Msg(kind: setProjectField, column: "library_preparation", value: "Library preparation needed"))
    check not state.project.hasSampleColumn("library_id")
    check state.project.hasSampleColumn("sample_id")
    check state.project.hasSampleColumn("tube_id")