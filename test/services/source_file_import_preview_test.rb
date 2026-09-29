require "test_helper"

class SourceFileImportPreviewTest < ActiveSupport::TestCase
  setup do
    @contents = File.binread(Rails.root.join("test/fixtures/files/source_catalog.csv"))
    @source_file = build_source_file(@contents)
    @right_ascension = build_concept("right_ascension_preview_test", "Right Ascension")
    @declination = build_concept("declination_preview_test", "Declination")
    @observation_time = build_concept("observation_time_preview_test", "Observation Time")
  end

  test "previews mapped and unmapped values without writing scientific records" do
    create_mapping("source_id", @right_ascension)
    create_mapping("flux note", nil, status: :unmapped)
    create_mapping("quality", @declination)

    assert_no_difference([ "Dataset.count", "SourceFile.count", "FieldMapping.count", "NormalizedConcept.count" ]) do
      @preview = SourceFileImportPreview.call(source_file: @source_file)
    end

    assert_equal 3, @preview[:summary][:total_source_row_count]
    assert_equal 3, @preview[:summary][:rows_previewed]
    assert_equal 2, @preview[:summary][:mapped_column_count]
    assert_equal 1, @preview[:summary][:unmapped_column_count]
    assert_equal [ "Declination", "Right Ascension" ], @preview[:summary][:normalized_concepts].map { |concept| concept[:name] }.sort

    first_row = @preview[:rows].first
    assert_equal "A-1", first_row[:mapped_values].find { |value| value[:source_column_name] == "source_id" }[:value]
    assert_equal "good", first_row[:mapped_values].find { |value| value[:source_column_name] == "quality" }[:value]
    assert_equal "12,3", first_row[:unmapped_values].find { |value| value[:source_column_name] == "flux note" }[:value]
    assert first_row[:importable]
    assert @preview[:issues].any? { |issue| issue.code == "unmapped_source_column" && issue.info? }
    assert_equal @contents, @source_file.reload.file.download
  end

  test "limits the interpreted preview rows while retaining the total row count" do
    contents = "source_id\n" + (1..25).map { |number| "A-#{number}" }.join("\n") + "\n"
    source_file = build_source_file(contents, filename: "large_source.csv")
    create_mapping("source_id", @right_ascension, source_file: source_file)

    preview = SourceFileImportPreview.call(source_file: source_file, row_limit: 2)

    assert_equal 25, preview[:summary][:total_source_row_count]
    assert_equal 2, preview[:summary][:rows_previewed]
    assert_equal [ 1, 2 ], preview[:rows].map { |row| row[:source_row_number] }
  end

  test "warns for blank mapped values without inventing required-field rules" do
    create_mapping("source_id", @right_ascension)
    create_mapping("flux note", @observation_time)

    preview = SourceFileImportPreview.call(source_file: @source_file)
    row = preview[:rows].find { |candidate| candidate[:source_row_number] == 2 }
    issue = row[:issues].find { |candidate| candidate.code == "blank_mapped_value" }

    assert issue
    assert issue.warning?
    assert row[:importable]
  end

  test "reports stale and missing mapping state as errors" do
    create_mapping("not_in_file", @right_ascension)
    invalid_mapping = create_mapping("source_id", @declination)
    invalid_mapping.update_column(:status, "invalid")

    preview = SourceFileImportPreview.call(source_file: @source_file)

    assert_includes preview[:issues].map(&:code), "mapped_source_column_missing"
    assert_includes preview[:issues].map(&:code), "invalid_mapping_state"
    assert preview[:rows].none? { |row| row[:importable] }
  end

  test "reports malformed CSV without changing the source file" do
    contents = "source_id,note\nA-1,\"unterminated\n"
    source_file = build_source_file(contents, filename: "malformed_preview.csv")

    preview = SourceFileImportPreview.call(source_file: source_file)

    issue = preview[:issues].find { |candidate| candidate.code == "malformed_csv" }
    assert issue
    assert issue.error?
    assert_equal 0, preview[:rows].length
    assert_equal contents, source_file.reload.file.download
  end

  test "reports a row with a different number of values" do
    contents = "source_id,note\nA-1,ok,extra\n"
    source_file = build_source_file(contents, filename: "uneven_preview.csv")

    preview = SourceFileImportPreview.call(source_file: source_file)

    issue = preview[:rows].first[:issues].find { |candidate| candidate.code == "malformed_csv_row" }
    assert issue
    assert issue.error?
    assert_equal [ 1 ], preview[:rows].map { |row| row[:source_row_number] }
    assert_not preview[:rows].first[:importable]
  end

  test "does not assign mappings to duplicate CSV headers" do
    contents = File.binread(Rails.root.join("test/fixtures/files/duplicate_headers.csv"))
    source_file = build_source_file(contents, filename: "duplicate_preview.csv")
    create_mapping("source_id", @right_ascension, source_file: source_file)

    preview = SourceFileImportPreview.call(source_file: source_file)

    issue = preview[:issues].find { |candidate| candidate.code == "duplicate_source_column_name" }
    assert issue
    assert issue.error?
    assert_empty preview[:rows].first[:mapped_values]
    assert preview[:rows].none? { |row| row[:importable] }
  end

  test "reports a source-file hash mismatch" do
    @source_file.update_column(:sha256, "b" * 64)

    preview = SourceFileImportPreview.call(source_file: @source_file)

    assert_includes preview[:issues].map(&:code), "source_file_hash_mismatch"
    assert preview[:rows].none? { |row| row[:importable] }
  end

  private

  def build_concept(key, name)
    NormalizedConcept.create!(
      key: key,
      name: name,
      description: "A preview test concept.",
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

  def build_source_file(contents, filename: "preview_source.csv")
    dataset = Dataset.create!(name: "Import preview dataset")
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
