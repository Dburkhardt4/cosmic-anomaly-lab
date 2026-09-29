require "test_helper"

class ImportRunTest < ActiveSupport::TestCase
  test "supports the import lifecycle and one run per source file" do
    source_file = build_source_file
    run = source_file.import_runs.create!(status: :pending, importer_version: "1")

    assert run.pending?
    run.update!(status: :importing, started_at: Time.current)
    assert run.importing?
    run.update!(status: :completed, completed_at: Time.current, rows_read: 2, rows_imported: 2)

    assert run.completed?
    assert run.finished?
    duplicate = source_file.import_runs.build(status: :pending, importer_version: "1")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_file_id], "has already been taken"
  end

  private

  def build_source_file
    dataset = Dataset.create!(name: "Import run dataset")
    contents = "source_id\nA-1\n"
    source_file = dataset.source_files.build(
      original_filename: "import-run.csv",
      sha256: Digest::SHA256.hexdigest(contents),
      byte_size: contents.bytesize
    )
    source_file.file.attach(io: StringIO.new(contents), filename: "import-run.csv", content_type: "text/csv")
    source_file.save!
    source_file
  end
end
