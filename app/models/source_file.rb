class SourceFile < ApplicationRecord
  belongs_to :dataset
  has_many :field_mappings, dependent: :destroy

  has_one_attached :file

  validates :original_filename, presence: true
  validates :sha256, presence: true, format: { with: /\A\h{64}\z/ }
  validates :byte_size, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate :file_must_be_attached

  private

  def file_must_be_attached
    errors.add(:file, "must be attached") unless file.attached?
  end
end
