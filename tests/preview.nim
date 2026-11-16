import ../src/[model, update, io, main]

proc previewModel(): AppModel =
  result = initialModel()
  for (key, value) in [
    ("contact_name", "Renée García"),
    ("contact_email", "alex.morgan@example.com"),
    ("principal_investigator", "José François"),
    ("pi_email", "jordan.lee@example.com"),
    ("po_number", "PO123456"),
    ("institution", "UConn (Storrs, Avery Point, or other)"),
    ("is_isg_member", "Yes"),
    ("library_preparation", "Library preparation needed"),
    ("instrument", "Illumina NovaSeq 6000"),
    ("novaseq_configuration", "PE 150"),
    ("description", "Étude génomique: séquençage de café et de maïs."),
    ("irb_certification", "An active/approved IRB protocol is not needed for these samples")
  ]:
    update(result, Msg(kind: setProjectField, column: key, value: value))
  while result.samples.len > 2:
    update(result, Msg(kind: removeSample, row: result.samples.len - 1))
  for row in 0 ..< result.samples.len:
    for (key, value) in [
      ("sample_id", "SAMPLE_00" & $(row + 1)),
      ("tube_id", "TUBE_00" & $(row + 1)),
      ("organism", if row == 0: "Coffea arabica, café" else: "Zea mays, maïs"),
      ("sample_type", "DNA"),
      ("concentration_ng_ul", "25"),
      ("volume_ul", "30"),
      ("read_depth", "30"),
      ("sample_disposition", "Return to submitter"),
      ("notes", if row == 0: "Échantillon préparé à Montréal" else: "Échantillon préparé à Québec")
    ]:
      update(result, Msg(kind: setSampleCell, row: row, column: key, value: value))

proc showSubmissionPreview(note, yaml, csv: cstring) {.importjs: """
  (function(note, yaml, csv) {
    const dialog = document.createElement('dialog');
    dialog.className = 'w-[min(42rem,calc(100%-2rem))] rounded-lg border border-slate-200 bg-white p-0 text-slate-900 shadow-xl backdrop:bg-black/50';
    dialog.setAttribute('aria-labelledby', 'preview-title');
    const content = document.createElement('div');
    content.className = 'flex max-h-[85vh] flex-col';
    const heading = document.createElement('h2');
    heading.id = 'preview-title';
    heading.className = 'border-b border-slate-200 px-6 py-4 text-lg font-semibold';
    heading.textContent = 'Submission preview';
    const body = document.createElement('pre');
    body.className = 'overflow-auto whitespace-pre-wrap break-words px-6 py-5 text-sm';
    body.textContent = note;
    const actions = document.createElement('div');
    actions.className = 'flex flex-wrap items-center gap-3 border-t border-slate-200 px-6 py-4';
    const urls = [];
    for (const [filename, value, type, label] of [
      ['project.yaml', yaml, 'application/yaml', 'Download project YAML'],
      ['samples.csv', csv, 'text/csv', 'Download samples CSV']
    ]) {
      const url = URL.createObjectURL(new Blob([value], {type: type + ';charset=utf-8'}));
      urls.push(url);
      const link = document.createElement('a');
      link.href = url;
      link.download = filename;
      link.className = 'rounded-md border border-slate-300 px-3 py-2 text-sm font-medium hover:bg-slate-50';
      link.textContent = label;
      actions.appendChild(link);
    }
    const close = document.createElement('button');
    close.type = 'button';
    close.className = 'ml-auto rounded-md bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800';
    close.textContent = 'Close';
    close.addEventListener('click', () => dialog.close());
    actions.appendChild(close);
    content.append(heading, body, actions);
    dialog.appendChild(content);
    document.body.appendChild(dialog);
    dialog.addEventListener('close', () => {
      urls.forEach(url => URL.revokeObjectURL(url));
      dialog.remove();
    });
    dialog.showModal();
    close.focus();
  })(#, #, #)
""".}

proc submitPreview(state: AppModel) =
  showSubmissionPreview(cstring(projectMessage(state.project)), cstring(projectYaml(state.project)), cstring(samplesCsv(state)))

startApp(previewModel(), submitPreview)