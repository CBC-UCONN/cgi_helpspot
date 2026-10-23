# DNA Sequencing Project Submission

A single page app (Nim + [Karax](https://github.com/karaxnim/karax), styled with Tailwind) where users enter DNA sequencing project metadata and a sample spreadsheet, then submit a [HelpSpot](https://www.helpspot.com) ticket with two attachments:

- `<project>_project.yaml` – project metadata
- `<project>_samples.csv` – sample data

The build produces plain static files in `public/`. A small [mummy](https://github.com/guzba/mummy) server is included for local testing only.

## Requirements

- Nim >= 2.0 and nimble
- Packages: `nimble install karax mummy` (or just run a nimble task, which prompts for dependencies)

## Usage

```sh
nimble web     # compile src/app.nim -> public/app.js and copy index.html into public/
nimble webdemo # same, plus a "Fill test data" button (see Test submissions)
nimble serve   # build, then serve public/ at http://127.0.0.1:8765 (set PORT to change)
nimble test    # unit tests for csv, validation, sheet and yaml modules
```

Deploy by copying `public/` to any static host.

## Configuration

`config.ini` in the package root is read at build time (`staticRead`) and compiled into `public/app.js`; it is not served or fetched by the page. Run `nimble web` after editing it.

```ini
[helpspot]
url = https://cbcsupport.helpspot.com/api/index.php?method=request.create
category_id = 0
```

- `url` – the HelpSpot `request.create` endpoint.
- `category_id` – HelpSpot category (`xCategory`); `0` omits it.

## Test submissions

Run `nimble servedemo` (or `nimble webdemo` to just build). The page gets a "Fill test data" button that fills the form and three valid sample rows, and the ticket note starts with `[TEST SUBMISSION - please discard]`. A test submission still creates a real HelpSpot ticket, so tell support or delete it afterwards. Use `nimble web` for production; its page has no test button.

## HelpSpot submission and CORS

HelpSpot does not allow CORS, so the browser sends the multipart POST with `mode: "no-cors"` and cannot read the response. The app can only detect that the request did not fail at the network level; it cannot confirm a ticket was created. Check HelpSpot after the first submission.

The ticket contains the contact name and email from the form (HelpSpot requires at least one of these), a short summary note, and the two attachments sent as `File1_*` / `File2_*` fields.

## Uploading a spreadsheet

Choose a `.csv`, `.xlsx` or `.xls` file (first sheet only). The first row must be headers; they are matched to column titles case- and punctuation-insensitively (aliases such as `conc` or `species` are also recognised). Unknown columns are ignored. An upload replaces the current rows.

## Validation

Validation is declarative and per column. Edit `src/lib/schema.nim` and list validators for each column or project field:

```nim
Column(key: "volume_ul", title: "Volume (uL)",
  validators: @[required(), numberRange(0, 100_000)])
```

Available validators (`src/lib/validation.nim`): `required`, `minLength`, `maxLength`, `allowedChars`, `oneOf`, `numberRange`, `email`, `uniqueInColumn`. A validator is just a `proc (value: string; ctx: ValidationContext): string` returning an error message or `""`, so custom ones are easy to add. Invalid cells are highlighted (hover for the message) and submission is blocked until everything is valid.

## Layout

```
src/app.nim          Karax UI and submit logic (JS backend)
src/jsbridge.nim     browser glue in Nim (file reading, attachments, POST)
src/server.nim       mummy dev server (native backend)
src/lib/             platform independent modules (csv, ini, validation, schema, sheet, yamlout)
index.html           page shell, copied to public/
config.ini           runtime configuration
tests/test_lib.nim   unit tests
public/              generated output (git ignored)
```

## Notes

- Tailwind and SheetJS (for `.xlsx` parsing) are loaded from CDNs in `index.html`; the browser needs internet access to use them.
