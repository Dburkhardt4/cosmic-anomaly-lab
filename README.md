# Cosmic Anomaly Lab

Cosmic Anomaly Lab is a local-first Rails research workbench for cataloging processed scientific datasets and preserving their source context. The current workflow supports CSV source attachment, structural inspection, explicit field mapping from source-specific columns to a small set of reusable concepts, a read-only import preview, persistent import into generic source-linked records, and Dataset-scoped browsing of accepted imported records. Imported records preserve the complete original row payload, source-row linkage, import-run provenance, and mapping snapshot; no unit conversion or automatic scientific interpretation is performed.

Datasets with completed imports expose an **Imported records** explorer. It paginates persisted records, supports simple SourceFile/record-type filters and text matching against stored normalized JSON, and opens each record with separate normalized, original-source, and provenance sections. The explorer does not reread CSV files for each page and does not provide typed range queries or cross-dataset analysis.

## Requirements

- Ruby 4.0.7
- Bundler
- SQLite 3

## Setup

```bash
bundle install
bin/rails db:prepare
```

## Run locally

```bash
bin/rails server
```

Open [http://localhost:3000](http://localhost:3000).

## Tests and checks

```bash
bin/rails test
bin/rubocop
bin/brakeman --quiet --no-pager
```

The application uses Rails 8.1, SQLite, server-rendered Rails views, importmap, Turbo, and the standard Rails test framework.
