class Dataset < ApplicationRecord
  has_many :source_files, dependent: :destroy
  has_many :field_mappings, through: :source_files
  has_many :import_runs, through: :source_files
  has_many :imported_source_records, through: :source_files
  has_many :normalized_records, through: :source_files

  validates :name, presence: true
  validate :source_url_uses_http_scheme

  private

  def source_url_uses_http_scheme
    return if source_url.blank?

    uri = URI.parse(source_url)
    return if uri.is_a?(URI::HTTP) && uri.host.present?

    errors.add(:source_url, "must be a valid HTTP or HTTPS URL")
  rescue URI::InvalidURIError
    errors.add(:source_url, "must be a valid HTTP or HTTPS URL")
  end
end
