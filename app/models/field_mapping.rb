class FieldMapping < ApplicationRecord
  belongs_to :source_file
  belongs_to :normalized_concept, optional: true

  enum :status, { unmapped: "unmapped", mapped: "mapped" }, default: :unmapped, validate: true

  validates :source_column_name, uniqueness: { scope: :source_file_id }
  validates :status, presence: true
  validate :source_column_name_cannot_be_nil
  validate :mapped_status_requires_concept
  validate :unmapped_status_does_not_have_concept

  private

  def source_column_name_cannot_be_nil
    errors.add(:source_column_name, "can't be blank") if source_column_name.nil?
  end

  def mapped_status_requires_concept
    return unless mapped?
    return if normalized_concept.present?

    errors.add(:normalized_concept, "must be selected for a mapped field")
  end

  def unmapped_status_does_not_have_concept
    return unless unmapped?
    return if normalized_concept.blank?

    errors.add(:normalized_concept, "must be blank for an unmapped field")
  end
end
