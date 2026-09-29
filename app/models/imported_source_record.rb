require "digest"
require "json"

class ImportedSourceRecord < ApplicationRecord
  belongs_to :source_file
  belongs_to :import_run
  has_one :normalized_record, dependent: :destroy

  enum :status, { accepted: "accepted", rejected: "rejected" }, default: :accepted, validate: true

  validates :source_row_number, numericality: { only_integer: true, greater_than: 0 }
  validates :payload_hash, presence: true, format: { with: /\A\h{64}\z/ }
  validates :source_row_number, uniqueness: { scope: :source_file_id }
  validate :import_run_belongs_to_source_file

  before_validation :ensure_payload_defaults
  before_validation :refresh_payload_hash

  def self.payload_hash_for(payload)
    Digest::SHA256.hexdigest(JSON.generate(payload))
  end

  private

  def ensure_payload_defaults
    self.validation_issues = [] if validation_issues.nil?
  end

  def refresh_payload_hash
    self.payload_hash = self.class.payload_hash_for(original_row_payload) if original_row_payload.present?
  end

  def import_run_belongs_to_source_file
    return if import_run.blank? || source_file.blank?
    return if import_run.source_file_id == source_file_id

    errors.add(:import_run, "must belong to the same source file")
  end
end
