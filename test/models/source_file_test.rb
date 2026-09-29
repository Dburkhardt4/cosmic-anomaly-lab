require "test_helper"

class SourceFileTest < ActiveSupport::TestCase
  test "belongs to a dataset and requires an attached file" do
    dataset = Dataset.create!(name: "Source file dataset")
    source_file = dataset.source_files.build(
      original_filename: "catalog.csv",
      sha256: "a" * 64,
      byte_size: 12
    )

    assert_equal dataset, source_file.dataset
    assert_not source_file.valid?
    assert_includes source_file.errors[:file], "must be attached"
  end
end
