class NormalizedRecord < ApplicationRecord
  belongs_to :imported_source_record
  has_one :source_file, through: :imported_source_record

  validates :record_type, presence: true
  validates :imported_source_record_id, uniqueness: true
  validate :source_record_must_be_accepted

  before_validation :ensure_payload_defaults

  private

  def ensure_payload_defaults
    self.normalized_values = [] if normalized_values.nil?
    self.unmapped_values = [] if unmapped_values.nil?
    self.field_mapping_snapshot = [] if field_mapping_snapshot.nil?
  end

  def source_record_must_be_accepted
    return if imported_source_record.blank? || imported_source_record.accepted?

    errors.add(:imported_source_record, "must be accepted before a normalized record is created")
  end
end
