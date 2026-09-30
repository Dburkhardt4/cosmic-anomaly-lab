require "test_helper"

class ImportedRecordsFlowTest < ActionDispatch::IntegrationTest
  test "dataset pages link to a paginated imported-record explorer" do
    dataset = Dataset.create!(name: "Browsable dataset")
    concept = build_concept("measurement_browsable", "Archive measurement", canonical_unit: "unit")
    source_file, run = build_source_file(dataset, "measurement,note\n1.2,alpha\n", "first.csv")
    map_source_file(source_file, concept)
    record = build_record(source_file, run, row_number: 1, value: "1.2", record_type: "sample")

    get dataset_path(dataset)

    assert_response :success
    assert_select ".record-exploration-panel", text: /1 imported record/
    assert_select "a[href='#{dataset_imported_records_path(dataset)}']", "Browse imported records"

    get dataset_imported_records_path(dataset)

    assert_response :success
    assert_select "h1", "Imported records"
    assert_select ".imported-records-table", text: /Archive measurement/
    assert_select ".imported-records-table tbody tr", count: 1
    assert_select "a[href='#{dataset_imported_record_path(dataset, record)}']", "Open"
    assert_select "a[href='#{dataset_source_file_import_run_path(dataset, source_file, run)}']", text: /Run ##{run.id}/
  end

  test "filters by source file, record type, and simple normalized-value text" do
    dataset = Dataset.create!(name: "Filterable dataset")
    concept = build_concept("label_filterable", "Archive label")
    first_source_file, first_run = build_source_file(dataset, "label\nalpha\n", "first.csv")
    second_source_file, second_run = build_source_file(dataset, "label\nbeta\n", "second.csv")
    map_source_file(first_source_file, concept, source_column_name: "label")
    map_source_file(second_source_file, concept, source_column_name: "label")
    first_record = build_record(first_source_file, first_run, row_number: 1, value: "alpha", record_type: "sample")
    second_record = build_record(second_source_file, second_run, row_number: 1, value: "beta", record_type: "candidate")

    get dataset_imported_records_path(dataset, source_file_id: first_source_file.id)

    assert_response :success
    assert_select ".record-filter-panel select[name='source_file_id'] option[selected='selected']", text: "first.csv"
    assert_select ".imported-records-table tbody tr", count: 1
    assert_select ".imported-records-table", text: /alpha/
    assert_empty css_select(".imported-records-table tbody tr").select { |row| row.text.include?("beta") }

    get dataset_imported_records_path(dataset, record_type: "candidate")

    assert_response :success
    assert_select ".imported-records-table tbody tr", count: 1
    assert_select ".imported-records-table", text: /beta/
    assert_empty css_select(".imported-records-table tbody tr").select { |row| row.text.include?("alpha") }

    get dataset_imported_records_path(dataset, query: "ALPHA")

    assert_response :success
    assert_select ".imported-records-table tbody tr", count: 1
    assert_select "a[href='#{dataset_imported_record_path(dataset, first_record)}']", "Open"
    assert_select "a[href='#{dataset_imported_record_path(dataset, second_record)}']", text: "Open", count: 0
  end

  test "paginates without rendering all records" do
    dataset = Dataset.create!(name: "Large browsable dataset")
    concept = build_concept("sequence_paginates", "Sequence")
    contents = "sequence\n" + (1..26).map { |number| "#{number}" }.join("\n") + "\n"
    source_file, run = build_source_file(dataset, contents, "many.csv")
    map_source_file(source_file, concept, source_column_name: "sequence")
    records = (1..26).map do |number|
      build_record(source_file, run, row_number: number, value: number.to_s)
    end

    get dataset_imported_records_path(dataset)

    assert_response :success
    assert_select ".imported-records-table tbody tr", count: ImportedRecordsController::PER_PAGE
    assert_select ".pagination", text: /Page 1 of 2/i
    next_link = css_select(".pagination a").find { |link| link.text.strip == "Next" }
    assert next_link
    assert_includes next_link["href"], "page=2"
    assert_select "a[href='#{dataset_imported_record_path(dataset, records.last)}']", text: "Open", count: 0

    get dataset_imported_records_path(dataset, page: 2)

    assert_response :success
    assert_select ".imported-records-table tbody tr", count: 1
    assert_select ".imported-records-table", text: /26/
    assert_select ".pagination", text: /Page 2 of 2/i
    previous_link = css_select(".pagination a").find { |link| link.text.strip == "Previous" }
    assert previous_link
    assert_includes previous_link["href"], "page=1"
  end

  test "shows normalized values, original payload, unmapped values, and provenance" do
    dataset = Dataset.create!(name: "Inspectable source-agnostic dataset")
    concept = build_concept("custom_quantity_detail", "Archive quantity", description: "A source-defined quantity.", canonical_unit: "catalog-unit")
    contents = "quantity,source_note\n42,kept exactly\n"
    source_file, run = build_source_file(dataset, contents, "source-agnostic.csv")
    map_source_file(source_file, concept, source_column_name: "quantity")
    source_file.field_mappings.create!(source_column_name: "source_note", status: :unmapped)
    record = build_record(source_file, run, row_number: 1, value: "42", record_type: "archive_item", unmapped_value: "kept exactly")

    get dataset_imported_record_path(dataset, record)

    assert_response :success
    assert_select "h1", "Imported record ##{record.id}"
    assert_select ".normalized-record-section", text: /Archive quantity/
    assert_select ".normalized-record-section", text: /custom_quantity_detail/
    assert_select ".normalized-record-section", text: /catalog-unit/
    assert_select ".normalized-record-section", text: /A source-defined quantity/
    assert_select ".original-record-section", text: /source_note/
    assert_select ".original-record-section", text: /kept exactly/
    assert_select ".original-record-section", text: /Unmapped \/ source-specific/
    assert_select ".provenance-section", text: /Inspectable source-agnostic dataset/
    assert_select ".provenance-section", text: /source-agnostic.csv/
    assert_select ".provenance-section", text: /#{source_file.sha256}/
    assert_select ".provenance-section", text: /Source row 1/
    assert_select ".provenance-section", text: /Run ##{run.id}/
    assert_select ".mapping-snapshot", text: /source_note/
  end

  test "renders a useful empty state for a dataset without imported records" do
    dataset = Dataset.create!(name: "Empty exploration dataset")

    get dataset_imported_records_path(dataset)

    assert_response :success
    assert_select ".empty-state", text: /no imported records/i
    assert_select ".record-filter-panel", text: /Filter records/
  end

  private

  def build_concept(key, name, description: "A generic test concept.", canonical_unit: nil)
    NormalizedConcept.create!(
      key: key,
      name: name,
      description: description,
      expected_value_type: "string",
      canonical_unit: canonical_unit
    )
  end

  def build_source_file(dataset, contents, filename)
    source_file = dataset.source_files.build(
      original_filename: filename,
      sha256: Digest::SHA256.hexdigest(contents),
      byte_size: contents.bytesize
    )
    source_file.file.attach(io: StringIO.new(contents), filename: filename, content_type: "text/csv")
    source_file.save!
    run = source_file.import_runs.create!(
      status: :completed,
      importer_version: "1",
      started_at: 1.minute.ago,
      completed_at: Time.current,
      rows_read: contents.lines.drop(1).length,
      rows_imported: contents.lines.drop(1).length,
      source_sha256: source_file.sha256,
      source_byte_size: source_file.byte_size
    )
    [ source_file, run ]
  end

  def map_source_file(source_file, concept, source_column_name: "measurement")
    source_file.field_mappings.create!(
      source_column_name: source_column_name,
      normalized_concept: concept,
      status: :mapped
    )
  end

  def build_record(source_file, run, row_number:, value:, record_type: "generic", unmapped_value: nil)
    columns = unmapped_value ? [ "quantity", "source_note" ] : [ "measurement" ]
    values = unmapped_value ? [ value, unmapped_value ] : [ value ]
    source_record = source_file.imported_source_records.create!(
      import_run: run,
      source_row_number: row_number,
      original_row_payload: { "source_columns" => columns, "values" => values },
      status: :accepted
    )
    source_record.create_normalized_record!(
      record_type: record_type,
      normalized_values: [
        {
          "concept_key" => source_file.field_mappings.mapped.first.normalized_concept.key,
          "concept_name" => source_file.field_mappings.mapped.first.normalized_concept.name,
          "source_column_name" => columns.first,
          "value" => value
        }
      ],
      unmapped_values: unmapped_value ? [ { "source_column_name" => "source_note", "value" => unmapped_value } ] : [],
      field_mapping_snapshot: source_file.field_mappings.order(:id).map do |mapping|
        {
          "source_column_name" => mapping.source_column_name,
          "status" => mapping.status,
          "normalized_concept_key" => mapping.normalized_concept&.key,
          "normalized_concept_name" => mapping.normalized_concept&.name
        }
      end
    )
  end
end
