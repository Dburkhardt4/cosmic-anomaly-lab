class ImportRun < ApplicationRecord
  belongs_to :source_file
  has_many :imported_source_records, dependent: :destroy

  enum :status, {
    pending: "pending",
    importing: "importing",
    completed: "completed",
    failed: "failed"
  }, validate: true

  validates :source_file_id, uniqueness: true
  validates :importer_version, presence: true
  validates :source_sha256, format: { with: /\A\h{64}\z/ }, allow_blank: true
  validates :source_byte_size, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :rows_read, :rows_imported, :rows_rejected, :warning_count, :error_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :ensure_validation_issues

  def finished?
    completed? || failed?
  end

  private

  def ensure_validation_issues
    self.validation_issues = [] if validation_issues.nil?
  end
end
