require "test_helper"

class ImportedSourceRecordTest < ActiveSupport::TestCase
  test "stores a stable original payload hash and source linkage" do
    source_file = build_source_file("source_id\nA-1\n")
    run = source_file.import_runs.create!(status: :completed, importer_version: "1")
    payload = { "source_columns" => [ "source_id" ], "values" => [ "A-1" ] }

    record = source_file.imported_source_records.create!(
      import_run: run,
      source_row_number: 1,
      original_row_payload: payload,
      status: :accepted
    )

    assert_equal payload, record.reload.original_row_payload
    assert_equal ImportedSourceRecord.payload_hash_for(payload), record.payload_hash
    assert_equal source_file, record.source_file
  end

  test "rejects an import run belonging to another source file" do
    source_file = build_source_file("source_id\nA-1\n")
    other_source_file = build_source_file("source_id\nB-1\n")
    run = other_source_file.import_runs.create!(status: :completed, importer_version: "1")

    record = source_file.imported_source_records.build(
      import_run: run,
      source_row_number: 1,
      original_row_payload: { "source_columns" => [ "source_id" ], "values" => [ "A-1" ] },
      status: :accepted
    )

    assert_not record.valid?
    assert_includes record.errors[:import_run], "must belong to the same source file"
  end

  private

  def build_source_file(contents)
    dataset = Dataset.create!(name: "Imported source record dataset")
    source_file = dataset.source_files.build(
      original_filename: "record.csv",
      sha256: Digest::SHA256.hexdigest(contents),
      byte_size: contents.bytesize
    )
    source_file.file.attach(io: StringIO.new(contents), filename: "record.csv", content_type: "text/csv")
    source_file.save!
    source_file
  end
end
