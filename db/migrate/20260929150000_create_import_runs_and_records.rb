class CreateImportRunsAndRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :import_runs do |t|
      t.references :source_file, null: false, foreign_key: true, index: false
      t.string :status, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :rows_read, null: false, default: 0
      t.integer :rows_imported, null: false, default: 0
      t.integer :rows_rejected, null: false, default: 0
      t.integer :warning_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.string :importer_version, null: false, default: "1"
      t.text :failure_message

      t.timestamps
    end

    add_index :import_runs, :source_file_id, unique: true

    create_table :imported_source_records do |t|
      t.references :source_file, null: false, foreign_key: true, index: false
      t.references :import_run, null: false, foreign_key: true, index: false
      t.integer :source_row_number, null: false
      t.json :original_row_payload, null: false
      t.string :payload_hash, null: false
      t.string :status, null: false, default: "accepted"
      t.json :validation_issues, null: false, default: []

      t.timestamps
    end

    add_index :imported_source_records, [ :source_file_id, :source_row_number ],
      unique: true, name: :index_imported_source_records_on_source_file_and_row
    add_index :imported_source_records, :import_run_id

    create_table :normalized_records do |t|
      t.references :imported_source_record, null: false, foreign_key: true, index: false
      t.string :record_type, null: false, default: "generic"
      t.json :normalized_values, null: false
      t.json :unmapped_values, null: false
      t.json :field_mapping_snapshot, null: false

      t.timestamps
    end

    add_index :normalized_records, :imported_source_record_id, unique: true
  end
end
