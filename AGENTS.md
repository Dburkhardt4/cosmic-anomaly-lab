# Cosmic Anomaly Lab agent guide

This file applies to the entire repository. Check for a more specific `AGENTS.md` before editing a nested directory if one is added later.

## Project shape

Cosmic Anomaly Lab is a local-first Rails research workbench. It is currently a Rails 8.1 application using Ruby 4.0.7, SQLite, server-rendered ERB views, Turbo, importmap, Propshaft, and Active Storage.

The main source-data flow is:

```text
Dataset
  -> SourceFile
       -> inspection
       -> explicit FieldMapping -> NormalizedConcept
       -> ImportRun
            -> ImportedSourceRecord -> NormalizedRecord
```

Important areas:

- `app/models/` contains the Active Record data model and invariants.
- `app/services/` contains CSV inspection, validation, mapping-context, checksum, preview, and import workflows.
- `app/controllers/` coordinates requests and renders or redirects; keep business logic out of controllers.
- `app/views/` contains the server-rendered workbench UI.
- `db/migrate/` and `db/seeds.rb` define persistence and the small reusable concept vocabulary.
- `test/models/`, `test/services/`, and `test/integration/` contain the Minitest suite.
- `docs/COSMIC_ANOMALY_LAB_PROJECT_OVERVIEW.md` is the detailed product and architecture context.

## Product and data boundaries

The distinction below is fundamental and must remain visible in both code and UI:

```text
source column -> explicit field mapping -> normalized concept
```

- Never infer scientific meaning from a source column name, sample value, or file metadata.
- Never add AI suggestions, confidence scores, automatic mapping, or implicit ontology behavior.
- Preserve the uploaded source file, exact source column names, original row payloads, source row numbers, checksums, and mapping decisions.
- A source column may remain explicitly unmapped. Unmapped values must not be discarded.
- Field mappings are user decisions and do not rename columns, transform values, convert units, or rewrite the source file.
- Imported records remain generic and source-linked. Do not add astronomy-specific record tables unless the user explicitly changes the product scope.
- Do not begin cross-dataset comparison, anomaly detection, investigations, or other future-scope work as part of a smaller feature.

When changing import behavior, preserve these guarantees:

- re-read the current source and current mappings at import time;
- verify source integrity before writing records;
- use a transaction for a run so fatal failures do not leave partial scientific records;
- make repeated completed imports idempotent;
- retain inspectable rejected rows and run-level failure information;
- keep provenance sufficient to trace every accepted value back to its source row.

## Rails conventions

- Prefer the existing nested resource structure under `datasets/:dataset_id/source_files/:source_file_id`.
- Keep controllers thin: load authorized/nested records, call a service, and choose the response.
- Put parsing and workflow rules in small, callable service objects under `app/services/`.
- Put durable invariants in model validations and database constraints. Application checks alone are not sufficient for uniqueness or duplicate protection.
- Use strong parameters and the existing Rails form helpers.
- Use explicit enums, JSON defaults, and associations consistently with the existing models.
- Add a migration for schema changes and keep `db/schema.rb` synchronized by running the migration.
- Keep seed data intentionally small and generic. Seeds should be safe to re-run.
- Use the existing CSS vocabulary and accessible, semantic HTML. Prefer progressive enhancement over introducing new JavaScript.
- Do not add a new dependency when the Ruby/Rails standard library or an existing project dependency is sufficient.

## Editing and repository safety

Before editing:

1. Read this file, `README.md`, the relevant section of the project overview, and the current implementation/tests.
2. Check `git status` and preserve unrelated user changes.
3. Trace the existing route, controller, service, model, view, and test path before choosing where to add behavior.

While editing:

- Use `apply_patch` for hand-written file changes.
- Do not use destructive commands such as `git reset --hard`, `git checkout --`, or broad recursive deletion.
- Do not overwrite unrelated work or reformat files unnecessarily.
- Do not commit or push unless the user explicitly asks.
- Do not place credentials, tokens, uploaded data, generated databases, or machine-specific files in Git.

## Verification commands

Run the narrowest relevant tests first, then the full checks for changes that affect application behavior or the schema.

```bash
bin/rails db:prepare
bin/rails test
bin/rails test test/models/source_file_test.rb test/services/source_file_importer_test.rb
bin/rubocop
bin/brakeman --quiet --no-pager
bin/bundler-audit
bin/importmap audit
bin/rails zeitwerk:check
bin/rails db:migrate:status
git diff --check
bin/ci
```

For production-oriented checks, use the project environment without changing development data:

```bash
RAILS_ENV=production bin/rails runner 'puts Rails.application.class.name'
RAILS_ENV=production bin/rails assets:precompile
```

If the sandbox prevents Rails from creating its parallel-test DRb socket, run the Rails suite with `PARALLEL_WORKERS=1` and report that environment limitation separately from application failures.

A schema-changing change is not complete while migrations are pending. Confirm migration status, boot, tests, and the relevant integration flow before handing it off.

## Documentation and handoff

Update `README.md` or the project overview when behavior, workflow, setup, or scope changes. Keep documentation precise about what is implemented versus future work.

In a completion report, include:

- the user-visible workflow change;
- the affected files and migrations;
- model/database constraints and provenance behavior;
- tests and validation commands with results;
- important scope or environment caveats;
- a suggested commit message.

