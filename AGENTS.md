# AGENTS.md

Guidance for AI agents working in this repository.

## Project

Nim single page app (Karax, JS backend) that collects DNA sequencing project metadata plus a sample spreadsheet and submits a HelpSpot ticket with a YAML and a CSV attachment. Output is static files in `public/`. `src/server.nim` (mummy) only serves `public/` for local testing.

## Commands

- `nimble web` – build `public/app.js` and copy `index.html` into `public/`
- `nimble webdemo` – same with `-d:demo`: adds a "Fill test data" button and marks ticket notes `[TEST SUBMISSION]`
- `nimble servedemo` – `webdemo` then serve
- `nimble serve` – build and serve on `http://127.0.0.1:8765` (`PORT` env overrides)
- `nimble test` – unit tests (`tests/test_lib.nim`, native backend)

Server needs `--threads:on` (already in the task). `public/` and `bin/` are generated; never edit them.

## Structure

- `src/app.nim` – UI, state, submit. JS backend only.
- `src/jsbridge.nim` – browser glue in Nim (file reading, SheetJS via the `XLSX` global, FormData, fetch). There is no hand written JS.
- `index.html` (package root) – the page shell; copied to `public/` by `nimble web`.
- `src/lib/*.nim` – pure Nim, must compile on both native and JS backends and stay free of DOM imports so they can be unit tested natively.
  - `validation.nim` validators; `schema.nim` project fields and sample columns; `sheet.nim` grid validation/import/export; `csv.nim`; `ini.nim`; `yamlout.nim`.
- `config.ini` (package root) – build-time config (HelpSpot URL, category id), embedded in `app.js` via `staticRead` and parsed by `src/lib/ini.nim`. It is not copied to `public/` or fetched at runtime. The URL must stay in this file, not in code.

## Conventions and constraints

- Do not use `import std/prelude`; import specific modules.
- Every `ProjectField` and `Column` needs a `help` string; it feeds the ARIA tooltip rendered by `renderHelp` in `src/app.nim` (trigger button + `aria-describedby` + `role="tooltip"`, Escape to close). Keep that pattern when changing it.
- Add or change validation only through the validator lists in `src/lib/schema.nim`. New validators go in `validation.nim`: empty values must pass (only `required` rejects empty) and the return is an error string or `""`.
- HelpSpot has no CORS. The POST uses `mode: "no-cors"`; only network errors can be detected. Do not add code that reads the response.
- Karax notes: handler signature `proc (ev: Event; n: VNode)`; read input text with `getInputText(n)`; call `redraw()` in async callbacks; import `karax/kdom` (with the `karax/` prefix) for DOM types.
- `importjs` patterns use `#` placeholders in argument order (no `$1` indexing); reorder proc parameters instead.
- Tailwind and SheetJS load from CDNs in `index.html`.
- Run `nimble test` and `nimble web` after changes; there are no automated browser tests, so UI changes need manual verification via `nimble serve`.
