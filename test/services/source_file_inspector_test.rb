require "test_helper"

class SourceFileInspectorTest < ActiveSupport::TestCase
  test "detects columns, counts rows, samples quoted values, and counts blanks" do
    contents = fixture_contents

    inspection = SourceFileInspector.new(StringIO.new(contents)).call

    assert_equal [ "source_id", "flux note", "quality" ], inspection[:columns]
    assert_equal 3, inspection[:row_count]
    assert_equal [
      [ "A-1", "12,3", "good" ],
      [ "A-2", nil, "unknown" ],
      [ "A-3", "value with \"quotes\"", "good" ]
    ], inspection[:sample_rows]
    assert_equal [ 0, 1, 0 ], inspection[:blank_counts]
  end

  test "does not rewrite the inspected source" do
    contents = fixture_contents
    io = StringIO.new(contents)

    SourceFileInspector.new(io).call

    assert_equal contents, io.string
  end

  test "rejects an empty source" do
    error = assert_raises(SourceFileInspector::Error) do
      SourceFileInspector.new(StringIO.new("")).call
    end

    assert_match(/empty|header/i, error.message)
  end

  test "rejects malformed CSV" do
    error = assert_raises(SourceFileInspector::Error) do
      SourceFileInspector.new(StringIO.new("source_id,note\nA-1,\"unterminated\n")).call
    end

    assert_match(/could not be inspected/i, error.message)
  end

  private

  def fixture_contents
    File.binread(Rails.root.join("test/fixtures/files/source_catalog.csv"))
  end
end
