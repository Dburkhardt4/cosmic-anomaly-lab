require "test_helper"

class FieldMappingTest < ActiveSupport::TestCase
  setup do
    @source_file = build_source_file
    @concept = NormalizedConcept.create!(
      key: "right_ascension_test",
      name: "Right Ascension",
      description: "An angular coordinate.",
      expected_value_type: "number",
      canonical_unit: "degree"
    )
  end

  test "creates a mapped field mapping for a source column" do
    mapping = @source_file.field_mappings.create!(
      source_column_name: "ra_deg",
      normalized_concept: @concept,
      status: :mapped
    )

    assert_equal @source_file, mapping.source_file
    assert_equal @concept, mapping.normalized_concept
    assert mapping.mapped?
  end

  test "allows a source column to remain explicitly unmapped" do
    mapping = @source_file.field_mappings.create!(source_column_name: "unknown", status: :unmapped)

    assert mapping.unmapped?
    assert_nil mapping.normalized_concept
  end

  test "preserves a blank source column name from inspection" do
    mapping = @source_file.field_mappings.create!(source_column_name: "", status: :unmapped)

    assert_equal "", mapping.reload.source_column_name
    assert mapping.unmapped?
  end

  test "updates a mapping between concepts and unmapped" do
    mapping = @source_file.field_mappings.create!(
      source_column_name: "measurement",
      normalized_concept: @concept,
      status: :mapped
    )

    mapping.update!(normalized_concept: nil, status: :unmapped)
    assert mapping.reload.unmapped?

    mapping.update!(normalized_concept: @concept, status: :mapped)
    assert_equal @concept, mapping.reload.normalized_concept
    assert mapping.mapped?
  end

  test "requires a concept for mapped status" do
    mapping = @source_file.field_mappings.build(source_column_name: "ra_deg", status: :mapped)

    assert_not mapping.valid?
    assert_includes mapping.errors[:normalized_concept], "must be selected for a mapped field"
  end

  test "rejects a concept on an unmapped field" do
    mapping = @source_file.field_mappings.build(
      source_column_name: "ra_deg",
      normalized_concept: @concept,
      status: :unmapped
    )

    assert_not mapping.valid?
    assert_includes mapping.errors[:normalized_concept], "must be blank for an unmapped field"
  end

  test "prevents duplicate source columns within one source file" do
    @source_file.field_mappings.create!(source_column_name: "ra_deg", status: :unmapped)
    duplicate = @source_file.field_mappings.build(source_column_name: "ra_deg", status: :unmapped)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_column_name], "has already been taken"
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  private

  def build_source_file
    dataset = Dataset.create!(name: "Field mapping dataset")
    contents = "ra_deg,dec_deg\n12.3,-4.5\n"
    source_file = dataset.source_files.build(
      original_filename: "mapping.csv",
      sha256: Digest::SHA256.hexdigest(contents),
      byte_size: contents.bytesize
    )
    source_file.file.attach(io: StringIO.new(contents), filename: "mapping.csv", content_type: "text/csv")
    source_file.save!
    source_file
  end
end
