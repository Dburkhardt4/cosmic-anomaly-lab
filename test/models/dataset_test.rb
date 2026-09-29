require "test_helper"

class DatasetTest < ActiveSupport::TestCase
  test "requires a name" do
    dataset = Dataset.new

    assert_not dataset.valid?
    assert_includes dataset.errors[:name], "can't be blank"
  end

  test "accepts source metadata" do
    dataset = Dataset.new(
      name: "Processed Survey Catalog",
      source_organization: "Example Observatory",
      source_url: "https://example.test/catalog",
      version: "DR1",
      description: "A processed source catalog."
    )

    assert dataset.valid?
  end

  test "source URL must use HTTP or HTTPS" do
    dataset = Dataset.new(name: "Unsafe source", source_url: "javascript:alert('xss')")

    assert_not dataset.valid?
    assert_includes dataset.errors[:source_url], "must be a valid HTTP or HTTPS URL"
  end
end
