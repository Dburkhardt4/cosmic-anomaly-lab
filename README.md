# Cosmic Anomaly Lab

Cosmic Anomaly Lab is a local-first Rails research workbench for cataloging processed scientific datasets and preserving their source context. The current workflow supports read-only CSV source attachment, structural inspection, explicit field mapping from source-specific columns to a small set of reusable concepts, and a read-only import preview. Field mapping records a possible relationship for future normalization, while the preview validates and displays source values without importing or transforming records. Persistent import and normalization are not implemented yet.

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
