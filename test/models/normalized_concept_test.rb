require "test_helper"

class NormalizedConceptTest < ActiveSupport::TestCase
  test "requires a stable key, name, and description" do
    concept = NormalizedConcept.new

    assert_not concept.valid?
    assert_includes concept.errors[:key], "can't be blank"
    assert_includes concept.errors[:name], "can't be blank"
    assert_includes concept.errors[:description], "can't be blank"
  end

  test "requires a unique stable key" do
    attributes = {
      key: "right_ascension_test",
      name: "Right Ascension",
      description: "An angular coordinate."
    }
    NormalizedConcept.create!(attributes)

    duplicate = NormalizedConcept.new(attributes)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end

  test "allows optional value metadata" do
    concept = NormalizedConcept.new(
      key: "source_identifier",
      name: "Source Identifier",
      description: "An identifier preserved from a source.",
      expected_value_type: nil,
      canonical_unit: nil,
      notes: nil
    )

    assert concept.valid?
  end
end
