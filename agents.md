# Agent Guide

## Purpose

This repository is a client-side DNA sequencing request SPA written in Nim with Karax. It uses Tailwind CSS and a Lustre-inspired Model → Update → View architecture.

## Source layout

All application source belongs in `/src`.

- `src/model.nim`: domain types, schema definitions, visibility predicates, and application state.
- `src/update.nim`: messages and state transitions.
- `src/main.nim`: Karax rendering and browser event wiring.
- `src/validators.nim`: reusable validation functions.
- `src/validation.nim`: schema-driven and cross-row validation.
- `src/io.nim`: project serialization, CSV parsing/export, and schema-derived column handling.

Do not use `import karax/prelude`. Import the specific Karax modules needed by the code.

## Architecture rules

1. Keep domain state in `model.nim`.
2. User actions become `Msg` values.
3. `update(model, msg)` is responsible for state transitions.
4. The view reads state and emits messages; it should not own business rules.
5. Validation belongs in reusable validator procs, not in view rendering.
6. Browser-specific JavaScript interop should remain isolated in `main.nim`.

## Schema is the source of truth

The project form and sample-table columns are schema-driven.

### Project fields

Define project fields in `projectSchema` in `src/model.nim` using `ProjectFieldDef`:

- `key`: model field key.
- `label`: user-facing label.
- `kind`: `textField`, `emailField`, `selectField`, `checkboxField`, or `textareaField`.
- `options`: select choices when applicable.
- `help`: optional explanatory text.
- `defaultValue`: initial string value.
- `visibleIf`: a `ProjectCondition` predicate.
- `validators`: reusable field validators.

The view renders `visibleProjectFields(project)`. Do not add independent visibility checks to the view when a rule belongs in the schema.

### Sample columns

Define columns in `sampleColumnSchema` using `SampleColumnDef`:

- `key`: stable CSV/model key.
- `label`: displayed table heading.
- `visibleIf`: a `ProjectCondition` predicate.
- `validators`: reusable column validators.

The table and CSV code both derive their columns from `visibleSampleColumns(project)`. Never maintain a second hard-coded list of conditional columns.

Simple reusable predicates include `alwaysVisible`, `assayIs(...)`, `assayIsNot(...)`, `indexIs(...)`, `indexIsNot(...)`, and `customReferenceEnabled`. More complicated conditions can use an inline Nim proc.

## Adding a field

When adding a project field:

1. Add a `ProjectFieldDef` to `projectSchema` with a unique key and any default, visibility predicate, and validators.
2. Add reusable validators in `validators.nim` if needed.
3. Add update behavior only if the generic `setProjectField` path cannot represent the field.

When adding a sample column:

1. Add one `SampleColumnDef` to `sampleColumnSchema` with a unique key and any visibility predicate and validators.
2. Add reusable validators in `validators.nim` if needed.

`ProjectForm` and `SampleRow` are string tables keyed by schema keys; they do not need per-field members or storage mappings.

Do not add conditional rendering directly to `sampleTable()` unless the condition is purely presentational. Data-dependent visibility belongs in the schema.

## CSV behavior

The current visible sample-column schema determines the CSV header. A CSV uploaded under one project configuration is intentionally rejected if its headers do not match the current configuration.

## Build

```bash
nimble buildWeb
```

The build writes the browser application to `/public`.

## Tailwind

The generated `public/index.html` currently loads Tailwind from its CDN. If this is changed to a compiled/pinned Tailwind build, keep generated assets under `/public` and do not put generated files under `/src`.

## Avoid

- `import karax/prelude`.
- Duplicating conditional column logic between the view and CSV code.
- Mutating model state directly from event handlers.
- Putting validation rules into rendering functions.
- Adding server dependencies for functionality that is explicitly client-side.
