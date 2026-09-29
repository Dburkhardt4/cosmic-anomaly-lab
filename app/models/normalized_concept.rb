class NormalizedConcept < ApplicationRecord
  has_many :field_mappings, dependent: :restrict_with_error

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :description, presence: true
end
