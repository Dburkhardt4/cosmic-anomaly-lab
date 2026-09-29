require "test_helper"

class SourceFileUploaderTest < ActiveSupport::TestCase
  setup do
    @dataset = Dataset.create!(name: "Uploader dataset")
  end

  test "stores a source file with provenance metadata and Active Storage attachment" do
    contents = fixture_contents
    upload = Rack::Test::UploadedFile.new(fixture_path, "text/csv")

    source_file = SourceFileUploader.call(dataset: @dataset, upload: upload)

    assert_equal @dataset, source_file.dataset
    assert_equal "source_catalog.csv", source_file.original_filename
    assert_equal contents.bytesize, source_file.byte_size
    assert_equal Digest::SHA256.hexdigest(contents), source_file.sha256
    assert source_file.file.attached?
    assert_equal contents, source_file.file.download
  end

  test "rejects an unsupported file type before creating a source file" do
    upload = Rack::Test::UploadedFile.new(fixture_path("source_catalog.txt"), "text/plain")

    assert_no_difference("SourceFile.count") do
      error = assert_raises(SourceFileUploader::Error) do
        SourceFileUploader.call(dataset: @dataset, upload: upload)
      end
      assert_match(/\.csv|supported/i, error.message)
    end
  end

  test "rejects an empty CSV before creating a source file" do
    Tempfile.create([ "empty-source", ".csv" ]) do |file|
      upload = Rack::Test::UploadedFile.new(file.path, "text/csv")

      assert_no_difference("SourceFile.count") do
        error = assert_raises(SourceFileUploader::Error) do
          SourceFileUploader.call(dataset: @dataset, upload: upload)
        end
        assert_match(/empty/i, error.message)
      end
    end
  end

  test "rejects malformed CSV before creating a source file" do
    upload = Rack::Test::UploadedFile.new(fixture_path("malformed_source.csv"), "text/csv")

    assert_no_difference("SourceFile.count") do
      error = assert_raises(SourceFileUploader::Error) do
        SourceFileUploader.call(dataset: @dataset, upload: upload)
      end
      assert_match(/could not be inspected/i, error.message)
    end
  end

  private

  def fixture_path(filename = "source_catalog.csv")
    Rails.root.join("test/fixtures/files", filename).to_s
  end

  def fixture_contents
    File.binread(fixture_path)
  end
end
