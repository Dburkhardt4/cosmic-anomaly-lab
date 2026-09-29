require "test_helper"

class SourceFileImporterTest < ActiveSupport::TestCase
  setup do
    @contents = File.binread(Rails.root.join("test/fixtures/files/source_catalog.csv"))
    @source_file = build_source_file(@contents)
    @right_ascension = build_concept("right_ascension_import_test", "Right Ascension")
    @declination = build_concept("declination_import_test", "Declination")
    @observation_time = build_concept("observation_time_import_test", "Observation Time")
  end

  test "imports generic records with complete source provenance" do
    create_mapping("source_id", @right_ascension)
    create_mapping("flux note", nil, status: :unmapped)
    create_mapping("quality", @declination)

    run = SourceFileImporter.call(source_file: @source_file)

    assert run.completed?
    assert_equal 3, run.rows_read
    assert_equal 3, run.rows_imported
    assert_equal 0, run.rows_rejected
    assert_equal 0, run.warning_count
    assert_equal 0, run.error_count
    assert_equal @source_file.sha256, run.source_sha256
    assert_equal @source_file.byte_size, run.source_byte_size
    assert_equal 3, @source_file.imported_source_records.count
    assert_equal 3, @source_file.normalized_records.count

    source_record = @source_file.imported_source_records.find_by!(source_row_number: 1)
    assert source_record.accepted?
    assert_equal(
      { "source_columns" => [ "source_id", "flux note", "quality" ], "values" => [ "A-1", "12,3", "good" ] },
      source_record.original_row_payload
    )
    assert_equal ImportedSourceRecord.payload_hash_for(source_record.original_row_payload), source_record.payload_hash
    assert_equal @source_file, source_record.source_file
    assert_equal @source_file.dataset, source_record.source_file.dataset

    normalized_record = source_record.normalized_record
    assert_equal "generic", normalized_record.record_type
    assert_equal "right_ascension_import_test", normalized_record.normalized_values.first["concept_key"]
    assert_equal "A-1", normalized_record.normalized_values.first["value"]
    assert_equal "12,3", normalized_record.unmapped_values.find { |value| value["source_column_name"] == "flux note" }["value"]
    assert_equal "mapped", normalized_record.field_mapping_snapshot.find { |mapping| mapping["source_column_name"] == "source_id" }["status"]
    assert_equal "unmapped", normalized_record.field_mapping_snapshot.find { |mapping| mapping["source_column_name"] == "flux note" }["status"]
    assert_equal @contents, @source_file.reload.file.download
  end

  test "records blank mapped values as warnings while importing the row" do
    create_mapping("source_id", @right_ascension)
    create_mapping("flux note", @observation_time)

    run = SourceFileImporter.call(source_file: @source_file)
    source_record = @source_file.imported_source_records.find_by!(source_row_number: 2)

    assert run.completed?
    assert_equal 3, run.rows_imported
    assert_equal 1, run.warning_count
    assert_empty source_record.validation_issues.select { |issue| issue["severity"] == "error" }
    assert_equal "blank_mapped_value", source_record.validation_issues.first["code"]
    assert source_record.accepted?
  end

  test "preserves rejected rows and rolls no normalized record for malformed row width" do
    contents = "source_id,note\nA-1,ok,extra\n"
    source_file = build_source_file(contents, filename: "rejected_import.csv")
    create_mapping("source_id", @right_ascension, source_file: source_file)

    run = SourceFileImporter.call(source_file: source_file)
    source_record = source_file.imported_source_records.first

    assert run.completed?
    assert_equal 1, run.rows_read
    assert_equal 0, run.rows_imported
    assert_equal 1, run.rows_rejected
    assert_equal 1, run.error_count
    assert source_record.rejected?
    assert_nil source_record.normalized_record
    assert_equal [ "A-1", "ok", "extra" ], source_record.original_row_payload["values"]
    assert_equal "malformed_csv_row", source_record.validation_issues.first["code"]
    assert_equal contents, source_file.reload.file.download
  end

  test "fails before writing records when the source checksum changed" do
    @source_file.update_column(:sha256, "b" * 64)

    run = SourceFileImporter.call(source_file: @source_file)

    assert run.failed?
    assert_equal 0, run.rows_read
    assert_equal 0, run.rows_imported
    assert_equal 1, run.error_count
    assert_includes run.failure_message, "integrity"
    assert_equal "source_file_hash_mismatch", run.validation_issues.first["code"]
    assert_empty @source_file.imported_source_records
    assert_empty @source_file.normalized_records
  end

  test "fails before writing records when mappings are invalid" do
    mapping = create_mapping("source_id", @right_ascension)
    mapping.update_column(:status, "invalid")

    run = SourceFileImporter.call(source_file: @source_file)

    assert run.failed?
    assert_equal 0, run.rows_read
    assert_equal 0, run.rows_imported
    assert_equal 1, run.error_count
    assert_includes run.failure_message, "mappings"
    assert_equal "invalid_mapping_state", run.validation_issues.first["code"]
    assert_empty @source_file.imported_source_records
  end

  test "rolls back all scientific records after a fatal persistence failure" do
    create_mapping("source_id", @right_ascension)

    original_create = NormalizedRecord.method(:create!)
    NormalizedRecord.define_singleton_method(:create!) do |*args, **kwargs|
      raise ActiveRecord::RecordInvalid.new(NormalizedRecord.new)
    end

    begin
      run = SourceFileImporter.call(source_file: @source_file)

      assert run.failed?
      assert_equal 1, run.error_count
    ensure
      NormalizedRecord.define_singleton_method(:create!) do |*args, **kwargs|
        original_create.call(*args, **kwargs)
      end
    end

    assert_empty @source_file.imported_source_records
    assert_empty @source_file.normalized_records
  end

  test "does not duplicate records when the completed import is requested again" do
    create_mapping("source_id", @right_ascension)

    first_run = SourceFileImporter.call(source_file: @source_file)
    first_record_ids = @source_file.imported_source_records.pluck(:id)
    first_normalized_ids = @source_file.normalized_records.pluck(:id)

    second_run = SourceFileImporter.call(source_file: @source_file)

    assert_equal first_run.id, second_run.id
    assert_equal first_run.completed_at, second_run.completed_at
    assert_equal first_record_ids, @source_file.imported_source_records.pluck(:id)
    assert_equal first_normalized_ids, @source_file.normalized_records.pluck(:id)
    assert_equal 3, @source_file.imported_source_records.count
  end

  test "recovers a stale importing run when no source records were written" do
    create_mapping("source_id", @right_ascension)
    stale_run = @source_file.import_runs.create!(
      status: :importing,
      started_at: 2.hours.ago,
      importer_version: "1"
    )

    run = SourceFileImporter.call(source_file: @source_file)

    assert_equal stale_run.id, run.id
    assert run.completed?
    assert_equal 3, run.rows_imported
    assert_equal 3, @source_file.imported_source_records.count
  end

  test "retains the import checksum if source metadata changes later" do
    create_mapping("source_id", @right_ascension)
    run = SourceFileImporter.call(source_file: @source_file)
    original_checksum = run.source_sha256

    @source_file.update_column(:sha256, "c" * 64)

    assert_equal original_checksum, run.reload.source_sha256
    assert_equal original_checksum, run.imported_source_records.first.import_run.source_sha256
  end

  private

  def build_concept(key, name)
    NormalizedConcept.create!(
      key: key,
      name: name,
      description: "An importer test concept.",
      expected_value_type: "string"
    )
  end

  def create_mapping(source_column_name, concept, status: :mapped, source_file: @source_file)
    source_file.field_mappings.create!(
      source_column_name: source_column_name,
      normalized_concept: concept,
      status: status
    )
  end

  def build_source_file(contents, filename: "import_source.csv")
    dataset = Dataset.create!(name: "Importer dataset")
    source_file = dataset.source_files.build(
      original_filename: filename,
      sha256: SourceFileChecksum.for_io(StringIO.new(contents))[:sha256],
      byte_size: contents.bytesize
    )
    source_file.file.attach(io: StringIO.new(contents), filename: filename, content_type: "text/csv")
    source_file.save!
    source_file
  end
end
