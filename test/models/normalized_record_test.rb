require "test_helper"

class NormalizedRecordTest < ActiveSupport::TestCase
  test "requires an accepted source record and preserves generic JSON values" do
    source_file = build_source_file
    run = source_file.import_runs.create!(status: :completed, importer_version: "1")
    source_record = source_file.imported_source_records.create!(
      import_run: run,
      source_row_number: 1,
      original_row_payload: { "source_columns" => [ "value" ], "values" => [ "12.3" ] },
      status: :accepted
    )

    record = source_record.create_normalized_record!(
      record_type: "generic",
      normalized_values: [ { "concept_key" => "measurement", "value" => "12.3" } ],
      unmapped_values: [ { "source_column_name" => "note", "value" => "kept" } ],
      field_mapping_snapshot: [ { "source_column_name" => "value", "status" => "mapped" } ]
    )

    assert_equal source_file, record.source_file
    assert_equal "12.3", record.reload.normalized_values.first["value"]
    assert_equal "kept", record.unmapped_values.first["value"]
  end

  test "rejects normalized records for rejected source rows" do
    source_file = build_source_file
    run = source_file.import_runs.create!(status: :completed, importer_version: "1")
    source_record = source_file.imported_source_records.create!(
      import_run: run,
      source_row_number: 1,
      original_row_payload: { "source_columns" => [ "value" ], "values" => [ "bad" ] },
      status: :rejected,
      validation_issues: [ { "code" => "invalid_value" } ]
    )

    record = source_record.build_normalized_record(record_type: "generic")

    assert_not record.valid?
    assert_includes record.errors[:imported_source_record], "must be accepted before a normalized record is created"
  end

  private

  def build_source_file
    contents = "value\n12.3\n"
    dataset = Dataset.create!(name: "Normalized record dataset")
    source_file = dataset.source_files.build(
      original_filename: "normalized.csv",
      sha256: Digest::SHA256.hexdigest(contents),
      byte_size: contents.bytesize
    )
    source_file.file.attach(io: StringIO.new(contents), filename: "normalized.csv", content_type: "text/csv")
    source_file.save!
    source_file
  end
end
