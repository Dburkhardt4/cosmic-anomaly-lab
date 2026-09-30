require "test_helper"

class DatasetComparisonFlowTest < ActionDispatch::IntegrationTest
  test "compares differently structured imports through shared normalized concept identity" do
    shared = build_concept("shared_position", "Shared Position", canonical_unit: "degree")
    dataset_a_only = build_concept("dataset_a_temperature", "Dataset A Temperature")
    dataset_b_only = build_concept("dataset_b_classification", "Dataset B Classification")
    dataset_a = build_imported_dataset(
      "Dataset A",
      "ra_deg,temperature\n10,22\n11,23\n12,24\n13,25\n",
      "dataset-a.csv",
      "ra_deg" => shared,
      "temperature" => dataset_a_only
    )
    dataset_b = build_imported_dataset(
      "Dataset B",
      "RA,classification\n10,blue\n11,green\n12,red\n13,yellow\n",
      "dataset-b.csv",
      "RA" => shared,
      "classification" => dataset_b_only
    )

    imported_source_record_count = ImportedSourceRecord.count
    normalized_record_count = NormalizedRecord.count

    get compare_datasets_path(dataset_a_id: dataset_a.id, dataset_b_id: dataset_b.id)

    assert_response :success
    assert_select "h1", "Compare datasets"
    assert_select ".comparison-readiness", text: /Shared normalized concepts found/
    assert_select ".comparison-dataset-card", count: 2
    assert_select ".comparison-dataset-card", text: /Dataset A/
    assert_select ".comparison-dataset-card", text: /Dataset B/
    assert_select ".comparison-dataset-card", text: /4/
    assert_select ".comparison-concepts-table", text: /Shared Position/
    assert_select ".comparison-concepts-table", text: /shared_position/
    assert_select ".comparison-concepts-table", text: /ra_deg/
    assert_select ".comparison-concepts-table", text: /RA/
    assert_select ".comparison-concepts-table", text: %r{4 / 4}
    assert_select ".comparison-concepts-table", text: /10.*11.*12/
    assert_select ".comparison-concepts-table", text: /13/, count: 0
    assert_select ".dataset-specific-section", text: /Dataset A Temperature/
    assert_select ".dataset-specific-section", text: /Dataset B Classification/
    assert_select ".dataset-specific-section", text: /temperature/
    assert_select ".dataset-specific-section", text: /classification/
    assert_equal imported_source_record_count, ImportedSourceRecord.count
    assert_equal normalized_record_count, NormalizedRecord.count

    get dataset_imported_records_path(dataset_a)

    assert_response :success
    assert_select ".imported-records-table", text: /dataset-a.csv/
    assert_select ".imported-records-table", text: /dataset-b.csv/, count: 0
  end

  test "shows a clear empty state when datasets have no shared concepts" do
    dataset_a_only = build_concept("only_a_concept", "Only A Concept")
    dataset_b_only = build_concept("only_b_concept", "Only B Concept")
    dataset_a = build_imported_dataset("Only A Dataset", "a_field\none\n", "only-a.csv", "a_field" => dataset_a_only)
    dataset_b = build_imported_dataset("Only B Dataset", "b_field\ntwo\n", "only-b.csv", "b_field" => dataset_b_only)

    get compare_datasets_path(dataset_a_id: dataset_a.id, dataset_b_id: dataset_b.id)

    assert_response :success
    assert_select ".comparison-readiness", text: /No shared normalized concepts/
    assert_select ".shared-concepts-empty", text: /no shared normalized concepts/i
    assert_select ".dataset-specific-section", text: /Only A Concept/
    assert_select ".dataset-specific-section", text: /Only B Concept/
  end

  test "requires two different available datasets for comparison" do
    dataset = Dataset.create!(name: "Single dataset")

    get compare_datasets_path(dataset_a_id: dataset.id, dataset_b_id: dataset.id)

    assert_response :success
    assert_select "[role='alert']", text: /two different datasets/i
    assert_select ".comparison-start-state", text: /select two datasets/i
  end

  test "reports when shared mappings have no imported records" do
    shared = build_concept("shared_without_records", "Shared Without Records")
    dataset_a = build_mapped_dataset_without_import("Mapped A", "value_a", shared)
    dataset_b = build_mapped_dataset_without_import("Mapped B", "value_b", shared)

    get compare_datasets_path(dataset_a_id: dataset_a.id, dataset_b_id: dataset_b.id)

    assert_response :success
    assert_select ".comparison-readiness", text: /Imported records are required/
    assert_select ".comparison-readiness-no_records"
  end

  test "counts persisted values by concept key across a concept rename" do
    shared = build_concept("renamed_shared_position", "Original Position")
    dataset_a = Dataset.create!(name: "Renamed Concept A")
    import_dataset_source_file(dataset_a, "position\n1\n", "before-rename.csv", "position" => shared)
    shared.update!(name: "Renamed Position")
    import_dataset_source_file(dataset_a, "position\n2\n", "after-rename.csv", "position" => shared)
    dataset_b = build_imported_dataset("Renamed Concept B", "position\n3\n", "renamed-b.csv", "position" => shared)

    get compare_datasets_path(dataset_a_id: dataset_a.id, dataset_b_id: dataset_b.id)

    assert_response :success
    assert_select ".comparison-concepts-table", text: %r{2 / 1}
    assert_select ".comparison-readiness", text: /Shared normalized concepts found/
  end

  private

  def build_concept(key, name, canonical_unit: nil)
    NormalizedConcept.create!(
      key: key,
      name: name,
      description: "A comparison test concept.",
      expected_value_type: "number",
      canonical_unit: canonical_unit
    )
  end

  def build_imported_dataset(name, contents, filename, mappings)
    dataset = Dataset.create!(name: name)
    import_dataset_source_file(dataset, contents, filename, mappings)
    dataset
  end

  def build_mapped_dataset_without_import(name, source_column_name, normalized_concept)
    dataset = Dataset.create!(name: name)
    source_file = build_source_file(dataset, "#{source_column_name}\nvalue\n", "#{name.parameterize}.csv")
    source_file.field_mappings.create!(
      source_column_name: source_column_name,
      normalized_concept: normalized_concept,
      status: :mapped
    )
    dataset
  end

  def import_dataset_source_file(dataset, contents, filename, mappings)
    source_file = build_source_file(dataset, contents, filename)
    mappings.each do |source_column_name, normalized_concept|
      source_file.field_mappings.create!(
        source_column_name: source_column_name,
        normalized_concept: normalized_concept,
        status: :mapped
      )
    end

    run = SourceFileImporter.call(source_file: source_file)
    assert run.completed?
    assert_equal contents.lines.drop(1).length, run.rows_imported
    source_file
  end

  def build_source_file(dataset, contents, filename)
    source_file = dataset.source_files.build(
      original_filename: filename,
      sha256: Digest::SHA256.hexdigest(contents),
      byte_size: contents.bytesize
    )
    source_file.file.attach(io: StringIO.new(contents), filename: filename, content_type: "text/csv")
    source_file.save!
    source_file
  end
end
