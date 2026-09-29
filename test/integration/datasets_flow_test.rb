require "test_helper"

class DatasetsFlowTest < ActionDispatch::IntegrationTest
  test "home page links to the dataset registry" do
    get root_path

    assert_response :success
    assert_select "h1", "Scientific datasets, kept understandable."
    assert_select "nav a[href='#{datasets_path}']", "Datasets"
  end

  test "creates, views, edits, and lists a dataset" do
    get new_dataset_path
    assert_response :success

    assert_difference("Dataset.count", 1) do
      post datasets_path, params: {
        dataset: {
          name: "Gaia Focused Sample",
          source_organization: "ESA",
          source_url: "https://example.test/gaia",
          version: "DR3",
          description: "A processed research sample."
        }
      }
    end

    dataset = Dataset.order(:created_at).last
    assert_redirected_to dataset_path(dataset)

    follow_redirect!
    assert_response :success
    assert_select "h1", "Gaia Focused Sample"
    assert_select "a[href='#{edit_dataset_path(dataset)}']", "Edit metadata"

    patch dataset_path(dataset), params: {
      dataset: { name: "Gaia Focused Sample Revised", version: "DR3.1" }
    }
    assert_redirected_to dataset_path(dataset)
    assert_equal "Gaia Focused Sample Revised", dataset.reload.name

    get datasets_path
    assert_response :success
    assert_select "a[href='#{dataset_path(dataset)}']", "Gaia Focused Sample Revised"
  end

  test "shows validation errors for a missing name" do
    assert_no_difference("Dataset.count") do
      post datasets_path, params: { dataset: { name: "", source_organization: "Unknown" } }
    end

    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /Name can't be blank/
  end

  test "uploads and inspects a CSV source file without importing it" do
    dataset = Dataset.create!(name: "Inspectable Catalog")
    contents = File.binread(Rails.root.join("test/fixtures/files/source_catalog.csv"))

    assert_difference([ "SourceFile.count", "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ], 1) do
      post dataset_source_files_path(dataset), params: {
        source_file: {
          file: fixture_file_upload("source_catalog.csv", "text/csv")
        }
      }
    end

    source_file = SourceFile.order(:created_at).last
    assert_redirected_to dataset_source_file_path(dataset, source_file)
    assert_equal dataset, source_file.dataset
    assert_equal contents, source_file.file.download

    get dataset_source_file_path(dataset, source_file)

    assert_response :success
    assert_select "h1", "source_catalog.csv"
    assert_select ".inspection-banner", text: /not been imported or normalized/i
    assert_select ".hash-value", Digest::SHA256.hexdigest(contents)
    assert_select ".inspection-table", text: /flux note/
    assert_select ".inspection-table", text: /12,3/
    assert_select ".inspection-table", text: /value with \"quotes\"/
    assert_select ".source-file-row-count", text: "3 total rows"
    assert_select "a[href='#{edit_dataset_source_file_field_mapping_path(dataset, source_file)}']", "Map fields"
    assert_equal contents, source_file.reload.file.download
  end

  test "maps inspected columns, leaves fields unmapped, updates mappings, and persists them" do
    dataset = Dataset.create!(name: "Field mapping catalog")
    contents = File.binread(Rails.root.join("test/fixtures/files/source_catalog.csv"))
    post dataset_source_files_path(dataset), params: {
      source_file: {
        file: fixture_file_upload("source_catalog.csv", "text/csv")
      }
    }
    source_file = SourceFile.order(:created_at).last
    right_ascension = NormalizedConcept.create!(
      key: "right_ascension_flow_test",
      name: "Right Ascension",
      description: "An angular coordinate.",
      expected_value_type: "number",
      canonical_unit: "degree"
    )
    declination = NormalizedConcept.create!(
      key: "declination_flow_test",
      name: "Declination",
      description: "A celestial latitude coordinate.",
      expected_value_type: "number",
      canonical_unit: "degree"
    )
    observation_time = NormalizedConcept.create!(
      key: "observation_time_flow_test",
      name: "Observation Time",
      description: "A time associated with an observation.",
      expected_value_type: "datetime"
    )

    get edit_dataset_source_file_field_mapping_path(dataset, source_file)

    assert_response :success
    assert_select "h1", "Map inspected fields"
    assert_select "a[href='#{dataset_source_file_import_preview_path(dataset, source_file)}']", "Preview import"
    assert_select ".mapping-table", text: /source_id/
    assert_select ".mapping-table", text: /A-1/
    assert_select "select#field-mapping-0 option", text: "Leave unmapped"

    patch dataset_source_file_field_mapping_path(dataset, source_file), params: {
      field_mappings: {
        "0" => right_ascension.id,
        "1" => "",
        "2" => declination.id
      }
    }

    assert_redirected_to edit_dataset_source_file_field_mapping_path(dataset, source_file)
    assert_equal 3, source_file.field_mappings.count
    assert_equal "mapped", source_file.field_mappings.find_by!(source_column_name: "source_id").status
    assert_equal right_ascension, source_file.field_mappings.find_by!(source_column_name: "source_id").normalized_concept
    assert source_file.field_mappings.find_by!(source_column_name: "flux note").unmapped?
    assert_equal declination, source_file.field_mappings.find_by!(source_column_name: "quality").normalized_concept

    patch dataset_source_file_field_mapping_path(dataset, source_file), params: {
      field_mappings: {
        "0" => "",
        "1" => observation_time.id,
        "2" => declination.id
      }
    }

    assert_redirected_to edit_dataset_source_file_field_mapping_path(dataset, source_file)
    assert source_file.field_mappings.find_by!(source_column_name: "source_id").reload.unmapped?
    assert_equal observation_time, source_file.field_mappings.find_by!(source_column_name: "flux note").reload.normalized_concept

    get edit_dataset_source_file_field_mapping_path(dataset, source_file)

    assert_response :success
    assert_select ".mapping-table", text: /Observation Time/
    assert_select "select#field-mapping-1 option[selected='selected']", text: "Observation Time"
    assert_equal contents, source_file.reload.file.download
  end

  test "previews mapped values without importing records" do
    dataset = Dataset.create!(name: "Import preview catalog")
    contents = File.binread(Rails.root.join("test/fixtures/files/source_catalog.csv"))
    post dataset_source_files_path(dataset), params: {
      source_file: {
        file: fixture_file_upload("source_catalog.csv", "text/csv")
      }
    }
    source_file = SourceFile.order(:created_at).last
    right_ascension = NormalizedConcept.create!(
      key: "right_ascension_preview_flow_test",
      name: "Right Ascension",
      description: "An angular coordinate.",
      expected_value_type: "number",
      canonical_unit: "degree"
    )

    get edit_dataset_source_file_field_mapping_path(dataset, source_file)
    assert_response :success

    patch dataset_source_file_field_mapping_path(dataset, source_file), params: {
      field_mappings: {
        "0" => right_ascension.id,
        "1" => "",
        "2" => ""
      }
    }

    assert_redirected_to edit_dataset_source_file_field_mapping_path(dataset, source_file)

    assert_no_difference([ "FieldMapping.count", "SourceFile.count", "NormalizedConcept.count" ]) do
      get dataset_source_file_import_preview_path(dataset, source_file)
    end

    assert_response :success
    assert_select "h1", /Import preview/
    assert_select ".preview-banner", text: /Dry run only/i
    assert_select ".preview-summary-list", text: /3/
    assert_select ".preview-values-table", text: /Right Ascension/
    assert_select ".preview-values-table", text: /flux note/
    assert_select ".preview-row", count: 3
    assert_equal contents, source_file.reload.file.download

    get dataset_source_file_import_preview_path(dataset, source_file)
    assert_response :success
    assert_select ".preview-values-table", text: /Right Ascension/
  end

  test "does not save mappings for duplicate source column names" do
    dataset = Dataset.create!(name: "Duplicate header catalog")
    post dataset_source_files_path(dataset), params: {
      source_file: {
        file: fixture_file_upload("duplicate_headers.csv", "text/csv")
      }
    }
    source_file = SourceFile.order(:created_at).last

    get edit_dataset_source_file_field_mapping_path(dataset, source_file)
    assert_response :success
    assert_select ".mapping-warnings", text: /share the same name/i

    patch dataset_source_file_field_mapping_path(dataset, source_file), params: {
      field_mappings: { "0" => "", "1" => "", "2" => "" }
    }

    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /unique source column names/i
    assert_empty source_file.field_mappings
  end

  test "rejects malformed field mapping parameters without raising" do
    dataset = Dataset.create!(name: "Malformed mapping catalog")
    post dataset_source_files_path(dataset), params: {
      source_file: {
        file: fixture_file_upload("source_catalog.csv", "text/csv")
      }
    }
    source_file = SourceFile.order(:created_at).last

    patch dataset_source_file_field_mapping_path(dataset, source_file), params: { field_mappings: "not-a-map" }

    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /parameters were invalid/i
    assert_empty source_file.field_mappings
  end

  test "rejects an unsupported upload and leaves the dataset without a source file" do
    dataset = Dataset.create!(name: "Upload validation dataset")

    assert_no_difference("SourceFile.count") do
      post dataset_source_files_path(dataset), params: {
        source_file: {
          file: fixture_file_upload("source_catalog.txt", "text/plain")
        }
      }
    end

    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /must have a \.csv filename|supported/i
  end
end
