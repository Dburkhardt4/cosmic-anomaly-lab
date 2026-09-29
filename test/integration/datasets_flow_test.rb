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
    assert_equal contents, source_file.reload.file.download
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
