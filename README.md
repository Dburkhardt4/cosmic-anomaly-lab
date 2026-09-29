# Cosmic Anomaly Lab

Cosmic Anomaly Lab is a local-first Rails research workbench for cataloging processed scientific datasets and preserving their source context. The current workflow supports CSV source attachment, structural inspection, explicit field mapping from source-specific columns to a small set of reusable concepts, a read-only import preview, and persistent import into generic source-linked records. Imported records preserve the complete original row payload, source-row linkage, and mapping snapshot; no unit conversion or automatic scientific interpretation is performed.

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
